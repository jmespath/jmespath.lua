local jmespath = require "jmespath"

describe('jmespath', function()
  
  it("returns a result", function()
    assert.are.equal("foo", jmespath.search("a.b", {a={b="foo"}}))
  end)

end)
