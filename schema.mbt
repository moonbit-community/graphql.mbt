///|
/// Shape of the JSON introspection payload returned by `introspect`.
pub(all) enum IntrospectionFormat {
  /// Full schema metadata for types, fields, inputs, unions, enums, and
  /// directives.
  Full
  /// Compact metadata containing type names and the query root only.
  TypeNamesOnly
} derive(Eq, Debug)

///|
/// Runtime description of a directive available in a compiled schema.
pub(all) struct DirectiveSpec {
  name : String
  arguments : Array[@parser.InputValue]
  locations : Array[String]
  repeatable : Bool
} derive(Eq, Debug)

///|
/// Runtime field definition compiled from SDL.
///
/// The executor uses `arguments` for coercion, `field_type` for completion and
/// non-null bubbling, and `directives` for schema metadata.
pub(all) struct FieldDef {
  name : String
  arguments : Array[@parser.InputValue]
  field_type : @parser.GqlType
  directives : Array[@parser.Directive]
} derive(Eq, Debug)

///|
/// Runtime type definition compiled from GraphQL SDL.
///
/// Input and output definitions are stored together because validation and
/// introspection need to traverse the complete schema registry.
pub(all) enum TypeDef {
  ScalarDef(String?)
  ObjectDef(
    description~ : String?,
    fields~ : Map[String, FieldDef],
    interfaces~ : Array[String]
  )
  InterfaceDef(
    description~ : String?,
    fields~ : Map[String, FieldDef],
    interfaces~ : Array[String]
  )
  UnionDef(description~ : String?, members~ : Array[String])
  EnumDef(description~ : String?, values~ : Array[String])
  InputObjectDef(
    description~ : String?,
    fields~ : Map[String, @parser.InputValue]
  )
} derive(Eq, Debug)

///|
/// Return true for scalar and enum output types.
pub fn TypeDef::is_leaf(self : TypeDef) -> Bool {
  match self {
    ScalarDef(_) | EnumDef(_) => true
    _ => false
  }
}

///|
/// Return true when the type can appear in GraphQL input positions.
pub fn TypeDef::is_input(self : TypeDef) -> Bool {
  match self {
    ScalarDef(_) | EnumDef(_) | InputObjectDef(_) => true
    _ => false
  }
}

///|
/// Return field definitions for object and interface types.
pub fn TypeDef::fields(self : TypeDef) -> Map[String, FieldDef]? {
  match self {
    ObjectDef(fields~, ..) | InterfaceDef(fields~, ..) => Some(fields)
    _ => None
  }
}

///|
/// Compiled GraphQL schema registry.
///
/// The registry stores user SDL definitions plus built-in scalars and
/// directives. Public lookup helpers keep validators, executors, and tools from
/// depending on map internals.
pub(all) struct TypeRegistry {
  types : Map[String, TypeDef]
  directives : Map[String, DirectiveSpec]
} derive(Eq, Debug)

///|
/// Look up a compiled type by name.
pub fn TypeRegistry::get(self : TypeRegistry, name : String) -> TypeDef? {
  self.types.get(name)
}

///|
/// Return true when a type name exists in the registry.
pub fn TypeRegistry::contains(self : TypeRegistry, name : String) -> Bool {
  self.types.contains(name)
}

///|
/// Look up a field on an object or interface type.
pub fn TypeRegistry::field(
  self : TypeRegistry,
  type_name : String,
  field_name : String,
) -> FieldDef? {
  match self.types.get(type_name) {
    Some(ObjectDef(fields~, ..)) | Some(InterfaceDef(fields~, ..)) =>
      fields.get(field_name)
    _ => None
  }
}

///|
/// Validation toggles captured in an executable schema.
pub(all) struct ValidationConfig {
  disable_introspection : Bool
} derive(Eq, Debug)

///|
/// Default validation configuration.
pub fn ValidationConfig::default() -> ValidationConfig {
  { disable_introspection: false }
}

///|
/// Field resolver metadata supplied by the executor.
///
/// `response_key` includes aliases, `path` points to the response position, and
/// `source` carries the parent value being completed.
pub(all) struct ResolveInfo {
  type_name : String
  field_name : String
  response_key : String
  path : Array[PathSegment]
  source : GqlValue
} derive(Eq, Debug)

