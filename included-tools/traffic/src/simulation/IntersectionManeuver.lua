local TrafficConfig = require('TrafficConfig')
local MathUtils  = require('MathUtils')
local CachingCurve = require('CachingCurve')
local ManeuverBase = require('ManeuverBase')
local IntersectionLink = require('IntersectionLink')
local DistanceTags = require('DistanceTags')

---@param item IntersectionManeuver
local function _highlightFlash(item, r, g, b)
  if TrafficConfig.debugBehaviour then
    local driver = item.guide:getDriver()
    if driver:getCar() == nil then return end
    driver:getCar():setDebugValue(r, g, b)
    setTimeout(function () 
      if driver:getCar() == nil then return end
      driver:getCar():setDebugValue()
    end, 0.3)
  end
end

---@class IntersectionManeuver : ManeuverBase
---@field inter TrafficIntersection
---@field phase integer
---@field guide TrafficGuide
---@field fromDef IntersectionLink
---@field toDef IntersectionLink
---@field _minContact any
---@field _trajectoryPriority number
---@field makingUTurn boolean
local IntersectionManeuver = class('IntersectionManeuver', ManeuverBase, class.Pool)

local lastIndex = 0
local _mrandom = math.random

---@param intersection TrafficIntersection
---@param guide TrafficGuide
---@param fromDef IntersectionLink
---@param toDef IntersectionLink
---@return IntersectionManeuver
function IntersectionManeuver:initialize(intersection, guide, fromDef, toDef)
  if self.inter then error('Already attached') end

  lastIndex = lastIndex + 1

  local curveInfo = intersection:getCachingCurve(fromDef, toDef)
  self.inter = intersection
  self.phase = intersection.phase
  self.guide = guide
  self.fromDef = fromDef
  self.toDef = toDef
  self._inCurve = -fromDef.lane:distanceToUpcoming(guide:getDistance(), fromDef.from)
  self.active = false
  self.closeToTraverse = false
  self._trajectoryPriority = intersection.mergingIntersection and _mrandom() or intersection:getPriorityLevel(fromDef.lane, toDef.lane)
  self._trajectoryOffsetPriority = lastIndex
  self._checkDelay = 0
  self._blockedCounter = 0
  self._impatienceCounter = 0
  self._engagedFor = 0
  self.justFloorIt = false
  self.makingUTurn = curveInfo.curve.fromDir:dot(curveInfo.curve.toDir) < -0.5
  self.curveInfo = curveInfo
  self._minContact = { distance = 1e9 }
end

function IntersectionManeuver:__tostring()
  return string.format('<IntersectionManeuver: %s, priority=%.2f, phase=%s>', 
    not self.closeToTraverse and 'far' or not self.active and 'waiting' or 'traversing',
    self._trajectoryPriority, self.phase)
end

function IntersectionManeuver:detach()
  self.inter:disconnectEngaged(self)
  self.inter = nil
  class.recycle(self)
end

local _mmin = math.min

---@param laneLink IntersectionLink
---@param iman IntersectionManeuver
local function findFreeAlternativeCallback(laneLink, _, iman)
  if laneLink.lane ~= iman.toDef.lane
    and laneLink.toPos ~= nil then
    local distance = laneLink.lane:distanceToNextCar(laneLink.to)
    if iman.inter:areLanesCompatible(iman.fromDef.lane, laneLink.lane, true) then
      return _mmin(distance, 100)
    end
  end
  return 0
end

---@return IntersectionLink
function IntersectionManeuver:_findFreeAlternative()
  if not self.guide:canChange() then return nil end
  -- if self.inter.name == 'I29' then ac.debug('looking for a way around', math.random()) end
  return self.inter._linksList:random(findFreeAlternativeCallback, self)
end

---@param e IntersectionManeuver
---@param n CachingCurve
local function findWayAroundNarrowCallback(e, _, n)
  return not n:intersects(e.curveInfo)
end

