# moonbit-community/graphql

GraphQL parser, validator, executor, subscription runtime, and small HTTP
adapter for MoonBit. The root package focuses on building executable schemas
from SDL and running GraphQL requests; the `parser` package exposes the AST,
tokenizer, parser, formatter, and minifier for tooling; the `http` package wires
an executable schema into `moonbitlang/async/http`.

## Packages

- `moonbit-community/graphql`: schema compilation, argument coercion,
  validation, execution, introspection, and subscription streams.
- `moonbit-community/graphql/parser`: GraphQL query and schema parsing,
  formatting, minification, and token-level source positions.
- `moonbit-community/graphql/http`: GET/POST handling, JSON batch requests,
  GraphiQL routing, and websocket subscription transport helpers.

## Building a Schema

Schemas are usually created from GraphQL SDL with `SchemaBuilder::from_sdl`.
Register a resolver for every query and mutation root field, then call
`finish()` to validate the executable schema.

```moonbit nocheck
///|
let builder : SchemaBuilder[Unit] = SchemaBuilder::from_sdl(
  (
    #|type Query {
    #|  hello(name: String = "world"): String!
    #|}
  ),
)

///|
let schema = builder
  .resolve("Query", "hello", async fn(_info, args, _ctx) {
    let name : String = args.get("name")
    GqlString("hello " + name)
  })
  .finish()
```

Resolvers receive:

- `ResolveInfo`: parent type, field name, response key, response path, and the
  source value being completed.
- `Args`: coerced GraphQL arguments, with typed access through
  `Args::get[T]` and `Args::get_opt[T]`.
- user context: the generic `Ctx` value passed to `execute`.

Object resolvers can return `GqlObject` values for simple objects or
`GqlTypedObject` values when the runtime GraphQL type matters, such as
interface and union selections. For untyped objects returned through an
interface or union, register `SchemaBuilder::resolve_type` to choose and
validate the concrete object type at execution time.

## Executing Requests

Use `GraphQLRequest::new` to provide a query, optional operation name, and
variables. `execute` returns a `GraphQLResponse`; `execute_with_status` also
returns the HTTP-oriented status code chosen by parse, validation, and coercion
failures.

```moonbit nocheck
///|
let response = execute(
  schema,
  GraphQLRequest::new("query SayHello($name: String!) { hello(name: $name) }", variables={
    "name": InputString("Ada"),
  }),
  (),
)

///|
let json = response.to_json()
```

The executor validates the document before running resolvers, coerces variables
and arguments against the schema, propagates non-null failures, and serializes
the response using GraphQL's `data` and `errors` shape.

## Parsing and Formatting

The parser package can be used independently for GraphQL tooling.

```moonbit nocheck
///|
let query = @parser.parse_query("query { viewer { id name } }")

///|
let pretty = query.format()

///|
let compact = @parser.minify_query(pretty)

///|
let schema_doc = @parser.parse_schema("type Query { viewer: User }")

///|
let sdl = schema_doc.format(style=@parser.Style::default().with_indent(2))
```

All parser errors include a 1-based source line and column through `ParseError`.
Tokens also retain byte offsets so editors and code generators can map AST data
back to the original source.

## HTTP Adapter

The `http` package exposes `serve` for live async HTTP servers and
`handle_request` for tests or custom routers. Defaults serve GraphQL at
`/graphql`, a small GraphiQL page at `/graphiql`, and websocket subscriptions at
`/graphql`.

```moonbit nocheck
let config = @graphql_http.HttpConfig::default()
@graphql_http.serve(server, schema, _request => (), config~)
```

Supported request forms include:

- `GET /graphql?query=...&operationName=...&variables=...`
- `POST /graphql` with `application/json`
- `POST /graphql` with `application/graphql`
- JSON batch arrays for multiple operations in one request
- websocket messages compatible with `graphql-transport-ws` `subscribe` and
  legacy `start` operations

## Notes

This project is intentionally small and close to the GraphQL specification. It
currently includes the built-in scalar and directive definitions needed by the
validator and executor, plus a minimal JSON-style introspection response for
runtime and tooling use.
