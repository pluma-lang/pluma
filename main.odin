package tramezzo

import "core:sort"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:unicode/utf8"

List :: struct {
	items: [dynamic]Value,
}

Map :: struct {
	entries: map[string]Value,
	order:   [dynamic]string,
}

map_set :: proc(m: ^Map, key: string, value: Value) {
	if key not_in m.entries {
		append(&m.order, key)
	}
	m.entries[key] = value
}

Function_Value :: struct {
    declaration: ^Function_Stmt,
}

GC_Object_Kind :: enum {
    List,
    Map,
    Function,
}

GC_Object :: struct {
    ptr: rawptr,
    kind: GC_Object_Kind,
    marked: bool,
}

gc_objects: [dynamic]GC_Object
gc_roots: [dynamic]Value
gc_allocations: int
gc_threshold: int = 1024

Value :: union {
	bool,
	i64,
	f64,
	string,
	^List,
	^Map,
	^Function_Value
}

scopes:        [dynamic]map[string]Value
frame_base:    int // index of the first scope that belongs to the running function call
functions:     map[string]^Function_Stmt
return_value:  Value

Flow :: enum {
	Normal,
	Return,
	Break,
	Continue
}

gc_new_list :: proc() -> ^List {
    obj := new(List)

    append(&gc_objects, GC_Object{
        ptr = obj,
        kind = .List,
    })

    gc_allocations += 1
    return obj
}

gc_new_map :: proc() -> ^Map {
    obj := new(Map)

    append(&gc_objects, GC_Object{
        ptr = obj,
        kind = .Map,
    })

    gc_allocations += 1
    return obj
}

gc_new_function :: proc() -> ^Function_Value {
    obj := new(Function_Value)

    append(&gc_objects, GC_Object{
        ptr = obj,
        kind = .Function,
    })

    gc_allocations += 1
    return obj
}

gc_mark_value :: proc(value: Value) {
	#partial switch v in value {
	case ^List:
		gc_mark_object(rawptr(v))

	case ^Map:
		gc_mark_object(rawptr(v))

	case ^Function_Value:
		gc_mark_object(rawptr(v))
	}
}

gc_mark_object :: proc(ptr: rawptr) {
	for i in 0 ..< len(gc_objects) {
		obj := &gc_objects[i]

		if obj.ptr != ptr {
			continue
		}

		if obj.marked {
			return
		}

		obj.marked = true

		#partial switch obj.kind {
		case .List:
			list := cast(^List)ptr

			for item in list.items {
				gc_mark_value(item)
			}

		case .Map:
			m := cast(^Map)ptr

			for _, value in m.entries {
				gc_mark_value(value)
			}
		}

		return
	}
}

gc_mark_roots :: proc() {
    for scope in scopes {
        for _, value in scope {
            gc_mark_value(value)
        }
    }

    gc_mark_value(return_value)

    for value in gc_roots {
        gc_mark_value(value)
    }
}

gc_push_root :: proc(value: Value) {
    append(&gc_roots, value)
}

gc_pop_root :: proc() {
    if len(gc_roots) > 0 {
        _ = pop(&gc_roots)
    }
}

gc_root_checkpoint :: proc() -> int {
	return len(gc_roots)
}

gc_restore_roots :: proc(checkpoint: int) {
	for len(gc_roots) > checkpoint {
		_ = pop(&gc_roots)
	}
}

gc_destroy_object :: proc(obj: GC_Object) {
    switch obj.kind {
    case .List:
        list := cast(^List)obj.ptr
        delete(list.items)
        free(list)

    case .Map:
        m := cast(^Map)obj.ptr
        delete(m.entries)
        delete(m.order)
        free(m)

    case .Function:
        fn := cast(^Function_Value)obj.ptr
        free(fn)
    }
}

gc_collect :: proc() {
    gc_mark_roots()

    i := 0

    for i < len(gc_objects) {
        obj := gc_objects[i]

        if obj.marked {
            gc_objects[i].marked = false
            i += 1
        } else {
            gc_destroy_object(obj)
            unordered_remove(&gc_objects, i)
        }
    }
}

gc_maybe_collect :: proc() {
    if gc_allocations >= gc_threshold {
        gc_collect()

        gc_allocations = 0
        gc_threshold = max(1024, len(gc_objects) * 2)
    }
}

