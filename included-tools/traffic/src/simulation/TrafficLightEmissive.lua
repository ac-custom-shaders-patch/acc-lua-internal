local Array = require('Array')
local IntersectionLink = require('IntersectionLink')
local TrafficContext = require('TrafficContext')

local rgbNone = rgb()
local rgbmNone = rgbm(0, 0, 0, 1)

local EmissivePiece = (function ()
  ---@class EmissivePiece : ClassBase
  local EmissivePiece = class('EmissivePiece')

  ---@param mode integer
  ---@param role {mesh: string}|{pos: SerializedVec3, dir: SerializedVec3, radius: number}
  ---@param color rgb
  ---@return EmissivePiece
  function EmissivePiece:initialize(mode, role, color)
    self.active = nil
    self.color = color
    self.colorRgbm = rgbm.new(color, 1)
    if mode == 1 then
      if role.mesh then
        self.ref = ac.findMeshes('{' .. role.mesh .. '}')
        self.ref:ensureUniqueMaterials()
      end
    elseif mode == 2 then
      self.items = Array(role, function (item) return {pos = vec3.new(item.pos), dir = vec3.new(item.dir), radius = item.radius} end)
      TrafficContext.drawCallbacks:push(function () self:draw() end)
    else
      ac.log('Unknown traffic light mode: '..tostring(mode))
    end
  end

  function EmissivePiece:draw()
    if not self.active then return end
    render.setDepthMode(render.DepthMode.Normal)
    for i = 1, #self.items do      
      local item = self.items[i]
      render.circle(item.pos, item.dir, item.radius, self.colorRgbm, rgbmNone)
    end
  end

  function EmissivePiece:set(active)
    if active == self.active then return end
    self.active = active
    if self.ref then
      -- ac.debug('self.ref', self.ref:name(1))
      -- ac.debug('self.color', active and self.color or rgbNone)
      self.ref:setMaterialProperty('ksEmissive', active and self.color or rgbNone)
    end
  end

  return class.emmy(EmissivePiece, EmissivePiece.initialize)
end)()

---@class TrafficLightEmissive : ClassBase
local TrafficLightEmissive = class('TrafficLightEmissive')

---@param side IntersectionSide
---@param params SerializedTrafficLightEmissiveParams
---@return TrafficLightEmissive
function TrafficLightEmissive:initialize(side, params)
  self.side = side

  -- TODO: If default emissive mode is used, `mode` value might be missing. Fallbacking to 1 here, but it’s a bit messy.
  if (params.mode == 1 or params.mode == nil) and params.roles then
    self.red = EmissivePiece(1, params.roles[1], rgb(40, 2, 2))
    self.yellow = EmissivePiece(1, params.roles[2], rgb(40, 30, 2))
    self.green = EmissivePiece(1, params.roles[3], rgb(2, 40, 2))
  elseif params.mode == 2 and params.virtual and params.virtual.items then
    self.red = EmissivePiece(2, table.slice(params.virtual.items, 1, nil, 3), rgb(40, 2, 2))
    self.yellow = EmissivePiece(2, table.slice(params.virtual.items, 2, nil, 3), rgb(40, 30, 2))
    self.green = EmissivePiece(2, table.slice(params.virtual.items, 3, nil, 3), rgb(2, 40, 2))
  else
    ac.log('Unknown traffic light mode: '..tostring(params.mode))
  end

  if params.hide and params.hide.mesh then
    ac.findMeshes(params.hide.mesh):setMaterialProperty('ksEmissive', rgb())
  end

  if params.mode == 1 or params.mode == nil then
  elseif params.mode == 2 then
    self.redPoints = Array(params.roles[1].items, function (item) return {pos = vec3.new(item.pos), dir = vec3.new(item.dir), radius = item.radius} end)
  else
    ac.log('Unknown traffic light mode: '..tostring(params.mode))
  end
end

function TrafficLightEmissive:update()
  if not self.red then return end
  self.red:set(self.side.tlState == IntersectionLink.StateRed or self.side.tlState == IntersectionLink.StateRedYellow)
  self.yellow:set(self.side.tlState == IntersectionLink.StateYellow or self.side.tlState == IntersectionLink.StateRedYellow)
  self.green:set(self.side.tlState == IntersectionLink.StateGreen)
end

return class.emmy(TrafficLightEmissive, TrafficLightEmissive.initialize)