///|
/// Async field resolver signature used by `SchemaBuilder::resolve`.
pub type Resolver[Ctx] = async (ResolveInfo, Args, Ctx) -> GqlValue

///|
/// Async subscription resolver signature used by `SchemaBuilder::subscribe`.
pub type SubscriptionResolver[Ctx] = async (ResolveInfo, Args, Ctx) -> SubscriptionStream

///|
/// Async resolver used to choose a concrete object type for an interface or
/// union value that is not returned as `GqlTypedObject`.
pub type TypeResolver[Ctx] = async (String, GqlValue, Ctx) -> String

///|
/// Queue-backed stream of GraphQL subscription events.
///
/// Producers publish `GraphQLResponse` values and close the stream when no more
/// events will be sent.
pub(all) struct SubscriptionStream {
  queue : @aqueue.Queue[GraphQLResponse]
}

///|
/// Create an unbounded subscription stream.
pub fn SubscriptionStream::new() -> SubscriptionStream {
  { queue: @aqueue.Queue::new(kind=Unbounded) }
}

///|
/// Publish a response event to waiting subscription consumers.
pub async fn SubscriptionStream::publish(
  self : SubscriptionStream,
  response : GraphQLResponse,
) -> Unit {
  self.queue.put(response)
}

///|
/// Close the stream so future `next` calls finish with `None`.
pub fn SubscriptionStream::close(self : SubscriptionStream) -> Unit {
  self.queue.close()
}

///|
/// Wait for the next response event.
///
/// Returns `None` when the stream is closed or when the current async task is
/// being cancelled.
pub async fn SubscriptionStream::next(
  self : SubscriptionStream,
) -> GraphQLResponse? {
  if @async.is_being_cancelled() {
    return None
  }
  Some(self.queue.get()) catch {
    _ => None
  }
}

///|
/// Validated schema ready for execution.
///
/// Construct values with `SchemaBuilder::from_sdl(...).resolve(...).finish()`
/// so root resolver coverage and schema references are checked before use.
pub(all) struct ExecutableSchema[Ctx] {
  registry : TypeRegistry
  query_type : String
  mutation_type : String?
  subscription_type : String?
  resolvers : Map[String, Resolver[Ctx]]
  subscriptions : Map[String, SubscriptionResolver[Ctx]]
  type_resolvers : Map[String, TypeResolver[Ctx]]
  validation : ValidationConfig
}

///|
/// Return the names of all compiled types in the schema registry.
pub fn[Ctx] ExecutableSchema::type_names(
  self : ExecutableSchema[Ctx],
) -> Array[String] {
  self.registry.types.keys().to_array()
}

///|
/// Return the GraphQL query root type name.
pub fn[Ctx] ExecutableSchema::query_type(
  self : ExecutableSchema[Ctx],
) -> String {
  self.query_type
}

///|
/// Mutable builder used to compile SDL and register resolvers.
///
/// The builder is generic over user context type `Ctx`, allowing applications
/// to pass request-scoped state directly to resolvers.
pub(all) struct SchemaBuilder[Ctx] {
  registry : TypeRegistry
  query_type : String
  mutation_type : String?
  subscription_type : String?
  resolvers : Map[String, Resolver[Ctx]]
  subscriptions : Map[String, SubscriptionResolver[Ctx]]
  type_resolvers : Map[String, TypeResolver[Ctx]]
  validation : ValidationConfig
}

///|
/// Parse and compile GraphQL SDL into a resolver builder.
///
/// Built-in scalars and directives are installed automatically. Raises
/// `SchemaError` when SDL parsing, duplicate definitions, or schema references
/// fail validation.
pub fn[Ctx] SchemaBuilder::from_sdl(
  source : String,
) -> SchemaBuilder[Ctx] raise SchemaError {
  let document = try @parser.parse_schema(source) catch {
    err => schema_error(err.to_string())
  } noraise {
    document => document
  }
  let (registry, query_type, mutation_type, subscription_type) = compile_schema(
    document,
  )
  {
    registry,
    query_type,
    mutation_type,
    subscription_type,
    resolvers: {},
    subscriptions: {},
    type_resolvers: {},
    validation: ValidationConfig::default(),
  }
}

