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
  ac.ControlButton(k, nil, {remap = true}):onPressed(ac.trySimKeyPressCommand:bind(v))
end

ac.ControlButton('__CM_RESET_CAMERA_VR', nil, {remap = true}):onPressed(ac.recenterVR)
ac.ControlButton('__CM_ABS_DECREASE', nil, {remap = true}):onPressed(function ()
  local c = ac.getCar(0)
  ac.setABS(c.absMode == 0 and c.absModes or c.absMode - 1)
end)
ac.ControlButton('__CM_TRACTION_CONTROL_DECREASE', nil, {remap = true}):onPressed(function ()
  local c = ac.getCar(0)
  ac.setABS(c.tractionControlMode == 0 and c.tractionControlModes or c.tractionControlMode - 1)
end)
ac.ControlButton('__CM_ENGINE_BRAKE_DECREASE', nil, {remap = true}):onPressed(function ()
  local c = ac.getCar(0)
  ac.setABS(c.currentEngineBrakeSetting == 0 and c.engineBrakeSettingsCount or c.currentEngineBrakeSetting - 1)
end)
ac.ControlButton('__CM_MGU_2', nil, {system = 'ignore'}):onPressed(function ()
  local u, c = ac.getUI(), ac.getCar(0)
  if u.ctrlDown and not u.altDown then
    ac.setMGUKRecovery(u.shiftDown and (c.mgukRecovery == 0 and 10 or c.mgukRecovery - 1) or (c.mgukRecovery + 1) % 11)
  end
end)
ac.ControlButton('__CM_MGU_1', nil, {system = 'ignore'}):onPressed(function ()
  local u, c = ac.getUI(), ac.getCar(0)
  if u.ctrlDown and not u.altDown and c.mgukDeliveryCount > 1 then
    ac.setMGUKDelivery((u.shiftDown and (c.mgukDelivery <= 0 and c.mgukDeliveryCount - 1 or c.mgukDelivery - 1) or c.mgukDelivery + 1) % c.mgukDeliveryCount)
  end
end)
ac.ControlButton('__CM_MGU_3', nil, {system = true}):onPressed(function ()
  local c = ac.getCar(0)
  ac.setMGUHCharging(not c.mguhChargingBatteries)
end)

local function refreshButtons()
  local controls = ac.INIConfig.controlsConfig()
  delayActive = controls:get('__EXTRA_CM', 'DELAY_SPECIFIC_SYSTEM_COMMANDS', true) 
    and not ac.INIConfig.videoConfig():get('VIDEO', 'FULLSCREEN', true)
  delayShowProgress = delayActive and controls:get('__EXTRA_CM', 'SHOW_SYSTEM_DELAYS', true)
  if delayShowProgress and displayToggle == nil then
    displayToggle = Toggle.DrawUI()
  end

  buttonsCount = 0
  addButton(ac.ControlButton('__EXT_SIM_PAUSE', ac.GamepadButton.Start, { gamepad = true }):setAlwaysActive(true), function ()
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
