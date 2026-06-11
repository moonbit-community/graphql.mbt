///|
suberror ResolverFailure {
  ResolverFailure(String)
} derive(Debug)

///|
fn luke() -> GqlValue {
  GqlValue::typed_object("Human", [
    ("id", GqlString("1000")),
    ("name", GqlString("Luke Skywalker")),
    ("homePlanet", GqlString("Tatooine")),
    (
      "friends",
      GqlList([
        GqlValue::typed_object("Droid", [
          ("id", GqlString("2001")),
          ("name", GqlString("R2-D2")),
          ("primaryFunction", GqlString("Astromech")),
          ("friends", GqlList([])),
        ]),
      ]),
    ),
  ])
}

///|
fn artoo() -> GqlValue {
  GqlValue::typed_object("Droid", [
    ("id", GqlString("2001")),
    ("name", GqlString("R2-D2")),
    ("primaryFunction", GqlString("Astromech")),
    ("friends", GqlList([luke()])),
  ])
}

///|
fn star_wars_sdl() -> String {
  (
    #|schema {
    #|  query: Query
    #|}
    #|
    #|enum Episode {
    #|  NEWHOPE
    #|  EMPIRE
    #|  JEDI
    #|}
    #|
    #|input HeroInput {
    #|  episode: Episode! = NEWHOPE
    #|}
    #|
    #|interface Character {
    #|  id: ID!
    #|  name: String!
    #|  friends: [Character!]!
    #|}
    #|
    #|type Human implements Character {
    #|  id: ID!
    #|  name: String!
    #|  friends: [Character!]!
    #|  homePlanet: String
    #|}
    #|
    #|type Droid implements Character {
    #|  id: ID!
    #|  name: String!
    #|  friends: [Character!]!
    #|  primaryFunction: String
    #|}
    #|
    #|union SearchResult = Human | Droid
    #|
    #|type Query {
    #|  hero(episode: Episode = NEWHOPE): Character!
    #|  heroByInput(input: HeroInput!): Character!
    #|  search(text: String): [SearchResult!]!
    #|  broken: String!
    #|}
  )
}

///|
fn star_wars_schema() -> ExecutableSchema[Unit] raise SchemaError {
  let builder : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(star_wars_sdl())
  builder
  .resolve("Query", "hero", async fn(_info, args, _ctx) {
    @async.sleep(0)
    let episode : String = args.get("episode")
    if episode == "JEDI" {
      artoo()
    } else {
      luke()
    }
  })
  .resolve("Query", "heroByInput", async fn(_info, args, _ctx) {
    @async.sleep(0)
    let input : Json = args.get("input")
    match input {
      Object(fields) =>
        match fields.get("episode") {
          Some(String("JEDI")) => artoo()
          _ => luke()
        }
      _ => luke()
    }
  })
  .resolve("Query", "search", async fn(_info, _args, _ctx) {
    @async.sleep(0)
    GqlList([luke(), artoo()])
  })
  .resolve("Query", "broken", async fn(_info, _args, _ctx) {
    @async.sleep(0)
    raise ResolverFailure("resolver failed")
  })
  .finish()
}

///|
async test "execute variables fragments directives and interfaces" {
  let schema = star_wars_schema()
  let request = GraphQLRequest::new(
    (
      #|query Hero($episode: Episode!, $withFriends: Boolean!) {
      #|  hero(episode: $episode) {
      #|    __typename
      #|    id
      #|    name
      #|    ... on Human {
      #|      homePlanet
      #|    }
      #|    friends @include(if: $withFriends) {
      #|      __typename
      #|      name
      #|    }
      #|  }
      #|}
    ),
    variables={
      "episode": InputEnum("NEWHOPE"),
      "withFriends": InputBoolean(true),
    },
  )
  let response = execute(schema, request, ())
  inspect(
    response.to_json().stringify(),
    content=(
      #|{"data":{"hero":{"__typename":"Human","id":"1000","name":"Luke Skywalker","homePlanet":"Tatooine","friends":[{"__typename":"Droid","name":"R2-D2"}]}}}
    ),
  )
}