runtime_error :: proc(line: int, format: string, args: ..any) -> ! {
	if line > 0 {
		fmt.eprintf("RuntimeError (line %d): ", line)
	} else {
		fmt.eprintf("RuntimeError: ")
	}
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

create_scope :: proc() {
	append(&scopes, make(map[string]Value))
}

destroy_scope :: proc() {
	if len(scopes) > 1 {
		scope := pop(&scopes)
		delete(scope)
	}
}

copy_value :: proc(v: Value, seen: ^map[rawptr]Value) -> Value {
	#partial switch x in v {
	case ^List:
		if existing, ok := seen[rawptr(x)]; ok {
			return existing
		}
		new_list := gc_new_list()
		seen[rawptr(x)] = new_list
		for item in x.items {
			append(&new_list.items, copy_value(item, seen))
		}
		return new_list

	case ^Map:
		if existing, ok := seen[rawptr(x)]; ok {
			return existing
		}
		new_map := gc_new_map()
		seen[rawptr(x)] = new_map
		for key in x.order {
			map_set(new_map, key, copy_value(x.entries[key], seen))
		}
		return new_map
	}

	return v
}

get_var :: proc(name: string, line: int) -> Value {
	#reverse for scope in scopes[frame_base:] {
		if value, ok := scope[name]; ok {
			return value
		}
	}
	if frame_base > 0 {
		if value, ok := scopes[0][name]; ok {
			return value
		}
	}
	runtime_error(line, "undefined variable: %s", name)
}

set_var :: proc(name: string, value: Value) {
	scopes[len(scopes) - 1][name] = value
}

assign_var :: proc(name: string, value: Value, line: int) {
	for i := len(scopes) - 1; i >= frame_base; i -= 1 {
		if name in scopes[i] {
			scopes[i][name] = value
			return
		}
	}
	if frame_base > 0 {
		if name in scopes[0] {
			scopes[0][name] = value
			return
		}
	}
	runtime_error(line, "undefined variable: %s (declare it with 'let' first)", name)
}

format_value :: proc(v: Value) -> string {
	switch x in v {
	case bool:
		return "true" if x else "false"
	case i64:
		return fmt.aprintf("%d", x)
	case f64:
		if x == math.floor(x) && abs(x) < 1e15 {
			return fmt.aprintf("%d", i64(x))
		}
		return fmt.aprintf("%v", x)
	case string:
		return x
	case ^List:
		b := strings.builder_make()
		strings.write_byte(&b, '[')
		for item, i in x.items {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			strings.write_string(&b, format_value(item))
		}
		strings.write_byte(&b, ']')
		return strings.to_string(b)
	case ^Map:
		b := strings.builder_make()
		strings.write_byte(&b, '{')
		first := true
		for key in x.order {
			if !first {
				strings.write_string(&b, ", ")
			}
			first = false
			strings.write_string(&b, key)
			strings.write_string(&b, ": ")
			strings.write_string(&b, format_value(x.entries[key]))
		}
		strings.write_byte(&b, '}')
		return strings.to_string(b)
	case ^Function_Value:
		return "<function>"
	case nil:
		return ""
	}
	return "null"
}

truthy :: proc(v: Value) -> bool {
	#partial switch x in v {
	case bool:   return x
	case i64:    return x != 0
	case f64:    return x != 0
	case string: return len(x) > 0
	case ^List:  return len(x.items) > 0
	case ^Map:   return len(x.entries) > 0
	case nil:    return false
	}
	return false
}

as_f64 :: proc(v: Value) -> (f64, bool) {
	#partial switch x in v {
	case i64: return f64(x), true
	case f64: return x, true
	}
	return 0, false
}

values_equal :: proc(a, b: Value) -> bool {
	#partial switch x in a {
	case nil:
		return b == nil
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case i64:
		#partial switch y in b {
		case i64: return x == y
		case f64: return f64(x) == y
		}
		return false
	case f64:
		#partial switch y in b {
		case i64: return x == f64(y)
		case f64: return x == y
		}
		return false
	case string:
		y, ok := b.(string)
		return ok && x == y
	case ^List:
		y, ok := b.(^List)
		if !ok || len(x.items) != len(y.items) {
			return false
		}
		for i in 0 ..< len(x.items) {
			if !values_equal(x.items[i], y.items[i]) {
				return false
			}
		}
		return true
	case ^Map:
		y, ok := b.(^Map)
		if !ok || len(x.entries) != len(y.entries) {
			return false
		}
		for key, value in x.entries {
			other, found := y.entries[key]
			if !found || !values_equal(value, other) {
				return false
			}
		}
		return true
	}
	return false
}

