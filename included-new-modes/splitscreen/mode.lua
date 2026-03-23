--[[
  Main part is done on C++ side, at least for now.
]]

local cfg = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  ALT_CONTROLS_CONFIG = '',
  HORIZONTAL_LAYOUT = true,
  TWO_RAW_MICE = true,
  HIDE_HUD = false,
  INCLUDE_TRAFFIC = false,
})

ac.applyLiveConfigEdit('custom_rendering_modes.ini', '[MODE_SPLITSCREEN]\n\
  HORIZONTAL_LAYOUT=%d\n\
  TWO_RAW_MICE=%d' % {cfg.HORIZONTAL_LAYOUT and 1 or 0, cfg.TWO_RAW_MICE and 1 or 0})
ac.loadCarControlsConfiguration(1, #cfg.ALT_CONTROLS_CONFIG > 0 and 'controllers/'..cfg.ALT_CONTROLS_CONFIG or 'controllers/presets/X360Default.ini')
physics.setAssists(ac.getAssists(), 1)

ac.onMessage(function (title)
  if title == 'ABS' or title == 'TC' or title == 'Auto Shifter' or title:startsWith('Turbo:') then
    setTimeout(function ()
      ac.setTargetCar(1)
      ac.setABS(ac.getCar(0).absMode)
      ac.setTractionControl(ac.getCar(0).tractionControlMode)
      ac.setAutoShifter(ac.getCar(0).autoShift)
      ac.setTurboWastegate(ac.getCar(0).turboWastegates[0])
      ac.setTargetCar(0)

      if __monitored then
        setTimeout(function ()
          print('Syncing assists:\n• ABS: %d, %d' % {ac.getCar(0).absMode, ac.getCar(1).absMode}
            .. '\n• TC: %d, %d' % {ac.getCar(0).tractionControlMode, ac.getCar(1).tractionControlMode}
            .. '\n• Automatic shifter: %s, %s' % {ac.getCar(0).autoShift, ac.getCar(1).autoShift}
            .. '\n• Turbo wastegate: %.2f, %.2f' % {ac.getCar(0).turboWastegates[0], ac.getCar(1).turboWastegates[0]})
        end)
      end
    end, 0, 'syncing')
  end
end)

ac.disableQuickMenuPitstop(true)
setTimeout(function ()
  ac.setHeadlights(true)
  ac.setHighBeams(true)
  ac.setTargetCar(1)
  ac.setHeadlights(true)
  ac.setHighBeams(true)
  ac.setTargetCar(0)
end, 0.1)

if cfg.HIDE_HUD then
  ui.onExclusiveHUD(function (mode)
    if mode == 'game' then
      return true
    end
  end)
end

if cfg.INCLUDE_TRAFFIC then  
  local simUpdateImpl
  local draw3DImpl

  function script.simUpdate(dt)
    if simUpdateImpl then
      simUpdateImpl(dt)
    end
  end

  function script.draw3D()
    if draw3DImpl then
      draw3DImpl()
    end
  end

  local trafficLib = require('shared/sim/traffic')
  trafficLib.lookup(true, function (err, data)
    if not err then
      local traffic = trafficLib.run({
        jsonConfigurationFilename = data.jsonConfigurationFilename,
        binaryConfigurationFilename = data.binaryConfigurationFilename,
        driversCount = 1000,
        speedMultiplier = 1,
        carnageMode = false
      })
      if traffic then
        draw3DImpl = traffic.draw3D
        simUpdateImpl = traffic.update
      end
    end
  end)
end