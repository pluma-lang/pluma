package tramezzo

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Token_Kind :: enum {
	Print, Input, Length, Copy, To_Number, To_String, List, Map, With,
	If, Else, Foreach, While, Then, In, From,
	Let, Function, Return,
	And, Or, Not,
	True, False, Null,
	Ident, Int, Float, String,
	Greater, Less, Greater_Eq, Less_Eq, Not_Eq, Eq_Eq, Assign,
	Plus, Minus, Star, Slash, Percent, Caret,
	L_Paren, R_Paren, Comma, Colon,
	Indent, Dedent, Newline, EOF,
}

Token :: struct {
	kind:        Token_Kind,
	text:        string,
	int_value:   i64,
	float_value: f64,
	line:        int,
}

syntax_error :: proc(line: int, format: string, args: ..any) -> ! {
	fmt.eprintf("SyntaxError (line %d): ", line)
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

keyword_kind :: proc(word: string) -> (Token_Kind, bool) {
	switch word {
	case "print":                   return .Print, true
	case "input":                   return .Input, true
	case "string":                  return .To_String, true
	case "number":                  return .To_Number, true
	case "length":                  return .Length, true
	case "copy":                  	return .Copy, true
	case "list":                    return .List, true
	case "map":                     return .Map, true
	case "with":                    return .With, true
	case "if":                      return .If, true
	case "else":                    return .Else, true
	case "foreach", "foreverytime": return .Foreach, true
	case "while":                   return .While, true
	case "then":                    return .Then, true
	case "in":                      return .In, true
	case "from":                    return .From, true
	case "let":                     return .Let, true
	case "function":                return .Function, true
	case "return":                  return .Return, true
	case "and":                     return .And, true
	case "or":                      return .Or, true
	case "not":                     return .Not, true
	case "true":                    return .True, true
	case "false":                   return .False, true
	case "null":                    return .Null, true
	}
	return .Ident, false
}

is_alpha :: proc(c: u8) -> bool {
	// bytes >= 0x80 are parts of UTF-8 letters, so accented identifiers work
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0x80
}

is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

is_alnum :: proc(c: u8) -> bool {
	return is_alpha(c) || is_digit(c)
}

tokenize_line :: proc(line: string, line_no: int, tokens: ^[dynamic]Token) {
	n := len(line)
	i := 0

	for i < n {
		c := line[i]

		switch {
		case is_alpha(c):
			j := i
			for j < n && is_alnum(line[j]) {
				j += 1
			}
			word := line[i:j]
			kind, is_keyword := keyword_kind(word)
			if is_keyword {
				append(tokens, Token{kind = kind, text = word, line = line_no})
			} else {
				append(tokens, Token{kind = .Ident, text = word, line = line_no})
			}
			i = j

		case is_digit(c):
			j := i
			for j < n && is_digit(line[j]) {
				j += 1
			}
			if j + 1 < n && line[j] == '.' && is_digit(line[j + 1]) {
				j += 1
				for j < n && is_digit(line[j]) {
					j += 1
				}
				value, _ := strconv.parse_f64(line[i:j])
				append(tokens, Token{kind = .Float, text = line[i:j], float_value = value, line = line_no})
			} else {
				value, _ := strconv.parse_i64(line[i:j])
				append(tokens, Token{kind = .Int, text = line[i:j], int_value = value, line = line_no})
			}
			i = j

		case c == '"':
			start := i + 1
			j := start
			for j < n && line[j] != '"' {
				j += 1
			}
			if j >= n {
				syntax_error(line_no, "unterminated string")
			}
			append(tokens, Token{kind = .String, text = line[start:j], line = line_no})
			i = j + 1

		case c == '#':
			return

		case c == ' ' || c == '\t':
			i += 1

		case:
			next: u8 = 0
			if i + 1 < n {
				next = line[i + 1]
			}

			kind: Token_Kind
			width := 1

			switch c {
			case '>':
				if next == '=' { kind = .Greater_Eq; width = 2 } else { kind = .Greater }
			case '<':
				if next == '=' { kind = .Less_Eq; width = 2 } else { kind = .Less }
			case '!':
				if next == '=' { kind = .Not_Eq; width = 2 } else { kind = .Not }
			case '=':
				if next == '=' { kind = .Eq_Eq; width = 2 } else { kind = .Assign }
			case '+': kind = .Plus
			case '-': kind = .Minus
			case '*': kind = .Star
			case '/': kind = .Slash
			case '%': kind = .Percent
			case '^': kind = .Caret
			case '(': kind = .L_Paren
			case ')': kind = .R_Paren
			case ',': kind = .Comma
			case ':': kind = .Colon
			case:
				syntax_error(line_no, "invalid character %q", rune(c))
			}

			append(tokens, Token{kind = kind, text = line[i:i + width], line = line_no})
			i += width
		}
	}
}

tokenize_source :: proc(source: string) -> [dynamic]Token {
	tokens: [dynamic]Token
	indents: [dynamic]int
	append(&indents, 0)

	line_no := 0
	rest := source

	for raw_line in strings.split_lines_iterator(&rest) {
		line_no += 1

		trimmed := strings.trim_left(raw_line, " \t")
		if len(trimmed) == 0 || trimmed[0] == '#' {
			continue
		}

		indent := raw_line[:len(raw_line) - len(trimmed)]
		if strings.contains_rune(indent, ' ') && strings.contains_rune(indent, '\t') {
			syntax_error(line_no, "mixed tabs and spaces")
		}

		level := len(indent)

		if level > indents[len(indents) - 1] {
			append(&indents, level)
			append(&tokens, Token{kind = .Indent, line = line_no})
		}
		for level < indents[len(indents) - 1] {
			pop(&indents)
			append(&tokens, Token{kind = .Dedent, line = line_no})
		}
		if level != indents[len(indents) - 1] {
			syntax_error(line_no, "inconsistent indentation")
		}

		tokenize_line(trimmed, line_no, &tokens)
		append(&tokens, Token{kind = .Newline, line = line_no})
	}

	for len(indents) > 1 {
		pop(&indents)
		append(&tokens, Token{kind = .Dedent, line = line_no})
	}
	append(&tokens, Token{kind = .EOF, line = line_no})

	return tokens
}
