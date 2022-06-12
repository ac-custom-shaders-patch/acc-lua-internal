local ManeuverBase = require('ManeuverBase')
local BezierCurveNormalized = require('BezierCurveNormalized')
local TrafficContext = require('TrafficContext')
local PackedArgs = require('PackedArgs')
local DistanceTags = require('DistanceTags')
local TrafficConfig= require('TrafficConfig')

local vecTmp0 = vec3()
local vecTmp1 = vec3()
local vecTmp2 = vec3()
local vecTmp3 = vec3()

---@param lane TrafficLane
---@param distance number
local function testFreeSpace(lane, distance)
  local freeDistance, previousCursor = lane:freeSpace(distance)

  -- Need at least 12 m of free space forwards and backwards
  if freeDistance < 12 then return false end

  if previousCursor ~= nil then
    local spaceToPrevious = lane:distanceTo(previousCursor.distance, distance)
    if previousCursor.driver.speedKmh / 3.6 * 10 > spaceToPrevious then
      return false
    end
  end

  return true
end

---@param curve BezierCurveNormalized
local function testCurvePoints(curve)
  return not TrafficContext.trackerBlocking:anyCloserThan(curve:getPointRef(0.25), 1.5)
    and not TrafficContext.trackerBlocking:anyCloserThan(curve:getPointRef(0.5), 1.5)
    and not TrafficContext.trackerBlocking:anyCloserThan(curve:getPointRef(0.75), 1.5)
end

---@param laneTo TrafficLane
---@param pos vec3
---@param dir vec3
local function findManeuverCurve(laneTo, pos, dir, freeSpaceTested)
  local p, e = laneTo:worldToPointEdgePos(pos)
  if p == 0 then return nil end

  local posOnLane, dirOnLane = laneTo:getPositionDirectionInto(vecTmp0, vecTmp1, p, e, true)
  local spaceToCross = posOnLane:distance(pos)
  local baseLaneDistance = laneTo:pointEdgePosToDistance(p, e)
  if not freeSpaceTested and not testFreeSpace(laneTo, baseLaneDistance) then return nil end

  if dirOnLane:dot(dir) < 0.5 then
    local tp, te = laneTo:distanceToPointEdgePos(baseLaneDistance)
    local tpos, tdir = laneTo:getPositionDirectionInto(vecTmp2, vecTmp3, tp, te, false)
    local curve = BezierCurveNormalized(pos, dir, tpos, tdir)
    if testCurvePoints(curve) then return p, e, curve, baseLaneDistance end
    return nil
  end

  local tp, te = laneTo:distanceToPointEdgePos(baseLaneDistance + spaceToCross + 4)
  local tpos, tdir = laneTo:getPositionDirectionInto(vecTmp2, vecTmp3, tp, te, false)
  local sdir = posOnLane:sub(pos):normalize():scale(0.4):add(dir):normalize()
  local curve = BezierCurveNormalized(pos, sdir, tpos, tdir)
  if testCurvePoints(curve) then return p, e, curve, baseLaneDistance + spaceToCross + 4 end
  class.recycle(curve)

  tp, te = laneTo:distanceToPointEdgePos(baseLaneDistance + spaceToCross + 1)
  tpos, tdir = laneTo:getPositionDirectionInto(vecTmp2, vecTmp3, tp, te, false)
  sdir = laneTo:interpolateInto(vecTmp1, p, e):sub(pos):normalize():scale(0.4):add(dir):normalize()
  curve = BezierCurveNormalized(pos, sdir, tpos, tdir)
  if testCurvePoints(curve) then return p, e, curve, baseLaneDistance + spaceToCross + 1 end
  class.recycle(curve)

  ac.debug('LCM is blocked by a car', math.random())
end

---@class LaneChangeManeuver : ManeuverBase, ClassPool
local LaneChangeManeuver = class('LaneChangeManeuver', ManeuverBase, class.Pool)

---@param guide TrafficGuide
---@param laneTo TrafficLane
---@param edgeMeta EdgeMeta
---@return LaneChangeManeuver
function LaneChangeManeuver.tryCreate(guide, laneTo, edgeMeta, freeSpaceTested)
  if guide._curCursor == nil or guide._curCursor.lane == laneTo then return nil end

  local car = guide:getDriver():getCar()
  if car == nil then return nil end

  if guide:getDriver()._nextCar ~= nil and car:freeDistanceTo(guide:getDriver()._nextCar) < 2 then
    return nil
  end

  local pos = car:getPosRef()
  local dir = car:getDirRef()
  if dir == nil then return nil end

  local p, e, curve, laneToDistance = findManeuverCurve(laneTo, pos, dir, freeSpaceTested)
  if p ~= nil then
    return LaneChangeManeuver(guide, laneTo, laneTo:startCursorOnEdge(guide:getDriver(), p, e), curve, laneToDistance, edgeMeta)
  end
