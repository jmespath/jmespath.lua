-- Implements JMESPath functions.
--
-- @module jmespath.functions

local Functions = {}
local json = require 'jmespath.json'

function fn_abs(args)
  validate('abs', args, {{'number'}})
  return math.abs(args[1])
end

function fn_avg(args)
  validate('avg', args, {{'array'}})
  -- @TODO
end

function fn_ceil(args)
  validate('ceil', args, {{'number'}})
  return math.ceil(args[1])
end

function fn_contains(args)
  validate('contains', args, {{'string', 'array'}, {'any'}})
  if type(args[1]) == 'table' then
    return in_table(args[1], args[2])
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
  validate('join', args, {{'array'}})
  -- @TODO
end

function fn_keys(args)
  validate('keys', args, {{'object'}})
  local keys = {}
  for k, _ in pairs(args[1]) do
    keys[#keys + 1] = k
  end
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
  -- @TODO
end

function fn_max_by(args)
  validate('max_by', args, {{'array'}})
  -- @TODO
end

function fn_min(args)
  validate('min', args, {{'array'}})
  -- @TODO
end

function fn_min_by(args)
  validate('min_by', args, {{'array'}})
  -- @TODO
end

function fn_reverse(args)
  validate('reverse', args, {{'array', 'string'}})
  if type(args[1]) == 'string' then
    return string.reverse(args[1])
  end
  local reversed = {}
  local items = #args[1]
  for k, v in ipairs(args[1]) do
    reversed[items + 1 - k] = v
  end
  return reversed
end

function fn_sort(args)
  validate('sort', args, {{'array'}})
  table.sort(args[1])
  return args[1]
end

function fn_sort_by(args)
  validate('sort_by', args, {{'array'}})
  -- @TODO
end

function fn_sum(args)
  validate('sum', args, {{'array'}})
  -- @TODO
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

function in_table(t, search)
  for _, value in pairs(t) do
    if value == search then return true end
  end
  return false
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
    or in_table(types, Functions.type(value))
    or (value == {} and type == {'array'})
  then
    return
  end
  local msg = 'must be one of the following types: '
    .. table.concat(types, '|') .. '. ' .. Functions.type(value) .. ' found';
  type_error(from, msg);
end

function validate_seq(from, types, a, b)
  -- @TODO
end

function Functions.is_object(value)
  return #value == 0
end

function Functions.is_array(value)
  return #value > 0
end

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
