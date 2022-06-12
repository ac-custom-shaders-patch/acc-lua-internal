local DistanceTags = require "DistanceTags"
---@class LaneCursor
---@field lane TrafficLane
---@field driver TrafficDriver
---@field point integer
---@field edgePos number
---@field distance number
---@field index integer
---@field edgeCubic table
---@field edgeMeta EdgeMeta
local LaneCursor = class('LaneCursor', class.Pool)

---@param lane TrafficLane
---@param edgeIndex integer
---@param edgePos number
---@param cursorIndex integer
---@param distance number
---@param driver TrafficDriver
---@return LaneCursor
function LaneCursor:initialize(lane, edgeIndex, edgePos, cursorIndex, distance, driver)
  if self.lane then error('Already attached') end
  self.lane = lane
  self.point = edgeIndex
  self.edgePos = edgePos
  self.index = cursorIndex
  self.distance = distance
  self.driver = driver
  self.edgeCubic = lane.edgesCubic[edgeIndex]
  self.edgeMeta = lane.edgesMeta[edgeIndex]
  self.notFullyOnLane = false
end

function LaneCursor:__tostring()
  return string.format('<LaneCursor: lane=%s, distance=%.2f m, index=%d>', self.lane, self.distance, self.index)
end

function LaneCursor:detach()
  self.lane:stop(self)
  self.lane = nil
  class.recycle(self)
end

function LaneCursor:advance(speedKmh, dt)
  local lane = self.lane
  local point = self.point
  local edgeCubic = self.edgeCubic
  self.edgePos = self.edgePos + (speedKmh / 3.6) * dt * edgeCubic.edgeLengthInv
  if self.edgePos > 1 then
    point = point + 1
    if lane.loop then
      if point > lane.size then
        point = 1
        lane:restart(self)
      end
    elseif point >= lane.size then
      self:detach()
      return true
    end
    self.point = point
    local oldEdge = edgeCubic
    edgeCubic = lane.edgesCubic[point]
    self.edgeMeta = lane.edgesMeta[point]
    self.edgePos = (self.edgePos - 1) * oldEdge.edgeLength * edgeCubic.edgeLengthInv
    self.edgeCubic = edgeCubic
  end
  self.distance = edgeCubic.totalDistance + edgeCubic.edgeLength * self.edgePos
  return false
end

function LaneCursor:rearDistance()
  return self.distance - self.driver.dimensions.rear
end

---@param pos vec3
function LaneCursor:syncPos(pos)
  self.point, self.edgePos = self.lane:worldToPointEdgePos(pos)
  if self.point == 0 then
    DebugShapes.pos = pos
    error('Invalid state: '..tostring(pos) .. ', lane=' .. tostring(self.lane) .. ', car=' .. tostring(self.driver:getCar()))
  end
end

function LaneCursor:distanceToNextCar()
  local i = self.index - 1
  if i == 0 then
    if self.lane.loop then
      local lastCursor = self.lane.orderedCars[self.lane.orderedCars.length]
      if lastCursor.driver ~= self.driver then
        return self.lane.totalDistance + lastCursor:rearDistance() - self.distance, lastCursor.driver:getCar(), DistanceTags.LaneCursorLoopAround
      else
        return 1e9, nil, DistanceTags.LaneCursorEmpty
      end
    end
    return 1e9, nil, DistanceTags.LaneCursorEmpty
  end
  local nextCursor = self.lane.orderedCars[i]
  return nextCursor:rearDistance() - self.distance, nextCursor.driver:getCar(), DistanceTags.LaneCursorCarInFront
end

function LaneCursor:calculateCurrentPosInto(v, estimate)
  return self.lane:interpolateInto(v, self.point, self.edgePos, estimate)
end

return class.emmy(LaneCursor, LaneCursor.initialize)