--[[
  Adds hotkeys to change FFB. Could be useful for binding FFB adjustment to the steering wheel buttons.
]]

local cfg = Config:mapSection('FFB_ADJUSTMENTS', {
  STEP = 0.05,
  SHOW_MESSAGE = true,
})

local function callback(dir)
  local ffb = Car.ffbMultiplier
  local newValue = dir == 0 and 1 or math.max(0, ffb + cfg.STEP * dir)
  ac.setFFBMultiplier(newValue)
  if cfg.SHOW_MESSAGE then
    ac.setMessage(string.format('User level for %s: %.0f%%', ac.getCarName(0, true), newValue * 100), 'Force Feedback')
  end
end

ac.ControlButton('__EXT_FFB_INCREASE', nil, nil, 0.2):onPressed(callback:bind(1))
ac.ControlButton('__EXT_FFB_DECREASE', nil, nil, 0.2):onPressed(callback:bind(-1))
ac.ControlButton('__EXT_FFB_RESET'):onPressed(callback:bind(0))
