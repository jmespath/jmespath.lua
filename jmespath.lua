local jmespath = {
  _VERSION     = '0.1.0',
  _DESCRIPTION = 'Declaritively extract data from JSON like structures',
  _URL         = 'https://github.com/mtdowling/jmespath.lua',
  _LICENSE     = 'https://github.com/mtdowling/jmespath.lua/blob/master/LICENSE'
}

------------------------------------------
-- Custom JSON decoding function
------------------------------------------

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

------------------------------------------
-- Lexer
------------------------------------------

local Lexer = (function()
  local Lexer = {}

  --- Lexer constructor
  function Lexer.new()
    return setmetatable({}, {__index = Lexer})
  end

  local tset = (function()
    local t = {
      -- Simple, single character, tokens
      simple = {
        [' ']  = 'ws',
        ['\n'] = 'ws',
        ['\t'] = 'ws',
        ['\r'] = 'ws',
        ['.']  = 'dot',
        ['*']  = 'star',
        [',']  = 'comma',
        [':']  = 'colon',
        ['{']  = 'lbrace',
        ['}']  = 'rbrace',
        [']']  = 'rbracket',
        ['(']  = 'lparen',
        [')']  = 'rparen',
        ['@']  = 'current',
        ['&']  = 'expref'
      },
      -- Tokens that can be numbers
      numbers = {
        ['0'] = 1, ['1'] = 1, ['2'] = 1, ['3'] = 1, ['4'] = 1, ['5'] = 1,
        ['6'] = 1, ['7'] = 1, ['8'] = 1, ['9'] = 1
      },
      -- Tokens that can start an identifier
      identifier_start = {
        ['a'] = 1, ['b'] = 1, ['c'] = 1, ['d'] = 1, ['e'] = 1, ['f'] = 1,
        ['g'] = 1, ['h'] = 1, ['i'] = 1, ['j'] = 1, ['k'] = 1, ['l'] = 1,
        ['m'] = 1, ['n'] = 1, ['o'] = 1, ['p'] = 1, ['q'] = 1, ['r'] = 1,
        ['s'] = 1, ['t'] = 1, ['u'] = 1, ['v'] = 1, ['w'] = 1, ['x'] = 1,
        ['y'] = 1, ['z'] = 1, ['A'] = 1, ['B'] = 1, ['C'] = 1, ['D'] = 1,
        ['E'] = 1, ['F'] = 1, ['G'] = 1, ['H'] = 1, ['I'] = 1, ['J'] = 1,
        ['K'] = 1, ['L'] = 1, ['M'] = 1, ['N'] = 1, ['O'] = 1, ['P'] = 1,
        ['Q'] = 1, ['R'] = 1, ['S'] = 1, ['T'] = 1, ['U'] = 1, ['V'] = 1,
        ['W'] = 1, ['X'] = 1, ['Y'] = 1, ['Z'] = 1, ['_'] = 1
      },
      -- Operator start tokens
      operator_start = {['='] = 1, ['<'] = 1, ['>'] = 1, ['!'] = 1},
      -- When a JSON literal starts with these, then JSON decode them.
      json_decode_char = {['"'] = 1, ['['] = 1, ['{'] = 1}
    }

    -- Combine two sequence tables into a new table.
    local function combine_seq(a, b)
      local result = {}
      for k, _ in pairs(a) do result[k] = true end
      for k, _ in pairs(b) do result[k] = true end
      return result
    end

    -- Represents identifier start tokens (merged with identifier_start).
    t.identifiers = combine_seq(t.identifier_start, t.numbers)
    t.identifiers['-'] = true
    -- Valid operator tokens
    t.operators = combine_seq(t.operator_start, {
      ['<='] = 1, ['>='] = 1, ['!='] = 1, ['=='] = 1
    })
    -- Valid JSON number tokens
    t.json_numbers = combine_seq(t.numbers, {['-'] = 1})
    return t
  end)()

  --- Creates a sequence table of tokens for use in a token stream.
  -- @tparam  string      Expression Expression to tokenize
  -- @treturn table Returns a sequence table of tokens
  function Lexer:tokenize(expression)
    local tokens = {}
    self.token_iter = expression:gmatch('.')
    self.pos = 0
    consume(self)
    while self.c do
      if tset.identifier_start[self.c] then
        tokens[#tokens + 1] = consume_identifier(self)
      elseif tset.simple[self.c] then
        if tset.simple[self.c] ~= 'ws' then
          tokens[#tokens + 1] = {
            pos   = self.pos,
            type  = tset.simple[self.c],
            value = self.c
          }
        end
        consume(self)
      elseif tset.numbers[self.c] or self.c == '-' then
        tokens[#tokens + 1] = consume_number(self)
      elseif self.c == '[' then
        tokens[#tokens + 1] = consume_lbracket(self)
      elseif tset.operator_start[self.c] then
        tokens[#tokens + 1] = consume_operator(self)
      elseif self.c == '|' then
        tokens[#tokens + 1] = consume_pipe(self)
      elseif self.c == '"' then
        tokens[#tokens + 1] = consume_quoted_identifier(self)
      elseif self.c == '`' then
        tokens[#tokens + 1] = consume_literal(self)
      else
        error('Unexpected character ' .. self.c .. ' found at #' .. self.pos)
      end
    end
    tokens[#tokens + 1] = {type = 'eof', pos = self.pos, value = ''}
    return tokens
  end

  --- Advances to the next token and modifies the internal state of the lexer.
  function consume(lexer)
    lexer.c = lexer.token_iter()
    if lexer.c ~= '' then lexer.pos = lexer.pos + 1 end
  end

  --- Consumes an identifier token /[A-Za-z0-9_\-]/
  function consume_identifier(lexer)
    local buffer = {lexer.c}
    local start = lexer.pos
    consume(lexer)
    while tset.identifiers[lexer.c] do
      buffer[#buffer + 1] = lexer.c
      consume(lexer)
    end
    return {pos = start, type = 'identifier', value = table.concat(buffer)}
  end

  --- Consumes a number token /[0-9\-]/
  function consume_number(lexer)
    local buffer = {lexer.c}
    local start = lexer.pos
    consume(lexer)
    while tset.numbers[lexer.c] do
      buffer[#buffer + 1] = lexer.c
      consume(lexer)
    end
    return {
      pos   = start,
      type  = 'number',
      value = tonumber(table.concat(buffer))
    }
  end

  --- Consumes a flatten token, lbracket, and filter token: '[]', '[?', and '['
  function consume_lbracket(lexer)
    consume(lexer)
    if lexer.c == ']' then
      consume(lexer)
      return {pos = lexer.pos - 1, type = 'flatten', value = '[]'}
    elseif lexer.c == '?' then
      consume(lexer)
      return {pos = lexer.pos - 1, type = 'filter', value = '[?'}
    else
      return {pos = lexer.pos - 1, type = 'lbracket', value = '['}
    end
  end

  --- Consumes an operation <, >, !, !=, ==
  function consume_operator(lexer)
    local token = {
      type  = 'comparator',
      pos   = lexer.pos,
      value = lexer.c
    }
    consume(lexer)
    if lexer.c == '=' then
      consume(lexer)
      token.value = token.value .. '='
    elseif token.value == '=' then
      error('Expected ==, got =')
    end
    if not tset.operators[token.value] then
      error('Invalid operator: ' .. token.value)
    end
    return token
  end

  --- Consumes an or, '||', and pipe, '|' token
  function consume_pipe(lexer)
    consume(lexer)
    if lexer.c ~= '|' then
      return {type = 'pipe', value = '|', pos = lexer.pos - 1};
    end
    consume(lexer)
    return {type = 'or', value = '||', pos = lexer.pos - 2};
  end

  --- Parse a string of tokens inside of a delimiter.
  -- @param   lexer   Lexer instance
  -- @param   wrapper Wrapping character
  -- @param   skip_ws Set to true to skip whitespace
  -- @treturn table   Returns the start of a token
  local function parse_inside(lexer, wrapper, skip_ws)
    local p = lexer.pos
    local buffer = {}
    -- Consume the leading character
    consume(lexer)
    -- Removing leading whitespace
    if skip_ws then
      while lexer.c == ' ' do consume(lexer) end
    end
    while lexer.c and lexer.c ~= wrapper do
      if lexer.c == "\\" then
        consume(lexer)
        buffer[#buffer + 1] = "\\"
      end
      buffer[#buffer + 1] = lexer.c
      consume(lexer)
    end
    if lexer.c ~= wrapper then
      error('Expected `' .. wrapper .. "` but found "
            .. tostring(lexer.c) .. ' at character #' .. lexer.pos)
    end
    consume(lexer)
    return {value = table.concat(buffer), pos = p}
  end

  --- Consumes a literal token.
  function consume_literal(lexer)
    local token = parse_inside(lexer, '`', true)
    local first_char = token.value:sub(1, 1)
    token.type = 'literal'
    if tset.json_decode_char[first_char] or
      tset.json_numbers[first_char]
    then
      token.value = json_decoder(token.value)
    elseif token.value == 'null' then
      token.value = nil
    elseif token.value == 'true' then
      token.value = true
    elseif token.value == 'false' then
      token.value = false
    else
      token.value = json_decoder('"' .. token.value .. '"')
    end
    return token
  end

  --- Consumes a quoted string.
  function consume_quoted_identifier(lexer)
    local token = parse_inside(lexer, '"')
    token.type = 'quoted_identifier'
    token.value = json_decoder('"' .. token.value.. '"')
    return token
  end

  return Lexer
end)()

------------------------------------------
-- JMESPath parser
------------------------------------------

local Parser = (function()
  local Parser = {}

  --- Creates a new parser
  -- @param Lexer
  function Parser.new()
    local self = setmetatable({}, {__index = Parser})
    self.lexer = Lexer.new()
    return self
  end

  function Parser:advance(valid)
    if self.pos < #self.tokens then
      self.pos = self.pos + 1
      self.token = self.tokens[self.pos]
    end
    if valid and not valid[self.token.type] then
      error('Syntax error at ' .. self.pos .. '. Found '
        .. self.token.type .. ' but expected one of: '
        .. table.concat(table_keys(valid), ', '))
    end
  end

  --- Peeks at the next token type without consuming it
  -- @treturn table
  function Parser:peek()
    if self.pos < #self.tokens then
      return self.tokens[self.pos + 1].type
    else
      return 'eof'
    end
  end

  --- Ensures that a token is not the given type or errors
  -- @param table  token
  -- @param string type
  function Parser:assert_not(type)
    if self.token.type == type then
      error('Token not ' .. self.pos .. ' not allowed to be ' .. type)
    end
  end

  -- Token binding precedence table
  local bp = {
    eof               = 0,
    quoted_identifier = 0,
    identifier        = 0,
    rbracket          = 0,
    rparen            = 0,
    comma             = 0,
    rbrace            = 0,
    number            = 0,
    current           = 0,
    expref            = 0,
    pipe              = 1,
    comparator        = 2,
    ['or']            = 5,
    flatten           = 6,
    star              = 20,
    dot               = 40,
    lbrace            = 50,
    filter            = 50,
    lbracket          = 50,
    lparen            = 60
  }

  -- Cached current node used as identity nodes.
  local current_node = {type = 'current'}

  -- Valid tokens after a dot
  local after_dot = {
    identifier        = true,
    quoted_identifier = true,
    lbracket          = true,
    lbrace            = true,
    star              = true
  }

  -- Hash of token handlers
  local parselets = {}

  --- Main expression parsing function.
  local function expr(parser, rbp)
    rbp = rbp or 0
    local left = parselets['nud_' .. parser.token.type](parser)
    while rbp < bp[parser.token.type] do
      left = parselets['led_' .. parser.token.type](parser, left)
    end
    return left
  end

  parselets.nud_identifier = function(parser)
    local result = {type = 'field', value = parser.token.value}
    parser:advance()
    return result
  end

  parselets.nud_quoted_identifier = function(parser)
    local token = parser.token
    parser:advance()
    parser:assert_not('lparen')
    return {type = 'field', value = token.value}
  end

  parselets.nud_current = function(parser)
    parser:advance()
    return {type = 'current'}
  end

  parselets.nud_literal = function(parser)
    local token = parser.token
    parser:advance()
    return {type = 'literal', value = token.value}
  end

  parselets.nud_expref = function(parser)
    parser:advance()
    return {type = 'expref', children = {expr(parser, 2)}}
  end

  function parse_kvp(parser)
    local valid_colon = {colon = true}
    local key = parser.token.value
    parser:advance(valid_colon)
    parser:advance()
    return {type = 'key_value_pair', value = key, children = {expr(parser)}}
  end

  parselets.nud_lbrace = function(parser)
    local valid_keys = {quoted_identifier = true, identifier = true}
    parser:advance(valid_keys)
    local pairs = {}
    repeat
      pairs[#pairs + 1] = parse_kvp(parser)
      if parser.token.type == 'comma' then parser:advance(valid_keys) end
    until parser.token.type == 'rbrace'
    parser:advance()
    return {type = 'multi_select_hash', children = pairs}
  end

  parselets.nud_flatten = function(parser)
    return parselets.led_flatten(parser, current_node)
  end

  parselets.nud_filter = function(parser)
    return parselets.led_filter(parser, current_node)
  end

  local function parse_multi_select_list(parser)
    local nodes = {}
    repeat
      nodes[#nodes + 1] = expr(parser)
      if parser.token.type == 'comma' then
        parser:advance()
        parser:assert_not('rbracket')
      end
    until parser.token.type == 'rbracket'
    parser:advance()
    return {type = 'multi_select_list', children = nodes}
  end

  local function parse_dot(parser, rbp)
    if parser.token.type == 'lbracket' then
      parser:advance()
      return parse_multi_select_list(parser)
    end
    return expr(parser, rbp)
  end

  local function parse_projection(parser, rbp)
    local t = parser.token.type
    if bp[t] < 10 then
      return current_node
    elseif t == 'dot' then
      parser:advance(after_dot)
      return parse_dot(parser, rbp)
    elseif t == 'lbracket' or t == 'filter' then
      return expr(parser, rbp)
    else
      throw(parser, 'Syntax error after projection')
    end
  end

  local function parse_wildcard_object(parser, left)
    parser:advance()
    return {
      type     = 'object_projection',
      children = {left or current_node, parse_projection(parser, bp.star)}
    }
  end

  parselets.nud_star = function(parser)
    return parse_wildcard_object(parser, current_node)
  end

  local function parse_wildcard_array(parser, left)
    parser:advance({rbracket = true})
    parser:advance()
    return {
      type     = 'array_projection',
      children = {left or current_node, parse_projection(parser, bp.star)}
    }
  end

  local function parse_array_index_expr(parser)
    local match_next = {number = true, colon = true, rbracket = true}
    local pos = 1
    local parts = {false, false, false}
    local expected  = match_next

    repeat
      if parser.token.type == 'colon' then
        pos = pos + 1
        expected = match_next
      else
        parts[pos] = parser.token.value
        expected = {colon = true, rbracket = true}
      end
      parser:advance(expected)
    until parser.token.type == 'rbracket'

    -- Consume the closing bracket
    parser:advance()

    -- If no colons were found then this is a simple index extraction.
    if pos == 1 then
      return {type = 'index', value = parts[1]}
    elseif pos > 3 then
      throw(parser, 'Invalid array slice syntax: too many colons')
    else
      -- Sliced array from start(e.g., [2:])
      return {type = 'slice', value = parts}
    end
  end

  parselets.nud_lbracket = function(parser)
    parser:advance()
    local t = parser.token.type
    if t == 'number' or t == 'colon' then
      return parse_array_index_expr(parser)
    elseif t == 'star' and parser:peek() == "rbracket" then
      return parse_wildcard_array(parser)
    end
    return parse_multi_select_list(parser)
  end

  parselets.led_lbracket = function(parser, left)
    local next_types = {number = true, colon = true, star = true}
    parser:advance(next_types)
    local t = parser.token.type
    if t == 'number' or t == 'colon' then
      return {
        type     = 'subexpression',
        children = {left, parse_array_index_expr(parser)}
      }
    end
    return parse_wildcard_array(parser, left)
  end

  parselets.led_flatten = function(parser, left)
    parser:advance()
    return {
      type = 'array_projection',
      children = {
        {type = 'flatten', children = {left}},
        parse_projection(parser, bp.flatten)
      }
    }
  end

  parselets.led_or = function(parser, left)
    parser:advance()
    return {type = 'or', children = {left, expr(parser, bp['or'])}}
  end

  parselets.led_pipe = function(parser, left)
    parser:advance()
    return {type = 'pipe', children = {left, expr(parser, bp.pipe)}}
  end

  parselets.led_lparen = function(parser, left)
    local args = {}
    parser:advance()
    while parser.token.type ~= 'rparen' do
      args[#args + 1] = expr(parser, 0)
      if parser.token.type == 'comma' then parser:advance() end
    end
    parser:advance()
    return {type = 'function', value = left.value, children = args}
  end

  parselets.led_filter = function(parser, left)
    parser:advance()
    local expression = expr(parser)
    if parser.token.type ~= 'rbracket' then
      throw(parser, 'Expected a closing rbracket for the filter')
    end
    parser:advance()
    local rhs = parse_projection(parser, bp.filter)
    return {
      type = 'array_projection',
      children = {
        left or current_node,
        {type = 'condition', children = {expression, rhs}}
      }
    }
  end

  parselets.led_comparator = function(parser, left)
    local token = parser.token
    parser:advance()
    return {
      type     = 'comparator',
      value    = token.value,
      children = {left, expr(parser)}
    }
  end

  parselets.led_dot = function(parser, left)
    parser:advance(after_dot)
    if parser.token.type == 'star' then
      return parse_wildcard_object(parser, left)
    end
    return {
      type     = 'subexpression',
      children = {left, parse_dot(parser, bp.dot)}
    }
  end

  setmetatable(parselets, {
    -- handle the invalid use of nud or led tokens
    __index = function(self, key)
      error("Invalid use of " .. key)
    end
  })

  local function throw(parser, msg)
    msg = 'Syntax error at character ' .. parser.token.pos .. '\n'
      .. parser.expr .. '\n'
      .. string.rep(' ', parser.token.pos - 1) .. '^\n'
      .. msg
    error(msg)
  end

  --- Parses an expression.
  -- @param  string expression Expression to parse into an AST
  -- @treturn table  Returns the parsed AST as a table of table nodes.
  -- @error   Raises an error when an invalid expression is provided.
  function Parser:parse(expression)
    self.expr = expression
    self.tokens = self.lexer:tokenize(expression)
    -- Advance to the first token
    self.pos = 0
    self:advance()
    local ast = expr(self, 0)
    if self.token.type ~= 'eof' then
      throw(self, 'Encountered an unexpected "' .. self.token.type
        .. '" token and did not reach the end of the token stream.')
    end
    return ast
  end

  return Parser
end)()

------------------------------------------
-- Functions
------------------------------------------

local Functions = (function()
  local Functions = {}

  function fn_abs(args)
    validate('abs', args, {{'number'}})
    return math.abs(args[1])
  end

  function fn_avg(args)
    validate('avg', args, {{'array'}})
    if not #args[1] then return nil end
    return fn_sum(args) / #args[1]
  end

  function fn_ceil(args)
    validate('ceil', args, {{'number'}})
    return math.ceil(args[1])
  end

  function fn_contains(args)
    validate('contains', args, {{'string', 'array'}, {'any'}})
    if type(args[1]) == 'table' then
      return Functions.in_table(args[2], args[1])
    end
    return string.find(args[1], args[2]) ~= nil
  end

  function fn_ends_with(args)
    validate('ends_with', args, {{'string'}})
    return args[2] == ''
      or string.sub(args[1], -string.len(args[2])) == args[2]
  end

  function fn_floor(args)
    validate('floor', args, {{'number'}})
    return math.floor(args[1])
  end

  function fn_join(args)
    validate('join', args, {{'array'}, {'string'}})
    local fn = function (carry, item, index)
      if index == 1 then return item end
      return carry .. args[2] .. item
    end
    return typed_reduce('join:0', args[1], {'string'}, fn)
  end

  function fn_keys(args)
    validate('keys', args, {{'object'}})
    local keys = {}
    for k, _ in pairs(args[1]) do keys[#keys + 1] = k end
    return keys
  end

  function fn_length(args)
    validate('length', args, {{'array', 'string'}})
    return #args[1]
  end

  function fn_not_null(args)
    validate_arity('not_null:0', #args, 1)
    for _, i in pairs(args) do
      if i ~= nil then return i end
    end
  end

  function fn_max(args)
    validate('max', args, {{'array'}})
    local fn = function (carry, item, index)
      if index > 1 and carry >= item then return carry end
      return item
    end
    return typed_reduce('max:0', args[1], {'number', 'string'}, fn)
  end

  function fn_max_by(args)
    validate('max_by', args, {{'array'}, {'expression'}})
    local expr = wrap_expr('max_by:1', args[2], {'number', 'string'})
    local fn = function (carry, item, index)
      if index == 1 then return item end
      if expr(carry) >= expr(item) then return carry end
      return item
    end
    return typed_reduce('max_by:1', args[1], {'any'}, fn)
  end

  function fn_min(args)
    validate('min', args, {{'array'}})
    local fn = function (carry, item)
      if index > 1 and carry <= item then return carry end
      return item
    end
    return typed_reduce('min:0', args[1], {'number', 'string'}, fn)
  end

  function fn_min_by(args)
    validate('min_by', args, {{'array'}})
    local expr = wrap_expr('min_by:1', args[2], {'number', 'string'})
    local fn = function (carry, item, index)
      if index == 1 then return item end
      if expr(carry) <= expr(item) then return carry end
      return item
    end
    return typed_reduce('min_by:1', args[1], {'any'}, fn)
  end

  function fn_reverse(args)
    validate('reverse', args, {{'array', 'string'}})
    if type(args[1]) == 'string' then
      return string.reverse(args[1])
    end
    local reversed, items = {}, #args[1]
    for k, v in ipairs(args[1]) do reversed[items + 1 - k] = v end
    return reversed
  end

  function fn_sort(args)
    validate('sort', args, {{'array'}})
    local valid = {'string', 'number'}
    return Functions.stable_sort(args[1], function (a, b)
      validate_seq('sort:0', valid, a, b)
      return sortfn(a, b)
    end)
  end

  function fn_sort_by(args)
    validate('sort_by', args, {{'array'}, {'expression'}})
    local expr, valid = args[2], {'string', 'number'}
    return Functions.stable_sort(args[1], function (a, b)
      local va, vb = expr(a), expr(b)
      validate_seq('sort_by:0', valid, va, vb)
      return sortfn(va, vb)
    end)
  end

  function fn_sum(args)
    validate('sum', args, {{'array'}})
    local fn = function (carry, item, index)
      if index > 1 then return carry + item end
      return item
    end
    return typed_reduce('sum:0', args[1], {'number'}, fn)
  end

  function fn_starts_with(args)
    validate('starts_with', args, {{'array'}})
    return string.sub(args[1], 1, string.len(args[2])) == args[2]
  end

  function fn_type(args)
    validate_arity('type:0', #args, 1)
    return Functions.type(args[1])
  end

  function fn_to_number(args)
    validate_arity('to_number:0', #args, 1)
    return tonumber(args[1])
  end

  function fn_to_string(args)
    validate_arity('to_string:0', #args, 1)
    if type(args[1]) == 'table' then
      local meta = getmetatable(args[1])
      if meta and meta.__tostring then
        return tostring(args[1])
      end
      return json.encode(args[1])
    end
    return tostring(args[1])
  end

  function fn_values(args)
    validate('values', args, {{'array'}})
    local values = {}
    for _, i in pairs(args[1]) do
      values[#values + 1] = i
    end
    return values
  end

  function validate_arity(from, given, expected)
    if given ~= expected then
      error(from .. ' expects ' .. expected .. ' arguments. ' .. given
        .. ' were provided.')
    end
  end

  function type_error(from, msg)
    if not string.match(from, ':') then
      error('Type error: ' .. from .. ' ' .. msg)
    end
    error('Argument ' .. from .. ' ' .. msg)
  end

  function validate(from, args, types)
    validate_arity(from, #args, #types)
    for k, v in pairs(args) do
      if types[k] and #types[k] then
        validate_type(from .. ':' .. k, v, types[k])
      end
    end
  end

  function validate_type(from, value, types)
    if types[1] == 'any'
      or Functions.in_table(Functions.type(value), types)
      or (value == {} and Functions.in_table('array', types))
    then
      return
    end
    local msg = 'must be one of the following types: '
      .. table.concat(types, '|') .. '. ' .. Functions.type(value) .. ' found';
    type_error(from, msg);
  end

  function validate_seq(from, types, a, b)
    local ta, tb = Functions.type(a), Functions.type(b)
    if ta ~= tb then
      type_error(from, 'encountered a type mismatch in sequence: ' .. ta .. ', ' .. tb)
    end
    local match = (#types and types[1] == 'any')
      or Functions.in_table(ta, types)
    if not match then
      type_error(from, 'encountered a type error in sequence. The argument must'
        .. ' be an array of ' .. table.concat(types, '|') .. ' types. Found '
        .. ta .. ', ' .. tb)
    end
  end

  --- Reduces a table to a single value while validating the sequence types
  -- @param string   from  'function:position'
  -- @param table    tbl   Table to reduce
  -- @param table    types Valid types
  -- @param function func  Reduce function
  function typed_reduce(from, tbl, types, func)
    return Functions.reduce(tbl, function (carry, item, index)
      if index > 1 then validate_seq(from, types, carry, item) end
      return func(carry, item, index)
    end)
  end

  --- Returns a composed function that validates the return value
  -- @param string   from  'function:position'
  -- @param function expr  Function to wrap
  -- @param table    types Valid types
  function wrap_expr(from, expr, types)
    from = 'The expression return value of ' .. from
    return function (value)
      value = expr(value)
      validate_type(from, value, types)
      return value
    end
  end

  --- Implements a sort function that returns 0, 1, or -1
  -- @param string|number a Left value
  -- @param string|number b Right value
  -- @return number
  function sortfn(a, b)
    if a == b then return 0 end
    if a < b then return -1 end
    return 1
  end

  --- Check if the search value is in table t
  -- @param mixed search Value to find
  -- @param table t      Table to search
  -- @return bool
  function Functions.in_table(search, t)
    for _, value in pairs(t) do
      if value == search then return true end
    end
    return false
  end

  --- Reduces a table using a callback function
  -- @param table    tbl     Table to reduce
  -- @param function func    Reduce function that accepts (carry, item)
  -- @param mixed    initial Optionally provide an initial carry value.
  function Functions.reduce(tbl, func, initial)
    local carry = initial
    for index, item in pairs(tbl) do
      carry = func(carry, item, index)
    end
    return carry
  end

  --- Determines if the given value is a JMESPath object
  -- @param mixed value
  -- @return bool
  function Functions.is_object(value)
    return #value == 0
  end

  --- Determines if the given value is a JMESPath array
  -- @param mixed value
  -- @return bool
  function Functions.is_array(value)
    return #value > 0
  end

  --- Implements a stable sort using a sort function
  -- @param table    data Data to sort
  -- @param function func Accepts a, b and returns -1, 0, or 1.
  -- @return table
  function Functions.stable_sort(data, func)
    -- Decorate each item by creating an array of [value, index]
    local wrapped, sorted = {}, {}
    for k, v in pairs(data) do wrapped[#wrapped + 1] = {v, k} end
    -- Sort by the sort function and use the index as a tie-breaker
    table.sort(wrapped, function (a, b)
      local result = func(a[1], b[1])
      if result == 0 then
        return a[2] < b[2]
      end
      return result == -1
    end)
    -- Undecorate each item and return the resulting sorted array
    for _, v in pairs(wrapped) do
      sorted[#sorted + 1] = v[1]
    end
    return sorted
  end

  --- Returns the JMESPath type of a Lua variable
  -- @param mixed value
  -- @return string
  function Functions.type(value)
    local t = type(value)
    if t == 'string' then return 'string' end
    if t == 'number' then return 'number' end
    if t == 'float' then return 'float' end
    if t == 'boolean' then return 'boolean' end
    if t == 'function' then return 'expression' end
    if t == 'nil' then return 'null' end
    if t == 'table' then
      if Functions.is_object(value) then return 'object' end
      return 'array'
    end
  end

  function Functions.new(config)
    local fns = {
      abs = fn_abs,
      avg = fn_avg,
      ceil = fn_ceil,
      contains = fn_contains,
      ends_with = fn_ends_with,
      floor = fn_floor,
      keys = fn_keys,
      length = fn_length,
      join = fn_join,
      not_null = fn_not_null,
      max = fn_max,
      max_by = fn_max_by,
      min = fn_min,
      min_by = fn_min_by,
      reverse = fn_reverse,
      sort = fn_sort,
      sort_by = fn_sort_by,
      starts_with = fn_starts_with,
      sum = fn_sum,
      to_number = fn_to_number,
      to_string = fn_to_string,
      type = fn_type,
      values = fn_values
    }
    return setmetatable({}, {
      __index = Functions,
      __call = function(t, fn, args)
        if not fns[fn] then error('Invalid function call: ' .. fn) end
        return fns[fn](args)
      end
    })
  end

  return Functions
end)()

------------------------------------------
-- Interpreter
------------------------------------------

local Interpreter = (function()
  local Interpreter = {}

  function Interpreter.new(config)
    local self = setmetatable({}, {__index = Interpreter})
    if config and config.fn_dispatcher then
      self.fn_dispatcher = config.fn_dispatcher
    else
      self.fn_dispatcher = Functions.new()
    end
    return self
  end

  -- Each visitor that handles a particular node type
  local visitors = {

    field = function(interpreter, node, data)
      if type(data) == 'table' then return data[node.value] end
    end,

    subexpression = function(interpreter, node, data)
      return interpreter:visit(
        node.children[2],
        interpreter:visit(node.children[1], data)
      )
    end,

    index = function(interpreter, node, data)
      if type(data) ~= 'table' then return nil end
      if node.value < 0 then return data[#data + node.value + 1] end
      return data[node.value + 1]
    end,

    object_projection = function(interpreter, node, data)
      local left = interpreter:visit(node.children[1], data)
      -- The left result must be a hash or sequence.
      if type(left) ~= 'table' then return nil end
      -- Empty tables should just return the table.
      if next(left) == nil then return left end
      -- Don't perform an object projection on an array
      if #left > 0 then return nil end
      local collected = {}
      local m = getmetatable(left)
      local order
      -- Determine the key order if possible
      if m and m.__jsonorder then
        order = m.__jsonorder
      else
        order = {}
        for k, _ in pairs(left) do order[#order + 1] = k end
      end
      for _, v in ipairs(order) do
        local value = left[v]
        local result = interpreter:visit(node.children[2], value)
        if result ~= nil then collected[#collected + 1] = result end
      end
      return collected
    end,

    array_projection = function(interpreter, node, data)
      local left = interpreter:visit(node.children[1], data)
      -- The left result must be a hash or sequence.
      if type(left) ~= 'table' then return nil end
      -- Empty tables should just return the table.
      if next(left) == nil then return left end
      -- Don't perform an array on an object
      if #left == 0 then return nil end
      local collected = {}
      for _, v in pairs(left) do
        local result = interpreter:visit(node.children[2], v)
        if result ~= nil then collected[#collected + 1] = result end
      end
      return collected
    end,

    flatten = function(interpreter, node, data)
      local left = interpreter:visit(node.children[1], data)
      -- flatten requires that the left result returns a sequence
      if type(left) ~= 'table' then return nil end
      -- Return if empty because we can't differentiate between array and hash.
      if next(left) == nil then return left end
      -- It is not empty, so ensure that the left result is a sequence table.
      if #left == 0 then return nil end

      local merged = {}
      for _, v in ipairs(left) do
        -- Push everything on that is not a table or is a hash.
        if type(v) ~= 'table' or (next(v) ~= nil and #v == 0) then
          merged[#merged + 1] = v
        elseif #v > 0 then
          -- Merge up sequence tables into the merged result.
          for _, j in ipairs(v) do
            merged[#merged + 1] = j
          end
        end
      end

      return merged
    end,

    literal = function(interpreter, node, data)
      return node.value
    end,

    current = function(interpreter, node, data)
      return data
    end,

    ["or"] = function(interpreter, node, data)
      local result = interpreter:visit(node.children[1], data)
      local t = type(result)
      if not result or result == '' or (t == 'table' and next(result) == nil)
      then
        result = interpreter:visit(node.children[2], data)
      end
      return result
    end,

    pipe = function(interpreter, node, data)
      return interpreter:visit(
        node.children[2],
        interpreter:visit(node.children[1], data)
      )
    end,

    multi_select_list = function(interpreter, node, data)
      if data == nil then return nil end
      local collected = {}
      local n = 0
      for _, v in pairs(node.children) do
        n = n + 1
        collected[n] = interpreter:visit(v, data)
      end
      return collected
    end,

    multi_select_hash = function(interpreter, node, data)
      if data == nil then return nil end
      local collected, order = {}, {}
      for _, v in ipairs(node.children) do
        collected[v.value] = interpreter:visit(v.children[1], data)
        order[#order + 1] = collected[v.value]
      end
      return setmetatable(collected, {__jsonorder = order})
    end,

    comparator = function(interpreter, node, data)
      -- @TODO
    end,

    condition = function(interpreter, node, data)
      if interpreter:visit(node.children[1], data) then
        return interpreter:visit(node.children[2], data)
      end
    end,

    ["function"] = function(interpreter, node, data)
      local args = {}
      for _, i in pairs(node.children) do
        args[#args + 1] = interpreter:visit(i, data)
      end
      return interpreter.fn_dispatcher(node.value, args)
    end,

    expression = function(interpreter, node, data)
      return {node = node, interpreter = interpreter}
    end
  }

  function Interpreter:visit(node, data)
    return visitors[node.type](self, node, data)
  end

  return Interpreter
end)()

local search_cache = {}
local parser = Parser.new()
local interpreter = Interpreter.new()
local parse = function(expression)
  if #search_cache > 1024 then search_cache = {} end
  if not search_cache[expression] then
    search_cache[expression] = parser:parse(expression)
  end
  return search_cache[expression]
end
local default_runtime = function(expression, data)
  return interpreter:visit(parse(expression), data)
end

------------------------------------------
-- Public API
------------------------------------------

return {
  --- Functions module, including useful JMESPath functions
  -- Functions: type, is_object, is_array, stable_sort, reduce, in_table
  Functions = Functions,

  --- Create a JMESPath runtime using the provided configuration hash
  -- @param table Hash of options.
  --              - fn_dispatcher: Function dispatcher function to use with
  --                the interpreter. The dispatcher function accepts a
  --                function name followed by an array of arguments.
  -- @return function Returns a JMESPath expression evaluator
  runtime = function(config)
    if config and config.fn_dispatcher then
      local interpreter = Interpreter.new{config}
      return function (expression, data)
        return interpreter:visit(parse(expression), data)
      end
    end
    return default_runtime
  end,

  --- Creates an AST for the given JMESPath expression
  -- @param string expression JMESPath expression as a string.
  -- @return Returns an AST table
  -- @error  Raises an error if the expression is invalid.
  parse = parse,

  --- Searches the provided data using a JMESPath expression
  -- @param string expression JMESPath expression as a string.
  -- @param         data       Data to search. Can be any primitive or a table.
  -- @return Returns the evaluated result as a table, string,
  --         nil, number, or boolean.
  -- @error  Raises an error if the expression is invalid.
  search = default_runtime
}
