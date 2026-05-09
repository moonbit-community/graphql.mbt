///|
/// Build a JSON introspection view of an executable schema.
///
/// `Full` returns root operation types, type metadata, field/input/enum details,
/// union members, and directives. `TypeNamesOnly` is a compact view for
/// diagnostics and simple tooling.
pub fn[Ctx] introspect(
  schema : ExecutableSchema[Ctx],
  format? : IntrospectionFormat = Full,
) -> Json {
  match format {
    TypeNamesOnly => {
      let names = schema.registry.types.keys().to_array()
      Json::object({
        "types": Json::array(names.map(name => Json::string(name))),
        "queryType": Json::string(schema.query_type),
      })
    }
    Full => {
      let types = schema.registry.types
        .keys()
        .to_array()
        .map(name => {
          let type_def = schema.registry.types[name]
          Json::object({
            "name": Json::string(name),
            "kind": Json::string(type_kind_name(type_def)),
            "fields": Json::array(introspection_fields(type_def)),
            "enumValues": Json::array(introspection_enum_values(type_def)),
            "inputFields": Json::array(introspection_input_fields(type_def)),
            "possibleTypes": Json::array(introspection_possible_types(type_def)),
          })
        })
      Json::object({
        "queryType": Json::object({ "name": Json::string(schema.query_type) }),
        "mutationType": option_type_ref(schema.mutation_type),
        "subscriptionType": option_type_ref(schema.subscription_type),
        "types": Json::array(types),
        "directives": Json::array(
          schema.registry.directives
          .keys()
          .to_array()
          .map(key => {
            let directive = schema.registry.directives[key]
            Json::object({
              "name": Json::string(directive.name),
              "locations": Json::array(
                directive.locations.map(loc => Json::string(loc)),
              ),
              "isRepeatable": Json::boolean(directive.repeatable),
              "args": Json::array(
                directive.arguments.map(arg => {
                  Json::object({
                    "name": Json::string(arg.name),
                    "type": Json::string(type_to_string(arg.value_type)),
                  })
                }),
              ),
            })
          }),
        ),
      })
    }
  }
}

///|
fn option_type_ref(type_name : String?) -> Json {
  match type_name {
    Some(name) => Json::object({ "name": Json::string(name) })
    None => Json::null()
  }
}

///|
fn type_kind_name(type_def : TypeDef) -> String {
  match type_def {
    ScalarDef(_) => "SCALAR"
    ObjectDef(_) => "OBJECT"
    InterfaceDef(_) => "INTERFACE"
    UnionDef(_) => "UNION"
    EnumDef(_) => "ENUM"
    InputObjectDef(_) => "INPUT_OBJECT"
  }
}

///|
fn introspection_fields(type_def : TypeDef) -> Array[Json] {
  match type_def {
    ObjectDef(fields~, ..) | InterfaceDef(fields~, ..) =>
      fields
      .values()
      .to_array()
      .map(field => {
        Json::object({
          "name": Json::string(field.name),
          "type": Json::string(type_to_string(field.field_type)),
          "args": Json::array(
            field.arguments.map(arg => {
              Json::object({
                "name": Json::string(arg.name),
                "type": Json::string(type_to_string(arg.value_type)),
              })
            }),
          ),
        })
      })
    _ => []
  }
}

///|
fn introspection_enum_values(type_def : TypeDef) -> Array[Json] {
  match type_def {
    EnumDef(values~, ..) =>
      values.map(value => Json::object({ "name": Json::string(value) }))
    _ => []
  }
}

///|
fn introspection_input_fields(type_def : TypeDef) -> Array[Json] {
  match type_def {
    InputObjectDef(fields~, ..) =>
      fields
      .values()
      .to_array()
      .map(field => {
        Json::object({
          "name": Json::string(field.name),
          "type": Json::string(type_to_string(field.value_type)),
        })
      })
    _ => []
  }
}

///|
fn introspection_possible_types(type_def : TypeDef) -> Array[Json] {
  match type_def {
    UnionDef(members~, ..) =>
      members.map(name => Json::object({ "name": Json::string(name) }))
    _ => []
  }
}
