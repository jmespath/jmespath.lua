local Tree = {}

function Tree:visit(node, data)
  return self["visit_" .. node.type](self, node, data)
end

function Tree:visit_field(node, data)
  if type(data) == "table" and data[node.key] ~= nil then
    return data[node.key]
  end
end

function Tree:visit_subexpression(node, data)
  return self:visit(node.children[2], self:visit(node.children[1], data))
end

function Tree:visit_index(node, data)
  if type(data) ~= "table" then return nil end
  if node.index < 0 then node.index = #data + node.index end
  node.index = node.index + 1
  if type(data) == "table" and data[node.index] ~= nil then
    return data[node.index]
  end
end

function Tree:visit_projection(node, data)
end

function Tree:visit_flatten(node, data)
end

function Tree:visit_literal(node, data)
  return node.value
end

function Tree:visit_current(node, data)
  return data
end

function Tree:visit_or(node, data)
  local result = self:visit(node.children[1], data)
  local t = type(result)
  if result == nil or result == false or result == ""
    or (t == "table" and #result == 0)
  then
    result = self:visit(node.children[2], data)
  end
  return result
end

function Tree:visit_pipe(node, data)
  return self:visit(node.children[2], self:visit(node.children[1], data))
end

function Tree:visit_multi_select_list(node, data)
  if data == nil then return nil end
  local collected = {}
  for k, v in ipairs(node.children) do
    collected[#collected + 1] = self:visit(v, value)
  end
  return collected
end

function Tree:visti_multi_select_hash(node, data)
  if data == nil then return nil end
  local collected = {}
  for k, v in ipairs(node.children) do
    collected[v.key] = self:visit(v.children[0], value)
  end
  return collected
end

function Tree:visit_comparator(node, data)
end

function Tree:visti_condition(node, data)
  if true == self:visit(node.children[0], data) then
    return self:visit(node.children[1], data)
  end
  return nil
end

function Tree:visit_function(node, data)
end

function Tree:visit_slice(node, data)
end

function Tree:visit_expression(node, data)
end

return Tree