///|
/// Register an async resolver for an object or interface field.
///
/// The resolver key is the pair `(type_name, field_name)`. Register root field
/// resolvers before calling `finish`.
pub fn[Ctx] SchemaBuilder::resolve(
  self : SchemaBuilder[Ctx],
  type_name : String,
  field_name : String,
  resolver : Resolver[Ctx],
) -> SchemaBuilder[Ctx] {
  self.resolvers[resolver_key(type_name, field_name)] = resolver
  self
}

///|
/// Register an async resolver for a subscription root field.
pub fn[Ctx] SchemaBuilder::subscribe(
  self : SchemaBuilder[Ctx],
  type_name : String,
  field_name : String,
  resolver : SubscriptionResolver[Ctx],
) -> SchemaBuilder[Ctx] {
  self.subscriptions[resolver_key(type_name, field_name)] = resolver
  self
}

///|
/// Register an async resolver for an interface or union runtime type.
///
/// `finish` validates that `type_name` names an abstract output type.
pub fn[Ctx] SchemaBuilder::resolve_type(
  self : SchemaBuilder[Ctx],
  type_name : String,
  resolver : TypeResolver[Ctx],
) -> SchemaBuilder[Ctx] {
  self.type_resolvers[type_name] = resolver
  self
}

///|
/// Enable or disable access to `__schema`, `__type`, and other introspection
/// fields during request validation.
pub fn[Ctx] SchemaBuilder::disable_introspection(
  self : SchemaBuilder[Ctx],
  disabled : Bool,
) -> SchemaBuilder[Ctx] {
  {
    registry: self.registry,
    query_type: self.query_type,
    mutation_type: self.mutation_type,
    subscription_type: self.subscription_type,
    resolvers: self.resolvers,
    subscriptions: self.subscriptions,
    type_resolvers: self.type_resolvers,
    validation: { disable_introspection: disabled },
  }
}

///|
/// Validate resolver coverage and freeze the builder into an executable schema.
///
/// Query and mutation root fields must have regular resolvers. Subscription
/// root fields may have either regular execution resolvers or subscription
/// stream resolvers.
pub fn[Ctx] SchemaBuilder::finish(
  self : SchemaBuilder[Ctx],
) -> ExecutableSchema[Ctx] raise SchemaError {
  require_root_resolvers(
    self.registry,
    self.query_type,
    self.resolvers,
    allow_subscription=false,
  )
  match self.mutation_type {
    Some(type_name) =>
      require_root_resolvers(
        self.registry,
        type_name,
        self.resolvers,
        allow_subscription=false,
      )
    None => ()
  }
  match self.subscription_type {
    Some(type_name) =>
      require_root_resolvers(
        self.registry,
        type_name,
        self.resolvers,
        subscriptions=self.subscriptions,
        allow_subscription=true,
      )
    None => ()
  }
  validate_type_resolvers(self.registry, self.type_resolvers)
  {
    registry: self.registry,
    query_type: self.query_type,
    mutation_type: self.mutation_type,
    subscription_type: self.subscription_type,
    resolvers: self.resolvers,
    subscriptions: self.subscriptions,
    type_resolvers: self.type_resolvers,
    validation: self.validation,
  }
}

///|
fn resolver_key(type_name : String, field_name : String) -> String {
  type_name + "." + field_name
}

///|
/// Compile parsed SDL into a registry and root operation type names.
///
/// The compiler first installs GraphQL built-ins, then loads definitions and
/// extensions, validates directive placements, and finally checks every type
/// reference against the complete registry.
fn compile_schema(
  document : @parser.SchemaDocument,
) -> (TypeRegistry, String, String?, String?) raise SchemaError {
  let registry = TypeRegistry::{ types: {}, directives: {} }
  install_builtins(registry)
  let mut query_type : String? = None
  let mut mutation_type : String? = None
  let mut subscription_type : String? = None
  for definition in document.definitions {
    match definition {
      SchemaDef(schema) => {
        if query_type != None ||
          mutation_type != None ||
          subscription_type != None {
          schema_error("duplicate schema definition")
        }
        query_type = schema.query
        mutation_type = schema.mutation
        subscription_type = schema.subscription
      }
      TypeDef(type_def) => install_type_definition(registry, type_def)
      TypeExt(type_ext) => extend_type_definition(registry, type_ext)
      DirectiveDef(directive) =>
        install_directive_definition(registry, directive)
    }
  }
  let query = query_type.unwrap_or("Query")
  let mutation = match mutation_type {
    Some(_) => mutation_type
    None => if registry.contains("Mutation") { Some("Mutation") } else { None }
  }
  let subscription = match subscription_type {
    Some(_) => subscription_type
    None =>
      if registry.contains("Subscription") {
        Some("Subscription")
      } else {
        None
      }
  }
  if !registry.contains(query) {
    schema_error("missing query root type `\{query}`")
  }
  validate_schema_directive_uses(registry, document)
  validate_schema_references(registry, query, mutation, subscription)
  (registry, query, mutation, subscription)
}

