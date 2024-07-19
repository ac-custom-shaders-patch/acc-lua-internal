--[[
  Adds support for extra features of DualSense and DualShock controllers. Sets state with low priority 
  so that other apps could override the state.
]]

if not ConfigGamepadFX then
  return
end

local function implementation()
  local settings = ConfigGamepadFX:mapSection('ADVANCED_GAMEPADS', {
    ENABLED = true,
    SHIFTING_COLORS = 'SMOOTH',
    SESSION_START = true,
    EXTRA_COLORS = true,
    BACKGROUND_COLORS = true,
    MOUSE_PAD = true,
    LOW_BATTERY_WARNING = true,
  })
  
  if not settings.ENABLED then
    return
  end
  
  local dualSenseEmulator = ac.connect({
    ac.StructItem.key('dualSenseEmulator'),
    available = ac.StructItem.boolean(),
    batteryCharging = ac.StructItem.boolean(),
    batteryCharge = ac.StructItem.float(),
    carIndex = ac.StructItem.int32(),
    touch1Pos = ac.StructItem.vec2(),
    touch2Pos = ac.StructItem.vec2(),
    lightBarColor = ac.StructItem.rgbm()
  }, false, ac.SharedNamespace.Global)
  
  local carInfo = {}
  local flashing = 0
  
  ---@alias CarInfo {state: ac.StateCar, rpmUp: number, rpmDown: number, fuelWarning: number}
  ---@return CarInfo
  local function getCarInfo(carIndex)
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
  
  local dualSensePadOverride = ac.connect({
    ac.StructItem.key('dualSensePadOverride'),
    override = ac.StructItem.boolean()
  }, false, ac.SharedNamespace.Shared)
  
  local colorBase = rgbm(0, 0, 0, 1)
  local colorShifting = rgbm(0, 0, 0, 1)
  local drawBatteryIcon = settings.LOW_BATTERY_WARNING and Toggle.DrawUI()
  
  ---@return rgbm
  local function computeReplayColor()
    local sceneColor = Sim.skyColor + Sim.lightColor
    local sceneColorBrightness = sceneColor:value()
    if sceneColorBrightness > 1 then
      sceneColor:scale(1 / sceneColorBrightness)
    end
    return sceneColor:rgbm(1)
  end
  
  ---@param info CarInfo
  ---@param color rgbm
  local function computeHighlightColor(info, color)
    if Sim.isReplayActive then
      if settings.BACKGROUND_COLORS then
        color:set(computeReplayColor())
      end
      return
    end
    
    local car = info.state
    local rpm = (car.rpm - info.rpmDown) / (info.rpmUp - info.rpmDown)
  
    -- Colors highlighting shifting stage
    if settings.SESSION_START and Sim.timeToSessionStart > -1e3 then
      if Sim.timeToSessionStart > 0 then
        color:set(Sim.timeToSessionStart < 6.7e3 and rgbm.colors.red or rgbm.colors.transparent)
      else
        color:set(flashing * 3 % 1 > 0.5 and rgbm.colors.green or rgbm.colors.transparent)
      end
    elseif settings.EXTRA_COLORS and car.gear == -1 then
      color:set(rgbm.colors.white)
    elseif settings.EXTRA_COLORS and (car.engineLifeLeft < 1 or car.hazardLights) then
      color:set(car.turningLightsActivePhase and rgbm.colors.orange or rgbm.colors.transparent)
    elseif settings.EXTRA_COLORS and car.fuel < info.fuelWarning then
      color:set(rgbm(1, 0.15, 0, 1))
    elseif settings.SHIFTING_COLORS ~= '0' then
      if rpm > 0.9 and (flashing * 3 % 1 > 0.5) then
        color:set(rgbm.colors.transparent)
      else
        if car.headlightsActive and settings.EXTRA_COLORS then
          colorBase.rgb:set(car.headlightsColor):scale(car.lowBeams and 0.1 or 0.2)
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
        else
          color:set(colorBase)
        end
      end
    end
  end
  
  ---@param info CarInfo
  ---@param ds ac.StateDualsenseOutput
  local function updateDualSense(info, ds)
    local car = info.state
    local rpm = (car.rpm - info.rpmDown) / (info.rpmUp - info.rpmDown)
  
    if Sim.isReplayActive then
      rpm = 0
    end
  
    -- LEDs showing RPM bar
    ds.playerLEDsBrightness = rpm > 0.5 and 0 or rpm > 0.25 and 1 or 2
    ds.playerLEDsFade = false
    for i = 0, 4 do
      ds.playerLEDs[i] = rpm > i / 4
    end
  
    -- Colors highlighting shifting stage
    computeHighlightColor(info, ds.lightBar)
  end
  
  ---@param info CarInfo
  ---@param ds ac.StateDualshockOutput
  local function updateDualShock(info, ds)
    -- Colors highlighting shifting stage
    computeHighlightColor(info, ds.lightBar)
  end
  
  local minBatteryLevel = 1
  local anyPadWasPressed = false
  
  local function mouseControlGen(padPressed, touch1Delta, touch2Delta, touch1Down, touch2Down)
    local ret = false
    if settings.MOUSE_PAD and not dualSensePadOverride.override then
      for i = 0, 1 do
        if i == 0 and touch1Down or touch2Down then
          if i == 0 and touch2Down then
            ac.setMouseWheel((touch1Delta.y + touch2Delta.y) * 50)
          else
            ac.setMousePosition((UI.mousePos + UI.windowSize * (i == 0 and touch1Delta or touch2Delta) * vec2(0.5, 1)) * UI.uiScale)
          end
          ret = ret or padPressed
          break
        end
      end
    end
    return ret
  end
  
  ---@param state ac.StateDualshock|ac.StateDualsense
  local function mouseControl(controllerIndex, state)
    return mouseControlGen(ac.isGamepadButtonPressed(controllerIndex, ac.GamepadButton.Pad),
      state.touches[0].delta, state.touches[1].delta, state.touches[0].down, state.touches[1].down)
  end
  
  local constZeroV2 = vec2()
  local dsePrevPressed = false
  local dsePrevPos = vec2()
  local dsePrevTime = 0
  
  local function mouseControlDse(point1, point2)
    local d1 = point1.x ~= 0 or point1.y ~= 0
    local delta = constZeroV2
    local pressed = false
    if d1 then
      local target = dsePrevPressed and (dsePrevPos + point1):scale(0.5) or point1
      if dsePrevPressed then delta = vec2(2, 1):mul(target - dsePrevPos) end
      dsePrevPos = target
    end
    if dsePrevPressed ~= d1 then
      dsePrevPressed = d1
      if not dsePrevPressed and ui.time() - dsePrevTime < 0.5 then
        d1 = true
        pressed = true
      end
      dsePrevTime = ui.time()
    end
    return mouseControlGen(pressed, delta, constZeroV2, d1, false)
  end
  
  Register('core', function (dt)
    if not Sim.isPaused then
      flashing = flashing + dt
      if flashing > 1 then
        flashing = flashing - 1
      end
    end
  
    minBatteryLevel = 1
    local anyPadPressed = false
  
    for controllerIndex, carIndex in pairs(ac.getDualSenseControllers()) do
      local state = ac.getDualSense(controllerIndex)
      if state and state.connected then
        updateDualSense(getCarInfo(carIndex), ac.setDualSense(controllerIndex, -1000))
  
        if drawBatteryIcon and not state.batteryCharging then
          minBatteryLevel = math.min(minBatteryLevel, state.battery == 0 and 1 or state.battery)
        end
  
        -- Pad moves mouse
        anyPadPressed = mouseControl(controllerIndex, state) or anyPadPressed
      end
    end
  
    for controllerIndex, carIndex in pairs(ac.getDualShockControllers()) do
      local state = ac.getDualShock(controllerIndex)
      if state and state.connected then
        updateDualShock(getCarInfo(carIndex), ac.setDualShock(controllerIndex, -1000))
  
        if drawBatteryIcon then
          minBatteryLevel = math.min(minBatteryLevel, state.battery == 0 and 1 or state.battery)
        end
  
        -- Pad moves mouse
        anyPadPressed = mouseControl(controllerIndex, state) or anyPadPressed
      end
    end
  
    local dse = dualSenseEmulator
    if dse.available then
      ac.broadcastSharedEvent('$SmallTweaks.RefreshDSEData')
      computeHighlightColor(getCarInfo(dse.carIndex), dse.lightBarColor)
  
      if drawBatteryIcon and not dse.batteryCharging then
        minBatteryLevel = math.min(minBatteryLevel, dse.batteryCharge == 0 and 1 or dse.batteryCharge)
      end
      
      -- Pad moves mouse
      anyPadPressed = mouseControlDse(dse.touch1Pos, dse.touch2Pos) or anyPadPressed
    end
  
    if anyPadWasPressed ~= anyPadPressed then
      anyPadWasPressed = anyPadPressed
      ac.setMouseLeftButtonDown(anyPadPressed)
    end
  
    drawBatteryIcon(minBatteryLevel < 0.2)
  end)
  
  if settings.LOW_BATTERY_WARNING then
    Register('drawGameUI', function (dt)
      if minBatteryLevel < 0.2 then
        ui.drawCarIcon('?internal\\lua-module\\res\\controller-battery.png', minBatteryLevel < 0.05 and rgbm.colors.red
          or minBatteryLevel < 0.1 and rgbm.colors.orange or rgbm.colors.yellow)
      end
    end)
  end  
end

local anyDualSense = next(ac.getDualSenseControllers()) ~= nil
local anyDualShock = next(ac.getDualShockControllers()) ~= nil

if ConfigGamepadFX:get('BASIC', 'ENABLED', true) then
  if anyDualSense or anyDualShock or ac.load('$SmallTweaks.DSEmulatorAvailable') then
    implementation()
  else
    local listener
    listener = ac.onSharedEvent('$SmallTweaks.DSAnyAvailable', function ()
      listener()
      implementation()
    end)
  end
end
