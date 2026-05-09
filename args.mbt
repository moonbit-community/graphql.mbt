///|
/// Coerced argument map passed to field and subscription resolvers.
///
/// The executor builds `Args` after validating the request against the schema,
/// applying GraphQL defaults, and converting variables into runtime input
/// values. Prefer `get` and `get_opt` so custom scalar and list coercion goes
/// through the `FromGraphQL` trait.
pub(all) struct Args {
  values : Map[String, InputValue]
} derive(Eq, Debug)

///|
/// Create an empty argument set for helpers and tests.
pub fn Args::empty() -> Args {
  { values: {} }
}

///|
/// Read a required argument and coerce it to a MoonBit type.
///
/// Raises `CoercionError` if the argument was not supplied or if the requested
/// MoonBit type cannot be built from the GraphQL input value.
pub fn[T : FromGraphQL] Args::get(
  self : Args,
  name : String,
) -> T raise CoercionError {
  match self.values.get(name) {
    Some(value) => FromGraphQL::from_graphql(value)
    None => coercion_error("missing argument `\{name}`")
  }
}

///|
/// Read an optional argument and coerce it when present.
///
/// Missing arguments return `None`; present `null` values are delegated to the
/// requested `FromGraphQL` implementation, so `T?` is the usual type for
/// nullable GraphQL arguments.
pub fn[T : FromGraphQL] Args::get_opt(
  self : Args,
  name : String,
) -> T? raise CoercionError {
  match self.values.get(name) {
    Some(value) => Some(FromGraphQL::from_graphql(value))
    None => None
  }
}

///|
/// Test whether an argument was present after GraphQL defaulting and coercion.
pub fn Args::contains(self : Args, name : String) -> Bool {
  self.values.contains(name)
}

///|
/// Return a copy of the underlying input map for custom coercion code.
pub fn Args::to_map(self : Args) -> Map[String, InputValue] {
  self.values.copy()
}
