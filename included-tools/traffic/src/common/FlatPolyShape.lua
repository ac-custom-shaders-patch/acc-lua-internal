local Triangle = require('Triangle')
local Array = require('Array')
local AABB = require('AABB')
local MathUtils = require('MathUtils')

---@class FlatPolyShape
---@field yThreshold number
---@field yCenter number
---@field points vec2[]
---@field aabb AABB
local FlatPolyShape = class('FlatPolyShape', class.Pool)

---@generic T
---@param yPos number
---@param yThreshold number
---@param points T[]
---@param pointsMapFunc nil|fun(item: T): vec2
---@return FlatPolyShape
function FlatPolyShape:initialize(yPos, yThreshold, points, pointsMapFunc)
  self.points = Array(points, pointsMapFunc)

  local aabb = AABB()
  local v3 = vec3(0, yPos, 0)
  for i = 1, #self.points do
    v3.x, v3.z = self.points[i].x, self.points[i].y
    aabb:extend(v3)
  end
  self.aabb = aabb:finalize()
  self.yThreshold = yThreshold + self.aabb.max.y - self.aabb.min.y
  self.yCenter = self.aabb.center.y
end

local _mabs = math.abs
local _vtmp2f = vec2()
local _vtmp2t = vec2()
local _vtmp3o = vec3()

---@param p3 vec3
function FlatPolyShape:contains(p3)
  if not p3 or _mabs(p3.y - self.yCenter) > self.yThreshold or not self.aabb:horizontallyContains(p3) then return false end

  local from = _vtmp2f:set(p3.x, p3.z)
  local to = _vtmp2t:set(self.aabb.min.x - 1, self.aabb.min.z - 1)
  local h, s = 0, #self.points
  for i = 1, s - 1 do
    if MathUtils.hasIntersection2D(from, to, self.points[i], self.points[i + 1]) then
      h = h + 1
    end
  end
  if MathUtils.hasIntersection2D(from, to, self.points[s], self.points[1]) then
    h = h + 1
  end
  return h % 2 == 1
end

---@param from3 vec3
---@param to3 vec3
function FlatPolyShape:intersect(from3, to3)
  if _mabs(from3.y - self.yCenter) > self.yThreshold or _mabs(to3.y - self.yCenter) > self.yThreshold then
    return nil, 0
  end

  local ret, side = nil, 0
  local retDistance = 1e9
  local from = vec2(from3.x, from3.z)
  local to = vec2(to3.x, to3.z)
  for i = 1, #self.points do
    local hit = MathUtils.intersect(from, to, self.points[i], self.points[i % #self.points + 1])
    if hit ~= nil then
      local len = from:distanceSquared(hit)
      if len < retDistance then
        retDistance = len
        ret, side = hit, i
      end
    end
  end
  return ret, side
end

---@param lanePoints vec3[]
---@param laneLooped boolean
---@param intersectionCallback fun(startIndex: integer, startPos: vec2, startSide: integer, endIndex: integer, endPos: vec2, endSide: integer)
function FlatPolyShape:collectIntersections(lanePoints, laneLooped, intersectionCallback)
  local startIndex, startPos, startSide = 1, nil, 0
  local loopStartIndex, loopStartPos, loopStartSide = 0, nil, 0
  local i = 2
  local size = #lanePoints
  while i <= size do
    local p1 = lanePoints[i - 1]
    while not p1:closerToThan(self.aabb.center, 400) do
      i = i + 40
      if i > size then break end
      p1 = lanePoints[i - 1]
    end

    local p2 = lanePoints[i]
    local c1 = self:contains(p1)
    local c2 = self:contains(p2)

    if i == 2 and c1 and laneLooped then
      while c2 do
        i = i + 1
        p1, p2 = p2, lanePoints[i]
        c1, c2 = c2, self:contains(p2)
      end

      local h, side = self:intersect(p1, p2)
      if not h then
        error('Failed to find an intersection')
      end
      loopStartIndex, loopStartPos, loopStartSide = i - 1, h, side

    elseif c1 ~= c2 then

      local h, side = self:intersect(c2 and p1 or p2, c2 and p2 or p1)
      if not h then
        error('Failed to find an intersection')
      end

      if c2 then
        startIndex, startPos, startSide = i - 1, h, side
      else
        intersectionCallback(startIndex, startPos or vec2(lanePoints[1].x, lanePoints[1].z), startSide, i - 1, h, side)
        startPos = nil
      end

    elseif not c1 and not c2 then
      if startPos ~= nil then
        error('Intersections intersect?')
      end

      local h1, side1 = self:intersect(p1, p2)
      if h1 ~= nil then
        local h2, side2 = self:intersect(p2, p1)
        if h2 == nil then
          error('Failed to find a second intersection')
        end
        intersectionCallback(i - 1, h1, side1, i - 1, h2, side2)
      end
    end

    i = i + 1
  end

  if loopStartPos ~= nil then
    intersectionCallback(loopStartIndex, loopStartPos, loopStartSide, startIndex, startPos, startSide)
  elseif startPos ~= nil then
    intersectionCallback(startIndex, startPos, startSide, size - 1, vec2(lanePoints[size].x, lanePoints[size].z), startSide)
  end
end

return class.emmy(FlatPolyShape, FlatPolyShape.initialize)
