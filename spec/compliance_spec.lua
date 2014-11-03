local jmespath = require 'jmespath'
local lfs = require 'lfs'
local json = require 'json'
local json_decoder = json.decode.getDecoder({
  others = {null = false},
  object = {
    setObjectKey = function (object, key, value)
      local meta = getmetatable(object)
      if not meta then
        setmetatable(object, {__jsonorder = {key}})
      else
        meta.__jsonorder[#meta.__jsonorder + 1] = key
      end
      object[key] = value
    end
  }
})

describe('compliance', function()

  -- Load the test suite JSON data from a file
  local function load_test(file)
    local f = assert(io.open(file, "r"))
    local t = assert(f:read("*a"), "Error loading file: " .. file)
    local data = assert(json_decoder(t), "Error decoding JSON: " .. file)
    f:close()
    return data
  end

  -- Run a test suite
  local function runsuite(file)
    data = assert(load_test(file))

    for i, suite in ipairs(data) do
      for i2, case in ipairs(suite.cases) do
        local name = string.format("%s from %s (Suite %s, case %s)",
          case.expression, file, i, i2)
        it(name, function()
          if case.error then
            assert.is_false(pcall(jmespath.search, case.expression, suite.given))
          elseif type(case.result) == "nil" then
            assert.is_true(jmespath.search(case.expression, suite.given) == nil)
          else
            local result = jmespath.search(case.expression, suite.given)
            local a = json.encode(result)
            local b = json.encode(case.result)
            -- Account for {} and [] being equivalent
            if a ~= b then
              a = a:gsub('{}', '[]')
              b = b:gsub('{}', '[]')
            end
            -- Account for nil being a weird concept in lua
            if a ~= b then
              a = a:gsub(',null', '')
              a = a:gsub('null', '')
              b = b:gsub(',null', '')
              b = b:gsub('null', '')
            end
            assert.are.same(a, b)
          end
        end)
      end
    end
  end

  local prefix = lfs.currentdir() .. "/spec/compliance/"
  local iter, obj = lfs.dir(prefix)
  local cur = obj:next()

  while cur do
    local attr = lfs.attributes(prefix .. cur)
    if attr.mode == "file" then
      runsuite(prefix .. cur)
    end
    cur = obj:next()
  end

  obj:close()

end)
