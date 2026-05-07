///|
fn query_roundtrip(source : String) -> Unit raise {
  let document = parse_query(source)
  assert_eq(document.to_string(), with_final_newline(source))
}

///|
fn query_roundtrip_with_style(source : String, style : Style) -> Unit raise {
  let document = parse_query(source)
  assert_eq(document.format(style~), with_final_newline(source))
}

///|
fn query_canonical(source : String, expected : String) -> Unit raise {
  let document = parse_query(source)
  assert_eq(document.to_string(), with_final_newline(expected))
}

///|
fn schema_roundtrip(source : String) -> Unit raise {
  let document = parse_schema(source)
  assert_eq(document.to_string(), with_final_newline(source))
}

///|
fn schema_canonical(source : String, expected : String) -> Unit raise {
  let document = parse_schema(source)
  assert_eq(document.to_string(), with_final_newline(expected))
}

///|
fn with_final_newline(source : String) -> String {
  if source.has_suffix("\n") {
    source
  } else {
    source + "\n"
  }
}

///|
test "tokenizer comments commas and simple tokens" {
  let tokens = tokenize("# x\n,,, a { b }")
    .filter(token => token.kind != TkEof)
    .map(token => token.value)
  assert_eq(tokens, ["a", "{", "b", "}"])
}

///|
test "tokenizer number and string validation" {
  assert_eq(tokenize("0 -0 -132 132 0.5 1.23e4").map(t => t.kind), [
    TkIntValue,
    TkIntValue,
    TkIntValue,
    TkIntValue,
    TkFloatValue,
    TkFloatValue,
    TkEof,
  ])
  assert_true((try? tokenize("01")) is Err(_))
  assert_true((try? tokenize(".1")) is Err(_))
  assert_true((try? tokenize("\"unterminated")) is Err(_))
}

///|
test "query roundtrips" {
  query_roundtrip(
    (
      #|{
      #|  a
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query {
      #|  node
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query Foo($arg: SomeType) {
      #|  field
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query($first: Int, $second: Int) {
      #|  field1(first: $first)
      #|  field2(second: $second)
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query Foo($site: [Int] = [123, 456]) {
      #|  field
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query Foo($site: Site = {url: null}) {
      #|  field
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query {
      #|  an_alias: node
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query @directive {
      #|  node
      #|}
    ),
  )
  query_roundtrip(
    (
      #|subscription @directive {
      #|  node
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query {
      #|  node(id: """
      #|    Hello,
      #|      world!
      #|  """)
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query {
      #|  node(id: 1, obj: {key1: 123, key2: 456})
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query {
      #|  node {
      #|    id
      #|    ... on User @defer {
      #|      name
      #|    }
      #|    ...something
      #|  }
      #|}
    ),
  )
  query_roundtrip(
    (
      #|fragment frag on Friend {
      #|  node
      #|}
    ),
  )
  query_roundtrip(
    (
      #|query {
      #|  node @dir(a: 1, b: "2", c: true, d: false, e: null)
      #|}
    ),
  )
}

///|
test "query multiline arguments style" {
  query_roundtrip_with_style(
    (
      #|query {
      #|  node(
      #|    id: 1,
      #|    obj: {
      #|      key1: 123,
      #|      key2: 456
      #|    }
      #|  )
      #|}
    ),
    Style::default().with_multiline_arguments(true),
  )
}

///|
test "query canonicalization and consume" {
  query_canonical(
    (
      #|query {
      #|  field1
      #|}
      #|query {
      #|  field2
      #|}
    ),
    (
      #|query {
      #|  field1
      #|}
      #|
      #|query {
      #|  field2
      #|}
    ),
  )
  let (_, rest) = consume_definition("query { a } query { b }")
  assert_eq(rest, "query { b }")
}

///|
test "minify query" {
  let source =
    #|query SomeQuery($foo: String!, $bar: String) {
    #|  someField(foo: $foo, bar: $bar) {
    #|    a
    #|    b {
    #|      ... on B {
    #|        c
    #|        d
    #|      }
    #|    }
    #|  }
    #|}
  assert_eq(
    minify_query(source),
    "query SomeQuery($foo:String!$bar:String){someField(foo:$foo bar:$bar){a b{...on B{c d}}}}",
  )
  assert_true((try? minify_query("query foo { bar; }")) is Err(_))
}

///|
test "schema roundtrips from rust fixtures" {
  schema_roundtrip(
    (
      #|schema {
      #|  query: Query
      #|}
    ),
  )
  schema_roundtrip(
    (
      #|"This is the best scalar type"
      #|scalar BestType @perfectness(value: 100500)
    ),
  )
  schema_roundtrip("extend scalar CustomScalar @onScalar")
  schema_roundtrip("type UndefinedType")
  schema_roundtrip(
    (
      #|type Type1 implements IOne
      #|
      #|type Type1 implements IOne & ITwo
    ),
  )
  schema_roundtrip(
    (
      #|interface IOne implements ITwo
      #|
      #|interface IThree implements IFour & IFive
    ),
  )
  schema_roundtrip(
    (
      #|extend type Foo {
      #|  seven(argument: [String]): Type
      #|}
      #|
      #|extend type Bar implements IOne & ITwo {
      #|  five(argument: [String!]!): Type
      #|}
    ),
  )
  schema_roundtrip(
    (
      #|extend interface Bar {
      #|  two(argument: InputType!): Type
      #|}
      #|
      #|extend interface Foo implements IOne & ITwo {
      #|  three(argument: [InputType!]!): Type
      #|}
    ),
  )
  schema_roundtrip("union Feed = Story | Article | Advert")
  schema_roundtrip("union UndefinedUnion")
  schema_roundtrip("extend union Feed = Photo | Video")
  schema_roundtrip(
    (
      #|enum Site {
      #|  DESKTOP
      #|  MOBILE
      #|}
    ),
  )
  schema_roundtrip(
    (
      #|input InputType {
      #|  key: String!
      #|  answer: Int = 42
      #|}
    ),
  )
  schema_roundtrip(
    "directive @skip(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT",
  )
  schema_roundtrip("directive @configurable on VARIABLE_DEFINITION")
  schema_roundtrip("directive @filter(expression: String!) repeatable on FIELD")
}

///|
test "schema canonicalization from rust fixtures" {
  schema_canonical(
    (
      #|type Type1 implements & IOne & ITwo
      #|type Type2 implements & IOne
    ),
    (
      #|type Type1 implements IOne & ITwo
      #|
      #|type Type2 implements IOne
    ),
  )
  schema_canonical(
    (
      #|extend input InputType {
      #|  other: Float = 1.23e4
      #|}
    ),
    (
      #|extend input InputType {
      #|  other: Float = 12300
      #|}
    ),
  )
}