end

---@param guide TrafficGuide
---@param laneTo TrafficLane
---@param cursorTo LaneCursor
---@param trajectory BezierCurveNormalized
---@param edgeMeta EdgeMeta
---@return LaneChangeManeuver
function LaneChangeManeuver:initialize(guide, laneTo, cursorTo, trajectory, laneToDistance, edgeMeta)
  self.guide = guide
  self.laneTo = laneTo
  self.transition = 0
  self.trajectory = trajectory
  self.trajectoryLengthInv = 1 / trajectory:length()
  self.lastPos = self.lastPos and self.lastPos:set(0, 0, 0) or vec3()
  self._laneToMult = (laneToDistance - cursorTo.distance) * self.trajectoryLengthInv
  self._swapTimer = 0
  self._edgeMeta = edgeMeta

  self.cursorFrom = guide:stealCurrentLaneCursor()
  self.cursorTo = cursorTo

  if TrafficConfig.debugBehaviour then
    guide.driver:getCar():setDebugValue(1, 0, 0)
  end
end

function LaneChangeManeuver:assign(other)
  -- Destructive assignment in C++ style. Cursors are handled separately.
  self.guide, other.guide = other.guide, self.guide
  self.laneTo, other.laneTo = other.laneTo, self.laneTo
  self.transition, other.transition = other.transition, self.transition
  self.trajectory, other.trajectory = other.trajectory, self.trajectory
  self.trajectoryLengthInv, other.trajectoryLengthInv = other.trajectoryLengthInv, self.trajectoryLengthInv
  self.lastPos, other.lastPos = other.lastPos, self.lastPos
  self._laneToMult, other._laneToMult = other._laneToMult, self._laneToMult
  self._swapTimer, other._swapTimer = other._swapTimer, self._swapTimer
  self._edgeMeta, other._edgeMeta = other._edgeMeta, self._edgeMeta
  class.recycle(other)
end

function LaneChangeManeuver:recycled()
  class.recycle(self.trajectory)
end

function LaneChangeManeuver:detach()
  if self.cursorFrom ~= nil then
    self.cursorFrom:detach()
    self.cursorFrom = nil
  end
  if self.cursorTo ~= nil then
    self.cursorTo:detach()
    self.cursorTo = nil
  end
  class.recycle(self)
end

local _mrandom = math.random

---@param car TrafficCar
---@param currentLane TrafficLane
---@param edgeMeta EdgeMeta
function LaneChangeManeuver.findAlternativeLane(car, currentLane, edgeMeta)
  local from, to = TrafficContext.lanesSpace:rawPointers(car:getPosRef())
  local currentLaneID = currentLane.id
  local carPos = car:getPosRef()
  local carDir = car:getDirRef()
  local ml, rl, dl = 1/0, nil, nil
  local mr, rr, dr = 1/0, nil, nil
  while from ~= to do
    local laneID = from[0]
    if laneID ~= currentLaneID then
      local lane = TrafficContext.grid:getLaneByID(laneID)
      local p = lane and lane:worldToPointEdgePos(carPos) or 0
      if p ~= 0 and math.abs(lane.points[p].y - carPos.y) < 1 then
        local d = lane.points[p]:distanceSquared(carPos)
        local h = vecTmp0:set(car:getPosRef()):sub(lane.points[p]):dot(edgeMeta.side)
        if h > 0 then
          if d < ml then ml, rl, dl = d, lane, lane.edgesMeta[p].dir end
        else
          if d < mr then mr, rr, dr = d, lane, lane.edgesMeta[p].dir end
        end
      end
    end
    from = from + 1
  end

  local s = _mrandom()
  if rl and dl:dot(carDir) < 0.5 and (not edgeMeta.allowUTurns or s > 0.1) then rl = nil end
  if rr and dr:dot(carDir) < 0.5 and (not edgeMeta.allowUTurns or s > 0.1) then rr = nil end
  return (s > 0.5 or not rr) and rl or rr
