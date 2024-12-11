--[[
  Library with some extra features for sampling advanced parameters of physisc surfaces.

  To use, include with `local surfaces = require('shared/sim/surfaces')`.
]]
---@diagnostic disable

local surfaces = {
}

---Casts a ray and checks type of underlying surface.
---@param pos vec3 @Raycast origin.
---@param dir vec3? @Raycast direction. Default value: `vec3(0, -1, 0)`. Doesn’t have to be normalized.
---@param length number? @Raycast distance. Default value: `10`.
---@return nil|'default'|'extraturf'|'grass'|'gravel'|'kerb'|'old'|'sand'|string @Returns `nil` if there is no hit. New types might be added later.
function surfaces.raycastType(pos, dir, length)
  local r = __util.native('physics.raycastTrackSurface.type', pos, dir, length)
  if r == 1 then return 'extraturf' end
  if r == 2 then return 'grass' end
  if r == 3 then return 'gravel' end
  if r == 4 then return 'kerb' end
  if r == 5 then return 'old' end
  if r == 6 then return 'sand' end
  return 'default'
end

return surfaces