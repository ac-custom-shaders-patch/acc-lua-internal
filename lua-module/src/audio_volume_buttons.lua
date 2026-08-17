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
  SAVE_VOLUME = false
})

local saved
if cfg.SAVE_VOLUME and cfg.MODE == 'UP_DOWN' then
  saved = ac.storage{ lastVolumeBtnValue = 1 }
end

local audioTarget = saved and saved.lastVolumeBtnValue or 1
local audioSmooth = saved and saved.lastVolumeBtnValue or 1
local audioInterval

local function audioSmoothAdjustment()
  if math.abs(audioTarget - audioSmooth) < 0.01 then
    audioSmooth = audioTarget
  else
    audioSmooth = math.applyLag(audioSmooth, audioTarget, cfg.TRANSITION_LAG, ac.getDeltaT())
  end
  ac.setAudioVolumeMultiplier(audioSmooth)
  if audioSmooth == audioTarget then
    audioInterval = nil
    return clearInterval
  end
end

local function setAudioTarget(value)
  value = math.saturate(value)
  if value == audioTarget then return end
  audioTarget = value
  if saved then saved.lastVolumeBtnValue = audioTarget end
  if cfg.SHOW_MESSAGE then ac.setMessage('Volume Level', 'Volume changed to %.0f%%' % (audioTarget * 100)) end

  if cfg.TRANSITION_LAG <= 0.01 or cfg.TRANSITION_LAG >= 1 then
    ac.setAudioVolumeMultiplier(audioTarget)
  elseif not audioInterval then
    audioInterval = setInterval(audioSmoothAdjustment)
  end
end

if cfg.MODE == 'HOLD_TO_ALTER' then
  local function recompute()
    local value = 1
    if btn0:down() then value = cfg.LEVEL_0 end
    if btn1:down() then value = cfg.LEVEL_1 end
    setAudioTarget(value)
  end
  btn0:onPressed(recompute)
  btn0:onReleased(recompute)
  btn1:onPressed(recompute)
  btn1:onReleased(recompute)
elseif cfg.MODE == 'PRESS_TO_ALTER' then
  local flag0 = false
  local flag1 = false
  btn0:onPressed(function ()
    flag0, flag1 = not flag0, false
    setAudioTarget(flag0 and cfg.LEVEL_0 or 1)
  end)
  btn1:onPressed(function ()
    flag0, flag1 = false, not flag1
    setAudioTarget(flag1 and cfg.LEVEL_1 or 1)
  end)
elseif cfg.MODE == 'UP_DOWN' then
  btn0:onPressed(function ()
    setAudioTarget(audioTarget + cfg.STEP)
  end)
  btn1:onPressed(function ()
    setAudioTarget(audioTarget - cfg.STEP)
  end)
else
  -- SET_RESTORE, default mode
  btn0:onPressed(function () setAudioTarget(cfg.LEVEL_0) end)
  btn1:onPressed(function () setAudioTarget(1) end)
end
