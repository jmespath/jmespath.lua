-- Implements a JMESPath Pratt parser
--
--     local Parser = require 'jmespath.parser'
--     local parser = Parser.new()
--
-- Parser accepts an optional config argument in its constructor. The config
-- argument is a table that can contain the following keys:
--
-- - lexer: An instance of a Lexer object
--
-- @module jmespath.parser

-- Parser module
local Parser = {}

--- Creates a new parser
-- @tparam Lexer
function Parser.new(lexer)
  local self = setmetatable({}, {__index = Parser})
  self.lexer = lexer or require('jmespath.lexer').new()
  return self
end

--- Advances to the next token, and optionally ensures the next token is of a
-- particular type.
-- @tparam valid table Optional hash of acceptable next types
function Parser:advance(valid)

  if self.pos < #self.tokens then
    self.pos = self.pos + 1
    self.token = self.tokens[self.pos]
  end

  if valid and not valid[self.token.type] then
    error('Syntax error at ' .. self.pos .. '. Found '
      .. self.token.type .. ' but expected one of: '
      .. table.concat(table_keys(valid), ', '))
  end
end

--- Peeks at the next token without consuming it
-- @treturn table
function Parser:peek()
  if self.pos < #self.tokens then
    return self.tokens[self.pos + 1]
  else
    return self.tokens[self.pos]
  end
end

-- Token binding precedence table
local bp = {
  eof               = 0,
  quoted_identifier = 0,
  identifier        = 0,
  rbracket          = 0,
  rparen            = 0,
  comma             = 0,
  rbrace            = 0,
  number            = 0,
  current           = 0,
  expref            = 0,
  literal           = 0,
  pipe              = 1,
  comparator        = 2,
  ['or']            = 5,
  flatten           = 6,
  star              = 20,
  dot               = 40,
  lbrace            = 50,
  filter            = 50,
  lbracket          = 50,
  lparen            = 60
}

-- Cached current node used as identity nodes.
local current_node = {type = 'current'}

-- Valid tokens after a dot
local after_dot = {
  identifier = true,
  quoted_identifier = true,
  lbracket = true,
  lbrace = true,
  star = true
}

-- Hash of token handlers
local parselets = {}

--- Main expression parsing function
local function expr(parser, rbp)
  rbp = rbp or 0
  local left = parselets['nud_' .. parser.token.type](parser)

  while rbp < bp[parser.token.type] do
    left = parselets['led_' .. parser.token.type](parser, left)
  end

  return left
end

--- Parses a leading identifier token (e.g., foo)
parselets.nud_identifier = function(parser)
  local result = {type = 'field', key = parser.token.value}
  parser:advance()
  return result
end

--- Parses a nud quoted identifier (e.g., 'foo')
parselets.nud_quoted_identifier = function(parser)
  local token = parser.token
  parser:advance()

  if parser.token.type == 'lparen' then
    throw(parser, 'Quoted identifiers are not allowed for function names')
  end

  return {type = 'field', key = token.value}
end

--- Parses the current node (e.g., @)
parselets.nud_current = function(parser)
  parser:advance()
  return {type = 'current'}
end

--- Parses a literal token (e.g., `foo`)
parselets.nud_literal = function(parser)
  local token = parser.token
  parser:advance()
  return {type = 'literal', value = token.value}
end

--- Parses an expression reference token
parselets.nud_expref = function(parser)
  parser:advance()
  return {type = 'expref', children = {expr(parser, 2)}}
end

--- Parses an lbrace token and creates a key-value-pair multi-select-hash
parselets.nud_lbrace = function(parser)
  local valid = {quoted_identifier = true, identifier = true}
  local valid_colon = {colon = true}
  local kvp = {}
  parser:advance(valid)

  while true do
    local key = parser.token.value
    parser:advance(valid_colon)
    parser:advance()
    kvp[#kvp + 1] = {
      type     = 'key_value_pair',
      key      = key,
      children = {expr(parser)}
    }
    if parser.token.type == 'comma' then
      parser:advance(valid)
    end
    if parser.token.type == 'rbrace' then
      break
    end
  end

  parser:advance()

  return {type = 'multi_select_hash', children = kvp}
end

--- Parses a flatten token with no leading token.
parselets.nud_flatten = function(parser)
  return parselets.led_flatten(parser, current_node)
end

--- Parses a filter token with no leading token (e.g., [?foo=bar])
parselets.nud_filter = function(parser)
  return parselets.led_filter(parser, current_node)
end

