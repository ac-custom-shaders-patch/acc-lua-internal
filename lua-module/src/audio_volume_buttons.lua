--[[
  Adds hotkeys to quickly alter audio level. Might be helpful for something like quickly lowering volume for a bit with voice chat.
]]

local btn0 = ac.ControlButton('__EXT_AUDIO_BTN_0', nil, nil, 0.2)
local btn1 = ac.ControlButton('__EXT_AUDIO_BTN_1', nil, nil, 0.2)
if not btn0:configured() and not btn1:configured() then
  return
end

local cfg = Config:mapSection('AUDIO_VOLUME_BUTTONS', {
  MODE = 'SET_RESTORE',
  LEVEL_0 = 0,
  LEVEL_1 = 0,
  STEP = 0.05,
  TRANSITION_LAG = 0.9,
  SHOW_MESSAGE = true,
})

local audioTarget = 1
local audioSmooth = 1
local flag0 = false
local flag1 = false

local modes = {
  function ()  -- SET_RESTORE, default mode
    if btn0:down() then audioTarget = cfg.LEVEL_0 end
    if btn1:down() then audioTarget = 1 end
  end,
  HOLD_TO_ALTER = function ()
    audioTarget = 1
    if btn0:down() then audioTarget = cfg.LEVEL_0 end
    if btn1:down() then audioTarget = cfg.LEVEL_1 end
  end,
  PRESS_TO_ALTER = function ()
    if btn0:pressed() then
      flag1 = false
      flag0 = not flag0
    end
    if btn1:pressed() then
      flag0 = false
      flag1 = not flag1
    end
    audioTarget = flag0 and cfg.LEVEL_0 or flag1 and cfg.LEVEL_1 or 1
  end,
  UP_DOWN = function ()
    if btn0:pressed() then
      audioTarget = audioTarget + cfg.STEP
    end
    if btn1:pressed() then
      audioTarget = audioTarget - cfg.STEP
    end
  end
}

local modeFn = modes[cfg.MODE] or modes[1]

local function audioCallback()
  local previousTarget = audioTarget
  modeFn()
  audioTarget = math.saturateN(audioTarget)
  if previousTarget ~= audioTarget and cfg.SHOW_MESSAGE then
    ac.setMessage('Volume Level', string.format('Volume changed to %.0f%%', audioTarget * 100))
  end

  audioSmooth = math.applyLag(audioSmooth, audioTarget, cfg.TRANSITION_LAG, ac.getDeltaT())
  return audioSmooth
end

ac.onAudioVolumeCalculation(audioCallback)