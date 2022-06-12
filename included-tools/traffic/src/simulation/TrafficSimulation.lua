local TrafficConfig = require('TrafficConfig')
local TrafficDriver = require('TrafficDriver')
local TrafficGrid = require('TrafficGrid')
local TrafficLane = require('TrafficLane')
local TrafficCarFactory = require('TrafficCarFactory')
local RaceCarTracker = require('RaceCarTracker')
local CarsList = require('CarsList')
local TrafficContext = require('TrafficContext')
local TrafficCarFullLOD = require('TrafficCarFullLOD')
local TrafficCarFakeShadow = require('TrafficCarFakeShadow')
local Array                = require('Array')

local sim = ac.getSim()

---@class TrafficSimulation
---@field drivers TrafficDriver[]
---@field carTrackers RaceCarTracker[]
---@field carFactory TrafficCarFactory
local TrafficSimulation = class('TrafficSimulation')

---@param data SerializedData
---@return TrafficSimulation
function TrafficSimulation:initialize(data)
  ac.perfBegin('Traffic initialization')
  TrafficContext.drawCallbacks:clear()
  self.drivers = Array()
  self.carTrackers = Array.range(sim.carsCount, function (i) return RaceCarTracker(i - 1) end)
  self.carFactory = TrafficCarFactory(CarsList)
  self.lastCameraPos = vec3(1/0)
  self.jumpedCounter = 0
  self:rebuildGrid(data)
  ac.perfEnd('Traffic initialization')
end

function TrafficSimulation:dispose()
  self.drivers:clear(TrafficDriver.dispose)
  self.carFactory:dispose()
end

---@param data SerializedData
function TrafficSimulation:rebuildGrid(data)
  -- ac.perfBegin('Rebuild grid')
  self:dispose()
  self.grid = TrafficGrid(data)
  for i = 1, TrafficConfig.driversCount do
    self.drivers:push(TrafficDriver(self.carFactory, self.grid, i))
  end
  TrafficContext.grid = self.grid
  -- ac.perfEnd('Rebuild grid')
end

function TrafficSimulation:update(dt)
  if dt > 0.05 then dt = 0.05 end

  -- ac.perfBegin('actual car trackers')
  for i = 1, self.carTrackers.length do
    self.carTrackers[i]:update()
  end
  -- ac.perfEnd('actual car trackers')

  local jumped = not self.lastCameraPos:closerToThan(sim.cameraPosition, 100)
  if jumped then
    self.jumpedCounter = 2
  end

  if self.jumpedCounter > 0 then
    self.jumpedCounter = self.jumpedCounter - 1
    TrafficCarFactory.setJumped(true)
    TrafficLane.setJumped(true)
    self.grid.canFindRandom = 1/0
    for _ = 1, TrafficConfig.runFramesOnJump do
      for i = 1, self.drivers.length do
        if self.drivers[i].guide == nil then
          self.drivers[i]:update(dt)
        end
      end
    end
    TrafficCarFactory.setJumped(false)
    TrafficLane.setJumped(false)
  end
  self.lastCameraPos:set(sim.cameraPosition)

  TrafficCarFullLOD.resetLimit()
  TrafficCarFakeShadow.resetLimit()

  ac.perfBegin('grid')
  self.grid:update(dt)
  ac.perfEnd('grid')

  ac.perfBegin('drivers')
  local d = 0
  for i = 1, self.drivers.length do
    local driver = self.drivers[i]
    driver:update(dt)
    if driver.guide ~= nil then
      d = d + 1
    end
  end
  ac.debug('Active drivers', d)
  ac.perfEnd('drivers')
  
  ac.perfBegin('cars')
  self.carFactory:update(dt)
  ac.perfEnd('cars')
end

function TrafficSimulation:drawMain()
  for i = 1, #TrafficContext.drawCallbacks do
    TrafficContext.drawCallbacks[i]()
  end
end

---@param layers TrafficDebugLayers
---@param clickToDelete boolean
function TrafficSimulation:draw3D(layers, clickToDelete)
  self.grid:draw3D(layers)

  if clickToDelete then
    for i = 1, #self.drivers do
      self.drivers[i]:mouseRay(layers:mouseRay(), layers:mousePoint())
    end
    -- TrafficContext.trackerBlocking:updateDebug(mousePoint)
  end

  layers:with('Drivers', function ()
    for i = 1, #self.drivers do
      self.drivers[i]:draw3D(layers)
    end
  end)

  layers:with('Cars', function ()
    self.carFactory:draw3D(layers)
  end)

  layers:with('Physics', function ()
    local mousePoint = layers:mousePoint()
    local aroundBlocking = TrafficContext.trackerBlocking:count(mousePoint)
    local aroundPhysics = TrafficContext.trackerPhysics:count(mousePoint)
    local aroundBlocking5 = TrafficContext.trackerBlocking:anyCloserThan(mousePoint, 5)
    local aroundPhysics5 = TrafficContext.trackerPhysics:anyCloserThan(mousePoint, 5)
    render.debugText(mousePoint, 
      string.format('blocking: %d (act5: %s)\nphysics: %d (act5: %s)',
        aroundBlocking, aroundBlocking5 and 'yes' or 'no',
        aroundPhysics, aroundPhysics5 and 'yes' or 'no'),
      rgbm(3,3,3,1), 0.8, render.FontAlign.Left)

    local cx = math.floor(mousePoint.x / 15) * 15
    local cz = math.floor(mousePoint.z / 15) * 15
    render.debugLine(vec3(cx, mousePoint.y, mousePoint.z - 50), vec3(cx, mousePoint.y, mousePoint.z + 50))
    render.debugLine(vec3(cx + 15, mousePoint.y, mousePoint.z - 50), vec3(cx + 15, mousePoint.y, mousePoint.z + 50))
    render.debugLine(vec3(mousePoint.x - 50, mousePoint.y, cz), vec3(mousePoint.x + 50, mousePoint.y, cz))
    render.debugLine(vec3(mousePoint.x - 50, mousePoint.y, cz + 15), vec3(mousePoint.x + 50, mousePoint.y, cz + 15))
  end)
end

return class.emmy(TrafficSimulation, TrafficSimulation.initialize)
