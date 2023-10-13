--[[
  Some helping utilities for dealing with car physics. Examples:

  • Get value for selected tyres from “tyres.ini”:

    local carsUtils = require('shared/sim/cars')
    carsUtils.getTyreConfigValue(0, true, 'ANGULAR_INERTIA', 1.05)

  • Get thermal value for selected tyres from “tyres.ini”:

    local carsUtils = require('shared/sim/cars')
    carsUtils.getTyreThermalConfigValue(0, true, 'SURFACE_TRANSFER', 0.01)
]]

local tyresCache = {}

local function getTyreConfigSection(car, prefix)
  local i = car and car.compoundIndex or 0
  return i == 0 and prefix or prefix..'_'..i
end

local function initCarEntry(carIndex)
  return {ac.getCar(carIndex), ac.INIConfig.carData(carIndex, 'tyres.ini')}
end

-- Actual library:
local carsUtils = {}

---Get value from “tyres.ini” for a certain car for currently selected set of tyres.
---@generic T
---@param carIndex integer @0-based car index.
---@param frontTyres boolean @Set to `true` for front tyres or `false` for rear tyres.
---@param key string @Parameter key.
---@param defaultValue T @Default parameter value in case config is damaged or unavailable.
---@return T
function carsUtils.getTyreConfigValue(carIndex, frontTyres, key, defaultValue)
  local entry = table.getOrCreate(tyresCache, carIndex, initCarEntry, carIndex)
  return entry[2]:get(getTyreConfigSection(entry[1], frontTyres and 'FRONT' or 'REAR'), key, defaultValue)
end

---Get thermal value from “tyres.ini” for a certain car for currently selected set of tyres.
---@generic T
---@param carIndex integer @0-based car index.
---@param frontTyres boolean @Set to `true` for front tyres or `false` for rear tyres.
---@param key string @Parameter key.
---@param defaultValue T @Default parameter value in case config is damaged or unavailable.
---@return T
function carsUtils.getTyreThermalConfigValue(carIndex, frontTyres, key, defaultValue)
  local entry = table.getOrCreate(tyresCache, carIndex, initCarEntry, carIndex)
  return entry[2]:get(getTyreConfigSection(entry[1], frontTyres and 'THERMAL_FRONT' or 'THERMAL_REAR'), key, defaultValue)
end

return carsUtils