function IntersectionManeuver:_findWayAroundNarrow()
  local newLaneLink = self:_findFreeAlternative()
  self._impatienceCounter = 0
  if newLaneLink ~= nil then
    local newCurveInfo = self.inter:getCachingCurve(self.fromDef, newLaneLink)
    if self.inter.traversing:every(findWayAroundNarrowCallback, newCurveInfo) then
      self.toDef = newLaneLink
      self.curveInfo = newCurveInfo
      self:activate()
      self.guide:changeNextTo(self.toDef.lane, self.toDef.to)
      return true
    end
  end
  return false
end

function IntersectionManeuver:_findWayAroundWide()
  self._impatienceCounter = 0
  local newLaneLink = self:_findFreeAlternative()
  if newLaneLink ~= nil then
    local dir = self.guide:getDriver():getDirRef()
    if dir == nil then return end
    local newCurveInfo = CachingCurve(
      self.guide:getDriver():getPosRef(), dir,
      newLaneLink.lane:interpolateDistance(newLaneLink.to), newLaneLink.lane:getDirection(newLaneLink.to), true)
    if self.inter.traversing:every(function (e) return e == self or not newCurveInfo:intersects(e.curveInfo) end) then
      self.toDef = newLaneLink
      self.curveInfo = newCurveInfo
      self:activate()
      self.guide:changeNextTo(self.toDef.lane, self.toDef.to)
      -- if self.inter.name == 'I29' then
        -- ac.debug('found a wide way around', math.random()) 
        -- DebugShapes['_findWayAroundWide: FROM'] = self.guide:getDriver():getPosRef():clone()
        -- DebugShapes['_findWayAroundWide: FROM'] = newLaneLink.toPos:clone()
      -- end
      return
    end
    class.recycle(newCurveInfo)
  end
end

local _mucrossY = MathUtils.crossY
local _dpos = vec3()

---@param a IntersectionManeuver
---@param b IntersectionManeuver
local function _compareTrajectories(a, b)
  if not a.makingUTurn and not b.makingUTurn then return 0 end
  local aUTurnLp = a.makingUTurn and a.toDef.toPos:distanceSquared(b.fromDef.fromPos) < a.fromDef.fromPos:distanceSquared(b.fromDef.fromPos) * 0.7
  local bUTurnLp = b.makingUTurn and b.toDef.toPos:distanceSquared(a.fromDef.fromPos) < b.fromDef.fromPos:distanceSquared(a.fromDef.fromPos) * 0.7
  return aUTurnLp == bUTurnLp and 0 or bUTurnLp and 1 or -1
end

---@param engagement IntersectionManeuver
function IntersectionManeuver:_hasPriorityOver(engagement)
  if self.fromDef.tlState > 0 then return true end

  if self._trajectoryPriority ~= engagement._trajectoryPriority then
    return (self._trajectoryPriority or 0) > (engagement._trajectoryPriority or 0)
  end

  -- If starting from the same point or our lane is currently blocked, can’t have a priority
  if self.fromDef.lane == engagement.fromDef.lane or self.fromDef.tlState < 0 then return false end

  -- If starting with similar direction, same priority
  if self.curveInfo.curve.fromDir:dot(engagement.curveInfo.curve.fromDir) > 0.8 then
    return false
  end

  -- Compare trajectories: somebody making a U-turn in a certain way would have to wait
  -- local comparisonResult = _compareTrajectories(self, engagement)
  -- if comparisonResult ~= 0 then
  --   return comparisonResult > 0
  -- end
  if engagement.makingUTurn ~= self.makingUTurn then
    return engagement.makingUTurn
  end

  -- If other car is on the right side of us, can’t have a priority
  return _mucrossY(self.curveInfo.curve.fromDir, _dpos:set(engagement.fromDef.fromPos):sub(self.fromDef.fromPos)) < 0
end

