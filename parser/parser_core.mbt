///|
priv struct Parser {
  tokens : Array[Token]
  mut index : Int
}

///|
fn Parser::new(source : String) -> Parser raise ParseError {
  { tokens: tokenize(source), index: 0 }
}

///|
fn Parser::peek(self : Parser) -> Token {
  match self.tokens.get(self.index) {
    Some(token) => token
    None => self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  self.peek().kind == TkEof
}

///|
fn Parser::take(self : Parser) -> Token {
  let token = self.peek()
  if self.index < self.tokens.length() {
    self.index += 1
  }
  token
}

///|
fn Parser::check_punct(self : Parser, value : String) -> Bool {
  let token = self.peek()
  token.kind == TkPunctuator && token.value == value
}

///|
fn Parser::eat_punct(self : Parser, value : String) -> Bool {
  if self.check_punct(value) {
    ignore(self.take())
    true
  } else {
    false
  }
}

///|
fn Parser::expect_punct(
  self : Parser,
  value : String,
) -> Token raise ParseError {
  if self.check_punct(value) {
    self.take()
  } else {
    let token = self.peek()
    parse_error("expected \{value}, found \{token.value}", token.position)
  }
}

///|
fn Parser::check_ident(self : Parser, value : String) -> Bool {
  let token = self.peek()
  token.kind == TkName && token.value == value
}

///|
fn Parser::eat_ident(self : Parser, value : String) -> Bool {
  if self.check_ident(value) {
    ignore(self.take())
    true
  } else {
    false
  }
}

///|
fn Parser::expect_ident(
  self : Parser,
  value : String,
) -> Token raise ParseError {
  if self.check_ident(value) {
    self.take()
  } else {
    let token = self.peek()
    parse_error("expected \{value}, found \{token.value}", token.position)
  }
}

///|
fn Parser::check_name(self : Parser) -> Bool {
  self.peek().kind == TkName
}

///|
fn Parser::expect_name(self : Parser) -> (String, Pos) raise ParseError {
  let token = self.peek()
  if token.kind == TkName {
    ignore(self.take())
    (token.value, token.position)
  } else {
    parse_error("expected Name, found \{token.value}", token.position)
  }
}

///|
fn Parser::expect_eof(self : Parser) -> Unit raise ParseError {
  if !self.at_eof() {
    let token = self.peek()
    parse_error("unexpected token \{token.value}", token.position)
  }
}

///|
fn empty_selection_set(position : Pos) -> SelectionSet {
  { span: (position, position), items: [] }
}

///|
fn Parser::parse_type(self : Parser) -> GqlType raise ParseError {
  let typ = if self.eat_punct("[") {
    let inner = self.parse_type()
    ignore(self.expect_punct("]"))
    ListType(inner)
  } else {
    let (name, _) = self.expect_name()
    NamedType(name)
  }
  if self.eat_punct("!") {
    NonNullType(typ)
  } else {
    typ
  }
}

///|
fn Parser::parse_arguments(
  self : Parser,
) -> Array[(String, Value)] raise ParseError {
  if !self.eat_punct("(") {
    return []
  }
  let args : Array[(String, Value)] = []
  if self.check_punct(")") {
    let token = self.peek()
    parse_error("expected argument", token.position)
  }
  while true {
    if self.check_punct(")") {
      ignore(self.take())
      break
    }
    let (name, _) = self.expect_name()
    ignore(self.expect_punct(":"))
    let value = self.parse_value()
    args.push((name, value))
    continue
  }
  args
}

///|
fn Parser::parse_directives(self : Parser) -> Array[Directive] raise ParseError {
  let result : Array[Directive] = []
  while true {
    if !self.eat_punct("@") {
      break
    }
    let (name, pos) = self.expect_name()
    let arguments = self.parse_arguments()
    result.push({ position: pos, name, arguments })
    continue
  }
  result
}

///|
fn Parser::parse_string_literal(self : Parser) -> String raise ParseError {
  let token = self.peek()
  match token.kind {
    TkStringValue => {
      ignore(self.take())
      unquote_string(token.value, token.position)
    }
    TkBlockString => {
      ignore(self.take())
      unquote_block_string(token.value)
    }
    _ => parse_error("expected string literal", token.position)
  }
}

///|
fn Parser::parse_plain_value(self : Parser) -> Value raise ParseError {
  let token = self.peek()
  match token.kind {
    TkName =>
      match token.value {
        "true" => {
          ignore(self.take())
          BooleanValue(true)
        }
        "false" => {
          ignore(self.take())
          BooleanValue(false)
        }
        "null" => {
          ignore(self.take())
          NullValue
        }
        name => {
          ignore(self.take())
          EnumValue(name)
        }
      }
    TkIntValue => {
      ignore(self.take())
      let value = @string.parse_int64(token.value[:]) catch {
        _ => parse_error("number too large", token.position)
      }
      IntValue({ value, })
    }
    TkFloatValue => {
      ignore(self.take())
      let value = @string.parse_double(token.value[:]) catch {
        _ => parse_error("unsupported float \{token.value}", token.position)
      }
      FloatValue(value)
    }
    TkStringValue | TkBlockString => StringValue(self.parse_string_literal())
    _ => parse_error("expected value", token.position)
  }
}

///|
fn Parser::parse_value(self : Parser) -> Value raise ParseError {
  if self.eat_punct("$") {
    let (name, _) = self.expect_name()
    return Variable(name)
  }
  if self.eat_punct("[") {
    let values : Array[Value] = []
    while true {
      if self.check_punct("]") {
        ignore(self.take())
        break
      }
      values.push(self.parse_value())
      continue
    }
    return ListValue(values)
  }
  if self.eat_punct("{") {
    let values : Array[(String, Value)] = []
    while true {
      if self.check_punct("}") {
        ignore(self.take())
        break
      }
      let (name, _) = self.expect_name()
      ignore(self.expect_punct(":"))
      values.push((name, self.parse_value()))
      continue
    }
    return ObjectValue(values)
  }
  self.parse_plain_value()
}

///|
fn Parser::parse_default_value(self : Parser) -> Value raise ParseError {
  if self.eat_punct("[") {
    let values : Array[Value] = []
    while true {
      if self.check_punct("]") {
        ignore(self.take())
        break
      }
      values.push(self.parse_default_value())
      continue
    }
    return ListValue(values)
  }
  if self.eat_punct("{") {
    let values : Array[(String, Value)] = []
    while true {
      if self.check_punct("}") {
        ignore(self.take())
        break
      }
      let (name, _) = self.expect_name()
      ignore(self.expect_punct(":"))
      values.push((name, self.parse_default_value()))
      continue
    }
    return ObjectValue(values)
  }
  self.parse_plain_value()
}

///|
fn unquote_string(source : String, position : Pos) -> String raise ParseError {
  let inner = source.view(start_offset=1, end_offset=source.length() - 1)
  let builder = StringBuilder::new(size_hint=source.length())
  for inner = inner {
    match inner {
      ['\\', c, .. tail] => {
        match c {
          '"' | '\\' | '/' => builder.write_char(c)
          'b' => builder.write_char('\u{0010}')
          'f' => builder.write_char('\u{000c}')
          'n' => builder.write_char('\n')
          'r' => builder.write_char('\r')
          't' => builder.write_char('\t')
          'u' => {
            if !tail.char_length_ge(4) {
              parse_error("\\u must have 4 characters after it", position)
            }
            let hex = tail.view(start_offset=0, end_offset=4).to_owned()
            let code = @string.parse_int(hex[:], base=16) catch {
              _ =>
                parse_error(
                  "\{hex} is not a valid unicode code point",
                  position,
                )
            }
            match code.to_char() {
              Some(ch) => builder.write_char(ch)
              None =>
                parse_error(
                  "\{hex} is not a valid unicode code point",
                  position,
                )
            }
            continue tail.view(start_offset=4)
          }
          bad => parse_error("bad escaped char \{bad}", position)
        }
        continue tail
      }
      [c, .. tail] => {
        builder.write_char(c)
        continue tail
      }
      [] => break
    }
  }
  builder.to_string()
}

///|
fn unquote_block_string(source : String) -> String {
  let body = source
    .view(start_offset=3, end_offset=source.length() - 3)
    .to_owned()
  let lines = rust_lines(body)
  let mut common_indent = 2147483647
  let mut first_non_empty_line : Int? = None
  let mut last_non_empty_line = 0
  for idx, line in lines {
    let trimmed = line.trim_start()
    let indent = line.length() - trimmed.length()
    if indent == line.length() {
      continue
    }
    if first_non_empty_line is None {
      first_non_empty_line = Some(idx)
    }
    last_non_empty_line = idx
    if idx != 0 {
      common_indent = Int::min(common_indent, indent)
    }
  }
  match first_non_empty_line {
    None => ""
    Some(first) => {
      let builder = StringBuilder::new(size_hint=source.length())
      let mut first_output = true
      for idx in first..<=last_non_empty_line {
        let line = lines[idx]
        let selected = if idx != 0 && line.length() >= common_indent {
          line.unsafe_substring(start=common_indent, end=line.length())
        } else {
          line
        }
        if first_output {
          first_output = false
        } else {
          builder.write_char('\n')
        }
        builder.write_string(selected.replace_all(old="\\\"\"\"", new="\"\"\""))
      }
      builder.to_string()
    }
  }
}

///|
fn rust_lines(source : String) -> Array[String] {
  if source.is_empty() {
    return []
  }
  let lines : Array[String] = source
    .split("\n")
    .map(line => line.to_owned())
    .collect()
  if source.has_suffix("\n") && !lines.is_empty() {
    ignore(lines.pop())
  }
  lines
}
