-- Provides tokenization of JMESPath expressions:
-- @module jmespath.lexer
-- @alias Lexer

-- JSON is needed for decoding tokens
local json = require "dkjson"

-- Simple, single character, tokens
local simple_tokens = {
  [" "]  = "ws",
  ["\n"] = "ws",
  ["\t"] = "ws",
  ["\r"] = "ws",
  ["."]  = "dot",
  ["*"]  = "star",
  [","]  = "comma",
  [":"]  = "colon",
  ["{"]  = "lbrace",
  ["}"]  = "rbrace",
  ["]"]  = "rbracket",
  ["("]  = "lparen",
  [")"]  = "rparen",
  ["@"]  = "current",
  ["&"]  = "expref"
}

-- Tokens that can start an identifier
local identifier_start = {
  ["a"] = 1, ["b"] = 1, ["c"] = 1, ["d"] = 1, ["e"] = 1, ["f"] = 1, ["g"] = 1,
  ["h"] = 1, ["i"] = 1, ["j"] = 1, ["k"] = 1, ["l"] = 1, ["m"] = 1, ["n"] = 1,
  ["o"] = 1, ["p"] = 1, ["q"] = 1, ["r"] = 1, ["s"] = 1, ["t"] = 1, ["u"] = 1,
  ["v"] = 1, ["w"] = 1, ["x"] = 1, ["y"] = 1, ["z"] = 1, ["A"] = 1, ["B"] = 1,
  ["C"] = 1, ["D"] = 1, ["E"] = 1, ["F"] = 1, ["G"] = 1, ["H"] = 1, ["I"] = 1,
  ["J"] = 1, ["K"] = 1, ["L"] = 1, ["M"] = 1, ["N"] = 1, ["O"] = 1, ["P"] = 1,
  ["Q"] = 1, ["R"] = 1, ["S"] = 1, ["T"] = 1, ["U"] = 1, ["V"] = 1, ["W"] = 1,
  ["X"] = 1, ["Y"] = 1, ["Z"] = 1, ["_"] = 1
}

-- Represents any acceptable identifier start token
local identifiers = {
  ["-"] = 1, ["0"] = 1, ["1"] = 1, ["2"] = 1, ["3"] = 1, ["4"] = 1,
  ["5"] = 1, ["6"] = 1, ["7"] = 1, ["8"] = 1, ["9"] = 1
}

-- Merge the identifier start tokens into the identifiers token list
for k, _ in pairs(identifier_start) do
  identifiers[k] = true
end

-- Operator start tokens
local op_tokens = {["="]=1, ["<"]=1, [">"]=1, ["!"]=1}

-- Tokens that can be numbers
local numbers = {
  ["0"] = 1, ["1"] = 1, ["2"] = 1, ["3"] = 1, ["4"] = 1,
  ["5"] = 1, ["6"] = 1, ["7"] = 1, ["8"] = 1, ["9"] = 1
}

local valid_operators = {
  ["<"] = 1, [">"] = 1, ["<="] = 1, [">="] = 1, ["!="] = 1, ["=="] = 1
}

-----------------------------------------------------------------------------
-- Returns a sequence table that contains a list of keys from a hash table.
--
-- @tparam  tabke t Input table to get a list of keys from
-- @treturn table   Returns the keys of the hash as a sequence table.
-----------------------------------------------------------------------------
local function table_keys(t)
  local keys = {}
  local n = 0

  for k, v in pairs(t) do
    n = n + 1
    keys[n] = k
  end

  return keys
end

-- @class Tokens stream class
local TokenStream = {}

-----------------------------------------------------------------------------
-- Creates a new token stream
--
-- @tparam table  token Sequence of tokens returned from a lexer
-- @tparam string expr  The expression that was parsed
-----------------------------------------------------------------------------
function TokenStream:new(tokens, expr)
  self.tokens = tokens
  self.expr = expr
  self.cur = self.tokens[1]
  self.pos = 0
  self.mark_pos = 0
  return self
end

