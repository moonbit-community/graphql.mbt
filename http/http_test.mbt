///|
fn test_schema() -> @graphql.ExecutableSchema[Unit] raise @graphql.SchemaError {
  let builder : @graphql.SchemaBuilder[Unit] = @graphql.SchemaBuilder::from_sdl(
    (
      #|type Query {
      #|  hello(name: String = "world"): String!
      #|}
    ),
  )
  builder
  .resolve("Query", "hello", async fn(_info, args, _ctx) {
    @async.sleep(0)
    let name : String = args.get("name")
    @graphql.GqlString("hello " + name)
  })
  .finish()
}

///|
fn subscription_schema() -> @graphql.ExecutableSchema[Unit] raise @graphql.SchemaError {
  let builder : @graphql.SchemaBuilder[Unit] = @graphql.SchemaBuilder::from_sdl(
    (
      #|schema {
      #|  query: Query
      #|  subscription: Subscription
      #|}
      #|
      #|type Query {
      #|  hello: String!
      #|}
      #|
      #|type Subscription {
      #|  count: Int!
      #|}
    ),
  )
  builder
  .resolve("Query", "hello", async fn(_info, _args, _ctx) {
    @async.sleep(0)
    @graphql.GqlString("hello")
  })
  .subscribe("Subscription", "count", async fn(_info, _args, _ctx) {
    let stream = @graphql.SubscriptionStream::new()
    stream.publish(
      @graphql.GraphQLResponse::data(
        @graphql.GqlObject({ "count": @graphql.GqlInt(1) }),
      ),
    )
    stream.close()
    stream
  })
  .finish()
}

///|
fn request(
  meth : @async_http.RequestMethod,
  path : String,
  content_type? : String,
) -> @async_http.Request {
  let headers : Map[String, String] = {}
  match content_type {
    Some(value) => headers["content-type"] = value
    None => ()
  }
  { meth, path, headers }
}

///|
async test "json post and application graphql post" {
  let schema = test_schema()
  let json_post = handle_request(
    schema,
    request(Post, "/graphql", content_type="application/json"),
    "{\"query\":\"query($name:String!){hello(name:$name)}\",\"variables\":{\"name\":\"Ada\"}}",
    (),
  )
  assert_eq(json_post.status_code, 200)
  assert_eq(json_post.body, "{\"data\":{\"hello\":\"hello Ada\"}}")
  let graphql_post = handle_request(
    schema,
    request(Post, "/graphql", content_type="application/graphql"),
    "query { hello(name: \"MoonBit\") }",
    (),
  )
  assert_eq(graphql_post.status_code, 200)
  assert_eq(graphql_post.body, "{\"data\":{\"hello\":\"hello MoonBit\"}}")
}

///|
async test "get query supports percent decoding" {
  let schema = test_schema()
  let response = handle_request(
    schema,
    request(Get, "/graphql?query=%7B%20hello%20%7D"),
    "",
    (),
  )
  assert_eq(response.status_code, 200)
  assert_eq(response.body, "{\"data\":{\"hello\":\"hello world\"}}")
}

///|
async test "batch and error status handling" {
  let schema = test_schema()
  let batch = handle_request(
    schema,
    request(Post, "/graphql", content_type="application/json"),
    "[{\"query\":\"{ hello }\"},{\"query\":\"{ hello(name: \\\"Ada\\\") }\"}]",
    (),
  )
  assert_eq(batch.status_code, 200)
  assert_eq(
    batch.body,
    "[{\"data\":{\"hello\":\"hello world\"}},{\"data\":{\"hello\":\"hello Ada\"}}]",
  )
  let empty_batch = handle_request(
    schema,
    request(Post, "/graphql", content_type="application/json"),
    "[]",
    (),
  )
  assert_eq(empty_batch.status_code, 400)
  let invalid_json = handle_request(
    schema,
    request(Post, "/graphql", content_type="application/json"),
    "{",
    (),
  )
  assert_eq(invalid_json.status_code, 400)
  let invalid_field = handle_request(
    schema,
    request(Post, "/graphql", content_type="application/json"),
    "{\"query\":\"{ missing }\"}",
    (),
  )
  assert_eq(invalid_field.status_code, 400)
}

///|
async test "graphiql and routing responses" {
  let schema = test_schema()
  let graphiql = handle_request(schema, request(Get, "/graphiql"), "", ())
  assert_eq(graphiql.status_code, 200)
  assert_true(graphiql.headers["content-type"].contains("text/html"))
  let not_found = handle_request(schema, request(Get, "/nope"), "", ())
  assert_eq(not_found.status_code, 404)
  let method_response = handle_request(
    schema,
    request(Delete, "/graphql"),
    "",
    (),
  )
  assert_eq(method_response.status_code, 405)
}

///|
async test "websocket graphql transport subscription" {
  let schema = subscription_schema()
  let server = @async_http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      serve(server, schema, _request => (), config=HttpConfig::default())
    })
    @async.sleep(50)
    let url = "ws://127.0.0.1:\{server.addr.port()}/graphql"
    let ws = @websocket.Conn::connect(url)
    defer ws.close()
    ws.send_text("{\"type\":\"connection_init\"}")
    let ack = ws.recv().read_all().text()
    assert_true(ack.contains("\"connection_ack\""))
    ws.send_text(
      "{\"id\":\"1\",\"type\":\"subscribe\",\"payload\":{\"query\":\"subscription { count }\"}}",
    )
    let next = ws.recv().read_all().text()
    assert_true(next.contains("\"next\""))
    assert_true(next.contains("\"count\":1"))
    let complete = ws.recv().read_all().text()
    assert_true(complete.contains("\"complete\""))
    ws.send_text("{\"type\":\"connection_terminate\"}")
  })
}
