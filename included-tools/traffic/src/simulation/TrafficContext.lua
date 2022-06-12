local Array = require('Array')
local MovingTracker = require('MovingTracker')

local TrafficContext = {
  carsRoot = ac.findNodes('carsRoot:yes'),
  trackerBlocking = MovingTracker(15),
  trackerPhysics = MovingTracker(10),
  lanesSpace = ac.HashSpace(15),

  ---@type TrafficGrid
  grid = nil,

  ---@type function[]
  drawCallbacks = Array()
}

return TrafficContext