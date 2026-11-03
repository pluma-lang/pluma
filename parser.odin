package tramezzo

import "core:rexcode/isa/ppc_vle/tablegen/generated"
Expr :: union {
	^Int_Lit,
	^Float_Lit,
	^String_Lit,
	^Bool_Lit,
	^Null_Lit,
	^Var,
	^Unary,
	^Binary,
	^List_Lit,
	^Map_Lit,
	^Access,
	^Call,
	^Input_Expr,
	^Length_Expr,
}

Int_Lit    :: struct { value: i64 }
Float_Lit  :: struct { value: f64 }
String_Lit :: struct { value: string }
Bool_Lit   :: struct { value: bool }
Null_Lit   :: struct { line: int }
Var        :: struct { name: string, line: int }
Unary      :: struct { op: Token_Kind, operand: Expr, line: int }
Binary     :: struct { op: Token_Kind, left, right: Expr, line: int }
List_Lit   :: struct { elements: [dynamic]Expr }
Map_Lit    :: struct { keys, values: [dynamic]Expr, line: int }
Access     :: struct { index, target: Expr, line: int }
Call       :: struct { callee: Expr, arguments: [dynamic]Expr, line: int }
Input_Expr :: struct { prompt: Expr }
Length_Expr :: struct { value: Expr, line: int }

Stmt :: union {
	^Let_Stmt,
	^Print_Stmt,
	^If_Stmt,
	^Foreach_Stmt,
	^While_Stmt,
	^Return_Stmt,
	^Function_Stmt,
	^Call_Stmt,
}

Let_Stmt      :: struct { name: string, value: Expr }
Print_Stmt    :: struct { value: Expr }
If_Stmt       :: struct { condition: Expr, body: [dynamic]Stmt, otherwise: [dynamic]Stmt }
Foreach_Stmt  :: struct { var_name, list_name: string, body: [dynamic]Stmt, line: int }
While_Stmt    :: struct { condition: Expr, body: [dynamic]Stmt }
Return_Stmt   :: struct { value: Expr }
Function_Stmt :: struct { name: string, params: [dynamic]string, body: [dynamic]Stmt }
Call_Stmt     :: struct { call: ^Call }

Parser :: struct {
	tokens: [dynamic]Token,
	pos:    int,
}

current :: proc(p: ^Parser) -> Token {
	if p.pos >= len(p.tokens) {
		return p.tokens[len(p.tokens) - 1]
	}
	return p.tokens[p.pos]
}

peek_kind :: proc(p: ^Parser, offset := 1) -> Token_Kind {
	index := p.pos + offset
	if index >= len(p.tokens) {
		return .EOF
	}
	return p.tokens[index].kind
}

check :: proc(p: ^Parser, kind: Token_Kind) -> bool {
	return current(p).kind == kind
}

advance :: proc(p: ^Parser) -> Token {
	tok := current(p)
	if tok.kind != .EOF {
		p.pos += 1
	}
	return tok
}

expect :: proc(p: ^Parser, kind: Token_Kind) -> Token {
	tok := current(p)
	if tok.kind != kind {
		syntax_error(tok.line, "expected %v, found %v", kind, tok.kind)
	}
	return advance(p)
}

make_binary :: proc(op: Token, left, right: Expr) -> Expr {
	node := new(Binary)
	node^ = Binary{op = op.kind, left = left, right = right, line = op.line}
	return node
}

parse_primary :: proc(p: ^Parser) -> Expr {
	tok := current(p)

	#partial switch tok.kind {
	case .Int:
		advance(p)
		node := new(Int_Lit)
		node.value = tok.int_value
		return node

	case .Float:
		advance(p)
		node := new(Float_Lit)
		node.value = tok.float_value
		return node

	case .String:
		advance(p)
		node := new(String_Lit)
		node.value = tok.text
		return node

	case .Ident:
		advance(p)
		node := new(Var)
		node.name = tok.text
		node.line = tok.line
		return node

	case .True:
		advance(p)
		node := new(Bool_Lit)
		node.value = true
		return node

	case .False:
		advance(p)
		node := new(Bool_Lit)
		node.value = false
		return node

	case .Null:
		advance(p)
		node := new(Null_Lit)
		node.line = tok.line
		return node

	case .List:   return parse_list(p)
	case .Map:    return parse_map(p)
	case .Input:  return parse_input(p)
	case .Length: return parse_len(p)

	case .L_Paren:
		advance(p)
		expr := parse_expression(p)
		expect(p, .R_Paren)
		return expr
	}

	syntax_error(tok.line, "invalid expression (found %v)", tok.kind)
}

