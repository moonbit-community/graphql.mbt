///|
test "query roundtrip minimal" {
  query_roundtrip_file_default("minimal")
}

///|
test "query roundtrip minimal query" {
  query_roundtrip_file_default("minimal_query")
}

///|
test "query roundtrip named query" {
  query_roundtrip_file_default("named_query")
}

///|
test "query roundtrip query vars" {
  query_roundtrip_file_default("query_vars")
}

///|
test "query roundtrip nameless vars" {
  query_roundtrip_file_default("query_nameless_vars")
}

///|
test "query canonical nameless vars multiple fields" {
  query_canonical_file("query_nameless_vars_multiple_fields")
}

///|
test "query roundtrip var defaults" {
  query_roundtrip_file_default("query_var_defaults")
}

///|
test "query roundtrip var default string" {
  query_roundtrip_file_default("query_var_default_string")
}

///|
test "query roundtrip var default float" {
  query_roundtrip_file_default("query_var_default_float")
}

///|
test "query roundtrip var default list" {
  query_roundtrip_file_default("query_var_default_list")
}

///|
test "query roundtrip var default object" {
  query_roundtrip_file_default("query_var_default_object")
}

///|
test "query roundtrip aliases" {
  query_roundtrip_file_default("query_aliases")
}

///|
test "query roundtrip arguments" {
  query_roundtrip_file_default("query_arguments")
}

///|
test "query roundtrip arguments multiline" {
  query_roundtrip_file_multiline_args("query_arguments_multiline")
}

///|
test "query roundtrip directive" {
  query_roundtrip_file_default("query_directive")
}

///|
test "query roundtrip mutation directive" {
  query_roundtrip_file_default("mutation_directive")
}

///|
test "query roundtrip mutation nameless vars" {
  query_roundtrip_file_default("mutation_nameless_vars")
}

///|
test "query roundtrip subscription directive" {
  query_roundtrip_file_default("subscription_directive")
}

///|
test "query roundtrip string literal" {
  query_roundtrip_file_default("string_literal")
}

///|
test "query roundtrip triple quoted literal" {
  query_roundtrip_file_default("triple_quoted_literal")
}

///|
test "query roundtrip list argument" {
  query_roundtrip_file_default("query_list_argument")
}

///|
test "query roundtrip object argument" {
  query_roundtrip_file_default("query_object_argument")
}

///|
test "query roundtrip object argument multiline" {
  query_roundtrip_file_multiline_args("query_object_argument_multiline")
}

///|
test "query roundtrip array argument multiline" {
  query_roundtrip_file_multiline_args("query_array_argument_multiline")
}

///|
test "query roundtrip nested selection" {
  query_roundtrip_file_default("nested_selection")
}

///|
test "query roundtrip inline fragment" {
  query_roundtrip_file_default("inline_fragment")
}

///|
test "query roundtrip inline fragment directive" {
  query_roundtrip_file_default("inline_fragment_dir")
}

///|
test "query roundtrip fragment spread" {
  query_roundtrip_file_default("fragment_spread")
}

///|
test "query roundtrip minimal mutation" {
  query_roundtrip_file_default("minimal_mutation")
}

///|
test "query roundtrip fragment" {
  query_roundtrip_file_default("fragment")
}

///|
test "query roundtrip directive args" {
  query_roundtrip_file_default("directive_args")
}

///|
test "query roundtrip directive args multiline" {
  query_roundtrip_file_multiline_args("directive_args_multiline")
}

///|
test "query canonical kitchen sink" {
  query_canonical_file("kitchen-sink")
}
