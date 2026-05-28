///|
/// Normalized operation selected from a parsed document.
///
/// The validator uses this shape so shorthand selections, queries, mutations,
/// and subscriptions can share the same downstream validation logic.
priv struct OperationPlan {
  kind : String
  name : String?
  variable_definitions : Array[@parser.VariableDefinition]
  directives : Array[@parser.Directive]
  selection_set : @parser.SelectionSet
}

///|
/// Tracks fragment and variable usage while recursively validating selections.
priv struct ValidationState {
  used_fragments : Map[String, Bool]
  used_variables : Map[String, Bool]
}

///|
priv struct CollectedField {
  parent_type : String
  field : @parser.Field
  field_type : @parser.GqlType
}

///|
fn select_operation(
  document : @parser.QueryDocument,
  operation_name : String?,
) -> OperationPlan raise ValidationError {
  let operations : Array[OperationPlan] = []
  let seen_operations : Map[String, Bool] = {}
  let mut has_anonymous = false
  for definition in document.definitions {
    match definition {
      OperationDefinition(operation) => {
        let plan = operation_to_plan(operation)
        match plan.name {
          Some(name) =>
            if seen_operations.contains(name) {
              validation_error("duplicate operation `\{name}`")
            } else {
              seen_operations[name] = true
            }
          None => has_anonymous = true
        }
        operations.push(plan)
      }
      _ => ()
    }
  }
  if operations.is_empty() {
    validation_error("document does not contain an operation")
  }
  if has_anonymous && operations.length() > 1 {
    validation_error("anonymous operation must be the only operation")
  }
  match operation_name {
    Some(expected) =>
      match find_operation(operations, expected) {
        Some(plan) => plan
        None => validation_error("unknown operation `\{expected}`")
      }
    None =>
      if operations.length() == 1 {
        operations[0]
      } else {
        validation_error(
          "operationName is required when document has multiple operations",
        )
      }
  }
}

///|
fn operation_to_plan(operation : @parser.OperationDefinition) -> OperationPlan {
  match operation {
    SelectionSetOperation(selection_set) =>
      {
        kind: "query",
        name: None,
        variable_definitions: [],
        directives: [],
        selection_set,
      }
    QueryOperation(query) =>
      {
        kind: "query",
        name: query.name,
        variable_definitions: query.variable_definitions,
        directives: query.directives,
        selection_set: query.selection_set,
      }
    MutationOperation(mutation) =>
      {
        kind: "mutation",
        name: mutation.name,
        variable_definitions: mutation.variable_definitions,
        directives: mutation.directives,
        selection_set: mutation.selection_set,
      }
    SubscriptionOperation(subscription) =>
      {
        kind: "subscription",
        name: subscription.name,
        variable_definitions: subscription.variable_definitions,
        directives: subscription.directives,
        selection_set: subscription.selection_set,
      }
  }
}

///|
fn find_operation(
  operations : Array[OperationPlan],
  name : String,
) -> OperationPlan? {
  for operation in operations {
    if operation.name == Some(name) {
      return Some(operation)
    }
  }
  None
}

///|
fn fragment_map(
  document : @parser.QueryDocument,
) -> Map[String, @parser.FragmentDefinition] raise ValidationError {
  let fragments : Map[String, @parser.FragmentDefinition] = {}
  for definition in document.definitions {
    match definition {
      FragmentDefinition(fragment) =>
        if fragments.contains(fragment.name) {
          validation_error("duplicate fragment `\{fragment.name}`")
        } else {
          fragments[fragment.name] = fragment
        }
      _ => ()
    }
  }
  fragments
}

///|
/// Validate a request and return GraphQL errors without executing resolvers.
///
/// This is useful for editor integrations, preflight checks, and tests. Parse
/// or validation failures are returned as `GraphQLError` values; an empty array
/// means the request is executable for the supplied schema.
pub fn[Ctx] validate(
  schema : ExecutableSchema[Ctx],
  request : GraphQLRequest,
) -> Array[GraphQLError] {
  try @parser.parse_query(request.query) catch {
    err => [GraphQLError::new(err.to_string())]
  } noraise {
    document =>
      try validate_document(schema, document, request.operation_name) catch {
        err => [GraphQLError::new(err.to_string())]
      } noraise {
        _ => []
      }
  }
}

