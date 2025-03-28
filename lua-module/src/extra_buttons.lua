--[[
  Adds extra hotkeys (currently only for pausing).
]]

--[[
TODO:
__CM_ONLINE_POLL_YES
__CM_ONLINE_POLL_NO
__CM_DISCORD_REQUEST_ACCEPT
__CM_DISCORD_REQUEST_DENY
]]

if Config:get('MISCELLANEOUS', 'DISABLE_CM_HOTKEYS', false) then
  return
end

-- ui.onDriverNameTag(true, rgbm.colors.transparent, function (car)
--   ui.drawRectFilled(0, ui.windowSize(), rgbm.colors.red)
--   ui.text(car:driverName())
-- end, { mainSize = 4 })

local buttons = {} ---@type {button: ac.ControlButton, action: fun(), delayed: {label: string, icon: string, condition: nil|fun(): boolean}?}[]
local buttonsCount = 0
local delayActive = false
local delayShowProgress = false
local displayToggle

---@param button ac.ControlButton
---@param action fun()
---@param delayed {label: string, icon: string, condition: nil|fun(): boolean}?
local function addButton(button, action, delayed)
  if button:configured() then
    buttonsCount = buttonsCount + 1
    buttons[buttonsCount] = {button = button, action = action, delayed = delayActive and delayed or nil}
  end
end