///|
async test "execute input objects aliases and union fragments" {
  let schema = star_wars_schema()
  let request = GraphQLRequest::new(
    (
      #|query Search($input: HeroInput!) {
      #|  jedi: heroByInput(input: $input) {
      #|    __typename
      #|    name
      #|  }
      #|  search(text: "droid") {
      #|    __typename
      #|    ... on Human {
      #|      homePlanet
      #|    }
      #|    ... on Droid {
      #|      primaryFunction
      #|    }
      #|  }
      #|}
    ),
    variables={ "input": InputObject({ "episode": InputEnum("JEDI") }) },
  )
  let response = execute(schema, request, ())
  inspect(
    response.to_json().stringify(),
    content=(
      #|{"data":{"jedi":{"__typename":"Droid","name":"R2-D2"},"search":[{"__typename":"Human","homePlanet":"Tatooine"},{"__typename":"Droid","primaryFunction":"Astromech"}]}}
    ),
  )
}

///|
async test "validation and resolver errors are reported" {
  let schema = star_wars_schema()
  let invalid = execute(
    schema,
    GraphQLRequest::new("query { hero { unknownField } }"),
    (),
  )
  assert_true(invalid.data == None)
  assert_true(invalid.errors[0].message.contains("unknown field"))
  let failed = execute(schema, GraphQLRequest::new("query { broken }"), ())
  assert_true(failed.data != None)
  assert_true(!failed.errors.is_empty())
}

///|
async test "validation checks fragments variables inputs and directives" {
  let schema = star_wars_schema()
  let bad_fragment = execute(
    schema,
    GraphQLRequest::new(
      "query { hero { ...Bad } } fragment Bad on Human { missing }",
    ),
    (),
  )
  assert_true(
    bad_fragment.errors[0].message.contains("unknown field `Human.missing`"),
  )
  let unused_variable = execute(
    schema,
    GraphQLRequest::new("query($episode: Episode) { hero { id } }"),
    (),
  )
  assert_true(
    unused_variable.errors[0].message.contains(
      "variable `$episode` is never used",
    ),
  )
  let mismatched_variable = execute(
    schema,
    GraphQLRequest::new(
      "query($episode: String!) { hero(episode: $episode) { id } }",
    ),
    (),
  )
  assert_true(
    mismatched_variable.errors[0].message.contains(
      "cannot be used as `Episode`",
    ),
  )
  let bad_input = execute(
    schema,
    GraphQLRequest::new(
      "{ heroByInput(input: { episode: JEDI extra: true }) { id } }",
    ),
    (),
  )
  assert_true(
    bad_input.errors[0].message.contains("unknown field `HeroInput.extra`"),
  )
  let bad_directive = execute(
    schema,
    GraphQLRequest::new("query @skip(if: true) { hero { id } }"),
    (),
  )
  assert_true(bad_directive.errors[0].message.contains("not allowed at QUERY"))
}

///|
test "schema compiler rejects duplicate and missing references" {
  @test.assert_raise(() => {
    let _ : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(
      (
        #|type Query { a: String }
        #|type Query { b: String }
      ),
    )
  })
  @test.assert_raise(() => {
    let _ : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(
      (
        #|type Query { a: Missing }
      ),
    )
  })
  @test.assert_raise(() => {
    let _ : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(
      (
        #|interface Node { id: ID! }
        #|type Query implements Node { name: String }
      ),
    )
  })
  @test.assert_raise(() => {
    let _ : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(
      (
        #|type Query @deprecated { a: String }
      ),
    )
  })
  @test.assert_raise(() => {
    let _ : ExecutableSchema[Unit] = SchemaBuilder::from_sdl(
        (
          #|type Query {
          #|  ping: String
          #|}
        ),
      )
      .resolve("Query", "ping", async fn(_info, _args, _ctx) {
        @async.sleep(0)
        GqlString("pong")
      })
      .resolve_type("Query", async fn(_abstract, _value, _ctx) {
        @async.sleep(0)
        "Query"
      })
      .finish()
  })
}

