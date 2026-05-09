///|
/// Result of completing one field or selection set.
///
/// `bubble_null` implements GraphQL non-null propagation: when true, the parent
/// completion step must replace its own value with null and continue bubbling if
/// its declared type is also non-null.
priv struct CompleteResult {
  value : GqlValue
  errors : Array[GraphQLError]
  bubble_null : Bool
}

///|
priv struct RuntimeFieldCollection {
  keys : Array[String]
  fields : Map[String, Array[@parser.Field]]
}

///|
/// Execute a GraphQL request and return only the GraphQL response envelope.
///
/// Use `execute_with_status` when an HTTP transport needs to distinguish parse,
/// validation, and variable coercion failures from successful execution.
pub async fn[Ctx] execute(
  schema : ExecutableSchema[Ctx],
  request : GraphQLRequest,
  context : Ctx,
) -> GraphQLResponse {
  let result = execute_with_status(schema, request, context)
  result.response
}

///|
/// HTTP-oriented execution result containing status code and GraphQL response.
pub(all) struct ExecutionHttpResult {
  status_code : Int
  response : GraphQLResponse
} derive(Eq, Debug)

///|
/// Execute a GraphQL request with parser, validator, variable coercion, resolver
/// execution, and GraphQL value completion.
///
/// Parse, validation, variable coercion, and root operation errors return
/// status `400`. Resolver and completion errors are represented inside the
/// GraphQL response with status `200`, following common GraphQL HTTP behavior.
pub async fn[Ctx] execute_with_status(
  schema : ExecutableSchema[Ctx],
  request : GraphQLRequest,
  context : Ctx,
) -> ExecutionHttpResult {
  let document = try @parser.parse_query(request.query) catch {
    err =>
      return {
        status_code: 400,
        response: GraphQLResponse::error(err.to_string()),
      }
  } noraise {
    document => document
  }
  let (operation, fragments) = try
    validate_document(schema, document, request.operation_name)
  catch {
    err =>
      return {
        status_code: 400,
        response: GraphQLResponse::error(err.to_string()),
      }
  } noraise {
    result => result
  }
  let variables = try
    coerce_variable_values(
      schema.registry,
      operation.variable_definitions,
      request.variables,
    )
  catch {
    err =>
      return {
        status_code: 400,
        response: GraphQLResponse::error(err.to_string()),
      }
  } noraise {
    values => values
  }
  let root_type = try operation_root_type(schema, operation) catch {
    err =>
      return {
        status_code: 400,
        response: GraphQLResponse::error(err.to_string()),
      }
  } noraise {
    type_name => type_name
  }
  let result = execute_selection_set(
    schema,
    root_type,
    operation.selection_set,
    GqlNull,
    variables,
    fragments,
    context,
    [],
  )
  {
    status_code: 200,
    response: { data: Some(result.value), errors: result.errors },
  }
}

