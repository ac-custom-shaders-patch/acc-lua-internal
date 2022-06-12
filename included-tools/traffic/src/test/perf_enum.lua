local Array = require "Array"
local generic_utils = require "src/generic_utils"

local Enum = {
  Key1 = 1,
  Key2 = 2,
  Key3 = 3,
  Key4 = 4
}

-- ffi.cdef[[
--   struct whatever {
--     static const int Key1 = 1;
--     static const int Key2 = 2;
--     static const int Key3 = 3;
--     static const int Key4 = 4;
--   };
-- ]]
-- local Enum = ffi.new("struct whatever")

return function ()
  collectgarbage()
  math.randomseed(0)
  ac.perfBegin(0)
  local t = 0
  for i = 1, 1000000 do
    t = t + Enum.Key2
  end  
  ac.debug('t', t)
  ac.perfEnd(0)
  generic_utils.runGC()
end
