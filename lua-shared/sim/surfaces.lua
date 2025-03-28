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

local surfacesIni

---@generic T
---@param wheel ac.StateWheel @Car wheel state (for example, `ac.getCar(0).wheels[0]`).
---@param key string @Key of a property from `surfaces.ini`, such as `FRICTION`.
---@param defaultValue T @Default value returned if there is no value with this key, or there is no valid surface.
---@return fun(): T @Call function to get the fresh value.
function surfaces.propertyAccessor(wheel, key, defaultValue)
  local p = -1
  local v = defaultValue
  if not surfacesIni then
    surfacesIni = ac.INIConfig.trackData('surfaces.ini')
  end
  return function ()
    local i = wheel.surfaceSectionIndex
    if i ~= p then
      print(i, key, defaultValue)
      p = i
      v = i >= 0 and surfacesIni:get('SURFACE_%s' % i, key, defaultValue) or defaultValue
    end
    return v
  end
end

return surfaces