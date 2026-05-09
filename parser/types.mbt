///|
/// 1-based source position in a GraphQL document.
pub(all) struct Pos {
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Error raised by tokenizer, query parser, and schema parser.
///
/// Each parse error carries the source position where parsing failed.
pub(all) suberror ParseError {
  GraphQLParseError(String, Pos)
} derive(Eq)

///|
/// Render a parse error with line and column context.
pub fn ParseError::to_string(self : ParseError) -> String {
  match self {
    GraphQLParseError(message, { line, column }) =>
      "graphql parse error at \{line}:\{column}: \{message}"
  }
}

///|
pub impl Show for ParseError with output(self : ParseError, logger : &Logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn[T] parse_error(message : String, position : Pos) -> T raise ParseError {
  raise GraphQLParseError(message, position)
}

///|
/// Integer literal wrapper.
///
/// GraphQL integer literals are parsed as `Int64` so tooling can preserve the
/// full accepted input range before application-level coercion.
pub(all) struct Number {
  value : Int64
} derive(Eq, Debug)

///|
/// Return the parsed integer literal as `Int64`.
pub fn Number::as_int64(self : Number) -> Int64 {
  self.value
}

///|
/// GraphQL type reference used by variable, field, and input definitions.
pub(all) enum GqlType {
  NamedType(String)
  ListType(GqlType)
  NonNullType(GqlType)
} derive(Eq, Debug)

///|
/// GraphQL literal or variable value.
///
/// This representation preserves GraphQL-specific distinctions such as enum
/// values versus strings and variables versus their eventual runtime values.
pub(all) enum Value {
  Variable(String)
  IntValue(Number)
  FloatValue(Double)
  StringValue(String)
  BooleanValue(Bool)
  NullValue
  EnumValue(String)
  ListValue(Array[Value])
  ObjectValue(Array[(String, Value)])
} derive(Eq, Debug)

///|
/// GraphQL directive use with parsed arguments.
pub(all) struct Directive {
  position : Pos
  name : String
  arguments : Array[(String, Value)]
} derive(Eq, Debug)

///|
/// Parsed executable GraphQL document.
pub(all) struct QueryDocument {
  definitions : Array[QueryDefinition]
} derive(Eq, Debug)

///|
/// Top-level executable document definition.
pub(all) enum QueryDefinition {
  OperationDefinition(OperationDefinition)
  FragmentDefinition(FragmentDefinition)
} derive(Eq, Debug)

///|
/// GraphQL operation definition, including shorthand selection-set operations.
pub(all) enum OperationDefinition {
  SelectionSetOperation(SelectionSet)
  QueryOperation(Query)
  MutationOperation(Mutation)
  SubscriptionOperation(Subscription)
} derive(Eq, Debug)

///|
/// Named fragment definition.
pub(all) struct FragmentDefinition {
  position : Pos
  name : String
  type_condition : TypeCondition
  directives : Array[Directive]
  selection_set : SelectionSet
} derive(Eq, Debug)

///|
/// Parsed `query` operation.
pub(all) struct Query {
  position : Pos
  name : String?
  variable_definitions : Array[VariableDefinition]
  directives : Array[Directive]
  selection_set : SelectionSet
} derive(Eq, Debug)

///|
/// Parsed `mutation` operation.
pub(all) struct Mutation {
  position : Pos
  name : String?
  variable_definitions : Array[VariableDefinition]
  directives : Array[Directive]
  selection_set : SelectionSet
} derive(Eq, Debug)

///|
/// Parsed `subscription` operation.
pub(all) struct Subscription {
  position : Pos
  name : String?
  variable_definitions : Array[VariableDefinition]
  directives : Array[Directive]
  selection_set : SelectionSet
} derive(Eq, Debug)

///|
/// Non-empty selection set with start and end source positions.
pub(all) struct SelectionSet {
  span : (Pos, Pos)
  items : Array[Selection]
} derive(Eq, Debug)

///|
/// Variable declaration from an operation definition.
pub(all) struct VariableDefinition {
  position : Pos
  name : String
  var_type : GqlType
  default_value : Value?
} derive(Eq, Debug)

///|
/// GraphQL field, fragment spread, or inline fragment selection.
pub(all) enum Selection {
  FieldSelection(Field)
  FragmentSpreadSelection(FragmentSpread)
  InlineFragmentSelection(InlineFragment)
} derive(Eq, Debug)

///|
/// Field selection with optional alias, arguments, directives, and nested
/// selection set.
pub(all) struct Field {
  position : Pos
  field_alias : String?
  name : String
  arguments : Array[(String, Value)]
  directives : Array[Directive]
  selection_set : SelectionSet
} derive(Eq, Debug)

///|
/// Reference to a named fragment.
pub(all) struct FragmentSpread {
  position : Pos
  fragment_name : String
  directives : Array[Directive]
} derive(Eq, Debug)

///|
/// Fragment type condition.
pub(all) enum TypeCondition {
  On(String)
} derive(Eq, Debug)

///|
/// Inline fragment with optional type condition.
pub(all) struct InlineFragment {
  position : Pos
  type_condition : TypeCondition?
  directives : Array[Directive]
  selection_set : SelectionSet
} derive(Eq, Debug)

///|
/// Parsed GraphQL schema document.
pub(all) struct SchemaDocument {
  definitions : Array[SchemaDefinition]
} derive(Eq, Debug)

///|
/// Top-level SDL definition.
pub(all) enum SchemaDefinition {
  SchemaDef(SchemaDefinitionData)
  TypeDef(TypeDefinition)
  TypeExt(TypeExtension)
  DirectiveDef(DirectiveDefinition)
} derive(Eq, Debug)

///|
/// Explicit `schema { ... }` root operation mapping.
pub(all) struct SchemaDefinitionData {
  position : Pos
  directives : Array[Directive]
  query : String?
  mutation : String?
  subscription : String?
} derive(Eq, Debug)

///|
/// SDL type definition.
pub(all) enum TypeDefinition {
  ScalarTypeDef(ScalarType)
  ObjectTypeDef(ObjectType)
  InterfaceTypeDef(InterfaceType)
  UnionTypeDef(UnionType)
  EnumTypeDef(EnumType)
  InputObjectTypeDef(InputObjectType)
} derive(Eq, Debug)

///|
/// SDL type extension.
pub(all) enum TypeExtension {
  ScalarTypeExt(ScalarTypeExtension)
  ObjectTypeExt(ObjectTypeExtension)
  InterfaceTypeExt(InterfaceTypeExtension)
  UnionTypeExt(UnionTypeExtension)
  EnumTypeExt(EnumTypeExtension)
  InputObjectTypeExt(InputObjectTypeExtension)
} derive(Eq, Debug)

///|
/// SDL scalar type definition.
pub(all) struct ScalarType {
  position : Pos
  description : String?
  name : String
  directives : Array[Directive]
} derive(Eq, Debug)

///|
/// SDL scalar type extension.
pub(all) struct ScalarTypeExtension {
  position : Pos
  name : String
  directives : Array[Directive]
} derive(Eq, Debug)

///|
/// SDL object type definition.
pub(all) struct ObjectType {
  position : Pos
  description : String?
  name : String
  implements_interfaces : Array[String]
  directives : Array[Directive]
  fields : Array[SchemaField]
} derive(Eq, Debug)

///|
/// SDL object type extension.
pub(all) struct ObjectTypeExtension {
  position : Pos
  name : String
  implements_interfaces : Array[String]
  directives : Array[Directive]
  fields : Array[SchemaField]
} derive(Eq, Debug)

///|
/// SDL object or interface field definition.
pub(all) struct SchemaField {
  position : Pos
  description : String?
  name : String
  arguments : Array[InputValue]
  field_type : GqlType
  directives : Array[Directive]
} derive(Eq, Debug)

///|
/// SDL input field or argument definition.
pub(all) struct InputValue {
  position : Pos
  description : String?
  name : String
  value_type : GqlType
  default_value : Value?
  directives : Array[Directive]
} derive(Eq, Debug)

///|
/// SDL interface type definition.
pub(all) struct InterfaceType {
  position : Pos
  description : String?
  name : String
  implements_interfaces : Array[String]
  directives : Array[Directive]
  fields : Array[SchemaField]
} derive(Eq, Debug)

///|
/// SDL interface type extension.
pub(all) struct InterfaceTypeExtension {
  position : Pos
  name : String
  implements_interfaces : Array[String]
  directives : Array[Directive]
  fields : Array[SchemaField]
} derive(Eq, Debug)

///|
/// SDL union type definition.
pub(all) struct UnionType {
  position : Pos
  description : String?
  name : String
  directives : Array[Directive]
  types : Array[String]
} derive(Eq, Debug)

///|
/// SDL union type extension.
pub(all) struct UnionTypeExtension {
  position : Pos
  name : String
  directives : Array[Directive]
  types : Array[String]
} derive(Eq, Debug)

///|
/// SDL enum type definition.
pub(all) struct EnumType {
  position : Pos
  description : String?
  name : String
  directives : Array[Directive]
  values : Array[EnumValue]
} derive(Eq, Debug)

///|
/// SDL enum value definition.
pub(all) struct EnumValue {
  position : Pos
  description : String?
  name : String
  directives : Array[Directive]
} derive(Eq, Debug)

///|
/// SDL enum type extension.
pub(all) struct EnumTypeExtension {
  position : Pos
  name : String
  directives : Array[Directive]
  values : Array[EnumValue]
} derive(Eq, Debug)

///|
/// SDL input object type definition.
pub(all) struct InputObjectType {
  position : Pos
  description : String?
  name : String
  directives : Array[Directive]
  fields : Array[InputValue]
} derive(Eq, Debug)

///|
/// SDL input object type extension.
pub(all) struct InputObjectTypeExtension {
  position : Pos
  name : String
  directives : Array[Directive]
  fields : Array[InputValue]
} derive(Eq, Debug)

///|
/// GraphQL directive location.
pub(all) enum DirectiveLocation {
  LocationQuery
  LocationMutation
  LocationSubscription
  LocationField
  LocationFragmentDefinition
  LocationFragmentSpread
  LocationInlineFragment
  LocationSchema
  LocationScalar
  LocationObject
  LocationFieldDefinition
  LocationArgumentDefinition
  LocationInterface
  LocationUnion
  LocationEnum
  LocationEnumValue
  LocationInputObject
  LocationInputFieldDefinition
  LocationVariableDefinition
} derive(Eq, Debug)

///|
/// SDL directive definition.
pub(all) struct DirectiveDefinition {
  position : Pos
  description : String?
  name : String
  arguments : Array[InputValue]
  repeatable : Bool
  locations : Array[DirectiveLocation]
} derive(Eq, Debug)

///|
/// Return the canonical GraphQL spec name for a directive location.
pub fn DirectiveLocation::as_string(self : DirectiveLocation) -> String {
  match self {
    LocationQuery => "QUERY"
    LocationMutation => "MUTATION"
    LocationSubscription => "SUBSCRIPTION"
    LocationField => "FIELD"
    LocationFragmentDefinition => "FRAGMENT_DEFINITION"
    LocationFragmentSpread => "FRAGMENT_SPREAD"
    LocationInlineFragment => "INLINE_FRAGMENT"
    LocationSchema => "SCHEMA"
    LocationScalar => "SCALAR"
    LocationObject => "OBJECT"
    LocationFieldDefinition => "FIELD_DEFINITION"
    LocationArgumentDefinition => "ARGUMENT_DEFINITION"
    LocationInterface => "INTERFACE"
    LocationUnion => "UNION"
    LocationEnum => "ENUM"
    LocationEnumValue => "ENUM_VALUE"
    LocationInputObject => "INPUT_OBJECT"
    LocationInputFieldDefinition => "INPUT_FIELD_DEFINITION"
    LocationVariableDefinition => "VARIABLE_DEFINITION"
  }
}

///|
/// Return true when this location belongs to executable GraphQL documents.
pub fn DirectiveLocation::is_query(self : DirectiveLocation) -> Bool {
  match self {
    LocationQuery
    | LocationMutation
    | LocationSubscription
    | LocationField
    | LocationFragmentDefinition
    | LocationFragmentSpread
    | LocationInlineFragment => true
    LocationSchema
    | LocationScalar
    | LocationObject
    | LocationFieldDefinition
    | LocationArgumentDefinition
    | LocationInterface
    | LocationUnion
    | LocationEnum
    | LocationEnumValue
    | LocationInputObject
    | LocationInputFieldDefinition
    | LocationVariableDefinition => false
  }
}

///|
/// Return true when this location belongs to GraphQL SDL.
pub fn DirectiveLocation::is_schema(self : DirectiveLocation) -> Bool {
  !self.is_query()
}

///|
fn parse_directive_location(
  value : String,
  position : Pos,
) -> DirectiveLocation raise ParseError {
  match value {
    "QUERY" => LocationQuery
    "MUTATION" => LocationMutation
    "SUBSCRIPTION" => LocationSubscription
    "FIELD" => LocationField
    "FRAGMENT_DEFINITION" => LocationFragmentDefinition
    "FRAGMENT_SPREAD" => LocationFragmentSpread
    "INLINE_FRAGMENT" => LocationInlineFragment
    "SCHEMA" => LocationSchema
    "SCALAR" => LocationScalar
    "OBJECT" => LocationObject
    "FIELD_DEFINITION" => LocationFieldDefinition
    "ARGUMENT_DEFINITION" => LocationArgumentDefinition
    "INTERFACE" => LocationInterface
    "UNION" => LocationUnion
    "ENUM" => LocationEnum
    "ENUM_VALUE" => LocationEnumValue
    "INPUT_OBJECT" => LocationInputObject
    "INPUT_FIELD_DEFINITION" => LocationInputFieldDefinition
    "VARIABLE_DEFINITION" => LocationVariableDefinition
    _ => parse_error("invalid directive location \{value}", position)
  }
}

///|
/// Pretty-printer options for parsed query and schema documents.
pub(all) struct Style {
  indent : Int
  multiline_arguments : Bool
} derive(Eq, Debug)

///|
/// Default formatting style: two-space indentation and inline arguments.
pub fn Style::default() -> Style {
  { indent: 2, multiline_arguments: false }
}

///|
/// Return a copy of the style with a new indentation width.
pub fn Style::with_indent(self : Style, indent : Int) -> Style {
  { ..self, indent, }
}

///|
/// Return a copy of the style with multiline argument formatting toggled.
pub fn Style::with_multiline_arguments(
  self : Style,
  multiline_arguments : Bool,
) -> Style {
  { ..self, multiline_arguments, }
}
