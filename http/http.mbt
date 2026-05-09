///|
/// Configuration for the async HTTP GraphQL adapter.
///
/// `graphql_path` handles GET and POST GraphQL requests. `graphiql_path`
/// enables a small browser endpoint when present. `websocket_path` enables
/// websocket subscription handling when present. `max_body_bytes` rejects large
/// POST bodies before JSON parsing or execution.
pub(all) struct HttpConfig {
  graphql_path : String
  graphiql_path : String?
  websocket_path : String?
  max_body_bytes : Int?
} derive(Eq, Debug)

///|
/// Default HTTP configuration.
pub fn HttpConfig::default() -> HttpConfig {
  {
    graphql_path: "/graphql",
    graphiql_path: Some("/graphiql"),
    websocket_path: Some("/graphql"),
    max_body_bytes: None,
  }
}

///|
/// Transport response returned by `handle_request`.
///
/// This type keeps request handling testable without needing a live socket.
pub(all) struct HttpResponse {
  status_code : Int
  reason : String
  headers : Map[String, String]
  body : String
} derive(Eq, Debug)

///|
/// Serve GraphQL requests on an async HTTP server until the server is closed.
///
/// The `context` callback is evaluated per request and its result is passed to
/// GraphQL resolvers. Websocket upgrades are routed before normal HTTP body
/// handling.
pub async fn[Ctx] serve(
  server : @async_http.Server,
  schema : @graphql.ExecutableSchema[Ctx],
  context : async (@async_http.Request) -> Ctx,
  config? : HttpConfig,
) -> Unit {
  let _bound_addr : @socket.Addr = server.addr
  let config = config.unwrap_or(HttpConfig::default())
  server.run_forever((request, body, conn) => {
    if is_websocket_request(request, config) {
      serve_ws(schema, request, conn, context(request))
      return
    }
    let body_text = body.read_all().text()
    let ctx = context(request)
    let response = handle_request(schema, request, body_text, ctx, config~)
    conn.send_response(
      response.status_code,
      response.reason,
      extra_headers=response.headers,
    )
    conn.write(response.body)
    conn.end_response()
  })
}

///|
/// Handle one HTTP request and return a complete response.
///
/// Supports GraphiQL routing, GraphQL GET requests, JSON POST requests,
/// `application/graphql` POST requests, JSON batches, and standard error status
/// responses for routing or media-type failures.
pub async fn[Ctx] handle_request(
  schema : @graphql.ExecutableSchema[Ctx],
  request : @async_http.Request,
  body : String,
  context : Ctx,
  config? : HttpConfig,
) -> HttpResponse {
  let config = config.unwrap_or(HttpConfig::default())
  if request.path_without_query() == config.graphiql_path.unwrap_or("") {
    return text_response(
      200,
      "OK",
      graphiql_html(config.graphql_path),
      "text/html; charset=utf-8",
    )
  }
  if request.path_without_query() != config.graphql_path {
    return json_response(
      404,
      "Not Found",
      @graphql.GraphQLResponse::error("not found").to_json(),
    )
  }
  match request.meth {
    Get => handle_get(schema, request, context)
    Post => handle_post(schema, request, body, context, config)
    _ =>
      json_response(
        405,
        "Method Not Allowed",
        @graphql.GraphQLResponse::error("method not allowed").to_json(),
      )
  }
}

///|
async fn[Ctx] handle_get(
  schema : @graphql.ExecutableSchema[Ctx],
  request : @async_http.Request,
  context : Ctx,
) -> HttpResponse {
  match request_from_query_string(request.query_string()) {
    Ok(graphql_request) => {
      let result = @graphql.execute_with_status(
        schema, graphql_request, context,
      )
      json_response(
        result.status_code,
        status_reason(result.status_code),
        result.response.to_json(),
      )
    }
    Err(message) =>
      json_response(
        400,
        "Bad Request",
        @graphql.GraphQLResponse::error(message).to_json(),
      )
  }
}

