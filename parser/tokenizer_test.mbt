///|
using @test {assert_eq, assert_raise}

///|
fn token_values(source : String) -> Array[String] raise {
  tokenize(source)
  .filter(token => token.kind != TkEof)
  .map(token => token.value)
}

///|
fn token_kinds(source : String) -> Array[TokenKind] raise {
  tokenize(source).filter(token => token.kind != TkEof).map(token => token.kind)
}

///|
fn assert_tokenize_error(source : String) -> Unit raise {
  assert_raise(() => tokenize(source))
}

///|
test "tokenizer comments and commas" {
  assert_eq(token_values("# hello { world }"), [])
  assert_eq(token_values("# x\n,,,"), [])
  assert_eq(token_values(", ,,  ,,,  # x"), [])
}

///|
test "tokenizer simple" {
  assert_eq(token_values("a { b }"), ["a", "{", "b", "}"])
  assert_eq(token_kinds("a { b }"), [TkName, TkPunctuator, TkName, TkPunctuator])
}

///|
test "tokenizer query" {
  assert_eq(
    token_values("query Query {\n            object { field }\n        }"),
    ["query", "Query", "{", "object", "{", "field", "}", "}"],
  )
}

///|
test "tokenizer fragment" {
  assert_eq(token_values("a { ...b }"), ["a", "{", "...", "b", "}"])
}

///|
test "tokenizer int" {
  assert_eq(token_values("0"), ["0"])
  assert_eq(token_values("0,"), ["0"])
  assert_eq(token_values("0# x"), ["0"])
  assert_eq(token_kinds("0"), [TkIntValue])
  assert_eq(token_values("-0"), ["-0"])
  assert_eq(token_kinds("-0"), [TkIntValue])
  assert_eq(token_values("-1"), ["-1"])
  assert_eq(token_kinds("-1"), [TkIntValue])
  assert_eq(token_values("-132"), ["-132"])
  assert_eq(token_kinds("-132"), [TkIntValue])
  assert_eq(token_values("132"), ["132"])
  assert_eq(token_kinds("132"), [TkIntValue])
  assert_eq(token_values("a(x: 10) { b }"), [
    "a", "(", "x", ":", "10", ")", "{", "b", "}",
  ])
  assert_eq(token_kinds("a(x: 10) { b }"), [
    TkName,
    TkPunctuator,
    TkName,
    TkPunctuator,
    TkIntValue,
    TkPunctuator,
    TkPunctuator,
    TkName,
    TkPunctuator,
  ])
}

///|
test "tokenizer invalid int" {
  assert_tokenize_error("01")
  assert_tokenize_error("00001")
  assert_tokenize_error("-")
  assert_tokenize_error("-01")
  assert_tokenize_error("-00001")
  assert_tokenize_error("0bbc")
}

///|
test "tokenizer float" {
  assert_eq(token_values("0.0"), ["0.0"])
  assert_eq(token_kinds("0.0"), [TkFloatValue])
  assert_eq(token_values("-0.0"), ["-0.0"])
  assert_eq(token_kinds("-0.0"), [TkFloatValue])
  assert_eq(token_values("-1.0"), ["-1.0"])
  assert_eq(token_kinds("-1.0"), [TkFloatValue])
  assert_eq(token_values("-1.023"), ["-1.023"])
  assert_eq(token_kinds("-1.023"), [TkFloatValue])
  assert_eq(token_values("-132.0"), ["-132.0"])
  assert_eq(token_kinds("-132.0"), [TkFloatValue])
  assert_eq(token_values("132.0"), ["132.0"])
  assert_eq(token_kinds("132.0"), [TkFloatValue])
  assert_eq(token_values("0e+0"), ["0e+0"])
  assert_eq(token_kinds("0e+0"), [TkFloatValue])
  assert_eq(token_values("0.0e+0"), ["0.0e+0"])
  assert_eq(token_kinds("0.0e+0"), [TkFloatValue])
  assert_eq(token_values("-0e+0"), ["-0e+0"])
  assert_eq(token_kinds("-0e+0"), [TkFloatValue])
  assert_eq(token_values("-1e+0"), ["-1e+0"])
  assert_eq(token_kinds("-1e+0"), [TkFloatValue])
  assert_eq(token_values("-132e+0"), ["-132e+0"])
  assert_eq(token_kinds("-132e+0"), [TkFloatValue])
  assert_eq(token_values("132e+0"), ["132e+0"])
  assert_eq(token_kinds("132e+0"), [TkFloatValue])
  assert_eq(token_values("a(x: 10.0) { b }"), [
    "a", "(", "x", ":", "10.0", ")", "{", "b", "}",
  ])
  assert_eq(token_kinds("a(x: 10.0) { b }"), [
    TkName,
    TkPunctuator,
    TkName,
    TkPunctuator,
    TkFloatValue,
    TkPunctuator,
    TkPunctuator,
    TkName,
    TkPunctuator,
  ])
  assert_eq(token_values("1.23e4"), ["1.23e4"])
  assert_eq(token_kinds("1.23e4"), [TkFloatValue])
}

///|
test "tokenizer invalid float" {
  assert_tokenize_error(".0")
  assert_tokenize_error(".1")
  assert_tokenize_error("01.0")
  assert_tokenize_error("00001.0")
  assert_tokenize_error("-.0")
  assert_tokenize_error("-01.0")
  assert_tokenize_error("-00001.0")
  assert_tokenize_error("0bbc.0")
  assert_tokenize_error("0.bbc")
  assert_tokenize_error("0.bbce0")
  assert_tokenize_error("0e0")
}

///|
test "tokenizer invalid string" {
  assert_tokenize_error("\"hello\\\"")
  assert_tokenize_error("\"hello\\\\\\\"")
}

///|
test "tokenizer string" {
  assert_eq(token_values("\"\""), ["\"\""])
  assert_eq(token_kinds("\"\""), [TkStringValue])
  assert_eq(token_values("\"hello\""), ["\"hello\""])
  assert_eq(token_values("\"hello\\\\\""), ["\"hello\\\\\""])
  assert_eq(token_values("\"hello\\\\\\\\\""), ["\"hello\\\\\\\\\""])
  assert_eq(token_values("\"he\\\\llo\""), ["\"he\\\\llo\""])
  assert_eq(token_kinds("\"hello\""), [TkStringValue])
  assert_eq(token_values("\"my\\\"quote\""), ["\"my\\\"quote\""])
  assert_eq(token_kinds("\"my\\\"quote\""), [TkStringValue])
}

///|
test "tokenizer block string" {
  assert_eq(token_values("\"\"\"\"\"\""), ["\"\"\"\"\"\""])
  assert_eq(token_kinds("\"\"\"\"\"\""), [TkBlockString])
  assert_eq(token_values("\"\"\"hello\"\"\""), ["\"\"\"hello\"\"\""])
  assert_eq(token_kinds("\"\"\"hello\"\"\""), [TkBlockString])
  assert_eq(token_values("\"\"\"my \"quote\" \"\"\""), [
    "\"\"\"my \"quote\" \"\"\"",
  ])
  assert_eq(token_kinds("\"\"\"my \"quote\" \"\"\""), [TkBlockString])
  assert_eq(token_values("\"\"\"\\\"\"\"quote\" \"\"\""), [
    "\"\"\"\\\"\"\"quote\" \"\"\"",
  ])
  assert_eq(token_kinds("\"\"\"\\\"\"\"quote\" \"\"\""), [TkBlockString])
}