///|
/// Run the complete document validation pipeline and return the selected
/// operation plus fragment map needed by the executor.
fn[Ctx] validate_document(
  schema : ExecutableSchema[Ctx],
  document : @parser.QueryDocument,
  operation_name : String?,
) -> (OperationPlan, Map[String, @parser.FragmentDefinition]) raise ValidationError {
  let operation = select_operation(document, operation_name)
  let fragments = fragment_map(document)
  validate_variable_definitions(schema.registry, operation.variable_definitions)
  validate_fragment_cycles(fragments)
  let root_type = operation_root_type(schema, operation)
  let state = ValidationState::{ used_fragments: {}, used_variables: {} }
  validate_directives(
    schema.registry,
    operation.directives,
    operation_directive_location(operation),
    operation.variable_definitions,
    state,
  )
  validate_selection_set(
    schema,
    root_type,
    operation.selection_set,
    fragments,
    operation.variable_definitions,
    state,
  )
  validate_all_fragments_used(fragments, state)
  validate_all_variables_used(operation.variable_definitions, state)
  (operation, fragments)
}

///|
fn operation_directive_location(operation : OperationPlan) -> String {
  match operation.kind {
    "query" => "QUERY"
    "mutation" => "MUTATION"
    "subscription" => "SUBSCRIPTION"
    _ => "QUERY"
  }
}

///|
fn[Ctx] operation_root_type(
  schema : ExecutableSchema[Ctx],
  operation : OperationPlan,
) -> String raise ValidationError {
  match operation.kind {
    "query" => schema.query_type
    "mutation" =>
      match schema.mutation_type {
        Some(type_name) => type_name
        None => validation_error("schema does not define a mutation root")
      }
    "subscription" =>
      match schema.subscription_type {
        Some(type_name) => type_name
        None => validation_error("schema does not define a subscription root")
      }
    _ => validation_error("unknown operation kind")
  }
}

///|
fn validate_variable_definitions(
  registry : TypeRegistry,
  definitions : Array[@parser.VariableDefinition],
) -> Unit raise ValidationError {
  let seen : Map[String, Bool] = {}
  for definition in definitions {
    if seen.contains(definition.name) {
      validation_error("duplicate variable `$\{definition.name}`")
    }
    seen[definition.name] = true
    if !is_input_type(registry, definition.var_type) {
      validation_error("variable `$\{definition.name}` uses non-input type")
    }
    match definition.default_value {
      Some(default_value) => {
        let state = ValidationState::{ used_fragments: {}, used_variables: {} }
        validate_input_value(
          registry,
          definition.var_type,
          default_value,
          [],
          state,
          location_has_default=false,
        )
      }
      None => ()
    }
  }
}

///|
fn is_input_type(registry : TypeRegistry, gql_type : @parser.GqlType) -> Bool {
  match gql_type {
    NonNullType(inner) | ListType(inner) => is_input_type(registry, inner)
    NamedType(name) =>
      match registry.types.get(name) {
        Some(type_def) => type_def.is_input()
        None => false
      }
  }
}