--- Parses a multi-select-list (e.g., [foo, baz, bar])
local function parse_multi_select_list(parser)
  local nodes = {}

  while true do
    nodes[#nodes + 1] = expr(parser)
    if parser.token.type == 'comma' then
      parser:advance()
      if parser.token.type == 'rbracket' then
        throw(parser, 'Expected expression, found rbracket')
      end
    end
    if parser.token.type == 'rbracket' then break end
  end

  parser:advance()
  return {type = 'multi_select_list', children = nodes}
end

--- Parses a dot expression with a maximum specified rbp value.
local function parse_dot(parser, rbp)
  if not after_dot[parser.token.type] then
    throw(parser, "Invalid token after dot")
  end

  -- We need special handling for lbracket tokens following dot (multi-select)
  if parser.token.type ~= 'lbracket' then
    return expr(parser, rbp)
  end

  parser:advance()

  return parse_multi_select_list(parser)
end

--- Parses a projection and accounts for permutations and syntax errors.
-- @error Raises an error when an invalid projection is provided.
local function parse_projection(parser, rbp)
  local t = parser.token.type
  if bp[t] < 10 then
    return current_node
  elseif t == 'dot' then
    parser:advance(after_dot)
    return parse_dot(parser, rbp)
  elseif t == 'lbracket' then
    return expr(parser, rbp)
  else
    throw(parser, 'Syntax error after projection')
  end
end

--- Parses a wildcard object token (used by bot nud and led tokens).
local function parse_wildcard_object(parser, left)
  parser:advance()
  return {
    type     = 'object_projection',
    children = {
      left or current_node,
      parse_projection(parser, bp.star)
    }
  }
end

--- Parses a star token with no leading token (e.g., *, foo | *)
parselets.nud_star = function(parser)
  return parse_wildcard_object(parser, current_node)
end

--- Parses a wildcard array token (used by bot nud and led tokens).
local function parse_wildcard_array(parser, left)
  parser:advance({rbracket = true})
  parser:advance()
  return {
    type     = 'array_projection',
    children = {
      left or current_node,
      parse_projection(parser, bp.star)
    }
  }
end

--- Parses both normal index access and slice access
local function parse_array_index_expr(parser)
  local match_next = {number = true, colon = true, rbracket = true}
  local pos = 1
  local parts = {false, false, false}

  while true do
    if parser.token.type == 'colon' then
      pos = pos + 1
    else
      parts[pos] = parser.token.value
    end
    parser:advance(match_next)
    if parser.token.type == 'rbracket' then break end
  end

  -- Consume the closing bracket
  parser:advance()

  -- If no colons were found then this is a simple index extraction.
  if pos == 1 then
    return {type = 'index', index = parts[1]}
  elseif pos > 3 then
    throw(parser, 'Invalid array slice syntax: too many colons')
  else
    -- Sliced array from start(e.g., [2:])
    return {type = 'slice', args = parts}
  end
end

--- Parses an lbracket token with no leading expression (e.g., [0])
parselets.nud_lbracket = function(parser)
  parser:advance()
  local t = parser.token.type

  if t == 'number' or t == 'colon' then
    return parse_array_index_expr(parser)
  end

  -- Try to parse a star, and if it fails, backtrack
  if t == 'star' and parser:peek().type == "rbracket" then
    return parse_wildcard_array(parser)
  end

  return parse_multi_select_list(parser)
end

--- Parses an lbracket token after a value (e.g., foo[0])
parselets.led_lbracket = function(parser, left)
  local next_types = {number = true, colon = true, star = true}
  parser:advance(next_types)
  local t = parser.token.type

  if t == 'number' or t == 'colon' then
    return {
      type     = 'subexpression',
      children = {left, parse_array_index_expr(parser)}
    }
  end

  return parse_wildcard_array(parser, left)
end

--- Parses a flatten token and creates a projection.
parselets.led_flatten = function(parser, left)
  parser:advance()
  return {
    type = 'array_projection',
    children = {
      {type = 'flatten', children = {left}},
      parse_projection(parser, bp.flatten)
    }
  }
end

--- Parses an or token.
parselets.led_or = function(parser, left)
  parser:advance()
  return {
    type     = 'or',
    children = {left, expr(parser, bp['or'])}
  }
end

--- Parses a pipe token.
parselets.led_pipe = function(parser, left)
  parser:advance()
  return {
    type     = 'pipe',
    children = {left, expr(parser, bp.pipe)}
  }
end

--- Parses an lparen that starts a function.
parselets.led_lparen = function(parser, left)
  local args = {}
  local name = left.key
  parser:advance()

  while parser.token.type ~= 'rparen' do
    args[#args + 1] = expr(parser, 0)
    if parser.token.type == 'comma' then parser:advance() end
  end

  parser:advance()

  return {type = 'function', fn = name, children = args}
end

--- Parses a filter expression (e.g., [?foo==bar])
parselets.led_filter = function(parser, left)
  parser:advance()
  local expression = expr(parser)

  if parser.token.type ~= 'rbracket' then
    throw(parser, 'Expected a closing rbracket for the filter')
  end

  parser:advance()
  local rhs = parse_projection(parser, bp.filter)

  return {
    type = 'array_projection',
    children = {
      left or current_node,
      {type = 'condition', children = {expression, rhs}}
    }
  }
end

--- Parses a comparator token (e.g., <expr> == <expr>)
parselets.led_comparator = function(parser, left)
  local token = parser.token
  parser:advance()

  return {
    type     = 'comparator',
    relation = token.value,
    children = {left, expr(parser)}
  }
end

--- Parses a dot token (e.g., <expr>.<expr>)
parselets.led_dot = function(parser, left)
  parser:advance()
  return {
    type     = 'subexpression',
    children = {left, parse_dot(parser, bp.dot)}
  }
end

setmetatable(parselets, {
  -- handle the invalid use of nud or led tokens
  __index = function(self, key)
    error("Invalid use of " .. key)
  end
})

--- Throws a valuable error message
local function throw(parser, msg)
  msg = 'Syntax error at character ' .. parser.token.pos .. '\n'
    .. parser.expr .. '\n'
    .. string.rep(' ', parser.token.pos - 1) .. '^\n'
    .. msg
  error(msg)
end

--- Parses an expression.
-- @tparam  string expression Expression to parse into an AST
-- @treturn table  Returns the parsed AST as a table of table nodes.
-- @error   Raises an error when an invalid expression is provided.
function Parser:parse(expression)
  self.expr = expression
  self.tokens = self.lexer:tokenize(expression)
  -- Advance to the first token
  self.pos = 0
  self:advance()

  local ast = expr(self, 0)

  if self.token.type ~= 'eof' then
    throw(self, 'Encountered an unexpected "' .. self.token.type
      .. '" token and did not reach the end of the token stream.')
  end

  return ast
end

return Parser
