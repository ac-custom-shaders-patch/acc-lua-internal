--[[
  Some helping utilities for working with weather conditions. Examples:

  • Estimate rain intensity for a certain weather type:

    local weatherUtils = require('shared/sim/weather')
    weatherUtils.estimateRainIntensity(ac.WeatherType.Drizzle)

  • Estimate road temperature based on air temperature for a certain weather type:

    local weatherUtils = require('shared/sim/weather')
    weatherUtils.estimateRoadTemperature(ac.WeatherType.Windy, 22, 12 * 60 * 60)

  • Support weather type override of CSP Debug App:

    local weatherUtils = require('shared/sim/weather')
    weatherUtils.debugAware(conditions)
]]
---@diagnostic disable

local rainIntensities = {}
rainIntensities[ac.WeatherType.Clear] =             0
rainIntensities[ac.WeatherType.FewClouds] =         0
rainIntensities[ac.WeatherType.ScatteredClouds] =   0
rainIntensities[ac.WeatherType.BrokenClouds] =      0
rainIntensities[ac.WeatherType.OvercastClouds] =    0
rainIntensities[ac.WeatherType.Windy] =             0
rainIntensities[ac.WeatherType.Fog] =               0
rainIntensities[ac.WeatherType.Mist] =              0
rainIntensities[ac.WeatherType.Haze] =              0
rainIntensities[ac.WeatherType.Dust] =              0
rainIntensities[ac.WeatherType.Smoke] =             0
rainIntensities[ac.WeatherType.Sand] =              0
rainIntensities[ac.WeatherType.LightDrizzle] =      0.01
rainIntensities[ac.WeatherType.Drizzle] =           0.02
rainIntensities[ac.WeatherType.HeavyDrizzle] =      0.03
rainIntensities[ac.WeatherType.LightRain] =         0.05
rainIntensities[ac.WeatherType.Rain] =              0.1
rainIntensities[ac.WeatherType.HeavyRain] =         0.2
rainIntensities[ac.WeatherType.LightThunderstorm] = 0.3
rainIntensities[ac.WeatherType.Thunderstorm] =      0.5
rainIntensities[ac.WeatherType.HeavyThunderstorm] = 0.6
rainIntensities[ac.WeatherType.Squalls] =           0
rainIntensities[ac.WeatherType.Tornado] =           0.8
rainIntensities[ac.WeatherType.Hurricane] =         1.0
rainIntensities[ac.WeatherType.LightSnow] =         0
rainIntensities[ac.WeatherType.Snow] =              0
rainIntensities[ac.WeatherType.HeavySnow] =         0
rainIntensities[ac.WeatherType.LightSleet] =        0
rainIntensities[ac.WeatherType.Sleet] =             0.05
rainIntensities[ac.WeatherType.HeavySleet] =        0.1
rainIntensities[ac.WeatherType.Hail] =              0.2

-- Values are taken from Sol weathers
local roadTemperatureCoefficients = {}
roadTemperatureCoefficients[ac.WeatherType.Clear] =              1.0
roadTemperatureCoefficients[ac.WeatherType.FewClouds] =          1.0
roadTemperatureCoefficients[ac.WeatherType.ScatteredClouds] =    0.8
roadTemperatureCoefficients[ac.WeatherType.BrokenClouds] =       0.1
roadTemperatureCoefficients[ac.WeatherType.OvercastClouds] =     0.01
roadTemperatureCoefficients[ac.WeatherType.Windy] =              0.3
roadTemperatureCoefficients[ac.WeatherType.Fog] =               -0.3
roadTemperatureCoefficients[ac.WeatherType.Mist] =              -0.2
roadTemperatureCoefficients[ac.WeatherType.Haze] =               0.9
roadTemperatureCoefficients[ac.WeatherType.Dust] =               1.0
roadTemperatureCoefficients[ac.WeatherType.Smoke] =             -0.2
roadTemperatureCoefficients[ac.WeatherType.Sand] =               1.0
roadTemperatureCoefficients[ac.WeatherType.LightDrizzle] =       0.1
roadTemperatureCoefficients[ac.WeatherType.Drizzle] =           -0.1
roadTemperatureCoefficients[ac.WeatherType.HeavyDrizzle] =      -0.3
roadTemperatureCoefficients[ac.WeatherType.LightRain] =          0.01
roadTemperatureCoefficients[ac.WeatherType.Rain] =              -0.2
roadTemperatureCoefficients[ac.WeatherType.HeavyRain] =         -0.5
roadTemperatureCoefficients[ac.WeatherType.LightThunderstorm] =  0.7
roadTemperatureCoefficients[ac.WeatherType.Thunderstorm] =       0.2
roadTemperatureCoefficients[ac.WeatherType.HeavyThunderstorm] = -0.2
roadTemperatureCoefficients[ac.WeatherType.Squalls] =           -0.5
roadTemperatureCoefficients[ac.WeatherType.Tornado] =           -0.3
roadTemperatureCoefficients[ac.WeatherType.Hurricane] =         -0.7
roadTemperatureCoefficients[ac.WeatherType.LightSnow] =         -0.7
roadTemperatureCoefficients[ac.WeatherType.Snow] =              -0.8
roadTemperatureCoefficients[ac.WeatherType.HeavySnow] =         -0.9
roadTemperatureCoefficients[ac.WeatherType.LightSleet] =        -1.0
roadTemperatureCoefficients[ac.WeatherType.Sleet] =             -1.0
roadTemperatureCoefficients[ac.WeatherType.HeavySleet] =        -1.0
roadTemperatureCoefficients[ac.WeatherType.Hail] =              -1.0

