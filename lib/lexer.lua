-- Provides tokenization of JMESPath expressions:

-- Simple, single character, tokens
local simple_tokens = {
  [' ']  = "ws",
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
local identifiers = {["-"]=1, ["0"]=1, ["1"]=1, ["2"]=1, ["3"]=1, ["4"]=1,
  ["5"]=1, ["6"]=1, ["7"]=1, ["8"]=1, ["9"]=1}
for k, v in pairs(identifier_start) do
  identifiers[k] = v
end

-- Operator start tokens
local op_tokens = {["="]=1, ["<"]=1, [">"]=1, ["!"]=1}

-- Tokens that can be numbers
local numbers = {
  ["0"]=1, ["1"]=1, ["2"]=1, ["3"]=1, ["4"]=1,
  ["5"]=1, ["6"]=1, ["7"]=1, ["8"]=1, ["9"]=1
}

local valid_operators = {
  ["<"]=1, [">"]=1, ["<="]=1, [">="]=1, ["!="]=1, ["=="]=1
}

local function table_keys (t)
  local keys, n = {}, 0
  for k, v in pairs(t) do
    n = n + 1
    keys[n] = k
  end
  return keys
end

local Lexer = {}

-- Initalizes the lexer
function Lexer:new (expression)
  self.expr = expression
  self.pos = 0
  self:consume()
  return self
end

-- Advances to the next token and modifies the internal state of the lexer
function Lexer:consume ()
  if self.pos == #self.expr then
    self.c = ""
  else
    self.pos = self.pos + 1
    self.c = self.expr:sub(self.pos, self.pos)
  end
end

-- Iterates over each character in a string and yields tokens
function Lexer:tokenize ()
  tokens = {}

  while self.c ~= "" do
    if identifier_start[self.c] then
      tokens[#tokens + 1] = self:consume_identifier()
    elseif simple_tokens[self.c] then
      if simple_tokens[self.c] ~= "ws" then
        tokens[#tokens + 1] = {
          ["pos"]   = self.pos,
          ["type"]  = simple_tokens[self.c],
          ["value"] = self.c
        }
      end
      self:consume()
    elseif numbers[self.c] or self.c == "-" then
      tokens[#tokens + 1] = self:consume_number()
    elseif self.c == "[" then
      tokens[#tokens + 1] = self:consume_lbracket()
    elseif op_tokens[self.c] then
      tokens[#tokens + 1] = self:consume_operator()
    elseif self.c == "|" then
      tokens[#tokens + 1] = self:consume_pipe()
    elseif self.c == '"' then
      tokens[#tokens + 1] = self:consume_quoted_identifier()
    elseif self.c == "`" then
      tokens[#tokens + 1] = self:consume_literal()
    else
      error("Unexpected character " .. self.c .. " found at #" .. self.pos)
    end
  end

  return tokens
end

-- Yield an identifier token
function Lexer:consume_identifier ()
  local buffer = {self.c}
  local start = self.pos
  self:consume()

  while identifiers[self.c] do
    buffer[#buffer + 1] = self.c
    self:consume()
  end

  return {pos=start, type="identifier", value=table.concat(buffer)}
end

-- Yield a number token
function Lexer:consume_number ()
  local buffer = {self.c}
  local start = self.pos
  self:consume()

  while numbers[self.c] do
    buffer[#buffer + 1] = self.c
    self:consume()
  end

  return {pos=start, type="number", value=tonumber(table.concat(buffer))}
end

-- Yield a flatten, filter, and lbracket tokens
function Lexer:consume_lbracket ()
  self:consume()
  if self.c == "]" then
    self:consume()
    return {pos=self.pos - 1, type="flatten", value="[]"}
  elseif self.c == "?" then
    self:consume()
    return {pos=self.pos - 1, type="filter", value="[?"}
  else
    return {pos=self.pos - 1, type="lbracket", value="["}
  end
end

-- Consumes an operation <, >, !, !=, ==
function Lexer:consume_operator ()
  token = {
    type  = "comparator",
    pos   = self.pos,
    value = self.c
  }

  self:consume()

  if self.c == "=" then
    self:consume()
    token.value = token.value .. "="
  elseif token.value == "=" then
    error("Expected ==, got =")
  end

  if not valid_operators[token.value] then
    error("Invalid operator: " .. token.value)
  end

  return token
end

-- Consumes ors and pipes
function Lexer:consume_pipe ()
  self:consume()
  if self.c ~= "|" then
    return {type="pipe", value="|", pos=self.pos - 1};
  end

  self:consume()
  return {type="or", value="||", pos=self.pos - 2};
end

-- Consumes a literal token
function Lexer:consume_literal ()
  -- @todo
end

-- Consumes a quoted string
function Lexer:consume_quoted_identifier ()
  -- @todo
end

-- Returns a token stream table
return function (expression)
  local tokens = (Lexer:new(expression)):tokenize()
  local pos = 1
  local mark_pos = 0

  return {
    cur = tokens[1],
    tokens = tokens,
    next = function(self, valid)
      pos = pos + 1
      if pos > #self.tokens then
        pos = #self.tokens
        self.cur = {pos=pos, type="eof"}
      else
        self.cur = self.tokens[pos]
      end
      if valid and not valid[self.cur.type] then
        error("Syntax error at " .. pos .. ". Found "
          .. self.cur.type .. " but expected one of: "
          .. table.concat(table_keys(valid), ", "))
      end
    end,
    mark = function(self)
      self.mark_pos = self.pos
    end,
    backtrack = function(self)
      if not self.mark then
        error("No mark position was set on the token stream")
      end
      pos = mark_pos
      mark_pos = nil
    end
  }
end
