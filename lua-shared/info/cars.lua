--[[
  Some helping utilities for dealing with car information. Examples:

  • Check if a car is a drifting car:

    local carsInfo = require('shared/info/cars')
    carsInfo.isDriftCar(0)
]]

-- Actual library:
local carsInfo = {}

---Checks if a car is a drift car (based on its name, ID or tags).
---@param carIndex integer @0-based car index.
---@return boolean
function carsInfo.isDriftCar(carIndex)
  return ac.getCarID(carIndex):regfind('drift', nil, true) ~= nil
    or ac.getCarName(carIndex):regfind('drift', nil, true) ~= nil
    or table.some(ac.getCarTags(carIndex) or {}, function (tag) return tag:regfind('drift', nil, true) end)
end

return carsInfo