-- Actual library:
local weatherUtils = {}

---Returns string describing given rain intensity.
---@param intensity number
---@return string
function weatherUtils.rainDescription(intensity)
  if intensity < 0.001 then return "None" end
  if intensity < 0.02 then return "Drizzle" end
  if intensity < 0.07 then return "Light rain" end
  if intensity < 0.15 then return "Extended shower" end
  if intensity < 0.3 then return "Brief thundershower" end
  if intensity < 0.6 then return "Heavy downpour" end
  return "Severe storm"
end

---Estimate rain intensity (in 0…1 range) for a certain weather type.
---@param weatherType ac.WeatherType
---@return number
function weatherUtils.estimateRainIntensity(weatherType)
  return rainIntensities[weatherType] or 0
end

---Update rain intensity in conditions based on weather type and transition value.
---Set `setWaterLevel` to `true` to update puddles amount as well (however, results
---will be better if you were to accumulate it manually based on rain intensity).
---@param conditions ac.ConditionsSet @Conditions to update.
---@param setWaterLevel boolean? @Default value: `false`.
function weatherUtils.setRainIntensity(conditions, setWaterLevel)
  local currentRain = weatherUtils.estimateRainIntensity(conditions.currentType)
  local upcomingRain = weatherUtils.estimateRainIntensity(conditions.upcomingType)
  conditions.rainIntensity = math.lerp(currentRain, upcomingRain, conditions.transition)
  conditions.rainWetness = conditions.rainIntensity
  if setWaterLevel then
    conditions.rainWater = math.sqrt(conditions.rainIntensity)
  end
end

---Estimate road temperature based on weather type, ambient temperature and current time of day using
---the same formula Kunos uses in AC Server Manager.
---@param weatherType ac.WeatherType @Weather type.
---@param ambientTemperature number @Ambient temperature in °C.
---@param timeOfDaySeconds number @Time of day in seconds from midnight.
---@return number @Road temperature in °C.
function weatherUtils.estimateRoadTemperature(weatherType, ambientTemperature, timeOfDaySeconds)
  -- Based on a formula used by original AC Server Manager
  local weatherCoefficient = roadTemperatureCoefficients[weatherType] or 1
  local time = math.clamp((timeOfDaySeconds / 3600 - 7) / 24, 0, 0.5) * math.lerpInvSat(timeOfDaySeconds / 3600, 24, 18)
  return ambientTemperature * (1 + 5.33332 * weatherCoefficient * (1 - time) *
      (math.exp(-6 * time) * math.sin(6 * time) + 0.25) * math.sin(0.9 * time))
end

---Update road temperature in conditions based on weather type and transition value.
---@param conditions ac.ConditionsSet @Conditions to update.
---@param timeOfDaySeconds number? @Time of day in seconds from midnight (uses current time by default).
function weatherUtils.setRoadTemperature(conditions, timeOfDaySeconds)
  timeOfDaySeconds = timeOfDaySeconds or ac.getDaySeconds()
  local current = weatherUtils.estimateRoadTemperature(conditions.currentType, conditions.temperatures.ambient, timeOfDaySeconds)
  local upcoming = weatherUtils.estimateRoadTemperature(conditions.upcomingType, conditions.temperatures.ambient, timeOfDaySeconds)
  conditions.temperatures.road = math.lerp(current, upcoming, conditions.transition)
end

local weatherDebug = nil
local weatherDebugExt = nil

---Sync weather type with custom weather type selected in CSP Debug App (in case you want to 
---support that dropdown list).
---@param conditions ac.ConditionsSet @Fields `currentType` and `upcomingType` might be updated.
---@param version integer? @Pass `1` to set other parameters, not just the weather type. Default value: `0`.
---@return boolean @Returns `true` if custom weather type is set.
function weatherUtils.debugAware(conditions, version)
  if not weatherDebug then
    weatherDebug = ac.connect({
      ac.StructItem.key('weatherFXDebugOverride'),
      weatherType = ac.StructItem.byte(),
      debugSupported = ac.StructItem.boolean()
    })
    weatherDebugExt = ac.connect({
      ac.StructItem.key('weatherFXDebugOverride.1'),
      windDirection = ac.StructItem.float(),
      windSpeedFrom = ac.StructItem.float(),
      windSpeedTo = ac.StructItem.float(),
      humidity = ac.StructItem.float(),
      pressure = ac.StructItem.float(),
      rainIntensity = ac.StructItem.float(),
      rainWetness = ac.StructItem.float(),
      rainWater = ac.StructItem.float(),
    })
    weatherDebug.debugSupported = true
    weatherDebug.weatherType = 255
    ac.onRelease(function ()
      weatherDebug.debugSupported = false
    end)
  end

  weatherDebug.debugSupported = true
  if weatherDebug.weatherType == 255 then
    return false
  end

  conditions.currentType = weatherDebug.weatherType
  conditions.upcomingType = weatherDebug.weatherType
  if (version or 0) >= 1 then
    conditions.wind.direction = weatherDebugExt.windDirection
    conditions.wind.speedFrom = weatherDebugExt.windSpeedFrom
    conditions.wind.speedTo = weatherDebugExt.windSpeedTo
    conditions.humidity = weatherDebugExt.humidity
    conditions.pressure = weatherDebugExt.pressure
    conditions.rainIntensity = weatherDebugExt.rainIntensity
    conditions.rainWetness = weatherDebugExt.rainWetness
    conditions.rainWater = weatherDebugExt.rainWater
  end
  return true
end

return weatherUtils
