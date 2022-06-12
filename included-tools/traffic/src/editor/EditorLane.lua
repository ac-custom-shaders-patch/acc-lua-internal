local Array = require('Array')
local AABB = require('AABB')
local CubicInterpolatingLane = require('CubicInterpolatingLane')

local lastIndex = 0

---@class EditorLane : ClassBase
---@field name string
---@field loop boolean
---@field aabb AABB
---@field role integer
---@field priorityOffset number
---@field finalized SerializedLane
---@field points vec3[]|Array
local EditorLane = class('EditorLane')

---@param p1 vec3|SerializedLane
---@param p2 vec3
---@return EditorLane
function EditorLane:initialize(p1, p2)
  lastIndex = lastIndex + 1
  self.uniqueID = lastIndex
  if vec3.isvec3(p1) then
    self.name = 'Lane #'..lastIndex
    self.id = lastIndex
    self.loop = false
    self.role = 3
    self.priorityOffset = 0
    self.points = Array{ p1, p2 }
    self.params = {}
  else
    -- deserialization
    self.name = p1.name
    self.id = p1.id or lastIndex
    self.loop = p1.loop == true
    self.role = p1.role or 3
    self.priorityOffset = p1.priorityOffset or 0
    self.points = Array(p1.points, vec3.new)
    self.params = p1.params or {}
  end
  self.aabb = AABB()
  self:recalculate()
end

function EditorLane:cubicCurve()
  local r = self._cubicCurve
  if r == nil then
    r = CubicInterpolatingLane(self.points, self.loop, true)
    self._cubicCurve = r
  end
  return r
end

---@return SerializedLane
function EditorLane:encode()
  return {
    name = self.name,
    id = self.id,
    loop = self.loop,
    role = self.role ~= 3 and self.role or nil,
    priorityOffset = self.priorityOffset,
    points = self.points:map(vec3.table, nil, {}),
    params = self.params
  }
end

local vecDown = vec3(0, -1, 0)

---@param editor EditorMain
---@return SerializedLane
function EditorLane:finalize(editor)
  if self.finalized == nil then
    local baseLane = try(function ()
      return CubicInterpolatingLane(self.points, self.loop)
    end, function (err)
      ac.error(string.format('Lane is damaged: %s', self.name))
    end)
    if not baseLane then
      self.finalized = {
        aabb = { vec3():table(), vec3():table() },
        points = {}
      }
    else
      local length = math.ceil(baseLane.totalDistance / 3)
      local resampledPoints = Array(self.loop and length or length + 1)
      resampledPoints[1] = baseLane.points[1]
      local loopLength = self.loop and length - 1 or length
      for i = 1, loopLength do
        local p = baseLane:interpolate(baseLane:distanceToPointEdgePos(baseLane.totalDistance * i / length))
        p.y = p.y + 2
        local offset = physics.raycastTrack(p, vecDown, 4)
        p.y = p.y - (offset ~= -1 and offset or 2)
        resampledPoints[i + 1] = p
      end
      self.finalized = {
        aabb = { self.aabb.min:table(), self.aabb.max:table() },
        points = resampledPoints:map(vec3.table, nil, {})
      }
      class.recycle(baseLane)
    end
  end

  local role = editor.rules.laneRoles[self.role]
  self.finalized.name = self.name
  self.finalized.id = self.id
  self.finalized.loop = self.loop
  self.finalized.role = self.role
  self.finalized.priority = (role and role.priority or 0) + self.priorityOffset
  self.finalized.priorityOffset = self.priorityOffset
  self.finalized.speedLimit = role and role.speedLimit or 90
  self.finalized.params = self.params

  return self.finalized
end

function EditorLane:getPointRef(pointIndex)
  return self.points[pointIndex]
end

function EditorLane:extend(point, insertInFront)
  if insertInFront then
    self.points:insert(1, point)
  else
    self.points:push(point)
  end
  self:recalculate()
end

function EditorLane:removePointAt(pointIndex)
  self.points:removeAt(pointIndex)
  self:recalculate()
end

function EditorLane:insertPointNextTo(point, pointIndex)
  local p = self.points:at(pointIndex)
  if p == nil then
    self:extend(point)
  else
    local n = self.points:at(pointIndex + 1)
    local r = self.points:at(pointIndex - 1)
    if n ~= nil and r ~= nil and (point - p):dot(n - p) < (point - p):dot(r - p) then
      self.points:insert(pointIndex, point)
    else
      self.points:insert(pointIndex + 1, point)
    end
    self:recalculate()
  end
end

function EditorLane:recalculate()
  self.finalized = nil

  class.recycle(self._cubicCurve)
  self._cubicCurve = nil

  local aabb = self.aabb
  aabb:reset()
  for i = 1, #self.points do
    aabb:extend(self.points[i])
  end
  aabb:finalize()

  local len = 0
  for i = 2, #self.points do
    len = len + self.points[i - 1]:distance(self.points[i])
  end
  self.length = len
end

return class.emmy(EditorLane, EditorLane.initialize)