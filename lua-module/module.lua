--[[
  Small Tweaks loads and runs this script with apps library. Script itself loads modules
  from `src` folder and defines a new `register()` function allowing for those modules
  to subscribe for different events.
]]

Sim = ac.getSim()
UI = ac.getUI()
AIRace = not Sim.isOnlineRace and not Sim.isReplayOnlyMode and Sim.carsCount > 1 and not Sim.isShowroomMode

---@diagnostic disable-next-line: undefined-field
Config = ac.INIConfig(ac.INIFormat.Extended, _G.__config__ or {}) -- Small Tweaks config is as `__config__` in a compatible form.

ConfigGamepadFX = ac.INIConfig.cspModule(ac.CSPModuleID.GamepadFX) ---@type ac.INIConfig?
ConfigGUI = ac.INIConfig.cspModule(ac.CSPModuleID.GUI) ---@type ac.INIConfig?
ConfigVRTweaks = ac.INIConfig.cspModule(ac.CSPModuleID.VRTweaks) ---@type ac.INIConfig?

ac.onCSPConfigChanged(ac.CSPModuleID.GamepadFX, __reloadScript__)
ac.onCSPConfigChanged(ac.CSPModuleID.GUI, __reloadScript__)
ac.onCSPConfigChanged(ac.CSPModuleID.VRTweaks, __reloadScript__)

if not ConfigGamepadFX:get('BASIC', 'ENABLED', true) then ConfigGamepadFX = nil end
if not ConfigGUI:get('BASIC', 'ENABLED', true) then ConfigGUI = nil end
if not ConfigVRTweaks:get('BASIC', 'ENABLED', true) then ConfigVRTweaks = nil end

if AIRace then
  ac.onCSPConfigChanged(ac.CSPModuleID.NewBehaviour, __reloadScript__)
  ConfigNewBehaviour = ac.INIConfig.cspModule(ac.CSPModuleID.NewBehaviour) ---@type ac.INIConfig?
  if not ConfigNewBehaviour:get('BASIC', 'ENABLED', true) then ConfigNewBehaviour = nil end
end

local fns = {
  core = {},
  gameplay = {},
  simUpdate = {},
  draw3D = {},
  drawUI = {},
  drawGameUI = {},
}

---@param mode 'core'|'gameplay'|'simUpdate'|'draw3D'|'drawUI'|'drawGameUI'
---@param callback fun(dt: number)
function Register(mode, callback)
  table.insert(fns[mode], callback)
  return function()
    table.removeItem(fns[mode], callback)
  end
end

-- Only for this Small Tweaks script: callbacks are optional to avoid a tiny overhead on calling them if
-- there is nothing to draw.
local draw3DCallbackCounter = 0
local drawUICallbackCounter = 0

Toggle = {
  Draw3D = function ()
    local state = false
    ---@param active boolean
    return function (active)
      if not active ~= state then return end
      state = not state
      local newCounter = draw3DCallbackCounter + (state and 1 or -1)
      if (newCounter > 0) ~= (draw3DCallbackCounter > 0) then
        __setDraw3DActive__(newCounter > 0) ---@diagnostic disable-line: undefined-global
      end
      draw3DCallbackCounter = newCounter
    end
  end,
  ---@type fun(): fun(active: boolean)
  DrawUI = function ()
    local state = false
    ---@param active boolean
    return function (active)
      if not active ~= state then return end
      state = not state
      local newCounter = drawUICallbackCounter + (state and 1 or -1)
      if (newCounter > 0) ~= (drawUICallbackCounter > 0) then
        __setDrawUIActive__(newCounter > 0) ---@diagnostic disable-line: undefined-global
      end
      drawUICallbackCounter = newCounter
    end
  end
}

--@includes:start
io.scanDir(__dirname..'/src', '*.lua', function (fileName)
  require('src/'..fileName:sub(1, #fileName - 4))
end)
--@includes:end

function script.update(dt)
  if not Sim.isPaused and not Sim.isInMainMenu then
    for i = 1, #fns.gameplay do fns.gameplay[i](dt) end
  end
  for i = 1, #fns.core do fns.core[i](dt) end
end

if #fns.simUpdate > 0 then
  function script.simUpdate(dt)
    for i = 1, #fns.simUpdate do fns.simUpdate[i](dt) end
  end
end

if #fns.draw3D > 0 then
  function script.draw3D(dt)
    for i = 1, #fns.draw3D do fns.draw3D[i](dt) end
  end
end

function script.drawUI(dt, inGame)
  if inGame then 
    for i = 1, #fns.drawGameUI do fns.drawGameUI[i](dt, inGame) end
  end
  for i = 1, #fns.drawUI do fns.drawUI[i](dt, inGame) end
end

ac.onSharedEvent('$SmallTweaks.ReloadScript', function (data, senderName, senderType)
  if senderType == 'joypad_assist' or senderType == 'joypad_assist_render' then
    __reloadScript__()
  end
end)

