--[[
  A quick and somewhat dirty fix.
]]

if not Config:get('MISCELLANEOUS', 'RECONNECT_WHEEL_ON_APP_RESTORE', false) then return end

local needsReconnecting = false
Register('core', function (dt)
  if Sim.isWindowForeground then
    if needsReconnecting then
      ac.log('Reconnecting devices')
      needsReconnecting = false
      __reconnectInputDevices__()
    end
  else
    needsReconnecting = true
  end
end)
