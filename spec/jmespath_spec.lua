local jmespath = require "jmespath"
local Parser = require 'jmespath.parser'
local Lexer = require 'jmespath.lexer'
local Interpreter = require 'jmespath.interpreter'

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
    local tokens = jmespath.tokenize("foo.bar")

    assert.are.same({
      type = "identifier",
      pos = 1,
      value = "foo"
    }, tokens[1])

    assert.are.same({
      type = "dot",
      pos = 4,
      value = "."
    }, tokens[2])

    assert.are.same({
      type = "identifier",
      pos = 5,
      value = "bar"
    }, tokens[3])

    assert.are.same({type = "eof", pos = 8, value = ''}, tokens[4])
  end)

end)
