--[[
  Draws an icon showing the state of manual pit limiter. Also, warns about disabled forced pit limiter with an icon and a message.
]]

local forcedLimiterDisabled = false
local settings = ConfigGUI:mapSection('EXTRA_HUD_ELEMENTS', {
  PIT_SPEED_LIMIT = false,
  MANUAL_PIT_SPEED_LIMITER = false,
  WARN_ABOUT_MANUAL_LIMITER = false,
})

setTimeout(function ()
  local serverCfg = ac.INIConfig.onlineExtras()
  if serverCfg ~= nil then
    if serverCfg:get('PITS_SPEED_LIMITER', 'DISABLE_FORCED', false) 
        and serverCfg:get('PITS_SPEED_LIMITER', 'SPEEDING_PENALTY', '') ~= 'NONE'
        and serverCfg:get('PITS_SPEED_LIMITER', 'SPEEDING_SUBSEQUENT_PENALTY', '') ~= 'NONE' then
      forcedLimiterDisabled = true

      if settings.WARN_ABOUT_MANUAL_LIMITER then
        local unregister
        unregister = Register('gameplay', function (dt)
          unregister()
          setTimeout(function ()
            ac.setMessage('Forced pit limiter disabled',
              string.format('Don’t drive in pits faster than %.0f km/h or you would be penalized', serverCfg:get('PITS_SPEED_LIMITER', 'SPEED_KMH', 80)))
          end, 2)
        end)
      end
    end
  end
end, 1)

if settings.PIT_SPEED_LIMIT or settings.MANUAL_PIT_SPEED_LIMITER then
  local sim = ac.getSim()
  local car = ac.getCar(0)
  local drawLimiterIcons = Toggle.DrawUI()

  Register('gameplay', function ()
    drawLimiterIcons(forcedLimiterDisabled and car.isInPitlane and settings.PIT_SPEED_LIMIT or car.manualPitsSpeedLimiterEnabled and settings.MANUAL_PIT_SPEED_LIMITER)
  end)

  Register('drawUI', function (dt)
    if forcedLimiterDisabled and car.isInPitlane and settings.PIT_SPEED_LIMIT then
      ui.drawCarIcon(function (size)
        ui.drawCircle(ui.getCursor() + size / 2, size / 2 - 2, rgbm.colors.red, 24, 4)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.black)
        ui.pushFont(ui.Font.Main)
        ui.textAligned(sim.pitsSpeedLimit, 0.5, size)
        ui.popFont()
        ui.popStyleColor()
      end, rgbm.colors.white)
    end

    if car.manualPitsSpeedLimiterEnabled and settings.MANUAL_PIT_SPEED_LIMITER then
      ui.drawCarIcon(ui.Icons.Speedometer, rgbm.colors.white)
    end
  end)
end
