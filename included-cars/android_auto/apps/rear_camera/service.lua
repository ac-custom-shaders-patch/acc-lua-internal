if ac.configValues({ RearCameraPosition = '' }).RearCameraPosition == '' then
  error('Not configured')
end

local openedAutomatically = false
local previousApp

return function ()
  if car.gear == -1 then
    if not openedAutomatically then
      openedAutomatically = true
      if system.isAppActive() then
        previousApp = nil
      else
        previousApp = system.foregroundApp()
        system.openApp()
      end
    end
  elseif openedAutomatically then
    if system.isAppActive() then
      if previousApp == nil then
        system.closeApp()
      else
        system.openApp(previousApp, true)
      end
    end
    openedAutomatically = false
    previousApp = nil
  end
end
