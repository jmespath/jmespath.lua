
-- Token binding precedence
local bp = {
  ["eof"]               = 0,
  ["quoted_identifier"] = 0,
  ["identifier"]        = 0,
  ["rbracket"]          = 0,
  ["rparen"]            = 0,
  ["comma"]             = 0,
  ["rbrace"]            = 0,
  ["number"]            = 0,
  ["current"]           = 0,
  ["expref"]            = 0,
  ["pipe"]              = 1,
  ["comparator"]        = 2,
  ["or"]                = 5,
  ["flatten"]           = 6,
  ["star"]              = 20,
  ["dot"]               = 40,
  ["lbrace"]            = 50,
  ["filter"]            = 50,
  ["lbracket"]          = 50,
  ["lparen"]            = 60
}

-- Cached current node
local current_node = {["type"]="current"}

-- Parser prototype
local Parser = {}

function Parser:create(config)
	config = config or {}
  if not config.lexer then
    config.lexer = require("lexer")
  end
  self.lexer = config.lexer
  return self
end

function Parser:parse(expression)
	self.tokens = self.lexer(expression)
	local ast = self:_expr(0)

	if self.tokens.cur.type ~= "eof" then
		self:_throw("Encountered an unexpected '" .. self.tokens.cur.type
			.. "' token and did not reach the end of the token stream.")
	end

	return ast
end

function Parser:_expr(rbp)
	rbp = rbp or 0
	left = self["_nud_" .. self.tokens.cur.type](self)
	while rbp < bp[self.tokens.cur.type] do
		local meth = "_led_" .. self.tokens.cur.type
		if not self[meth] then
			self:_throw("Invalid token " .. meth)
		end
		left = self[meth](self, left)
  end
  return left
end

function Parser:_nud_identifier()
  token = self.tokens.cur
  self.tokens:next()
  return {type="field", key=token.value}
end

function Parser:_nud_quoted_identifier()
  token = self.tokens.cur
  self.tokens:next()
  if self.tokens.token.type == "lparen" then
  	self:_throw("Quoted identifiers are not allowed for function names")
  end
  return {["type"]="field", ["key"]=token.value}
end

function Parser:_nud_current()
  self.tokens:next()
  return {["type"]="current"}
end

function Parser:_nud_literal()
	local token = self.tokens.cur
	self.tokens:next()
  return {["type"]="literal", ["value"]=token.value}
end

function Parser:_nud_expref()
	self.tokens:next()
	return {["type"]="expref", ["children"]={self:_expr(2)}}
end

function Parser:_nud_lbrace()
	local valid = {quoted_identifier=true, identifier=true}
	local valid_colon = {colon=true}
	local kvp = {}

	self.tokens:next(valid)

  while true do
  	local key = self.tokens.cur.value
    self.tokens:next(valid_colon)
    self.tokens:next()
    kvp[#kvp + 1] = {
      ["type"]     = "key_value_pair",
      ["key"]      = key,
      ["children"] = {self:_expr()}
    }
  	if self.tokens.cur.type == "comma" then
      self.tokens:next(valid) 
  	end
    if self.tokens.cur.type == 'rbrace' then break end
  end

  self.tokens:next()

  return {["type"]="multi_select_hash", ["children"]=kvp}
end

function Parser:_nud_flatten()
	return self:_led_flatten(current_node)
end

function Parser:_nud_filter()
	return self:_led_filter(current_node)
end

function Parser:_nud_star()
	return self:_parse_wildcard_object(current_node)
end

function Parser:_nud_lbracket()
	self.tokens:next()
	local t = self.tokens.cur.type
  if t == "number" or t == "colon" then
    return self:_parse_array_index_expr()
  end

  -- Try to parse a star, and if it fails, backtrack
  if t == "star" then
  	self.tokens:mark()
  	local result, err = pcall(self:_parse_wildcard_array())
  	if not err then
  		self.tokens:unmark()
  		return result
  	end
  	self.tokens:backtrack()
  end

  return self:_parse_multi_select_list()
end

function Parser:_led_lbracket(left)
	local next_types = {number=true, colon=true, star=true}
	self.tokens:next(next_types)
  local t = self.tokens.cur.type
  if t == "number" or t == "colon" then
      return {
          ["type"]     = "subexpression",
          ["children"] = {left, self:_parse_array_index_expr()}
      }
  end
  return self:_parse_wildcard_array(left)
