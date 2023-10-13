local TrafficConfig = require('TrafficConfig')
local CarBase = require('CarBase')
local DistanceTags = require('DistanceTags')
local ManeuverBase = require('ManeuverBase')

local sim = ac.getSim()

local _mrandom = math.random
local _mmax = math.max
local _mmin = math.min
local _initPos = vec3()

---@class TrafficDriver
---@field guide TrafficGuide
---@field car TrafficCar
---@field carFactory TrafficCarFactory
---@field grid TrafficGrid
---@field pos any
---@field pauseFor number
---@field speedy number
---@field index integer
---@field dimensions CarDefinitionDimensions
---@field _optimalBaseMargin number
---@field _distanceTag DistanceTag
local TrafficDriver = class('TrafficDriver', class.NoInitialize)

---@param carFactory TrafficCarFactory
---@param grid TrafficGrid
---@param index integer
---@return TrafficDriver
function TrafficDriver.allocate(carFactory, grid, index)
  return {
    carFactory = carFactory,
    grid = grid,
    index = index,
    speedKmh = TrafficConfig.startingSpeed,
    pauseFor = 0,
    speedy = _mrandom(),
    maxSpeed = math.huge,
    dimensions = { front = 0.5, rear = 4 },
    _distanceToNext = 0,
    _mouseHovered = false,

    pos = vec3(),
    _awarenessSleep = 0,
    _farSkip = 0,
    -- _optimalBaseMargin = _mrandom() > 0.9 and 2.5 + _mrandom() or 1.4 + _mrandom() * 0.4,
    -- _optimalBaseMargin = 1 + _mrandom() * 0.4,
    _optimalBaseMargin = _mrandom() > 0.9 and 3.5 + _mrandom() or 2 + _mrandom() * 0.4,
  }
end

function TrafficDriver:dispose() end

local function _driverUpdateSpeed(self, dt)
  local ts = self._targetSpeed
  local cs = self.speedKmh

  local mts = ts > 0 and ts or 0
  local sds = mts - cs

  local lag
  if sds > 0.01 then
    lag = 0.99
  elseif sds > -0.01 then
    return
  elseif ts < 0 then
    local ta = ts * _mmin(cs * 0.1, 1)
    ta = ta * ta
    ta = ta * ta
    lag = 0.94 - 0.1 * ta
  else
    lag = 0.94 + 0.04 * _mmin(ts * 0.03, 1)
  end

  self.speedKmh = cs + (mts - cs) * _mmin((1 - lag) * dt * 60, 1)
  -- self.speedKmh = mts
end

