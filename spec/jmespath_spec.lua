local jmespath = require "jmespath"

describe('jmespath', function()
  
  it("returns a result", function()
    assert.are.equal("foo", jmespath.search("a.b", {a={b="foo"}}))
  end)

  it("parses", function()
    assert.are.same({
      type = "subexpression",
      children = {
        {type = "field", key = "foo"},
        {type = "field", key = "bar"}
      }
    }, jmespath.parse("foo.bar"))
  end)

  it("tokenizes", function()
    local stream = jmespath.tokenize("foo.bar")

    stream:next()
    assert.are.same({
      type = "identifier",
      pos = 1,
      value = "foo"
    }, stream.cur)

    stream:next()
    assert.are.same({
      type = "dot",
      pos = 4,
      value = "."
    }, stream.cur)

    stream:next()
    assert.are.same({
      type = "identifier",
      pos = 5,
      value = "bar"
    }, stream.cur)

    stream:next()
    assert.are.same({
      type = "eof",
      pos = 8
    }, stream.cur)
  end)

end)
