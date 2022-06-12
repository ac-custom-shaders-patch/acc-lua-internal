local TrafficGraph = require('TrafficGraph')
local TrafficLane = require('TrafficLane')
local TrafficArea = require('TrafficArea')
local TrafficIntersection = require('TrafficIntersection')
local TrafficGuide = require('TrafficGuide')
local TrafficPath = require('TrafficPath')
local Array = require('Array')

---@class TrafficGrid
---@field graph TrafficGraph
---@field lanes TrafficLane[]
---@field intersections TrafficIntersection[]
local TrafficGrid = class('TrafficGrid')

---@param data SerializedData
---@return TrafficGrid
function TrafficGrid:initialize(data)
  if data.lanes == nil then error('data.lanes is not set') end

  -- ac.perfBegin('Rebuild grid: lanes')
  self.lanes = Array(data.lanes, TrafficLane):filter(function (p) return p.size > 0 end)
  self.lanesMap = self.lanes:reduce({}, function (t, l) t[l.id] = l return t end)
  -- ac.perfEnd('Rebuild grid: lanes')
  -- self.lanes = table.map({ lanes[4] }, TrafficLane)
  -- self.lanes = table.map({ lanes[5] }, TrafficLane)

  -- ac.perfBegin('Rebuild grid: intersections')
  self.intersections = Array(data.intersections, TrafficIntersection)
  -- ac.perfEnd('Rebuild grid: intersections')

  self.areas = Array(data.areas, TrafficArea)
  self.areas:forEach(function (area)
    self.lanes:forEach(function (lane) area:process(lane) end)
  end)

  -- ac.perfBegin('Rebuild grid: finalization')
  self.graph = TrafficGraph(self.lanes, self.intersections)
  -- ac.perfEnd('Rebuild grid: finalization')

  self.canFindRandom = 0
end

---@return TrafficLane
function TrafficGrid:getLaneByID(id)
  return self.lanesMap[id]
end

function TrafficGrid:randomPath(driver)
  -- if true then 
  --   local p = TrafficPath.createFromPoints(self, table.random({
  --     {80,66,29,68,82},
  --     {81,67,29,68,82},
  --   }))
  --   if p == nil then return nil end
  --   return TrafficGuide(p, driver)
  -- end

  local r = self.canFindRandom
  if r == 0 then return end
  self.canFindRandom = r - 1

  local wandering = TrafficPath.tryCreateWandering(self)
  if wandering ~= nil then return TrafficGuide(wandering, driver) end

  -- local path = TrafficPath.tryCreateRandom(self)
  -- return path and TrafficGuide(path, driver)
end

function TrafficGrid:update(dt)
  self.canFindRandom = 100
  local cameraPosition = ac.getCameraPosition()
  for i = 1, #self.intersections do
    self.intersections[i]:update(cameraPosition, dt)
  end
end

function TrafficGrid:draw3D(layers)
  layers:with('Lanes', true, function ()
    for i = 1, #self.lanes do
      self.lanes[i]:draw3D(layers)
    end
  end)

  layers:with('Intersections', function ()
    for i = 1, #self.intersections do
      self.intersections[i]:draw3D(layers)
    end
  end)

  layers:with('Graph', function ()
    self.graph:draw3D(layers)
  end)
end

return class.emmy(TrafficGrid, TrafficGrid.initialize)