///|
/// Install the scalar and directive definitions required by the GraphQL spec.
fn install_builtins(registry : TypeRegistry) -> Unit {
  for name in ["String", "Int", "Float", "Boolean", "ID"] {
    registry.types[name] = ScalarDef(None)
  }
  registry.directives["@skip"] = {
    name: "skip",
    arguments: [builtin_directive_arg("if", non_null_named("Boolean"), None)],
    locations: ["FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT"],
    repeatable: false,
  }
  registry.directives["@include"] = {
    name: "include",
    arguments: [builtin_directive_arg("if", non_null_named("Boolean"), None)],
    locations: ["FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT"],
    repeatable: false,
  }
  registry.directives["@deprecated"] = {
    name: "deprecated",
    arguments: [
      builtin_directive_arg(
        "reason",
        NamedType("String"),
        Some(StringValue("No longer supported")),
      ),
    ],
    locations: [
      "FIELD_DEFINITION", "ARGUMENT_DEFINITION", "ENUM_VALUE", "INPUT_FIELD_DEFINITION",
    ],
    repeatable: false,
  }
  registry.directives["@specifiedBy"] = {
    name: "specifiedBy",
    arguments: [builtin_directive_arg("url", non_null_named("String"), None)],
    locations: ["SCALAR"],
    repeatable: false,
  }
}

///|
fn non_null_named(name : String) -> @parser.GqlType {
  NonNullType(NamedType(name))
}

///|
fn builtin_directive_arg(
  name : String,
  value_type : @parser.GqlType,
  default_value : @parser.Value?,
) -> @parser.InputValue {
  {
    position: { line: 0, column: 0 },
    description: None,
    name,
    value_type,
    default_value,
    directives: [],
  }
}

///|
fn install_type_definition(
  registry : TypeRegistry,
  type_def : @parser.TypeDefinition,
) -> Unit raise SchemaError {
  let (name, compiled) = match type_def {
    ScalarTypeDef(def) => (def.name, ScalarDef(def.description))
    ObjectTypeDef(def) =>
      (
        def.name,
        ObjectDef(
          description=def.description,
          fields=schema_fields_to_map(def.fields),
          interfaces=def.implements_interfaces,
        ),
      )
    InterfaceTypeDef(def) =>
      (
        def.name,
        InterfaceDef(
          description=def.description,
          fields=schema_fields_to_map(def.fields),
          interfaces=def.implements_interfaces,
        ),
      )
    UnionTypeDef(def) =>
      (def.name, UnionDef(description=def.description, members=def.types))
    EnumTypeDef(def) =>
      (
        def.name,
        EnumDef(
          description=def.description,
          values=def.values.map(value => value.name),
        ),
      )
    InputObjectTypeDef(def) =>
      (
        def.name,
        InputObjectDef(
          description=def.description,
          fields=input_values_to_map(def.fields),
        ),
      )
  }
  if registry.types.contains(name) {
    schema_error("duplicate type `\{name}`")
  }
  registry.types[name] = compiled
}