function TrafficDriver:update(dt)
  -- ac.perfFrameBegin(2010)
  if self.car ~= nil and self.car:crashed() then
    if self.guide ~= nil and self.guide:detach(false) then
      self.guide = nil
    end
    self.speedKmh = 0
    return
  end
  -- ac.perfFrameEnd(2010)

  -- if self.car ~= nil and self.car:distanceToCameraSquared() > 300^2 and _mrandom() > 0.99 then
  --   self.pauseFor = 3
  -- end

  local speedKmh = self.speedKmh
  local movingAtLeastABit = speedKmh > 0.01

  -- Lower refresh rate for cars further away
  -- ac.perfFrameBegin(2020)
  local distanceSquared = self.pos:distanceSquared(sim.cameraPosition, 400)
  local farAway = distanceSquared > 100^2 and (distanceSquared > 250^2 or self.guide == nil or not self.guide.maneuvering == ManeuverBase.ManeuverNone or speedKmh < 1)
  if farAway then
    if self._farSkip > 0 then
      self._farSkip = self._farSkip - 1
      if self.car ~= nil then self.car:extrapolateMovement(speedKmh / 3.6 * dt) end
      return
    else
      self._farSkip = distanceSquared > 400^2 and 4 or 1
      dt = dt * (self._farSkip + 1)
    end
  end
  -- ac.perfFrameEnd(2020)

  -- Advancing along current guide, dropping guide if finished
  -- ac.perfFrameBegin(2030)
  if self.guide ~= nil and self.guide:advance(speedKmh, dt) then
    self.guide = nil
  end
  -- ac.perfFrameEnd(2030)

  -- If guide is dropped (or still missing, release car, exit, but first try and get a new guide for the next frame)
  -- ac.perfFrameBegin(2040)
  if self.guide == nil then
    if self.car ~= nil then
      -- self.car:setDebugValue(rgb(1, 0, 1))
      self.carFactory:release(self.car)
      self.car = nil
    end
    self.guide = self.grid:randomPath(self)
    return
  end

  -- If guide is ready but car is not, let’s try and find one
  if self.car == nil then
    self.car = self.carFactory:get(self)
    if self.car ~= nil then
      self.dimensions = self.car.definition.dimensions
      self.maxSpeed = self.car.definition.maxSpeed

      self.guide:calculateCurrentPosInto(_initPos, false)
      if self.guide:advance(1, 0.1) then -- about 3 cm
        self.guide = nil
        return
      end
      
      self.guide:calculateCurrentPosInto(self.pos, false)
      self.car:initializePos(_initPos, self.pos)
    end
  end
  -- ac.perfFrameEnd(2040)

  -- Update car position
  -- ac.perfFrameBegin(2060)
  if movingAtLeastABit then
    self.guide:calculateCurrentPosInto(self.pos, false)
  end
  if self.car ~= nil then
    -- local r = #vec2(-44.55, -255.61)
    -- if self._dbgPosRad == nil then
    --   local an = (ac.getCar(0).pos * vec3(1, 0, 1)):normalize()
    --   self._dbgPosRad = math.atan2(an.z, an.x)
    -- end
    -- self._dbgPosRad = self._dbgPosRad + 20 * dt / r
    -- self.pos:set(math.cos(self._dbgPosRad) * r, -1, math.sin(self._dbgPosRad) * r)


    self.car:setPos(self.pos, speedKmh)
  end

  -- ac.perfFrameEnd(2060)

  -- Stopping
  if self.pauseFor > 0 then
    self.pauseFor = self.pauseFor - dt
  end

  -- ac.perfFrameBegin(2080)
  if self._awarenessSleep <= 0 then
    -- ac.perfFrameBegin(2081)
    self:updateAwareness()
    -- ac.perfFrameEnd(2081)

    -- ac.perfFrameBegin(2082)
    self:updateTargetSpeed()
    -- ac.perfFrameEnd(2082)

    -- ac.perfFrameBegin(2084)
    if not farAway then
      self:updateCar()
    end
    -- ac.perfFrameEnd(2084)
  else
    self._awarenessSleep = self._awarenessSleep - dt
  end
  -- ac.perfFrameEnd(2080)
  
  -- ac.perfFrameBegin(2090)
  if movingAtLeastABit or self._targetSpeed > 0.5 then
    _driverUpdateSpeed(self, dt)
  elseif speedKmh > 0 then
    self.speedKmh = 0
  end
  -- self.speedKmh = 0
  -- ac.perfFrameEnd(2090)
end

function TrafficDriver:getSpeedKmh()
  return self.speedKmh
end

function TrafficDriver:getDistanceToNext()
  return self._distanceToNext
end

function TrafficDriver:setPauseFor(time)
  self.pauseFor = time
end

function TrafficDriver:updateTargetSpeed()
  local meta = self.guide:getMeta()
  local targetSpeed = self.pauseFor > 0 and 0 or _mmin(self.maxSpeed, meta.speedLimit * (0.6 + 0.4 * self.speedy))
  local car = self.car

  local optimalMargin
  local maneuverType = self.guide.maneuvering
  if maneuverType == ManeuverBase.ManeuverNone then
    optimalMargin = self._nextCar ~= nil and self._optimalBaseMargin or 0
  elseif maneuverType == ManeuverBase.ManeuverRegular then
    optimalMargin = 1.2
  else
    optimalMargin = 0.4
  end

  optimalMargin = optimalMargin + self.speedKmh * 0.1
  -- if car.stationaryFor > 2 then optimalMargin = 0.4 end
  self._optimalMargin = optimalMargin

  local dtn = self._distanceToNext
  targetSpeed = math.min(targetSpeed, _mmax(dtn * 2, 12))

  local spaceLeft = dtn - optimalMargin
  if spaceLeft < optimalMargin then
    if spaceLeft < 0.3 then
      targetSpeed = -math.lerpInvSat(spaceLeft, 0.2, -0.8)
    else
      targetSpeed = self._nextCar == nil and 10 or _mmax(10, self._nextCar:getSpeedKmh() * 0.98)
    end

    if car ~= nil and self._nextCar ~= nil and car.stationaryFor > 1 and car.flashHighBeams == 0
        and self._nextCar:getDistanceToNext() > 40 and _mrandom() > 0.95 then
      car.flashHighBeams = _mrandom(1, 3)
    end
  end

  if car ~= nil then
    targetSpeed = targetSpeed * math.lerp(1, 0.3, math.saturateN(math.abs(self.car.turn)))
    car._horizontalOffsetTarget = car._horizontalOffsetBase * meta.spreadMult
  end

  self._targetSpeed = targetSpeed
end