///|
async fn[Ctx] handle_post(
  schema : @graphql.ExecutableSchema[Ctx],
  request : @async_http.Request,
  body : String,
  context : Ctx,
  config : HttpConfig,
) -> HttpResponse {
  match config.max_body_bytes {
    Some(limit) =>
      if body.length() > limit {
        return json_response(
          413,
          "Payload Too Large",
          @graphql.GraphQLResponse::error("request body exceeds max_body_bytes").to_json(),
        )
      }
    None => ()
  }
  let content_type = header(request.headers, "content-type").unwrap_or(
    "application/json",
  )
  if content_type.contains("application/graphql") {
    let result = @graphql.execute_with_status(
      schema,
      @graphql.GraphQLRequest::new(body),
      context,
    )
    return json_response(
      result.status_code,
      status_reason(result.status_code),
      result.response.to_json(),
    )
  }
  if !content_type.contains("application/json") {
    return json_response(
      415,
      "Unsupported Media Type",
      @graphql.GraphQLResponse::error("unsupported content-type").to_json(),
    )
  }
  let parsed = try @json.parse(body) catch {
    err =>
      return json_response(
        400,
        "Bad Request",
        @graphql.GraphQLResponse::error(err.to_string()).to_json(),
      )
  } noraise {
    json => json
  }
  match parsed {
    Array(items) =>
      if items.is_empty() {
        json_response(
          400,
          "Bad Request",
          @graphql.GraphQLResponse::error("batch request must not be empty").to_json(),
        )
      } else {
        let responses : Array[Json] = []
        let mut status = 200
        for item in items {
          match request_from_json(item) {
            Ok(graphql_request) => {
              let result = @graphql.execute_with_status(
                schema, graphql_request, context,
              )
              if result.status_code >= 400 {
                status = 400
              }
              responses.push(result.response.to_json())
            }
            Err(message) => {
              status = 400
              responses.push(@graphql.GraphQLResponse::error(message).to_json())
            }
          }
        }
        json_response(status, status_reason(status), Json::array(responses))
      }
    _ =>
      match request_from_json(parsed) {
        Ok(graphql_request) => {
          let result = @graphql.execute_with_status(
            schema, graphql_request, context,
          )
          json_response(
            result.status_code,
            status_reason(result.status_code),
            result.response.to_json(),
          )
        }
        Err(message) =>
          json_response(
            400,
            "Bad Request",
            @graphql.GraphQLResponse::error(message).to_json(),
          )
      }
  }
}

///|
/// Handle a websocket connection using `graphql-transport-ws` style messages
/// and the legacy `start`/`stop` message names.
async fn[Ctx] serve_ws(
  schema : @graphql.ExecutableSchema[Ctx],
  request : @async_http.Request,
  conn : @async_http.ServerConnection,
  context : Ctx,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  defer ws.close()
  @async.with_task_group(group => {
    let tasks : Map[String, @async.Task[Unit]] = {}
    defer cancel_ws_tasks(tasks)
    for ;; {
      let message = ws.recv()
      match message.kind {
        Text => {
          let text = message.read_all().text()
          let keep_open = handle_ws_message(
            schema, ws, text, context, group, tasks,
          )
          if !keep_open {
            return
          }
        }
        Binary => {
          ignore(message.read_all())
          ws.send_text(
            ws_message(
              "error",
              None,
              Json::object({
                "message": Json::string("binary messages are not supported"),
              }),
            ).stringify(),
          )
        }
      }
    }
  }) catch {
    @websocket.ConnectionClosed(_, _) => ()
    _ => ()
  }
}

///|
async fn[Ctx] handle_ws_message(
  schema : @graphql.ExecutableSchema[Ctx],
  ws : @websocket.Conn,
  text : String,
  context : Ctx,
  group : @async.TaskGroup[Unit],
  tasks : Map[String, @async.Task[Unit]],
) -> Bool {
  let json = try @json.parse(text) catch {
    err => {
      ws.send_text(
        ws_message(
          "error",
          None,
          Json::object({ "message": Json::string(err.to_string()) }),
        ).stringify(),
      )
      return true
    }
  } noraise {
    json => json
  }
  let object = match json {
    Object(object) => object
    _ => {
      ws.send_text(
        ws_message(
          "error",
          None,
          Json::object({
            "message": Json::string("expected websocket message object"),
          }),
        ).stringify(),
      )
      return true
    }
  }
  let message_type = match object.get("type") {
    Some(String(value)) => value
    _ => ""
  }
  let id = match object.get("id") {
    Some(String(value)) => Some(value)
    _ => None
  }
  match message_type {
    "connection_init" =>
      ws.send_text(
        Json::object({ "type": Json::string("connection_ack") }).stringify(),
      )
    "subscribe" | "start" => {
      let payload = match object.get("payload") {
        Some(payload) => payload
        None => Json::object({})
      }
      let task_id = websocket_operation_id(id)
      cancel_ws_task(tasks, task_id)
      let task = group.spawn(allow_failure=true, () => {
        run_ws_operation(schema, ws, message_type, id, payload, context)
      })
      tasks[task_id] = task
    }
    "complete" | "stop" => cancel_ws_task(tasks, websocket_operation_id(id))
    "connection_terminate" => {
      cancel_ws_tasks(tasks)
      return false
    }
    _ =>
      ws.send_text(
        ws_message(
          "error",
          id,
          Json::object({
            "message": Json::string("unknown websocket message type"),
          }),
        ).stringify(),
      )
  }
  true
}

