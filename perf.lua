local json = require "cjson"
local jmespath = require "jmespath"

local data = json.decode('{"j49": {"j48": {"j47": {"j46": {"j45": {"j44": {"j43": {"j42": {"j41": {"j40": {"j39": {"j38": {"j37": {"j36": {"j35": {"j34": {"j33": {"j32": {"j31": {"j30": {"j29": {"j28": {"j27": {"j26": {"j25": {"j24": {"j23": {"j22": {"j21": {"j20": {"j19": {"j18": {"j17": {"j16": {"j15": {"j14": {"j13": {"j12": {"j11": {"j10": {"j9": {"j8": {"j7": {"j6": {"j5": {"j4": {"j3": {"j2": {"j1": {"j0": {}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}')
local search = "j49.j48.j47.j46.j45.j44.j43.j42.j41.j40.j39.j38.j37.j36.j35.j34.j33.j32.j31.j30.j29.j28.j27.j26.j25.j24.j23.j22.j21.j20.j19.j18.j17.j16.j15.j14.j13.j12.j11.j10.j9.j8.j7.j6.j5.j4.j3.j2.j1.j0"

local parser = require("jmespath.parser").new()
local int = require("jmespath.interpreter").new()

local best = 1000

for i = 1, 100000 do
  local s = os.clock()
  int:visit(parser:parse(search), data)
  local t = os.clock() - s
  if t < best then best = t end
end

print(string.format("%.7f", best))
