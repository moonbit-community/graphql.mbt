///|
priv enum MaybeInput {
  InputProvided(InputValue)
  InputOmitted
}

///|
/// Convert a parsed GraphQL value into the runtime input representation before
/// schema-aware coercion is applied.
fn parser_value_to_input(
  value : @parser.Value,
  variables : Map[String, InputValue],
) -> InputValue raise CoercionError {
  match parser_value_to_maybe_input(value, variables) {
    InputProvided(value) => value
    InputOmitted => coercion_error("variable was not provided")
  }
}

///|
fn parser_value_to_maybe_input(
  value : @parser.Value,
  variables : Map[String, InputValue],
) -> MaybeInput raise CoercionError {
  match value {
    @parser.Variable(name) =>
      match variables.get(name) {
        Some(value) => InputProvided(value)
        None => InputOmitted
      }
    @parser.IntValue(number) => InputProvided(InputInt(number.as_int64()))
    @parser.FloatValue(value) => InputProvided(InputFloat(value))
    @parser.StringValue(value) => InputProvided(InputString(value))
    @parser.BooleanValue(value) => InputProvided(InputBoolean(value))
    @parser.NullValue => InputProvided(InputNull)
    @parser.EnumValue(value) => InputProvided(InputEnum(value))
    @parser.ListValue(values) => {
      let list : Array[InputValue] = []
      for item in values {
        match parser_value_to_maybe_input(item, variables) {
          InputProvided(value) => list.push(value)
          InputOmitted => list.push(InputNull)
        }
      }
      InputProvided(InputList(list))
    }
    @parser.ObjectValue(fields) => {
      let object : Map[String, InputValue] = {}
      for pair in fields {
        let name = pair.0
        let value = pair.1
        match parser_value_to_maybe_input(value, variables) {
          InputProvided(value) => object[name] = value
          InputOmitted => ()
        }
      }
      InputProvided(InputObject(object))
    }
  }
}

///|
fn default_value_to_input(
  value : @parser.Value,
) -> InputValue raise CoercionError {
  parser_value_to_input(value, {})
}

///|
/// Coerce a runtime input value according to a GraphQL input type.
///
/// Non-null, list, scalar, enum, and input-object semantics are handled here so
/// variables and field arguments follow the same rules.
fn coerce_input(
  registry : TypeRegistry,
  gql_type : @parser.GqlType,
  value : InputValue,
) -> InputValue raise CoercionError {
  match gql_type {
    @parser.NonNullType(inner) =>
      match value {
        InputNull =>
          coercion_error("expected non-null \{type_to_string(gql_type)}")
        _ => coerce_input(registry, inner, value)
      }
    @parser.ListType(inner) =>
      match value {
        InputNull => InputNull
        InputList(values) =>
          InputList(values.map(value => coerce_input(registry, inner, value)))
        _ => InputList([coerce_input(registry, inner, value)])
      }
    @parser.NamedType(name) =>
      match value {
        InputNull => InputNull
        _ => coerce_named_input(registry, name, value)
      }
  }
}

///|
fn coerce_named_input(
  registry : TypeRegistry,
  name : String,
  value : InputValue,
) -> InputValue raise CoercionError {
  match name {
    "String" =>
      match value {
        InputString(_) => value
        _ => coercion_error("expected String")
      }
    "ID" =>
      match value {
        InputString(_) | InputInt(_) => value
        _ => coercion_error("expected ID")
      }
    "Boolean" =>
      match value {
        InputBoolean(_) => value
        _ => coercion_error("expected Boolean")
      }
    "Int" =>
      match value {
        InputInt(_) => value
        _ => coercion_error("expected Int")
      }
    "Float" =>
      match value {
        InputFloat(_) | InputInt(_) => value
        _ => coercion_error("expected Float")
      }
    _ =>
      match registry.types.get(name) {
        Some(ScalarDef(_)) => value
        Some(EnumDef(values~, ..)) =>
          match value {
            InputEnum(enum_value) | InputString(enum_value) =>
              if values.contains(enum_value) {
                InputEnum(enum_value)
              } else {
                coercion_error("unknown enum value `\{name}.\{enum_value}`")
              }
            _ => coercion_error("expected enum `\{name}`")
          }
        Some(InputObjectDef(fields~, ..)) =>
          coerce_input_object(registry, name, fields, value)
        Some(_) => coercion_error("type `\{name}` is not an input type")
        None => coercion_error("unknown input type `\{name}`")
      }
  }
}

