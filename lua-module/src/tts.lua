local mmf
local waitingCallbacks = {}
local ttsMode = Config:get('MISCELLANEOUS', 'TTS_ENGINE', 0)
local ttsModeReady
local busyInstalling
local orphanMode = Config:get('OBS', 'ORPHAN_TTS', false)

local function installCustomTTSEngine(id, name, mainFileName)
  local destination = '%s/tts/%s' % {ac.getFolder(ac.FolderID.ExtCache), id}
  if not io.fileExists('%s/%s.exe' % {destination, mainFileName}) then
    busyInstalling = name
    io.createDir(destination)
    ac.log('%s installation: start' % name)
    web.get('https://acstuff.ru/u/blob/ac-tts-%s-1.zip?v=5' % id, function (err, response)
      if not err and not __util.native('_vasj', response.body) then
        err = 'Package is damaged'
      end
 
      if err then
        ac.warn('Failed to load %s: %s' % {name, err})
        ui.toast(ui.Icons.Warning, 'Failed to install %s engine###tts_install' % name)
        return
      end

      io.extractFromZipAsync(response.body, destination, nil, function (err)
        (err and ac.warn or ac.log)('%s installation: %s' % {name, err or 'success'})
        if not err and io.fileExists('%s/%s.bin' % {destination, mainFileName}) then
          io.move('%s/%s.bin' % {destination, mainFileName}, '%s/%s.exe' % {destination, mainFileName})
          ttsModeReady = destination
          mmf = false
          if not busyInstalling then
            ui.toast(ui.Icons.Confirm, '%s engine is installed and ready to work###tts_install' % name)
          end
        else
          ui.toast(ui.Icons.Warning, 'Failed to install %s engine###tts_install' % name)
        end
        busyInstalling = nil
      end)
    end)
  else
    ttsModeReady = destination
  end
end

if ttsMode == 1 then
  installCustomTTSEngine('win10', 'Win10 TTS', 'AcTools.Extra.TextToSpeechService2')
elseif ttsMode == 2 then
  installCustomTTSEngine('piper', 'Piper TTS', 'piper')
end

local function ttsSay(text, params, callbackKey)
  if not text or text == '' then return end

  if busyInstalling then
    ui.toast(ui.Icons.LoadingSpinner, 'Using basic TTS engine while %s one is being installed…###tts_install' % busyInstalling)
    busyInstalling = nil
  end

  if not mmf then
    local runID = bit.bor(math.randomKey(), 0)
    if mmf == nil then
      setInterval(function ()
        if not mmf then 
          for _, v in pairs(waitingCallbacks) do
            ac.broadcastSharedEvent('$SmallTweaks.TTS.Said', v)
          end
          table.clear(waitingCallbacks)
          return
        end
        for i = 0, 7 do
          local c = mmf.data.complete[i]
          if c ~= 0 and waitingCallbacks[c] then
            ac.broadcastSharedEvent('$SmallTweaks.TTS.Said', waitingCallbacks[c])
            waitingCallbacks[c] = nil
            mmf.data.complete[i] = 0
          end
        end
      end, 0.05)
      if orphanMode then
        ac.onRelease(function (item)
          if mmf then
            mmf.data.runID = 0
          end
        end)
      end
    end
    mmf = {
      data = ac.writeMemoryMappedFile('AcTools.CSP.TTS.v2', {
        ac.StructItem.explicit(),
        runID = ac.StructItem.int32(),        
        key = ac.StructItem.int32(),        
        entries = ac.StructItem.array(ac.StructItem.struct{
          flags = ac.StructItem.uint16(),
          length = ac.StructItem.uint16(),
          rate = ac.StructItem.int16(),
          volume = ac.StructItem.uint16(),
          voiceID = ac.StructItem.uint32(),
          data = ac.StructItem.string(65536), 
        }, 4),
        complete = ac.StructItem.array(ac.StructItem.int32(), 8),
      }),
      waitFor = 0,
    }
    mmf.data.runID = runID
    mmf.data.key = 0   
    local baseFilename = ac.getFolder(ac.FolderID.ExtInternal)..'/plugins/AcTools.TextToSpeechService.exe'
    local processParams = { 
      filename = baseFilename,
      terminateWithScript = true,
      timeout = 0,
      environment = {TTS_RUN_ID = tostring(runID)},
      inheritEnvironment = true,
    }
    if ttsModeReady then
      if ttsMode == 1 then
        processParams.filename = ttsModeReady:replace('/', '\\')..'\\AcTools.Extra.TextToSpeechService2.exe'
        processParams.workingDirectory = ttsModeReady
      end
      if ttsMode == 2 then
        processParams.environment.TTS_PIPER_EXECUTABLE = ttsModeReady..'\\piper.exe'
        processParams.environment.TTS_PIPER_VOICES = ttsModeReady..'\\voices'
      end
    end
    if orphanMode then
      processParams.arguments = {'--launcher', processParams.filename}
      processParams.filename = baseFilename
    else
      processParams.dataCallback = function (err, data)
        (err and ac.warn or ac.log)(data)
      end
    end
    os.runConsoleProcess(processParams, function (err, data)
      if orphanMode then
        return
      end
      if err then
        ac.error(err)
      else
        if data.exitCode ~= 0 then
          ttsMode = 0
        end
        ac.warn('TTS service stopped: %s' % data.exitCode)
      end
      if mmf.data.runID == runID then
        mmf = false
      end
    end)

    ac.log('TTS service started')
  end

  if os.preciseClock() < mmf.waitFor then
    setTimeout(function ()
      ttsSay(text, params)
    end, 0.01 + mmf.waitFor - os.preciseClock())
    return
  end

  text = tostring(text) 
  local nextKey = mmf.data.key + 1
  local destination = mmf.data.entries[nextKey % 4]
  destination.length = #text
  destination.data = text
  destination.flags = params.gender == 'male' and 1 or params.gender == 'female' and 2 or params.gender == 'neutral' and 3 or 0
  if callbackKey then
    destination.flags = bit.bor(destination.flags, 4)
    waitingCallbacks[nextKey] = callbackKey
  end
  destination.rate = tonumber(params.rate) or 0
  destination.volume = math.max(0, (tonumber(params.volume) or 1) * 100)
  destination.voiceID = tonumber(params.voiceID) or 0
  ac.memoryBarrier()
  mmf.data.key = nextKey
  mmf.waitFor = os.preciseClock() + 0.25
  ac.log('TTS phrase sent: %s (%s)' % {text, nextKey})
end

ac.onSharedEvent('$SmallTweaks.TTS.Say', function (data)
  if type(data) ~= 'table' then return end
  ttsSay(tostring(data.text), type(data.params) == 'table' and data.params or {}, data.key)
end)
