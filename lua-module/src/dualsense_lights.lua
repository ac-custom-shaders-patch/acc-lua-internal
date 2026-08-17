--[[
  Adds support for extra features of DualSense and DualShock controllers. Sets state with low priority 
  so that other apps could override the state.
]]

if not ConfigGamepadFX or not ConfigGamepadFX:get('BASIC', 'ENABLED', true) then
  return
end

local MIN_BATTERY_THRESHOLD = const(0.2)

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
  
  print('Gamepad FX enabled:', settings.ENABLED)
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
    
  local dualSensePadOverride = ac.connect({
    ac.StructItem.key('dualSensePadOverride'),
    override = ac.StructItem.boolean()
  }, false, ac.SharedNamespace.Shared)
  
  local lowBattery = false
  local drawBatteryIcon = settings.LOW_BATTERY_WARNING and Toggle.DrawUI()
  
  ---@param info CarInfo
  ---@param ds ac.StateDualsenseOutput?
  local function updateDualSense(info, ds)
    if not ds then return end
    
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
    ComputeHighlightColor(info, lowBattery, settings, ds.lightBar)
  end
  
  ---@param info CarInfo
  ---@param ds ac.StateDualshockOutput?
  local function updateDualShock(info, ds)
    if not ds then return end
    -- Colors highlighting shifting stage
    ComputeHighlightColor(info, lowBattery, settings, ds.lightBar)
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
    minBatteryLevel = 1
    local anyPadPressed = false
  
    for controllerIndex, carIndex in pairs(ac.getDualSenseControllers()) do
      local state = ac.getDualSense(controllerIndex)
      if state and state.connected then
        updateDualSense(GetCarInfo(carIndex), ac.setDualSense(controllerIndex, -1000))
  
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
        updateDualShock(GetCarInfo(carIndex), ac.setDualShock(controllerIndex, -1000))
  
        if drawBatteryIcon and not state.batteryCharging then
          minBatteryLevel = math.min(minBatteryLevel, state.battery == 0 and 1 or state.battery)
        end
  
        -- Pad moves mouse
        anyPadPressed = mouseControl(controllerIndex, state) or anyPadPressed
      end
    end
  
    local dse = dualSenseEmulator
    if dse.available then
      -- ac.broadcastSharedEvent('$SmallTweaks.RefreshDSEData') -- TODO: what does it do?
      ComputeHighlightColor(GetCarInfo(dse.carIndex), lowBattery, settings, dse.lightBarColor)
  
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
  
    lowBattery = minBatteryLevel < MIN_BATTERY_THRESHOLD
    drawBatteryIcon(minBatteryLevel < MIN_BATTERY_THRESHOLD)
  end)
  
  if settings.LOW_BATTERY_WARNING then
    Register('drawGameUI', function (dt)
      if minBatteryLevel < MIN_BATTERY_THRESHOLD then
        ui.drawCarIcon('?internal\\lua-module\\res\\controller-battery.png', minBatteryLevel < 0.05 and rgbm.colors.red
          or minBatteryLevel < 0.1 and rgbm.colors.orange or rgbm.colors.yellow, 'Controller battery is low')
      end
    end)
  end  
end

local anyDualSense = next(ac.getDualSenseControllers()) ~= nil
local anyDualShock = next(ac.getDualShockControllers()) ~= nil

if anyDualSense or anyDualShock or ac.load('$SmallTweaks.DSEmulatorAvailable') then
  implementation()
else
  local listener
  listener = ac.onSharedEvent('$SmallTweaks.DSAnyAvailable', function ()
    listener()
    implementation()
  end)
end