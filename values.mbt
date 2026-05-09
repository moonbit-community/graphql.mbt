///|
/// GraphQL input value used for variables, literals after coercion, and
/// resolver arguments.
///
/// `InputEnum` preserves the distinction between enum tokens and strings while
/// allowing later coercion against enum definitions.
pub(all) enum InputValue {
  InputNull
  InputString(String)
  InputBoolean(Bool)
  InputInt(Int64)
  InputFloat(Double)
  InputEnum(String)
  InputList(Array[InputValue])
  InputObject(Map[String, InputValue])
} derive(Eq, Debug)

///|
/// Convert an input value into JSON for transport or diagnostics.
pub fn InputValue::to_json(self : InputValue) -> Json {
  match self {
    InputNull => Json::null()
    InputString(value) => Json::string(value)
    InputBoolean(value) => Json::boolean(value)
    InputInt(value) => Json::number(value.to_double(), repr=value.to_string())
    InputFloat(value) => Json::number(value)
    InputEnum(value) => Json::string(value)
    InputList(values) => Json::array(values.map(value => value.to_json()))
    InputObject(fields) => {
      let object : Map[String, Json] = {}
      for name, value in fields.iter2() {
        object[name] = value.to_json()
      }
      Json::object(object)
    }
  }
}

///|
/// Convert JSON request data into GraphQL input values.
///
/// JSON numbers with no fractional component become `InputInt`; other numbers
/// become `InputFloat`. Enum values cannot be represented distinctly in JSON and
/// are therefore parsed as `InputString`.
pub fn InputValue::from_json(json : Json) -> InputValue {
  match json {
    Null => InputNull
    True => InputBoolean(true)
    False => InputBoolean(false)
    Number(value, ..) => {
      let truncated = value.trunc()
      if value == truncated {
        InputInt(truncated.to_int64())
      } else {
        InputFloat(value)
      }
    }
    String(value) => InputString(value)
    Array(values) =>
      InputList(values.map(value => InputValue::from_json(value)))
    Object(fields) => {
      let object : Map[String, InputValue] = {}
      for name, value in fields.iter2() {
        object[name] = InputValue::from_json(value)
      }
      InputObject(object)
    }
  }
}

///|
/// Runtime value returned by resolvers and completed into GraphQL response data.
///
/// Use scalar variants for leaf fields, `GqlObject` for object-like values, and
/// `GqlTypedObject` when interface or union completion needs an explicit
/// runtime type.
pub(all) enum GqlValue {
  GqlNull
  GqlString(String)
  GqlBoolean(Bool)
  GqlInt(Int)
  GqlInt64(Int64)
  GqlFloat(Double)
  GqlEnum(String)
  GqlList(Array[GqlValue])
  GqlObject(Map[String, GqlValue])
  GqlTypedObject(String, Map[String, GqlValue])
} derive(Eq, Debug)

///|
/// Construct an object value from a compact field array.
pub fn GqlValue::object(fields : ArrayView[(String, GqlValue)]) -> GqlValue {
  GqlObject(Map::from_array(fields))
}

///|
/// Construct an object value with an explicit GraphQL runtime type.
///
/// This is required when returning interface or union members whose concrete
/// type cannot be inferred from the field's declared type.
pub fn GqlValue::typed_object(
  type_name : String,
  fields : ArrayView[(String, GqlValue)],
) -> GqlValue {
  GqlTypedObject(type_name, Map::from_array(fields))
}

///|
/// Convert a completed GraphQL runtime value into JSON response data.
pub fn GqlValue::to_json(self : GqlValue) -> Json {
  match self {
    GqlNull => Json::null()
    GqlString(value) => Json::string(value)
    GqlBoolean(value) => Json::boolean(value)
    GqlInt(value) => Json::number(value.to_double(), repr=value.to_string())
    GqlInt64(value) => Json::number(value.to_double(), repr=value.to_string())
    GqlFloat(value) => Json::number(value)
    GqlEnum(value) => Json::string(value)
    GqlList(values) => Json::array(values.map(value => value.to_json()))
    GqlObject(fields) | GqlTypedObject(_, fields) => {
      let object : Map[String, Json] = {}
      for name, value in fields.iter2() {
        object[name] = value.to_json()
      }
      Json::object(object)
    }
  }
}