///|
fn extend_type_definition(
  registry : TypeRegistry,
  type_ext : @parser.TypeExtension,
) -> Unit raise SchemaError {
  match type_ext {
    ScalarTypeExt(def) =>
      if !registry.types.contains(def.name) {
        schema_error("cannot extend unknown scalar `\{def.name}`")
      }
    ObjectTypeExt(def) => {
      let current = match registry.types.get(def.name) {
        Some(ObjectDef(description~, fields~, interfaces~)) =>
          (description, fields, interfaces)
        _ => schema_error("cannot extend unknown object `\{def.name}`")
      }
      merge_field_maps(current.1, schema_fields_to_map(def.fields), def.name)
      for iface in def.implements_interfaces {
        if !current.2.contains(iface) {
          current.2.push(iface)
        }
      }
    }
    InterfaceTypeExt(def) => {
      let current = match registry.types.get(def.name) {
        Some(InterfaceDef(description~, fields~, interfaces~)) =>
          (description, fields, interfaces)
        _ => schema_error("cannot extend unknown interface `\{def.name}`")
      }
      merge_field_maps(current.1, schema_fields_to_map(def.fields), def.name)
      for iface in def.implements_interfaces {
        if !current.2.contains(iface) {
          current.2.push(iface)
        }
      }
    }
    UnionTypeExt(def) =>
      match registry.types.get(def.name) {
        Some(UnionDef(members~, ..)) =>
          for type_ref in def.types {
            if !members.contains(type_ref) {
              members.push(type_ref)
            }
          }
        _ => schema_error("cannot extend unknown union `\{def.name}`")
      }
    EnumTypeExt(def) =>
      match registry.types.get(def.name) {
        Some(EnumDef(values~, ..)) =>
          for value in def.values {
            if values.contains(value.name) {
              schema_error("duplicate enum value `\{def.name}.\{value.name}`")
            }
            values.push(value.name)
          }
        _ => schema_error("cannot extend unknown enum `\{def.name}`")
      }
    InputObjectTypeExt(def) =>
      match registry.types.get(def.name) {
        Some(InputObjectDef(fields~, ..)) =>
          merge_input_maps(fields, input_values_to_map(def.fields), def.name)
        _ => schema_error("cannot extend unknown input object `\{def.name}`")
      }
  }
}

///|
fn install_directive_definition(
  registry : TypeRegistry,
  directive : @parser.DirectiveDefinition,
) -> Unit raise SchemaError {
  let key = "@" + directive.name
  if registry.directives.contains(key) {
    schema_error("duplicate directive `\{directive.name}`")
  }
  registry.directives[key] = {
    name: directive.name,
    arguments: directive.arguments,
    locations: directive.locations.map(location => location.as_string()),
    repeatable: directive.repeatable,
  }
}

///|
fn schema_fields_to_map(
  fields : Array[@parser.SchemaField],
) -> Map[String, FieldDef] raise SchemaError {
  let map : Map[String, FieldDef] = {}
  for field in fields {
    if map.contains(field.name) {
      schema_error("duplicate field `\{field.name}`")
    }
    map[field.name] = {
      name: field.name,
      arguments: field.arguments,
      field_type: field.field_type,
      directives: field.directives,
    }
  }
  map
}

///|
fn input_values_to_map(
  values : Array[@parser.InputValue],
) -> Map[String, @parser.InputValue] raise SchemaError {
  let map : Map[String, @parser.InputValue] = {}
  for value in values {
    if map.contains(value.name) {
      schema_error("duplicate input field or argument `\{value.name}`")
    }
    map[value.name] = value
  }
  map
}

///|
fn merge_field_maps(
  target : Map[String, FieldDef],
  extension : Map[String, FieldDef],
  owner : String,
) -> Unit raise SchemaError {
  for name, field in extension.iter2() {
    if target.contains(name) {
      schema_error("duplicate field `\{owner}.\{name}`")
    }
    target[name] = field
  }
}

///|
fn merge_input_maps(
  target : Map[String, @parser.InputValue],
  extension : Map[String, @parser.InputValue],
  owner : String,
) -> Unit raise SchemaError {
  for name, field in extension.iter2() {
    if target.contains(name) {
      schema_error("duplicate input field `\{owner}.\{name}`")
    }
    target[name] = field
  }
}

///|
fn validate_schema_directive_uses(
  registry : TypeRegistry,
  document : @parser.SchemaDocument,
) -> Unit raise SchemaError {
  for definition in document.definitions {
    match definition {
      SchemaDef(schema) =>
        schema_validate_directives(registry, schema.directives, "SCHEMA")
      TypeDef(type_def) =>
        validate_type_definition_directives(registry, type_def)
      TypeExt(type_ext) =>
        validate_type_extension_directives(registry, type_ext)
      DirectiveDef(directive) =>
        schema_validate_input_values(
          registry,
          directive.arguments,
          "ARGUMENT_DEFINITION",
        )
    }
  }
}

