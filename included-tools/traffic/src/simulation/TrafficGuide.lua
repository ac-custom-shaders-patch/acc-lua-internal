local ManeuverBase = require('ManeuverBase')
local TrafficContext = require('TrafficContext')
local LaneChangeManeuver = require('LaneChangeManeuver')
local TrafficConfig = require('TrafficConfig')
local DistanceTags = require('DistanceTags')

---@class TrafficGuide
---@field path TrafficPath
---@field driver TrafficDriver
---@field _curCursor LaneCursor
---@field _curManeuver ManeuverBase
---@field _meta EdgeMeta
local TrafficGuide = class('TrafficGuide', class.NoInitialize)

---@param path TrafficPath
---@param driver TrafficDriver
---@return TrafficGuide
function TrafficGuide.allocate(path, driver)
  local nextLane, nextLanePos = path:next()
  if nextLane == nil then error('Invalid state of the path') end

  local cursor = nextLane:startCursor(driver, nextLanePos)
  return {
    path = path,
    driver = driver,
    maneuvering = ManeuverBase.ManeuverNone,
    _curCursor = cursor,
    _curManeuver = nil,
    _nextLane = nil,
    _nextLanePos = 0,
    _swapTimer = 0
  }
end

-- Full detach, destroying all lane cursors
---@param reason string|nil|boolean @False if it’s an expected detachment which does not require to be checked if it happened too close to camera
function TrafficGuide:detach(reason)
  if reason ~= false and self.driver:getPosRef():closerToThan(ac.getSim().cameraPosition, 200) then
    if not reason then reason = '?' end
    ac.warn('Early detachment nearby: reason='..tostring(reason)..', lane='..(self._curCursor and self._curCursor.lane.name or '?'))
    DebugShapes['Early detachment ('..(self._curCursor and self._curCursor.lane.name or '?')..')'] = self.driver:getPosRef():clone()
  end
  if self._curManeuver ~= nil then self._curManeuver:detach() end
  if self._curCursor ~= nil then self._curCursor:detach() end
  return true
end

local _tmpVec = vec3()

-- Advancing along path (returns true if path is finished and driver has arrived to their destination point)
function TrafficGuide:advance(speedKmh, dt)
  local car = self:getDriver():getCar()

  if TrafficConfig.debugSpawnAround then
    if car and car:distanceToCameraSquared() > 400*400 then return self:detach('Too far') end
  elseif car and car:distanceToCameraSquared() > (car:crashed()
      and TrafficConfig.despawnCrashedDistance * TrafficConfig.despawnCrashedDistance 
      or TrafficConfig.despawnDistance * TrafficConfig.despawnDistance) then
    return self:detach('Too far')
  end

  -- First, as we drive towards an intersection, let’s find it if nothing is set yet
  local _curCursor = self._curCursor
  if _curCursor ~= nil then

    -- if _curCursor.lane.name == 'Lane #8' then
    --   return self:detach() -- TODO
    -- end

    if _curCursor:advance(speedKmh, dt) then
      _curCursor = nil
      self._curCursor = nil
      if self._curManeuver == nil then
        return self:detach('Lane is ended')
      else
        self._curManeuver:ensureActive()
      end
    else
      self._meta = _curCursor.edgeMeta
    end

    -- Calculate distance to it
    local distanceToNextLink = self._meta.distanceToNextLink
    -- distanceToNextLink = 1e9 -- TODO

    -- If nearby, let’s engage with it
    if distanceToNextLink > 0 and distanceToNextLink < 24 and self._curManeuver == nil then
      -- self._nextLane, self._nextLanePos = self.path:next(self._meta.dir)
      self._nextLane, self._nextLanePos = self.path:next(self.driver:getDirRef() or self._meta.dir)
      if self._nextLane == nil then
        return self:detach('No lane to use after maneuver')
      end

      local nextLink = self._meta.nextLink
      self._curManeuver = nextLink.intersection:engage(self, _curCursor.lane, nextLink.from, self._nextLane, self._nextLanePos)
    end
  end

  -- If engaged, let’s check if we can proceed
  if self._curManeuver ~= nil then
    if self._curManeuver:advance(speedKmh, dt) then
      if _curCursor ~= nil then
        _curCursor:detach()
        _curCursor = nil
      end

      if self._nextCursor ~= nil then
        -- some maneuvers can end up calling :adoptCurrentCursor() so next cursor would already be set
        _curCursor = self._nextCursor
        self._nextCursor = nil
        self._curCursor = _curCursor
        self.path:changeCurrentTo(_curCursor.lane, _curCursor.distance)
        if _curCursor.lane == nil then error('Invalid state: adopted cursor is detached') end
      elseif self._nextLane == nil then
        return self:detach()
      else
        self._curManeuver:calculateCurrentPosInto(_tmpVec)
        _curCursor = self._nextLane:startCursor(self.driver, self._nextLanePos, _tmpVec)
        self._curCursor = _curCursor
      end
  
      self._curManeuver = nil
      self.maneuvering = ManeuverBase.ManeuverNone
      -- self.driver.pauseFor = 5e9
      
      self._swapTimer = -10
    elseif _curCursor ~= nil and self._curManeuver:shouldDetachFromLane() then
      _curCursor:detach()
      self._curCursor = nil
    end
  elseif speedKmh < 1 and self._meta.distanceToNextLink > 40 then
    local _swapTimer = self._swapTimer + dt
    if _swapTimer > 1 then
      _swapTimer = 0
      self:_tryToChangeLane()
    end
    self._swapTimer = _swapTimer
  else
    self._swapTimer = 0
  end

  return false
