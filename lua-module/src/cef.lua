local hopingForRestart = false
local connect = ac.connect{
  ac.StructItem.key('cefState'),
  tabsCount = ac.StructItem.int32(),
  cefState = ac.StructItem.byte(), -- 0: ready, 1: installing, ≥10: errors
  cefLoop = ac.StructItem.boolean(),
  noProxyServer = ac.StructItem.boolean(),
  useTimer = ac.StructItem.boolean(),
  setGPUDevicePriority = ac.StructItem.int8(),
  setGPUProcessPriority = ac.StructItem.int8(),
  targetFPS = ac.StructItem.int32(),
}
connect.tabsCount = 0
connect.cefState = 1

local function reportCEFError(type, message)
  ac.store('.SmallTweaks.CEFInstallError', message)
  connect.cefState = type
end

local reinstallNext = false
local reinstalledOnce = false

---CEF is here and ready to go, time to launch it and wait for its exit. 
---@param filename string
---@param key string
---@param closeCallback fun(err: string?)
local function runWebHostProcess(filename, key, closeCallback)
  ac.store('.SmallTweaks.CEFLaunchedOnce', 1)
  ac.log('CEF loop: '..tostring(connect.cefLoop and 1 or 0))
  
  if __util.dev then
    local devFilename = 'C:/Development/temp-alt/cef-mixer-master/bin/Debug/cefmixer.exe'
    if io.fileExists(devFilename) then
      filename = devFilename
      ac.warn('Using debug cefmixer build')
    end
  end

  local setPriority = Config:get('MISCELLANEOUS', 'SET_CEF_PRIORITY', true)
  local startTime = os.time()
  local errData = {}
  connect.cefState = 0
  os.runConsoleProcess({
    filename = filename,
    workingDirectory = io.getParentPath(filename) or '',
    terminateWithScript = true,
    dataCallback = function (err, data)
      if err then
        if #errData < 40 then
          errData[#errData + 1] = data
        end
        ac.error(data)
      else
        ac.warn(data)
      end
    end,
    environment = {
      ACCSPWB_KEY = key,
      ACCSPWB_AUTOPLAY = 1,
      ACCSPWB_NO_PROXY_SERVER = connect.noProxyServer and 1 or nil,
      ACCSPWB_CEF_THREADING = connect.cefLoop and 1 or nil,
      ACCSPWB_USE_TIMER = connect.useTimer and 1 or nil,
      ACCSPWB_GPU_PROCESS_PRIORITY = connect.setGPUProcessPriority ~= 0 and connect.setGPUProcessPriority or setPriority and 3 or nil,
      ACCSPWB_GPU_PRIORITY = connect.setGPUDevicePriority ~= 0 and connect.setGPUDevicePriority or setPriority and 5 or nil,
      ACCSPWB_TARGET_FPS = connect.targetFPS < 1 and 60 or connect.targetFPS,
      ACCSPWB_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.134 Safari/537.36 AssettoCorsa/1.16.3',
      ACCSPWB_DATA_DIRECTORY = ac.getFolder(ac.FolderID.AppDataLocal)..'/ac-cef-layer',
      ACCSPWB_D3D_DEVICE = table.join({__d3dAdapterLuid__()}, ';'),
    } or nil,
    inheritEnvironment = true
  }, function (err, data)
    local lastRunTime = os.time() - startTime
    ac.log('CEF backend exited: '..(err or data and data.exitCode))
    if err then
      local errMsg = tostring(err):trim()
      ac.error('Failed to start CEF backend: '..errMsg..', run time: '..tostring(lastRunTime)..' s')
      reinstallNext = true
      reportCEFError(11, errMsg)
    elseif data.exitCode ~= 0 then
      ac.warn('CEF backend crashed: '..tostring(data.exitCode))
      if data.exitCode == 20 then
        reinstallNext = false
        reportCEFError(12, 'Failed to access CEF texture.')
      elseif data.exitCode == 11 then
        reinstallNext = false
        reportCEFError(13, 'Failed to reshare CEF texture.')
      elseif data.exitCode == 29 then
        reportCEFError(18, 'CEF webpage renderer keeps crashing.')
      else
        if lastRunTime < 3 then
          reinstallNext = true
        end
        if data.exitCode == 10 then
          reportCEFError(14, #errData > 0 and table.concat(errData) or 'Unexpected exception in CEF layer.')
        else
          reportCEFError(17, #errData > 0 and table.concat(errData) or 'Unexpected crash of a CEF process.')
        end
      end
    else
      ac.warn('CEF backend exited')
      reportCEFError(10, '')
    end
    if err or data.exitCode ~= 0 then
      closeCallback(err or ('Exit code: '..tostring(data.exitCode)))
    else
      closeCallback(nil)
    end
  end)
  ac.log('New process has started')
end

local timer

local function readableSize(bytes)
  if bytes < 1.2 * (1024 * 1024) then return string.format('%.1f KB', bytes / 1024) end
  return string.format('%.1f MB', bytes / (1024 * 1024))
end

local function readableSizeFraction(bytes, bytesTotal)
  if not bytesTotal or bytesTotal == 0 then return readableSize(bytes) end
  if bytesTotal < 1.2 * (1024 * 1024) then return string.format('%.1f/%.1f KB', bytes / 1024, bytesTotal / 1024) end
  return string.format('%.1f/%.1f MB', bytes / (1024 * 1024), bytesTotal / (1024 * 1024))
end

local function readableETA(time)
  if time >= 24 * 60 * 60 then return 'too long left' end
  local u, v
  if time < 1.6 * 60 then u, v = 'second', math.round(time)
  elseif time < 1.6 * 60 * 60 then u, v = 'minute', math.round((time / 60))
  else u, v = 'hour', math.round((time / (60 * 60))) end
  return string.format('%.0f %s%s left', v, u, v == 1 and '' or 's')
end

local function findETA(speed, bytes, bytesTotal)
  if bytesTotal < bytes then return 'some time left' end
  local leftToDownload = bytesTotal - bytes
  return speed <= 1 and math.huge or leftToDownload / speed
end

---Here we need to verify CEF is present, download its binaries if it’s missing and then launch the process.
---@param key string
---@param closeCallback fun(err: string?)
local function setupWebHostProcess(key, closeCallback)
  local function init()
    -- I will add progress callbacks to `web:get()`, but for now it is what it is

    if reinstalledOnce then
      reinstallNext = false
    elseif reinstallNext then
      reinstalledOnce = true
    end

    local err, filename = __cefState__(reinstallNext)
    reinstallNext = false

    if filename then
      runWebHostProcess(filename, key, closeCallback)
    elseif err then
      ac.error('Immediate installation error: '..err)
      reportCEFError(15, err)
      setTimeout(function ()
        closeCallback(err)
      end)
    elseif timer then
      ac.error('Damaged state')
    else
      local installingProgress = ac.connect{
        ac.StructItem.key('cefState.install'),
        progress = ac.StructItem.float(),
        message = ac.StructItem.string(256),
      }
  
      connect.cefState = 2
      local lastLoaded, lastTime, avgSpeed = -1, -1, 0
      timer = setInterval(function ()
        local err, filename, loaded, total, progressMessage = __cefState__()
        if filename then
          clearInterval(timer)
          timer = nil
          runWebHostProcess(filename, key, closeCallback)
        elseif err then
          clearInterval(timer)
          timer = nil
          ac.error('Installation error: '..err)
          reportCEFError(15, err)
          closeCallback(err)
        elseif progressMessage then
          installingProgress.progress = total > 0 and loaded <= total and loaded / total or -1
          installingProgress.message = total > 0 and string.format('Installing: %s (%d/%d)', progressMessage, loaded + 1, total) or progressMessage
        else
          local now = os.preciseClock()
          if loaded > 0 then
            if lastLoaded == -1 then 
              lastLoaded, lastTime = loaded, now
            else
              avgSpeed = math.lerp(avgSpeed, (loaded - lastLoaded) / math.max(1e-10, now - lastTime), avgSpeed == 0 and 1 or 0.1)
            end
            installingProgress.progress = loaded <= total and loaded / total or -1
            installingProgress.message = string.format('Loading: %s, %s', readableSizeFraction(loaded, total), readableETA(findETA(avgSpeed, loaded, total)))
          else
            installingProgress.progress = -1
            installingProgress.message = 'Loading: connecting…'
          end
        end
      end)
    end
  end

  if ac.load('.SmallTweaks.CEFLaunchedOnce') == 1 then
    setTimeout(init, 1) 
  else
    init()
  end
end

---@type {mapped: {count: integer, tabs: integer[]}, tabs: {key: integer, luaID: integer}[]}?
local webHost = nil

---Updating memory mapped file listing IDs of active tabs 
local function rebuildWebHost()
  if not webHost then error('Damaged state') end
  if hopingForRestart then
    -- For restart, a negative number with a value forcing backend to instantly exit without any errors
    webHost.mapped.count = -2
  else
    -- 33554432 is a special value for when the actual list is being updated
    webHost.mapped.count = 33554432
    ac.memoryBarrier()
    for i = 1, #webHost.tabs do
      webHost.mapped.tabs[i - 1] = webHost.tabs[i].key
    end
    ac.memoryBarrier()
    webHost.mapped.count = #webHost.tabs
  end
end

---@type function
local restartWebHost

local awaitingWebHostStart = false

---Starting the thing: setting up memory mapped file, updating public state, etc.
local function startWebHost()
  if awaitingWebHostStart then return end
  awaitingWebHostStart = true
  connect.cefState = 1
  connect.cefLoop = ac.load('.SmallTweaks.CEF.useCEFLoop') == 1
  connect.useTimer = ac.load('.SmallTweaks.CEF.useTimer') == 1
  connect.noProxyServer = ac.load('.SmallTweaks.CEF.skipProxyServer') == 1
  connect.setGPUDevicePriority = ac.load('.SmallTweaks.CEF.setGPUDevicePriority') or 0
  connect.setGPUProcessPriority = ac.load('.SmallTweaks.CEF.setGPUProcessPriority') or 0
  connect.targetFPS = ac.load('.SmallTweaks.CEF.targetFPS') or 60
  if connect.targetFPS < 1 then connect.targetFPS = 60 end

  local key = string.format('AcTools.CSP.CEF.v0.%u.L', math.randomKey())
  local mapped = ac.writeMemoryMappedFile(key, [[int32_t count;uint32_t tabs[255];]])
  setupWebHostProcess(key, function (err)
    awaitingWebHostStart = false
    if connect.cefState < 10 then
      reportCEFError(16, 'Unknown error.')  
    end
    ac.store('.SmallTweaks.CEF.crashMessage', err or '')
    if hopingForRestart then
      hopingForRestart = false
      if webHost then webHost.mapped.count = 0 end
      setTimeout(restartWebHost)
    end
  end)
  webHost = {key = key, mapped = mapped, tabs = {}}
  ac.onRelease(function ()
    mapped.count = -1
  end)
end

restartWebHost = function ()
  startWebHost()
  rebuildWebHost()
  ac.broadcastSharedEvent('$SmallTweaks.CEF.Restart')
end

local listeningToRelease = false

ac.onSharedEvent('$SmallTweaks.CEF', function (data, _, _, luaID)
  if type(data) ~= 'table' then return end

  if not webHost then
    if not data.added then return end
    startWebHost()
    if not webHost then return end
  end

  if data.added then
    if #webHost.tabs >= 255 then
      ac.error('Too many tabs')
      return
    end

    if not listeningToRelease then
      listeningToRelease = true
      ac.onLuaScriptDisposal(function (_, _, luaID)
        local any = false
        webHost.tabs = table.filter(webHost.tabs, function (item)
          if item.luaID ~= luaID then return true end
          any = true
          return false
        end)
        if any then
          ac.warn('Script screwed off without releasing the tab: '..luaID)
          rebuildWebHost()
        end
      end)
    end

    table.insert(webHost.tabs, {key = data.added, luaID = luaID})
    connect.tabsCount = #webHost.tabs
    rebuildWebHost()
    ac.log('Tab added: '..data.added..', total tabs: '..#webHost.tabs..', script: '..luaID)
  elseif data.removed then
    local _, i = table.findFirst(webHost.tabs, function (item) return item.key == data.removed end)
    if not i then
      ac.warn('Tab to remove is missing: '..data.removed..', total tabs: '..#webHost.tabs..', script: '..luaID)
    else
      table.remove(webHost.tabs, i)
      rebuildWebHost()
      ac.log('Tab removed: '..data.removed..', total tabs: '..#webHost.tabs..', script: '..luaID)
    end
  elseif data.restart then
    ac.warn(data.reinstall and 'Reinstall requested' or 'Restart requested', 'state: '..tonumber(connect.cefState))
    if data.reinstall then reinstallNext, reinstalledOnce = true, false end
    if connect.cefState >= 10 then
      restartWebHost()
    elseif connect.cefState > 0 then
      ac.log('CEF is still initializing, nothing to do here')
    else
      hopingForRestart = true
      rebuildWebHost()
    end
  end
end)

if Sim.frame > 5 then
  ac.broadcastSharedEvent('$SmallTweaks.CEF.Restart')
end