///|
/// Start a subscription operation and return its response stream.
///
/// This validates the request as a subscription, coerces variables and
/// arguments, and invokes the registered subscription resolver for the single
/// selected root field.
pub async fn[Ctx] start_subscription(
  schema : ExecutableSchema[Ctx],
  request : GraphQLRequest,
  context : Ctx,
) -> Result[SubscriptionStream, GraphQLResponse] {
  let document = try @parser.parse_query(request.query) catch {
    err => return Err(GraphQLResponse::error(err.to_string()))
  } noraise {
    document => document
  }
  let (operation, _) = try
    validate_document(schema, document, request.operation_name)
  catch {
    err => return Err(GraphQLResponse::error(err.to_string()))
  } noraise {
    result => result
  }
  if operation.kind != "subscription" {
    return Err(GraphQLResponse::error("operation is not a subscription"))
  }
  let variables = try
    coerce_variable_values(
      schema.registry,
      operation.variable_definitions,
      request.variables,
    )
  catch {
    err => return Err(GraphQLResponse::error(err.to_string()))
  } noraise {
    values => values
  }
  let root_type = try operation_root_type(schema, operation) catch {
    err => return Err(GraphQLResponse::error(err.to_string()))
  } noraise {
    type_name => type_name
  }
  if operation.selection_set.items.length() != 1 {
    return Err(
      GraphQLResponse::error("subscription must select exactly one root field"),
    )
  }
  let field = match operation.selection_set.items[0] {
    @parser.FieldSelection(field) => field
    _ =>
      return Err(
        GraphQLResponse::error("subscription root selection must be a field"),
      )
  }
  let field_def = match schema.registry.field(root_type, field.name) {
    Some(field_def) => field_def
    None =>
      return Err(
        GraphQLResponse::error(
          "unknown subscription field `\{root_type}.\{field.name}`",
        ),
      )
  }
  let args = try
    coerce_argument_values(
      schema.registry,
      field_def.arguments,
      field.arguments,
      variables,
    )
  catch {
    err => return Err(GraphQLResponse::error(err.to_string()))
  } noraise {
    args => args
  }
  let resolver = match
    schema.subscriptions.get(resolver_key(root_type, field.name)) {
    Some(resolver) => resolver
    None =>
      return Err(
        GraphQLResponse::error(
          "missing subscription resolver for `\{root_type}.\{field.name}`",
        ),
      )
  }
  let response_key = field.field_alias.unwrap_or(field.name)
  let path = [PathField(response_key)]
  let info = {
    type_name: root_type,
    field_name: field.name,
    response_key,
    path,
    source: GqlNull,
  }
  try resolver(info, args, context) catch {
    err => Err(GraphQLResponse::error("\{err}"))
  } noraise {
    stream => Ok(stream)
  }
}

///|
/// Execute every selected field and fragment against a runtime object type.
///
/// Fragment spreads are evaluated only when their type condition overlaps with
/// the current runtime type, and object fields with the same response key are
/// merged into one response map.
async fn[Ctx] execute_selection_set(
  schema : ExecutableSchema[Ctx],
  type_name : String,
  selection_set : @parser.SelectionSet,
  source : GqlValue,
  variables : Map[String, InputValue],
  fragments : Map[String, @parser.FragmentDefinition],
  context : Ctx,
  path : Array[PathSegment],
) -> CompleteResult {
  let object : Map[String, GqlValue] = {}
  let errors : Array[GraphQLError] = []
  let runtime_type = source.runtime_type(fallback=type_name)
  let collection = collect_execution_fields(
    schema, runtime_type, selection_set, variables, fragments,
  )
  for response_key in collection.keys {
    let fields = collection.fields[response_key]
    let merged_field = merge_runtime_fields(fields)
    let field_result = execute_field(
      schema, runtime_type, merged_field, source, variables, fragments, context,
      path,
    )
    object[response_key] = field_result.value
    errors.append(field_result.errors)
    if field_result.bubble_null {
      return { value: GqlNull, errors, bubble_null: true }
    }
  }
  { value: GqlObject(object), errors, bubble_null: false }
}