///|
fn validate_type_definition_directives(
  registry : TypeRegistry,
  type_def : @parser.TypeDefinition,
) -> Unit raise SchemaError {
  match type_def {
    ScalarTypeDef(def) =>
      schema_validate_directives(registry, def.directives, "SCALAR")
    ObjectTypeDef(def) => {
      schema_validate_directives(registry, def.directives, "OBJECT")
      schema_validate_fields(registry, def.fields)
    }
    InterfaceTypeDef(def) => {
      schema_validate_directives(registry, def.directives, "INTERFACE")
      schema_validate_fields(registry, def.fields)
    }
    UnionTypeDef(def) =>
      schema_validate_directives(registry, def.directives, "UNION")
    EnumTypeDef(def) => {
      schema_validate_directives(registry, def.directives, "ENUM")
      for value in def.values {
        schema_validate_directives(registry, value.directives, "ENUM_VALUE")
      }
    }
    InputObjectTypeDef(def) => {
      schema_validate_directives(registry, def.directives, "INPUT_OBJECT")
      schema_validate_input_values(
        registry,
        def.fields,
        "INPUT_FIELD_DEFINITION",
      )
    }
  }
}

///|
fn validate_type_extension_directives(
  registry : TypeRegistry,
  type_ext : @parser.TypeExtension,
) -> Unit raise SchemaError {
  match type_ext {
    ScalarTypeExt(def) =>
      schema_validate_directives(registry, def.directives, "SCALAR")
    ObjectTypeExt(def) => {
      schema_validate_directives(registry, def.directives, "OBJECT")
      schema_validate_fields(registry, def.fields)
    }
    InterfaceTypeExt(def) => {
      schema_validate_directives(registry, def.directives, "INTERFACE")
      schema_validate_fields(registry, def.fields)
    }
    UnionTypeExt(def) =>
      schema_validate_directives(registry, def.directives, "UNION")
    EnumTypeExt(def) => {
      schema_validate_directives(registry, def.directives, "ENUM")
      for value in def.values {
        schema_validate_directives(registry, value.directives, "ENUM_VALUE")
      }
    }
    InputObjectTypeExt(def) => {
      schema_validate_directives(registry, def.directives, "INPUT_OBJECT")
      schema_validate_input_values(
        registry,
        def.fields,
        "INPUT_FIELD_DEFINITION",
      )
    }
  }
}

///|
fn schema_validate_fields(
  registry : TypeRegistry,
  fields : Array[@parser.SchemaField],
) -> Unit raise SchemaError {
  for field in fields {
    schema_validate_directives(registry, field.directives, "FIELD_DEFINITION")
    schema_validate_input_values(
      registry,
      field.arguments,
      "ARGUMENT_DEFINITION",
    )
  }
}

///|
fn schema_validate_input_values(
  registry : TypeRegistry,
  values : Array[@parser.InputValue],
  location : String,
) -> Unit raise SchemaError {
  for value in values {
    schema_validate_directives(registry, value.directives, location)
  }
}

///|
fn schema_validate_directives(
  registry : TypeRegistry,
  directives : Array[@parser.Directive],
  location : String,
) -> Unit raise SchemaError {
  let seen : Map[String, Bool] = {}
  for directive in directives {
    let spec = match registry.directives.get("@" + directive.name) {
      Some(spec) => spec
      None => schema_error("unknown directive `@\{directive.name}`")
    }
    if !spec.locations.contains(location) {
      schema_error(
        "directive `@\{directive.name}` is not allowed at \{location}",
      )
    }
    if seen.contains(directive.name) && !spec.repeatable {
      schema_error("duplicate directive `@\{directive.name}`")
    }
    seen[directive.name] = true
    schema_validate_directive_arguments(spec, directive.arguments)
  }
}

///|
fn schema_validate_directive_arguments(
  spec : DirectiveSpec,
  arguments : Array[(String, @parser.Value)],
) -> Unit raise SchemaError {
  let seen : Map[String, Bool] = {}
  for pair in arguments {
    let name = pair.0
    if seen.contains(name) {
      schema_error("duplicate argument `@\{spec.name}(\{name}:)`")
    }
    seen[name] = true
    if !spec.arguments.any(arg => arg.name == name) {
      schema_error("unknown argument `@\{spec.name}(\{name}:)`")
    }
  }
  for argument in spec.arguments {
    if is_non_null(argument.value_type) &&
      argument.default_value == None &&
      !seen.contains(argument.name) {
      schema_error(
        "directive `@\{spec.name}` requires argument `\{argument.name}`",
      )
    }
  }
}