compare_values :: proc(a, b: Value, line: int) -> int {
	if x, ok := a.(i64); ok {
		if y, ok2 := b.(i64); ok2 {
			return -1 if x < y else (1 if x > y else 0)
		}
	}

	fx, ok_x := as_f64(a)
	fy, ok_y := as_f64(b)
	if ok_x && ok_y {
		return -1 if fx < fy else (1 if fx > fy else 0)
	}

	sx, ok_sx := a.(string)
	sy, ok_sy := b.(string)
	if ok_sx && ok_sy {
		return strings.compare(sx, sy)
	}

	runtime_error(line, "these values cannot be compared")
}

int_arithmetic :: proc(op: Token_Kind, a, b: i64, line: int) -> Value {
	#partial switch op {
	case .Plus:  return a + b
	case .Minus: return a - b
	case .Star:  return a * b
	case .Slash:
		if b == 0 {
			runtime_error(line, "division by zero")
		}
		return f64(a) / f64(b)
	case .SlashSlash:
		if b == 0 {
			runtime_error(line, "division by zero")
		}
		return a / b
	case .Percent:
		if b == 0 {
			runtime_error(line, "modulo by zero")
		}
		m := a % b
		if m != 0 && (m < 0) != (b < 0) {
			m += b
		}
		return m
	case .Caret:
		if b < 0 {
			return math.pow(f64(a), f64(b))
		}
		result: i64 = 1
		base := a
		e := b
		for e > 0 {
			if e & 1 == 1 {
				result *= base
			}
			base *= base
			e >>= 1
		}
		return result
	}
	return nil
}

arithmetic :: proc(op: Token_Kind, a, b: Value, line: int) -> Value {
	if op == .Plus {
		if sa, ok := a.(string); ok {
			if sb, ok2 := b.(string); ok2 {
				return strings.concatenate({sa, sb})
			}
		}
		if la, ok := a.(^List); ok {
			if lb, ok2 := b.(^List); ok2 {
				result := gc_new_list()
				append(&result.items, ..la.items[:])
				append(&result.items, ..lb.items[:])
				return result
			}
		}
	}

	if ia, ok := a.(i64); ok {
		if ib, ok2 := b.(i64); ok2 {
			return int_arithmetic(op, ia, ib, line)
		}
	}

	fa, ok_a := as_f64(a)
	fb, ok_b := as_f64(b)
	if !ok_a || !ok_b {
		runtime_error(line, "invalid operand types for arithmetic")
	}

	#partial switch op {
	case .Plus:  return fa + fb
	case .Minus: return fa - fb
	case .Star:  return fa * fb
	case .Slash:
		if fb == 0 {
			runtime_error(line, "division by zero")
		}
		return fa / fb
	case .Percent:
		if fb == 0 {
			runtime_error(line, "modulo by zero")
		}
		return fa - math.floor(fa / fb) * fb
	case .Caret:
		return math.pow(fa, fb)
	}
	return nil
}

read_line :: proc() -> string {
	buf: [dynamic]byte
	one: [1]byte

	for {
		n, err := os.read(os.stdin, one[:])
		if err != nil || n <= 0 {
			break
		}
		if one[0] == '\n' {
			break
		}
		append(&buf, one[0])
	}

	line := string(buf[:])
	return strings.trim_right(line, "\r")
}

eval_convert :: proc(n: ^Convert_Expr) -> Value {
	v := eval(n.value)

	if n.target == .To_String {
		return format_value(v)
	}

	#partial switch x in v {
	case i64, f64:
		return v
	case bool:
		return i64(1) if x else i64(0)
	case string:
		s := strings.trim_space(x)
		if i, ok := strconv.parse_i64(s); ok {
			return i
		}
		if f, ok := strconv.parse_f64(s); ok {
			return f
		}
		runtime_error(n.line, "cannot convert \"%s\" to number", x)
	}

	runtime_error(n.line, "this value cannot be converted to number")
}