///|
async fn[Ctx] run_ws_operation(
  schema : @graphql.ExecutableSchema[Ctx],
  ws : @websocket.Conn,
  message_type : String,
  id : String?,
  payload : Json,
  context : Ctx,
) -> Unit {
  let next_kind = if message_type == "start" { "data" } else { "next" }
  match request_from_json(payload) {
    Ok(graphql_request) =>
      match @graphql.start_subscription(schema, graphql_request, context) {
        Ok(stream) => {
          defer stream.close()
          while !@async.is_being_cancelled() {
            match stream.next() {
              Some(response) =>
                ws.send_text(
                  ws_message(next_kind, id, response.to_json()).stringify(),
                )
              None => break
            }
          }
          if !@async.is_being_cancelled() {
            ws.send_text(
              ws_message("complete", id, Json::object({})).stringify(),
            )
          }
        }
        Err(subscription_error) => {
          let result = @graphql.execute_with_status(
            schema, graphql_request, context,
          )
          if !result.response.errors.is_empty() && result.response.data == None {
            ws.send_text(
              ws_message(
                "error",
                id,
                Json::array(result.response.errors.map(err => err.to_json())),
              ).stringify(),
            )
          } else if !subscription_error.errors.is_empty() &&
            subscription_error.errors[0].message !=
            "operation is not a subscription" {
            ws.send_text(
              ws_message(
                "error",
                id,
                Json::array(subscription_error.errors.map(err => err.to_json())),
              ).stringify(),
            )
          } else {
            ws.send_text(
              ws_message(next_kind, id, result.response.to_json()).stringify(),
            )
            ws.send_text(
              ws_message("complete", id, Json::object({})).stringify(),
            )
          }
        }
      }
    Err(message) =>
      ws.send_text(
        ws_message(
          "error",
          id,
          Json::array([@graphql.GraphQLError::new(message).to_json()]),
        ).stringify(),
      )
  }
}

///|
fn websocket_operation_id(id : String?) -> String {
  id.unwrap_or("")
}

///|
fn cancel_ws_task(tasks : Map[String, @async.Task[Unit]], id : String) -> Unit {
  match tasks.get(id) {
    Some(task) => {
      task.cancel()
      tasks.remove(id)
    }
    None => ()
  }
}

///|
fn cancel_ws_tasks(tasks : Map[String, @async.Task[Unit]]) -> Unit {
  for _, task in tasks.iter2() {
    task.cancel()
  }
  tasks.clear()
}

///|
/// Decode a GraphQL-over-HTTP JSON payload into the core request type.
fn request_from_json(json : Json) -> Result[@graphql.GraphQLRequest, String] {
  let object = match json {
    Object(object) => object
    _ => return Err("GraphQL request must be a JSON object")
  }
  let query = match object.get("query") {
    Some(String(query)) => query
    _ => return Err("GraphQL request requires string field `query`")
  }
  let operation_name = match object.get("operationName") {
    Some(String(name)) => Some(name)
    Some(Null) | None => None
    _ => return Err("`operationName` must be a string or null")
  }
  let variables = match object.get("variables") {
    Some(Object(raw_variables)) => {
      let values : Map[String, @graphql.InputValue] = {}
      for name, value in raw_variables.iter2() {
        values[name] = @graphql.InputValue::from_json(value)
      }
      values
    }
    Some(Null) | None => {}
    _ => return Err("`variables` must be an object or null")
  }
  Ok(@graphql.GraphQLRequest::{ query, operation_name, variables })
}

