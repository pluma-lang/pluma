package tramezzo

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

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

Value :: union {
	bool,
	i64,
	f64,
	string,
	^List,
	^Map,
}

scopes:        [dynamic]map[string]Value
functions:     map[string]^Function_Stmt
return_value:  Value

Flow :: enum {
	Normal,
	Return,
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

get_var :: proc(name: string, line: int) -> Value {
	#reverse for scope in scopes {
		if value, ok := scope[name]; ok {
			return value
		}
	}
	runtime_error(line, "undefined variable: %s", name)
}

set_var :: proc(name: string, value: Value) {
	scopes[len(scopes) - 1][name] = value
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
	case nil:
		return "null"
	}
	return "null"
}

truthy :: proc(v: Value) -> bool {
	switch x in v {
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
	switch x in a {
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
				result := new(List)
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
	right := eval(n.right)

	#partial switch n.op {
	case .Plus, .Minus, .Star, .Slash, .Percent, .Caret:
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
	fn, found := functions[n.name]
	if !found {
		runtime_error(n.line, "undefined function: %s", n.name)
	}

	if len(n.args) != len(fn.params) {
		runtime_error(
			n.line,
			"%s expects %d arguments, but %d were given",
			n.name,
			len(fn.params),
			len(n.args),
		)
	}

	values := make([dynamic]Value, 0, len(n.args))
	defer delete(values)
	for arg in n.args {
		append(&values, eval(arg))
	}

	create_scope()

	for param, i in fn.params {
		set_var(param, values[i])
	}

	result: Value = nil
	if exec_block(fn.body) == .Return {
		result = return_value
		return_value = nil
	}

	destroy_scope()

	return result
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
		list := new(List)
		for element in n.elements {
			append(&list.items, eval(element))
		}
		return list
	case ^Map_Lit:
		m := new(Map)
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
	case ^Length_Expr:
		v := eval(n.value)
		#partial switch x in v {
		case string: return i64(len(x))
		case ^List:  return i64(len(x.items))
		case ^Map:   return i64(len(x.entries))
		}
		runtime_error(n.line, "length needs a list or a string")
	}
	return nil
}

exec_block :: proc(statements: [dynamic]Stmt) -> Flow {
	for statement in statements {
		if exec(statement) == .Return {
			return .Return
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

	case ^If_Stmt:
		if truthy(eval(n.condition)) {
			return exec_block(n.body)
		} else if len(n.otherwise) > 0 {
			return exec_block(n.otherwise)
		}

	case ^While_Stmt:
		for truthy(eval(n.condition)) {
			if exec_block(n.body) == .Return {
				return .Return
			}
		}

	case ^Foreach_Stmt:
		sequence := get_var(n.list_name, n.line)
		#partial switch s in sequence {
		case ^List:
			for i := 0; i < len(s.items); i += 1 {
				set_var(n.var_name, s.items[i])
				if exec_block(n.body) == .Return {
					return .Return
				}
			}
		case ^Map:
			for key in s.order {
				set_var(n.var_name, key)
				if exec_block(n.body) == .Return {
					return .Return
				}
			}
		case:
			runtime_error(n.line, "'%s' is not a list or a map", n.list_name)
		}

	case ^Return_Stmt:
		return_value = eval(n.value)
		return .Return

	case ^Function_Stmt:
		functions[n.name] = n

	case ^Call_Stmt:
		_ = eval_call(n.call)
	}

	return .Normal
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: tramezzo <file.tmz>")
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