///|
fn coerce_input_object(
  registry : TypeRegistry,
  type_name : String,
  fields : Map[String, @parser.InputValue],
  value : InputValue,
) -> InputValue raise CoercionError {
  let object = match value {
    InputObject(object) => object
    _ => coercion_error("expected input object `\{type_name}`")
  }
  for name, _ in object.iter2() {
    if !fields.contains(name) {
      coercion_error("unknown field `\{type_name}.\{name}`")
    }
  }
  let coerced : Map[String, InputValue] = {}
  for name, field in fields.iter2() {
    match object.get(name) {
      Some(value) =>
        coerced[name] = coerce_input(registry, field.value_type, value)
      None =>
        match field.default_value {
          Some(default_value) =>
            coerced[name] = coerce_input(
              registry,
              field.value_type,
              default_value_to_input(default_value),
            )
          None =>
            if is_non_null(field.value_type) {
              coercion_error(
                "missing required input field `\{type_name}.\{name}`",
              )
            }
        }
    }
  }
  InputObject(coerced)
}

///|
/// Coerce field or directive arguments from parsed literal values plus already
/// coerced variable values.
fn coerce_argument_values(
  registry : TypeRegistry,
  definitions : Array[@parser.InputValue],
  values : Array[(String, @parser.Value)],
  variables : Map[String, InputValue],
) -> Args raise CoercionError {
  let provided : Map[String, @parser.Value] = Map::from_array(values)
  let result : Map[String, InputValue] = {}
  for name, _ in provided.iter2() {
    if !definitions.any(def => def.name == name) {
      coercion_error("unknown argument `\{name}`")
    }
  }
  for definition in definitions {
    match provided.get(definition.name) {
      Some(value) =>
        match parser_value_to_maybe_input(value, variables) {
          InputProvided(value) =>
            result[definition.name] = coerce_input(
              registry,
              definition.value_type,
              value,
            )
          InputOmitted =>
            apply_argument_default_or_required(registry, result, definition)
        }
      None => apply_argument_default_or_required(registry, result, definition)
    }
  }
  { values: result }
}

///|
fn apply_argument_default_or_required(
  registry : TypeRegistry,
  result : Map[String, InputValue],
  definition : @parser.InputValue,
) -> Unit raise CoercionError {
  match definition.default_value {
    Some(default_value) =>
      result[definition.name] = coerce_input(
        registry,
        definition.value_type,
        default_value_to_input(default_value),
      )
    None =>
      if is_non_null(definition.value_type) {
        coercion_error("missing required argument `\{definition.name}`")
      }
  }
}

///|
/// Coerce operation variables against variable definitions before validation
/// and execution read them.
fn coerce_variable_values(
  registry : TypeRegistry,
  definitions : Array[@parser.VariableDefinition],
  provided : Map[String, InputValue],
) -> Map[String, InputValue] raise CoercionError {
  let variables : Map[String, InputValue] = {}
  for definition in definitions {
    match provided.get(definition.name) {
      Some(value) =>
        variables[definition.name] = coerce_input(
          registry,
          definition.var_type,
          value,
        )
      None =>
        match definition.default_value {
          Some(default_value) =>
            variables[definition.name] = coerce_input(
              registry,
              definition.var_type,
              default_value_to_input(default_value),
            )
          None =>
            if is_non_null(definition.var_type) {
              coercion_error("missing required variable `$\{definition.name}`")
            }
        }
    }
  }
  variables
}

///|
fn is_non_null(gql_type : @parser.GqlType) -> Bool {
  gql_type is @parser.NonNullType(_)
}

///|
fn type_to_string(gql_type : @parser.GqlType) -> String {
  match gql_type {
    @parser.NamedType(name) => name
    @parser.ListType(inner) => "[\{type_to_string(inner)}]"
    @parser.NonNullType(inner) => type_to_string(inner) + "!"
  }
}
