============
jmespath.lua
============

A pure Lua implementation of `JMESPath <http://jmespath.readthedocs.org/en/latest/>`_.

.. code-block:: lua

    local jmespath = require "jmespath"
    
    local data = {
      foo = {
        baz = "bar"
      }
    }

    print(jmespath.search("foo.baz", data))
