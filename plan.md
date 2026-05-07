# MoonBit GraphQL Server, Juniper-Inspired

## Summary

- Build a Juniper-like server in this repo around the existing parser API in `parser/pkg.generated.mbti`: SDL/query parsing stays in `parser`; executable schema, validation, execution, typed resolver helpers, HTTP, and WebSocket support are added above it.
- Use **SDL-first** as the schema source, per your choice. Typed MoonBit traits are used for argument coercion and resolver return conversion, not for generating schema metadata like Juniper's Rust proc macros.
- Target Juniper's split: core `execute`/schema/runtime behavior like `juniper/src/lib.rs`, and transport-neutral request/response plus HTTP adapters like `juniper/src/http/mod.rs`.

## Key API Shape

- Root package `moonbit-community/graphql` exposes:
  - `ExecutableSchema[Ctx]`
  - `SchemaBuilder[Ctx]::from_sdl(String) -> Self raise SchemaError`
  - `SchemaBuilder::resolve(type_name, field_name, resolver) -> Self`
  - `SchemaBuilder::subscribe(type_name, field_name, resolver) -> Self`
  - `SchemaBuilder::finish() -> ExecutableSchema[Ctx] raise SchemaError`
  - `async fn execute[Ctx](ExecutableSchema[Ctx], GraphQLRequest, &Ctx) -> GraphQLResponse`
  - `fn introspect(ExecutableSchema[_], format~ : IntrospectionFormat) -> Json`
- Typed layer:
  - `trait ToGraphQL { to_graphql(Self) -> GqlValue }`
  - `trait FromGraphQL { from_graphql(InputValue) -> Self raise CoercionError }`
  - Built-in impls for `String`, `Bool`, `Int`, `Int64`, `Double`, `T?`, `Array[T]`, and `Json`.
  - `Args::get[T : FromGraphQL](name : String) -> T raise CoercionError`.
- Runtime values:
  - `InputValue` is the post-variable-substitution input representation, preserving enum/list/object/null distinctions.
  - `GqlValue` is the internal execution output representation and serializes to JSON only at the response boundary.
- Transport package `moonbit-community/graphql/http` exposes:
  - `HttpConfig { graphql_path, graphiql_path?, websocket_path?, max_body_bytes? }`
  - `async fn serve[Ctx](@http.Server, ExecutableSchema[Ctx], async (@http.Request) -> Ctx, config? : HttpConfig) -> Unit`

## Implementation Changes

- Schema compiler:
  - Convert `parser.SchemaDocument` into a registry of scalars, objects, interfaces, unions, enums, input objects, directives, and root operation types.
  - Merge SDL extensions; reject duplicate names, missing referenced types, invalid root operations, invalid directive locations, and unbound root field resolvers.
  - Add built-ins: `String`, `Int`, `Float`, `Boolean`, `ID`, `@skip`, `@include`, `@deprecated`, `@specifiedBy`.
- Validation:
  - Implement GraphQL October 2021 validation rules comparable to Juniper: operation/fragment uniqueness, known types/fields/arguments/directives, variable definition/use rules, fragment cycles and spread applicability, scalar leaf selection, required arguments, input object correctness, overlapping field merge checks, and optional introspection disabling.
- Execution:
  - Parse query, select operation, merge variable defaults, coerce variables/arguments, build fragment map, then recursively execute selection sets.
  - Support aliases, fragments, inline fragments, `@skip`, `@include`, `__typename`, non-null propagation, list/object recursion, field error paths, and partial data with `errors`.
  - Resolve object/interface/union concrete type using `GqlValue` type metadata or typed `ToGraphQL` object conversion.
- HTTP and subscriptions:
  - Support `GET`, `POST application/json`, `POST application/graphql`, single and non-empty batch requests.
  - Return Juniper-like status behavior: malformed HTTP/JSON or parse/validation errors as `400`; successful GraphQL execution as `200` even when field errors are present.
  - Add GraphiQL HTML endpoint.
  - Use `moonbitlang/async/websocket` for `graphql-transport-ws` first, then legacy `graphql-ws` compatibility. Subscription resolvers return a stream abstraction backed by `@async.Queue`.

## Test Plan

- Keep existing parser tests unchanged.
- Add schema compiler tests for valid SDL, extensions, duplicate definitions, invalid references, root operation selection, directives, interfaces, and unions.
- Port a small Juniper Star Wars-style schema as a MoonBit integration test using SDL plus typed resolvers.
- Add execution tests for variables, defaults, aliases, fragments, directives, non-null bubbling, resolver errors, enum/input coercion, introspection, and validation failures.
- Add HTTP tests mirroring Juniper's suite: simple GET, encoded GET, variables, JSON POST, GraphQL POST, batch POST, empty batch rejection, invalid JSON, invalid fields.
- Add WebSocket subscription tests for connection init, subscribe, next/error/complete messages, and cancellation on disconnect.

## Assumptions

- "Full Juniper-like" is the end target, but implementation should land in phases: core schema/execution first, then HTTP, then full validation/introspection polish, then subscriptions.
- SDL remains the source of truth; typed traits make resolver code safer but do not replace SDL or require code generation.
- MoonBit will not try to emulate Rust proc macros in v1.
- HTTP/WebSocket packages target native via `moonbitlang/async`; the parser and core execution layer stay transport-independent.