///|
/// Validate a selection set recursively against a concrete parent type.
///
/// This pass checks fields, response key conflicts, directive locations,
/// fragment applicability, argument values, and nested selection requirements.
fn[Ctx] validate_selection_set(
  schema : ExecutableSchema[Ctx],
  type_name : String,
  selection_set : @parser.SelectionSet,
  fragments : Map[String, @parser.FragmentDefinition],
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  validate_overlapping_fields(
    schema.registry,
    type_name,
    selection_set,
    fragments,
  )
  let response_keys : Map[String, String] = {}
  for selection in selection_set.items {
    match selection {
      FieldSelection(field) => {
        if schema.validation.disable_introspection &&
          field.name.has_prefix("__") {
          validation_error("introspection is disabled")
        }
        let response_key = field.field_alias.unwrap_or(field.name)
        if response_keys.contains(response_key) &&
          response_keys[response_key] != field.name {
          validation_error(
            "conflicting fields for response key `\{response_key}`",
          )
        }
        response_keys[response_key] = field.name
        validate_directives(
          schema.registry,
          field.directives,
          "FIELD",
          variables,
          state,
        )
        let field_type : @parser.GqlType = if field.name == "__typename" {
          NonNullType(NamedType("String"))
        } else if field.name == "__schema" {
          validate_arguments(
            schema.registry,
            [],
            field.arguments,
            variables,
            state,
          )
          NamedType("Json")
        } else if field.name == "__type" {
          validate_arguments(
            schema.registry,
            [builtin_directive_arg("name", non_null_named("String"), None)],
            field.arguments,
            variables,
            state,
          )
          NamedType("Json")
        } else {
          match schema.registry.field(type_name, field.name) {
            Some(definition) => {
              validate_arguments(
                schema.registry,
                definition.arguments,
                field.arguments,
                variables,
                state,
              )
              definition.field_type
            }
            None =>
              validation_error("unknown field `\{type_name}.\{field.name}`")
          }
        }
        validate_field_selection_shape(
          schema,
          field_type,
          field.selection_set,
          fragments,
          variables,
          state,
        )
      }
      FragmentSpreadSelection(spread) => {
        validate_directives(
          schema.registry,
          spread.directives,
          "FRAGMENT_SPREAD",
          variables,
          state,
        )
        match fragments.get(spread.fragment_name) {
          Some(fragment) => {
            state.used_fragments[spread.fragment_name] = true
            validate_directives(
              schema.registry,
              fragment.directives,
              "FRAGMENT_DEFINITION",
              variables,
              state,
            )
            let On(fragment_type) = fragment.type_condition
            if !is_known_output_type(schema.registry, fragment_type) {
              validation_error("unknown fragment type `\{fragment_type}`")
            }
            if !types_overlap(schema.registry, type_name, fragment_type) {
              validation_error(
                "fragment `\{spread.fragment_name}` cannot apply to `\{type_name}`",
              )
            }
            validate_selection_set(
              schema,
              fragment_type,
              fragment.selection_set,
              fragments,
              variables,
              state,
            )
          }
          None => validation_error("unknown fragment `\{spread.fragment_name}`")
        }
      }
      InlineFragmentSelection(fragment) => {
        validate_directives(
          schema.registry,
          fragment.directives,
          "INLINE_FRAGMENT",
          variables,
          state,
        )
        let next_type = match fragment.type_condition {
          Some(On(next)) => {
            if !is_known_output_type(schema.registry, next) {
              validation_error("unknown inline fragment type `\{next}`")
            }
            if !types_overlap(schema.registry, type_name, next) {
              validation_error("inline fragment cannot apply to `\{type_name}`")
            }
            next
          }
          None => type_name
        }
        validate_selection_set(
          schema,
          next_type,
          fragment.selection_set,
          fragments,
          variables,
          state,
        )
      }
    }
  }
}

///|
fn validate_overlapping_fields(
  registry : TypeRegistry,
  type_name : String,
  selection_set : @parser.SelectionSet,
  fragments : Map[String, @parser.FragmentDefinition],
) -> Unit raise ValidationError {
  let groups : Map[String, Array[CollectedField]] = {}
  collect_validation_fields(
    registry, type_name, selection_set, fragments, groups,
  )
  for response_key, fields in groups.iter2() {
    for i in 0..<fields.length() {
      for j in (i + 1)..<fields.length() {
        validate_field_pair_merge(
          registry,
          response_key,
          fields[i],
          fields[j],
          fragments,
        )
      }
    }
  }
}

