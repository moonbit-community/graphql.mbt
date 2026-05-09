///|
priv struct Formatter {
  buf : StringBuilder
  style : Style
  mut indent : Int
}

///|
fn Formatter::new(style : Style) -> Formatter {
  { buf: StringBuilder::new(size_hint=1024), style, indent: 0 }
}

///|
fn Formatter::to_string(self : Formatter) -> String {
  self.buf.to_string()
}

///|
fn Formatter::write(self : Formatter, value : String) -> Unit {
  self.buf.write_string(value)
}

///|
fn Formatter::write_char(self : Formatter, value : Char) -> Unit {
  self.buf.write_char(value)
}

///|
fn Formatter::write_indent(self : Formatter) -> Unit {
  for _ in 0..<self.indent {
    self.buf.write_char(' ')
  }
}

///|
fn Formatter::endline(self : Formatter) -> Unit {
  self.buf.write_char('\n')
}

///|
fn Formatter::inc_indent(self : Formatter) -> Unit {
  self.indent += self.style.indent
}

///|
fn Formatter::dec_indent(self : Formatter) -> Unit {
  self.indent -= self.style.indent
}

///|
fn Formatter::start_argument_block(self : Formatter, open_char : Char) -> Unit {
  self.buf.write_char(open_char)
  if self.style.multiline_arguments {
    self.inc_indent()
  }
}

///|
fn Formatter::end_argument_block(self : Formatter, close_char : Char) -> Unit {
  if self.style.multiline_arguments {
    self.endline()
    self.dec_indent()
    self.write_indent()
  }
  self.buf.write_char(close_char)
}

///|
fn Formatter::start_argument(self : Formatter) -> Unit {
  if self.style.multiline_arguments {
    self.endline()
    self.write_indent()
  }
}

///|
fn Formatter::delineate_argument(self : Formatter) -> Unit {
  self.buf.write_char(',')
  if !self.style.multiline_arguments {
    self.buf.write_char(' ')
  }
}

///|
fn Formatter::start_block(self : Formatter) -> Unit {
  self.write("{")
  self.endline()
  self.inc_indent()
}

///|
fn Formatter::end_block(self : Formatter) -> Unit {
  self.dec_indent()
  self.write_indent()
  self.write("}")
  self.endline()
}

///|
fn Formatter::margin(self : Formatter) -> Unit {
  if !self.buf.is_empty() {
    self.endline()
  }
}

///|
fn Formatter::write_quoted(self : Formatter, value : String) -> Unit {
  let mut has_newline = false
  let mut has_nonprintable = false
  for c in value.iter() {
    if c == '\n' {
      has_newline = true
    } else if c == '\r' ||
      c == '\t' ||
      (c.to_int() >= 0x20 && c.to_int() <= 0xffff) {
      ()
    } else {
      has_nonprintable = true
    }
  }
  if !has_newline || has_nonprintable {
    self.write("\"")
    for c in value.iter() {
      match c {
        '\r' => self.write("\\r")
        '\n' => self.write("\\n")
        '\t' => self.write("\\t")
        '"' => self.write("\\\"")
        '\\' => self.write("\\\\")
        _ if c.to_int() >= 0x20 && c.to_int() <= 0xffff => self.write_char(c)
        _ => {
          let hex = c.to_int().to_string(radix=16)
          self.write("\\u")
          for _ in 0..<(4 - hex.length()) {
            self.write("0")
          }
          self.write(hex)
        }
      }
    }
    self.write("\"")
  } else {
    self.write("\"\"\"")
    self.endline()
    self.inc_indent()
    for line in rust_lines(value) {
      if !line.trim().is_empty() {
        self.write_indent()
        self.write(line.replace_all(old="\"\"\"", new="\\\"\"\""))
      }
      self.endline()
    }
    self.dec_indent()
    self.write_indent()
    self.write("\"\"\"")
  }
}

///|
/// Format an executable GraphQL document with a stable canonical layout.
pub fn QueryDocument::format(
  self : QueryDocument,
  style? : Style = Style::default(),
) -> String {
  let formatter = Formatter::new(style)
  self.display(formatter)
  formatter.to_string()
}

///|
/// Format an executable GraphQL document using the default style.
pub fn QueryDocument::to_string(self : QueryDocument) -> String {
  self.format()
}

