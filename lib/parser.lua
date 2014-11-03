-- Implements a JMESPath Pratt parser
--
--     local Parser = require 'jmespath.parser'
--     local parser = Parser.new()
--
-- Parser accepts an optional lexer argument in its constructor.
--
-- @module jmespath.parser

-- Parser module
local Parser = {}

--- Creates a new parser
-- @param Lexer
function Parser.new(lexer)
  local self = setmetatable({}, {__index = Parser})
  self.lexer = lexer or require('jmespath.lexer').new()
  return self
end

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

--- Peeks at the next token type without consuming it
-- @treturn table
function Parser:peek()
  if self.pos < #self.tokens then
    return self.tokens[self.pos + 1].type
  else
    return 'eof'
  end
end

--- Ensures that a token is not the given type or errors
-- @param table  token
-- @param string type
function Parser:assert_not(type)
  if self.token.type == type then
    error('Token not ' .. self.pos .. ' not allowed to be ' .. type)
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
  identifier        = true,
  quoted_identifier = true,
  lbracket          = true,
  lbrace            = true,
  star              = true
}

-- Hash of token handlers
local parselets = {}

--- Main expression parsing function.
local function expr(parser, rbp)
  rbp = rbp or 0
  local left = parselets['nud_' .. parser.token.type](parser)
  while rbp < bp[parser.token.type] do
    left = parselets['led_' .. parser.token.type](parser, left)
  end
  return left
end

parselets.nud_identifier = function(parser)
  local result = {type = 'field', value = parser.token.value}
  parser:advance()
  return result
end

parselets.nud_quoted_identifier = function(parser)
  local token = parser.token
  parser:advance()
  parser:assert_not('lparen')
  return {type = 'field', value = token.value}
end

parselets.nud_current = function(parser)
  parser:advance()
  return {type = 'current'}
end

parselets.nud_literal = function(parser)
  local token = parser.token
  parser:advance()
  return {type = 'literal', value = token.value}
end

parselets.nud_expref = function(parser)
  parser:advance()
  return {type = 'expref', children = {expr(parser, 2)}}
end

function parse_kvp(parser)
  local valid_colon = {colon = true}
  local key = parser.token.value
  parser:advance(valid_colon)
  parser:advance()
  return {type = 'key_value_pair', value = key, children = {expr(parser)}}
end

parselets.nud_lbrace = function(parser)
  local valid_keys = {quoted_identifier = true, identifier = true}
  parser:advance(valid_keys)
  local pairs = {}
  repeat
    pairs[#pairs + 1] = parse_kvp(parser)
    if parser.token.type == 'comma' then parser:advance(valid_keys) end
  until parser.token.type == 'rbrace'
  parser:advance()
  return {type = 'multi_select_hash', children = pairs}
end

parselets.nud_flatten = function(parser)
  return parselets.led_flatten(parser, current_node)
end

parselets.nud_filter = function(parser)
  return parselets.led_filter(parser, current_node)
end

local function parse_multi_select_list(parser)
  local nodes = {}
  repeat
    nodes[#nodes + 1] = expr(parser)
    if parser.token.type == 'comma' then
      parser:advance()
      parser:assert_not('rbracket')
    end
  until parser.token.type == 'rbracket'
  parser:advance()
  return {type = 'multi_select_list', children = nodes}
end

local function parse_dot(parser, rbp)
  if parser.token.type == 'lbracket' then
    parser:advance()
    return parse_multi_select_list(parser)
  end
  return expr(parser, rbp)
end

local function parse_projection(parser, rbp)
  local t = parser.token.type
  if bp[t] < 10 then
    return current_node
  elseif t == 'dot' then
    parser:advance(after_dot)
    return parse_dot(parser, rbp)
  elseif t == 'lbracket' or t == 'filter' then
    return expr(parser, rbp)
  else
    throw(parser, 'Syntax error after projection')
  end
end

local function parse_wildcard_object(parser, left)
  parser:advance()
  return {
    type     = 'object_projection',
    children = {left or current_node, parse_projection(parser, bp.star)}
  }
end

parselets.nud_star = function(parser)
  return parse_wildcard_object(parser, current_node)
end

local function parse_wildcard_array(parser, left)
  parser:advance({rbracket = true})
  parser:advance()
  return {
    type     = 'array_projection',
    children = {left or current_node, parse_projection(parser, bp.star)}
  }
end

local function parse_array_index_expr(parser)
  local match_next = {number = true, colon = true, rbracket = true}
  local pos = 1
  local parts = {false, false, false}
  local expected  = match_next

  repeat
    if parser.token.type == 'colon' then
      pos = pos + 1
      expected = match_next
    else
      parts[pos] = parser.token.value
      expected = {colon = true, rbracket = true}
    end
    parser:advance(expected)
  until parser.token.type == 'rbracket'

  -- Consume the closing bracket
  parser:advance()

  -- If no colons were found then this is a simple index extraction.
  if pos == 1 then
    return {type = 'index', value = parts[1]}
  elseif pos > 3 then
    throw(parser, 'Invalid array slice syntax: too many colons')
  else
    -- Sliced array from start(e.g., [2:])
    return {type = 'slice', value = parts}
  end
end

parselets.nud_lbracket = function(parser)
  parser:advance()
  local t = parser.token.type
  if t == 'number' or t == 'colon' then
    return parse_array_index_expr(parser)
  elseif t == 'star' and parser:peek() == "rbracket" then
    return parse_wildcard_array(parser)
  end
  return parse_multi_select_list(parser)
end

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

parselets.led_or = function(parser, left)
  parser:advance()
  return {type = 'or', children = {left, expr(parser, bp['or'])}}
end

parselets.led_pipe = function(parser, left)
  parser:advance()
  return {type = 'pipe', children = {left, expr(parser, bp.pipe)}}
end

parselets.led_lparen = function(parser, left)
  local args = {}
  parser:advance()
  while parser.token.type ~= 'rparen' do
    args[#args + 1] = expr(parser, 0)
    if parser.token.type == 'comma' then parser:advance() end
  end
  parser:advance()
  return {type = 'function', value = left.value, children = args}
end

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

parselets.led_comparator = function(parser, left)
  local token = parser.token
  parser:advance()
  return {
    type     = 'comparator',
    value    = token.value,
    children = {left, expr(parser)}
  }
end

parselets.led_dot = function(parser, left)
  parser:advance(after_dot)
  if parser.token.type == 'star' then
    return parse_wildcard_object(parser, left)
  end
  return {type = 'subexpression', children = {left, parse_dot(parser, bp.dot)}}
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
-- @param  string expression Expression to parse into an AST
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
