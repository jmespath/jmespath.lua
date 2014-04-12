-- Provides tokenization of JMESPath expressions:
--
--     local Lexer = require "jmespath.lexer"
--     local lexer = Lexer()
--
-- @module jmespath.lexer
-- @alias Lexer

-- JSON is needed for decoding tokens
local json = require "dkjson"
local TokenStream = require "jmespath.tokenstream"

-- Lexer prototype class that is returned as the module
local Lexer = {}

-- Combine two sequence tables into a new table.
local function combine_seq(a, b)
  result = {}
  for k, _ in pairs(a) do result[k] = true end
  for k, _ in pairs(b) do result[k] = true end
  return result
end

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

-- Tokens that can be numbers
local numbers = {
  ["0"] = 1, ["1"] = 1, ["2"] = 1, ["3"] = 1, ["4"] = 1,
  ["5"] = 1, ["6"] = 1, ["7"] = 1, ["8"] = 1, ["9"] = 1
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

-- Represents identifier start tokens (merged with identifier_start).
local identifiers = combine_seq(identifier_start, numbers)
identifiers["-"] = true

-- Operator start tokens
local operator_start_tokens = {["="]=1, ["<"]=1, [">"]=1, ["!"]=1}

local valid_operators = combine_seq(operator_start_tokens, {
  ["<="] = 1, [">="] = 1, ["!="] = 1, ["=="] = 1
})

local json_decode_characters = {['"'] = 1, ['['] = 1, ['{'] = 1}
local json_numbers = combine_seq(numbers, {["-"] = 1})

--- Initalizes the lexer
function Lexer:new()
  return self
end

--- Creates a sequence table of tokens for use in a token stream.
-- @tparam  string      Expression Expression to tokenize
-- @treturn TokenStream Returns a stream of tokens
function Lexer:tokenize(expression)
  local tokens = {}
  self.token_iter = expression:gmatch(".")
  self.pos = 0
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
    elseif operator_start_tokens[self.c] then
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

  return TokenStream(tokens, expression)
end

--- Advances to the next token and modifies the internal state of the lexer.
function Lexer:_consume()
  self.c = self.token_iter()
  if self.c ~= "" then self.pos = self.pos + 1 end
end

--- Consumes an identifier token /[A-Za-z0-9_\-]/
-- @treturn table Returns the identifier token
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

--- Consumes a number token /[0-9\-]/
-- @treturn table Returns the number token
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

--- Consumes a flatten token, lbracket, and filter token: "[]", "[?", and "["
-- @treturn table Returns the token
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

--- Consumes an operation <, >, !, !=, ==
-- @treturn table Returns the token
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

--- Consumes an or, "||", and pipe, "|" token
-- @treturn table Returns the token
function Lexer:_consume_pipe()
  self:_consume()

  if self.c ~= "|" then
    return {type = "pipe", value = "|", pos = self.pos - 1};
  end

  self:_consume()

  return {type = "or", value = "||", pos = self.pos - 2};
end

--- Parse a string of tokens inside of a delimiter.
-- @param   lexer   Lexer instance
-- @param   wrapper Wrapping character
-- @param   skip_ws Set to true to skip whitespace
-- @treturn table   Returns the start of a token
local function parse_inside(lexer, wrapper, skip_ws)
  local p = lexer.pos
  local last = "\\"
  local buffer = {}

  -- Consume the leading character
  lexer:_consume()

  while lexer.c and not (lexer.c == wrapper and last ~= "\\") do
    last = lexer.c
    if not skip_ws or last ~= " " then
      buffer[#buffer + 1] = lexer.c
    end
    lexer:_consume()
  end

  lexer:_consume()

  return {value = table.concat(buffer), pos = p}
end

--- Consumes a literal token.
-- @treturn table Returns the token
function Lexer:_consume_literal()
  local token = parse_inside(self, '`', true)
  local first_char = token.value:sub(1, 1)
  token.type = "literal"

  if json_decode_characters[first_char] or json_numbers[first_char] then
    token.value = json.decode(token.value)
  elseif token.value == "null" then
    token.value = nil
  elseif token.value == "true" then
    token.value = true
  elseif token.value == "false" then
    token.value = false
  elseif token.value:sub(1, 1) == '"' then
    token.value = json.decode(token.value)
  else
    token.value = json.decode('"' .. token.value .. '"')
  end

  return token
end

--- Consumes a quoted string.
-- @treturn table Returns the token
function Lexer:_consume_quoted_identifier()
  local token = parse_inside(self, '"')
  token.type = "quoted_identifier"
  token.value = json.decode('"' .. token.value.. '"')
  return token
end

-- Return the Lexer creational method
return function()
  return Lexer:new()
end
