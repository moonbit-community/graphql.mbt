///|
pub fn parse_schema(source : String) -> SchemaDocument raise ParseError {
  let parser = Parser::new(source)
  let definitions : Array[SchemaDefinition] = []
  if parser.at_eof() {
    parse_error("expected schema definition", parser.peek().position)
  }
  while true {
    if parser.at_eof() {
      break
    }
    definitions.push(parser.parse_schema_definition())
    continue
  }
  parser.expect_eof()
  { definitions, }
}

///|
fn Parser::parse_schema_definition(
  self : Parser,
) -> SchemaDefinition raise ParseError {
  if self.check_ident("schema") {
    SchemaDef(self.parse_schema_root_definition())
  } else if self.check_ident("extend") {
    TypeExt(self.parse_type_extension())
  } else {
    self.parse_described_definition()
  }
}

///|
fn Parser::parse_schema_root_definition(
  self : Parser,
) -> SchemaDefinitionData raise ParseError {
  let position = self.expect_ident("schema").position
  let directives = self.parse_directives()
  ignore(self.expect_punct("{"))
  let mut query : String? = None
  let mut mutation : String? = None
  let mut subscription : String? = None
  while true {
    if self.check_punct("}") {
      ignore(self.take())
      break
    }
    let (operation, op_pos) = self.expect_name()
    ignore(self.expect_punct(":"))
    let (type_name, _) = self.expect_name()
    match operation {
      "query" =>
        match query {
          Some(_) => parse_error("duplicate `query` operation", op_pos)
          None => query = Some(type_name)
        }
      "mutation" =>
        match mutation {
          Some(_) => parse_error("duplicate `mutation` operation", op_pos)
          None => mutation = Some(type_name)
        }
      "subscription" =>
        match subscription {
          Some(_) => parse_error("duplicate `subscription` operation", op_pos)
          None => subscription = Some(type_name)
        }
      _ => parse_error("expected query, mutation or subscription", op_pos)
    }
    continue
  }
  { position, directives, query, mutation, subscription }
}

///|
fn Parser::parse_described_definition(
  self : Parser,
) -> SchemaDefinition raise ParseError {
  let description = if self.peek().kind == TkStringValue ||
    self.peek().kind == TkBlockString {
    Some(self.parse_string_literal())
  } else {
    None
  }
  if self.check_ident("scalar") {
    TypeDef(ScalarTypeDef(self.parse_scalar_type(description)))
  } else if self.check_ident("type") {
    TypeDef(ObjectTypeDef(self.parse_object_type(description)))
  } else if self.check_ident("interface") {
    TypeDef(InterfaceTypeDef(self.parse_interface_type(description)))
  } else if self.check_ident("union") {
    TypeDef(UnionTypeDef(self.parse_union_type(description)))
  } else if self.check_ident("enum") {
    TypeDef(EnumTypeDef(self.parse_enum_type(description)))
  } else if self.check_ident("input") {
    TypeDef(InputObjectTypeDef(self.parse_input_object_type(description)))
  } else if self.check_ident("directive") {
    DirectiveDef(self.parse_directive_definition(description))
  } else {
    let token = self.peek()
    parse_error("expected type or directive definition", token.position)
  }
}

///|
fn Parser::parse_type_extension(
  self : Parser,
) -> TypeExtension raise ParseError {
  ignore(self.expect_ident("extend"))
  if self.check_ident("scalar") {
    ScalarTypeExt(self.parse_scalar_type_extension())
  } else if self.check_ident("type") {
    ObjectTypeExt(self.parse_object_type_extension())
  } else if self.check_ident("interface") {
    InterfaceTypeExt(self.parse_interface_type_extension())
  } else if self.check_ident("union") {
    UnionTypeExt(self.parse_union_type_extension())
  } else if self.check_ident("enum") {
    EnumTypeExt(self.parse_enum_type_extension())
  } else if self.check_ident("input") {
    InputObjectTypeExt(self.parse_input_object_type_extension())
  } else {
    let token = self.peek()
    parse_error("expected type extension", token.position)
  }
}

///|
fn Parser::parse_scalar_type(
  self : Parser,
  description : String?,
) -> ScalarType raise ParseError {
  let position = self.expect_ident("scalar").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  { position, description, name, directives }
}

///|
fn Parser::parse_scalar_type_extension(
  self : Parser,
) -> ScalarTypeExtension raise ParseError {
  let position = self.expect_ident("scalar").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  if directives.is_empty() {
    parse_error(
      "Scalar type extension should contain at least one directive.", position,
    )
  }
  { position, name, directives }
}