///|
pub impl Show for QueryDocument with output(
  self : QueryDocument,
  logger : &Logger,
) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn QueryDocument::display(self : QueryDocument, formatter : Formatter) -> Unit {
  for item in self.definitions {
    item.display(formatter)
  }
}

///|
fn QueryDefinition::display(
  self : QueryDefinition,
  formatter : Formatter,
) -> Unit {
  match self {
    OperationDefinition(op) => op.display(formatter)
    FragmentDefinition(fragment) => fragment.display(formatter)
  }
}

///|
fn OperationDefinition::display(
  self : OperationDefinition,
  formatter : Formatter,
) -> Unit {
  match self {
    SelectionSetOperation(set) => set.display(formatter)
    QueryOperation(query) => query.display(formatter)
    MutationOperation(mutation) => mutation.display(formatter)
    SubscriptionOperation(subscription) => subscription.display(formatter)
  }
}

///|
fn FragmentDefinition::display(
  self : FragmentDefinition,
  formatter : Formatter,
) -> Unit {
  formatter.margin()
  formatter.write_indent()
  formatter.write("fragment ")
  formatter.write(self.name)
  formatter.write(" ")
  self.type_condition.display(formatter)
  display_directives(self.directives, formatter)
  formatter.write(" ")
  formatter.start_block()
  for item in self.selection_set.items {
    item.display(formatter)
  }
  formatter.end_block()
}

///|
fn SelectionSet::display(self : SelectionSet, formatter : Formatter) -> Unit {
  formatter.margin()
  formatter.write_indent()
  formatter.start_block()
  for item in self.items {
    item.display(formatter)
  }
  formatter.end_block()
}

///|
fn Selection::display(self : Selection, formatter : Formatter) -> Unit {
  match self {
    FieldSelection(field) => field.display(formatter)
    FragmentSpreadSelection(fragment) => fragment.display(formatter)
    InlineFragmentSelection(fragment) => fragment.display(formatter)
  }
}

///|
fn display_query_arguments(
  arguments : Array[(String, Value)],
  formatter : Formatter,
) -> Unit {
  if !arguments.is_empty() {
    formatter.start_argument_block('(')
    formatter.start_argument()
    formatter.write(arguments[0].0)
    formatter.write(": ")
    arguments[0].1.display(formatter)
    for arg in arguments.view(start=1) {
      formatter.delineate_argument()
      formatter.start_argument()
      formatter.write(arg.0)
      formatter.write(": ")
      arg.1.display(formatter)
    }
    formatter.end_argument_block(')')
  }
}

///|
fn Field::display(self : Field, formatter : Formatter) -> Unit {
  formatter.write_indent()
  match self.field_alias {
    Some(alias_value) => {
      formatter.write(alias_value)
      formatter.write(": ")
    }
    None => ()
  }
  formatter.write(self.name)
  display_query_arguments(self.arguments, formatter)
  display_directives(self.directives, formatter)
  if !self.selection_set.items.is_empty() {
    formatter.write(" ")
    formatter.start_block()
    for item in self.selection_set.items {
      item.display(formatter)
    }
    formatter.end_block()
  } else {
    formatter.endline()
  }
}

///|
fn Query::display(self : Query, formatter : Formatter) -> Unit {
  formatter.margin()
  formatter.write_indent()
  formatter.write("query")
  match self.name {
    Some(name) => {
      formatter.write(" ")
      formatter.write(name)
    }
    None => ()
  }
  display_variable_definitions(self.variable_definitions, formatter)
  display_directives(self.directives, formatter)
  formatter.write(" ")
  formatter.start_block()
  for item in self.selection_set.items {
    item.display(formatter)
  }
  formatter.end_block()
}

///|
fn Mutation::display(self : Mutation, formatter : Formatter) -> Unit {
  formatter.margin()
  formatter.write_indent()
  formatter.write("mutation")
  match self.name {
    Some(name) => {
      formatter.write(" ")
      formatter.write(name)
    }
    None => ()
  }
  display_variable_definitions(self.variable_definitions, formatter)
  display_directives(self.directives, formatter)
  formatter.write(" ")
  formatter.start_block()
  for item in self.selection_set.items {
    item.display(formatter)
  }
  formatter.end_block()
}

