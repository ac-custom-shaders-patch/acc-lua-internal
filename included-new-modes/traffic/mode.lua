--[[
  Simply loads some code from traffic planner tool and runs that. If you were to create a new mode with traffic, maybe contact
  me on Discord or Telegram first, so we could plan things in a way that wouldn’t break in the future.
]]

if ac.load('newmode.traffic.notavailable') then
  ac.warn('Not available in this session')
  return
end

local settings = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  TRAFFIC_DENSITY = 1500,
  SPEED_MULT = 1,
  CARNAGE_MODE = false,
})

local simUpdateImpl
local draw3DImpl
local drawUIImpl

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

function script.drawUI()
  if drawUIImpl then
    drawUIImpl()
  end
end

local function reportError(title, suggestion)
  drawUIImpl = function()
    if ac.load('newmode.traffic.notavailable') then
      return
    end
    ui.drawRectFilled(0, ui.windowSize(), rgbm(0, 0, 0, 0.5))
    ui.pushFont(ui.Font.Title)
    ui.drawTextClipped(title, 0, ui.windowSize(), rgbm.colors.white, 0.5)
    ui.popFont()
    ui.drawTextClipped('Use Traffic Planner tool in Objects Inspector to '..suggestion, vec2(0, 30), ui.windowSize() + vec2(0, 30), rgbm.colors.white, 0.5)
    ui.setCursor(ui.windowSize() / 2 + vec2(-120, 60))
    ui.childWindow('w', vec2(240, 40), function ()
      if ui.button('OK', -0.1, 0) then
        ac.store('newmode.traffic.notavailable', 1)
      end
    end)
  end
end

local changed = false
local refresh
ac.addMainMenuSettings(function ()
  if not refresh then
    ui.text('Loading necessary files, please wait…')
    return
  end
  ui.pushItemWidth(-0.1)
  settings.TRAFFIC_DENSITY = ui.slider('##density', settings.TRAFFIC_DENSITY, 0, 5000, 'Cars limit: %.0f')
  if ui.itemEdited() then changed = true end
  settings.SPEED_MULT = ui.slider('##speed', settings.SPEED_MULT * 100, 0, 100, 'Top speed limit: %.0f%%') / 100
  if ui.itemEdited() then changed = true end
  if ui.checkbox('Carnage mode', settings.CARNAGE_MODE) then
    settings.CARNAGE_MODE = not settings.CARNAGE_MODE
    changed = true
  end
  ui.popItemWidth()
  if changed and refresh and not ui.isAnyMouseDown() then
    refresh()
  end
end, nil, 150)

local trafficLib = require('shared/sim/traffic')
trafficLib.lookup(true, function (err, data)
  if not err then
    local traffic = trafficLib.run({
      jsonConfigurationFilename = data.jsonConfigurationFilename,
      binaryConfigurationFilename = data.binaryConfigurationFilename,
      driversCount = settings.TRAFFIC_DENSITY,
      speedMultiplier = settings.SPEED_MULT,
      carnageMode = settings.CARNAGE_MODE
    })
    if traffic then
      draw3DImpl = traffic.draw3D
      simUpdateImpl = traffic.update
      refresh = function ()
        traffic.restart({
          driversCount = settings.TRAFFIC_DENSITY,
          speedMultiplier = settings.SPEED_MULT,
          carnageMode = settings.CARNAGE_MODE
        })
      end
    end
  else
    reportError('Traffic data is missing', 'configure traffic')
  end
end)
