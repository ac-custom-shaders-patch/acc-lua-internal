local CacheTable = require('CacheTable')

---Represents link between intersection and lane. Could be with lane going to intersection and ending, could be with lane starting from intersection,
---could be both.
---@class IntersectionLink : ClassBase
---@field intersection TrafficIntersection
---@field lane TrafficLane Set by TrafficLane during its finalization step.
---@field enterSide IntersectionSide
---@field from number @Position on lane (`0`…`lane.totalDistance`) where intersection begins and lane pauses.
---@field to number @Position on lane (`0`…`lane.totalDistance`) where intersection ends and lane continues.
---@field fromPos vec3|nil @3D point on lane where intersection begins and lane pauses, only for lanes that don’t start from intersection.
---@field toPos vec3|nil @3D point on lane where intersection ends and lane continues, only for lanes that don’t end on intersection.
---@field fromDir vec3|nil
---@field toDir vec3|nil
---@field fromSide integer
---@field toSide integer
---@field fromOrigPos vec3 @Original lane pause position, without optional offset
---@field toOrigPos vec3 @Original lane resume position, without optional offset
---@field curves CacheTable
---@field tlState integer
local IntersectionLink = class('IntersectionLink', class.NoInitialize)

IntersectionLink.StateAuto = 0
IntersectionLink.StateGreen = 2
IntersectionLink.StateYellow = 1
IntersectionLink.StateRedYellow = -1
IntersectionLink.StateRed = -2

---@param intersection TrafficIntersection
---@param lane TrafficLane
---@param from number
---@param to number
---@param fromPos vec3
---@param toPos vec3
---@param fromSide IntersectionSide
---@param toSide IntersectionSide
---@param fromOrigPos vec3
---@param toOrigPos vec3
---@return IntersectionLink
function IntersectionLink.allocate(intersection, lane, from, to, fromPos, toPos, fromSide, toSide, fromOrigPos, toOrigPos)
  local fromFits = lane.loop or from > 0.1
  local toFits = lane.loop or to < lane.totalDistance - 0.1
  if fromPos and math.isNaN(fromPos.x) or toPos and math.isNaN(toPos.x) then 
    ac.error('NaN in IntersectionLink: '..tostring(lane)..'; '..tostring(intersection))
  end
  return {
    intersection = intersection,
    lane = lane,
    from = from,
    to = to,
    fromPos = fromFits and fromPos or nil,  -- can be nil for intersections at which lane begins
    toPos = toFits and toPos or nil,      -- can be nil for intersections at which lane ends
    fromDir = fromFits and lane:getDirection(from) or nil,
    toDir = toFits and lane:getDirection(to) or nil,
    fromSide = fromFits and fromSide or nil,
    toSide = toFits and toSide or nil,
    fromOrigPos = fromOrigPos,
    toOrigPos = toOrigPos,
    curves = CacheTable(),
    tlState = IntersectionLink.StateAuto
  }
end

function IntersectionLink:__tostring()
  return string.format('<Link between %s and %s>', self.intersection, self.lane)
end

function IntersectionLink:laneGoesOn()
  return self.toPos ~= nil
end

function IntersectionLink:getFromPosDir()
  return self.lane:interpolateDistance(self.from), self.lane:getDirection(self.from)
end

function IntersectionLink:getToPosDir()
  return self.lane:interpolateDistance(self.to), self.lane:getDirection(self.to)
end

return class.emmy(IntersectionLink, IntersectionLink.allocate)
