local Array = require('Array')

local function getTangent(points, distances, loop, point, size)
  if not loop and (point == 1 or point >= size) then
    if point >= size then
      return (points[size] - points[size - 1]) / distances[size]
    end
    return (points[2] - points[1]) / distances[1]
  end

  return (points[point % size + 1] - points[point == 1 and size or point - 1])
    / math.max(0.00001, distances[point > size and 1 or point] + distances[point == 1 and size or point - 1])
end

---@class CubicInterpolatingLane : ClassBase
---@field totalDistance number
---@field points vec3[]
---@field edgesLength number[]
---@field edgesCubic {totalDistance: number, edgeLength: number, edgeLengthInv: number, tangentCur: number, tangentFol: number}[]
local CubicInterpolatingLane = class(class.Pool)

---@param points vec3[]
---@param loop boolean
---@param pointsPrepared boolean
---@return CubicInterpolatingLane
function CubicInterpolatingLane:initialize(points, loop, pointsPrepared)
  if not self.points then
    if not pointsPrepared and not self.points then self.points = Array() end
    self.edgesLength = Array()
    self.edgesCubic = Array()
  end

  if pointsPrepared then
    self.points = points
    self.ownPoints = false
  else
    self.ownPoints = true
    for i = 1, #points do
      local v = vec3.new(points[i])
      if i == 1 or not v:closerToThan(self.points[#self.points], 1) then
        self.points:push(v)
      end
    end
  end

  local count = #self.points
  self.size = count

  self.loop = loop
  if count < (self.loop and 3 or 2) then
    error('Too few points: '..tostring(#self.points))
    return
  end

  Array.range(count, nil, nil, function (i)
    if i == count and not loop then return self.points[i - 1]:distance(self.points[i]) end
    return self.points[i % count + 1]:distance(self.points[i])
  end, nil, self.edgesLength)

  local totalDistance = 0
  Array.range(count, nil, nil, function (i)
    local len = self.edgesLength[i]
    local ret = {
      totalDistance = totalDistance,
      edgeLength = len,
      edgeLengthInv = 1 / len,
      tangentCur = getTangent(self.points, self.edgesLength, self.loop, i, count),
      tangentFol = getTangent(self.points, self.edgesLength, self.loop, i + 1, count),
    }
    if i < count or loop then
      totalDistance = totalDistance + self.edgesLength[i]
    end
    return ret
  end, nil, self.edgesCubic)
  self.totalDistance = totalDistance
end

function CubicInterpolatingLane:recycled()
  self.edgesLength:clear()
  self.edgesCubic:clear()
  if self.ownPoints then
    self.points:clear()
  else
    self.points = nil
  end
end

---@param v vec3
---@param point integer
---@param edgePos number
---@param estimate boolean
---@return vec3
function CubicInterpolatingLane:interpolateInto(v, point, edgePos, estimate)
  local size = self.size
  if size <= 1 then
    return v:set(self.points[1])
  end

  local cur = self.points[point]
  if not cur then
    error('Invalid point value: '..tostring(point))
  end
  local fol = point == size and not self.loop and cur or self.points[point % size + 1]
  if estimate or size < 4 then
    return v:setLerp(cur, fol, edgePos)
  end

  local di = self.edgesCubic[point]
  local t1 = edgePos
  local t2 = t1 * t1
  local t3 = t1 * t2

  v:set(cur):scale(2 * t3 - 3 * t2 + 1)
  v:addScaled(di.tangentCur, (t3 - 2 * t2 + t1) * di.edgeLength)
  v:addScaled(fol, -2 * t3 + 3 * t2)
  return v:addScaled(di.tangentFol, (t3 - t2) * di.edgeLength)
end

---@param point integer
---@param edgePos number
---@param estimate boolean
---@return vec3
function CubicInterpolatingLane:interpolate(point, edgePos, estimate)
  local r = vec3()
  self:interpolateInto(r, point, edgePos, estimate)
  return r
end

---@param distance number
---@param estimate boolean
---@return vec3
function CubicInterpolatingLane:interpolateDistance(distance, estimate)
  local p, e = self:distanceToPointEdgePos(distance)
  return self:interpolate(p, e, estimate)
end

---@param v vec3
---@param distance number
---@param estimate boolean
---@return vec3
function CubicInterpolatingLane:interpolateDistanceInto(v, distance, estimate)
  local p, e = self:distanceToPointEdgePos(distance)
  return self:interpolateInto(v, p, e, estimate)
end

---@param distance number
function CubicInterpolatingLane:findClosestPoint(distance)
  return self.edgesCubic:findLeftOfIndex(function (meta) return meta.totalDistance > distance end)
end

---@param distance number
---@return integer, number
function CubicInterpolatingLane:distanceToPointEdgePos(distance)
  local nlPoint = self:findClosestPoint(distance)
  return nlPoint, (distance - self.edgesCubic[nlPoint].totalDistance) / self.edgesLength[nlPoint]
end

---@param point integer
---@param edgePos number
---@return number
function CubicInterpolatingLane:pointEdgePosToDistance(point, edgePos)
  return self.edgesCubic[point].totalDistance + self.edgesCubic[point].edgeLength * edgePos
end

return class.emmy(CubicInterpolatingLane, CubicInterpolatingLane.initialize)