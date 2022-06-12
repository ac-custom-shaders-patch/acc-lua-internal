local Array = require "Array"
local generic_utils = require "src/generic_utils"

local v = Array()
for i = 1, 1000 do
  v:push({ value = i + math.random() * 0.5 })
end

-- local v = {}
-- for i = 1, 1000 do
--   table.insert(v, { value = i + math.random() * 0.5 })
-- end

return function ()
  collectgarbage()
  math.randomseed(0)
  ac.perfBegin(0)
  local t = 0
  local f = function (j, _, k) return j > k end
  for i = 1, 10000 do
    local k = math.random() * 100
    local r = v:findLeftOfIndex(f, k)
    t = t + r
  end  
  ac.debug('t', t)
  ac.perfEnd(0)
  generic_utils.runGC()
end

-- return function ()
--   collectgarbage()
--   math.randomseed(0)
--   ac.perfBegin(0)
--   local t = 0
--   for i = 1, 1000000 do
--     t = t + v[i % 1000 + 1].value
--   end  
--   ac.debug('t', t)
--   ac.perfEnd(0)
--   generic_utils.runGC()
-- end

--[[

Conclusion: even though capturing variables does produce garbage, but passing variadic arguments
to a callback is quite a lot slower (2.1 ms vs 4.5 ms)

]]