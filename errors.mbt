///|
/// Error raised while compiling SDL into an executable schema.
///
/// Schema errors cover duplicate definitions, missing root types, invalid
/// directive uses, and references to unknown input or output types.
pub(all) suberror SchemaError {
  SchemaError(String)
} derive(Eq, Debug)

///|
/// Render a schema error with a stable GraphQL-oriented prefix.
pub fn SchemaError::to_string(self : SchemaError) -> String {
  match self {
    SchemaError(message) => "graphql schema error: \{message}"
  }
}

///|
pub impl Show for SchemaError with output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn[T] schema_error(message : String) -> T raise SchemaError {
  raise SchemaError(message)
}

///|
/// Error raised when literal, variable, or resolver argument values cannot be
/// coerced to the expected GraphQL input type.
pub(all) suberror CoercionError {
  CoercionError(String)
} derive(Eq, Debug)

///|
/// Render a coercion error with a stable GraphQL-oriented prefix.
pub fn CoercionError::to_string(self : CoercionError) -> String {
  match self {
    CoercionError(message) => "graphql coercion error: \{message}"
  }
}

///|
pub impl Show for CoercionError with output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn[T] coercion_error(message : String) -> T raise CoercionError {
  raise CoercionError(message)
}

///|
/// Error raised when a parsed GraphQL operation fails document validation.
///
/// Validation runs before resolver execution and reports issues such as unknown
/// fields, invalid fragments, unused variables, and directive misuse.
pub(all) suberror ValidationError {
  ValidationError(String)
} derive(Eq, Debug)

///|
/// Render a validation error with a stable GraphQL-oriented prefix.
pub fn ValidationError::to_string(self : ValidationError) -> String {
  match self {
    ValidationError(message) => "graphql validation error: \{message}"
  }
}

///|
pub impl Show for ValidationError with output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn[T] validation_error(message : String) -> T raise ValidationError {
  raise ValidationError(message)
}

///|
/// Error category for executor-specific failures.
///
/// Resolver exceptions are captured as GraphQL response errors; this error type
/// is available for executor helpers that need to raise explicitly.
pub(all) suberror ExecutionError {
  ExecutionError(String)
} derive(Eq, Debug)

///|
/// Render an execution error with a stable GraphQL-oriented prefix.
pub fn ExecutionError::to_string(self : ExecutionError) -> String {
  match self {
    ExecutionError(message) => "graphql execution error: \{message}"
  }
}

///|
pub impl Show for ExecutionError with output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}
