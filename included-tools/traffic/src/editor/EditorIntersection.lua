local Array = require('Array')
local AABB = require('AABB')

local lastIndex = 0

local function _setTrajectoryAllowed(m, f, t, v)
  local u = m[f]
  if u == nil then
    if v == false then
      m[f] = {[t] = true}
    end
    return
  end
  if (v ~= false) ~= (u[t] ~= true) then
    if v then
      u[t] = nil
      if next(u) == nil then
        m[f] = nil
      end
    else
      u[t] = true
    end
  end
end

local function _setTrajectoryAttributes(m, f, t, v)
  local u = m[f]
  if u == nil then
    if v ~= nil then
      m[f] = {[t] = v}
    end
    return
  end
  if (v ~= nil) ~= (u[t] ~= nil) then
    if v == nil then
      u[t] = nil
      if next(u) == nil then
        m[f] = nil
      end
    else
      u[t] = v
    end
  end
end

local function _setEntryOffset(m, i, v, e)
  local l = m[i]
  if l == nil then
    l = {0,0}
    m[i] = l
  end
  l[e and 2 or 1] = v
end

---@class EditorIntersection : ClassBase
---@field name string
---@field points vec3[]
---@field aabb AABB
---@field trafficLightProgram string
---@field trafficLightParams SerializedTrafficLightParams
---@field trafficLightEmissive SerializedTrafficLightEmissiveParams[]
local EditorIntersection = class('EditorIntersection')

---@param points vec3[]|SerializedIntersection
---@return EditorIntersection
function EditorIntersection:initialize(points)
  lastIndex = lastIndex + 1
  self.uniqueID = lastIndex
  self.trajectoryAttributes = {}
  self.disallowedTrajectories = {}
  self.trafficLightParams = {}
  self.entryOffsets = {}
  self.entryPriorityOffsets = {}
  self.aabb = AABB()

  if vec3.isvec3(points[1]) then
    self.name = "Intersection #" .. lastIndex
    self.id = lastIndex
    self.points = points
  else
    -- deserialization
    self.name = points.name
    self.id = points.id or lastIndex
    self.points = Array(points.points, vec3.new)

    if points.disallowedTrajectories then
      for i = 1, #points.disallowedTrajectories do
        local e = points.disallowedTrajectories[i]
        _setTrajectoryAllowed(self.disallowedTrajectories, e[1], e[2], false)
      end
    end

    if points.trajectoryAttributes then
      for i = 1, #points.trajectoryAttributes do
        local e = points.trajectoryAttributes[i]
        _setTrajectoryAttributes(self.trajectoryAttributes, e[1], e[2], e[3])
      end
    end

    if points.entryOffsets then
      for i = 1, #points.entryOffsets do
        local e = points.entryOffsets[i]
        _setEntryOffset(self.entryOffsets, e.lane, e.offsets[1], false)
        _setEntryOffset(self.entryOffsets, e.lane, e.offsets[2], true)
      end
    end

    if points.entryPriorityOffsets then
      for i = 1, #points.entryPriorityOffsets do
        local e = points.entryPriorityOffsets[i]
        self.entryPriorityOffsets[e.lane] = e.offset
      end
    end

    if points.trafficLight then
      self.trafficLightProgram = points.trafficLight.program
      self.trafficLightParams = points.trafficLight.params or {}
      self.trafficLightEmissive = points.trafficLight.emissive or {}
    end
  end
  self:recalculate()
end

function EditorIntersection:getPointRef(pointIndex)
  return self.points[pointIndex]
end

---@param laneFrom EditorLane
---@param laneTo EditorLane
---@return SerializedTrajectoryAttributes
function EditorIntersection:getTrajectoryAttributes(laneFrom, laneTo)
  local t = self.trajectoryAttributes[laneFrom.id]
  if t == nil then
    return nil
  end
  return t[laneTo.id]
end

---@param laneFrom EditorLane
---@param laneTo EditorLane
---@param attributes SerializedTrajectoryAttributes
function EditorIntersection:setTrajectoryAttributes(laneFrom, laneTo, attributes)
  _setTrajectoryAttributes(self.trajectoryAttributes, laneFrom.id, laneTo.id, attributes)
  self.finalized = nil
end

function EditorIntersection:isTrajectoryAllowed(laneFrom, laneTo)
  local t = self.disallowedTrajectories[laneFrom.id]
  if t == nil then
    return true
  end
  return t[laneTo.id] == nil
end

function EditorIntersection:setTrajectoryAllowed(laneFrom, laneTo, value)
  _setTrajectoryAllowed(self.disallowedTrajectories, laneFrom.id, laneTo.id, value)
  self.finalized = nil
end

function EditorIntersection:getEntryOffset(lane, exitOffset)
  local l = self.entryOffsets[lane.id]
  return l ~= nil and l[exitOffset and 2 or 1] or 0
end

function EditorIntersection:setEntryOffset(lane, offset, exitOffset)
  _setEntryOffset(self.entryOffsets, lane.id, offset, exitOffset)
  self.finalized = nil
end

function EditorIntersection:getEntryPriorityOffset(lane)
  return self.entryPriorityOffsets[lane.id] or 0
end

function EditorIntersection:setEntryPriorityOffset(lane, offset)
  self.entryPriorityOffsets[lane.id] = offset
  self.finalized = nil
end

function EditorIntersection:encode()
  local _disTr = {}
  for enterID, enterMap in pairs(self.disallowedTrajectories) do
    for exitID, _ in pairs(enterMap) do
      table.insert(_disTr, {enterID, exitID})
    end
  end

  local _traAt = {}
  for enterID, enterMap in pairs(self.trajectoryAttributes) do
    for exitID, attributes in pairs(enterMap) do
      table.insert(_traAt, {enterID, exitID, attributes})
    end
  end

  local _entOf = {}
  for laneID, values in pairs(self.entryOffsets) do
    if values[1] ~= 0 or values[2] ~= 0 then
      table.insert(_entOf, {lane = laneID, offsets = values})
    end
  end

  local _entPo = {}
  for laneID, value in pairs(self.entryPriorityOffsets) do
    if value ~= 0 then
      table.insert(_entPo, {lane = laneID, offset = value})
    end
  end

  ---@type SerializedTrafficLightRef
  local _trfLg = nil
  if self.trafficLightProgram ~= nil then
    _trfLg = { program = self.trafficLightProgram, params = self.trafficLightParams, emissive = self.trafficLightEmissive }
  end

  return {
    name = self.name,
    id = self.id,
    points = self.points:map(function(p) return {p.x, p.y, p.z} end, nil, {}),
    disallowedTrajectories = #_disTr > 0 and _disTr or nil,
    trajectoryAttributes = #_traAt > 0 and _traAt or nil,
    entryOffsets = #_entOf > 0 and _entOf or nil,
    entryPriorityOffsets = #_entPo > 0 and _entPo or nil,
    trafficLight = _trfLg
  }
end

function EditorIntersection:finalize()
  if self.finalized == nil then
    self.finalized = self:encode()
    self.finalized.aabb = { self.aabb.min:table(), self.aabb.max:table() }
  end
  return self.finalized
end

function EditorIntersection:recalculate()
  self.finalized = nil

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

return class.emmy(EditorIntersection, EditorIntersection.initialize)