local msgs = {}
local function log(str)
  if #msgs > 50 then
    table.remove(msgs, 1)
  end
  msgs[#msgs + 1] = str
end 

if Config:get('MISCELLANEOUS', 'DEBUG_SYSTEM_KEYBINDINGS', false) then
  ui.onExclusiveHUD(function (mode)
    ui.text(table.concat(msgs, '\n'))
  end)
end

for k, v in pairs{
  HIDE_APPS = 'Hide Show Apps',
  HIDE_DAMAGE = 'Hide Damage',
  SHOW_DAMAGE = 'Show Damage',
  DRIVER_NAMES = 'Driver Names',
  IDEAL_LINE = 'Ideal Line',
  START_REPLAY = 'Start Replay',
  PAUSE_REPLAY = 'Pause Replay',
  NEXT_LAP = 'Next Lap',
  PREVIOUS_LAP = 'Previous Lap',
  NEXT_CAR = 'Next Car',
  PLAYER_CAR = 'Player Car',
  PREVIOUS_CAR = 'Previous Car',
  MOUSE_STEERING = 'Mouse Steering',
  ACTIVATE_AI = 'Activate AI',
  RESET_RACE = 'Reset Race',
  AUTO_SHIFTER = 'Auto Shifter',
  SLOWMO = 'SLOWMO',
  FFWD = 'FFWD',
  REV = 'REV',
  ABS = 'ABS',
  TRACTION_CONTROL = 'Traction Control',
  __CM_ENGINE_BRAKE = 'Engine Brake',
  __CM_NEXT_APPS_DESKTOP = 'Cycle Virtual Desktop',
} do
  local btn = ac.ControlButton(k, nil, k:startsWith('__') and {system = 'shift'} or {remap = true})
  log(string.format('System binding: %s, configured: %s, bound to: %s', k, btn:configured(), btn:boundTo()))
  btn:onPressed((function (id, shift)
    local s = ac.trySimKeyPressCommand(id, shift == true)
    log('System binding pressed: %s, %s' % {id, s})
  end):bind(v))
end

ac.ControlButton('__CM_RESET_CAMERA_VR', nil, {remap = true}):onPressed(ac.recenterVR)
ac.ControlButton('__CM_ABS_DECREASE', nil, {remap = true}):onPressed(function ()
  ac.setABS(Car.absMode == 0 and Car.absModes or Car.absMode - 1)
end)
ac.ControlButton('__CM_TRACTION_CONTROL_DECREASE', nil, {remap = true}):onPressed(function ()
  ac.setTC(Car.tractionControlMode == 0 and Car.tractionControlModes or Car.tractionControlMode - 1)
end)
ac.ControlButton('__CM_ENGINE_BRAKE_DECREASE', nil, {remap = true}):onPressed(function ()
  ac.setEngineBrakeSetting(Car.currentEngineBrakeSetting == 0 and Car.engineBrakeSettingsCount or Car.currentEngineBrakeSetting - 1)
end)
ac.ControlButton('__CM_MGU_2', nil, {system = 'shift'}):onPressed(function ()
  local u = ac.getUI()
  ac.setMGUKRecovery(u.shiftDown and (Car.mgukRecovery == 0 and 10 or Car.mgukRecovery - 1) or (Car.mgukRecovery + 1) % 11)
end)
ac.ControlButton('__CM_MGU_2_DECREASE', nil, {remap = true}):onPressed(function ()
  ac.setMGUKRecovery(Car.mgukRecovery == 0 and 10 or Car.mgukRecovery - 1)
end)
ac.ControlButton('__CM_MGU_1', nil, {system = 'shift'}):onPressed(function ()
  local u = ac.getUI()
  if Car.mgukDeliveryCount > 1 then
    ac.setMGUKDelivery((u.shiftDown and (Car.mgukDelivery <= 0 and Car.mgukDeliveryCount - 1 or Car.mgukDelivery - 1) or Car.mgukDelivery + 1) % Car.mgukDeliveryCount)
  end
end)
ac.ControlButton('__CM_MGU_1_DECREASE', nil, {remap = true}):onPressed(function ()
  if Car.mgukDeliveryCount > 1 then
    ac.setMGUKDelivery((Car.mgukDelivery <= 0 and Car.mgukDeliveryCount - 1 or Car.mgukDelivery - 1) % Car.mgukDeliveryCount)
  end
end)
ac.ControlButton('__CM_MGU_3', nil, {system = true}):onPressed(function ()
  ac.setMGUHCharging(not Car.mguhChargingBatteries)
end)

local function checkIfDelayIsActive(controls)
  if not controls:get('__EXTRA_CM', 'DELAY_SPECIFIC_SYSTEM_COMMANDS', true) then
    return false
  end
  if ac.INIConfig.videoConfig():get('VIDEO', 'FULLSCREEN', true)
    and ac.INIConfig.raceConfig():get('HEADER', '__CM_FEATURE_SET', 0) < 1 then
    return false
  end
  return true
end

local function refreshButtons()
  local controls = ac.INIConfig.controlsConfig()
  delayActive = checkIfDelayIsActive(controls)
  delayShowProgress = delayActive and controls:get('__EXTRA_CM', 'SHOW_SYSTEM_DELAYS', true)
  if delayShowProgress and displayToggle == nil then
    displayToggle = Toggle.DrawUI()
  end

  buttonsCount = 0
  local pauseBtn = ac.ControlButton('__EXT_SIM_PAUSE', ac.GamepadButton.Start, { gamepad = true }):setAlwaysActive(true)
  addButton(pauseBtn, function ()
    if Sim.isInMainMenu then
      ac.tryToStart()
    else
      ac.tryToPause(not Sim.isPaused)
    end
  end)
  addButton(ac.ControlButton('__CM_PAUSE'):setAlwaysActive(true), function () ac.tryToPause(not Sim.isPaused) end)
  addButton(ac.ControlButton('__CM_EXIT', nil, { system = true }):setAlwaysActive(true), ac.shutdownAssettoCorsa, {label = 'Exit the race…', icon = ui.Icons.Exit})
  addButton(ac.ControlButton('__CM_TO_PITS', nil, { system = true }), ac.tryToTeleportToPits, {label = 'Teleport to pits…', icon = ui.Icons.PitStopAlt})
  addButton(ac.ControlButton('__CM_RESET_SESSION', nil, { system = true }):setAlwaysActive(true), ac.tryToRestartSession, {label = 'Restart session…', icon = ui.Icons.Restart})
  addButton(ac.ControlButton('__CM_START_SESSION', nil, { system = true }):setAlwaysActive(true), ac.tryToStart)
  addButton(ac.ControlButton('__CM_START_STOP_SESSION', nil, { system = true }):setAlwaysActive(true), function ()
    if Sim.isInMainMenu then
      ac.tryToStart()
    else
      ac.tryToTeleportToPits()
      setTimeout(ac.tryToOpenRaceMenu)
    end
  end, {label = 'Setup in pits…', icon = ui.Icons.PitStopAlt, condition = function ()
    return not Sim.isInMainMenu
  end })
  addButton(ac.ControlButton('__CM_SETUP_CAR', nil, { system = true }), function ()
    ac.tryToTeleportToPits()
    setTimeout(ac.tryToOpenRaceMenu)
  end, {label = 'Setup in pits…', icon = ui.Icons.PitStopAlt})
end

refreshButtons()
ac.onControlSettingsChanged(refreshButtons)

local delayCurrent
local delayProgress = 0
local delayDisplay
local delayDisplayAlpha = 0
local delayDisplayProgress = 0
local ignoreUntilReleased

Register('core', function (dt)
  local delayProcessing = false
  for i = 1, buttonsCount do
    local button = buttons[i]
    if button == ignoreUntilReleased then
      if not button.button:down() then
        ignoreUntilReleased = nil
      end
    elseif button.delayed and (not button.delayed.condition or button.delayed.condition()) then
      if button.button:down() then
        if delayCurrent ~= button then
          delayCurrent = button
          delayProgress = 0
        elseif delayProgress ~= -1 then
          delayProgress = delayProgress + dt * 2.1
          if delayProgress > 1 then
            ignoreUntilReleased = button
            delayProgress = -1
            button.action()
          end
        end
        delayProcessing = true
      end
    elseif button.button:pressed() then
      ignoreUntilReleased = button
      button.action()
    end
  end

  if delayCurrent and not delayProcessing then
    delayCurrent = nil
    delayProgress = 0
  end

  if delayCurrent and delayProgress ~= -1 or delayDisplayAlpha > 0.001 then
    if delayCurrent then 
      delayDisplay = delayCurrent.delayed
      delayDisplayProgress = delayProgress
    end
    delayDisplayAlpha = math.applyLag(delayDisplayAlpha, (delayCurrent and delayProgress ~= -1) and 1 or 0, 0.8, dt)
    displayToggle(delayDisplayAlpha > 0.001)
  end
end)

if delayShowProgress then
  Register('drawUI', function (dt)
    if delayDisplayAlpha <= 0.001 then return end
    local w = ui.windowWidth() / 2 - 120
    local h = ui.windowHeight() - 140
    ui.pushStyleVarAlpha(delayDisplayAlpha)
    ui.pushFont(ui.Font.Title)
    ui.beginOutline()
    local i = vec2(w + (300 - ui.measureText(delayDisplay.label).x) / 2 - 22, h + 22)
    ui.pathArcTo(i, 12, -math.pi / 2, -math.pi / 2 - math.abs(delayDisplayProgress) * math.pi * 2, 20)
    ui.pathStroke(rgbm.colors.white, false, 2)
    ui.drawIcon(delayDisplay.icon or ui.Icons.List, i - 6, i + 6, rgbm.colors.white)
    ui.drawTextClipped(delayDisplay.label, vec2(w, h), vec2(w + 300, h + 40), rgbm.colors.white, vec2(0.5, 0.5))
    ui.endOutline(rgbm.colors.black)
    ui.popFont()
    ui.popStyleVar()
  end)
end
