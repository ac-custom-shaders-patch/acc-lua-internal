local TrafficContext = require('TrafficContext')
local CarBase = require('CarBase')

---@class RaceCarTracker : CarBase
local RaceCarTracker = class('RaceCarTracker', CarBase)

function RaceCarTracker:__tostring()
  return string.format('<AC car #%d>', self.car.index)
end

---@param index integer
---@return RaceCarTracker
function RaceCarTracker:initialize(index)
  self.car = ac.getCar(index)
  self.trackerPhysics = TrafficContext.trackerPhysics:track(self)
  self.trackerBlocking = TrafficContext.trackerBlocking:track(self)
  CarBase.initialize(self, self.car.transform, self.car.aabbSize.z / 2, self.car.aabbSize.x / 2)
end

function RaceCarTracker:update()
  local pos = self.car.pos
  -- if ui.hotkeyCtrl() then pos:set(892.48, -1079.05, 1107.26) else pos:set(887.39, -1079.05, 1106.58) end
  -- self.car.transform.position:set(pos)
  -- local pos = vec3(885.27, -1079.05, 1098.78)
  -- DebugShapes.tracker = pos:clone()
  self.trackerPhysics:update(pos)
  self.trackerBlocking:update(pos)
end

function RaceCarTracker:getSpeedKmh()
  return self.car.speedKmh
end

function RaceCarTracker:getDistanceToNext()
  return 1
end

function RaceCarTracker:setPauseFor(time)
  ac.log(string.format('Please stay still for %.1f m', time / 60))
end

return class.emmy(RaceCarTracker, RaceCarTracker.initialize)