---@param engagement IntersectionManeuver
---@param greenLightMode boolean 
function IntersectionManeuver:_compatibleWith(engagement, greenLightMode)
  if self.fromDef == engagement.fromDef -- start from the same position
      -- or greenLightMode and self.inter.phase == engagement.phase -- green light: ignore trajectories and just go -- TODO:DEV
      or self.inter.mergingIntersection and engagement.active -- merging intersections work differently
      or not self.curveInfo:intersects(engagement.curveInfo) then -- if trajectories do not intersect, all is good
    return true
  end

  -- if trajectories intersect, last chance: maybe _remaining_ bits of trajectories don’t?
  -- if self._engagedFor > 5 and engagement._inCurve > 6 and not self.curveInfo:intersectsAfter(engagement.curveInfo, self._inCurve + 3, engagement._inCurve) then
  --   _highlightFlash(self, 1, 0, 1)
  --   -- local e = engagement
  --   -- for j = 0, 20 do
  --   --   DebugShapes['pe'..tostring(j)] = e.curveInfo.curve:get(math.lerp(e._inCurve, e.curveInfo.curve.length, j/20))
  --   --   DebugShapes['ps'..tostring(j)] = e.curveInfo.curve:get(math.lerp((self._inCurve + 3), self.curveInfo.curve.length, j/20))
  --   -- end
  --   return true
  -- end

  -- nope, have to wait
  return false
end

function IntersectionManeuver:_compatibleWithTraversing(greenLightMode)
  local ts = self.inter.traversing
  local tn = ts.length
  for i = 1, tn do
    local e = ts[i]
    if not self:_compatibleWith(e, greenLightMode) then
      return false
    end
  end
  return true
end

function IntersectionManeuver:_anyBlocking()
  local es = self.inter.engaged
  local en = es.length
  for i = 1, en do
    local other = es[i]
    if other.closeToTraverse and not other.active and other:_hasPriorityOver(self) and not self:_compatibleWith(other) then
      return other
    end
  end
  return nil
end

function IntersectionManeuver:_shouldLetOthersFirst()
  local bc = self._blockedCounter
  if bc > 4 then
    _highlightFlash(self, 0, 1, 1)
    return false
  end

  if self._impatienceCounter > 2 and self.inter.traversing:some(function (i) return i.fromDef == self.fromDef and i.toDef == self.toDef end) then
    _highlightFlash(self, 0, 1, 1)
    return false
  end

  local blocking = self:_anyBlocking()
  if blocking == nil then 
    _highlightFlash(self, 0, 1, 0)
    return false
  end

  _highlightFlash(self, 1, 0, 0)
  _highlightFlash(blocking, 1, 1, 0)

  self._blockedCounter = bc + 1
  self._impatienceCounter = 0
  return true
end

function IntersectionManeuver:_checkIfShouldGo(speedKmh, dt)
  local fromDef = self.fromDef
  local inter = self.inter

  -- if inter.phase ~= inter.lowestPhase then return false end -- TODO

  -- Red light or something like that
  local tlState = fromDef.tlState
  if tlState < 0 or tlState > 0 and inter.phase == inter.lowestPhase then
    return tlState > 0 and (tlState == IntersectionLink.StateGreen or self._inCurve > -4)
  end

  if not self:_compatibleWithTraversing(tlState == IntersectionLink.StateGreen) then

    -- Got tired of waiting and found a different route
    if self._impatienceCounter > 5 and speedKmh < 0.01 and self:_findWayAroundNarrow() then
      _highlightFlash(self, 0, 0, 0.5)
      return true
    end

    -- Somebody is currently traversing intersection in an incompatible manner
    if self._blockedCounter > 1 then
      self._blockedCounter = 4
    end

    _highlightFlash(self, 0.3, 0, 0)
    return false

  end

  -- Letting go a car on the right side
  if tlState == IntersectionLink.StateAuto and self:_shouldLetOthersFirst() then
    return false
  end

  return true
end

function IntersectionManeuver:activate()
  if not self.active then
    self.active = true
    self.phase = self.inter.phase
    self.inter.traversing:push(self)
  end
end

