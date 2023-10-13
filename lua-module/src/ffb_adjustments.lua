--[[
  Adds hotkeys to change FFB. Could be useful for binding FFB adjustment to the steering wheel buttons.
]]

local btn0 = ac.ControlButton('__EXT_FFB_INCREASE', nil, nil, 0.2)
local btn1 = ac.ControlButton('__EXT_FFB_DECREASE', nil, nil, 0.2)
if not btn0:configured() and not btn1:configured() then
  return
end

local cfg = Config:mapSection('FFB_ADJUSTMENTS', {
  STEP = 0.05,
  SHOW_MESSAGE = true,
})

Register('gameplay', function ()
  if btn0:pressed() or btn1:pressed() then
    local ffb = ac.getCar(0).ffbMultiplier
    local newValue = math.max(0, ffb + cfg.STEP * (btn0:pressed() and 1 or -1))
    ac.setFFBMultiplier(newValue)
    if cfg.SHOW_MESSAGE then
      ac.setMessage(string.format('User level for %s: %.0f%%', ac.getCarName(0, true), newValue * 100), 'Force Feedback')
    end
  end
end)