///|
/// Validate cross-type references after all SDL definitions and extensions have
/// been installed.
///
/// This pass catches missing field return types, input object field types,
/// invalid union members, and interface implementation mismatches.
fn validate_schema_references(
  registry : TypeRegistry,
  query : String,
  mutation : String?,
  subscription : String?,
) -> Unit raise SchemaError {
  assert_output_type(registry, query, "query root")
  match mutation {
    Some(type_name) => assert_output_type(registry, type_name, "mutation root")
    None => ()
  }
  match subscription {
    Some(type_name) =>
      assert_output_type(registry, type_name, "subscription root")
    None => ()
  }
  for type_name, type_def in registry.types.iter2() {
    match type_def {
      ObjectDef(fields~, interfaces~, ..)
      | InterfaceDef(fields~, interfaces~, ..) => {
        for iface in interfaces {
          match registry.types.get(iface) {
            Some(InterfaceDef(fields=iface_fields, ..)) =>
              validate_interface_fields(type_name, fields, iface, iface_fields)
            Some(_) =>
              schema_error("`\{type_name}` implements non-interface `\{iface}`")
            None =>
              schema_error(
                "`\{type_name}` implements unknown interface `\{iface}`",
              )
          }
        }
        for _, field in fields.iter2() {
          assert_known_output_type(
            registry,
            field.field_type,
            "\{type_name}.\{field.name}",
          )
          for arg in field.arguments {
            assert_known_input_type(
              registry,
              arg.value_type,
              "\{type_name}.\{field.name}(\{arg.name})",
            )
          }
        }
      }
      UnionDef(members~, ..) =>
        for type_ref in members {
          match registry.types.get(type_ref) {
            Some(ObjectDef(_)) => ()
            Some(_) =>
              schema_error(
                "union `\{type_name}` contains non-object `\{type_ref}`",
              )
            None =>
              schema_error(
                "union `\{type_name}` contains unknown type `\{type_ref}`",
              )
          }
        }
      InputObjectDef(fields~, ..) =>
        for _, field in fields.iter2() {
          assert_known_input_type(
            registry,
            field.value_type,
            "\{type_name}.\{field.name}",
          )
        }
      _ => ()
    }
  }
}

///|
fn validate_interface_fields(
  type_name : String,
  fields : Map[String, FieldDef],
  iface : String,
  iface_fields : Map[String, FieldDef],
) -> Unit raise SchemaError {
  for name, iface_field in iface_fields.iter2() {
    let field = match fields.get(name) {
      Some(field) => field
      None =>
        schema_error(
          "`\{type_name}` implements `\{iface}` but misses field `\{name}`",
        )
    }
    if field.field_type != iface_field.field_type {
      schema_error(
        "`\{type_name}.\{name}` type does not match interface `\{iface}.\{name}`",
      )
    }
    validate_interface_arguments(type_name, field, iface, iface_field)
  }
}

///|
fn validate_interface_arguments(
  type_name : String,
  field : FieldDef,
  iface : String,
  iface_field : FieldDef,
) -> Unit raise SchemaError {
  for iface_arg in iface_field.arguments {
    let arg = match find_schema_argument(field.arguments, iface_arg.name) {
      Some(arg) => arg
      None =>
        schema_error(
          "`\{type_name}.\{field.name}` misses interface argument `\{iface_arg.name}` from `\{iface}.\{iface_field.name}`",
        )
    }
    if arg.value_type != iface_arg.value_type {
      schema_error(
        "`\{type_name}.\{field.name}(\{arg.name})` type does not match interface argument",
      )
    }
  }
  for arg in field.arguments {
    let declared_by_interface = iface_field.arguments.any(iface_arg => {
      iface_arg.name == arg.name
    })
    if !declared_by_interface &&
      is_non_null(arg.value_type) &&
      arg.default_value == None {
      schema_error(
        "`\{type_name}.\{field.name}` adds required argument `\{arg.name}` not declared by interface `\{iface}`",
      )
    }
  }
}

///|
fn find_schema_argument(
  arguments : Array[@parser.InputValue],
  name : String,
) -> @parser.InputValue? {
  for argument in arguments {
    if argument.name == name {
      return Some(argument)
    }
  }
  None
}

