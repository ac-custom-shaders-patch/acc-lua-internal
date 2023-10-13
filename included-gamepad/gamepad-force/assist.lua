local modes = {
  require('modes/race'),
  require('modes/drift')
}

ScriptSettings = ac.INIConfig.scriptSettings():mapSection('TWEAKS', {
  MODE_SWITCH_BUTTON = ac.GamepadButton.RightThumb
})

local storageKey = 'mode:'..ac.getCarID(0)
local currentMode = modes[tonumber(ac.storage[storageKey])] or modes[require('shared/info/cars').isDriftCar(0) and 2 or 1]
local wasPressed = false

function script.update(dt)
  currentMode.update(dt)

  if ac.isGamepadButtonPressed(__gamepadIndex, ScriptSettings.MODE_SWITCH_BUTTON) ~= wasPressed then
    wasPressed = not wasPressed
    if wasPressed then
      local newModeIndex = table.indexOf(modes, currentMode) % #modes + 1
      ac.storage[storageKey] = newModeIndex
      local newMode = modes[newModeIndex]
      newMode.sync(currentMode)
      currentMode = newMode
      ac.setSystemMessage('Gamepad mode', 'Switched to '..currentMode.name)
    end
  end
end