///|
/// Read a field from `GqlObject` or `GqlTypedObject`.
///
/// The executor uses this as the default resolver when no explicit field
/// resolver is registered.
pub fn GqlValue::field(self : GqlValue, name : String) -> GqlValue? {
  match self {
    GqlObject(fields) | GqlTypedObject(_, fields) => fields.get(name)
    _ => None
  }
}

///|
/// Return the explicit runtime type carried by a typed object, or `fallback`.
pub fn GqlValue::runtime_type(self : GqlValue, fallback~ : String) -> String {
  match self {
    GqlTypedObject(type_name, _) => type_name
    _ => fallback
  }
}

///|
/// Convert a MoonBit value into a resolver-facing GraphQL runtime value.
pub(open) trait ToGraphQL {
  to_graphql(Self) -> GqlValue
}

///|
/// Convert a coerced GraphQL input value into a MoonBit resolver argument type.
pub(open) trait FromGraphQL {
  from_graphql(InputValue) -> Self raise CoercionError
}

///|
pub impl ToGraphQL for String with to_graphql(self) {
  GqlString(self)
}

///|
pub impl FromGraphQL for String with from_graphql(value) {
  match value {
    InputString(value) | InputEnum(value) => value
    InputInt(value) => value.to_string()
    _ => coercion_error("expected String")
  }
}

///|
pub impl ToGraphQL for Bool with to_graphql(self) {
  GqlBoolean(self)
}

///|
pub impl FromGraphQL for Bool with from_graphql(value) {
  match value {
    InputBoolean(value) => value
    _ => coercion_error("expected Boolean")
  }
}

///|
pub impl ToGraphQL for Int with to_graphql(self) {
  GqlInt(self)
}

///|
pub impl FromGraphQL for Int with from_graphql(value) {
  match value {
    InputInt(value) => value.to_int()
    _ => coercion_error("expected Int")
  }
}

///|
pub impl ToGraphQL for Int64 with to_graphql(self) {
  GqlInt64(self)
}

///|
pub impl FromGraphQL for Int64 with from_graphql(value) {
  match value {
    InputInt(value) => value
    _ => coercion_error("expected Int64")
  }
}

///|
pub impl ToGraphQL for Double with to_graphql(self) {
  GqlFloat(self)
}

///|
pub impl FromGraphQL for Double with from_graphql(value) {
  match value {
    InputFloat(value) => value
    InputInt(value) => value.to_double()
    _ => coercion_error("expected Float")
  }
}

///|
pub impl ToGraphQL for Json with to_graphql(self) {
  gql_value_from_json(self)
}

///|
pub impl FromGraphQL for Json with from_graphql(value) {
  value.to_json()
}

///|
pub impl[T : ToGraphQL] ToGraphQL for T? with to_graphql(self) {
  match self {
    None => GqlNull
    Some(value) => value.to_graphql()
  }
}

///|
pub impl[T : FromGraphQL] FromGraphQL for T? with from_graphql(value) {
  match value {
    InputNull => None
    _ => Some(FromGraphQL::from_graphql(value))
  }
}

///|
pub impl[T : ToGraphQL] ToGraphQL for Array[T] with to_graphql(self) {
  GqlList(self.map(value => value.to_graphql()))
}

///|
pub impl[T : FromGraphQL] FromGraphQL for Array[T] with from_graphql(value) {
  match value {
    InputList(values) => values.map(value => FromGraphQL::from_graphql(value))
    _ => [FromGraphQL::from_graphql(value)]
  }
}