///|
/// Resolve and complete a single field, including built-in introspection fields.
///
/// When no explicit resolver is registered, object values fall back to field
/// lookup on the parent `GqlObject` or `GqlTypedObject`.
async fn[Ctx] execute_field(
  schema : ExecutableSchema[Ctx],
  type_name : String,
  field : @parser.Field,
  source : GqlValue,
  variables : Map[String, InputValue],
  fragments : Map[String, @parser.FragmentDefinition],
  context : Ctx,
  parent_path : Array[PathSegment],
) -> CompleteResult {
  let response_key = field.field_alias.unwrap_or(field.name)
  let path = parent_path.copy()
  path.push(PathField(response_key))
  if field.name == "__typename" {
    return { value: GqlString(type_name), errors: [], bubble_null: false }
  }
  if field.name == "__schema" {
    return {
      value: gql_value_from_json(introspect(schema, format=Full)),
      errors: [],
      bubble_null: false,
    }
  }
  if field.name == "__type" {
    let type_name_arg = find_argument(field.arguments, "name")
    let type_json = match type_name_arg {
      Some((_, value)) =>
        match parser_value_to_input(value, variables) {
          InputString(name) | InputEnum(name) => introspect_type(schema, name)
          _ => Json::null()
        }
      None => Json::null()
    }
    return {
      value: gql_value_from_json(type_json),
      errors: [],
      bubble_null: false,
    }
  }
  let field_def = match schema.registry.field(type_name, field.name) {
    Some(field_def) => field_def
    None =>
      return {
        value: GqlNull,
        errors: [
          GraphQLError::new("unknown field `\{type_name}.\{field.name}`", path~),
        ],
        bubble_null: false,
      }
  }
  let args = try
    coerce_argument_values(
      schema.registry,
      field_def.arguments,
      field.arguments,
      variables,
    )
  catch {
    err =>
      return {
        value: GqlNull,
        errors: [GraphQLError::new(err.to_string(), path~)],
        bubble_null: is_non_null(field_def.field_type),
      }
  } noraise {
    args => args
  }
  let raw = match find_resolver(schema, type_name, field.name) {
    Some(resolver) => {
      let info = {
        type_name,
        field_name: field.name,
        response_key,
        path,
        source,
      }
      try resolver(info, args, context) catch {
        err =>
          return {
            value: GqlNull,
            errors: [GraphQLError::new("\{err}", path~)],
            bubble_null: is_non_null(field_def.field_type),
          }
      } noraise {
        value => value
      }
    }
    None =>
      match source.field(field.name) {
        Some(value) => value
        None =>
          return {
            value: GqlNull,
            errors: [
              GraphQLError::new(
                "missing resolver for `\{type_name}.\{field.name}`",
                path~,
              ),
            ],
            bubble_null: is_non_null(field_def.field_type),
          }
      }
  }
  complete_value(
    schema,
    field_def.field_type,
    field.selection_set,
    raw,
    variables,
    fragments,
    context,
    path,
  )
}

///|
/// Complete a raw resolver value according to a GraphQL output type.
///
/// This is where list item completion, object sub-selection, and non-null
/// bubbling are enforced.
async fn[Ctx] complete_value(
  schema : ExecutableSchema[Ctx],
  gql_type : @parser.GqlType,
  selection_set : @parser.SelectionSet,
  value : GqlValue,
  variables : Map[String, InputValue],
  fragments : Map[String, @parser.FragmentDefinition],
  context : Ctx,
  path : Array[PathSegment],
) -> CompleteResult {
  match gql_type {
    @parser.NonNullType(inner) => {
      let result = complete_value(
        schema, inner, selection_set, value, variables, fragments, context, path,
      )
      if result.bubble_null || result.value == GqlNull {
        let errors = result.errors
        if errors.is_empty() {
          errors.push(
            GraphQLError::new("non-null field resolved to null", path~),
          )
        }
        { value: GqlNull, errors, bubble_null: true }
      } else {
        { value: result.value, errors: result.errors, bubble_null: false }
      }
    }
    @parser.ListType(inner) =>
      match value {
        GqlNull => { value: GqlNull, errors: [], bubble_null: false }
        GqlList(values) => {
          let completed : Array[GqlValue] = []
          let errors : Array[GraphQLError] = []
          for index, item in values.iter2() {
            let item_path = path.copy()
            item_path.push(PathIndex(index))
            let result = complete_value(
              schema, inner, selection_set, item, variables, fragments, context,
              item_path,
            )
            errors.append(result.errors)
            if result.bubble_null {
              completed.push(GqlNull)
              if is_non_null(inner) {
                return { value: GqlNull, errors, bubble_null: true }
              }
            } else {
              completed.push(result.value)
            }
          }
          { value: GqlList(completed), errors, bubble_null: false }
        }
        _ =>
          {
            value: GqlNull,
            errors: [
              GraphQLError::new(
                "expected list for `\{type_to_string(gql_type)}`",
                path~,
              ),
            ],
            bubble_null: false,
          }
      }
    @parser.NamedType(name) =>
      match schema.registry.types.get(name) {
        Some(ScalarDef(_)) | Some(EnumDef(_)) =>
          { value, errors: [], bubble_null: false }
        Some(ObjectDef(_)) =>
          if value == GqlNull {
            { value: GqlNull, errors: [], bubble_null: false }
          } else {
            let runtime_type = value.runtime_type(fallback=name)
            if runtime_type != name {
              return {
                value: GqlNull,
                errors: [
                  GraphQLError::new(
                    "runtime type `\{runtime_type}` is not valid for object `\{name}`",
                    path~,
                  ),
                ],
                bubble_null: false,
              }
            }
            execute_selection_set(
              schema, runtime_type, selection_set, value, variables, fragments, context,
              path,
            )
          }
        Some(InterfaceDef(_)) | Some(UnionDef(_)) =>
          if value == GqlNull {
            { value: GqlNull, errors: [], bubble_null: false }
          } else {
            match
              resolve_abstract_runtime_type(schema, name, value, context, path) {
              Ok(runtime_type) =>
                execute_selection_set(
                  schema, runtime_type, selection_set, value, variables, fragments,
                  context, path,
                )
              Err(error) =>
                { value: GqlNull, errors: [error], bubble_null: false }
            }
          }
        Some(InputObjectDef(_)) | None =>
          {
            value: GqlNull,
            errors: [
              GraphQLError::new("cannot complete output type `\{name}`", path~),
            ],
            bubble_null: false,
          }
      }
  }
}

