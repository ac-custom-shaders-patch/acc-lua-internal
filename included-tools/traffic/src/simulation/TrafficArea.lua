local AABB = require('AABB')
local Array = require('Array')
local FlatPolyShape = require('FlatPolyShape')

---@class TrafficArea
---@field name string
---@field id integer
---@field params SerializedAreaParams
local TrafficArea = class('TrafficArea')

---@param def SerializedArea
---@return TrafficArea
function TrafficArea:initialize(def)
  self.id = def.id
  self.name = def.name
  self.shapes = Array(def.shapes, function (shape)
    return FlatPolyShape(shape[1][2], 10, shape, function (t) return vec2(t[1], t[3]) end)
  end)
  self.params = def.params
  self.aabb = AABB.fromArray(self.shapes, function (shape) return shape.aabb end)
end

---@param lane TrafficLane
---@param meta EdgeMeta
---@param params SerializedAreaParams
local function extendMeta(lane, meta, params)
  if params.priority then meta.priority = params.priority + lane.priorityOffset end
  if params.customSpeedLimit then meta.speedLimit = params.speedLimit or 90 end
  if params.spreadMult ~= nil then meta.spreadMult = params.spreadMult end
  if params.allowUTurns ~= nil then meta.allowUTurns = params.allowUTurns end
  if params.allowLaneChanges ~= nil then meta.allowLaneChanges = params.allowLaneChanges end
end

---@param lane TrafficLane
function TrafficArea:process(lane)
  if not self.aabb:horizontallyInsersects(lane.aabb) then return end

  for i = 1, lane.size do
    if self.shapes:some(function (
      shape ---@type FlatPolyShape
    ) return shape:contains(lane.points[i]) end) then
      extendMeta(lane, lane.edgesMeta[i], self.params)
    end
  end
end

return class.emmy(TrafficArea, TrafficArea.initialize)