///|
fn Subscription::display(self : Subscription, formatter : Formatter) -> Unit {
  formatter.margin()
  formatter.write_indent()
  formatter.write("subscription")
  match self.name {
    Some(name) => {
      formatter.write(" ")
      formatter.write(name)
      display_variable_definitions(self.variable_definitions, formatter)
    }
    None => ()
  }
  display_directives(self.directives, formatter)
  formatter.write(" ")
  formatter.start_block()
  for item in self.selection_set.items {
    item.display(formatter)
  }
  formatter.end_block()
}

///|
fn display_variable_definitions(
  variables : Array[VariableDefinition],
  formatter : Formatter,
) -> Unit {
  if !variables.is_empty() {
    formatter.write("(")
    variables[0].display(formatter)
    for variable in variables.view(start=1) {
      formatter.write(", ")
      variable.display(formatter)
    }
    formatter.write(")")
  }
}

///|
fn VariableDefinition::display(
  self : VariableDefinition,
  formatter : Formatter,
) -> Unit {
  formatter.write("$")
  formatter.write(self.name)
  formatter.write(": ")
  self.var_type.display(formatter)
  match self.default_value {
    Some(value) => {
      formatter.write(" = ")
      value.display(formatter)
    }
    None => ()
  }
}

///|
fn GqlType::display(self : GqlType, formatter : Formatter) -> Unit {
  match self {
    NamedType(name) => formatter.write(name)
    ListType(typ) => {
      formatter.write("[")
      typ.display(formatter)
      formatter.write("]")
    }
    NonNullType(typ) => {
      typ.display(formatter)
      formatter.write("!")
    }
  }
}

///|
fn Value::display(self : Value, formatter : Formatter) -> Unit {
  match self {
    Variable(name) => {
      formatter.write("$")
      formatter.write(name)
    }
    IntValue(number) => formatter.write(number.value.to_string())
    FloatValue(value) => formatter.write(value.to_string())
    StringValue(value) => formatter.write_quoted(value)
    BooleanValue(true) => formatter.write("true")
    BooleanValue(false) => formatter.write("false")
    NullValue => formatter.write("null")
    EnumValue(name) => formatter.write(name)
    ListValue(items) => {
      formatter.start_argument_block('[')
      if !items.is_empty() {
        formatter.start_argument()
        items[0].display(formatter)
        for item in items.view(start=1) {
          formatter.delineate_argument()
          formatter.start_argument()
          item.display(formatter)
        }
      }
      formatter.end_argument_block(']')
    }
    ObjectValue(items) => {
      formatter.start_argument_block('{')
      let sorted = items.copy()
      sorted.sort_by((left, right) => left.0.lexical_compare(right.0))
      let mut first = true
      for item in sorted {
        if first {
          first = false
        } else {
          formatter.delineate_argument()
        }
        formatter.start_argument()
        formatter.write(item.0)
        formatter.write(": ")
        item.1.display(formatter)
      }
      formatter.end_argument_block('}')
    }
  }
}

///|
fn InlineFragment::display(
  self : InlineFragment,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("...")
  match self.type_condition {
    Some(cond) => {
      formatter.write(" ")
      cond.display(formatter)
    }
    None => ()
  }
  display_directives(self.directives, formatter)
  formatter.write(" ")
  formatter.start_block()
  for item in self.selection_set.items {
    item.display(formatter)
  }
  formatter.end_block()
}

///|
fn TypeCondition::display(self : TypeCondition, formatter : Formatter) -> Unit {
  match self {
    On(name) => {
      formatter.write("on ")
      formatter.write(name)
    }
  }
}

///|
fn FragmentSpread::display(
  self : FragmentSpread,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("...")
  formatter.write(self.fragment_name)
  display_directives(self.directives, formatter)
  formatter.endline()
}

///|
fn Directive::display(self : Directive, formatter : Formatter) -> Unit {
  formatter.write("@")
  formatter.write(self.name)
  display_query_arguments(self.arguments, formatter)
}

///|
fn display_directives(
  directives : Array[Directive],
  formatter : Formatter,
) -> Unit {
  for directive in directives {
    formatter.write(" ")
    directive.display(formatter)
  }
}

///|
/// Format an SDL document with a stable canonical layout.
pub fn SchemaDocument::format(
  self : SchemaDocument,
  style? : Style = Style::default(),
) -> String {
  let formatter = Formatter::new(style)
  self.display(formatter)
  formatter.to_string()
}

///|
/// Format an SDL document using the default style.
pub fn SchemaDocument::to_string(self : SchemaDocument) -> String {
  self.format()
}

