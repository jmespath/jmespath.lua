-- Implements a stream of tokens, allowing for backtracking
--
--     local TokenStream = require 'jmespath.tokenstream'
--     local ts = TokenStream(tokens, expression)
--
-- @module jmespath.tokenstream
-- @alias TokenStream

-- TokenStream prototype
local TokenStream = {}

--- Returns a sequence table that contains a list of keys from a hash table.
-- @tparam  tabke t Input table to get a list of keys from
-- @treturn table   Returns the keys of the hash as a sequence table.
local function table_keys(t)
  local keys = {}
  local n = 0

  for k, v in pairs(t) do
    n = n + 1
    keys[n] = k
  end

  return keys
end

--- Creates a new token stream
-- @tparam table  token Sequence of tokens returned from a lexer
-- @tparam string expr  The expression that was parsed
function TokenStream.new(tokens, expr)
  local self = setmetatable({}, {__index = TokenStream})
  self.tokens = tokens
  self.cur = self.tokens[1]
  self.expr = expr
  self.pos = 0
  return self
end

--- Moves the token stream cursor to the next token.
-- @tparam table valid An optional hash table of valid next tokens.
-- @error  Raises an error if the next found token is not in the valid hash.
function TokenStream:next(valid)
  self.pos = self.pos + 1

  if self.pos <= #self.tokens then
    self.cur = self.tokens[self.pos]
  else
    -- Use an eof token if the position is the last token.
    self.pos = self.pos - 1
    self.cur = {pos = #self.expr + 1, type = 'eof'}
  end

  if valid and not valid[self.cur.type] then
    error('Syntax error at ' .. self.pos .. '. Found '
      .. self.cur.type .. ' but expected one of: '
      .. table.concat(table_keys(valid), ', '))
  end
end

--- Looks ahead to future tokens
-- @param  number Number of lookahead tokens (defaults to 1)
-- @return table
function TokenStream:peek(number)
  if not number then number = 1 end
  return self.tokens[self.pos + number] or {pos = #self.expr + 1, type = 'eof'}
end

return TokenStream
