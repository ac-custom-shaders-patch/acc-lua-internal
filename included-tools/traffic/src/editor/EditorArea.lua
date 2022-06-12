local Array = require('Array')
local AABB = require('AABB')

local lastIndex = 0

---@class EditorArea : ClassBase
---@field name string
---@field shapes vec3[][]
---@field aabb AABB
---@field params SerializedAreaParams
local EditorArea = class('EditorArea')

---@param points vec3[]|SerializedArea
---@return EditorArea
function EditorArea:initialize(points)
  lastIndex = lastIndex + 1
  self.uniqueID = lastIndex
  self.params = {}
  self.aabb = AABB()

  if vec3.isvec3(points[1]) then
    self.name = "Area #" .. lastIndex
    self.id = lastIndex
    self.shapes = Array{ points }
    self.params = {}
  else
    -- deserialization
    self.name = points.name
    self.id = points.id or lastIndex
    self.shapes = points.points 
      and Array{ Array(points.points, vec3.new) }
      or Array(points.shapes, function (shape) return Array(shape, vec3.new) end)
    self.params = points.params or {}
  end
  self:recalculate()
end

function EditorArea:encode()
  return {
    name = self.name,
    id = self.id,
    shapes = self.shapes:map(function (s)
      return s:map(function(p) return {p.x, p.y, p.z} end, nil, {})
    end, nil, {}),
    params = self.params
  }
end

---@param editor EditorMain
function EditorArea:finalize(editor)
  if self.finalized == nil then
    self.finalized = self:encode()
    self.finalized.aabb = { self.aabb.min:table(), self.aabb.max:table() }
  end
  self.params.priority = editor.rules.laneRoles[self.params.role] and editor.rules.laneRoles[self.params.role].priority or nil
  self.finalized.params = self.params
  return self.finalized
end

function EditorArea:extend(newShape)
  self.shapes:push(newShape)
  self:recalculate()
end

function EditorArea:getPointRef(pointIndex)
  return self.shapes[math.floor(pointIndex / 1000)][pointIndex % 1000]
end

function EditorArea:removePointAt(pointIndex)
  self.shapes[math.floor(pointIndex / 1000)]:removeAt(pointIndex % 1000)
  self:recalculate()
end

function EditorArea:insertPointNextTo(point, pointIndex)
  local s = self.shapes[math.floor(pointIndex / 1000)]
  pointIndex = pointIndex % 1000
  local p = s:at(pointIndex)
  if p == nil then
    s:push(point)
  else
    local n = s:at(pointIndex % #s + 1)
    local r = s:at(pointIndex == 1 and #s or pointIndex - 1)
    if n ~= nil and r ~= nil and (point - p):dot(n - p) < (point - p):dot(r - p) then
      s:insert(pointIndex, point)
    else
      s:insert(pointIndex + 1, point)
    end
  end
  self:recalculate()
end

function EditorArea:recalculate()
  self.finalized = nil

  local aabb = self.aabb
  aabb:reset()
  for i = 1, #self.shapes do
    for j = 1, #self.shapes[i] do
      aabb:extend(self.shapes[i][j])
    end
  end
  aabb:finalize()
end

return class.emmy(EditorArea, EditorArea.initialize)
