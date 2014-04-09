-- Implements the main jmespath() function
local lexer = require "jmespath.lexer"
local interpreter = require "jmespath.interpreter"
local Parser = require "jmespath.parser"
local parser = Parser:new({lexer=lexer})
local cache = {}
local jp = {}

-- Searches the provided data using a JMESPath expression
-- @param string expression JMESPath expression
-- @param mixed  data       Data to search
-- @return mixed Returns the evaluated result
function jp.search (expression, data)
  return interpreter:visit(jp.parse(expression), data)
end

-- Parses the given JMESPath expression into an AST
-- @param string expression Expression to parse
-- @return table Returns the AST as a table
function jp.parse (expression)
  if #cache > 1024 then cache = {} end
  if not cache[expression] then
    cache[expression] = parser:parse(expression)
  end
  return cache[expression]
end

-- Tokenizes the given JMESPath expression into a token stream
-- @param string expression JMESPath expression to tokenize
-- @return table
function jp.tokenize (expression)
  return lexer(expression)
end

return jp