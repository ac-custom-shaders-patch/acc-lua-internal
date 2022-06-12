--[[
  Small Tweaks loads and runs this script with apps library. Script itself loads modules
  from `src` folder and defines a new `register()` function allowing for those modules
  to subscribe for different events.
]]

---@diagnostic disable-next-line: undefined-field
Config = ac.INIConfig(ac.INIFormat.Extended, _G.__config__ or {}) -- Small Tweaks config is as `__config__` in a compatible form.

ConfigGUI = ac.INIConfig.cspModule(ac.CSPModuleID.GUI)
ConfigVRTweaks = ac.INIConfig.cspModule(ac.CSPModuleID.VRTweaks)

local fns = {
  core = {},
  gameplay = {},
  simUpdate = {},
  draw3D = {},
  drawUI = {},
}

---@param mode 'core'|'gameplay'|'simUpdate'|'draw3D'|'drawUI'
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

io.scanDir(__dirname..'/src', '*.lua', function (fileName)
  require('src/'..fileName:sub(1, #fileName - 4))
end)

local sim = ac.getSim()

function script.update(dt)
  if not sim.isPaused and not sim.isInMainMenu then
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

if #fns.drawUI > 0 then
  function script.drawUI(dt)
    for i = 1, #fns.drawUI do fns.drawUI[i](dt) end
  end
end

--[[
local handbrake = ac.AudioEvent('event:/extension_common/turn_signal_ext')
handbrake.cameraInteriorMultiplier = 1
handbrake.volume = 10

function UpdateAudio()
  local car = ac.getCar(0)
  if car.handbrake > 0 and not handbrake:isPlaying() then
    handbrake:start()
  end
  handbrake:setPosition(car.position, car.up, car.look, car.velocity)
  handbrake:setParam('state', car.handbrake)
end
]]

-- local cs = ac.getCar(0).currentSector 
-- local cs = ac.getCar(0).currentSplits[0]
-- local cs = ac.getCar(0).lastSplits[0]
-- local cs = ac.getCar(0).bestSplits[0]
-- local cs = ac.getCar(0).bestLapSplits[0]
-- local cs = ac.getSim().lapSplits

-- ac.getSession(0).