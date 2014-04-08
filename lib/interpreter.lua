-- Interprets JMESPath ASTs

-- Tree visitor prototypr
local Tree = {}

-- Double-dispatch function used to implement the external AST visitor.
function Tree:visit (node, data)
  return self["visit_" .. node.type](self, node, data)
end

-- Returns a specific field of the current node
function Tree:visit_field (node, data)
  if type(data) == "table" and data[node.key] ~= nil then
    return data[node.key]
  end
end

-- Passes the result of the left expression to the right expression
function Tree:visit_subexpression (node, data)
  return self:visit(node.children[2], self:visit(node.children[1], data))
end

-- Returns a specific index of the current node
function Tree:visit_index (node, data)
  if type(data) ~= "table" then return nil end
  if node.index < 0 then node.index = #data + node.index end
  node.index = node.index + 1
  if type(data) == "table" and data[node.index] ~= nil then
    return data[node.index]
  end
end

-- Interprets a projection node, passing the values of the left child through
-- the values of the right child and aggregating the non-null results into
-- the return value.
function Tree:visit_projection (node, data)
  local left = self:visit(node.children[1], data)

  if type(left) ~= "table" then
    return nil
  end

  -- Validates the expected type of the projection
  if node.from and #left and (
    (node.from == "object" and data[1] ~= nil)
    or (node.from == "array" and data[1] == nil)
  ) then
    return nil
  end

  local collected = {}
  for _, v in pairs(left) do
    local result = self:visit(node.children[1], v)
    if result ~= nil then
        collected[#collected + 1] = result
    end
  end

  return collected
end

-- Flattens (merges) up the current node
function Tree:visit_flatten (node, data)
end

-- Returns a literal value
function Tree:visit_literal (node, data)
  return node.value
end

-- Returns the current node (identity node)
function Tree:visit_current (node, data)
  return data
end

-- Evaluates the left expression, and if it evaluates to false, returns the
-- result of the right expression.
function Tree:visit_or (node, data)
  local result = self:visit(node.children[1], data)
  local t = type(result)
  if result == nil or result == false or result == ""
    or (t == "table" and #result == 0)
  then
    result = self:visit(node.children[2], data)
  end
  return result
end

-- Passes the result of the left expression to the right expression while
-- stopping any open projections.
function Tree:visit_pipe (node, data)
  return self:visit(node.children[2], self:visit(node.children[1], data))
end

-- Returns a sequence table of results
function Tree:visit_multi_select_list (node, data)
  if data == nil then return nil end
  local collected = {}
  for k, v in ipairs(node.children) do
    collected[#collected + 1] = self:visit(v, value)
  end
  return collected
end

-- Returns a hash table of results
function Tree:visti_multi_select_hash (node, data)
  if data == nil then return nil end
  local collected = {}
  for k, v in ipairs(node.children) do
    collected[v.key] = self:visit(v.children[0], value)
  end
  return collected
end

-- Evaluates a comparison
function Tree:visit_comparator (node, data)
end

-- Returns a value if a condition evaluates to true or nil
function Tree:visti_condition (node, data)
  if true == self:visit(node.children[0], data) then
    return self:visit(node.children[1], data)
  end
  return nil
end

-- Returns the result of a funciton
function Tree:visit_function (node, data)
end

-- Returns the result of a string or array slice
function Tree:visit_slice (node, data)
end

-- Returns an expression node
function Tree:visit_expression (node, data)
  return {node = node, interpreter = self}
end

return Tree
