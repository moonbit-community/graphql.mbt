///|
pub fn parse_query(source : String) -> QueryDocument raise ParseError {
  let parser = Parser::new(source)
  let definitions : Array[QueryDefinition] = []
  if parser.at_eof() {
    parse_error("expected query definition", parser.peek().position)
  }
  while true {
    if parser.at_eof() {
      break
    }
    definitions.push(parser.parse_query_definition())
    continue
  }
  parser.expect_eof()
  { definitions, }
}

///|
pub fn consume_definition(
  source : String,
) -> (QueryDefinition, String) raise ParseError {
  let (tokens, rest_offset) = tokenize_first_query_definition(source)
  let parser : Parser = { tokens, index: 0 }
  let definition = parser.parse_query_definition()
  parser.expect_eof()
  let rest = source.unsafe_substring(start=rest_offset, end=source.length())
  (definition, rest)
}

///|
fn Parser::parse_query_definition(
  self : Parser,
) -> QueryDefinition raise ParseError {
  if self.check_punct("{") ||
    self.check_ident("query") ||
    self.check_ident("mutation") ||
    self.check_ident("subscription") {
    OperationDefinition(self.parse_operation_definition())
  } else if self.check_ident("fragment") {
    FragmentDefinition(self.parse_fragment_definition())
  } else {
    let token = self.peek()
    parse_error(
      "expected {, query, mutation, subscription or fragment",
      token.position,
    )
  }
}

///|
fn Parser::parse_operation_definition(
  self : Parser,
) -> OperationDefinition raise ParseError {
  if self.check_punct("{") {
    SelectionSetOperation(self.parse_selection_set())
  } else if self.check_ident("query") {
    QueryOperation(self.parse_query_operation())
  } else if self.check_ident("mutation") {
    MutationOperation(self.parse_mutation_operation())
  } else if self.check_ident("subscription") {
    SubscriptionOperation(self.parse_subscription_operation())
  } else {
    let token = self.peek()
    parse_error("expected operation definition", token.position)
  }
}

///|
fn Parser::parse_query_operation(self : Parser) -> Query raise ParseError {
  let position = self.expect_ident("query").position
  let (name, variable_definitions, directives, selection_set) = self.parse_operation_common()
  { position, name, variable_definitions, directives, selection_set }
}

///|
fn Parser::parse_mutation_operation(self : Parser) -> Mutation raise ParseError {
  let position = self.expect_ident("mutation").position
  let (name, variable_definitions, directives, selection_set) = self.parse_operation_common()
  { position, name, variable_definitions, directives, selection_set }
}

///|
fn Parser::parse_subscription_operation(
  self : Parser,
) -> Subscription raise ParseError {
  let position = self.expect_ident("subscription").position
  let (name, variable_definitions, directives, selection_set) = self.parse_operation_common()
  { position, name, variable_definitions, directives, selection_set }
}

///|
fn Parser::parse_operation_common(
  self : Parser,
) -> (String?, Array[VariableDefinition], Array[Directive], SelectionSet) raise ParseError {
  let name = if self.check_name() {
    let (name, _) = self.expect_name()
    Some(name)
  } else {
    None
  }
  let variable_definitions = self.parse_variable_definitions()
  let directives = self.parse_directives()
  let selection_set = self.parse_selection_set()
  (name, variable_definitions, directives, selection_set)
}

///|
fn Parser::parse_variable_definitions(
  self : Parser,
) -> Array[VariableDefinition] raise ParseError {
  if !self.eat_punct("(") {
    return []
  }
  let variables : Array[VariableDefinition] = []
  if self.check_punct(")") {
    let token = self.peek()
    parse_error("expected variable definition", token.position)
  }
  while true {
    if self.check_punct(")") {
      ignore(self.take())
      break
    }
    let position = self.expect_punct("$").position
    let (name, _) = self.expect_name()
    ignore(self.expect_punct(":"))
    let var_type = self.parse_type()
    let default_value = if self.eat_punct("=") {
      Some(self.parse_default_value())
    } else {
      None
    }
    variables.push({ position, name, var_type, default_value })
    continue
  }
  variables
}

///|
fn Parser::parse_fragment_definition(
  self : Parser,
) -> FragmentDefinition raise ParseError {
  let position = self.expect_ident("fragment").position
  let (name, _) = self.expect_name()
  ignore(self.expect_ident("on"))
  let (type_name, _) = self.expect_name()
  let type_condition = On(type_name)
  let directives = self.parse_directives()
  let selection_set = self.parse_selection_set()
  { position, name, type_condition, directives, selection_set }
}

///|
fn Parser::parse_selection_set(self : Parser) -> SelectionSet raise ParseError {
  let start = self.expect_punct("{").position
  let items : Array[Selection] = []
  if self.check_punct("}") {
    let token = self.peek()
    parse_error("expected selection", token.position)
  }
  while true {
    if self.check_punct("}") {
      let end = self.take().position
      return { span: (start, end), items }
    }
    items.push(self.parse_selection())
    continue
  }
  parse_error("unterminated selection set", start)
}

///|
fn Parser::parse_selection(self : Parser) -> Selection raise ParseError {
  if self.eat_punct("...") {
    self.parse_spread()
  } else {
    FieldSelection(self.parse_field())
  }
}

///|
fn Parser::parse_spread(self : Parser) -> Selection raise ParseError {
  let position = self.peek().position
  if self.check_ident("on") || self.check_punct("@") || self.check_punct("{") {
    let type_condition = if self.eat_ident("on") {
      let (name, _) = self.expect_name()
      Some(On(name))
    } else {
      None
    }
    let directives = self.parse_directives()
    let selection_set = self.parse_selection_set()
    InlineFragmentSelection({
      position,
      type_condition,
      directives,
      selection_set,
    })
  } else {
    let (fragment_name, fragment_pos) = self.expect_name()
    let directives = self.parse_directives()
    FragmentSpreadSelection({
      position: fragment_pos,
      fragment_name,
      directives,
    })
  }
}

///|
fn Parser::parse_field(self : Parser) -> Field raise ParseError {
  let (name_or_alias, position) = self.expect_name()
  let (name, field_alias) = if self.eat_punct(":") {
    let (name, _) = self.expect_name()
    (name, Some(name_or_alias))
  } else {
    (name_or_alias, None)
  }
  let arguments = self.parse_arguments()
  let directives = self.parse_directives()
  let selection_set = if self.check_punct("{") {
    self.parse_selection_set()
  } else {
    empty_selection_set(position)
  }
  { position, field_alias, name, arguments, directives, selection_set }
}

///|
pub fn minify_query(source : String) -> String raise ParseError {
  let tokens = tokenize(source)
  let pieces : Array[String] = []
  let mut prev_was_non_punctuator = false
  for token in tokens {
    if token.kind == TkEof {
      break
    }
    let is_non_punctuator = token.kind != TkPunctuator
    if prev_was_non_punctuator && is_non_punctuator {
      pieces.push(" ")
    }
    pieces.push(token.value)
    prev_was_non_punctuator = is_non_punctuator
  }
  pieces.join("")
}
