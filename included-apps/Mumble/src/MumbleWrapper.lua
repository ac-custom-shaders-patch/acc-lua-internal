---@ext
--[[
  Self-contained wrapper for Mumble client plugin. Include-and-run, and call functions in returned objects in time
  to render UI and update the state.
]]

-- Definitions

local HAS_FLAG = const(function(item, flag) return bit.band(item.flags, flag) ~= 0 end)

local FLAG_DEFAULT = const(1)
local FLAG_ACTIVE = const(2)
local FLAG_SELECTED = const(4)

local FLAG_TALKING = const(1)
local FLAG_MUTED = const(2)
local FLAG_SELF_MUTED = const(4)
local FLAG_SUPRESSED = const(8)
local FLAG_DEAF = const(16)
local FLAG_SELF_DEAF = const(32)
local FLAG_STREAM = const(64)
local FLAG_IMMEDIATE_TALKING = const(128)
local FLAG_MUTED_ANY = const(2 + 4 + 8)

local DEF_DEVICE_NAME_SIZE = const(256)
local DEF_DEVICE_ICON_SIZE = const(128)
local DEF_COMMAND_SIZE = const(256)
local DEF_MAX_DEVICE_COUNT = const(64)
local DEF_MAX_COMMAND_COUNT = const(64)
local DEF_MAX_CONNECTED_COUNT = const(256)
local DEF_CHANNELS_DATA_SIZE = const(32768)
local DEF_EXPECTED_MARK_VALUE = const(12345678)

local SETTINGS_COLUMN_WIDTH = const(90)

---@alias MumbleConfig {configPrefix: string?, host: string, port: integer, password: string?, channel: string?, context: string?, use3D: boolean?, maxDistance: number?, muteDistance: number?}
---@alias MumbleWrapper {update: fun(dt: number), main: fun(), settings: fun(), fullscreen: fun()}

ffi.cdef(const('\
  typedef struct { const char name['..DEF_DEVICE_NAME_SIZE..']; const char icon['..DEF_DEVICE_ICON_SIZE..']; uint32_t flags; } mumble_DeviceInfo;\
  typedef struct { uint8_t sessionID; uint8_t peakVolume; uint16_t flags; uint32_t channelID; } mumble_ConnectedState;\
  typedef struct { char value['..DEF_COMMAND_SIZE..']; } mumble_CommandInfo;'))

---@alias MumbleMMF.Device {name: string, icon: string, flags: integer}
---@alias MumbleMMF.User {sessionID: integer, peakVolume: integer, flags: integer, channelID: integer}
---@alias MumbleMMF.Channel {id: integer, name: string, description: string, canEnter: boolean, isEnterRestricted: boolean, maxUsers: integer, children: MumbleMMF.Channel[], parent: MumbleMMF.Channel?, currentUsers: number, directUsers: number}

---@class MumbleMMF
---@field numInputDevices integer
---@field numOutputDevices integer
---@field inputDevices MumbleMMF.Device[]
---@field outputDevices MumbleMMF.Device[]
---@field bitrate integer
---@field streamConnectPointSize integer
---@field commands {value: string}[]
---@field numCommands integer
---@field frameIndex integer
---@field listenerPos vec3
---@field listenerDir vec3
---@field listenerUp vec3
---@field audioSourcePos vec3
---@field pushToTalk boolean
---@field requireMicPeak boolean
---@field serverLoopback boolean
---@field numCurrentlyConnected integer
---@field currentlyConnected MumbleMMF.User[]
---@field channelsPhase integer
---@field channelsData any
---@field micPeak number
---@field mark integer
---@return MumbleMMF
local function MumbleMMF(endpoint)
  local ret = ac.writeMemoryMappedFile(endpoint, const('\
    int bitrate;\
    int streamConnectPointSize;\
    int numInputDevices;\
    int numOutputDevices;\
    mumble_DeviceInfo inputDevices['..DEF_MAX_DEVICE_COUNT..'];\
    mumble_DeviceInfo outputDevices['..DEF_MAX_DEVICE_COUNT..'];\
    mumble_CommandInfo commands['..DEF_MAX_COMMAND_COUNT..'];\
    int numCommands;\
    int frameIndex;\
    vec3 listenerPos;\
    vec3 listenerDir;\
    vec3 listenerUp;\
    vec3 audioSourcePos;\
    bool pushToTalk;\
    bool requireMicPeak;\
    bool serverLoopback;\
    bool _pad1;\
    int numCurrentlyConnected;\
    mumble_ConnectedState currentlyConnected['..DEF_MAX_CONNECTED_COUNT..'];\
    int channelsPhase;\
    char channelsData['..DEF_CHANNELS_DATA_SIZE..'];\
    float micPeak;\
    int mark;'))
  ret.mark = DEF_EXPECTED_MARK_VALUE
  ac.onRelease(function () ret.mark = DEF_EXPECTED_MARK_VALUE + 1 end)
  return ret
end

-- Cache of key structs

local sim = ac.getSim()
local uiState = ac.getUI()
local ownCar = ac.getCar(0)
if not ownCar then error('Player car is missing', 2) end

-- Utility functions

---@type fun(maxDelaySeconds: number): fun(value: number, delay: number): number
local function delayed(maxDelaySeconds)
  local t, j, steps = {}, 1, 1 + math.ceil(60 * maxDelaySeconds)
  for i = 1, steps do t[i] = 0 end
  return function (current, delaySeconds)
    j = j + 1
    if j == steps + 1 then j = 1 end
    local delay = math.floor(delaySeconds / uiState.dt)
    t[j] = current
    local bak = j - math.clamp(delay, 0, steps - 1)
    if bak < 1 then bak = bak + steps end
    return t[bak]
  end
end

---@type fun(v: boolean|number|table|nil): string
local function encodeValue(v)
  local t = type(v)
  if t == 'boolean' then return v and '1' or '0' end
  if t == 'table' then return table.concat(table.map(v, encodeValue), '\t') end
  return v and tostring(v) or ''
end

---@type fun(data: table): string
local function encodeConfig(data)
  return table.concat(table.map(data, function (v, k) return k..'\t'..encodeValue(v) end), '\n') 
end

---@type fun(peak: number): ui.ExtraCanvas
local getTalkingIcon = (function ()
  local cache = table.range(32, function () return false end)
  return function (value)
    local key = 1 + math.floor(value * 31.999)
    local ret = cache[key]
    if not ret then
      ret = ui.ExtraCanvas(64, 3)
      render.backupRenderTarget()
      ret:updateWithShader({
        textures = { txIcon = 'res/speaker.png' },
        values = { gPos = math.saturateN(((key - 1) / 32) * 1.3 - 0.1) },
        shader = 'res/speaker.fx',
        cacheKey = 0
      })
      render.restoreRenderTarget()
      cache[key] = ret
    end
    return ret
  end
end)()

local exitCodes = {
  [0] = { message = 'Completely unexpected error', restartDelay = math.huge }, -- this one should never really happen
  [12] = { message = 'Internal error', restartDelay = 10 },
  [13] = { message = 'Versions mismatch', restartDelay = math.huge },
  [14] = { message = 'Audio device failure', restartDelay = 10 },
  [15] = { message = 'Failed to find remote address', restartDelay = 3 },
  [16] = { message = 'Failed to connect', restartDelay = 3 },
  [17] = { message = 'Disconnected', restartDelay = 3 },
  [18] = { message = 'Waiting for a slot to clear', restartDelay = 3 },
  [19] = { message = 'Invalid password', restartDelay = math.huge },
  [20] = { message = 'Server refused connection', restartDelay = math.huge },
}

local pushToTalkButton = ac.ControlButton('__EXT_PUSHTOTALK')

-- Actual state-storing implementation

