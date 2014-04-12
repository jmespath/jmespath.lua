-- Implements the main jmespath() function
-- @module jmespath

-- Exported module
local jmespath = {_VERSION = "0.1.0"}

local lexer = require("jmespath.lexer")()
local interpreter = require("jmespath.interpreter")()
local parser = require("jmespath.parser")({lexer = lexer})
local cache = {}

--- Searches the provided data using a JMESPath expression
-- @tparam string expression JMESPath expression as a string.
-- @param         data       Data to search. Can be any primitive or a table.
-- @return Returns the evaluated result as a table, string,
--         nil, number, or boolean.
-- @error  Raises an error if the expression is invalid.
function jmespath.search(expression, data)
  return interpreter:visit(jmespath.parse(expression), data)
end

--- Parses the given JMESPath expression into an AST of tables
-- @tparam  string expression Expression to parse
-- @treturn table  Returns the parsed result as a table of AST nodes.
-- @error   Raises an error if the expression is invalid.
function jmespath.parse(expression)
  if #cache > 1024 then cache = {} end
  if not cache[expression] then
    cache[expression] = parser:parse(expression)
  end

  return cache[expression]
end

--- Parses the given JMESPath expression into a token stream table.
-- @tparam  string expression Expression to tokenize
-- @treturn table  Returns a token stream table.
-- @error   Raises an error if the expression is invalid.
function jmespath.tokenize(expression)
  return lexer:tokenize(expression)
end

return jmespath
