-- Implements JMESPath functions.
--
-- @module jmespath.functions

local Functions = {}
local json = require 'json'

function fn_abs(args)
  validate('abs', args, {{'number'}})
  return math.abs(args[1])
end

function fn_avg(args)
  validate('avg', args, {{'array'}})
  if not #args[1] then return nil end
  return fn_sum(args) / #args[1]
end

function fn_ceil(args)
  validate('ceil', args, {{'number'}})
  return math.ceil(args[1])
end

function fn_contains(args)
  validate('contains', args, {{'string', 'array'}, {'any'}})
  if type(args[1]) == 'table' then
    return Functions.in_table(args[2], args[1])
  end
  return string.find(args[1], args[2]) ~= nil
end

function fn_ends_with(args)
  validate('ends_with', args, {{'string'}})
  return args[2] == '' or string.sub(args[1], -string.len(args[2])) == args[2]
end

function fn_floor(args)
  validate('floor', args, {{'number'}})
  return math.floor(args[1])
end

function fn_join(args)
  validate('join', args, {{'array'}, {'string'}})
  local fn = function (carry, item, index)
    if index == 1 then return item end
    return carry .. args[2] .. item
  end
  return typed_reduce('join:0', args[1], {'string'}, fn)
end

function fn_keys(args)
  validate('keys', args, {{'object'}})
  local keys = {}
  for k, _ in pairs(args[1]) do keys[#keys + 1] = k end
  return keys
end

function fn_length(args)
  validate('length', args, {{'array', 'string'}})
  return #args[1]
end

function fn_not_null(args)
  validate_arity('not_null:0', #args, 1)
  for _, i in pairs(args) do
    if i ~= nil then return i end
  end
end

function fn_max(args)
  validate('max', args, {{'array'}})
  local fn = function (carry, item, index)
    if index > 1 and carry >= item then return carry end
    return item
  end
  return typed_reduce('max:0', args[1], {'number', 'string'}, fn)
end

function fn_max_by(args)
  validate('max_by', args, {{'array'}, {'expression'}})
  local expr = wrap_expr('max_by:1', args[2], {'number', 'string'})
  local fn = function (carry, item, index)
    if index == 1 then return item end
    if expr(carry) >= expr(item) then return carry end
    return item
  end
  return typed_reduce('max_by:1', args[1], {'any'}, fn)
end

function fn_min(args)
  validate('min', args, {{'array'}})
  local fn = function (carry, item)
    if index > 1 and carry <= item then return carry end
    return item
  end
  return typed_reduce('min:0', args[1], {'number', 'string'}, fn)
end

function fn_min_by(args)
  validate('min_by', args, {{'array'}})
  local expr = wrap_expr('min_by:1', args[2], {'number', 'string'})
  local fn = function (carry, item, index)
    if index == 1 then return item end
    if expr(carry) <= expr(item) then return carry end
    return item
  end
  return typed_reduce('min_by:1', args[1], {'any'}, fn)
end

function fn_reverse(args)
  validate('reverse', args, {{'array', 'string'}})
  if type(args[1]) == 'string' then
    return string.reverse(args[1])
  end
  local reversed, items = {}, #args[1]
  for k, v in ipairs(args[1]) do reversed[items + 1 - k] = v end
  return reversed
end

function fn_sort(args)
  validate('sort', args, {{'array'}})
  local valid = {'string', 'number'}
  return Functions.stable_sort(args[1], function (a, b)
    validate_seq('sort:0', valid, a, b)
    return sortfn(a, b)
  end)
end

function fn_sort_by(args)
  validate('sort_by', args, {{'array'}, {'expression'}})
  local expr, valid = args[2], {'string', 'number'}
  return Functions.stable_sort(args[1], function (a, b)
    local va, vb = expr(a), expr(b)
    validate_seq('sort_by:0', valid, va, vb)
    return sortfn(va, vb)
  end)
end

function fn_sum(args)
  validate('sum', args, {{'array'}})
  local fn = function (carry, item, index)
    if index > 1 then return carry + item end
    return item
  end
  return typed_reduce('sum:0', args[1], {'number'}, fn)
end

function fn_starts_with(args)
  validate('starts_with', args, {{'array'}})
  return string.sub(args[1], 1, string.len(args[2])) == args[2]
end

function fn_type(args)
  validate_arity('type:0', #args, 1)
  return Functions.type(args[1])
end

function fn_to_number(args)
  validate_arity('to_number:0', #args, 1)
  return tonumber(args[1])
end

function fn_to_string(args)
  validate_arity('to_string:0', #args, 1)
  if type(args[1]) == 'table' then
    local meta = getmetatable(args[1])
    if meta and meta.__tostring then
      return tostring(args[1])
    end
    return json.encode(args[1])
  end
  return tostring(args[1])
end

function fn_values(args)
  validate('values', args, {{'array'}})
  local values = {}
  for _, i in pairs(args[1]) do
    values[#values + 1] = i
  end
  return values
end

function Functions.new(config)
  local fns = {
    abs = fn_abs,
    avg = fn_avg,
    ceil = fn_ceil,
    contains = fn_contains,
    ends_with = fn_ends_with,
    floor = fn_floor,
    keys = fn_keys,
    length = fn_length,
    join = fn_join,
    not_null = fn_not_null,
    max = fn_max,
    max_by = fn_max_by,
    min = fn_min,
    min_by = fn_min_by,
    reverse = fn_reverse,
    sort = fn_sort,
    sort_by = fn_sort_by,
    starts_with = fn_starts_with,
    sum = fn_sum,
    to_number = fn_to_number,
    to_string = fn_to_string,
    type = fn_type,
    values = fn_values
  }
  return setmetatable({}, {
    __index = Functions,
    __call = function(t, fn, args)
      if not fns[fn] then error('Invalid function call: ' .. fn) end
      return fns[fn](args)
    end
  })
end

function validate_arity(from, given, expected)
  if given ~= expected then
    error(from .. ' expects ' .. expected .. ' arguments. ' .. given
      .. ' were provided.')
  end
end

function type_error(from, msg)
  if not string.match(from, ':') then
    error('Type error: ' .. from .. ' ' .. msg)
  end
  error('Argument ' .. from .. ' ' .. msg)
end

function validate(from, args, types)
  validate_arity(from, #args, #types)
  for k, v in pairs(args) do
    if types[k] and #types[k] then
      validate_type(from .. ':' .. k, v, types[k])
    end
  end
end

function validate_type(from, value, types)
  if types[1] == 'any'
    or Functions.in_table(Functions.type(value), types)
    or (value == {} and Functions.in_table('array', types))
  then
    return
  end
  local msg = 'must be one of the following types: '
    .. table.concat(types, '|') .. '. ' .. Functions.type(value) .. ' found';
  type_error(from, msg);
end

function validate_seq(from, types, a, b)
  local ta, tb = Functions.type(a), Functions.type(b)
  if ta ~= tb then
    type_error(from, 'encountered a type mismatch in sequence: ' .. ta .. ', ' .. tb)
  end
  local match = (#types and types[1] == 'any')
    or Functions.in_table(ta, types)
  if not match then
    type_error(from, 'encountered a type error in sequence. The argument must '
      .. 'be an array of ' .. table.concat(types, '|') .. ' types. Found '
      .. ta .. ', ' .. tb)
  end
end

--- Reduces a table to a single value while validating the sequence types
-- @param string   from  'function:position'
-- @param table    tbl   Table to reduce
-- @param table    types Valid types
-- @param function func  Reduce function
function typed_reduce(from, tbl, types, func)
  return Functions.reduce(tbl, function (carry, item, index)
    if index > 1 then validate_seq(from, types, carry, item) end
    return func(carry, item, index)
  end)
end

--- Returns a composed function that validates the return value
-- @param string   from  'function:position'
-- @param function expr  Function to wrap
-- @param table    types Valid types
function wrap_expr(from, expr, types)
  from = 'The expression return value of ' .. from
  return function (value)
    value = expr(value)
    validate_type(from, value, types)
    return value
  end
end

--- Implements a sort function that returns 0, 1, or -1
-- @param string|number a Left value
-- @param string|number b Right value
-- @return number
function sortfn(a, b)
  if a == b then return 0 end
  if a < b then return -1 end
  return 1
end

--- Check if the search value is in table t
-- @param mixed search Value to find
-- @param table t      Table to search
-- @return bool
function Functions.in_table(search, t)
  for _, value in pairs(t) do
    if value == search then return true end
  end
  return false
end

--- Reduces a table using a callback function
-- @param table    tbl     Table to reduce
-- @param function func    Reduce function that accepts (carry, item)
-- @param mixed    initial Optionally provide an initial carry value.
function Functions.reduce(tbl, func, initial)
  local carry = initial
  for index, item in pairs(tbl) do
    carry = func(carry, item, index)
  end
  return carry
end

--- Determines if the given value is a JMESPath object
-- @param mixed value
-- @return bool
function Functions.is_object(value)
  return #value == 0
end

--- Determines if the given value is a JMESPath array
-- @param mixed value
-- @return bool
function Functions.is_array(value)
  return #value > 0
end

--- Implements a stable sort using a sort function
-- @param table    data Data to sort
-- @param function func Accepts a, b and returns -1, 0, or 1.
-- @return table
function Functions.stable_sort(data, func)
  -- Decorate each item by creating an array of [value, index]
  local wrapped, sorted = {}, {}
  for k, v in pairs(data) do wrapped[#wrapped + 1] = {v, k} end
  -- Sort by the sort function and use the index as a tie-breaker
  table.sort(wrapped, function (a, b)
    local result = func(a[1], b[1])
    if result == 0 then
      return a[2] < b[2]
    end
    return result == -1
  end)
  -- Undecorate each item and return the resulting sorted array
  for _, v in pairs(wrapped) do
    sorted[#sorted + 1] = v[1]
  end
  return sorted
end

--- Returns the JMESPath type of a Lua variable
-- @param mixed value
-- @return string
function Functions.type(value)
  local t = type(value)
  if t == 'string' then return 'string' end
  if t == 'number' then return 'number' end
  if t == 'float' then return 'float' end
  if t == 'boolean' then return 'boolean' end
  if t == 'function' then return 'expression' end
  if t == 'nil' then return 'null' end
  if t == 'table' then
    if Functions.is_object(value) then return 'object' end
    return 'array'
  end
end

return Functions