eval_binary :: proc(n: ^Binary) -> Value {
	if n.op == .And {
		left := eval(n.left)
		if !truthy(left) {
			return left
		}
		return eval(n.right)
	}
	if n.op == .Or {
		left := eval(n.left)
		if truthy(left) {
			return left
		}
		return eval(n.right)
	}

	left := eval(n.left)

	root_base := gc_root_checkpoint()
	gc_push_root(left)

	right := eval(n.right)
	gc_restore_roots(root_base)

	#partial switch n.op {
	case .Plus, .Minus, .Star, .Slash, .SlashSlash, .Percent, .Caret:
		return arithmetic(n.op, left, right, n.line)
	case .Greater:    return compare_values(left, right, n.line) > 0
	case .Less:       return compare_values(left, right, n.line) < 0
	case .Greater_Eq: return compare_values(left, right, n.line) >= 0
	case .Less_Eq:    return compare_values(left, right, n.line) <= 0
	case .Eq_Eq:      return values_equal(left, right)
	case .Not_Eq:     return !values_equal(left, right)
	}

	runtime_error(n.line, "unknown operator")
}

resolve_index :: proc(index_value: Value, length: int, line: int) -> i64 {
	idx, ok := index_value.(i64)
	if !ok {
		runtime_error(line, "the index must be an integer")
	}

	i := idx if idx >= 0 else idx + i64(length)
	if i < 0 || i >= i64(length) {
		runtime_error(line, "index out of range: %d", idx)
	}
	return i
}

eval_access :: proc(n: ^Access) -> Value {
	index_value := eval(n.index)
	target := eval(n.target)

	#partial switch t in target {
	case ^Map:
		key, is_string := index_value.(string)
		if !is_string {
			runtime_error(n.line, "map keys must be strings")
		}
		value, found := t.entries[key]
		if !found {
			runtime_error(n.line, "key not found: %s", key)
		}
		return value

	case ^List:
		i := resolve_index(index_value, len(t.items), n.line)
		return t.items[i]

	case string:
		i := resolve_index(index_value, len(t), n.line)
		return t[i:i + 1]
	}

	runtime_error(n.line, "this value cannot be indexed")
}

eval_call :: proc(n: ^Call) -> Value {
	callee := eval(n.callee)
	fn_value, ok := callee.(^Function_Value)

	if !ok {
		runtime_error(n.line, "this value is not callable")
	}

	root_base := gc_root_checkpoint()
	defer gc_restore_roots(root_base)

	gc_push_root(fn_value)

	fn := fn_value.declaration

	if len(n.arguments) != len(fn.params) {
		runtime_error(
			n.line,
			"function expects %d arguments, but %d were given",
			len(fn.params),
			len(n.arguments),
		)
	}

	values := make([dynamic]Value, 0, len(n.arguments))
	defer delete(values)

	for arg in n.arguments {
		value := eval(arg)

		append(&values, value)
		gc_push_root(value)
	}

	saved_frame_base := frame_base
	create_scope()
	frame_base = len(scopes) - 1
	defer {
		frame_base = saved_frame_base
		destroy_scope()
	}

	for param, i in fn.params {
		set_var(param, values[i])
	}

	result: Value = nil

	if exec_block(fn.body) == .Return {
		result = return_value
		return_value = nil
	}

	return result
}

eval_extreme :: proc(value: Value, line: int, find_minimum: bool) -> Value {
	list, ok := value.(^List)

	if !ok {
		runtime_error(line, "minimum and maximum need a list")
	}

	if len(list.items) == 0 {
		runtime_error(line, "cannot find minimum or maximum of an empty list")
	}

	result := list.items[0]

	for i in 1 ..< len(list.items) {
		current := list.items[i]
		comparison := compare_values(current, result, line)

		if (find_minimum && comparison < 0) ||
		   (!find_minimum && comparison > 0) {
			result = current
		}
	}

	return result
}

// Normalizes slice bounds: negatives count from the end, then clamp to [0, length].
slice_bounds :: proc(from, to: i64, length: int) -> (lo, hi: int) {
	l := from if from >= 0 else from + i64(length)
	h := to   if to   >= 0 else to   + i64(length)
	l = clamp(l, 0, i64(length))
	h = clamp(h, 0, i64(length))
	if h < l {
		h = l
	}
	return int(l), int(h)
}

