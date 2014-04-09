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

    local expression = "foo.baz"
    local result = jmespath.search(expression, data)

Testing
-------

jmespath.lua is tested using `busted <http://olivinelabs.com/busted>`_. You'll
need to install busted to run the tests::

    luarocks install luacov
    luarocks install busted

After installing busted, you can run the tests with the following command::

    busted