///|
async test "introspection exposes schema metadata" {
  let schema = star_wars_schema()
  let direct = introspect(schema, format=TypeNamesOnly)
  assert_true(direct.stringify().contains("Character"))
  let response = execute(
    schema,
    GraphQLRequest::new(
      (
        #|query {
        #|  __schema
        #|}
      ),
    ),
    (),
  )
  assert_true(response.to_json().stringify().contains("queryType"))
  let disabled = SchemaBuilder::from_sdl(
      (
        #|type Query {
        #|  ping: String!
        #|}
      ),
    )
    .resolve("Query", "ping", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlString("pong")
    })
    .disable_introspection(true)
    .finish()
  let denied = execute(disabled, GraphQLRequest::new("query { __schema }"), ())
  assert_true(!denied.errors.is_empty())
}

///|
async test "subscription resolver returns queue backed stream" {
  let sdl =
    #|schema {
    #|  query: Query
    #|  subscription: Subscription
    #|}
    #|
    #|type Query {
    #|  ping: String!
    #|}
    #|
    #|type Subscription {
    #|  count: Int!
    #|}
  let builder : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(sdl)
  let schema = builder
    .resolve("Query", "ping", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlString("pong")
    })
    .subscribe("Subscription", "count", async fn(_info, _args, _ctx) {
      let stream = SubscriptionStream::new()
      stream.publish(GraphQLResponse::data(GqlObject({ "count": GqlInt(1) })))
      stream.close()
      stream
    })
    .finish()
  let result = start_subscription(
    schema,
    GraphQLRequest::new("subscription { count }"),
    (),
  )
  match result {
    Ok(stream) =>
      match stream.next() {
        Some(response) =>
          assert_eq(response.to_json().stringify(), "{\"data\":{\"count\":1}}")
        None => fail("expected subscription event")
      }
    Err(response) => fail(response.to_json().stringify())
  }
}

///|
async test "merged fields execute resolver once and keep nested selections" {
  let calls : Array[Int] = []
  let schema = SchemaBuilder::from_sdl(
      (
        #|type Query {
        #|  user: User!
        #|}
        #|
        #|type User {
        #|  id: ID!
        #|  name: String!
        #|}
      ),
    )
    .resolve("Query", "user", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      calls.push(1)
      GqlValue::object([("id", GqlString("u1")), ("name", GqlString("Ada"))])
    })
    .finish()
  let response = execute(
    schema,
    GraphQLRequest::new("{ user { name } user { id } }"),
    (),
  )
  assert_eq(calls.length(), 1)
  assert_eq(
    response.to_json().stringify(),
    "{\"data\":{\"user\":{\"name\":\"Ada\",\"id\":\"u1\"}}}",
  )
}

///|
async test "overlapping field merge validation checks arguments and exclusivity" {
  let schema = SchemaBuilder::from_sdl(
      (
        #|type Query {
        #|  label(id: ID): String
        #|  search: [Search!]!
        #|}
        #|
        #|union Search = Human | Droid
        #|
        #|type Human {
        #|  homePlanet: String
        #|}
        #|
        #|type Droid {
        #|  primaryFunction: String
        #|}
      ),
    )
    .resolve("Query", "label", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlString("x")
    })
    .resolve("Query", "search", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlList([
        GqlValue::typed_object("Human", [("homePlanet", GqlString("Tatooine"))]),
        GqlValue::typed_object("Droid", [
          ("primaryFunction", GqlString("Astromech")),
        ]),
      ])
    })
    .finish()
  let conflict = execute(
    schema,
    GraphQLRequest::new("{ same: label(id: \"1\") same: label(id: \"2\") }"),
    (),
  )
  assert_true(conflict.errors[0].message.contains("conflicting arguments"))
  let exclusive = execute(
    schema,
    GraphQLRequest::new(
      (
        #|{
        #|  search {
        #|    ... on Human { label: homePlanet }
        #|    ... on Droid { label: primaryFunction }
        #|  }
        #|}
      ),
    ),
    (),
  )
  assert_eq(
    exclusive.to_json().stringify(),
    "{\"data\":{\"search\":[{\"label\":\"Tatooine\"},{\"label\":\"Astromech\"}]}}",
  )
}