///|
fn collect_validation_fields(
  registry : TypeRegistry,
  type_name : String,
  selection_set : @parser.SelectionSet,
  fragments : Map[String, @parser.FragmentDefinition],
  groups : Map[String, Array[CollectedField]],
) -> Unit {
  for selection in selection_set.items {
    match selection {
      FieldSelection(field) =>
        match validation_field_type(registry, type_name, field) {
          Some(field_type) => {
            let response_key = field.field_alias.unwrap_or(field.name)
            let collected = { parent_type: type_name, field, field_type }
            match groups.get(response_key) {
              Some(fields) => fields.push(collected)
              None => groups[response_key] = [collected]
            }
          }
          None => ()
        }
      FragmentSpreadSelection(spread) =>
        match fragments.get(spread.fragment_name) {
          Some(fragment) => {
            let On(fragment_type) = fragment.type_condition
            collect_validation_fields(
              registry,
              fragment_type,
              fragment.selection_set,
              fragments,
              groups,
            )
          }
          None => ()
        }
      InlineFragmentSelection(fragment) => {
        let next_type = match fragment.type_condition {
          Some(On(name)) => name
          None => type_name
        }
        collect_validation_fields(
          registry,
          next_type,
          fragment.selection_set,
          fragments,
          groups,
        )
      }
    }
  }
}

///|
fn validation_field_type(
  registry : TypeRegistry,
  type_name : String,
  field : @parser.Field,
) -> @parser.GqlType? {
  if field.name == "__typename" {
    Some(NonNullType(NamedType("String")))
  } else if field.name == "__schema" || field.name == "__type" {
    Some(NamedType("Json"))
  } else {
    match registry.field(type_name, field.name) {
      Some(definition) => Some(definition.field_type)
      None => None
    }
  }
}

///|
fn validate_field_pair_merge(
  registry : TypeRegistry,
  response_key : String,
  left : CollectedField,
  right : CollectedField,
  fragments : Map[String, @parser.FragmentDefinition],
) -> Unit raise ValidationError {
  if !types_overlap(registry, left.parent_type, right.parent_type) {
    return
  }
  if left.field.name != right.field.name {
    validation_error("conflicting fields for response key `\{response_key}`")
  }
  if !arguments_equal(left.field.arguments, right.field.arguments) {
    validation_error("conflicting arguments for response key `\{response_key}`")
  }
  if !same_response_shape(registry, left.field_type, right.field_type) {
    validation_error(
      "conflicting return types for response key `\{response_key}`",
    )
  }
  let named = named_type(left.field_type)
  if is_composite_type(registry, named) &&
    !left.field.selection_set.items.is_empty() &&
    !right.field.selection_set.items.is_empty() {
    let items = left.field.selection_set.items.copy()
    items.append(right.field.selection_set.items)
    let merged : @parser.SelectionSet = {
      span: left.field.selection_set.span,
      items,
    }
    validate_overlapping_fields(registry, named, merged, fragments)
  }
}

///|
fn arguments_equal(
  left : Array[(String, @parser.Value)],
  right : Array[(String, @parser.Value)],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for pair in left {
    match find_argument_value(right, pair.0) {
      Some(value) => if value != pair.1 { return false }
      None => return false
    }
  }
  true
}

