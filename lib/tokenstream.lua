-- Implements a stream of tokens, allowing for backtracking
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
function TokenStream:new(tokens, expr)
  self.tokens = tokens
  self.expr = expr
  self.cur = self.tokens[1]
  self.pos = 0
  self.mark_pos = 0
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
    self.cur = {pos = #self.expr + 1, type = "eof"}
  end

  if valid and not valid[self.cur.type] then
    error("Syntax error at " .. self.pos .. ". Found "
      .. self.cur.type .. " but expected one of: "
      .. table.concat(table_keys(valid), ", "))
  end
end

--- Marks the current token position for backtracking.
-- Marking a token allows you to backtrack to the marked token in the event of
-- a parse error.
function TokenStream:mark()
  self.mark_pos = self.pos
end

--- Removes any previously set mark token.
function TokenStream:unmark()
  self.mark_pos = 0
end

--- Sets the token cursor position to a previously set mark position.
-- @error Raises an error if no mark position was previously set.
function TokenStream:backtrack()
  if not self.mark_pos then
    error("No mark position was set on the token stream")
  end
  self.pos = self.mark_pos
  self.mark_pos = nil
end

return TokenStream