///|
async test "operation and variable defaults follow GraphQL omission semantics" {
  let schema = SchemaBuilder::from_sdl(
      (
        #|input HeroInput {
        #|  episode: String = "NEWHOPE"
        #|}
        #|
        #|type Query {
        #|  maybe(name: String = "world"): String
        #|  hero(input: HeroInput!): String
        #|}
      ),
    )
    .resolve("Query", "maybe", async fn(_info, args, _ctx) {
      @async.sleep(0)
      match args.to_map().get("name") {
        Some(InputNull) => GqlString("null")
        Some(_) => {
          let name : String = args.get("name")
          GqlString(name)
        }
        None => GqlString("missing")
      }
    })
    .resolve("Query", "hero", async fn(_info, args, _ctx) {
      @async.sleep(0)
      let input : Json = args.get("input")
      match input {
        Object(fields) =>
          match fields.get("episode") {
            Some(String(value)) => GqlString(value)
            _ => GqlString("missing")
          }
        _ => GqlString("missing")
      }
    })
    .finish()
  let omitted = execute(
    schema,
    GraphQLRequest::new("query($name: String) { maybe(name: $name) }"),
    (),
  )
  assert_eq(omitted.to_json().stringify(), "{\"data\":{\"maybe\":\"world\"}}")
  let variable_default = execute(
    schema,
    GraphQLRequest::new("query($name: String = \"Ada\") { maybe(name: $name) }"),
    (),
  )
  assert_eq(
    variable_default.to_json().stringify(),
    "{\"data\":{\"maybe\":\"Ada\"}}",
  )
  let explicit_null = execute(
    schema,
    GraphQLRequest::new("query($name: String) { maybe(name: $name) }", variables={
      "name": InputNull,
    }),
    (),
  )
  assert_eq(
    explicit_null.to_json().stringify(),
    "{\"data\":{\"maybe\":\"null\"}}",
  )
  let input_default = execute(
    schema,
    GraphQLRequest::new("{ hero(input: {}) }"),
    (),
  )
  assert_eq(
    input_default.to_json().stringify(),
    "{\"data\":{\"hero\":\"NEWHOPE\"}}",
  )
}

///|
async test "anonymous operation must be alone" {
  let schema = star_wars_schema()
  let response = execute(
    schema,
    GraphQLRequest::new(
      "query Named { hero { id } } { hero { id } }",
      operation_name="Named",
    ),
    (),
  )
  assert_true(response.errors[0].message.contains("anonymous operation"))
}

///|
async test "abstract type resolver handles untyped objects and rejects invalid runtime types" {
  let sdl =
    #|interface Character {
    #|  name: String!
    #|}
    #|
    #|type Human implements Character {
    #|  name: String!
    #|  homePlanet: String
    #|}
    #|
    #|type Droid {
    #|  name: String!
    #|}
    #|
    #|type Query {
    #|  hero: Character
    #|}
  let schema = SchemaBuilder::from_sdl(sdl)
    .resolve("Query", "hero", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlValue::object([
        ("name", GqlString("Luke")),
        ("homePlanet", GqlString("Tatooine")),
      ])
    })
    .resolve_type("Character", async fn(_abstract, _value, _ctx) {
      @async.sleep(0)
      "Human"
    })
    .finish()
  let response = execute(
    schema,
    GraphQLRequest::new(
      "{ hero { __typename name ... on Human { homePlanet } } }",
    ),
    (),
  )
  assert_eq(
    response.to_json().stringify(),
    "{\"data\":{\"hero\":{\"__typename\":\"Human\",\"name\":\"Luke\",\"homePlanet\":\"Tatooine\"}}}",
  )
  let invalid = SchemaBuilder::from_sdl(sdl)
    .resolve("Query", "hero", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlValue::object([("name", GqlString("R2-D2"))])
    })
    .resolve_type("Character", async fn(_abstract, _value, _ctx) {
      @async.sleep(0)
      "Droid"
    })
    .finish()
  let invalid_response = execute(
    invalid,
    GraphQLRequest::new("{ hero { __typename name } }"),
    (),
  )
  assert_true(
    invalid_response.errors[0].message.contains("not valid for abstract type"),
  )
  let missing = SchemaBuilder::from_sdl(sdl)
    .resolve("Query", "hero", async fn(_info, _args, _ctx) {
      @async.sleep(0)
      GqlValue::object([("name", GqlString("Luke"))])
    })
    .finish()
  let missing_response = execute(
    missing,
    GraphQLRequest::new("{ hero { __typename name } }"),
    (),
  )
  assert_true(
    missing_response.errors[0].message.contains("missing runtime type"),
  )
}
