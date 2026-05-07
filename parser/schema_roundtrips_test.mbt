///|
test "schema roundtrip minimal" {
  schema_roundtrip_file("minimal")
}

///|
test "schema roundtrip scalar type" {
  schema_roundtrip_file("scalar_type")
}

///|
test "schema roundtrip extend scalar" {
  schema_roundtrip_file("extend_scalar")
}

///|
test "schema roundtrip minimal type" {
  schema_roundtrip_file("minimal_type")
}

///|
test "schema roundtrip implements" {
  schema_roundtrip_file("implements")
}

///|
test "schema canonical implements amp" {
  schema_canonical_file("implements_amp")
}

///|
test "schema roundtrip implements interface" {
  schema_roundtrip_file("implements_interface")
}

///|
test "schema roundtrip simple object" {
  schema_roundtrip_file("simple_object")
}

///|
test "schema roundtrip extend object" {
  schema_roundtrip_file("extend_object")
}

///|
test "schema roundtrip interface" {
  schema_roundtrip_file("interface")
}

///|
test "schema roundtrip extend interface" {
  schema_roundtrip_file("extend_interface")
}

///|
test "schema roundtrip union" {
  schema_roundtrip_file("union")
}

///|
test "schema roundtrip empty union" {
  schema_roundtrip_file("empty_union")
}

///|
test "schema roundtrip union extension" {
  schema_roundtrip_file("union_extension")
}

///|
test "schema roundtrip enum" {
  schema_roundtrip_file("enum")
}

///|
test "schema roundtrip extend enum" {
  schema_roundtrip_file("extend_enum")
}

///|
test "schema roundtrip input type" {
  schema_roundtrip_file("input_type")
}

///|
test "schema canonical extend input" {
  schema_canonical_file("extend_input")
}

///|
test "schema roundtrip directive" {
  schema_roundtrip_file("directive")
}

///|
test "schema canonical kitchen sink" {
  schema_canonical_file("kitchen-sink")
}

///|
test "schema canonical directive descriptions" {
  schema_canonical_file("directive_descriptions")
}

///|
test "schema roundtrip directive variable definition" {
  schema_roundtrip_file("directive_variable_definition")
}

///|
test "schema roundtrip repeatable" {
  schema_roundtrip_file("repeatable")
}
