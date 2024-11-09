---@ext

local sim = ac.getSim()
local car = ac.getCar(0)

if not true then
  -- local layer = ui.UserIconsLayer(10)
  -- local layer2 = ui.UserIconsLayer(15)
  -- local player = ui.GIFPlayer('2.0.gif')

  -- function script.update()
  --   layer(0, player)
  --   if ac.isKeyDown(ac.KeyIndex.LeftButton) then
  --     layer2(0, ui.Icons.Bluetooth)
  --   else
  --     layer2(0, nil)
  --   end
  -- end

  local canvas = ui.ExtraCanvas(64, 3)
  function script.fullscreenUI()
    render.backupRenderTarget()

    local peakVolume = math.sin(os.preciseClock() * 2) * 0.5 + 0.5
    canvas:updateWithShader({
      textures = { txIcon = 'res/speaker.png' },
      values = { gPos = peakVolume },
      shader = 'res/speaker.fx'
    })
    render.restoreRenderTarget()

    ui.drawRectFilled(vec2(8, 8), vec2(72, 72), rgbm.colors.red, 0)
    ui.drawImage(canvas, vec2(8, 8), vec2(72, 72))
  end

  return
end

local debugRun = false
-- if io.fileExists('C:/Development/old/AcToolsExtra/AcTools.Extra.MumbleClient/bin/Release/AcTools.Extra.MumbleClient.exe') then
--   if sim.carsCount > 1 and not sim.isOnlineRace then
--     debugRun = true
--   end
--   os.execute('taskkill /f /im AcTools.Extra.MumbleClient.exe')
--   io.copyFile('C:/Development/old/AcToolsExtra/AcTools.Extra.MumbleClient/bin/Release/AcTools.Extra.MumbleClient.exe',
--     ac.getFolder(ac.FolderID.ExtInternal)..'/plugins/AcTools.MumbleClient.exe', false)
--   io.copyFile('C:/Development/old/AcToolsExtra/AcTools.Extra.MumbleClient/bin/Release/AcTools.Extra.MumbleClient.pdb',
--     ac.getFolder(ac.FolderID.ExtInternal)..'/plugins/AcTools.Extra.MumbleClient.pdb', false)
-- end

if not sim.isOnlineRace and not debugRun or not car then
  ac.unloadApp()
  ac.setAppWindowVisible('Mumble', '?', false)
  function script.windowMain(_)
    local fading = ac.windowFading()
    if fading > 0.01 then
      ui.beginOutline()
      ui.textWrapped('Voice chat is not configured for this race.')
      ui.endOutline(rgbm(0, 0, 0, fading))
    else
      ui.textWrapped('Voice chat is not configured for this race.')
    end
  end  
  function script.windowSettings(_)
    ui.textWrapped('Voice chat is not configured for this race.')
  end
  return
end

local mumble
if debugRun then
  local debugVolumeSet = 1
  ac.setAudioVolume(ac.AudioChannel.Engine, debugVolumeSet)
  ac.setAudioVolume(ac.AudioChannel.Tyres, debugVolumeSet)
  ac.setAudioVolume(ac.AudioChannel.Wind, debugVolumeSet)
  ac.setAudioVolume(ac.AudioChannel.Transmission, debugVolumeSet)
  ac.setAudioVolume(ac.AudioChannel.Surfaces, debugVolumeSet)
  ac.setAudioVolume(ac.AudioChannel.Dirt, debugVolumeSet)
  ac.setAudioVolume(ac.AudioChannel.Opponents, debugVolumeSet)
  -- mumble = require('./src/MumbleWrapper')({host = '127.0.0.1', password = 'pass', channel = 'ch0', context = 'offline', use3D = true})
  mumble = require('./src/MumbleWrapper')({host = '193.178.170.107', context = 'offline', use3D = true, maxDistance = 50})
else
  ac.onOnlineWelcome(function (message, config)
    if mumble then return end

    local cfg = config:mapSection('MUMBLE_INTEGRATION', { 
      HOST = '',
      PORT = 64738,
      PASSWORD = '',
      CHANNEL = 'Root',
      POSITIONAL_AUDIO = true,
      POSITIONAL_AUDIO_DIRECT_PTT = false,
      POSITIONAL_MAX_DISTANCE = 50,
      MUTE_DISTANCE = math.huge,
      USERNAME_PREFIX = ''
    })
    if cfg.HOST == '' then
      ac.unloadApp()
      ac.setAppWindowVisible('Mumble', '?', false)
    else
      local function preprocessValue(value)
        return value:gsub('{([A-Za-z]+)}', function (k)
          if k == 'ServerIP' then return ac.getServerIP() end
          if k == 'ServerName' then return ac.getServerName() end
          if k == 'ServerPortHTTP' then return ac.getServerPortHTTP() end
          if k == 'ServerPortTCP' then return ac.getServerPortTCP() end
          if k == 'ServerPortUDP' then return ac.getServerPortUDP() end
        end)
      end
      ac.log('Mumble config', cfg)
      mumble = require('./src/MumbleWrapper')({
        host = preprocessValue(cfg.HOST),
        port = cfg.PORT,
        password = preprocessValue(cfg.PASSWORD),
        channel = preprocessValue(cfg.CHANNEL),
        use3D = cfg.POSITIONAL_AUDIO,
        useDirectPTT = cfg.POSITIONAL_AUDIO_DIRECT_PTT,
        maxDistance = cfg.POSITIONAL_MAX_DISTANCE,
        muteDistance = cfg.MUTE_DISTANCE,
        context = string.format('%s:%s', ac.getServerIP(), ac.getServerPortTCP()),
        usernamePrefix = cfg.USERNAME_PREFIX ~= '' and preprocessValue(cfg.USERNAME_PREFIX) or nil
      })
    end
  end)
end

function script.update(dt)
  if mumble then
    mumble.update(dt)
  end
end

function script.windowMain(_)
  if mumble then
    mumble.main()
  else
    local fading = ac.windowFading()
    if fading > 0.01 then
      ui.beginOutline()
      ui.textWrapped('Voice chat is not configured for this race.')
      ui.endOutline(rgbm(0, 0, 0, fading))
    else
      ui.textWrapped('Voice chat is not configured for this race.')
    end
  end
end

function script.windowSettings(_)
  if mumble then
    mumble.settings()
  else
    ui.textWrapped('Voice chat is not configured for this race.')
  end
end

function script.fullscreenUI(_)
  if mumble then
    mumble.fullscreen()
  end
end

function script.windowOnHide(_)
  ac.setWindowTitle('main', 'Voice Chat')
end