function TrafficDriver:updateAwareness(dt)
  self._distanceToNext, self._nextCar, self._distanceTag = self.guide:distanceToNextCar()
  if self._distanceTag == nil then error('DistanceTag is required') end
  if self._distanceToNext < 2 and self._distanceTag == DistanceTags.IntersectionMergingCarInFront then self.pauseFor = _mmax(_mrandom() * 3 - 1, 0) end
  if self._nextCar ~= nil and not CarBase.isInstanceOf(self._nextCar) then error('Wrong type: '..tostring(self._nextCar)) end
  self._distanceToNext = self._distanceToNext - self.dimensions.front
  self._awarenessSleep = self.speedKmh < 0.1 and 0.5 or self.guide.maneuvering and 0.1 or math.clampN((self._distanceToNext / (self.speedKmh / 3.6)) * 0.2, 0.1, 0.3)
end

function TrafficDriver:updateCar()
  if self.car ~= nil then
    self.car.headlightsActive = sim.timeHours < 10 or sim.timeHours > 19
  end
end

---@return number
function TrafficDriver:distanceBetweenCarAndPoint(point)
  return self.car and self.car:distanceBetweenCarAndPoint(point) or self.pos:distance(point)
end

---@return TrafficCar|nil
function TrafficDriver:getCar()
  return self.car
end

---@return vec3
function TrafficDriver:getPosRef()
  return self.pos
end

---@return vec3|nil
function TrafficDriver:getDirRef()
  if self.car ~= nil then
    return self.car:getDirRef()
  end
  return nil
end

function TrafficDriver:mouseRay(ray, mousePoint)
  if self.car == nil then return end

  local carPos, carDir = self.car:getPosRef(), self.car:getDirRef()
  local hovered = ray:sphere(carPos, 2) > 0 or ray:sphere(carPos - carDir * 2, 2) > 0
  if hovered ~= self._mouseHovered then
    self.car:setDebugValue(hovered and rgb(1, 1, 1) or rgb())
    self._mouseHovered = hovered
  end
  if hovered and ui.mouseClicked() then
    if self.guide ~= nil then
      self.guide:detach(false)
      self.guide = nil
    end
    self.carFactory:release(self.car)
    self.car = nil
  end

  -- if mousePoint:distance(self.pos) < 10 then
  --   render.debugText(self.car.pos, string.format('%.2f m', self:distanceBetweenCarAndPoint(mousePoint)), rgbm(3, 3, 3, 1), 2.5)
  -- end
end

function TrafficDriver:draw3D(layers)
  if self.car == nil or not self.pos:closerToThan(sim.cameraPosition, 60) then return end

  local s = nil
  local function add(format, ...)
    if s == nil then
      s = string.format(format, ...)
    else
      s = s .. '\n' .. string.format(format, ...)
    end
  end

  layers:with('Name', function () 
    add('%s, %s', tostring(self), tostring(self.car)) 
  end)
  layers:with('Distance to next', function () 
    add('DTN: %.2f m (%s, next car=%s, real d.=%.2f m, opt.m.: %.2f m)', self._distanceToNext, self._distanceTag.name, self._nextCar, 
      self.car and self._nextCar and self.car:freeDistanceTo(self._nextCar, self.car:getDirRef()) or -1, self._optimalMargin) 
  end)
  layers:with('Waiting', function () 
    add('Waiting for: %.2f s', self.pauseFor) 
  end)
  layers:with('Speed', function () 
    add('Spd: %.2f km/h (tsp: %.2f km/h, turn=%s)', self.car:getSpeedKmh(), self._targetSpeed, self.car and self.car.turn or '?') 
  end)
  layers:with('Next intersection', function () 
    add('Int: %s, dst: %.1f m', self.guide._meta.nextLink and self.guide._meta.nextLink.intersection or "N/A", self.guide._meta.distanceToNextLink) 
  end)
  layers:with('Intersection status', function ()
    add('Ien: maneuver type=%d, maneuver=%s, cur=%s', self.guide.maneuvering, self.guide._curManeuver, self.guide._curCursor) 
  end)
  layers:with('Position on lane', function () 
    add('Pol: %s', self.guide._curCursor and self.guide._curCursor.distance or 'N/A')
  end)
  layers:with('Distance from mouse to car', function () 
    add('Dst: %f', self:distanceBetweenCarAndPoint(layers:mousePoint()))
  end)

  if s ~= nil then
    render.debugText(self.car._pos, s, rgbm(3, 3, 3, 1), 0.8, render.FontAlign.Left)
  end
end

return class.emmy(TrafficDriver, TrafficDriver.allocate)