///|
let common_test_pos : Pos = { line: 1, column: 1 }

///|
fn quoted_block(input : String) -> String {
  "\"\"\"" + input + "\"\"\""
}

///|
test "number from int and to int64 conversion" {
  assert_eq(
    Number::{ value: Int64::from_int(1) }.as_int64(),
    Int64::from_int(1),
  )
  assert_eq(
    Number::{ value: Int64::from_int(584) }.as_int64(),
    Int64::from_int(584),
  )
  assert_eq(
    Number::{ value: Int64::from_int(-2147483648) }.as_int64(),
    Int64::from_int(-2147483648),
  )
  assert_eq(
    Number::{ value: Int64::from_int(2147483647) }.as_int64(),
    Int64::from_int(2147483647),
  )
}

///|
test "unquote unicode string" {
  assert_eq(unquote_string("\"\\u0009\"", common_test_pos), "\u{0009}")
  assert_eq(unquote_string("\"\\u000A\"", common_test_pos), "\u{000A}")
  assert_eq(unquote_string("\"\\u000D\"", common_test_pos), "\u{000D}")
  assert_eq(unquote_string("\"\\u0020\"", common_test_pos), "\u{0020}")
  assert_eq(unquote_string("\"\\uFFFF\"", common_test_pos), "\u{FFFF}")
  assert_eq(
    unquote_string("\"\\u0009 hello \\u000A there\"", common_test_pos),
    "\u{0009} hello \u{000A} there",
  )
}

///|
test "block string leading and trailing empty lines" {
  let block = quoted_block(
    "   \n\n  Hello,\n    World!\n\n  Yours,\n    GraphQL.\n\n\n",
  )
  assert_eq(
    unquote_block_string(block),
    "Hello,\n  World!\n\nYours,\n  GraphQL.",
  )
}

///|
test "block string indent" {
  let block = quoted_block("Hello   \n\n  Hello,\n    World!\n")
  assert_eq(unquote_block_string(block), "Hello   \n\nHello,\n  World!")
}

///|
test "block string escaping" {
  let block = quoted_block("\\\"\"\"")
  assert_eq(unquote_block_string(block), "\"\"\"")
}

///|
test "block string empty" {
  assert_eq(unquote_block_string(quoted_block("")), "")
  assert_eq(unquote_block_string(quoted_block("   \n\t\n")), "")
}