end

function Parser:_led_flatten(left)
	self.tokens:next()
  return {
    ["type"]="projection",
    ["from"]="array",
    ["children"]={
      {["type"]="flatten", ["children"]={left}},
      self:_parse_projection(bp.flatten)
    }
  }
end

function Parser:_led_or(left)
	self.tokens:next()
	return {["type"]="or", ["children"]={left, self:_expr(bp["or"])}}
end

function Parser:_led_pipe(left)
	self.tokens:next()
	return {["type"]="pipe", ["children"]={left, self:_expr(bp.pipe)}}
end

function Parser:_led_lparen(left)
  local args = {}
  local name = left.key
  self.tokens:next()
  
  while self.tokens.cur.type ~= "rparen" do
  	args[#args + 1] = self:_expr(0)
  	if self.tokens.cur.type == "comma" then
  		self.tokens:next()
  	end
  end
  
  self.tokens:next()
  return {["type"]="function", ["fn"]=name, ["children"]=args}
end

function Parser:_led_filter(left)
  self.tokens:next()
  local expression = self:_expr()
  if self.tokens.cur.type ~= "rbracket" then
  	self:_throw("Expected a closing rbracket for the filter")
  end
        
  self.tokens:next()
  local rhs = self:_parse_projection(bp.filter)

	return {
		["type"]="projection",
		["from"]="array",
		["children"]={
			left or current_node,
			{
			  ["type"]="condition", 
			  ["children"]={expression, rhs}
			}
		}
  }
end

function Parser:_led_comparator(left)
	local token = self.tokens.cur
  self.tokens:next()
  return {
    ["type"]="comparator",
    ["relation"]= token.value,
    ["children"]={left, self:_expr()}
  }
end

function Parser:_led_dot(left)
  self.tokens:next()
	return {
	    type     = "subexpression",
	    children = {left, self:_parse_dot(bp.dot)}
	}
end

function Parser:_parse_projection(rbp)
	local t = self.tokens.cur.type
	if bp[t] < 10 then
		return current_node
	elseif t == "dot" then
		self.tokens:next(after_dot)
		return self:_parse_dot(rbp)
	elseif t == "lbracket" then
		return self:expr(rbp)
	else
		self:_throw("Syntax error after projection")
	end
end

function Parser:_parse_wildcard_object(left)
	self.tokens:next()
  return {
    ["type"] = "projection",
    ["from"] = "object",
    ["children"] = {left or current_node, self:_parse_projection(bp.star)}
  }
end

function Parser:_parse_wildcard_array(left)
  self.tokens:next({rbracket=true})
  self.tokens:next()
  return {
    ["type"] = "projection",
    ["from"] = "array",
    ["children"] = {left or current_node, self:_parse_projection(bp.star)}
  }
end

function Parser:_parse_array_index_expr()
  local match_next = {number=true, colon=true, rbracket=true}

  local pos = 1
  local parts = {false, false, false}
  
  while true do
    if self.tokens.cur.type == "colon" then
      pos = pos + 1
    else
      parts[pos] = self.tokens.cur.value
    end
    self.tokens:next(match_next)
    if self.tokens.cur.type == "rbracket" then break end
  end

  -- Consume the closing bracket
  self.tokens:next()

  if pos == 1 then
    -- No colons were found so this is a simple index extraction
    return {["type"]="index", ["index"]=parts[1]}
  end

  if pos > 3 then
  	self:_throw("Invalid array slice syntax: too many colons")
  end

  -- Sliced array from start (e.g., [2:])
  return {["type"]="slice", ["args"]=parts}
end

function Parser:_parse_multi_select_list()
  local nodes = {}

  while true do
  	nodes[#nodes + 1] = self:_expr()
  	if self.tokens.cur.type == "comma" then
  		self.tokens:next()
  		if self.tokens.cur.type == "rbracket" then
        self:_throw("Expected expression, found rbracket")
      end
  	end
  	if self.tokens.cur.type == "rbracket" then break end
  end

  self.tokens:next()
  return {["type"]="multi_select_list", ["children"]=nodes}
end

function Parser:_parse_dot(rbp)
  if self.tokens.cur.type ~= "lbracket" then
  	return self:_expr(rbp)
  end
  self.tokens:next()
  return self:_parse_multi_select_list()
end

function Parser:_throw(msg)
	error(msg)
end

return Parser
