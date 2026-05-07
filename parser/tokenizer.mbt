///|
pub(all) enum TokenKind {
  TkPunctuator
  TkName
  TkIntValue
  TkFloatValue
  TkStringValue
  TkBlockString
  TkEof
} derive(Eq, Debug)

///|
pub(all) struct Token {
  kind : TokenKind
  value : String
  position : Pos
  start_offset : Int
  end_offset : Int
  next_offset : Int
} derive(Eq, Debug)

///|
priv struct Lexer {
  source : String
  mut input : StringView
  mut line : Int
  mut column : Int
  mut recursion_limit : Int
}

///|
pub fn tokenize(source : String) -> Array[Token] raise ParseError {
  let lexer = Lexer::{
    source,
    input: source[:],
    line: 1,
    column: 1,
    recursion_limit: 50,
  }
  let tokens : Array[Token] = []
  while true {
    lexer.skip_ignored()
    let start = lexer.input.start_offset()
    let position = { line: lexer.line, column: lexer.column }
    match lexer.input {
      [] => {
        tokens.push({
          kind: TkEof,
          value: "",
          position,
          start_offset: start,
          end_offset: start,
          next_offset: start,
        })
        break
      }
      _ => {
        let (kind, end_offset) = lexer.take_token(position)
        let value = lexer.source.unsafe_substring(start~, end=end_offset)
        lexer.skip_ignored()
        tokens.push({
          kind,
          value,
          position,
          start_offset: start,
          end_offset,
          next_offset: lexer.input.start_offset(),
        })
        continue
      }
    }
  }
  tokens
}

///|
fn tokenize_first_query_definition(
  source : String,
) -> (Array[Token], Int) raise ParseError {
  let lexer = Lexer::{
    source,
    input: source[:],
    line: 1,
    column: 1,
    recursion_limit: 50,
  }
  let tokens : Array[Token] = []
  let mut nesting = 0
  let mut first = true
  while true {
    lexer.skip_ignored()
    let start = lexer.input.start_offset()
    let position = { line: lexer.line, column: lexer.column }
    match lexer.input {
      [] => {
        push_eof(tokens, position, start)
        return (tokens, start)
      }
      _ => {
        let (kind, end_offset) = lexer.take_token(position)
        let value = lexer.source.unsafe_substring(start~, end=end_offset)
        lexer.skip_ignored()
        let token = {
          kind,
          value,
          position,
          start_offset: start,
          end_offset,
          next_offset: lexer.input.start_offset(),
        }
        tokens.push(token)
        if first {
          first = false
          if !is_query_definition_start(token) {
            let eof_offset = token.next_offset
            push_eof(
              tokens,
              { line: lexer.line, column: lexer.column },
              eof_offset,
            )
            return (tokens, eof_offset)
          }
        }
        if token.kind == TkPunctuator {
          match token.value {
            "(" | "[" | "{" => nesting += 1
            ")" | "]" | "}" => nesting -= 1
            _ => ()
          }
          if token.value == "}" && nesting == 0 {
            let eof_offset = token.next_offset
            push_eof(
              tokens,
              { line: lexer.line, column: lexer.column },
              eof_offset,
            )
            return (tokens, eof_offset)
          }
        }
        continue
      }
    }
  }
  (tokens, lexer.input.start_offset())
}

///|
fn push_eof(tokens : Array[Token], position : Pos, offset : Int) -> Unit {
  tokens.push({
    kind: TkEof,
    value: "",
    position,
    start_offset: offset,
    end_offset: offset,
    next_offset: offset,
  })
}

///|
fn is_query_definition_start(token : Token) -> Bool {
  (token.kind == TkPunctuator && token.value == "{") ||
  (
    token.kind == TkName &&
    (
      token.value == "query" ||
      token.value == "mutation" ||
      token.value == "subscription" ||
      token.value == "fragment"
    )
  )
}