function IntersectionManeuver:advance(speedKmh, dt)
  local active = self.active
  local closeToTraverse = self.closeToTraverse
  local _inCurve = self._inCurve + (speedKmh / 3.6) * dt
  self._inCurve = _inCurve
  self._engagedFor = self._engagedFor + dt

  if active or closeToTraverse then
    self._impatienceCounter = self._impatienceCounter + dt
  end

  if not closeToTraverse and _inCurve > -2 then
    closeToTraverse, self.closeToTraverse = true, true
  end

  if not active and speedKmh > 10
      and self._trajectoryPriority >= 0 
      and self.guide._curCursor and self.guide._curCursor.index == 1
      and self.fromDef.tlState == IntersectionLink.StateGreen 
      and self.inter.phase == self.inter.lowestPhase then
    active, self.justFloorIt = true, true
    self:activate()
  end

  if not active and closeToTraverse then
    local checkDelay = self._checkDelay - dt
    if checkDelay > 0 then
      self._checkDelay = checkDelay
    elseif self:_checkIfShouldGo(speedKmh, dt) then
      active = true
      self:activate()
    else
      self._checkDelay = 0.5
    end
  end

  if active then
    if _inCurve > self.curveInfo.curve.length then
      self:detach()
      return true
    end

    if speedKmh < 0.01 and self._impatienceCounter > 5 and not self:shouldDetachFromLane() and self.guide:getDriver():getDirRef() ~= nil then
      self:_findWayAroundWide()
      return false
    end
  end

  return false
end

function IntersectionManeuver:shouldDetachFromLane()
  return self._inCurve > 5
end

function IntersectionManeuver:ensureActive()
  if self._inCurve < 0 then
    self._inCurve = 0
  end
end

function IntersectionManeuver:calculateCurrentPosInto(v, estimate)
  if self._inCurve >= 0 then
    return self.curveInfo.curve:getInto(v, self._inCurve, estimate)
  else
    if self.guide._curCursor == nil then
      DebugShapes.unexpected = self.guide.driver:getPosRef():clone()
      error('Guide lost its cursor, but intersection meaneuver is yet to start')
    end
  end
  return nil
end

function IntersectionManeuver:handlesDistanceToNext()
  return self.active
end

local _refFuturePos = vec3()
local _futureDirHint = vec3()
local _needsMinContact = false

---@param driver TrafficDriver
---@param otherDriver TrafficDriver
local function _distanceBetween(driver, otherDriver, futurePosHint)
  local car = driver:getCar()
  local otherCar = otherDriver:getCar()
  if car == nil or otherCar == nil then return 0 end
  return car:freeDistanceTo(otherCar, _futureDirHint:set(futurePosHint):sub(car:getPosRef()):addScaled(car:getDirRef(), 6):normalize())
end

