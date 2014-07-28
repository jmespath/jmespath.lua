package = "jmespath"
version = "0.1-0"

source = {
   url = "git://github.com/mtdowling/jmespath",
   tag = "0.1.0",
}

description = {
   summary = "Declaratively specify how to extract elements from a JSON document, in Lua",
   homepage = "https://github.com/mtdowling/jmespath.lua",
   license = "MIT"
}

dependencies = {
   "lua >= 5.1",
   "dkjson"
}

build = {
   type = "builtin",
   modules = {
      ["jmespath"] = "lib/jmespath.lua",
      ["jmespath.lexer"] = "lib/lexer.lua",
      ["jmespath.parser"] = "lib/parser.lua",
      ["jmespath.interpreter"] = "lib/interpreter.lua",
      ["jmespath.arraymap"] = "lib/arraymap.lua",
   }
}
