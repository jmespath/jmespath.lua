-- Interprets JMESPath ASTs
--
--     local Interpreter = require 'jmespath.interpreter'
--     local interpreter = Interpreter.new()
--     local result = interpreter:visit(ast_node, data_to_visit)
--
-- The interpreter accepts an optional configuration table that can contain
-- the following keys:
--
-- - hashfn: A function that returns the data structure used to create hashes
--   (e.g., used when evaluating multi-select-hash nodes). This can be useful
--   if you wanted to provide a custom data structure that maintains ordered
--   hashes.
--
-- @module jmespath.interpreter

-- Interpreter prototype
local Interpreter = {}
local Functions = require('jmespath.functions')

--- Interpreter constructor
function Interpreter.new(config)
  local self = setmetatable({}, {__index = Interpreter})
  if config then
    if config.hashfn then self.hashfn = config.hashfn end
    if config.fn_dispatcher then self.fn_dispatcher = config.fn_dispatcher end
  end
  if not self.hashfn then
    self.hashfn = function() return {} end
  end
  if not self.fn_dispatcher then
    self.fn_dispatcher = Functions.new()
  end
  return self
end

-- Each visitor that handles a particular node type
local visitors = {

  --- Returns a specific field of the current node
  field = function(interpreter, node, data)
    if type(data) == 'table' then return data[node.value] end
  end,

  --- Passes the result of the left expression to the right expression
  subexpression = function(interpreter, node, data)
    return interpreter:visit(
      node.children[2],
      interpreter:visit(node.children[1], data)
    )
  end,

  --- Returns a specific index of the current node
  index = function(interpreter, node, data)
    if type(data) ~= 'table' then return nil end
    if node.value < 0 then return data[#data + node.value + 1] end
    return data[node.value + 1]
  end,

  --- Interprets an object projection node
  object_projection = function(interpreter, node, data)
    local left = interpreter:visit(node.children[1], data)
    -- The left result must be a hash or sequence.
    if type(left) ~= 'table' then return nil end
    -- Empty tables should just return the table.
    if next(left) == nil then return left end
    -- Don't perform an object projection on an array
    if #left > 0 then return nil end

    local collected = {}
    local m = getmetatable(left)
    local order

    -- Determine the key order if possible
    if m and m.__jsonorder then
      order = m.__jsonorder
    else
      order = {}
      for k, _ in pairs(left) do order[#order + 1] = k end
    end

    for _, v in ipairs(order) do
      local value = left[v]
      local result = interpreter:visit(node.children[2], value)
      if result ~= nil then collected[#collected + 1] = result end
    end

    return collected
  end,

  --- Interprets an array projection
  array_projection = function(interpreter, node, data)
    local left = interpreter:visit(node.children[1], data)
    -- The left result must be a hash or sequence.
    if type(left) ~= 'table' then return nil end
    -- Empty tables should just return the table.
    if next(left) == nil then return left end
    -- Don't perform an array on an object
    if #left == 0 then return nil end

    local collected = {}
    for _, v in pairs(left) do
      local result = interpreter:visit(node.children[2], v)
      if result ~= nil then collected[#collected + 1] = result end
    end

    return collected
  end,

  --- Flattens(merges) up the current node
  flatten = function(interpreter, node, data)
    local left = interpreter:visit(node.children[1], data)
    -- flatten requires that the left result returns a sequence
    if type(left) ~= 'table' then return nil end
    -- Return if empty because we can't differentiate between an array and hash.
    if next(left) == nil then return left end
    -- It is not empty, so ensure that the left result is a sequence table.
    if #left == 0 then return nil end

    local merged = {}
    for _, v in ipairs(left) do
      -- Push everything on that is not a table or is a hash.
      if type(v) ~= 'table' or (next(v) ~= nil and #v == 0) then
        merged[#merged + 1] = v
      elseif #v > 0 then
        -- Merge up sequence tables into the merged result.
        for _, j in ipairs(v) do
          merged[#merged + 1] = j
        end
      end
    end

    return merged
  end,

  --- Returns a literal value
  literal = function(interpreter, node, data)
    return node.value
  end,

  --- Returns the current node (identity node)
  current = function(interpreter, node, data)
    return data
  end,

  --- Evaluates an or expression
  -- Evaluates the left expression, and if it evaluates to false, returns the
  -- result of the right expression.
  ["or"] = function(interpreter, node, data)
    local result = interpreter:visit(node.children[1], data)
    local t = type(result)
    if not result or result == '' or (t == 'table' and next(result) == nil)
    then
      result = interpreter:visit(node.children[2], data)
    end
    return result
  end,

  --- Evaluates a pipe expression
  -- Passes the result of the left expression to the right expression while
  -- stopping any open projections.
  pipe = function(interpreter, node, data)
    return interpreter:visit(
      node.children[2],
      interpreter:visit(node.children[1], data)
    )
  end,

  --- Returns a sequence table of results
  multi_select_list = function(interpreter, node, data)
    if data == nil then return nil end
    local collected = {}
    local n = 0
    for _, v in pairs(node.children) do
      n = n + 1
      collected[n] = interpreter:visit(v, data)
    end
    return collected
  end,

  --- Returns a hash table of results
  multi_select_hash = function(interpreter, node, data)
    if data == nil then return nil end
    local collected, order = interpreter.hashfn(), {}
    for _, v in ipairs(node.children) do
      collected[v.value] = interpreter:visit(v.children[1], data)
      order[#order + 1] = collected[v.value]
    end
    return setmetatable(collected, {__jsonorder = order})
  end,

  --- Evaluates a comparison
  comparator = function(interpreter, node, data)
    -- @TODO
  end,

  --- Returns a value if a condition evaluates to true or nil
  condition = function(interpreter, node, data)
    if interpreter:visit(node.children[1], data) then
      return interpreter:visit(node.children[2], data)
    end
  end,

  --- Returns the result of a function call
  ["function"] = function(interpreter, node, data)
    local args = {}
    for _, i in pairs(node.children) do
      args[#args + 1] = interpreter:visit(i, data)
    end
    return interpreter.fn_dispatcher(node.value, args)
  end,

  --- Returns an expression node
  expression = function(interpreter, node, data)
    return {node = node, interpreter = interpreter}
  end
}

--- Double-dispatch function used to implement the external AST visitor.
-- @tparam table node Node to traverse
-- @param        data Data to search
-- @return Returns the evaluated result.
function Interpreter:visit(node, data)
  return visitors[node.type](self, node, data)
end

return Interpreter
