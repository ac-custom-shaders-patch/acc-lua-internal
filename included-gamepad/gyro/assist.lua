ScriptSettings = ac.INIConfig.scriptSettings():mapSection('TWEAKS', {
  MODE_SWITCH_BUTTON = ac.GamepadButton.RightThumb,
  TRIGGERS_FEEDBACK = true,
  SENSITIVITY = 0.5
})

local wasPressed = false
local storedValue = ac.storage('mode:'..ac.getCarID(0), require('shared/info/cars').isDriftCar(0))
local driftMode = storedValue:get() == true

local currentModeId = nil
local currentMode = nil
local step = 0

function script.update(dt)
  local state = ac.getJoypadState()
  if state.gamepadType ~= currentModeId then
    currentModeId = state.gamepadType
    currentMode = state.gamepadType == ac.GamepadType.DualSense and require('mode_dualsense') or require('mode_dualshock')
  end

  step = step > 10000 and 0 or step + 1
  currentMode(state, driftMode, step, dt)

  if ac.isGamepadButtonPressed(__gamepadIndex, ScriptSettings.MODE_SWITCH_BUTTON) ~= wasPressed then
    wasPressed = not wasPressed
    if wasPressed then
      driftMode = not driftMode
      storedValue:set(driftMode)
      ac.setSystemMessage('Gamepad mode', 'Switched to '..(driftMode and 'Drift' or 'Race'))
    end
  end
end