///|
fn Parser::parse_implements_interfaces(
  self : Parser,
) -> Array[String] raise ParseError {
  if !self.eat_ident("implements") {
    return []
  }
  ignore(self.eat_punct("&"))
  let interfaces : Array[String] = []
  let (name, _) = self.expect_name()
  interfaces.push(name)
  while true {
    if !self.eat_punct("&") {
      break
    }
    let (name, _) = self.expect_name()
    interfaces.push(name)
    continue
  }
  interfaces
}

///|
fn Parser::parse_input_value(self : Parser) -> InputValue raise ParseError {
  let position = self.peek().position
  let description = if self.peek().kind == TkStringValue ||
    self.peek().kind == TkBlockString {
    Some(self.parse_string_literal())
  } else {
    None
  }
  let (name, _) = self.expect_name()
  ignore(self.expect_punct(":"))
  let value_type = self.parse_type()
  let default_value = if self.eat_punct("=") {
    Some(self.parse_default_value())
  } else {
    None
  }
  let directives = self.parse_directives()
  { position, description, name, value_type, default_value, directives }
}

///|
fn Parser::parse_arguments_definition(
  self : Parser,
) -> Array[InputValue] raise ParseError {
  if !self.eat_punct("(") {
    return []
  }
  let args : Array[InputValue] = []
  if self.check_punct(")") {
    let token = self.peek()
    parse_error("expected argument definition", token.position)
  }
  while true {
    if self.check_punct(")") {
      ignore(self.take())
      break
    }
    args.push(self.parse_input_value())
    continue
  }
  args
}

///|
fn Parser::parse_schema_field(self : Parser) -> SchemaField raise ParseError {
  let position = self.peek().position
  let description = if self.peek().kind == TkStringValue ||
    self.peek().kind == TkBlockString {
    Some(self.parse_string_literal())
  } else {
    None
  }
  let (name, _) = self.expect_name()
  let arguments = self.parse_arguments_definition()
  ignore(self.expect_punct(":"))
  let field_type = self.parse_type()
  let directives = self.parse_directives()
  { position, description, name, arguments, field_type, directives }
}

///|
fn Parser::parse_fields(self : Parser) -> Array[SchemaField] raise ParseError {
  if !self.eat_punct("{") {
    return []
  }
  let fields : Array[SchemaField] = []
  if self.check_punct("}") {
    let token = self.peek()
    parse_error("expected field", token.position)
  }
  while true {
    if self.check_punct("}") {
      ignore(self.take())
      break
    }
    fields.push(self.parse_schema_field())
    continue
  }
  fields
}

///|
fn Parser::parse_object_type(
  self : Parser,
  description : String?,
) -> ObjectType raise ParseError {
  let position = self.expect_ident("type").position
  let (name, _) = self.expect_name()
  let implements_interfaces = self.parse_implements_interfaces()
  let directives = self.parse_directives()
  let fields = self.parse_fields()
  { position, description, name, implements_interfaces, directives, fields }
}

///|
fn Parser::parse_object_type_extension(
  self : Parser,
) -> ObjectTypeExtension raise ParseError {
  let position = self.expect_ident("type").position
  let (name, _) = self.expect_name()
  let implements_interfaces = self.parse_implements_interfaces()
  let directives = self.parse_directives()
  let fields = self.parse_fields()
  if implements_interfaces.is_empty() &&
    directives.is_empty() &&
    fields.is_empty() {
    parse_error(
      "Object type extension should contain at least one interface, directive or field.",
      position,
    )
  }
  { position, name, implements_interfaces, directives, fields }
}

///|
fn Parser::parse_interface_type(
  self : Parser,
  description : String?,
) -> InterfaceType raise ParseError {
  let position = self.expect_ident("interface").position
  let (name, _) = self.expect_name()
  let implements_interfaces = self.parse_implements_interfaces()
  let directives = self.parse_directives()
  let fields = self.parse_fields()
  { position, description, name, implements_interfaces, directives, fields }
}

///|
fn Parser::parse_interface_type_extension(
  self : Parser,
) -> InterfaceTypeExtension raise ParseError {
  let position = self.expect_ident("interface").position
  let (name, _) = self.expect_name()
  let implements_interfaces = self.parse_implements_interfaces()
  let directives = self.parse_directives()
  let fields = self.parse_fields()
  if directives.is_empty() && fields.is_empty() {
    parse_error(
      "Interface type extension should contain at least one directive or field.",
      position,
    )
  }
  { position, name, implements_interfaces, directives, fields }
}

