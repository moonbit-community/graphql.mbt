///|
fn read_fixture(relative_path : String) -> String raise {
  let from_module_root = "parser/testdata/graphql-parser/\{relative_path}"
  if @fs.path_exists(from_module_root) {
    @fs.read_file_to_string(from_module_root)
  } else {
    @fs.read_file_to_string("testdata/graphql-parser/\{relative_path}")
  }
}

///|
fn query_roundtrip_file(name : String, style : Style) -> Unit raise {
  let source = read_fixture("queries/\{name}.graphql")
  let document = parse_query(source)
  assert_eq(document.format(style~), source)
}

///|
fn query_roundtrip_file_default(name : String) -> Unit raise {
  query_roundtrip_file(name, Style::default())
}

///|
fn query_roundtrip_file_multiline_args(name : String) -> Unit raise {
  query_roundtrip_file(name, Style::default().with_multiline_arguments(true))
}

///|
fn query_canonical_file(name : String) -> Unit raise {
  let source = read_fixture("queries/\{name}.graphql")
  let expected = read_fixture("queries/\{name}_canonical.graphql")
  query_canonical(source, expected)
}

///|
fn schema_roundtrip_file(name : String) -> Unit raise {
  let source = read_fixture("schemas/\{name}.graphql")
  let document = parse_schema(source)
  assert_eq(document.to_string(), source)
}

///|
fn schema_canonical_file(name : String) -> Unit raise {
  let source = read_fixture("schemas/\{name}.graphql")
  let expected = read_fixture("schemas/\{name}_canonical.graphql")
  schema_canonical(source, expected)
}