// Byte offset of the n-th rune, so UTF-8 strings slice by character, like `length` counts them.
rune_to_byte_offset :: proc(s: string, rune_index: int) -> int {
	count := 0
	i := 0
	for i < len(s) {
		if count == rune_index {
			return i
		}
		_, width := utf8.decode_rune_in_string(s[i:])
		i += width
		count += 1
	}
	return len(s)
}

eval :: proc(e: Expr) -> Value {
	switch n in e {
	case nil:
		return nil
	case ^Int_Lit:
		return n.value
	case ^Float_Lit:
		return n.value
	case ^String_Lit:
		return n.value
	case ^Bool_Lit:
		return n.value
	case ^Null_Lit:
		return nil
	case ^Var:
		return get_var(n.name, n.line)
	case ^Convert_Expr:
		return eval_convert(n)
	case ^Unary:
		v := eval(n.operand)
		if n.op == .Minus {
			#partial switch x in v {
			case i64: return -x
			case f64: return -x
			}
			runtime_error(n.line, "this value cannot be negated")
		}
		return !truthy(v)
	case ^Binary:
		return eval_binary(n)
	case ^List_Lit:
	    list := gc_new_list()

	    gc_push_root(list)
	    defer gc_pop_root()

	    for element in n.elements {
	        append(&list.items, eval(element))
	    }

	    return list
	case ^Copy_Expr:
		seen := make(map[rawptr]Value)
		defer delete(seen)
		return copy_value(eval(n.value), &seen)
	case ^Sort_Expr:
		value := eval(n.value).(^List)

		sort.quick_sort_proc(
			value.items[:],
			proc(a, b: Value) -> int {
				return compare_values(a, b, 0)
			},
		)
		return value
	case ^Map_Lit:
	    m := gc_new_map()

	    gc_push_root(m)
	    defer gc_pop_root()

	    for key_expr, i in n.keys {
	        key, ok := eval(key_expr).(string)

	        if !ok {
	            runtime_error(n.line, "map keys must be strings")
	        }

	        map_set(m, key, eval(n.values[i]))
	    }

	    return m
	case ^Access:
		return eval_access(n)
	case ^Call:
		return eval_call(n)
	case ^Input_Expr:
		if n.prompt != nil {
			fmt.print(format_value(eval(n.prompt)))
		}
		return read_line()
	case ^Range_Expr:
		from, ok1 := eval(n.from).(i64)
		to, ok2 := eval(n.to).(i64)

		if !ok1 || !ok2 {
    		runtime_error(n.line, "range boundaries must be integers")
		}

		result := gc_new_list()

     	for i := from; i < to; i += 1 {
      		append(&result.items, Value(i))
      	}

        return result
	case ^Slice_Expr:
		to_slice := eval(n.elements)

		root_base := gc_root_checkpoint()
		gc_push_root(to_slice)

		from, ok1 := eval(n.from).(i64)
		to, ok2 := eval(n.to).(i64)

		gc_restore_roots(root_base)

		if !ok1 || !ok2 {
			runtime_error(n.line, "slice boundaries must be integers")
		}

		#partial switch t in to_slice {
		case string:
			lo, hi := slice_bounds(from, to, utf8.rune_count_in_string(t))
			return t[rune_to_byte_offset(t, lo):rune_to_byte_offset(t, hi)]

		case ^List:
			lo, hi := slice_bounds(from, to, len(t.items))
			result := gc_new_list()
			append(&result.items, ..t.items[lo:hi])
			return result
		}

		runtime_error(n.line, "slice needs a list or a string")

	case ^Length_Expr:
		v := eval(n.value)
		#partial switch x in v {
		case string: return i64(utf8.rune_count_in_string(x))
		case ^List:  return i64(len(x.items))
		case ^Map:   return i64(len(x.entries))
		}
		runtime_error(n.line, "length needs a list or a string")
	case ^Minimum_Expr:
		return eval_extreme(eval(n.value), n.line, true)

	case ^Maximum_Expr:
		return eval_extreme(eval(n.value), n.line, false)
	}

	return nil
}

