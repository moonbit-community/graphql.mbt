///|
test "minify query strips ignored characters" {
  let source =
    #|
    #|        query SomeQuery($foo: String!, $bar: String) {
    #|            someField(foo: $foo, bar: $bar) {
    #|                a
    #|                b { 
    #|                    ... on B {
    #|                        c 
    #|                        d 
    #|                    } 
    #|                } 
    #|            } 
    #|        }
    #|        
  assert_eq(
    minify_query(source),
    "query SomeQuery($foo:String!$bar:String){someField(foo:$foo bar:$bar){a b{...on B{c d}}}}",
  )
}

///|
test "minify query unexpected token" {
  let source =
    #|
    #|        query foo {
    #|            bar;
    #|        }
    #|        
  try minify_query(source) catch {
    err => assert_true(err.to_string().contains("unexpected character"))
  } noraise {
    _ => assert_true(false)
  }
}