end

---@param speedKmh number
---@param dt number
---@return boolean
function LaneChangeManeuver:advance(speedKmh, dt)
  if self.cursorTo == nil then
    error('Already detached')
    return true
  end

  if speedKmh < 2 then
    -- local car = self.guide.driver:getCar()
    local _swapTimer = self._swapTimer + dt
    if _swapTimer > 2 then
      _swapTimer = 0

      if self.transition < 0.05 then
        if self.lastPos.x ~= 0 then self.cursorFrom:syncPos(self.lastPos) end
        self.guide:adoptCurrentCursor(self.cursorFrom)
        self.cursorFrom = nil
        self:detach()
        return true
      end

      if self.cursorFrom ~= nil and self.cursorFrom:distanceToNextCar() > 4 then
        local swap = LaneChangeManeuver.tryCreate(self.guide, self.cursorFrom.lane, self._edgeMeta, true)
        if swap ~= nil then
          self:assign(swap)
          if self.cursorFrom then
            self.cursorFrom:detach()
          end
          self.cursorFrom, self.cursorTo = self.cursorTo, swap.cursorTo
        end
      end

      -- local altLane = LaneChangeManeuver.findAlternativeLane(car, self.cursorTo.lane, self._edgeMeta)
      -- if altLane ~= nil then
      --   local swap = LaneChangeManeuver.tryCreate(self.guide, altLane, self._edgeMeta, true)
      --   if swap ~= nil then
      --     self:assign(swap)
      --     if self.cursorFrom then
      --       self.cursorFrom:detach()
      --     end
      --     self.cursorFrom, self.cursorTo = self.cursorTo, swap.cursorTo
      --   end
      -- end

    end

    self._swapTimer = _swapTimer
  else
    self._swapTimer = 0
  end

  local transition = self.transition + dt * (speedKmh / 3.6) * self.trajectoryLengthInv
  if transition >= 1 and self.transition < 1 then
    self.cursorTo:syncPos(self.lastPos)
    self.guide:adoptCurrentCursor(self.cursorTo)
    self.cursorTo = nil
    self:detach()
    return true
  end
  self.transition = transition

  if self.cursorFrom and self.cursorFrom:advance(speedKmh * 0.5, dt) then
    self.cursorFrom = nil
  end

  if self.cursorTo:advance(speedKmh * self._laneToMult, dt) then
    self.cursorTo = nil
    self:detach()
    return true
  end

  return false
end

---@return boolean
function LaneChangeManeuver:shouldDetachFromLane()
  return true
end

---@return boolean
function LaneChangeManeuver:handlesDistanceToNext()
  return true
end

---@return boolean
function LaneChangeManeuver:handlesDistanceToBlocking()
  return true
end

local packed = PackedArgs()

---@param car1 CarBase
local function checkBlocking(car1, params)
  local car2, dir = params[1], params[2]
  return car2:freeDistanceTo(car1, dir)
end

---@return number, CarBase|nil, DistanceTag
function LaneChangeManeuver:distanceToNextCar()
  local rd, rc, rt = 5, nil, DistanceTags.LaneChangeBase
  
  if self.transition > 0.3 then
    local td, tc, tt = self.cursorTo:distanceToNextCar()
    if td < rd then
      rd, rc, rt = td, tc, tt
    end
  end

  if self.transition < 0.7 and self.cursorFrom ~= nil then
    local fd, fc, ft = self.cursorFrom:distanceToNextCar()
    if fd < rd then
      rd, rc, rt = fd, fc, ft
    end
  end

  local car = self.guide.driver:getCar()
  local vecDir = self.trajectory:getInto(vecTmp1, self.transition * 0.8 + 0.2):sub(self.lastPos):normalize()
  local bd, bc = TrafficContext.trackerBlocking:findNearest(self.lastPos, checkBlocking, packed:pack2(car, vecDir))
  if bd < rd then
    return bd, bc, DistanceTags.LaneChangeBlocking
  end

  return rd, rc, rt
end

---@param v vec3
---@param estimate boolean
function LaneChangeManeuver:calculateCurrentPosInto(v, estimate)
  if self.transition >= 1 then
    return self.cursorTo:calculateCurrentPosInto(v, estimate)
  end

  self.trajectory:getInto(v, self.transition)
  self.lastPos:set(v)
  return v
end

return class.emmy(LaneChangeManeuver, LaneChangeManeuver.initialize)