///|
fn[Ctx] collect_execution_fields(
  schema : ExecutableSchema[Ctx],
  runtime_type : String,
  selection_set : @parser.SelectionSet,
  variables : Map[String, InputValue],
  fragments : Map[String, @parser.FragmentDefinition],
) -> RuntimeFieldCollection {
  let collection = RuntimeFieldCollection::{ keys: [], fields: {} }
  collect_execution_fields_into(
    schema, runtime_type, selection_set, variables, fragments, collection,
  )
  collection
}

///|
fn[Ctx] collect_execution_fields_into(
  schema : ExecutableSchema[Ctx],
  runtime_type : String,
  selection_set : @parser.SelectionSet,
  variables : Map[String, InputValue],
  fragments : Map[String, @parser.FragmentDefinition],
  collection : RuntimeFieldCollection,
) -> Unit {
  for selection in selection_set.items {
    match selection {
      @parser.FieldSelection(field) =>
        if should_include(field.directives, variables) {
          append_execution_field(collection, field)
        }
      @parser.FragmentSpreadSelection(spread) =>
        if should_include(spread.directives, variables) {
          match fragments.get(spread.fragment_name) {
            Some(fragment) => {
              let @parser.On(fragment_type) = fragment.type_condition
              if types_overlap(schema.registry, runtime_type, fragment_type) {
                collect_execution_fields_into(
                  schema,
                  runtime_type,
                  fragment.selection_set,
                  variables,
                  fragments,
                  collection,
                )
              }
            }
            None => ()
          }
        }
      @parser.InlineFragmentSelection(fragment) =>
        if should_include(fragment.directives, variables) {
          let next_type = match fragment.type_condition {
            Some(@parser.On(name)) => name
            None => runtime_type
          }
          if types_overlap(schema.registry, runtime_type, next_type) {
            collect_execution_fields_into(
              schema,
              runtime_type,
              fragment.selection_set,
              variables,
              fragments,
              collection,
            )
          }
        }
    }
  }
}

///|
fn append_execution_field(
  collection : RuntimeFieldCollection,
  field : @parser.Field,
) -> Unit {
  let response_key = field.field_alias.unwrap_or(field.name)
  match collection.fields.get(response_key) {
    Some(fields) => fields.push(field)
    None => {
      collection.keys.push(response_key)
      collection.fields[response_key] = [field]
    }
  }
}