-----------------------------------------------------------------------------
-- Moves the token stream cursor to the next token.
--
-- @tparam table valid An optional hash table of valid next tokens.
-- @error  Raises an error if the next found token is not in the valid hash.
-----------------------------------------------------------------------------
function TokenStream:next(valid)
  self.pos = self.pos + 1

  if self.pos <= #self.tokens then
    self.cur = self.tokens[self.pos]
  else
    -- Use an eof token if the position is the last token.
    self.pos = self.pos - 1
    self.cur = {pos = #self.expr + 1, type = "eof"}
  end

  if valid and not valid[self.cur.type] then
    error("Syntax error at " .. self.pos .. ". Found "
      .. self.cur.type .. " but expected one of: "
      .. table.concat(table_keys(valid), ", "))
  end
end

-----------------------------------------------------------------------------
-- Marks the current position of the token stream which allows you to
-- backtrack to the marked token in the event of a parse error.
-----------------------------------------------------------------------------
function TokenStream:mark()
  self.mark_pos = self.pos
end

-----------------------------------------------------------------------------
-- Removes any previously set mark token.
-----------------------------------------------------------------------------
function TokenStream:unmark()
  self.mark_pos = 0
end

-----------------------------------------------------------------------------
-- Sets the token cursor position to a previously set mark position.
--
-- @error Raises an error if no mark position was previously set.
-----------------------------------------------------------------------------
function TokenStream:backtrack()
  if not self.mark_pos then
    error("No mark position was set on the token stream")
  end
  self.pos = self.mark_pos
  self.mark_pos = nil
end

-- Lexer prototype class that is returned as the module
local Lexer = {}

-----------------------------------------------------------------------------
-- Initalizes the lexer
--
-- @treturn table Returns an instance of a lexer.
-----------------------------------------------------------------------------
function Lexer:new()
  return self
end

-----------------------------------------------------------------------------
-- Creates a sequence table of tokens for use in a token stream.
--
-- @tparam  string      Expression Expression to tokenize
-- @treturn TokenStream Returns a stream of tokens
-----------------------------------------------------------------------------
function Lexer:tokenize(expression)
  local tokens = {}
  self.pos = 0
  self.expr = expression
  self:_consume()

  while self.c do
    if identifier_start[self.c] then
      tokens[#tokens + 1] = self:_consume_identifier()
    elseif simple_tokens[self.c] then
      if simple_tokens[self.c] ~= "ws" then
        tokens[#tokens + 1] = {
          pos   = self.pos,
          type  = simple_tokens[self.c],
          value = self.c
        }
      end
      self:_consume()
    elseif numbers[self.c] or self.c == "-" then
      tokens[#tokens + 1] = self:_consume_number()
    elseif self.c == "[" then
      tokens[#tokens + 1] = self:_consume_lbracket()
    elseif op_tokens[self.c] then
      tokens[#tokens + 1] = self:_consume_operator()
    elseif self.c == "|" then
      tokens[#tokens + 1] = self:_consume_pipe()
    elseif self.c == '"' then
      tokens[#tokens + 1] = self:_consume_quoted_identifier()
    elseif self.c == "`" then
      tokens[#tokens + 1] = self:_consume_literal()
    else
      error("Unexpected character " .. self.c .. " found at #" .. self.pos)
    end
  end

  return TokenStream:new(tokens, expression)
end

-----------------------------------------------------------------------------
-- Advances to the next token and modifies the internal state of the lexer.
-----------------------------------------------------------------------------
function Lexer:_consume()
  if self.pos == #self.expr then
    self.c = false
  else
    self.pos = self.pos + 1
    self.c = self.expr:sub(self.pos, self.pos)
  end
end

-----------------------------------------------------------------------------
-- Consumes an identifier token /[A-Za-z0-9_\-]/
--
-- @treturn table Returns the identifier token
-----------------------------------------------------------------------------
function Lexer:_consume_identifier()
  local buffer = {self.c}
  local start = self.pos
  self:_consume()

  while identifiers[self.c] do
    buffer[#buffer + 1] = self.c
    self:_consume()
  end

  return {pos = start, type = "identifier", value = table.concat(buffer)}
end

-----------------------------------------------------------------------------
-- Consumes a number token /[0-9\-]/
--
-- @treturn table Returns the number token
-----------------------------------------------------------------------------
function Lexer:_consume_number()
  local buffer = {self.c}
  local start = self.pos
  self:_consume()

  while numbers[self.c] do
    buffer[#buffer + 1] = self.c
    self:_consume()
  end

  return {
    pos   = start,
    type  = "number",
    value = tonumber(table.concat(buffer))
  }
end

-----------------------------------------------------------------------------
-- Consumes a flatten token, lbracket, and filter token: "[]", "[?", and "["
--
-- @treturn table Returns the token
-----------------------------------------------------------------------------
function Lexer:_consume_lbracket()
  self:_consume()
  if self.c == "]" then
    self:_consume()
    return {pos = self.pos - 1, type = "flatten", value = "[]"}
  elseif self.c == "?" then
    self:_consume()
    return {pos = self.pos - 1, type = "filter", value = "[?"}
  else
    return {pos = self.pos - 1, type = "lbracket", value = "["}
  end
end

-----------------------------------------------------------------------------
-- Consumes an operation <, >, !, !=, ==
--
-- @treturn table Returns the token
-----------------------------------------------------------------------------
function Lexer:_consume_operator()
  token = {
    type  = "comparator",
    pos   = self.pos,
    value = self.c
  }

  self:_consume()

  if self.c == "=" then
    self:_consume()
    token.value = token.value .. "="
  elseif token.value == "=" then
    error("Expected ==, got =")
  end

  if not valid_operators[token.value] then
    error("Invalid operator: " .. token.value)
  end

  return token
end

-----------------------------------------------------------------------------
-- Consumes an or, "||", and pipe, "|" token
--
-- @treturn table Returns the token
-----------------------------------------------------------------------------
function Lexer:_consume_pipe()
  self:_consume()

  if self.c ~= "|" then
    return {type = "pipe", value = "|", pos = self.pos - 1};
  end

  self:_consume()

  return {type = "or", value = "||", pos = self.pos - 2};
end

-----------------------------------------------------------------------------
-- Parse a string of tokens inside of a delimiter.
--
-- @param   lexer   Lexer instance
-- @param   wrapper Wrapping character
-- @treturn table   Returns the start of a token
-----------------------------------------------------------------------------
local function parse_inside(lexer, wrapper)
  local p = lexer.pos
  local last = "\\"
  local buffer = {}

  -- Consume the leading character
  lexer:_consume()

  while lexer.c and not (lexer.c == wrapper and last ~= "\\") do
    last = lexer.c
    buffer[#buffer + 1] = lexer.c
    lexer:_consume()
  end

  lexer:_consume()

  return {value = table.concat(buffer), pos = p}
end

-----------------------------------------------------------------------------
-- Consumes a literal token.
--
-- @treturn table Returns the token
-----------------------------------------------------------------------------
function Lexer:_consume_literal()
  local token = parse_inside(self, '`')
  token.type = "literal"
  token.value = json.decode(token.value)
  return token
end

-----------------------------------------------------------------------------
-- Consumes a quoted string.
--
-- @treturn table Returns the token
-----------------------------------------------------------------------------
function Lexer:_consume_quoted_identifier()
  local token = parse_inside(self, '"')
  token.type = "quoted_identifier"
  token.value = json.decode('"' .. token.value.. '"')
  return token
end

return Lexer