---Create a new Mumble wrapper.
---@param mumbleParams MumbleConfig
---@return MumbleWrapper
return function(mumbleParams)

  ---@type MumbleConfig
  mumbleParams = table.chain({ host = 'localhost', port = 64738, channel = 'Root', use3D = true, maxDistance = 50, muteDistance = math.huge }, mumbleParams)

  -- Wrapper config

  local config = ac.storage({
    inputDevice = '',
    inputVolume = 1,
    inputMode = 'pushToTalk', ---@type 'alwaysSend'|'pushToTalk'|'amplitude'|'voiceActivity'
    inputMode_holdSeconds = 0.5,
    inputMode_amplitude_minValue = 0.02,
    inputMode_voiceActivity_start = 85,
    inputMode_voiceActivity_continue = 65,
    inputBitrate = 24000,
    inputDenoise_speex = false,
    inputDenoise_speexSuppress = -25,
    inputDenoise_rnn = false,
    inputEchoCancellation = false,
    inputEchoCancellation_suppress = -45,
    inputEchoCancellation_suppressActive = -45,
    inputAutoGainControl = false,
    inputAutoGainControl_level = 24000,
    
    outputDevice = '',
    outputVolume = 1,
    outputFMOD = true,
    outputDoppler = true,
    outputReverb = true,
    audioFade = 0.5,
    audioFade_others = true,
    audioFade_own = true,

    systemForceTCP = false,
    systemSetQOS = false,

    perUser = '{}',
    settingsShown = false,
  }, mumbleParams.configPrefix)

  local function needsSpeexDSP()
    return config.inputMode == 'voiceActivity' or config.inputDenoise_speex or config.inputEchoCancellation --or config.inputAutoGainControl_level
  end

  -- List of commands to send to “backend”

  local commandsList, commandsCount = {}, 0
  local function addCommand(key, ...)
    local command = key
		for i = 1, select('#', ...) do
      command = command..'\t'..encodeValue(select(i, ...))
		end
    commandsCount = commandsCount + 1
    commandsList[commandsCount] = command
  end

  -- Notify about errors reported when trying to do things

  local attemptedOperation = nil ---@type {time: number, operation: string}?
  local function makeAnAttempt(thing)
    attemptedOperation = {time = os.preciseClock(), operation = thing}
  end

  -- Connection point and “backend” process

  local mmfKey = 'AcTools.CSP.Mumble.v0__'..tostring(math.randomKey())
  local mmf = MumbleMMF(mmfKey)

  local logItems = {} ---@type string[]
  local processError = nil ---@type {message: string, timeOfAnotherAttempt: number}?
  local hideErrorMessage = false
  local ownSessionID = sim.isOnlineRace and ownCar.sessionID or 0
  local function startProcess()
    processError = nil
    table.clear(logItems)
    logItems[1] = 'i: Trying to establish Mumble connection…\n'
    table.clear(commandsList)
    commandsCount = 0
    ac.setWindowNotificationCounter('main', 0)
    os.runConsoleProcess({
      filename = ac.getFolder(ac.FolderID.ExtInternal)..'/plugins/AcTools.MumbleClient.exe',
      stdin = encodeConfig({
        ['system.connectPoint'] = mmfKey,
        ['system.streamConnectPointsPrefix'] = config.outputFMOD and mmfKey..'.' or '',
        ['system.forceTCP'] = config.systemForceTCP,
        ['system.setQOS'] = config.systemSetQOS,
        ['data.sendPosition'] = mumbleParams.use3D or (mumbleParams.muteDistance or math.huge) < 1e9,
        ['audio.inputBitrate'] = config.inputBitrate,
        ['audio.inputDevice'] = config.inputDevice,
        ['audio.inputDevice.volume'] = config.inputVolume,
        ['audio.outputDevice'] = config.outputDevice ~= '' and config.outputDevice or ac.getAudioOutputDevice(),
        ['audio.outputDevice.volume'] = config.outputVolume,
        ['server.host'] = mumbleParams.host,
        ['server.port'] = mumbleParams.port,
        ['server.password'] = mumbleParams.password,
        ['server.userID'] = ownSessionID,
        ['server.userAgent'] = 'AcTools.MumbleClient/'..tostring(ac.getPatchVersionCode()),
        ['user.channel'] = mumbleParams.channel,
        ['user.pluginContext'] = mumbleParams.context and ac.encodeBase64('Assetto Corsa'..string.char(0)..mumbleParams.context, false),
        ['user.pluginIdentity'] = mumbleParams.context and ownSessionID,
  
        ['audio.positional.bloom'] = 0,
        ['audio.positional.muteDistance'] = math.max(3, mumbleParams.muteDistance) or math.huge,
        ['audio.positional.maxDistance'] = math.max(3, mumbleParams.maxDistance),
        ['audio.positional.maxDistanceVolume'] = 0,
        ['audio.positional.minDistance'] = 1,
  
        ['audio.inputMode'] = config.inputMode,
        ['audio.inputMode.holdSeconds'] = config.inputMode_holdSeconds,
        ['audio.inputMode.amplitude.minValue'] = config.inputMode_amplitude_minValue,
        ['filter.speexDSP'] = needsSpeexDSP(),
        ['filter.speexDSP.denoise'] = config.inputDenoise_speex,
        ['filter.speexDSP.denoise.suppress'] = config.inputDenoise_speexSuppress,
        ['filter.speexDSP.echo'] = config.inputEchoCancellation,
        ['filter.speexDSP.echo.suppress'] = config.inputEchoCancellation_suppress,
        ['filter.speexDSP.echo.suppressActive'] = config.inputEchoCancellation_suppressActive,
        ['filter.speexDSP.autoGainControl'] = config.inputAutoGainControl,
        ['filter.speexDSP.autoGainControl.level'] = config.inputAutoGainControl_level,
        ['filter.speexDSP.voiceActivityDetector'] = config.inputMode == 'voiceActivity',
        ['filter.speexDSP.voiceActivityDetector.start'] = config.inputMode_voiceActivity_start,
        ['filter.speexDSP.voiceActivityDetector.continue'] = config.inputMode_voiceActivity_continue,
        ['filter.rnnNoise'] = config.inputDenoise_rnn,
        ['audio.outputDesiredLatency'] = 100,
        ['audio.inputBufferMilliseconds'] = 100,
      }),
      dataCallback = function (err, data)
        -- if not sim.isOnlineRace then
        --   ac.log(data:trim())
        -- end
        if string.byte(data, 1) == const(string.byte('!', 1)) and string.byte(data, 2) == const(string.byte(':', 1))
            and attemptedOperation and os.preciseClock() - attemptedOperation.time < 2 then
          ui.toast(ui.Icons.Warning, 'Failed to '..attemptedOperation.operation..': '..data:sub(4))
          attemptedOperation = nil
        end
        if #logItems > 60 then
          table.remove(logItems, 1)
        end
        logItems[#logItems + 1] = data
      end,
      terminateWithScript = true,
      timeout = 0,
    }, function (err, data)
      if err then
        ac.error('Failed to launch Mumble client', err)
      else
        local errorData = exitCodes[data.exitCode]
        if not errorData then
          ac.error('Mumble client shut down', data.exitCode)
          processError = {message = 'Mumble client shut down: '..tostring(data.exitCode)}
        elseif errorData.restartDelay == math.huge then
          processError = {message = errorData.message}
        else
          processError = {message = errorData.message, timeOfAnotherAttempt = errorData.restartDelay + os.preciseClock()}
          setTimeout(startProcess, errorData.restartDelay)
          errorData.restartDelay = errorData.restartDelay + 5
        end
        if data.exitCode ~= 0 then
          ac.setWindowNotificationCounter('main', -1)
        end
      end
    end)
  end
  startProcess()

  -- Commands for online scripts

  ---@param data {channel: string?, mute: boolean?}
  local function commandCallback(data)
    if type(data) ~= 'table' then ac.warn('invalid command', data) return end
    if type(data.channel) == 'string' then addCommand('user.channel', data.channel) end
    if type(data.mute) == 'boolean' then addCommand('user.selfMute', data.mute) end
  end
  -- ac.broadcastSharedEvent('app.csp.mumble', {channel = 'ch2'})
  -- ac.broadcastSharedEvent('app.csp.mumble', {mute = true})

  -- Car data holders

  local playerIcons = ui.UserIconsLayer(100)
  local headTransform = mat4x4()

  ---@alias PerUserCfg {muted: boolean, volume: number}
  ---@type PerUserCfg[]
  local perUser = stringify.tryParse(config.perUser) or {}
  local perUserUpdating = false

  ---@param applied PerUserCfg
  ---@param target PerUserCfg
  ---@param sessionID integer?
  ---@return boolean
  local function syncPerUser(applied, target, sessionID)
    if (target.muted ~= nil and applied.muted ~= target.muted) or (target.volume ~= nil and applied.volume ~= target.volume) then
      table.assign(applied, target)
      if sessionID then addCommand('action.configureUser', sessionID, applied.muted and 0 or applied.volume) end
      return true
    end
    return false
  end

  ---@param cfg PerUserCfg
  local function isPerUserDefault(cfg)
    return (cfg.volume == nil or cfg.volume == 1) and (cfg.muted == nil or cfg.muted == false)
  end

  ---@class CarData
  local CarData = class('CarData')

  ---@param car ac.StateCar
  ---@param sessionID integer
  function CarData:initialize(car, sessionID)
    self.car = car
    self.sessionID = sessionID
    self.lastConnectedTime = -1
    self.talkingSmoothness = ui.SmoothInterpolation(0, 1)
    self.talkingAnimation = 0
    self.talkingIcon = nil ---@type ui.ExtraCanvas?
    self.delayedVolume = delayed(1)
    self.peakVolume = -1
    self.drawnVolume = -1
    self.closeEnough = true
    self.player = nil ---@type ac.AudioEvent?
    self.driverName = nil ---@type string?
    self.driverConfig = {muted = false, volume = 1}
    self.appliedConfig = {muted = false, volume = 1}
    self.driverTags = nil ---@type ac.DriverTags?
    self.peakSmoothed = 0
    self.flags = 0

    if car.isConnected then
      self:onConnected()
    else
      self:onDisconnected()
    end
  end

  function CarData:onConnected()
    self.driverName = ac.getDriverName(self.car.index)
    self.driverTags = ac.DriverTags(self.driverName)
    self.driverConfig = perUser[self.driverName] or {muted = false, volume = 1}
    if self.driverConfig.muted ~= self.driverTags.muted then
      self.driverConfig.muted = self.driverTags.muted
      self:saveDriverConfig()
    end
    syncPerUser(self.appliedConfig, self.driverConfig, self.sessionID)
  end

  function CarData:onDisconnected()
    self.driverTags = nil
    if not self.appliedConfig.muted then
      self.appliedConfig.muted = true
      addCommand('action.configureUser', self.sessionID, 0)
    end
  end

  function CarData:saveDriverConfig()
    if isPerUserDefault(self.driverConfig) then
      perUser[self.driverName] = nil
    else
      perUser[self.driverName] = self.driverConfig
    end
    if not perUserUpdating then
      perUserUpdating = true
      setTimeout(function ()
        config.perUser = stringify(perUser, true)
        perUserUpdating = false
      end)
    end    
  end

  ---@param params PerUserCfg
  function CarData:configure(params)
    if params.muted ~= nil and self.driverTags then
      self.driverTags.muted = params.muted
    end
    if self.car.isConnected then
      if syncPerUser(self.appliedConfig, params, self.sessionID) then
        table.assign(self.driverConfig, params)
        self:saveDriverConfig()
      end
    end
  end

  function CarData:restartFMODStream()
    if self.player then
      self.player:dispose()
      self.player = nil
    end
  end

  function CarData:isMumbleConnected()
    return os.preciseClock() < self.lastConnectedTime + 0.5
  end

  function CarData:getMumbleColor()
    if self.talkingAnimation > 0.01 then
      return rgbm.colors.cyan
    elseif self:isMumbleConnected() then
      return rgbm.colors.lime
    else
      return rgbm.colors.gray
    end
  end

  ---@param user MumbleMMF.User
  ---@param dt number
  function CarData:update(user, volumeBoost, dt)
    -- In case driver name changes without reconnection:
    if ac.getDriverName(self.car.index) ~= self.driverName then
      self:onDisconnected()
      self:onConnected()
    end

    self.lastConnectedTime = os.preciseClock()
    self.flags = user.flags

    if self.driverTags and self.driverTags.muted ~= self.driverConfig.muted then
      self:configure({muted = self.driverTags.muted})
    end

    local flagTalking = HAS_FLAG(self, FLAG_TALKING) and self.car.isConnected
    if not flagTalking and self.talkingAnimation < 0.001 and self.peakSmoothed < 0.02 then
      if self.player then self.player.volume = 0 end
      return false
    end

    self.peakVolume = self.delayedVolume(tonumber(user.peakVolume) / 255, 0.1)
    self.talkingAnimation = self.talkingSmoothness(flagTalking and 1 or 0)
    self.talkingIcon = getTalkingIcon(self.peakVolume)
    playerIcons(self.car.index, flagTalking and self.talkingIcon or nil)

    if math.abs(self.peakVolume - self.peakSmoothed) > 0.01 then
      self.peakSmoothed = math.applyLag(self.peakSmoothed, self.peakVolume, 0.85, dt)
      ac.setDriverMouthOpened(self.car.index, math.lerpInvSat(self.peakSmoothed, 0.1, 0.6))
    end

    local flagHasStream = HAS_FLAG(self, FLAG_STREAM)
    if flagHasStream then
      if not self.player then
        self.player = self:_createStream()
      end
      self.player.volume = volumeBoost * config.outputVolume * math.max(0, 1 - self.car.distanceToCamera / mumbleParams.muteDistance)
      if mumbleParams.use3D then
        ac.getDriverHeadTransformTo(headTransform, self.car.index)
        self.player:setPosition(headTransform.position, headTransform.look:normalize(), headTransform.up, self.car.velocity)
      end
    elseif self.player then
      self.player:dispose()
      self.player = nil
    end

    return self.talkingAnimation > 0.01
  end

  function CarData:_createStream()
    local player = ac.AudioEvent.fromFile({
      stream = { name = mmfKey..'.'..self.sessionID, size = mmf.streamConnectPointSize },
      use3D = mumbleParams.use3D,
      useOcclusion = true,
      maxDistance = math.max(3, mumbleParams.maxDistance),
      minDistance = 1,
      insideConeAngle = 120,
      outsideConeAngle = 240,
      outsideVolume = 0.6,
      dopplerEffect = (mumbleParams.use3D and config.outputDoppler) and 1 or 0
    }, mumbleParams.use3D and config.outputReverb or false)
    player.volume = config.outputVolume
    player.cameraExteriorMultiplier = 1
    player.cameraInteriorMultiplier = 1
    player.cameraTrackMultiplier = 1
    return player
  end

  ---@type CarData[]
  local carCache = table.range(sim.carsCount - 1, 0, function (i)
    local car = ac.getCar(i)
    if car then
      local key = sim.isOnlineRace and car.sessionID or car.index
      return CarData(car, key), key
    end
  end)

  ---@return CarData
  local function getExtrasFor(sessionID)
    return carCache[sessionID]
  end

  local function updateFMODStreamsVolume()
    for i = 0, #carCache do
      local player = carCache[i].player
      if player then
        player.volume = config.outputVolume
      end
    end
  end

  local function restartFMODStreams()
    for i = 0, #carCache do
      carCache[i]:restartFMODStream()
    end
  end

  ac.onClientConnected(function (_, connectedSessionID) getExtrasFor(connectedSessionID):onConnected() end)
  ac.onClientDisconnected(function (_, connectedSessionID) getExtrasFor(connectedSessionID):onDisconnected() end)

  -- Syncing state with “backend”

  local talkingList, talkingCount = {}, 0 ---@type CarData[], integer
  local lastChannelsPhase, channelsData, channelsMap = -1, {}, {} ---@type integer, MumbleMMF.Channel, table<integer, MumbleMMF.Channel>
  local volumeMultiplier = 1
  local actualVolumeMultiplier = 1
  local lastMicRequireFrame = 0
  local lastServerLoopbackFrame = 0
  local ownMutedSmoothness = ui.SmoothInterpolation(0, 1)
  local ownMutedAnimation = 0
  local volumeListener = nil ---@type fun()?
  
  ---@param item MumbleMMF.Channel
  ---@param parent MumbleMMF.Channel?
  local function finalizeChannel(item, parent)
    item.parent = parent
    channelsMap[item.id] = item
    for _, v in ipairs(item.children) do finalizeChannel(v, item) end
  end

  ---@param root MumbleMMF.Channel
  local function finalizeChannels(root)
    channelsData = root
    table.clear(channelsMap)
    if root then
      finalizeChannel(root, nil)
    end
  end

  local subscriptions = nil ---@type fun()[]?
  local listenerTooltip, listenerContextMenu
  
  local function syncState(dt)
    if mmf.numCurrentlyConnected < 1 or processError then
      if subscriptions then
        table.forEach(subscriptions, function (item) item() end)
        subscriptions = nil
      end
    elseif not subscriptions then
      subscriptions = {
        ui.onDriverTooltip(false, listenerTooltip),
        ui.onDriverContextMenu(listenerContextMenu),
        ac.onSharedEvent('app.csp.mumble', commandCallback, true)
      }
    end
    
    if processError then
      if mmf.frameIndex > 0 then
        restartFMODStreams()
        mmf.frameIndex = 0
        table.clear(talkingList)
        talkingCount = 0
        actualVolumeMultiplier = 1
        if volumeListener then
          volumeListener()
          volumeListener = nil
        end
        for i = 0, sim.carsCount - 1 do
          ac.setDriverMouthOpened(i, 0)
        end
      end
      return
    end

    if hideErrorMessage then
      hideErrorMessage = false
    end
  
    mmf.frameIndex = mmf.frameIndex + 1
    mmf.listenerPos:set(sim.cameraPosition)
    mmf.listenerDir:set(sim.cameraLook)
    mmf.listenerUp:set(sim.cameraUp)
    ownCar.bodyTransform:transformPointTo(mmf.audioSourcePos, ownCar.driverEyesPosition)
    mmf.pushToTalk = pushToTalkButton:down()

    local ownMuted = HAS_FLAG(mmf.currentlyConnected[0], FLAG_MUTED_ANY) and (config.inputMode ~= 'pushToTalk' or mmf.pushToTalk)
    ownMutedAnimation = ownMutedSmoothness(ownMuted and 1 or 0)

    if mmf.frameIndex > lastMicRequireFrame then
      mmf.requireMicPeak = false
    end
    if mmf.frameIndex > lastServerLoopbackFrame then
      mmf.serverLoopback = false
    end

    if talkingCount > 0 then
      table.clear(talkingList)
      talkingCount = 0
    end
    local volumeBoost = 1 / actualVolumeMultiplier
    local othersTalking = false

    local fadeOthers = config.audioFade_others
    local fadeOwn = config.audioFade_own
    for i = 0, mmf.numCurrentlyConnected - 1 do
      local user = mmf.currentlyConnected[i]
      local ex = getExtrasFor(tonumber(user.sessionID))
      if ex and ex:update(user, volumeBoost, dt) then
        talkingCount = talkingCount + 1
        talkingList[talkingCount] = ex

        local fade
        if ex.car.index > 0 or mmf.serverLoopback then
          fade = fadeOthers
        else
          fade = fadeOwn
        end
        if fade then
          othersTalking = true
        end
      end
    end

    volumeMultiplier = othersTalking and math.max(volumeMultiplier - dt * 3, 0) or math.min(volumeMultiplier + dt * 3, 1)
    actualVolumeMultiplier = math.lerp(config.audioFade, 1, volumeMultiplier)

    if actualVolumeMultiplier > 0.999 then
      if volumeListener then
        volumeListener()
        volumeListener = nil
      end
    elseif not volumeListener then
      volumeListener = ac.onAudioVolumeCalculation(function () return actualVolumeMultiplier end)
    end

    if commandsCount > 0 and mmf.numCommands == 0 and mmf.numCurrentlyConnected > 0 then
      local commandsToSubmit = math.min(commandsCount, DEF_MAX_COMMAND_COUNT)
      for i = 0, commandsToSubmit - 1 do
        ac.stringToFFIStruct(commandsList[i + 1], mmf.commands[i].value, DEF_COMMAND_SIZE)
      end
      mmf.numCommands = commandsToSubmit
      if commandsCount <= DEF_MAX_COMMAND_COUNT then
        table.clear(commandsList)
      else
        commandsList = table.slice(commandsList, DEF_MAX_COMMAND_COUNT + 1)
      end
      commandsCount = commandsCount - commandsToSubmit
    end

    if mmf.channelsPhase ~= lastChannelsPhase then
      lastChannelsPhase = mmf.channelsPhase
      finalizeChannels(JSON.parse(ffi.string(mmf.channelsData)))
    end
  end

  -- Controls

  local icons = ui.atlasIcons('res/icons.png', 4, 1, {
    FMOD = {1, 1},
    ZeroPercent = {1, 2},
    VolumeMuted = {1, 3},
  })

  local stateIconSize = vec2(8, 8)
  listenerTooltip = function(carIndex)
    local ex = getExtrasFor(carIndex)
    if ex then
      local icon, color, text
      if ex.driverConfig.muted then
        icon, color, text = ui.Icons.Ban, rgbm.colors.red, 'Muted by you'
      elseif ex.driverConfig.volume == 0 then
        icon, color, text = icons.ZeroPercent, rgbm.colors.yellow, 'Volume is set to 0%'
      elseif HAS_FLAG(ex, FLAG_SUPRESSED) then
        icon, color, text = ui.Icons.MicrophoneMuted, rgbm.colors.lime, 'Supressed'
      elseif HAS_FLAG(ex, FLAG_MUTED) then
        icon, color, text = ui.Icons.MicrophoneMuted, rgbm.colors.cyan, 'Muted'
      elseif HAS_FLAG(ex, FLAG_SELF_MUTED) then
        icon, color, text = ui.Icons.MicrophoneMuted, rgbm.colors.red, 'Self-muted'
      elseif HAS_FLAG(ex, FLAG_DEAF) then
        icon, color, text = icons.VolumeMuted, rgbm.colors.cyan, 'Deaf'
      elseif HAS_FLAG(ex, FLAG_SELF_DEAF) then
        icon, color, text = icons.VolumeMuted, rgbm.colors.red, 'Self-deaf'
      else
        if ex.talkingAnimation > 0.01 then
          text, icon = 'Currently speaking', ui.Icons.Microphone
        elseif ex:isMumbleConnected() then
          text, icon = 'Connected to voice chat', ui.Icons.Confirm
        else
          text, icon = 'Not connected to voice chat', ui.Icons.Cancel
        end
        color = ex:getMumbleColor()
      end

      ui.text(text)
      ui.sameLine(0, 4)
      ui.offsetCursorY(4)
      ui.icon(icon, stateIconSize, color)
    end
  end

  listenerContextMenu = function(carIndex)
    local ex = getExtrasFor(carIndex)
    if ex then
      ui.setNextItemWidth(ui.availableSpaceX())
      if ex.car.index == 0 then
        config.inputVolume = ui.slider('##volume', config.inputVolume * 100, 0, 100, 'Microphone volume: %.0f%%') / 100
        if ui.itemEdited() then
          addCommand('audio.inputDevice.volume', config.inputVolume)
        end
      else
        local newVolume = ui.slider('##volume', ex.driverConfig.volume * 100, 0, 100, 'Voice volume: %.0f%%') / 100
        if ui.itemEdited() then
          ex:configure({volume = newVolume})
        end
      end
    end
  end

  local contextMenuOpened = nil ---@type {[1]: CarData?, [2]: boolean}?
  local tmpVec2 = vec2()

  ---@param cur vec2
  ---@param icon ui.Icons
  ---@param color rgbm
  local function CtrlUsers_UserIcon(cur, threshold, icon, color, hint)
    if cur.x < threshold then return end
    ui.drawIcon(icon, cur, tmpVec2:set(cur):add(11), color)
    if ui.rectHovered(cur, tmpVec2) then
      ui.setTooltip(hint)
    end
    cur.x = cur.x - 16
  end

  local function CtrlUsers_Users(startFrom, channelID)
    for i = startFrom, mmf.numCurrentlyConnected - 1 do
      local user = mmf.currentlyConnected[i]
      if user.channelID == channelID then
        local ex = getExtrasFor(tonumber(user.sessionID) or -1)
        if ex and ex.car.isConnected then
          ui.offsetCursorX(10)
          ui.pushID(ex.sessionID)
          local cur = ui.getCursor()
          if ex.talkingAnimation > 0.01 then
            ui.drawIcon(ex.talkingIcon, ui.getCursor() + 2, ui.getCursor() + 13, ex:getMumbleColor())
          else
            ui.drawIcon(ui.Icons.User, ui.getCursor() + 2, ui.getCursor() + 13, ex:getMumbleColor())
          end
          ui.offsetCursorX(18)
          ui.textColored(ex.driverName, ex.driverTags and ex.driverTags.color or rgbm.colors.white)
          ui.sameLine()
          local t = ui.getCursorX()
          ui.setCursor(cur)
          ui.invisibleButton('##user', vec2(ui.availableSpaceX(), 17))

          if ui.itemHovered() then
            ui.setDriverTooltip(ex.car.index)
            if ui.itemClicked(ui.MouseButton.Left) then
              ui.mentionDriverInChat(ex.car.index, true)
            elseif ui.itemClicked(ui.MouseButton.Right) then
              contextMenuOpened = {ex, false}
            end
          end

          cur.y = cur.y + 2
          cur.x = cur.x + ui.availableSpaceX() - 20

          if ex.driverConfig.muted then
            CtrlUsers_UserIcon(cur, t, ui.Icons.Ban, rgbm.colors.red, 'Muted by you')
          elseif ex.driverConfig.volume == 0 then
            CtrlUsers_UserIcon(cur, t, icons.ZeroPercent, rgbm.colors.yellow, 'Volume is set to 0%')
          end
          if HAS_FLAG(user, FLAG_SUPRESSED) then
            CtrlUsers_UserIcon(cur, t, ui.Icons.MicrophoneMuted, rgbm.colors.lime, 'Supressed')
          end
          if HAS_FLAG(user, FLAG_MUTED) then
            CtrlUsers_UserIcon(cur, t, ui.Icons.MicrophoneMuted, rgbm.colors.cyan, 'Muted')
          elseif HAS_FLAG(user, FLAG_SELF_MUTED) then
            CtrlUsers_UserIcon(cur, t, ui.Icons.MicrophoneMuted, rgbm.colors.red, 'Self-muted')
          end
          if HAS_FLAG(user, FLAG_DEAF) then
            CtrlUsers_UserIcon(cur, t, icons.VolumeMuted, rgbm.colors.cyan, 'Deaf')
          elseif HAS_FLAG(user, FLAG_SELF_DEAF) then
            CtrlUsers_UserIcon(cur, t, icons.VolumeMuted, rgbm.colors.red, 'Self-deaf')
          end

          ui.popID()
        end
      end
    end
  end

  ---@param channel MumbleMMF.Channel 
  local function CtrlUsers_Channel(channel)
    if channel.description == 'hidden' then
      return
    end

    local start = ui.getCursor()
    local hovered = ui.rectHovered(start, start + vec2(ui.availableSpaceX(), 17))

    if #channel.children == 0 and channel.currentUsers == 0 then
      ui.offsetCursorX(30)
      ui.text(channel.name)
    else
      local firstConnected = 256
      for i = 0, mmf.numCurrentlyConnected - 1 do
        if mmf.currentlyConnected[i].channelID == channel.id then
          firstConnected = i
          break
        end
      end

      if firstConnected == 0 then
        ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 0, 1))
      end

      local flags = ui.TreeNodeFlags.OpenOnArrow
      if channel.currentUsers > 0 then flags = bit.bor(flags, ui.TreeNodeFlags.DefaultOpen) end
      if channel.parent == nil then flags = bit.bor(flags, ui.TreeNodeFlags.NoArrow, ui.TreeNodeFlags.NoTreePushOnOpen) end
      if ui.beginTreeNode(channel.currentUsers > 0 and string.format('%s (%d)', channel.name, channel.currentUsers) or channel.name, flags) then
        if firstConnected == 0 then
          ui.popStyleColor()
        end
        using(function ()
          for _, v in ipairs(channel.children) do
            CtrlUsers_Channel(v)
          end
          CtrlUsers_Users(firstConnected, channel.id)
        end, ui.endTreeNode)
      else
        if firstConnected == 0 then
          ui.popStyleColor()
        end
      end
    end

    start.x = start.x + ui.availableSpaceX() - 10
    start.y = start.y + 2

    if channel.description then
      ui.drawIcon(ui.Icons.Notifications, start, start + 11, rgbm.colors.yellow)
      start.x = start.x - 16
      if hovered then
        ui.setTooltip(channel.description)
      end
    end

    if not channel.canEnter then
      ui.drawIcon(ui.Icons.Padlock, start, start + 11, rgbm.colors.red)
      start.x = start.x - 16
    elseif channel.isEnterRestricted then
      ui.drawIcon(ui.Icons.PadlockUnlocked, start, start + 11, rgbm.colors.red)
      start.x = start.x - 16
    end

    if channel.maxUsers > 0 and channel.directUsers >= channel.maxUsers then
      ui.drawIcon(ui.Icons.Group, start, start + 11, rgbm.colors.white)
    end

    if hovered and uiState.isMouseLeftKeyDoubleClicked then
      makeAnAttempt('change channel')
      addCommand('user.channel', channel.name)
    end
  end

  local function CtrlUsers()
    if channelsData == nil then
      ac.setWindowTitle('main', 'Voice Chat')
      ui.textWrapped('Getting channel data…')
    elseif #channelsData.children > 0 then
      local ownChannel = channelsMap[mmf.currentlyConnected[0].channelID]
      if ownChannel and ownChannel.description == 'hidden' then
        ac.setWindowTitle('main', 'Voice Chat')
        CtrlUsers_Users(0, ownChannel.id)
      else
        ac.setWindowTitle('main', '')
        ui.offsetCursorX(-12)
        ui.offsetCursorY(-26)
        ui.pushClipRect(vec2(0, ui.getScrollY()), ui.windowSize():add(vec2(0, ui.getScrollY())), false)
        for _, v in pairs(channelsMap) do
          v.currentUsers = 0
          v.directUsers = 0
        end
        for i = 0, mmf.numCurrentlyConnected - 1 do
          local c = channelsMap[mmf.currentlyConnected[i].channelID]
          if c ~= nil then
            c.directUsers = c.directUsers + 1
            while c ~= nil do
              c.currentUsers = c.currentUsers + 1
              c = c.parent
            end
          end
        end
        -- ui.setMaxCursorY(ui.getCursorY)
        CtrlUsers_Channel(channelsData)
        ui.popClipRect()
      end
    else
      ac.setWindowTitle('main', 'Voice Chat')
      CtrlUsers_Users(0, channelsData.id)
    end
  end

  local overlayItemSize = vec2(160, 24)
  local overlayItemColor = rgbm(0, 0, 0, 0.5)
  local overlayItemHoveredColor = rgbm(0, 0, 0, 0.6)
  local overlayIconPos1 = vec2(8, 4)
  local overlayIconPos2 = vec2(24, 20)
  local overlayIconPosR = vec2(8 + 8.3, 4 + 8.3)
  local overlayTextOffset = vec2(30, 4)
  local overlayButtonsRect1 = vec2(0, -24)
  local overlayButtonsRect2 = vec2(160, 0)
  local errorSmoothness = ui.SmoothInterpolation(0, 1)
  local errorAnimation = 0
  local popupButtonsSmoothness = ui.SmoothInterpolation(0, 1)
  local popupButtonsAnimation = 0
  local fadeWindowIn = false
  local needsButton = false

  local function OverlayRect(pos1, pos2)
    local hovered = ui.rectHovered(pos1, pos2)
    ui.drawRectFilled(pos1, pos2, hovered and overlayItemHoveredColor or overlayItemColor, 2)
    return hovered
  end

  local function CtrlTalkingUsers_List()
    local cur = vec2()
    local windowHovered = ui.windowHovered()
    local buttonsHovered = ui.rectHovered(overlayButtonsRect1, overlayButtonsRect2, false)
    local hovered = windowHovered or buttonsHovered

    if popupButtonsAnimation > 0.01 then
      ui.pushStyleVarAlpha(popupButtonsAnimation)
      ui.pushClipRect(vec2(0, -30 * popupButtonsAnimation), vec2(160, 0), false)

      local btn1Hovered = OverlayRect(vec2(6, -24), vec2(26, -4))
      ui.drawIcon(ui.Icons.List, vec2(9, -21), vec2(23, -7))
      if btn1Hovered then
        ui.setTooltip(ac.isWindowOpen('main') and 'Hide voice chat list' or 'Show voice chat list')
        if ui.mouseClicked() then
          ac.setWindowOpen('main', not ac.isWindowOpen('main'))
          fadeWindowIn = true
        end
      end

      local btn2Hovered = OverlayRect(vec2(30, -24), vec2(50, -4))
      ui.drawIcon(ui.Icons.Settings, vec2(33, -21), vec2(47, -7))
      if btn2Hovered then
        ui.setTooltip(ac.isWindowOpen('main.settings') and 'Hide voice chat settings' or 'Show voice chat settings')
        if ui.mouseClicked() then
          ac.setWindowOpen('main.settings', not ac.isWindowOpen('main.settings'))
        end
      end
      ui.popClipRect()
      ui.popStyleVar()
    end
    popupButtonsAnimation = popupButtonsSmoothness(hovered and 1 or 0)

    if processError or needsButton then
      local height = 30 * errorAnimation
      errorAnimation = errorSmoothness(hideErrorMessage and 0 or 1)
      if height - 6 > 0.5 then
        if errorAnimation < 0.99 then
          ui.pushClipRect(cur, cur + vec2(160, height - 6), true)
        end
        if processError then
          if processError.timeOfAnotherAttempt then
            local itemHovered = OverlayRect(cur, cur + overlayItemSize)
            ui.beginRotation()
            ui.drawIcon(ui.Icons.Loading, cur + overlayIconPos1, cur + overlayIconPos2, rgbm.colors.white)
            ui.endPivotRotation(math.round(os.preciseClock() * -10) * 45, cur + overlayIconPosR)
            ui.drawText('Voice chat issues…', cur + overlayTextOffset, rgbm.colors.white)
            if itemHovered then
              local timeLeft = processError.timeOfAnotherAttempt - os.preciseClock()
              ui.setTooltip(string.format('%s\nNext attempt: %.1f s\nClick to dismiss', processError.message, math.max(timeLeft, 0)))
              if ui.mouseClicked() then
                hideErrorMessage = true
              end
            end
          else
            local itemHovered = OverlayRect(cur, cur + overlayItemSize)
            ui.drawIcon(ui.Icons.Warning, cur + overlayIconPos1, cur + overlayIconPos2, rgbm.colors.white)
            ui.drawText('Voice chat error', cur + overlayTextOffset, rgbm.colors.white)
            if itemHovered then
              ui.setTooltip(processError.message..'\nClick to dismiss')
              if ui.mouseClicked() then
                hideErrorMessage = true
              end
            end
          end
        else
          local itemHovered = OverlayRect(cur, cur + overlayItemSize)
          ui.drawIcon(ui.Icons.Info, cur + overlayIconPos1, cur + overlayIconPos2, rgbm.colors.white)
          ui.drawText('Configure voice chat', cur + overlayTextOffset, rgbm.colors.white)
          if itemHovered then
            ui.setTooltip('Choose automatic input mode or configure Push-to-Talk button\nClick to open settings')
            if ui.mouseClicked() then
              config.settingsShown = true
              ac.setWindowOpen('main.settings', true)
            end
          end
        end
        if errorAnimation < 0.99 then
          ui.popClipRect()
        end
      end
      return
    end

    if ownMutedAnimation > 0.01 then
      local height = 30 * ownMutedAnimation
      if height - 6 > 0.5 then
        if ownMutedAnimation < 0.99 then
          ui.pushClipRect(cur, cur + vec2(160, height - 6), true)
        end
        local itemHovered = OverlayRect(cur, cur + overlayItemSize)
        ui.drawIcon(ui.Icons.MicrophoneMuted, cur + overlayIconPos1, cur + overlayIconPos2, rgbm.colors.red)
        ui.drawText('You’re muted', cur + overlayTextOffset, rgbm.colors.white)
        if itemHovered then
          ui.setTooltip('This state is controlled externally, either by a server config, by a script or by a Mumble server admin')
        end
        if ownMutedAnimation < 0.99 then
          ui.popClipRect()
        end
      end
    end

    for i = 1, talkingCount do
      local ex = talkingList[i]
      if ex.talkingAnimation > 0.01 then
        local height = 30 * ex.talkingAnimation
        if height - 6 > 0.5 then
          if ex.talkingAnimation < 0.99 then
            ui.pushClipRect(cur, cur + vec2(160, height - 6), true)
          end
          local itemHovered = OverlayRect(cur, cur + overlayItemSize)
          ui.drawImage(ex.talkingIcon, cur + overlayIconPos1, cur + overlayIconPos2)
          ui.drawText(ex.driverName, cur + overlayTextOffset, ex.driverTags.color)
          if itemHovered then
            ui.setDriverTooltip(ex.car.index)
            if ui.itemClicked(ui.MouseButton.Left) then
              ui.mentionDriverInChat(ex.car.index, true)
            elseif ui.itemClicked(ui.MouseButton.Right) then
              contextMenuOpened = {ex, false}
            end
          end
          if ex.talkingAnimation < 0.99 then
            ui.popClipRect()
          end
        end
        cur.y = cur.y + 30 * ex.talkingAnimation
      end
    end

    if contextMenuOpened then
      if not contextMenuOpened[2] then
        ui.openPopup('driverContextMenu')
        contextMenuOpened[2] = true
      end
      if not ui.setDriverPopup('driverContextMenu', contextMenuOpened[1].car.index) then
        contextMenuOpened = nil
      end
    end
  end

  local usersWindowPos = vec2(0, 40)
  local usersWindowSize = vec2(160, 0)
  local function CtrlTalkingUsers()
    needsButton = not config.settingsShown and config.inputMode == 'pushToTalk' and not pushToTalkButton:configured() and mmf.numCurrentlyConnected > 1 and mmf.numInputDevices > 0
    local size = (processError or needsButton) and (hideErrorMessage and errorAnimation < 0.01 and 0 or 1)
      or (talkingCount + ((ownMutedAnimation > 0.01 or popupButtonsAnimation > 0.01) and 1 or 0))
    if popupButtonsAnimation > 0.01 and size == 0 then size = 1 end
    if size == 0 and contextMenuOpened == nil then return end
    usersWindowPos.x, usersWindowSize.y = uiState.windowSize.x - 180, 30 * size
    ui.setCursor(usersWindowPos)
    ui.childWindow('mumble_Talking', usersWindowSize, false, 0, CtrlTalkingUsers_List)
  end

  ---@param num integer
  ---@param list MumbleMMF.Device[]
  ---@param key string
  ---@param fmodOutput boolean?
  local function CtrlDeviceList(num, list, key, fmodOutput)
    if ui.frameCount() % 32 == 0 then
      addCommand('action.updateDevices')
    end

    if num == 0 and not fmodOutput then
      ui.pushDisabled()
      ui.combo('##'..key, 'No devices found', function () end)
      ui.popDisabled()
      return
    end
  
    local selectedName, selectedIcon
    if fmodOutput and config.outputFMOD then
      selectedName = 'FMOD'
      selectedIcon = icons.FMOD
    else
      local selected = list[0]
      for i = 0, num - 1 do
        if HAS_FLAG(list[i], FLAG_SELECTED) then
          selected = list[i]
        end
      end
      selectedName = ffi.string(selected.name)
      selectedIcon = ffi.string(selected.icon)
    end

    ui.combo('##'..key, '\t '..selectedName, function ()
      if fmodOutput then
        if ui.selectable('\t  FMOD', config.outputFMOD) and not config.outputFMOD then
          addCommand('system.streamConnectPointsPrefix', mmfKey..'.')
          config.outputFMOD = true
        end
        if ui.itemHovered() then
          ui.setTooltip('Use in-game audio for better spatial playback')
        end
        ui.addIcon(icons.FMOD, vec2(16, 16), vec2(0, 0.5))
      end

      for i = 0, num - 1 do
        local name = ffi.string(list[i].name)
        if ui.selectable('\t  '..name, list[i] == selectedName) then
          addCommand('audio.'..key, name)
          if fmodOutput and config.outputFMOD then
            addCommand('system.streamConnectPointsPrefix', nil)
            config.outputFMOD = false
            restartFMODStreams()
          end
          config[key] = name
        end
        ui.addIcon(ffi.string(list[i].icon), vec2(16, 16), vec2(0, 0.5))
      end
    end)
    ui.addIcon(selectedIcon, vec2(16, 16), vec2(0, 0.5))
  end

  local settingsInputModes = {
    { value = 'alwaysSend', name = 'Continuous', description = 'Stream audio constantly', settings = function () end },
    { value = 'pushToTalk', name = 'Push-to-Talk', description = 'Hold a button to talk', settings = function ()
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      ui.alignTextToFramePadding()
      ui.text('Button:')
      ui.sameLine(200)
      pushToTalkButton:control(vec2(ui.availableSpaceX(), 0))
    end },
    { value = 'amplitude', name = 'Amplitude threshold', description = 'Send audio if a certain threshold is reached', settings = function ()
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      ui.pushItemWidth(ui.availableSpaceX())
      config.inputMode_holdSeconds = ui.slider('##hold', config.inputMode_holdSeconds, 0, 5, 'Hold for: %.1f s')
      if ui.itemEdited() then addCommand('audio.inputMode.holdSeconds', config.inputMode_holdSeconds) end
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      config.inputMode_amplitude_minValue = ui.slider('##amv', config.inputMode_amplitude_minValue * 100, 0, 10, 'Threshold: %.1f%%') / 100
      if ui.itemEdited() then addCommand('audio.inputMode.amplitude.minValue', config.inputMode_amplitude_minValue) end
    end },
    { value = 'voiceActivity', name = 'Voice detection', description = 'Uses SpeexDSP library to detect voice', settings = function () 
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      ui.pushItemWidth(ui.availableSpaceX())
      config.inputMode_holdSeconds = ui.slider('##hold', config.inputMode_holdSeconds, 0, 5, 'Hold for: %.1f s')
      if ui.itemEdited() then addCommand('audio.inputMode.holdSeconds', config.inputMode_holdSeconds) end
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      config.inputMode_voiceActivity_start = ui.slider('##vas', config.inputMode_voiceActivity_start, 0, 100, 'Start probability: %.0f%%')
      if ui.itemEdited() then addCommand('filter.speexDSP.voiceActivityDetector.start', config.inputMode_voiceActivity_start) end
      if ui.itemHovered() then ui.setTooltip('Probability required for SpeexDSP to detect voice for the first time') end
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      config.inputMode_voiceActivity_continue = ui.slider('##vac', config.inputMode_voiceActivity_continue, 0, 100, 'Continue probability: %.0f%%')
      if ui.itemEdited() then addCommand('filter.speexDSP.voiceActivityDetector.continue', config.inputMode_voiceActivity_continue) end
      if ui.itemHovered() then ui.setTooltip('Probability required for SpeexDSP to continue detecting voice') end
    end },
  }

  local settingsTabs = {
    { name = 'Recording', icon = ui.Icons.Microphone, content = function ()
      lastMicRequireFrame = mmf.frameIndex + 4
      mmf.requireMicPeak = true

      ui.alignTextToFramePadding()
      ui.text('Device:')
      ui.sameLine(SETTINGS_COLUMN_WIDTH)
      ui.pushItemWidth(ui.availableSpaceX())
      CtrlDeviceList(mmf.numInputDevices, mmf.inputDevices, 'inputDevice')
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      ui.setNextItemWidth(ui.availableSpaceX())
      config.inputVolume = ui.slider('##inputVolume', config.inputVolume * 100, 0, 100, 'Volume: %.0f%%') / 100
      if ui.itemEdited() then
        addCommand('audio.inputDevice.volume', config.inputVolume)
      end

      ui.offsetCursorY(20)
      
      ui.text('Mode:')
      ui.sameLine(SETTINGS_COLUMN_WIDTH)
      ui.setNextItemWidth(ui.availableSpaceX())
      local currentMode = table.findFirst(settingsInputModes, function (item) return item.value == config.inputMode end) or settingsInputModes[1]
      ui.combo('##mode', currentMode.name, ui.ComboFlags.None, function ()
        for _, v in ipairs(settingsInputModes) do
          if ui.selectable(v.name, v == currentMode) then
            config.inputMode = v.value
            addCommand('audio.inputMode', config.inputMode)
            addCommand('filter.speexDSP', needsSpeexDSP())
            addCommand('filter.speexDSP.voiceActivityDetector', config.inputMode == 'voiceActivity')
          end
          if ui.itemHovered() then
            ui.setTooltip(v.description)
          end
        end
      end)
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if HAS_FLAG(mmf.currentlyConnected[0], FLAG_IMMEDIATE_TALKING) then
        ui.pushStyleColor(ui.StyleColor.PlotHistogram, rgbm.colors.cyan)
        ui.progressBar(mmf.micPeak, vec2(ui.availableSpaceX(), 2))
        ui.popStyleColor()
      else
        ui.progressBar(mmf.micPeak, vec2(ui.availableSpaceX(), 2))
      end
      currentMode.settings()

      ui.offsetCursorY(20)
      
      ui.text('Quality:')
      ui.sameLine(SETTINGS_COLUMN_WIDTH)
      ui.setNextItemWidth(ui.availableSpaceX())
      local newBitrate, bitrateChanged = ui.slider('##bitrate', mmf.bitrate / 1e3, 8, 96, 'Compression bitrate: %.0f KHz')
      if bitrateChanged then
        mmf.bitrate = math.max(math.round(newBitrate) or 8, 1) * 1e3
        config.inputBitrate = mmf.bitrate
        addCommand('audio.inputBitrate', mmf.bitrate)
      end

      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if ui.checkbox('SpeexDSP noise supression', config.inputDenoise_speex) then
        config.inputDenoise_speex = not config.inputDenoise_speex
        addCommand('filter.speexDSP', needsSpeexDSP())
        addCommand('filter.speexDSP.denoise', config.inputDenoise_speex)
      end
      if config.inputDenoise_speex then
        ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
        config.inputDenoise_speexSuppress = -ui.slider('##speexamount', -config.inputDenoise_speexSuppress, 1, 99, 'Strength: -%.0f dB')
        if ui.itemEdited() then
          addCommand('filter.speexDSP.denoise.suppress', config.inputDenoise_speexSuppress)
        end
      end
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if ui.checkbox('RNNoise noise supression', config.inputDenoise_rnn) then
        config.inputDenoise_rnn = not config.inputDenoise_rnn
        addCommand('filter.rnnNoise', config.inputDenoise_rnn)
      end
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if ui.checkbox('Echo cancellation', config.inputEchoCancellation) then
        config.inputEchoCancellation = not config.inputEchoCancellation
        addCommand('filter.speexDSP', needsSpeexDSP())
        addCommand('filter.speexDSP.echo', config.inputEchoCancellation)
      end
      if config.inputEchoCancellation then
        ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
        config.inputEchoCancellation_suppress = -ui.slider('##speexechosuppress', -config.inputEchoCancellation_suppress, 1, 99, 'Echo suppress: -%.0f dB')
        if ui.itemEdited() then
          addCommand('filter.speexDSP.echo.suppress', config.inputEchoCancellation_suppress)
        end
        ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
        config.inputEchoCancellation_suppressActive = -ui.slider('##speexechosuppressactive', -config.inputEchoCancellation_suppressActive, 1, 99, 'Echo suppress (active): -%.0f dB')
        if ui.itemEdited() then
          addCommand('filter.speexDSP.echo.suppress', config.inputEchoCancellation_suppressActive)
        end
      end

      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if ui.checkbox('Automatic gain control', config.inputAutoGainControl) then
        config.inputAutoGainControl = not config.inputAutoGainControl
        addCommand('filter.speexDSP', needsSpeexDSP())
        addCommand('filter.speexDSP.autoGainControl', config.inputAutoGainControl)
      end
      if config.inputAutoGainControl then
        ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
        config.inputAutoGainControl_level = ui.slider('##speexagc', config.inputAutoGainControl_level/1000, 1, 99, 'AGC level: %.0fk') * 1000
        if ui.itemEdited() then
          addCommand('filter.speexDSP.autoGainControl.level', config.inputAutoGainControl_level)
        end
      end
    end },
    { name = 'Playback', icon = ui.Icons.VolumeHigh, content = function ()

      ui.alignTextToFramePadding()
      ui.text('Device:')
      ui.sameLine(SETTINGS_COLUMN_WIDTH)
      ui.pushItemWidth(ui.availableSpaceX())
      CtrlDeviceList(mmf.numOutputDevices, mmf.outputDevices, 'outputDevice', true)
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      ui.setNextItemWidth(ui.availableSpaceX())
      config.outputVolume = ui.slider('##outputVolume', config.outputVolume * 100, 0, 100, 'Volume: %.0f%%') / 100
      if ui.itemEdited() then
        addCommand('audio.outputDevice.volume', config.outputVolume)
        updateFMODStreamsVolume()
      end
  
      if config.outputFMOD then
        ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
        if ui.checkbox('Doppler effect', config.outputDoppler) then
          config.outputDoppler = not config.outputDoppler
          restartFMODStreams()
        end
        if ui.itemHovered() then ui.setTooltip('Add a bit of pitch offset based on audio source velocity (applies on servers with 3D audio)') end
        ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
        if ui.checkbox('Reverb effect', config.outputReverb) then
          config.outputReverb = not config.outputReverb
          restartFMODStreams()
        end
        if ui.itemHovered() then ui.setTooltip('Add echo effect in tunnels and such based on track configuration (applies on servers with 3D audio)') end
      end

      ui.offsetCursorY(20)
      ui.alignTextToFramePadding()
      ui.text('Attenuation:')
      ui.sameLine(SETTINGS_COLUMN_WIDTH)
      ui.setNextItemWidth(ui.availableSpaceX())
      config.audioFade = ui.slider('##audioFade', config.audioFade * 100, 0, 100, 'AC audio fade: %.0f%%') / 100
      if ui.itemHovered() then ui.setTooltip('Lower the rest of audio volume if anybody is currently talking') end

      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if ui.checkbox('While other drivers talk', config.audioFade_others) then
        config.audioFade_others = not config.audioFade_others
      end
      ui.offsetCursorX(SETTINGS_COLUMN_WIDTH)
      if ui.checkbox('While you talk', config.audioFade_own) then
        config.audioFade_own = not config.audioFade_own
      end
    end },
    { name = 'Network', icon = ui.Icons.Earth, content = function ()
      if ui.checkbox('Force TCP mode', config.systemForceTCP) then
        config.systemForceTCP = not config.systemForceTCP
        addCommand('system.forceTCP', config.systemForceTCP)
      end
      if ui.checkbox('Use Quality of Service to increase packets priority', config.systemSetQOS) then
        config.systemSetQOS = not config.systemSetQOS
        addCommand('system.setQOS', config.systemSetQOS)
      end
    end, availableDisconnected = true },
    { name = 'Log', icon = ui.Icons.ListAlt, content = function ()
      ui.pushFont(ui.Font.Monospace)
      ui.setScrollY(1e9)
      ui.textWrapped(table.concat(logItems))
      ui.popFont()
    end, availableDisconnected = true },
  }
  local settingsSelectedTab = settingsTabs[tonumber(ac.storage.selectedSettingsTab) or 1]
  local tabIconSize = vec2(16, 16)

  local function CtrlGeneralSettings()
    lastServerLoopbackFrame = mmf.frameIndex + 4

    ui.pushClipRect(vec2(), ui.windowSize(), false)
    ui.offsetCursorX(-20)
    ui.childWindow('##items', vec2(120, 400), function ()
      ui.offsetCursorY(10)
      ui.pushStyleVar(ui.StyleVar.SelectablePadding, vec2(40, 0))
      ui.pushStyleVar(ui.StyleVar.ItemSpacing, vec2(0, 20))
      for i, v in ipairs(settingsTabs) do
        if ui.selectable(v.name, v == settingsSelectedTab) then
          settingsSelectedTab = v
          ac.storage.selectedSettingsTab = i
        end
        ui.addIcon(v.icon, tabIconSize, vec2(0.08, 0.5))
      end
      ui.popStyleVar(2)

      ui.offsetCursorY(ui.availableSpaceY() - 30)
      ui.offsetCursorX(20)
      ui.pushFont(ui.Font.Small)
      if ui.checkbox('Loopback', mmf.serverLoopback) then
        mmf.serverLoopback = not mmf.serverLoopback
      end
      if ui.itemHovered() then
        ui.setTooltip('Use this option for server to send your audio back to you and compare different audio settings')
      end
      ui.popFont()
    end)
    ui.sameLine(0, 8)
    if mmf.numCurrentlyConnected > 0 or settingsSelectedTab.availableDisconnected then
      ui.childWindow('##settings', vec2(340, 400), settingsSelectedTab.content)
    else
      ui.childWindow('##settings', vec2(340, 400), function ()
        local p = ui.windowSize():scale(0.5)
        p.x, p.y = p.x - 20, p.y - 60
        if not processError or processError.timeOfAnotherAttempt then
          ui.drawLoadingSpinner(p, p + 40)
          ui.textAligned('Awaiting voice chat connection…', vec2(0.5, 0.5), ui.availableSpace())
        else
          ui.drawIcon(ui.Icons.Warning, p, p + 40)
          ui.textAligned('Failed to establish voice chat connection', vec2(0.5, 0.5), ui.availableSpace())
        end
      end)
    end
    ui.popClipRect()
  end

  local function CtrlWindow_Content(fading)
    if processError then
      ac.setWindowTitle('main', 'Voice Chat')
      ui.header(processError.timeOfAnotherAttempt and 'Error' or 'Fatal error')
      ui.textWrapped(processError.message)
      if processError.timeOfAnotherAttempt then
        ui.offsetCursorY(8)
        local timeLeft = processError.timeOfAnotherAttempt - os.preciseClock()
        ui.textWrapped(string.format('Next attempt: %.1f s', math.max(timeLeft, 0)))
      end
      return
    end

    if mmf.numCurrentlyConnected < 1 then
      ac.setWindowTitle('main', 'Voice Chat')
      ui.pushStyleVarAlpha(1 - fading * 0.9)
      local p = ui.windowSize():scale(0.5):sub(20)
      ui.drawLoadingSpinner(p, p + 40)
      ui.popStyleVar()
      return
    end

    CtrlUsers()
  end

  local function CtrlWindow()
    if fadeWindowIn then
      fadeWindowIn = false
      ac.forceFadingIn()
    end
    local fading = ac.windowFading()
    if fading > 0.01 then
      ui.beginOutline()
      CtrlWindow_Content(fading)
      ui.endOutline(rgbm(0, 0, 0, fading))
    else
      CtrlWindow_Content(0)
    end
  end

  ac.onRelease(function ()
    for i = 0, sim.carsCount - 1 do
      ac.setDriverMouthOpened(i, 0)
    end
  end)

  return {
    update = syncState,
    main = CtrlWindow,
    settings = CtrlGeneralSettings,
    fullscreen = CtrlTalkingUsers
  }
end