exec_assign :: proc(n: ^Assign_Stmt) {
	value := eval(n.value)

	root_base := gc_root_checkpoint()
	gc_push_root(value)
	defer gc_restore_roots(root_base)

	#partial switch t in n.target {
	case ^Var:
		assign_var(t.name, value, t.line)

	case ^Access:
		index_value := eval(t.index)
		container := eval(t.target)

		#partial switch c in container {
		case ^Map:
			key, is_string := index_value.(string)
			if !is_string {
				runtime_error(t.line, "map keys must be strings")
			}
			map_set(c, key, value)

		case ^List:
			i := resolve_index(index_value, len(c.items), t.line)
			c.items[i] = value

		case string:
			runtime_error(t.line, "strings are immutable: cannot assign to one of their characters")

		case:
			runtime_error(t.line, "this value does not support assignment")
		}
	}
}

exec_block :: proc(statements: [dynamic]Stmt) -> Flow {
    for statement in statements {
        flow := exec(statement)

        gc_maybe_collect()

        if flow != .Normal {
            return flow
        }
    }

    return .Normal
}

exec :: proc(s: Stmt) -> Flow {
	switch n in s {
	case nil:
		return .Normal

	case ^Let_Stmt:
		set_var(n.name, eval(n.value))

	case ^Print_Stmt:
		fmt.println(format_value(eval(n.value)))

	case ^Append_Stmt:
	    l := eval(n.list)

	    gc_push_root(l)
	    defer gc_pop_root()

	    elem := eval(n.to_append)

	    list_ptr, ok := l.(^List)

	    if !ok {
	        runtime_error(n.line, "append target must be a list")
	    }

	    append(&list_ptr.items, elem)

	case ^If_Stmt:
		if truthy(eval(n.condition)) {
			return exec_block(n.body)
		} else if len(n.otherwise) > 0 {
			return exec_block(n.otherwise)
		}

	case ^While_Stmt:
	    for truthy(eval(n.condition)) {
	        flow := exec_block(n.body)

	        if flow == .Return {
	            return .Return
	        }
	        if flow == .Break {
	            break
	        }
	        if flow == .Continue {
	            continue
	        }
	    }

	case ^Foreach_Stmt:
		sequence := eval(n.sequence)

		gc_push_root(sequence)
		defer gc_pop_root()
		#partial switch s in sequence {
		case ^List:
		    for i := 0; i < len(s.items); i += 1 {
		        set_var(n.var_name, s.items[i])

		        flow := exec_block(n.body)

		        if flow == .Return {
		            return .Return
		        }
		        if flow == .Break {
		            break
		        }
		        if flow == .Continue {
		            continue
		        }
		    }
		case ^Map:
		    for key in s.order {
		        set_var(n.var_name, key)

		        flow := exec_block(n.body)

		        if flow == .Return {
		            return .Return
		        }
		        if flow == .Break {
		            break
		        }
		        if flow == .Continue {
		            continue
		        }
		    }
		case string:
		    i := 0
		    for i < len(s) {
		        _, width := utf8.decode_rune_in_string(s[i:])
		        set_var(n.var_name, s[i:i + width])
		        i += width

		        flow := exec_block(n.body)

		        if flow == .Return {
		            return .Return
		        }
		        if flow == .Break {
		            break
		        }
		        if flow == .Continue {
		            continue
		        }
		    }
		case:
    		runtime_error(n.line, "this value is not iterable")
		}

	case ^Break_Stmt:
    	return .Break

	case ^Continue_Stmt:
    	return .Continue

	case ^Return_Stmt:
		return_value = eval(n.value)
		return .Return

	case ^Function_Stmt:
	    fn := gc_new_function()
	    fn.declaration = n
	    set_var(n.name, fn)

	case ^Call_Stmt:
		_ = eval_call(n.call)

	case ^Assign_Stmt:
		exec_assign(n)
	}

	return .Normal
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: pluma <file.pluma>")
		os.exit(1)
	}

	path := os.args[1]
	if !strings.has_suffix(path, ".pluma") {
		fmt.eprintfln("invalid file name %s: files must end in .pluma", path)
		os.exit(1)
	}

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("cannot read %s", path)
		os.exit(1)
	}

	create_scope()

	parser := Parser{tokens = tokenize_source(string(data))}
	program := parse_program(&parser)

	if exec_block(program) == .Return {
		runtime_error(0, "'return' outside a function")
	}
}
