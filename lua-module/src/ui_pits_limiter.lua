--[[
  Draws an icon showing the state of manual pit limiter. Also, warns about disabled forced pit limiter with an icon and a message.
]]

if Sim.isShowroomMode then
  return
end

local forcedLimiterDisabled = false
local settings = ConfigGUI:mapSection('EXTRA_HUD_ELEMENTS', {
  PIT_SPEED_LIMIT = false,
  MANUAL_PIT_SPEED_LIMITER = false,
  WARN_ABOUT_MANUAL_LIMITER = false,
})

---@param cfg ac.INIConfig
local function parseRaceConfig(cfg)
  if cfg:get('PITS_SPEED_LIMITER', 'DISABLE_FORCED', false) 
      and cfg:get('PITS_SPEED_LIMITER', 'SPEEDING_PENALTY', '') ~= 'NONE'
      and cfg:get('PITS_SPEED_LIMITER', 'SPEEDING_SUBSEQUENT_PENALTY', '') ~= 'NONE' then
    forcedLimiterDisabled = true

    if settings.WARN_ABOUT_MANUAL_LIMITER then
      local unregister
      unregister = Register('gameplay', function (dt)
        setTimeout(unregister)
        setTimeout(function ()
          ac.setMessage('Forced pit limiter disabled',
            string.format('Don’t drive in pits faster than %.0f km/h or you would be penalized', cfg:get('PITS_SPEED_LIMITER', 'SPEED_KMH', 80)))
        end, 2)
      end)
    end
  end
end

if Sim.isOnlineRace then
  ac.onOnlineWelcome(function (_, config)
    parseRaceConfig(config)
  end)
else
  parseRaceConfig(ac.INIConfig.raceConfig())
end

if settings.PIT_SPEED_LIMIT or settings.MANUAL_PIT_SPEED_LIMITER then
  local car = ac.getCar(0)
  local drawLimiterIcons = Toggle.DrawUI()
  if not car then return end

  Register('gameplay', function ()
    drawLimiterIcons(forcedLimiterDisabled and car.isInPitlane and settings.PIT_SPEED_LIMIT or car.manualPitsSpeedLimiterEnabled and settings.MANUAL_PIT_SPEED_LIMITER)
  end)

  Register('drawGameUI', function (dt)
    if forcedLimiterDisabled and car.isInPitlane and settings.PIT_SPEED_LIMIT then
      ui.drawCarIcon(function (size)
        ui.drawCircle(ui.getCursor() + size / 2, size / 2 - 2, rgbm.colors.red, 24, 4)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.black)
        ui.pushFont(ui.Font.Main)
        ui.textAligned(string.format('%.0f', Sim.pitsSpeedLimit), 0.5, size)
        ui.popFont()
        ui.popStyleColor()
      end, rgbm.colors.white)
    end

    if car.manualPitsSpeedLimiterEnabled and settings.MANUAL_PIT_SPEED_LIMITER then
      ui.drawCarIcon(ui.Icons.Speedometer, rgbm.colors.white)
    end
  end)
end
