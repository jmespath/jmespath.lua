local jmespath = require "jmespath"
local lfs = require "lfs"
local json = require "jmespath.json"

local function jcmp(a, b)

  local ta, tb = type(a), type(b)
  if ta ~= tb then return false end
  if ta ~= "table" then return a == b end
  if #a ~= #b then return false end
  local visited = {}

  if #a > 0 then
    for k1, v1 in ipairs(a) do
      for k2, v2 in ipairs(b) do
        if not visited[k2] and jcmp(v1, v2) then
          visited[k2] = true
          break
        end
      end
    end
    return #visited == #a
  end

  for k, _ in pairs(a) do
    if not jcmp(a[k], b[k]) then return false end
    visited[k] = true
  end

  for k, _ in pairs(b) do
    if not visited[k] and not jcmp(a[k], b[k]) then return false end
  end

  return true
end

describe('compliance', function()

  -- Load the test suite JSON data from a file
  local function load_test(file)
    local f = assert(io.open(file, "r"))
    local t = assert(f:read("*a"), "Error loading file: " .. file)
    local data = assert(json.decode(t), "Error decoding JSON: " .. file)
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
            if not jcmp(case.result, result) then
              assert.are.same(case.result, result)
            end
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
