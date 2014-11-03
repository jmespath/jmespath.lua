-- Implements the main jmespath function
-- @module jmespath

local jmespath = {
  _VERSION = '0.1.0',
  _DESCRIPTION = 'Declaritively extract data from JSON like structures',
  _URL = 'https://github.com/mtdowling/jmespath.lua',
  _LICENSE = 'https://github.com/mtdowling/jmespath.lua/blob/master/LICENSE'
}

local interpreter = require('jmespath.interpreter').new()
local parser = require('jmespath.parser').new()
local cache = {}

--- Searches the provided data using a JMESPath expression
-- @tparam string expression JMESPath expression as a string.
-- @param         data       Data to search. Can be any primitive or a table.
-- @return Returns the evaluated result as a table, string,
--         nil, number, or boolean.
-- @error  Raises an error if the expression is invalid.
function jmespath.search(expression, data)
  if #cache > 1024 then cache = {} end
  if not cache[expression] then
    cache[expression] = parser:parse(expression)
  end
  return interpreter:visit(cache[expression], data)
end

return jmespath
