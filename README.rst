============
jmespath.lua
============

A pure Lua implementation of `JMESPath <http://jmespath.readthedocs.org/en/latest/>`_.

.. code-block:: lua

    local jmespath = require "jmespath"
    local expression = "foo.baz"
    local data = { foo = { baz = "bar" } }
    local result = jmespath.search(expression, data)

jmespath.lua can be installed using `LuaRocks <http://luarocks.org/>`_:

::

    luarocks install jmespath

Runtimes
--------

jmespath.lua allows you to create a customized runtime using a hash of
configuration options to control how jmespath.lua parses and evaluates
expressions. Use the ``jmespath.runtime()`` function to create a new runtime.

.. code-block:: lua

    local jmespath = require 'jmespath'
    local runtime = jmespath.runtime()
    runtime('foo', {foo=10}) -- outputs 10

The ``runtime`` function accepts a hash of the following configuration options:

fn_dispatcher
    A function that accepts a function name as the first argument and a
    sequence of arguments as the second argument. This can be useful for
    registering new functions with the JMESPath interpreter. For example, let's
    say you wanted to add a custom ``add`` function that accepts a variadic
    number of arguments. This can be acheived by wrapping the existing default
    function dispatcher and adding a new function:

    .. code-block:: lua

        local jmespath = require 'jmespath'
        local default_dispatcher = jmespath.Functions.new()
        local dispatcher = function (name, args)
          if name == 'add' then
            jmespath.Functions.reduce(args, function (carry, item, index)
              if index > 1 then return carry + item end
              return item
            end)
          end
          return default_dispatcher(name, args)
        end
        local runtime = jmespath.runtime{fn_dispatcher = dispatcher}
        runtime('foo', {foo=10}) -- outputs 10

Testing
-------

jmespath.lua is tested using `busted <http://olivinelabs.com/busted>`_. You'll
need to install busted and luafilesystem to run the tests::

    make test-setup

After installing jmespath.lua, you can run the tests with the following
command::

    make test
