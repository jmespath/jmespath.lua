-- Implements an ordered hash using an array.
--
--     local ArrayMap = require "jmespath.arraymap"
--     local am = ArrayMap{foo = "bar", baz = "bam"}
--
-- Because lookups are implemented using an array of tuples representing
-- key value pairs, array lookups are O(n)
--
-- @module jmespath.arraymap

local ArrayMap = {}

--- Adds key value pairs into the array map as tuples
-- Overwrites any previously set value by the same key name.
function ArrayMap:__newindex(k, v)
  -- Remove an existing value from the table and the keys table
  if v == nil then
    if self._keys[k] then
      table.remove(self, self._keys[k])
      table.remove(self._keys, k)
    end
    return
  end

  if ArrayMap.get_value(self, k) == nil then
    -- Creating a new key
    self._keys[k] = #self + 1
    rawset(self, #self + 1, {k, v})
  else
    -- Overwrite the existing key
    rawset(self, self._keys[k], {k, v})
  end
end

--- Allows the ArrayMap to be used like a hash
function ArrayMap:__index(k)
  local result = ArrayMap.get_value(self, k)
  if result ~= nil then return result end
  return rawget(ArrayMap, k)
end

--- Iterates over the key value pairs of the table from the tuples
-- Lua 5.2+ only
function ArrayMap:__pairs()
  return self:iter()
end

--- Iterates over the key value pairs of the table from the tuples
function ArrayMap:iter()
  local i = 0
  return function()
    i = i + 1
    if i > #self then return nil end
    local tuple = rawget(self, i)
    return tuple[1], tuple[2]
  end
end

--- Gets a value from the array map by the key name.
-- @param k Key to retrieve
-- @return Returns the corresponding value and the index at which it was found.
function ArrayMap:get_value(k)
  local keys = rawget(self, "_keys")
  if keys[k] then return rawget(self, keys[k])[2] end
end

--- Appending all the key value pairs in the given hash to the array map
-- @param values Hash table of key value pairs to append
-- @return self
function ArrayMap:extend(values)
  for k, v in pairs(values) do self[k] = v end
  return self
end

-- Returns the ArrayMap prototype constructor function.
return setmetatable(ArrayMap, {
  --- ArrayMap constructor accepts an initial hash of data
  -- @param value Hash table of value to seed the array map with
  -- @return self
  __call = function(am, values)
    local instance = setmetatable({_keys = {}}, ArrayMap)
    if values then ArrayMap.extend(instance, values) end
    return instance
  end
})
