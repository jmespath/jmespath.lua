--[==[
JSON parser based on v2.4 of David Kolf's JSON module for Lua 5.1/5.2

`json.decode (string [, options])`
--------------------------------------------
Decodes a JSON string.

Accepts an optional table of options:

- "null": The object to use for null values. The default is `nil`, but you
  could set it to `json.null` or any other value.

Every array or object that is decoded gets a metatable with the `__jsontype`
field set to either `array` or `object`. Object tables also contain a
`__jsonorder` attribute that is a sequence containing the order of object
keys to allow for insert order map traversal.

`json.null`
-----------

You can use this value for setting explicit `null` values.

---------------------------------------------------------------------

*Copyright (C) 2010-2013 David Heiko Kolf*

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
<!--]==]

-- global dependencies:
local pairs, tostring, tonumber, setmetatable, select =
      pairs, tostring, tonumber, setmetatable, select
local floor = math.floor
local gsub, strsub, strchar, strfind, strlen, strmatch =
      string.gsub, string.sub, string.char,
      string.find, string.len, string.match

local json = { version = "dkjson 2.4" }
json.null = setmetatable({}, {__tojson = function () return "null" end})

local function replace(str, o, n)
  local i, j = strfind (str, o, 1, true)
  if i then
    return strsub(str, 1, i-1) .. n .. strsub(str, j+1, -1)
  else
    return str
  end
end

-- locale independent num2str and str2num functions
local decpoint, numfilter

local function updatedecpoint ()
  decpoint = strmatch(tostring(0.5), "([^05+])")
  -- build a filter that can be used to remove group separators
  numfilter = "[^0-9%-%+eE" .. gsub(decpoint, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "]+"
end

updatedecpoint()

local function str2num (str)
  local num = tonumber(replace(str, ".", decpoint))
  if not num then
    updatedecpoint()
    num = tonumber(replace(str, ".", decpoint))
  end
  return num
end

local function loc (str, where)
  local line, pos, linepos = 1, 1, 0
  while true do
    pos = strfind (str, "\n", pos, true)
    if pos and pos < where then
      line = line + 1
      linepos = pos
      pos = pos + 1
    else
      break
    end
  end
  return "line " .. line .. ", column " .. (where - linepos)
end

local function unterminated (str, what, where)
  return nil, strlen (str) + 1, "unterminated " .. what .. " at " .. loc (str, where)
end

local escapechars = {
  ["\""] = "\"", ["\\"] = "\\", ["/"] = "/", ["b"] = "\b", ["f"] = "\f",
  ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
}

local function unichar (value)
  if value < 0 then
    return nil
  elseif value <= 0x007f then
    return strchar (value)
  elseif value <= 0x07ff then
    return strchar (0xc0 + floor(value/0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0xffff then
    return strchar (0xe0 + floor(value/0x1000),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  elseif value <= 0x10ffff then
    return strchar (0xf0 + floor(value/0x40000),
                    0x80 + (floor(value/0x1000) % 0x40),
                    0x80 + (floor(value/0x40) % 0x40),
                    0x80 + (floor(value) % 0x40))
  else
    return nil
  end
end

local function copytable (tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = v
  end
  return copy
end

local g = require ("lpeg")

if g.version() == "0.11" then
  error "due to a bug in LPeg 0.11, it cannot be used for JSON matching"
end

local pegmatch = g.match
local P, S, R = g.P, g.S, g.R

local function ErrorCall (str, pos, msg, state)
  if not state.msg then
    state.msg = msg .. " at " .. loc (str, pos)
    state.pos = pos
  end
  return false
end

local function Err (msg)
  return g.Cmt (g.Cc (msg) * g.Carg (2), ErrorCall)
end

local Space = (S" \n\r\t" + P"\239\187\191")^0

local PlainChar = 1 - S"\"\\\n\r"
local EscapeSequence = (P"\\" * g.C (S"\"\\/bfnrt" + Err "unsupported escape sequence")) / escapechars
local HexDigit = R("09", "af", "AF")
local function UTF16Surrogate (match, pos, high, low)
  high, low = tonumber (high, 16), tonumber (low, 16)
  if 0xD800 <= high and high <= 0xDBff and 0xDC00 <= low and low <= 0xDFFF then
    return true, unichar ((high - 0xD800)  * 0x400 + (low - 0xDC00) + 0x10000)
  else
    return false
  end
end
local function UTF16BMP (hex)
  return unichar (tonumber (hex, 16))
end
local U16Sequence = (P"\\u" * g.C (HexDigit * HexDigit * HexDigit * HexDigit))
local UnicodeEscape = g.Cmt (U16Sequence * U16Sequence, UTF16Surrogate) + U16Sequence/UTF16BMP
local Char = UnicodeEscape + EscapeSequence + PlainChar
local String = P"\"" * g.Cs (Char ^ 0) * (P"\"" + Err "unterminated string")
local Integer = P"-"^(-1) * (P"0" + (R"19" * R"09"^0))
local Fractal = P"." * R"09"^0
local Exponent = (S"eE") * (S"+-")^(-1) * R"09"^1
local Number = (Integer * Fractal^(-1) * Exponent^(-1))/str2num
local Constant = P"true" * g.Cc (true) + P"false" * g.Cc (false) + P"null" * g.Carg (1)
local SimpleValue = Number + String + Constant
local ArrayContent, ObjectContent

-- The functions parsearray and parseobject parse only a single value/pair
-- at a time and store them directly to avoid hitting the LPeg limits.
local function parsearray (str, pos, nullval, state)
  local obj, cont
  local npos
  local t, nt = {}, 0
  repeat
    obj, cont, npos = pegmatch (ArrayContent, str, pos, nullval, state)
    if not npos then break end
    pos = npos
    nt = nt + 1
    t[nt] = obj
  until cont == 'last'
  return pos, setmetatable (t, copytable(state.arraymeta))
end

local function parseobject (str, pos, nullval, state)
  local obj, key, cont, npos
  local t = {}
  local meta = copytable(state.objectmeta)
  meta.__jsonorder = {}
  repeat
    key, obj, cont, npos = pegmatch (ObjectContent, str, pos, nullval, state)
    if not npos then break end
    pos = npos
    t[key] = obj
    meta.__jsonorder[#meta.__jsonorder + 1] = key
  until cont == 'last'
  return pos, setmetatable (t, meta)
end

local Array = P"[" * g.Cmt (g.Carg(1) * g.Carg(2), parsearray) * Space * (P"]" + Err "']' expected")
local Object = P"{" * g.Cmt (g.Carg(1) * g.Carg(2), parseobject) * Space * (P"}" + Err "'}' expected")
local Value = Space * (Array + Object + SimpleValue)
local ExpectedValue = Value + Space * Err "value expected"
ArrayContent = Value * Space * (P"," * g.Cc'cont' + g.Cc'last') * g.Cp()
local Pair = g.Cg (Space * String * Space * (P":" + Err "colon expected") * ExpectedValue)
ObjectContent = Pair * Space * (P"," * g.Cc'cont' + g.Cc'last') * g.Cp()
local DecodeValue = ExpectedValue * g.Cp ()

function json.decode (str, options)
  local state = {}
  state.objectmeta = {__jsontype = 'object'}
  state.arraymeta = {__jsontype = 'array'}
  local nullval = options and options['null']
  local obj, retpos = pegmatch(DecodeValue, str, pos, nullval, state)
  if state.msg then
    return nil, state.pos, state.msg
  else
    return obj, retpos
  end
end

return json