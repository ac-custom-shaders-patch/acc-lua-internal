local IntersectionLink = require('IntersectionLink')
local Array = require('Array')
local TrafficLightEmissive = require('TrafficLightEmissive')

---@class TrafficLight
---@field emissive TrafficLightEmissive[]
local TrafficLight = class('TrafficLight')

---@param data SerializedTrafficLightRef
---@param intersection TrafficIntersection
---@return TrafficLight
function TrafficLight:initialize(data, intersection)
  self.program = data.program
  self.params = data.params
  self.sides = intersection._sides
  self.position = vec3.new(intersection._sides[1].p1)
  self._intersection = intersection  -- stored only for delayed emissive creation
  self._data = data
  self.timeLeft = 0
  self.allowedLane = 1
end

function TrafficLight:update(cameraPosition, dt)
  local r = false
  self.timeLeft = self.timeLeft - dt
  if self.timeLeft < 0 then 
    self.timeLeft = self.params.duration or 15
    self.allowedLane = 1 - self.allowedLane
    r = true
  end

  local updateEmissive = true -- self.position:closerToThan(cameraPosition, 400)
  if updateEmissive and not self.emissive then
    self.emissive = self._intersection._sides:mapTable(function (side, _, data_)
      local i = side.index
      return i, data_.emissive and data_.emissive[i] and (data_.emissive[i].mode or data_.emissive[i].roles) and TrafficLightEmissive(side, data_.emissive[i]) or nil    
    end, self._data)
    self._intersection = nil
    self._data = nil
  end

  ---@param self_ TrafficLight
  for i = 1, #self.sides do
    local side = self.sides[i]
    local index = side.index
    local tlState = index % 2 == self.allowedLane 
      and (self.timeLeft < 2 and IntersectionLink.StateYellow or IntersectionLink.StateGreen)
      or (self.timeLeft < 2 and IntersectionLink.StateRedYellow or IntersectionLink.StateRed)
    if side.tlState ~= tlState then
      side.tlState = tlState
      side.entries:forEach(function (entry, _, tlState_) entry.tlState = tlState_ end, tlState)

      if updateEmissive then
        if self.emissive[index] then self.emissive[index]:update() end
      end
    end
  end
  return r
end

local function renderQuad(pos, dir, color)
  render.glSetColor(color)
  render.glBegin(render.GLPrimitiveType.Quads)
  render.glVertex(pos)
  render.glVertex(pos + vec3(0, 0.5, 0))
  render.glVertex(pos + vec3(dir.z * 0.5, 0.5, -dir.x * 0.5))
  render.glVertex(pos + vec3(dir.z * 0.5, 0, -dir.x * 0.5))
  render.glEnd()
end

local _colors = {
  redInactive = rgbm(0.4, 0, 0, 1),
  redActive = rgbm(40, 3, 3, 1),
  yellowInactive = rgbm(0.4, 0.3, 0, 1),
  yellowActive = rgbm(30, 20, 0, 1),
  greenInactive = rgbm(0.1, 0.4, 0, 1),
  greenActive = rgbm(10, 30, 0, 1),
}

function TrafficLight:draw3D(layers)
  for i = 1, self.sides.length do
    local side = self.sides[i]
    local pos = (side.entries[#side.entries].fromPos - side.centerEntries):normalize():add(side.entries[#side.entries].fromPos):add(vec3(0, 3, 0))
    local tlState = side.tlState
    renderQuad(pos, -side.entryDir, tlState == IntersectionLink.StateGreen and _colors.greenActive or _colors.greenInactive)
    renderQuad(pos:add(vec3(0, 0.5, 0)), -side.entryDir, (tlState == IntersectionLink.StateYellow or tlState == IntersectionLink.StateRedYellow) and _colors.yellowActive or _colors.yellowInactive)
    renderQuad(pos:add(vec3(0, 0.5, 0)), -side.entryDir, (tlState == IntersectionLink.StateRed or tlState == IntersectionLink.StateRedYellow) and _colors.redActive or _colors.redInactive)
  end
end

return class.emmy(TrafficLight, TrafficLight.initialize)