///|
fn find_argument_value(
  arguments : Array[(String, @parser.Value)],
  name : String,
) -> @parser.Value? {
  for pair in arguments {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn same_response_shape(
  registry : TypeRegistry,
  left : @parser.GqlType,
  right : @parser.GqlType,
) -> Bool {
  match (left, right) {
    (NonNullType(left_inner), NonNullType(right_inner)) =>
      same_response_shape(registry, left_inner, right_inner)
    (NonNullType(_), _) | (_, NonNullType(_)) => false
    (ListType(left_inner), ListType(right_inner)) =>
      same_response_shape(registry, left_inner, right_inner)
    (ListType(_), _) | (_, ListType(_)) => false
    (NamedType(left_name), NamedType(right_name)) => {
      let left_leaf = is_leaf_type_name(registry, left_name)
      let right_leaf = is_leaf_type_name(registry, right_name)
      if left_leaf || right_leaf {
        left_leaf && right_leaf && left_name == right_name
      } else {
        true
      }
    }
  }
}

///|
fn is_leaf_type_name(registry : TypeRegistry, name : String) -> Bool {
  if name == "Json" {
    return true
  }
  match registry.types.get(name) {
    Some(type_def) => type_def.is_leaf()
    None => false
  }
}

///|
fn is_composite_type(registry : TypeRegistry, name : String) -> Bool {
  match registry.types.get(name) {
    Some(ObjectDef(_)) | Some(InterfaceDef(_)) | Some(UnionDef(_)) => true
    _ => false
  }
}

///|
fn[Ctx] validate_field_selection_shape(
  schema : ExecutableSchema[Ctx],
  gql_type : @parser.GqlType,
  selection_set : @parser.SelectionSet,
  fragments : Map[String, @parser.FragmentDefinition],
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  let named = named_type(gql_type)
  match schema.registry.types.get(named) {
    Some(type_def) =>
      if type_def.is_leaf() || named == "Json" {
        if !selection_set.items.is_empty() && named != "Json" {
          validation_error(
            "field of leaf type `\{named}` must not have a selection set",
          )
        }
      } else if selection_set.items.is_empty() {
        validation_error(
          "field of object type `\{named}` requires a selection set",
        )
      } else {
        validate_selection_set(
          schema, named, selection_set, fragments, variables, state,
        )
      }
    None =>
      if named == "Json" {
        ()
      } else {
        validation_error("unknown type `\{named}`")
      }
  }
}

///|
fn validate_arguments(
  registry : TypeRegistry,
  definitions : Array[@parser.InputValue],
  arguments : Array[(String, @parser.Value)],
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  let seen : Map[String, Bool] = {}
  for pair in arguments {
    let name = pair.0
    let value = pair.1
    if seen.contains(name) {
      validation_error("duplicate argument `\{name}`")
    }
    seen[name] = true
    if !definitions.any(def => def.name == name) {
      validation_error("unknown argument `\{name}`")
    }
    let definition = match find_input_definition(definitions, name) {
      Some(definition) => definition
      None => validation_error("unknown argument `\{name}`")
    }
    validate_input_value(
      registry,
      definition.value_type,
      value,
      variables,
      state,
      location_has_default=definition.default_value != None,
    )
  }
  for definition in definitions {
    if is_non_null(definition.value_type) &&
      definition.default_value == None &&
      !seen.contains(definition.name) {
      validation_error("missing required argument `\{definition.name}`")
    }
  }
}

///|
fn validate_directives(
  registry : TypeRegistry,
  directives : Array[@parser.Directive],
  location : String,
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  let seen : Map[String, Bool] = {}
  for directive in directives {
    let spec = match registry.directives.get("@" + directive.name) {
      Some(spec) => spec
      None => validation_error("unknown directive `@\{directive.name}`")
    }
    if !spec.locations.contains(location) {
      validation_error(
        "directive `@\{directive.name}` is not allowed at \{location}",
      )
    }
    if seen.contains(directive.name) && !spec.repeatable {
      validation_error("duplicate directive `@\{directive.name}`")
    }
    seen[directive.name] = true
    validate_arguments(
      registry,
      spec.arguments,
      directive.arguments,
      variables,
      state,
    )
  }
}

///|
fn find_input_definition(
  definitions : Array[@parser.InputValue],
  name : String,
) -> @parser.InputValue? {
  for definition in definitions {
    if definition.name == name {
      return Some(definition)
    }
  }
  None
}

///|
fn find_variable_definition(
  variables : Array[@parser.VariableDefinition],
  name : String,
) -> @parser.VariableDefinition? {
  for definition in variables {
    if definition.name == name {
      return Some(definition)
    }
  }
  None
}

///|
/// Validate a literal, variable, list, or object value against an expected input
/// type while marking referenced variables as used.
fn validate_input_value(
  registry : TypeRegistry,
  expected_type : @parser.GqlType,
  value : @parser.Value,
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
  location_has_default~ : Bool,
) -> Unit raise ValidationError {
  match expected_type {
    NonNullType(inner) =>
      match value {
        NullValue =>
          validation_error("expected non-null \{type_to_string(expected_type)}")
        _ =>
          validate_input_value(
            registry,
            inner,
            value,
            variables,
            state,
            location_has_default~,
          )
      }
    ListType(inner) =>
      match value {
        Variable(name) =>
          validate_variable_value(
            expected_type,
            name,
            variables,
            state,
            location_has_default~,
          )
        NullValue => ()
        ListValue(values) =>
          for item in values {
            validate_input_value(
              registry,
              inner,
              item,
              variables,
              state,
              location_has_default=false,
            )
          }
        _ =>
          validate_input_value(
            registry,
            inner,
            value,
            variables,
            state,
            location_has_default=false,
          )
      }
    NamedType(name) =>
      match value {
        Variable(variable_name) =>
          validate_variable_value(
            expected_type,
            variable_name,
            variables,
            state,
            location_has_default~,
          )
        NullValue => ()
        _ => validate_named_input_value(registry, name, value, variables, state)
      }
  }
}

///|
fn validate_named_input_value(
  registry : TypeRegistry,
  name : String,
  value : @parser.Value,
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  match name {
    "String" =>
      if !(value is StringValue(_)) {
        validation_error("expected String")
      }
    "ID" =>
      if !(value is StringValue(_) || value is IntValue(_)) {
        validation_error("expected ID")
      }
    "Boolean" =>
      if !(value is BooleanValue(_)) {
        validation_error("expected Boolean")
      }
    "Int" => if !(value is IntValue(_)) { validation_error("expected Int") }
    "Float" =>
      if !(value is FloatValue(_) || value is IntValue(_)) {
        validation_error("expected Float")
      }
    _ =>
      match registry.types.get(name) {
        Some(ScalarDef(_)) => ()
        Some(EnumDef(values~, ..)) =>
          match value {
            EnumValue(enum_value) =>
              if !values.contains(enum_value) {
                validation_error("unknown enum value `\{name}.\{enum_value}`")
              }
            _ => validation_error("expected enum `\{name}`")
          }
        Some(InputObjectDef(fields~, ..)) =>
          validate_input_object_value(
            registry, name, fields, value, variables, state,
          )
        Some(_) => validation_error("type `\{name}` is not an input type")
        None => validation_error("unknown input type `\{name}`")
      }
  }
}

///|
fn validate_input_object_value(
  registry : TypeRegistry,
  type_name : String,
  definitions : Map[String, @parser.InputValue],
  value : @parser.Value,
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  let fields = match value {
    ObjectValue(fields) => fields
    _ => validation_error("expected input object `\{type_name}`")
  }
  let seen : Map[String, Bool] = {}
  for pair in fields {
    let name = pair.0
    let field_value = pair.1
    if seen.contains(name) {
      validation_error("duplicate input field `\{type_name}.\{name}`")
    }
    seen[name] = true
    let definition = match definitions.get(name) {
      Some(definition) => definition
      None => validation_error("unknown field `\{type_name}.\{name}`")
    }
    validate_input_value(
      registry,
      definition.value_type,
      field_value,
      variables,
      state,
      location_has_default=definition.default_value != None,
    )
  }
  for name, definition in definitions.iter2() {
    if is_non_null(definition.value_type) &&
      definition.default_value == None &&
      !seen.contains(name) {
      validation_error("missing required input field `\{type_name}.\{name}`")
    }
  }
}

///|
fn validate_variable_value(
  expected_type : @parser.GqlType,
  name : String,
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
  location_has_default~ : Bool,
) -> Unit raise ValidationError {
  let definition = match find_variable_definition(variables, name) {
    Some(definition) => definition
    None => validation_error("variable `$\{name}` is not defined")
  }
  state.used_variables[name] = true
  if !variable_type_allowed(
      definition.var_type,
      expected_type,
      variable_has_non_null_default(definition) || location_has_default,
    ) {
    validation_error(
      "variable `$\{name}` of type `\{type_to_string(definition.var_type)}` cannot be used as `\{type_to_string(expected_type)}`",
    )
  }
}

///|
fn variable_has_non_null_default(
  definition : @parser.VariableDefinition,
) -> Bool {
  match definition.default_value {
    Some(NullValue) | None => false
    Some(_) => true
  }
}

///|
fn variable_type_allowed(
  variable_type : @parser.GqlType,
  expected_type : @parser.GqlType,
  nullable_default_ok : Bool,
) -> Bool {
  match expected_type {
    NonNullType(expected_inner) =>
      match variable_type {
        NonNullType(variable_inner) =>
          variable_type_allowed(variable_inner, expected_inner, false)
        _ =>
          nullable_default_ok &&
          variable_type_allowed(variable_type, expected_inner, false)
      }
    ListType(expected_inner) =>
      match variable_type {
        NonNullType(variable_inner) =>
          variable_type_allowed(variable_inner, expected_type, false)
        ListType(variable_inner) =>
          variable_type_allowed(variable_inner, expected_inner, false)
        _ => false
      }
    NamedType(expected_name) =>
      match variable_type {
        NonNullType(variable_inner) =>
          variable_type_allowed(variable_inner, expected_type, false)
        NamedType(variable_name) => variable_name == expected_name
        _ => false
      }
  }
}

///|
fn validate_fragment_cycles(
  fragments : Map[String, @parser.FragmentDefinition],
) -> Unit raise ValidationError {
  for name, _ in fragments.iter2() {
    let stack : Array[String] = []
    visit_fragment(name, fragments, stack)
  }
}

///|
fn visit_fragment(
  name : String,
  fragments : Map[String, @parser.FragmentDefinition],
  stack : Array[String],
) -> Unit raise ValidationError {
  if stack.contains(name) {
    validation_error("fragment cycle involving `\{name}`")
  }
  match fragments.get(name) {
    Some(fragment) => {
      let next_stack = stack.copy()
      next_stack.push(name)
      for selection in fragment.selection_set.items {
        match selection {
          FragmentSpreadSelection(spread) =>
            visit_fragment(spread.fragment_name, fragments, next_stack)
          InlineFragmentSelection(inline_fragment) =>
            visit_fragment_spreads(
              inline_fragment.selection_set,
              fragments,
              next_stack,
            )
          _ => ()
        }
      }
    }
    None => validation_error("unknown fragment `\{name}`")
  }
}

///|
fn visit_fragment_spreads(
  selection_set : @parser.SelectionSet,
  fragments : Map[String, @parser.FragmentDefinition],
  stack : Array[String],
) -> Unit raise ValidationError {
  for selection in selection_set.items {
    match selection {
      FragmentSpreadSelection(spread) =>
        visit_fragment(spread.fragment_name, fragments, stack)
      InlineFragmentSelection(inline_fragment) =>
        visit_fragment_spreads(inline_fragment.selection_set, fragments, stack)
      _ => ()
    }
  }
}

///|
fn validate_all_fragments_used(
  fragments : Map[String, @parser.FragmentDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  for name, _ in fragments.iter2() {
    if !state.used_fragments.contains(name) {
      validation_error("fragment `\{name}` is never used")
    }
  }
}

///|
fn validate_all_variables_used(
  variables : Array[@parser.VariableDefinition],
  state : ValidationState,
) -> Unit raise ValidationError {
  for variable in variables {
    if !state.used_variables.contains(variable.name) {
      validation_error("variable `$\{variable.name}` is never used")
    }
  }
}

///|
fn is_known_output_type(registry : TypeRegistry, type_name : String) -> Bool {
  match registry.types.get(type_name) {
    Some(ScalarDef(_))
    | Some(ObjectDef(_))
    | Some(InterfaceDef(_))
    | Some(UnionDef(_))
    | Some(EnumDef(_)) => true
    _ => false
  }
}

///|
/// Return true when two output type conditions can select at least one common
/// runtime object type.
fn types_overlap(
  registry : TypeRegistry,
  left : String,
  right : String,
) -> Bool {
  if left == right {
    return true
  }
  let left_possible = possible_object_types(registry, left)
  let right_possible = possible_object_types(registry, right)
  left_possible.any(name => right_possible.contains(name))
}

///|
fn possible_object_types(
  registry : TypeRegistry,
  type_name : String,
) -> Array[String] {
  match registry.types.get(type_name) {
    Some(ObjectDef(_)) => [type_name]
    Some(InterfaceDef(_)) =>
      registry.types
      .to_array()
      .filter_map(kv => {
        match kv.1 {
          ObjectDef(interfaces~, ..) =>
            if interfaces.contains(type_name) ||
              type_implements_interface(registry, kv.0, type_name) {
              Some(kv.0)
            } else {
              None
            }
          _ => None
        }
      })
    Some(UnionDef(members~, ..)) => members
    _ => []
  }
}
