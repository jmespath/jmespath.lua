local jmespath = require "jmespath"
local lfs = require "lfs"
local json = require "dkjson"

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
    print(file)
    data = assert(load_test(file))

    for i, suite in ipairs(data) do
      for i2, case in ipairs(suite.cases) do
        local result = jmespath.search(case.expression, suite.given)
        print(file .. ": " .. i .. ": " .. i2 .. ": " .. case.expression)
        if case.result == nil then
          assert.is_nil(result)
        else
          assert.are.same(case.result, result)
        end
      end
    end
  end

  it("passes compliance tests", function()
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

end)