///|
fn Parser::parse_union_members(self : Parser) -> Array[String] raise ParseError {
  ignore(self.eat_punct("|"))
  let types : Array[String] = []
  let (name, _) = self.expect_name()
  types.push(name)
  while true {
    if !self.eat_punct("|") {
      break
    }
    let (name, _) = self.expect_name()
    types.push(name)
    continue
  }
  types
}

///|
fn Parser::parse_union_type(
  self : Parser,
  description : String?,
) -> UnionType raise ParseError {
  let position = self.expect_ident("union").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  let types = if self.eat_punct("=") { self.parse_union_members() } else { [] }
  { position, description, name, directives, types }
}

///|
fn Parser::parse_union_type_extension(
  self : Parser,
) -> UnionTypeExtension raise ParseError {
  let position = self.expect_ident("union").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  let has_members = self.eat_punct("=")
  let types = if has_members { self.parse_union_members() } else { [] }
  if directives.is_empty() && !has_members {
    parse_error(
      "Union type extension should contain at least one directive or type.", position,
    )
  }
  { position, name, directives, types }
}

///|
fn Parser::parse_enum_values(
  self : Parser,
) -> Array[EnumValue] raise ParseError {
  ignore(self.expect_punct("{"))
  let values : Array[EnumValue] = []
  if self.check_punct("}") {
    let token = self.peek()
    parse_error("expected enum value", token.position)
  }
  while true {
    if self.check_punct("}") {
      ignore(self.take())
      break
    }
    let position = self.peek().position
    let description = if self.peek().kind == TkStringValue ||
      self.peek().kind == TkBlockString {
      Some(self.parse_string_literal())
    } else {
      None
    }
    let (name, _) = self.expect_name()
    let directives = self.parse_directives()
    values.push({ position, description, name, directives })
    continue
  }
  values
}

///|
fn Parser::parse_enum_type(
  self : Parser,
  description : String?,
) -> EnumType raise ParseError {
  let position = self.expect_ident("enum").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  let values = if self.check_punct("{") { self.parse_enum_values() } else { [] }
  { position, description, name, directives, values }
}

///|
fn Parser::parse_enum_type_extension(
  self : Parser,
) -> EnumTypeExtension raise ParseError {
  let position = self.expect_ident("enum").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  let has_values = self.check_punct("{")
  let values = if has_values { self.parse_enum_values() } else { [] }
  if directives.is_empty() && !has_values {
    parse_error(
      "Enum type extension should contain at least one directive or value.", position,
    )
  }
  { position, name, directives, values }
}

///|
fn Parser::parse_input_fields(
  self : Parser,
) -> Array[InputValue] raise ParseError {
  if !self.eat_punct("{") {
    return []
  }
  let fields : Array[InputValue] = []
  if self.check_punct("}") {
    let token = self.peek()
    parse_error("expected input field", token.position)
  }
  while true {
    if self.check_punct("}") {
      ignore(self.take())
      break
    }
    fields.push(self.parse_input_value())
    continue
  }
  fields
}

///|
fn Parser::parse_input_object_type(
  self : Parser,
  description : String?,
) -> InputObjectType raise ParseError {
  let position = self.expect_ident("input").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  let fields = self.parse_input_fields()
  { position, description, name, directives, fields }
}

///|
fn Parser::parse_input_object_type_extension(
  self : Parser,
) -> InputObjectTypeExtension raise ParseError {
  let position = self.expect_ident("input").position
  let (name, _) = self.expect_name()
  let directives = self.parse_directives()
  let fields = self.parse_input_fields()
  if directives.is_empty() && fields.is_empty() {
    parse_error(
      "Input object type extension should contain at least one directive or field.",
      position,
    )
  }
  { position, name, directives, fields }
}

///|
fn Parser::parse_directive_locations(
  self : Parser,
) -> Array[DirectiveLocation] raise ParseError {
  if !(self.check_punct("|") || self.check_name()) {
    return []
  }
  ignore(self.eat_punct("|"))
  let locations : Array[DirectiveLocation] = []
  let (name, pos) = self.expect_name()
  locations.push(parse_directive_location(name, pos))
  while true {
    if !self.eat_punct("|") {
      break
    }
    let (name, pos) = self.expect_name()
    locations.push(parse_directive_location(name, pos))
    continue
  }
  locations
}

///|
fn Parser::parse_directive_definition(
  self : Parser,
  description : String?,
) -> DirectiveDefinition raise ParseError {
  let position = self.expect_ident("directive").position
  ignore(self.expect_punct("@"))
  let (name, _) = self.expect_name()
  let arguments = self.parse_arguments_definition()
  let repeatable = self.eat_ident("repeatable")
  ignore(self.expect_ident("on"))
  let locations = self.parse_directive_locations()
  { position, description, name, arguments, repeatable, locations }
}