///|
fn Lexer::take_token(
  self : Lexer,
  position : Pos,
) -> (TokenKind, Int) raise ParseError {
  match self.input {
    ['(', .. rest] | ['[', .. rest] | ['{', .. rest] => {
      if self.recursion_limit == 0 {
        parse_error("Recursion limit exceeded", position)
      }
      self.recursion_limit -= 1
      self.advance_to(rest, 1)
      (TkPunctuator, self.input.start_offset())
    }
    [')', .. rest] | [']', .. rest] | ['}', .. rest] => {
      self.recursion_limit += 1
      self.advance_to(rest, 1)
      (TkPunctuator, self.input.start_offset())
    }
    ['!', .. rest]
    | ['$', .. rest]
    | [':', .. rest]
    | ['=', .. rest]
    | ['@', .. rest]
    | ['|', .. rest]
    | ['&', .. rest] => {
      self.advance_to(rest, 1)
      (TkPunctuator, self.input.start_offset())
    }
    [.. "...", .. rest] => {
      self.advance_to(rest, 3)
      (TkPunctuator, self.input.start_offset())
    }
    ['.', ..] =>
      parse_error("bare dot '.' is not supported, only \"...\"", position)
    ['_', ..] | ['a'..='z', ..] | ['A'..='Z', ..] => {
      let rest = scan_while(self.input, is_name_continue)
      let count = self.input.start_offset().until(rest.start_offset()).count()
      self.advance_to(rest, count)
      (TkName, self.input.start_offset())
    }
    ['-', ..] | ['0'..='9', ..] => self.take_number(position)
    ['"', '"', '"', .. rest] => self.take_block_string(rest, position)
    ['"', .. rest] => self.take_string(rest, position)
    [c, ..] => parse_error("unexpected character \{c}", position)
    [] => parse_error("unexpected end of input", position)
  }
}

///|
fn Lexer::take_number(
  self : Lexer,
  position : Pos,
) -> (TokenKind, Int) raise ParseError {
  let start = self.input.start_offset()
  let rest = scan_number_tail(self.input)
  let end_offset = rest.start_offset()
  let value = self.source.unsafe_substring(start~, end=end_offset)
  if value.contains_char('.') ||
    value.contains_char('e') ||
    value.contains_char('E') {
    if !check_float(value) {
      parse_error("unsupported float \{value}", position)
    }
    self.advance_to(rest, value.char_length())
    (TkFloatValue, end_offset)
  } else {
    if !check_int(value) {
      parse_error("unsupported integer \{value}", position)
    }
    self.advance_to(rest, value.char_length())
    (TkIntValue, end_offset)
  }
}

///|
fn Lexer::take_string(
  self : Lexer,
  rest_after_quote : StringView,
  position : Pos,
) -> (TokenKind, Int) raise ParseError {
  let start = self.input.start_offset()
  let mut escaped = false
  let rest = rest_after_quote
  for rest = rest {
    match rest {
      ['"', .. tail] if !escaped => {
        let end_offset = tail.start_offset()
        let value = self.source.unsafe_substring(start~, end=end_offset)
        self.advance_to(tail, value.char_length())
        break (TkStringValue, end_offset)
      }
      ['\n', ..] => parse_error("unterminated string value", position)
      ['\\', .. tail] if !escaped => {
        escaped = true
        continue tail
      }
      [_, .. tail] => {
        escaped = false
        continue tail
      }
      [] => parse_error("unterminated string value", position)
    }
  }
}

///|
fn Lexer::take_block_string(
  self : Lexer,
  rest_after_open : StringView,
  position : Pos,
) -> (TokenKind, Int) raise ParseError {
  let start = self.input.start_offset()
  let rest = rest_after_open
  let mut previous = '\u{0}'
  for rest = rest {
    match rest {
      [.. "\"\"\"", .. tail] if previous != '\\' => {
        let end_offset = tail.start_offset()
        let value = self.source.unsafe_substring(start~, end=end_offset)
        self.update_position(value)
        self.input = tail
        break (TkBlockString, end_offset)
      }
      [c, .. tail] => {
        previous = c
        continue tail
      }
      [] => parse_error("unterminated block string value", position)
    }
  }
}

///|
fn Lexer::advance_to(self : Lexer, rest : StringView, columns : Int) -> Unit {
  self.input = rest
  self.column += columns
}

///|
fn Lexer::update_position(self : Lexer, value : String) -> Unit {
  let mut lines = 0
  let mut after_last_newline = 0
  for c in value.iter() {
    if c == '\n' {
      lines += 1
      after_last_newline = 0
    } else {
      after_last_newline += 1
    }
  }
  self.line += lines
  if lines > 0 {
    self.column = after_last_newline + 1
  } else {
    self.column += after_last_newline
  }
}