---@return number, CarBase|nil, DistanceTag
function IntersectionManeuver:distanceToNextCar()
  local rd, rc, rt = -self._inCurve, nil, DistanceTags.IntersectionDistanceTo
  local justFloorIt = self.justFloorIt
  if justFloorIt then
    local eng = self.inter.engaged
    for i = 1, #eng do
      local e = eng[i]
      if e.fromDef ~= self.fromDef and e._trajectoryPriority > self._trajectoryPriority then
        justFloorIt = false
        break
      end
    end
    if justFloorIt then
      rd, rt = 40, DistanceTags.IntersectionDrivingStraightWithPriority
    end
  end

  if self.closeToTraverse then
    if self.active then
      rd, rt = 40, DistanceTags.IntersectionActive
    end

    local _inCurve = self._inCurve

    local curveLeft = self.curveInfo.curve.length - _inCurve
    if curveLeft < 8 then
      local dd, dc, dt = self.toDef.lane:distanceToNextCar(self.toDef.to - curveLeft, self.guide:getDriver().dimensions.front)
      if dd < rd then
        rd, rc, rt = dd, dc, dt
        -- self.driver._nextTag = desiredTag

        if self._minContact.mainCar ~= nil then
          self._minContact.active = false
        end
      end
    end

    -- self.driver._nextTag = 'inter: min-none'

    if self._minContact.mainCar ~= nil then
      self._minContact.active = false
    end

    local _trajectoryPriority = _inCurve > 0 and self._trajectoryPriority or 0
    self.curveInfo.curve:getInto(_refFuturePos, _inCurve + 4, true)

    local ts = self.inter.traversing
    local tn = ts.length
    local fromSameSide = 0
    for i = 1, tn do
      local e = ts[i]
      if e ~= self then

        if _trajectoryPriority < 0 then
          if e.fromDef.enterSide == self.fromDef.enterSide then
            fromSameSide = fromSameSide + 1
          elseif (e._trajectoryPriority > self._trajectoryPriority or e._trajectoryPriority == self._trajectoryPriority and self._trajectoryOffsetPriority < e._trajectoryOffsetPriority) 
              and self.curveInfo:intersects(e.curveInfo)
              and self.curveInfo:intersectsAfter(e.curveInfo, self._inCurve + 3, e._inCurve) 
              then
            -- ac.debug('here', self.curveInfo:intersectsAfter(e.curveInfo, self._inCurve + 3, e._inCurve))
            -- if not self.curveInfo:intersectsAfter(e.curveInfo, self._inCurve + 3, e._inCurve) then
            --   for j = 0, 20 do
            --     DebugShapes['pe'..tostring(j)] = e.curveInfo.curve:get(math.lerp(e._inCurve, e.curveInfo.curve.length, j/20))
            --     DebugShapes['ps'..tostring(j)] = e.curveInfo.curve:get(math.lerp((self._inCurve + 3), self.curveInfo.curve.length, j/20))
            --   end
            -- end

            local d = 4 - _inCurve
            if d < rd then
              rd, rc, rt = d, e.guide:getDriver():getCar(), DistanceTags.IntersectionWaitingOnSecondaryRoute
            end
          end
        end

        local eDriver = e.guide:getDriver()
        if eDriver.pos:closerToThan(_refFuturePos, 6) then
          local d = _distanceBetween(self.guide:getDriver(), eDriver, _refFuturePos)
          if d < rd then
            rd, rc, rt = d, eDriver:getCar(), e.fromDef == self.fromDef and DistanceTags.IntersectionCarInFront or DistanceTags.IntersectionMergingCarInFront
            -- self.driver._nextTag = 'inter: car in front'
            if _needsMinContact and (self._minContact.distance > rd or not self._minContact.active) then
              self._minContact.distance = rd
              self._minContact.refFuturePos = _refFuturePos:clone()
              self._minContact.mainCar = self.guide:getDriver().pos
              self._minContact.nextCar = eDriver.pos
              self._minContact.active = true
            end
          end
        end

      end
    end

    if self.active then

      if _trajectoryPriority < 0 then
        if _inCurve > 2.501 and rd > 1.5 then
          self._trajectoryPriority = 0
          local newPhase = self.phase - 1
          self.phase = newPhase
          if self.inter.lowestPhase > newPhase then
            self.inter.lowestPhase = newPhase
          end
        else
          -- solves gridlocks that occur when two lower priories get stuck because one with larger weight would
          -- also wait for a car that is blocked by a smaller weight low priority car 
          self._trajectoryOffsetPriority = self._trajectoryOffsetPriority + fromSameSide
        end
      end
    end
    return rd, rc, rt
  end

  return rd, rc, rt
end

function IntersectionManeuver:draw3D(layers)
  if not self.closeToTraverse then return end

  layers:with('Trajectory', true, function()
    local f, t = nil, self.fromDef.fromPos
    for j = 1, 8 do
      f, t = t, self.curveInfo.curve:get((j / 9) * self.curveInfo.curve.length)
      render.debugArrow(f, t, 0.5, self.active and rgbm(0, 3, 0, 1) or rgbm(3, 0, 0, 1))
    end
    render.debugArrow(t, self.toDef.toPos, 0.5, self.active and rgbm(0, 3, 0, 1) or rgbm(3, 0, 0, 1))
  end)

  layers:with('Min contact', true, function()
    _needsMinContact = true
    if self._minContact.mainCar ~= nil then
      render.debugArrow(self._minContact.mainCar, self._minContact.refFuturePos, 0.1, rgbm(0, 3, 0, 1))
      render.debugArrow(self._minContact.mainCar, self._minContact.nextCar, 0.1, rgbm(3, self._minContact.active and 0 or 1, 0, 1))
      render.debugText(self._minContact.mainCar, string.format('CNT: %.2f m', self._minContact.distance),
        rgbm(3, 0.5, 0, 1), 1.5)
      -- self._minContact.mainCar = nil
    end
  end)

  layers:with('Priority', true, function()
    render.debugText(self.guide.driver:getPosRef(), string.format('PRI: %.2f', self._trajectoryPriority))
  end)
end

return class.emmy(IntersectionManeuver, IntersectionManeuver.initialize)