///|
/// Decode GraphQL GET query parameters into the core request type.
fn request_from_query_string(
  query_string : String,
) -> Result[@graphql.GraphQLRequest, String] {
  let params = query_params(query_string)
  let query = match params.get("query") {
    Some(query) => query
    None => return Err("GET request requires `query` parameter")
  }
  let operation_name = params.get("operationName")
  let variables = match params.get("variables") {
    Some(raw) =>
      try @json.parse(raw) catch {
        err => return Err(err.to_string())
      } noraise {
        Object(raw_variables) => {
          let values : Map[String, @graphql.InputValue] = {}
          for name, value in raw_variables.iter2() {
            values[name] = @graphql.InputValue::from_json(value)
          }
          values
        }
        Null => {}
        _ => return Err("`variables` parameter must decode to an object")
      }
    None => {}
  }
  Ok(@graphql.GraphQLRequest::{ query, operation_name, variables })
}

///|
fn query_params(query_string : String) -> Map[String, String] {
  let params : Map[String, String] = {}
  if query_string.is_empty() {
    return params
  }
  for part_view in query_string.split("&") {
    let part = part_view.to_owned()
    let pair = part.split_once("=")
    match pair {
      Some((key, value)) =>
        params[url_decode(key.to_owned())] = url_decode(value.to_owned())
      None => params[url_decode(part)] = ""
    }
  }
  params
}

///|
fn url_decode(source : String) -> String {
  let chars : Array[Char] = []
  let mut index = 0
  while index < source.length() {
    let code = source[index].to_int()
    if code == 37 && index + 2 < source.length() {
      let high = hex_value(source[index + 1].to_int())
      let low = hex_value(source[index + 2].to_int())
      if high >= 0 && low >= 0 {
        chars.push(Int::unsafe_to_char(high * 16 + low))
        index = index + 3
        continue
      }
    }
    if code == 43 {
      chars.push(' ')
    } else {
      chars.push(source[index].to_char().unwrap())
    }
    index = index + 1
  }
  String::from_array(chars)
}

///|
fn hex_value(code : Int) -> Int {
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 55
  } else if code >= 97 && code <= 102 {
    code - 87
  } else {
    -1
  }
}

///|
fn @async_http.Request::path_without_query(
  self : @async_http.Request,
) -> String {
  match self.path.split_once("?") {
    Some((path, _)) => path.to_owned()
    None => self.path
  }
}

///|
fn @async_http.Request::query_string(self : @async_http.Request) -> String {
  match self.path.split_once("?") {
    Some((_, query)) => query.to_owned()
    None => ""
  }
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  for key, value in headers.iter2() {
    if key.to_lower() == name.to_lower() {
      return Some(value)
    }
  }
  None
}

///|
fn is_websocket_request(
  request : @async_http.Request,
  config : HttpConfig,
) -> Bool {
  match config.websocket_path {
    Some(path) =>
      request.path_without_query() == path &&
      header(request.headers, "upgrade").map_or(false, value => {
        value.to_lower() == "websocket"
      })
    None => false
  }
}

///|
fn json_response(
  status_code : Int,
  reason : String,
  body : Json,
) -> HttpResponse {
  text_response(
    status_code,
    reason,
    body.stringify(),
    "application/json; charset=utf-8",
  )
}

///|
fn text_response(
  status_code : Int,
  reason : String,
  body : String,
  content_type : String,
) -> HttpResponse {
  {
    status_code,
    reason,
    headers: {
      "content-type": content_type,
      "content-length": body.length().to_string(),
    },
    body,
  }
}

///|
fn status_reason(status_code : Int) -> String {
  match status_code {
    200 => "OK"
    400 => "Bad Request"
    404 => "Not Found"
    405 => "Method Not Allowed"
    413 => "Payload Too Large"
    415 => "Unsupported Media Type"
    _ => "OK"
  }
}

///|
/// Build a GraphQL websocket protocol message.
fn ws_message(kind : String, id : String?, payload : Json) -> Json {
  let object : Map[String, Json] = { "type": Json::string(kind) }
  match id {
    Some(id) => object["id"] = Json::string(id)
    None => ()
  }
  if kind != "complete" {
    object["payload"] = payload
  }
  Json::object(object)
}

///|
fn graphiql_html(path : String) -> String {
  "<!doctype html><html><head><meta charset=\"utf-8\"><title>GraphiQL</title></head><body><div id=\"graphiql\">GraphiQL endpoint: " +
  path +
  "</div></body></html>"
}