///|
pub impl Show for SchemaDocument with output(
  self : SchemaDocument,
  logger : &Logger,
) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn SchemaDocument::display(
  self : SchemaDocument,
  formatter : Formatter,
) -> Unit {
  for item in self.definitions {
    item.display(formatter)
  }
}

///|
fn SchemaDefinition::display(
  self : SchemaDefinition,
  formatter : Formatter,
) -> Unit {
  formatter.margin()
  match self {
    SchemaDef(schema) => schema.display(formatter)
    TypeDef(definition) => definition.display(formatter)
    TypeExt(extension) => extension.display(formatter)
    DirectiveDef(directive) => directive.display(formatter)
  }
}

///|
fn SchemaDefinitionData::display(
  self : SchemaDefinitionData,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("schema")
  display_directives(self.directives, formatter)
  formatter.write(" ")
  formatter.start_block()
  match self.query {
    Some(name) => {
      formatter.write_indent()
      formatter.write("query: ")
      formatter.write(name)
      formatter.endline()
    }
    None => ()
  }
  match self.mutation {
    Some(name) => {
      formatter.write_indent()
      formatter.write("mutation: ")
      formatter.write(name)
      formatter.endline()
    }
    None => ()
  }
  match self.subscription {
    Some(name) => {
      formatter.write_indent()
      formatter.write("subscription: ")
      formatter.write(name)
      formatter.endline()
    }
    None => ()
  }
  formatter.end_block()
}

///|
fn TypeDefinition::display(
  self : TypeDefinition,
  formatter : Formatter,
) -> Unit {
  match self {
    ScalarTypeDef(scalar) => scalar.display(formatter)
    ObjectTypeDef(object) => object.display(formatter)
    InterfaceTypeDef(interface_) => interface_.display(formatter)
    UnionTypeDef(union_) => union_.display(formatter)
    EnumTypeDef(enum_) => enum_.display(formatter)
    InputObjectTypeDef(input) => input.display(formatter)
  }
}

///|
fn display_description(description : String?, formatter : Formatter) -> Unit {
  match description {
    Some(value) => {
      formatter.write_indent()
      formatter.write_quoted(value)
      formatter.endline()
    }
    None => ()
  }
}

///|
fn ScalarType::display(self : ScalarType, formatter : Formatter) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("scalar ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  formatter.endline()
}

///|
fn ScalarTypeExtension::display(
  self : ScalarTypeExtension,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("extend scalar ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  formatter.endline()
}

///|
fn display_schema_fields(
  fields : Array[SchemaField],
  formatter : Formatter,
) -> Unit {
  if !fields.is_empty() {
    formatter.write(" ")
    formatter.start_block()
    for field in fields {
      field.display(formatter)
    }
    formatter.end_block()
  } else {
    formatter.endline()
  }
}

///|
fn display_implements(
  interfaces : Array[String],
  formatter : Formatter,
) -> Unit {
  if !interfaces.is_empty() {
    formatter.write(" implements ")
    formatter.write(interfaces[0])
    for name in interfaces.view(start=1) {
      formatter.write(" & ")
      formatter.write(name)
    }
  }
}

///|
fn ObjectType::display(self : ObjectType, formatter : Formatter) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("type ")
  formatter.write(self.name)
  display_implements(self.implements_interfaces, formatter)
  display_directives(self.directives, formatter)
  display_schema_fields(self.fields, formatter)
}

///|
fn ObjectTypeExtension::display(
  self : ObjectTypeExtension,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("extend type ")
  formatter.write(self.name)
  display_implements(self.implements_interfaces, formatter)
  display_directives(self.directives, formatter)
  display_schema_fields(self.fields, formatter)
}

///|
fn InputValue::display(self : InputValue, formatter : Formatter) -> Unit {
  match self.description {
    Some(value) => {
      formatter.write_quoted(value)
      formatter.write(" ")
    }
    None => ()
  }
  formatter.write(self.name)
  formatter.write(": ")
  self.value_type.display(formatter)
  match self.default_value {
    Some(value) => {
      formatter.write(" = ")
      value.display(formatter)
    }
    None => ()
  }
  display_directives(self.directives, formatter)
}

///|
fn display_input_arguments(
  arguments : Array[InputValue],
  formatter : Formatter,
) -> Unit {
  if !arguments.is_empty() {
    formatter.write("(")
    arguments[0].display(formatter)
    for arg in arguments.view(start=1) {
      formatter.write(", ")
      arg.display(formatter)
    }
    formatter.write(")")
  }
}

