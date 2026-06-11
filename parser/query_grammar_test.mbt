///|
fn parsed_query(source : String) -> QueryDocument raise {
  parse_query(source)
}

///|
test "query grammar one field" {
  assert_eq(parsed_query("{ a }"), {
    definitions: [
      OperationDefinition(
        SelectionSetOperation({
          span: ({ line: 1, column: 1 }, { line: 1, column: 5 }),
          items: [
            FieldSelection({
              position: { line: 1, column: 3 },
              field_alias: None,
              name: "a",
              arguments: [],
              directives: [],
              selection_set: {
                span: ({ line: 1, column: 3 }, { line: 1, column: 3 }),
                items: [],
              },
            }),
          ],
        }),
      ),
    ],
  })
}

///|
test "query grammar builtin values" {
  assert_eq(parsed_query("{ a(t: true, f: false, n: null) }"), {
    definitions: [
      OperationDefinition(
        SelectionSetOperation({
          span: ({ line: 1, column: 1 }, { line: 1, column: 33 }),
          items: [
            FieldSelection({
              position: { line: 1, column: 3 },
              field_alias: None,
              name: "a",
              arguments: [
                ("t", BooleanValue(true)),
                ("f", BooleanValue(false)),
                ("n", NullValue),
              ],
              directives: [],
              selection_set: {
                span: ({ line: 1, column: 3 }, { line: 1, column: 3 }),
                items: [],
              },
            }),
          ],
        }),
      ),
    ],
  })
}

///|
test "query grammar one field roundtrip" {
  assert_eq(parsed_query("{ a }").to_string(), "{\n  a\n}\n")
}

///|
test "query grammar large integer fails" {
  @test.assert_raise(() => parse_query("{ a(x: 10000000000000000000000000000 }"))
}

///|
test "query consume single query" {
  let (query, remainder) = consume_definition("query { a } query { b }")
  assert_true(query is OperationDefinition(_))
  assert_eq(remainder, "query { b }")
}

///|
test "query consume full text" {
  let (query, remainder) = consume_definition("query { a }")
  assert_true(query is OperationDefinition(_))
  assert_eq(remainder, "")
}

///|
test "query consume before non graphql remainder" {
  let (query, remainder) = consume_definition("query { a } where a > 1 => 10.0")
  assert_true(query is OperationDefinition(_))
  assert_eq(remainder, "where a > 1 => 10.0")
}

///|
test "query consume fails without operation" {
  try consume_definition("where a > 1 => 10.0") catch {
    err => {
      let message = err.to_string()
      assert_true(message.contains("graphql parse error at 1:1"))
      assert_true(
        message.contains(
          "expected {, query, mutation, subscription or fragment",
        ),
      )
    }
  } noraise {
    _ => assert_true(false)
  }
}

///|
test "query recursion too deep" {
  let query = "{ a".repeat(30) +
    "(b: " +
    "[".repeat(25) +
    "]".repeat(25) +
    "}".repeat(30)
  try parse_query(query) catch {
    err => assert_true(err.to_string().contains("Recursion limit exceeded"))
  } noraise {
    _ => assert_true(false)
  }
}

///|
fn assert_query_error_fixture(name : String) -> Unit raise {
  let parts : Array[String] = read_fixture("query_errors/\{name}.txt")
    .split("\n---\n")
    .map(part => part.to_owned())
    .collect()
  assert_eq(parts.length(), 2)
  assert_true(!parts[1].is_empty())
  @test.assert_raise(() => parse_query(parts[0]))
}

///|
test "query error fixture invalid curly brace" {
  assert_query_error_fixture("invalid_curly_brace")
}

///|
test "query error fixture bad args" {
  assert_query_error_fixture("bad_args")
}