parse_unary :: proc(p: ^Parser) -> Expr {
	tok := current(p)
	if tok.kind == .Minus || tok.kind == .Not {
		advance(p)
		node := new(Unary)
		node^ = Unary{op = tok.kind, operand = parse_unary(p), line = tok.line}
		return node
	}
	return parse_primary(p)
}

parse_access :: proc(p: ^Parser) -> Expr {
	node := parse_unary(p)

	for {
		if check(p, .From) {
			tok := advance(p)
			target := parse_unary(p)

			access := new(Access)
			access^ = Access{index = node, target = target, line = tok.line}
			node = access
		} else if check(p, .With) {
			node = parse_call(p, node)
		} else {
			break
		}
	}

	return node
}

parse_factor :: proc(p: ^Parser) -> Expr {
	left := parse_access(p)

	for {
		kind := current(p).kind
		if kind != .Star && kind != .Caret && kind != .Slash && kind != .Percent {
			break
		}
		op := advance(p)
		right := parse_access(p)
		left = make_binary(op, left, right)
	}

	return left
}

parse_term :: proc(p: ^Parser) -> Expr {
	left := parse_factor(p)

	for check(p, .Plus) || check(p, .Minus) {
		op := advance(p)
		right := parse_factor(p)
		left = make_binary(op, left, right)
	}

	return left
}

is_comparison :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Greater, .Less, .Greater_Eq, .Less_Eq, .Eq_Eq, .Not_Eq:
		return true
	}
	return false
}

parse_comparison :: proc(p: ^Parser) -> Expr {
	left := parse_term(p)

	for is_comparison(current(p).kind) {
		op := advance(p)
		right := parse_term(p)
		left = make_binary(op, left, right)
	}

	return left
}

parse_and :: proc(p: ^Parser) -> Expr {
	left := parse_comparison(p)

	for check(p, .And) {
		op := advance(p)
		right := parse_comparison(p)
		left = make_binary(op, left, right)
	}

	return left
}

parse_expression :: proc(p: ^Parser) -> Expr {
	left := parse_and(p)

	for check(p, .Or) {
		op := advance(p)
		right := parse_and(p)
		left = make_binary(op, left, right)
	}

	return left
}

parse_list :: proc(p: ^Parser) -> Expr {
	expect(p, .List)
	expect(p, .With)

	node := new(List_Lit)

	if check(p, .Null) {
		advance(p)
		return node
	}

	multiline := false
	if check(p, .Newline) && peek_kind(p) == .Indent {
		advance(p)
		advance(p)
		multiline = true
	}

	append(&node.elements, parse_expression(p))

	for check(p, .Comma) {
		advance(p)

		if multiline {
			for check(p, .Newline) {
				advance(p)
			}
		}

		append(&node.elements, parse_expression(p))
	}

	if multiline {
		newline := expect(p, .Newline)
		expect(p, .Dedent)
		inject_at(&p.tokens, p.pos, Token{kind = .Newline, line = newline.line})
	}

	return node
}

parse_map :: proc(p: ^Parser) -> Expr {
	keyword := expect(p, .Map)
	expect(p, .With)

	node := new(Map_Lit)
	node.line = keyword.line

	if check(p, .Null) {
		advance(p)
		return node
	}

	multiline := false
	if check(p, .Newline) && peek_kind(p) == .Indent {
		advance(p)
		advance(p)
		multiline = true
	}

	for {
		key := parse_expression(p)
		expect(p, .Colon)
		value := parse_expression(p)

		append(&node.keys, key)
		append(&node.values, value)

		had_comma := false
		if check(p, .Comma) {
			advance(p)
			had_comma = true
		}

		if multiline {
			if check(p, .Newline) && peek_kind(p) != .Dedent {
				advance(p)
				continue
			}
			break
		}

		if !had_comma {
			break
		}
	}

	if multiline {
		newline := expect(p, .Newline)
		expect(p, .Dedent)
		inject_at(&p.tokens, p.pos, Token{kind = .Newline, line = newline.line})
	}

	return node
}

parse_call :: proc(p: ^Parser, callee: Expr) -> ^Call {
	tok := expect(p, .With)

	node := new(Call)
	node.callee = callee
	node.line = tok.line

	kind := current(p).kind
	if kind != .Newline && kind != .R_Paren && kind != .EOF {
		append(&node.arguments, parse_expression(p))

		for check(p, .Comma) {
			advance(p)
			append(&node.arguments, parse_expression(p))
		}
	}

	return node
}