///|
fn merge_runtime_fields(fields : Array[@parser.Field]) -> @parser.Field {
  let first = fields[0]
  let items : Array[@parser.Selection] = []
  for field in fields {
    items.append(field.selection_set.items)
  }
  {
    position: first.position,
    field_alias: first.field_alias,
    name: first.name,
    arguments: first.arguments,
    directives: first.directives,
    selection_set: { span: first.selection_set.span, items },
  }
}

///|
async fn[Ctx] resolve_abstract_runtime_type(
  schema : ExecutableSchema[Ctx],
  abstract_type : String,
  value : GqlValue,
  context : Ctx,
  path : Array[PathSegment],
) -> Result[String, GraphQLError] {
  let runtime_type = match value {
    GqlTypedObject(type_name, _) => type_name
    _ =>
      match schema.type_resolvers.get(abstract_type) {
        Some(resolver) =>
          try resolver(abstract_type, value, context) catch {
            err =>
              return Err(
                GraphQLError::new(
                  "type resolver for `\{abstract_type}` failed: \{err}",
                  path~,
                ),
              )
          } noraise {
            type_name => type_name
          }
        None =>
          return Err(
            GraphQLError::new(
              "missing runtime type for abstract type `\{abstract_type}`",
              path~,
            ),
          )
      }
  }
  if abstract_type_accepts_runtime(schema.registry, abstract_type, runtime_type) {
    Ok(runtime_type)
  } else {
    Err(
      GraphQLError::new(
        "runtime type `\{runtime_type}` is not valid for abstract type `\{abstract_type}`",
        path~,
      ),
    )
  }
}

///|
fn abstract_type_accepts_runtime(
  registry : TypeRegistry,
  abstract_type : String,
  runtime_type : String,
) -> Bool {
  match registry.types.get(runtime_type) {
    Some(ObjectDef(_)) => ()
    _ => return false
  }
  match registry.types.get(abstract_type) {
    Some(InterfaceDef(_)) =>
      type_implements_interface(registry, runtime_type, abstract_type)
    Some(UnionDef(members~, ..)) => members.contains(runtime_type)
    _ => false
  }
}

///|
fn[Ctx] find_resolver(
  schema : ExecutableSchema[Ctx],
  type_name : String,
  field_name : String,
) -> Resolver[Ctx]? {
  schema.resolvers.get(resolver_key(type_name, field_name))
}

///|
fn should_include(
  directives : Array[@parser.Directive],
  variables : Map[String, InputValue],
) -> Bool {
  let mut is_included = true
  for directive in directives {
    if directive.name == "skip" || directive.name == "include" {
      let if_arg = find_argument(directive.arguments, "if")
      let condition = match if_arg {
        Some((_, value)) =>
          try parser_value_to_input(value, variables) catch {
            _ => false
          } noraise {
            InputBoolean(value) => value
            _ => false
          }
        None => false
      }
      if directive.name == "skip" && condition {
        is_included = false
      } else if directive.name == "include" && !condition {
        is_included = false
      }
    }
  }
  is_included
}

///|
fn find_argument(
  arguments : Array[(String, @parser.Value)],
  name : String,
) -> (String, @parser.Value)? {
  for argument in arguments {
    if argument.0 == name {
      return Some(argument)
    }
  }
  None
}

///|
fn[Ctx] introspect_type(schema : ExecutableSchema[Ctx], name : String) -> Json {
  match schema.registry.types.get(name) {
    Some(type_def) =>
      Json::object({
        "name": Json::string(name),
        "kind": Json::string(type_kind_name(type_def)),
        "fields": Json::array(introspection_fields(type_def)),
        "enumValues": Json::array(introspection_enum_values(type_def)),
        "inputFields": Json::array(introspection_input_fields(type_def)),
        "possibleTypes": Json::array(introspection_possible_types(type_def)),
      })
    None => Json::null()
  }
}