///|
/// Convert arbitrary JSON into a GraphQL response value.
///
/// This supports custom scalar resolvers and the internal introspection bridge.
fn gql_value_from_json(json : Json) -> GqlValue {
  match json {
    Null => GqlNull
    True => GqlBoolean(true)
    False => GqlBoolean(false)
    Number(value, ..) => GqlFloat(value)
    String(value) => GqlString(value)
    Array(values) => GqlList(values.map(value => gql_value_from_json(value)))
    Object(fields) => {
      let object : Map[String, GqlValue] = {}
      for name, value in fields.iter2() {
        object[name] = gql_value_from_json(value)
      }
      GqlObject(object)
    }
  }
}

///|
/// Segment in a GraphQL response error path.
pub(all) enum PathSegment {
  PathField(String)
  PathIndex(Int)
} derive(Eq, Debug)

///|
/// Convert a path segment into the JSON representation used in GraphQL errors.
pub fn PathSegment::to_json(self : PathSegment) -> Json {
  match self {
    PathField(name) => Json::string(name)
    PathIndex(index) => Json::number(index.to_double(), repr=index.to_string())
  }
}

///|
/// 1-based source location used in GraphQL errors.
pub(all) struct SourceLocation {
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Convert a source location into the JSON representation used in errors.
pub fn SourceLocation::to_json(self : SourceLocation) -> Json {
  Json::object({ "line": self.line.to_json(), "column": self.column.to_json() })
}

///|
/// GraphQL error entry with message, optional path, and optional source
/// locations.
pub(all) struct GraphQLError {
  message : String
  path : Array[PathSegment]
  locations : Array[SourceLocation]
} derive(Eq, Debug)

///|
/// Create a GraphQL error, defaulting absent path and locations to empty arrays.
pub fn GraphQLError::new(
  message : String,
  path? : Array[PathSegment],
  locations? : Array[SourceLocation],
) -> GraphQLError {
  { message, path: path.unwrap_or([]), locations: locations.unwrap_or([]) }
}

///|
/// Convert a GraphQL error into the standard JSON response shape.
pub fn GraphQLError::to_json(self : GraphQLError) -> Json {
  let object : Map[String, Json] = { "message": Json::string(self.message) }
  if !self.path.is_empty() {
    object["path"] = Json::array(self.path.map(segment => segment.to_json()))
  }
  if !self.locations.is_empty() {
    object["locations"] = Json::array(self.locations.map(loc => loc.to_json()))
  }
  Json::object(object)
}

///|
/// Executable GraphQL request.
///
/// `query` contains the operation document, `operation_name` selects one
/// operation from multi-operation documents, and `variables` holds JSON-style
/// GraphQL input values keyed by variable name without the leading `$`.
pub(all) struct GraphQLRequest {
  query : String
  operation_name : String?
  variables : Map[String, InputValue]
} derive(Eq, Debug)

///|
/// Build a request with empty variables by default.
pub fn GraphQLRequest::new(
  query : String,
  operation_name? : String,
  variables? : Map[String, InputValue],
) -> GraphQLRequest {
  { query, operation_name, variables: variables.unwrap_or({}) }
}

///|
/// GraphQL execution response.
///
/// Successful field data is stored in `data`; parse, validation, coercion, and
/// resolver failures are accumulated in `errors`.
pub(all) struct GraphQLResponse {
  data : GqlValue?
  errors : Array[GraphQLError]
} derive(Eq, Debug)

///|
/// Create a response containing only `data`.
pub fn GraphQLResponse::data(data : GqlValue) -> GraphQLResponse {
  { data: Some(data), errors: [] }
}

///|
/// Create a response containing a single top-level error message.
pub fn GraphQLResponse::error(message : String) -> GraphQLResponse {
  { data: None, errors: [GraphQLError::new(message)] }
}

///|
/// Convert the response into the standard GraphQL JSON envelope.
pub fn GraphQLResponse::to_json(self : GraphQLResponse) -> Json {
  let object : Map[String, Json] = {}
  match self.data {
    Some(data) => object["data"] = data.to_json()
    None => ()
  }
  if !self.errors.is_empty() {
    object["errors"] = Json::array(self.errors.map(error => error.to_json()))
  }
  Json::object(object)
}