end

function TrafficGuide:_tryToChangeLane()
  local path = self.path
  if not path:canChange() or not self.driver.car or not self._curCursor or math.random() < 0.3 then return end

  local d, n = self:distanceToNextCar()
  if n and self.driver.car:freeDistanceTo(n, self.driver.car._transform.side) < 2 then return end

  local newLane = LaneChangeManeuver.findAlternativeLane(self.driver.car, self._curCursor.lane, self._meta)
  if newLane ~= nil then
    self._curManeuver = LaneChangeManeuver.tryCreate(self, newLane, self._meta)
    self.driver.car.stationaryFor = 0
  end
end

---@param car1 CarBase
---@param car2 CarBase
local function checkBlocking(car1, car2)
  return car2:freeDistanceTo(car1)
end

local tmpVec = vec3()

---@return number, CarBase|nil, DistanceTag
function TrafficGuide:distanceToNextCar()
  -- if self.index == 2 then return 0, nil end
  local rd, rc, rt

  local maneuver = self._curManeuver
  if maneuver ~= nil and maneuver:handlesDistanceToNext() then
    rd, rc, rt = maneuver:distanceToNextCar()
  elseif self._curCursor == nil then
    rd, rc, rt = 0, nil, DistanceTags.ErrorCursorless
  else
    rd, rc, rt = self._curCursor:distanceToNextCar()
    if maneuver ~= nil then
      local md, mc, mt = maneuver:distanceToNextCar()
      if md < rd then
        rd, rc, rt = md, mc, mt
      end
    end
  end

  if maneuver == nil or not maneuver:handlesDistanceToBlocking() then
    local ownCar = self.driver:getCar()
    if ownCar == nil then
      return 0, nil, DistanceTags.ErrorNoCar
    end
    local bd, bc = TrafficContext.trackerBlocking:findNearest(self.driver.pos, checkBlocking, ownCar)
    if bc ~= nil and bc:getDirRef():dot(self.driver:getDirRef()) < 0.5 
        and tmpVec:set(bc:getPosRef()):sub(self.driver:getPosRef()):normalize():dot(self.driver:getDirRef()) > 0.5 then
      bd = bd - 4
    end
    if bd < rd then
      return bd, bc, DistanceTags.Blocking
    end
  end

  return rd, rc, rt
end

function TrafficGuide:canChange()
  return self.path:canChange()
end

---@param newLane TrafficLane
---@param newLanePos number
function TrafficGuide:changeNextTo(newLane, newLanePos)
  self.path:changeNextTo(newLane, newLanePos)
  self._nextLane = newLane
  self._nextLanePos = newLanePos
end

---@param newCursor LaneCursor
function TrafficGuide:adoptCurrentCursor(newCursor)
  if self._nextCursor ~= nil then
    self._nextCursor:detach()
  end
  self._nextCursor = newCursor
end

function TrafficGuide:getDistance()
  return self._curCursor.distance
end

function TrafficGuide:getDriver()
  return self.driver
end

---@return LaneCursor
function TrafficGuide:stealCurrentLaneCursor()
  local r = self._curCursor
  self._curCursor = nil
  return r
end

function TrafficGuide:calculateCurrentPosInto(v, estimate)
  local maneuver = self._curManeuver
  if not maneuver and not self._curCursor then error('Cursorless guide') end
  if maneuver and maneuver:calculateCurrentPosInto(v, estimate) then
    self.maneuvering = maneuver:getManeuverType()
    return v
  end
  return self._curCursor:calculateCurrentPosInto(v, estimate)
end

function TrafficGuide:getMeta()
  return self._meta
end

return class.emmy(TrafficGuide, TrafficGuide.allocate)
