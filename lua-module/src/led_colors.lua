local carInfo = {}
---@alias CarInfo {state: ac.StateCar, rpmUp: number, rpmDown: number, fuelWarning: number}
---@return CarInfo
function GetCarInfo(carIndex)
  local ret = carInfo[carIndex]
  if not ret then
    local aiIni = ac.INIConfig.carData(carIndex, 'ai.ini')
    local carIni = ac.INIConfig.carData(carIndex, 'car.ini')
    ret = {
      state = ac.getCar(carIndex),
      rpmUp = aiIni:get('GEARS', 'UP', 9000),
      rpmDown = math.max(aiIni:get('GEARS', 'DOWN', 6000), aiIni:get('GEARS', 'UP', 9000) / 2),
      fuelWarning = carIni:get('GRAPHICS', 'FUEL_LIGHT_MIN_LITERS', 0)
    }
    carInfo[carIndex] = ret
  end
  return ret
end

---@return rgbm
local function computeReplayColor()
  local sceneColor = math.convertHDR(Sim.skyColor + Sim.lightColor)
  local sceneColorBrightness = sceneColor:value()
  if sceneColorBrightness > 1 then
    sceneColor:scale(1 / sceneColorBrightness)
  end
  return sceneColor:rgbm(1)
end

local flashing = -1

local function getFlashing()
  if flashing == -1 then
    flashing = 0
    Register('core', function(dt)
      if not Sim.isPaused then
        flashing = flashing + dt
        if flashing > 1 then
          flashing = flashing - 1
        end
      end
    end)
  end
  return flashing
end

local colorBase = rgbm(0, 0, 0, 1)
local colorShifting = rgbm(0, 0, 0, 1)

---@param info CarInfo
---@param lowBattery boolean
---@param settings {LOW_BATTERY_WARNING: boolean, BACKGROUND_COLORS: boolean, SESSION_START: boolean, EXTRA_COLORS: boolean, SHIFTING_COLORS: '0'|'1'|'SMOOTH'}
---@param color rgbm @Output value
function ComputeHighlightColor(info, lowBattery, settings, color, noHeadlightColor)
  if lowBattery and settings.LOW_BATTERY_WARNING then
    color:set(os.preciseClock() % 1 > 0.5 and rgbm.colors.red or rgbm.colors.black)
    return true
  end

  if Sim.isReplayActive then
    if settings.BACKGROUND_COLORS then
      color:set(computeReplayColor())
    else
      color:scale(0)
    end
    return false
  end

  local car = info.state
  local rpm = (car.rpm - info.rpmDown) / (info.rpmUp - info.rpmDown)
  local any = false

  -- Colors highlighting shifting stage
  if settings.SESSION_START and Sim.timeToSessionStart > -1e3 then
    if Sim.timeToSessionStart > 0 then
      color:set(Sim.timeToSessionStart < 6.7e3 and rgbm.colors.red or rgbm.colors.transparent)
    else
      color:set(getFlashing() * 3 % 1 > 0.5 and rgbm.colors.green or rgbm.colors.transparent)
    end
    any = true
  elseif settings.EXTRA_COLORS and car.gear == -1 then
    color:set(rgbm.colors.white)
    any = true
  elseif settings.EXTRA_COLORS and (car.engineLifeLeft < 1 or car.hazardLights) then
    color:set(car.turningLightsActivePhase and rgbm.colors.orange or rgbm.colors.transparent)
    any = true
  elseif settings.EXTRA_COLORS and car.fuel < info.fuelWarning then
    color:set(rgbm(1, 0.15, 0, 1))
    any = true
  elseif settings.EXTRA_COLORS and car.anyFlamesActive then
    color:set(rgbm.colors.yellow)
    any = true
  elseif settings.SHIFTING_COLORS ~= '0' then
    if rpm > 0.9 and (getFlashing() * 3 % 1 > 0.5) then
      color:set(rgbm.colors.transparent)
      any = true
    else
      if car.headlightsActive and settings.EXTRA_COLORS and not noHeadlightColor then
        colorBase.rgb:set(car.headlightsColor):scale(car.lowBeams and 0.1 or 0.2)
        any = true
      elseif colorBase.rgb.r > 0 or colorBase.rgb.g > 0 or colorBase.rgb.b > 0 then
        colorBase.rgb:scale(0)
      end
      local mix = math.saturateN(rpm * 2 + 1)
      if mix > 0 then
        local isSmooth = settings.SHIFTING_COLORS == 'SMOOTH'
        colorShifting.rgb = isSmooth
            and hsv(90 * math.saturateN(1 - rpm), 1, 1):rgb()
            or (rpm > 0.6 and rgb.colors.red or rpm > 0.2 and rgb.colors.yellow or rgb.colors.green)
        if isSmooth then
          color:setLerp(colorBase, colorShifting, mix)
        else
          color:set(colorShifting)
        end
        any = true
      else
        color:set(colorBase)
      end
    end
  end
  return any
end