///|
fn assert_output_type(
  registry : TypeRegistry,
  type_name : String,
  usage : String,
) -> Unit raise SchemaError {
  match registry.types.get(type_name) {
    Some(ObjectDef(_)) => ()
    Some(_) => schema_error("`\{type_name}` cannot be used as \{usage}")
    None => schema_error("unknown type `\{type_name}` used as \{usage}")
  }
}

///|
fn assert_known_output_type(
  registry : TypeRegistry,
  gql_type : @parser.GqlType,
  usage : String,
) -> Unit raise SchemaError {
  let name = named_type(gql_type)
  match registry.types.get(name) {
    Some(ScalarDef(_))
    | Some(ObjectDef(_))
    | Some(InterfaceDef(_))
    | Some(UnionDef(_))
    | Some(EnumDef(_)) => ()
    Some(InputObjectDef(_)) =>
      schema_error("input object `\{name}` cannot be output from \{usage}")
    None => schema_error("unknown output type `\{name}` in \{usage}")
  }
}

///|
fn assert_known_input_type(
  registry : TypeRegistry,
  gql_type : @parser.GqlType,
  usage : String,
) -> Unit raise SchemaError {
  let name = named_type(gql_type)
  match registry.types.get(name) {
    Some(ScalarDef(_)) | Some(EnumDef(_)) | Some(InputObjectDef(_)) => ()
    Some(_) =>
      schema_error("output type `\{name}` cannot be used as input in \{usage}")
    None => schema_error("unknown input type `\{name}` in \{usage}")
  }
}

///|
fn named_type(gql_type : @parser.GqlType) -> String {
  match gql_type {
    NamedType(name) => name
    ListType(inner) | NonNullType(inner) => named_type(inner)
  }
}

///|
fn type_implements_interface(
  registry : TypeRegistry,
  type_name : String,
  interface_name : String,
) -> Bool {
  type_implements_interface_seen(registry, type_name, interface_name, [])
}

///|
fn type_implements_interface_seen(
  registry : TypeRegistry,
  type_name : String,
  interface_name : String,
  seen : Array[String],
) -> Bool {
  if seen.contains(type_name) {
    return false
  }
  let interfaces = match registry.types.get(type_name) {
    Some(ObjectDef(interfaces~, ..)) | Some(InterfaceDef(interfaces~, ..)) =>
      interfaces
    _ => return false
  }
  if interfaces.contains(interface_name) {
    return true
  }
  let next_seen = seen.copy()
  next_seen.push(type_name)
  for parent in interfaces {
    if type_implements_interface_seen(
        registry, parent, interface_name, next_seen,
      ) {
      return true
    }
  }
  false
}

///|
/// Ensure root operation fields have execution or subscription resolvers before
/// the builder can produce an executable schema.
fn[Ctx] require_root_resolvers(
  registry : TypeRegistry,
  type_name : String,
  resolvers : Map[String, Resolver[Ctx]],
  subscriptions? : Map[String, SubscriptionResolver[Ctx]],
  allow_subscription~ : Bool,
) -> Unit raise SchemaError {
  let fields = match registry.types.get(type_name) {
    Some(ObjectDef(fields~, ..)) => fields
    _ => schema_error("root type `\{type_name}` is not an object")
  }
  for field_name, _ in fields.iter2() {
    let key = resolver_key(type_name, field_name)
    let has_resolver = resolvers.contains(key)
    let has_subscription = match subscriptions {
      Some(subs) => subs.contains(key)
      None => false
    }
    if !has_resolver && !(allow_subscription && has_subscription) {
      schema_error("missing resolver for root field `\{key}`")
    }
  }
}

///|
fn[Ctx] validate_type_resolvers(
  registry : TypeRegistry,
  type_resolvers : Map[String, TypeResolver[Ctx]],
) -> Unit raise SchemaError {
  for type_name, _ in type_resolvers.iter2() {
    match registry.types.get(type_name) {
      Some(InterfaceDef(_)) | Some(UnionDef(_)) => ()
      Some(_) =>
        schema_error(
          "type resolver `\{type_name}` must target an interface or union",
        )
      None => schema_error("type resolver targets unknown type `\{type_name}`")
    }
  }
}