///|
fn Lexer::skip_ignored(self : Lexer) -> Unit {
  while true {
    match self.input {
      ['\u{feff}', .. rest] | ['\r', .. rest] => {
        self.input = rest
        continue
      }
      ['\t', .. rest] => {
        self.column += 8
        self.input = rest
        continue
      }
      ['\n', .. rest] => {
        self.column = 1
        self.line += 1
        self.input = rest
        continue
      }
      [' ', .. rest] | [',', .. rest] => {
        self.column += 1
        self.input = rest
        continue
      }
      ['#', .. rest] => {
        let rest = self.skip_comment(rest)
        self.input = rest
        continue
      }
      _ => break
    }
  }
}

///|
fn Lexer::skip_comment(self : Lexer, input : StringView) -> StringView {
  for input = input {
    match input {
      ['\n', .. rest] | ['\r', .. rest] => {
        self.column = 1
        self.line += 1
        break rest
      }
      [_, .. rest] => continue rest
      [] as rest => break rest
    }
  }
}

///|
fn scan_while(input : StringView, pred : (Char) -> Bool) -> StringView {
  for input = input {
    match input {
      [c, .. rest] if pred(c) => continue rest
      rest => break rest
    }
  }
}

///|
fn scan_number_tail(input : StringView) -> StringView {
  for input = input {
    match input {
      [c, ..] as rest if is_number_stop(c) => break rest
      [_, .. rest] => continue rest
      [] as rest => break rest
    }
  }
}

///|
fn is_number_stop(c : Char) -> Bool {
  match c {
    ' '
    | '\n'
    | '\r'
    | '\t'
    | ','
    | '#'
    | '!'
    | '$'
    | ':'
    | '='
    | '@'
    | '|'
    | '&'
    | '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}' => true
    _ => false
  }
}

///|
fn is_name_continue(c : Char) -> Bool {
  c == '_' || c.is_ascii_alphabetic() || c.is_ascii_digit()
}

///|
fn all_digits(input : StringView) -> Bool {
  for input = input {
    match input {
      [c, .. rest] if c.is_ascii_digit() => continue rest
      [] => break true
      _ => break false
    }
  }
}

///|
fn check_int(value : String) -> Bool {
  if value == "0" || value == "-0" {
    true
  } else if value.has_prefix("0") {
    false
  } else if value == "-" {
    false
  } else if value.has_prefix("-0") {
    false
  } else {
    all_digits_after_first(value)
  }
}

///|
fn all_digits_after_first(value : String) -> Bool {
  let mut first = true
  for c in value.iter() {
    if first {
      first = false
      continue
    }
    if !c.is_ascii_digit() {
      return false
    }
  }
  true
}

///|
pub impl Show for TokenKind with output(self : TokenKind, logger : &Logger) -> Unit {
  logger.write_string(
    match self {
      TkPunctuator => "TkPunctuator"
      TkName => "TkName"
      TkIntValue => "TkIntValue"
      TkFloatValue => "TkFloatValue"
      TkStringValue => "TkStringValue"
      TkBlockString => "TkBlockString"
      TkEof => "TkEof"
    },
  )
}

///|
fn check_dec(value : StringView) -> Bool {
  !value.is_empty() && all_digits(value)
}

///|
fn check_exp(value : StringView) -> Bool {
  match value {
    [] => false
    [first, .. rest] =>
      if first != '-' && first != '+' && (first <= '0' || first >= '9') {
        false
      } else {
        all_digits(rest)
      }
  }
}

///|
fn check_float(value : String) -> Bool {
  let exponent = first_exponent(value)
  let real = value.find(".")
  match (exponent, real) {
    (Some(e), Some(r)) if e < r => false
    (Some(e), Some(r)) =>
      check_int(value.unsafe_substring(start=0, end=r)) &&
      check_dec(value.view(start_offset=r + 1, end_offset=e)) &&
      check_exp(value.view(start_offset=e + 1))
    (Some(e), None) =>
      check_int(value.unsafe_substring(start=0, end=e)) &&
      check_exp(value.view(start_offset=e + 1))
    (None, Some(r)) =>
      check_int(value.unsafe_substring(start=0, end=r)) &&
      check_dec(value.view(start_offset=r + 1))
    (None, None) => false
  }
}

///|
fn first_exponent(value : String) -> Int? {
  let lower = value.find("e")
  let upper = value.find("E")
  match (lower, upper) {
    (Some(a), Some(b)) => Some(Int::min(a, b))
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
}