parse_input :: proc(p: ^Parser) -> Expr {
	expect(p, .Input)

	node := new(Input_Expr)
	if check(p, .String) {
		node.prompt = parse_primary(p)
	}
	return node
}

parse_len :: proc(p: ^Parser) -> Expr {
	tok := expect(p, .Length)

	node := new(Length_Expr)
	node.line = tok.line
	node.value = parse_unary(p)
	return node
}

parse_block :: proc(p: ^Parser) -> [dynamic]Stmt {
	expect(p, .Newline)
	expect(p, .Indent)

	statements: [dynamic]Stmt

	for !check(p, .Dedent) && !check(p, .EOF) {
		if check(p, .Newline) {
			advance(p)
			continue
		}
		append(&statements, parse_statement(p))
	}

	expect(p, .Dedent)

	return statements
}

parse_declaration :: proc(p: ^Parser) -> Stmt {
	expect(p, .Let)

	name := current(p)
	if name.kind != .Ident {
		syntax_error(name.line, "variable name expected")
	}
	advance(p)

	expect(p, .Assign)

	node := new(Let_Stmt)
	node.name = name.text
	node.value = parse_expression(p)

	expect(p, .Newline)

	return node
}

parse_function :: proc(p: ^Parser) -> Stmt {
	expect(p, .Function)

	name := current(p)
	if name.kind != .Ident {
		syntax_error(name.line, "function name expected")
	}
	advance(p)
	expect(p, .With)

	node := new(Function_Stmt)
	node.name = name.text

	if check(p, .Ident) {
		append(&node.params, advance(p).text)

		for check(p, .Comma) {
			advance(p)

			token := current(p)
			if token.kind != .Ident {
				syntax_error(token.line, "parameter expected after the comma")
			}
			append(&node.params, token.text)
			advance(p)
		}
	}

	node.body = parse_block(p)

	return node
}

parse_print :: proc(p: ^Parser) -> Stmt {
	expect(p, .Print)

	node := new(Print_Stmt)
	node.value = parse_expression(p)

	expect(p, .Newline)

	return node
}

parse_if :: proc(p: ^Parser) -> Stmt {
	expect(p, .If)

	node := new(If_Stmt)
	node.condition = parse_expression(p)

	expect(p, .Then)

	node.body = parse_block(p)

	if check(p, .Else) {
		advance(p)
		node.otherwise = parse_block(p)
	}

	return node
}

parse_foreach :: proc(p: ^Parser) -> Stmt {
	keyword := expect(p, .Foreach)

	name := current(p)
	if name.kind != .Ident {
		syntax_error(name.line, "variable name expected")
	}
	advance(p)
	expect(p, .In)

	list := current(p)
	if list.kind != .Ident {
		syntax_error(list.line, "list name expected")
	}
	advance(p)
	expect(p, .Then)

	node := new(Foreach_Stmt)
	node.var_name = name.text
	node.list_name = list.text
	node.line = keyword.line
	node.body = parse_block(p)

	return node
}

parse_while :: proc(p: ^Parser) -> Stmt {
	expect(p, .While)

	node := new(While_Stmt)
	node.condition = parse_expression(p)

	expect(p, .Then)

	node.body = parse_block(p)

	return node
}

parse_return :: proc(p: ^Parser) -> Stmt {
	expect(p, .Return)

	node := new(Return_Stmt)
	node.value = parse_expression(p)

	expect(p, .Newline)

	return node
}

parse_statement :: proc(p: ^Parser) -> Stmt {
	tok := current(p)

	#partial switch tok.kind {
	case .Ident:
		if peek_kind(p) == .With {
			name := advance(p)

			variable := new(Var)
			variable^ = Var{name = name.text, line = name.line}

			callee: Expr = variable

			node := new(Call_Stmt)
			node.call = parse_call(p, callee)

			expect(p, .Newline)
			return node
		}
		syntax_error(tok.line, "unknown statement: %s", tok.text)

	case .Let:      return parse_declaration(p)
	case .Print:    return parse_print(p)
	case .If:       return parse_if(p)
	case .Foreach:  return parse_foreach(p)
	case .While:    return parse_while(p)
	case .Return:   return parse_return(p)
	case .Function: return parse_function(p)
	}

	syntax_error(tok.line, "unknown statement: %v", tok.kind)
}

parse_program :: proc(p: ^Parser) -> [dynamic]Stmt {
	statements: [dynamic]Stmt

	for !check(p, .EOF) {
		if check(p, .Newline) {
			advance(p)
			continue
		}
		append(&statements, parse_statement(p))
	}

	return statements
}