///|
fn SchemaField::display(self : SchemaField, formatter : Formatter) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write(self.name)
  display_input_arguments(self.arguments, formatter)
  formatter.write(": ")
  self.field_type.display(formatter)
  display_directives(self.directives, formatter)
  formatter.endline()
}

///|
fn InterfaceType::display(self : InterfaceType, formatter : Formatter) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("interface ")
  formatter.write(self.name)
  display_implements(self.implements_interfaces, formatter)
  display_directives(self.directives, formatter)
  display_schema_fields(self.fields, formatter)
}

///|
fn InterfaceTypeExtension::display(
  self : InterfaceTypeExtension,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("extend interface ")
  formatter.write(self.name)
  display_implements(self.implements_interfaces, formatter)
  display_directives(self.directives, formatter)
  display_schema_fields(self.fields, formatter)
}

///|
fn UnionType::display(self : UnionType, formatter : Formatter) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("union ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  display_union_members(self.types, formatter)
  formatter.endline()
}

///|
fn UnionTypeExtension::display(
  self : UnionTypeExtension,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("extend union ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  display_union_members(self.types, formatter)
  formatter.endline()
}

///|
fn display_union_members(types : Array[String], formatter : Formatter) -> Unit {
  if !types.is_empty() {
    formatter.write(" = ")
    formatter.write(types[0])
    for typ in types.view(start=1) {
      formatter.write(" | ")
      formatter.write(typ)
    }
  }
}

///|
fn EnumType::display(self : EnumType, formatter : Formatter) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("enum ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  display_enum_values(self.values, formatter, false)
}

///|
fn EnumTypeExtension::display(
  self : EnumTypeExtension,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("extend enum ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  display_enum_values(self.values, formatter, false)
}

///|
fn display_enum_values(
  values : Array[EnumValue],
  formatter : Formatter,
  _input_style : Bool,
) -> Unit {
  if !values.is_empty() {
    formatter.write(" ")
    formatter.start_block()
    for value in values {
      formatter.write_indent()
      match value.description {
        Some(description) => {
          formatter.write_quoted(description)
          formatter.write(" ")
        }
        None => ()
      }
      formatter.write(value.name)
      display_directives(value.directives, formatter)
      formatter.endline()
    }
    formatter.end_block()
  } else {
    formatter.endline()
  }
}

///|
fn display_input_fields(
  fields : Array[InputValue],
  formatter : Formatter,
) -> Unit {
  if !fields.is_empty() {
    formatter.write(" ")
    formatter.start_block()
    for field in fields {
      formatter.write_indent()
      field.display(formatter)
      formatter.endline()
    }
    formatter.end_block()
  } else {
    formatter.endline()
  }
}

///|
fn InputObjectType::display(
  self : InputObjectType,
  formatter : Formatter,
) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("input ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  display_input_fields(self.fields, formatter)
}

///|
fn InputObjectTypeExtension::display(
  self : InputObjectTypeExtension,
  formatter : Formatter,
) -> Unit {
  formatter.write_indent()
  formatter.write("extend input ")
  formatter.write(self.name)
  display_directives(self.directives, formatter)
  display_input_fields(self.fields, formatter)
}

///|
fn TypeExtension::display(self : TypeExtension, formatter : Formatter) -> Unit {
  match self {
    ScalarTypeExt(scalar) => scalar.display(formatter)
    ObjectTypeExt(object) => object.display(formatter)
    InterfaceTypeExt(interface_) => interface_.display(formatter)
    UnionTypeExt(union_) => union_.display(formatter)
    EnumTypeExt(enum_) => enum_.display(formatter)
    InputObjectTypeExt(input) => input.display(formatter)
  }
}

///|
fn DirectiveDefinition::display(
  self : DirectiveDefinition,
  formatter : Formatter,
) -> Unit {
  display_description(self.description, formatter)
  formatter.write_indent()
  formatter.write("directive @")
  formatter.write(self.name)
  display_input_arguments(self.arguments, formatter)
  if self.repeatable {
    formatter.write(" repeatable")
  }
  if !self.locations.is_empty() {
    formatter.write(" on ")
    formatter.write(self.locations[0].as_string())
    for location in self.locations.view(start=1) {
      formatter.write(" | ")
      formatter.write(location.as_string())
    }
  }
  formatter.endline()
}
