local utils = {}

local steam = require('shared/utils/luasteam')
local altonline = require('shared/sim/altonline')
local parcel = require('shared/utils/parcel')
local plates = require('shared/sim/plates')
local binary = require('shared/utils/binary')
local steamID64 = ac.StructItem.build({ value = ac.StructItem.uint64() })
local ownRaceFlags

function utils.setOwnFlags(flags)
  ownRaceFlags = flags
end

function utils.encodeSteamID(steamID, flags)
  steamID64.value = ac.parseUInt64(steamID)
  local ret = ac.encodeBase64(ac.structBytes(steamID64) or '', true)
  if flags and #flags > 0 then
    ret = ret..'.'..flags
  end
  return ret
end

---@type fun(steamID: string?): string?, string
function utils.decodeSteamID(steamID)
  local pieces = string.split(steamID or '', '.', 2)
  local decoded = ac.decodeBase64(pieces[1])
  if not decoded or #decoded ~= 8 then
    return string.regmatch(steamID, '^76\\d{15}$') and steamID or nil, pieces[2] or ''
  end
  ac.fillStructWithBytes(steamID64, decoded)
  return select(1, tostring(steamID64.value):replace('ULL', '')), pieces[2] or ''
end

local conditions = ac.ConditionsSet()
local extrasPack = ac.StructItem.build({
  time = ac.StructItem.uint32(),
  timeMult = ac.StructItem.half(),
  weatherType1 = ac.StructItem.uint8(),
  weatherType2 = ac.StructItem.uint8(),
  weatherTypeTransition = ac.StructItem.unorm8(),
  rainIntensity = ac.StructItem.unorm8(),
  rainWetness = ac.StructItem.unorm8(),
  rainWater = ac.StructItem.unorm8(),
  temperatureAmbient = ac.StructItem.int8(),
  temperatureRoad = ac.StructItem.int8(),
  windSpeed = ac.StructItem.uint8(),
  windDir = ac.StructItem.unorm8(),
  humidity = ac.StructItem.unorm8(),
  pressure = ac.StructItem.int8(),
  trackState = ac.StructItem.unorm8(),
})

---@param a ac.ConditionsSet
---@param b ac.ConditionsSet
function utils.conditionsAreDifferent(a, b)
  return a.currentType ~= b.currentType
      or a.upcomingType ~= b.upcomingType
      or math.abs(a.transition - b.transition) > 0.01
      or math.abs(a.rainIntensity - b.rainIntensity) > 0.001
      or math.abs(a.rainWetness - b.rainWetness) > 0.001
      or math.abs(a.rainWater - b.rainWater) > 0.01
end

function utils.packConditions()
  ac.getConditionsSetTo(conditions)
  extrasPack.time = ac.getSim().timestamp - ac.getSim().timePhotoModeOffset
  extrasPack.timeMult = ac.getSim().timeMultiplier
  extrasPack.weatherType1 = conditions.currentType
  extrasPack.weatherType2 = conditions.upcomingType
  extrasPack.weatherTypeTransition = conditions.transition
  extrasPack.rainIntensity = conditions.rainIntensity
  extrasPack.rainWetness = conditions.rainWetness
  extrasPack.rainWater = conditions.rainWater
  extrasPack.temperatureAmbient = conditions.temperatures.ambient
  extrasPack.temperatureRoad = conditions.temperatures.road
  extrasPack.windSpeed = (conditions.wind.speedFrom + conditions.wind.speedTo) / 2
  assert(conditions.wind.direction >= 0 and conditions.wind.direction <= 360)
  extrasPack.windDir = conditions.wind.direction / 360
  extrasPack.humidity = conditions.humidity
  extrasPack.pressure = math.clamp((conditions.pressure - 101325) / 200, -127, 127)
  extrasPack.trackState = ac.getSim().roadGrip
  return ac.structBytes(extrasPack), conditions, ac.getSim().timeMultiplier
end

function utils.unpackConditions(packed)
  ac.fillStructWithBytes(extrasPack, packed)
  conditions.currentType = extrasPack.weatherType1
  conditions.upcomingType = extrasPack.weatherType2
  conditions.transition = extrasPack.weatherTypeTransition
  conditions.rainIntensity = extrasPack.rainIntensity
  conditions.rainWetness = extrasPack.rainWetness
  conditions.rainWater = extrasPack.rainWater
  conditions.temperatures.ambient = extrasPack.temperatureAmbient
  conditions.temperatures.road = extrasPack.temperatureRoad
  conditions.wind.speedFrom, conditions.wind.speedTo = extrasPack.windSpeed, extrasPack.windSpeed
  conditions.wind.direction = extrasPack.windDir * 360
  conditions.humidity = extrasPack.humidity
  conditions.pressure = extrasPack.pressure * 200 + 101325
  conditions.trackState.sessionStart = extrasPack.trackState
  conditions.trackState.randomness = 0
  conditions.trackState.lapGain = 0
  ac.setWeatherTimeMultiplier(extrasPack.timeMult)
  ac.overrideWeatherConditions(conditions)
  ac.overrideSimTimestamp(extrasPack.time)
end

local DATA_EXCHANGE_DEBUG = false
local DATA_EXCHANGE_EXTERNAL = true

do
  local now = os.time()
  io.scanDir(ac.getFolder(ac.FolderID.ScriptConfig), 'cache-*.bin', function (fileName, attr)
    if now - attr.lastAccessTime > 7 * 24 * 60 * 60 then
      io.deleteFile('%s/%s' % {ac.getFolder(ac.FolderID.ScriptConfig), fileName})
    end
  end)
end

---Really basic implementation of some helper allowing to exchange missing data between clients.
---@param params {sendFn: (fun(requestSide: boolean, packet: string): boolean), remainingSpaceFn: (fun(): integer), filesFilter: (fun(fileName: string, fileAttributes: io.FileAttributes, relativePrefix: string): boolean), allowedToShare: (fun(fullDirFilename: string): boolean), maxTotalSize: integer, cacheLoaded: boolean}
function utils.dataExchangeHelper(params)
  local chunkSize = 200 * 1024
  local dataReceiving ---@type nil|{chunks: string[], destination: string, cacheFilename: string, callback: fun(err: string?), manifest: {size: integer, chunks: integer}, receivedBytes: integer, start: number}
  local dataSending ---@type nil|{}|{sentChunks: integer, totalChunks: integer, packedData: string, start: number}
  local popupOpened = false

  local function abort()
    if dataReceiving then
      dataReceiving.callback('Operation aborted')
      params.sendFn(true, 'c')
    end
    if dataSending then
      params.sendFn(false, '')
    end
    dataReceiving, dataSending = nil, nil
  end

  local function exchangeMsg(label, receivedBytes, totalBytes, startTime, exchangeSpeed)
    local clockNow = os.preciseClock()
    local progress = receivedBytes and totalBytes and receivedBytes / totalBytes
    local passedTime = startTime and clockNow - startTime or 1
    local speedCur = receivedBytes and receivedBytes / (1024 * 1024) / passedTime or 0
    exchangeSpeed.speed = (exchangeSpeed.speed and exchangeSpeed.speed ~= 0) and math.lerp(exchangeSpeed.speed or 0, speedCur, 0.1) or speedCur
    ui.text(receivedBytes and totalBytes and
      '%s: %.1f/%.1f MB' % { label, receivedBytes / (1024 * 1024), totalBytes / (1024 * 1024) } or '%s…' % label)
    if not exchangeSpeed.eta or exchangeSpeed.etaTime > clockNow then
      exchangeSpeed.eta = exchangeSpeed.speed > 0 and
        'ETA: %.1f s (%.1f MB/s)' % { (totalBytes - receivedBytes) / (1024 * 1024) / exchangeSpeed.speed, exchangeSpeed.speed } or
        'ETA: ?'
      exchangeSpeed.etaTime = clockNow + 0.3
    end
    ui.text(exchangeSpeed.eta)
    ui.offsetCursorY(2)
    ui.progressBar(progress or math.nan, vec2(340, 2))
  end

  local exchangeSpeed = {{}, {}}
  local function progressUI()
    if not dataReceiving and not dataSending then
      return true
    end
    if dataReceiving then
      exchangeMsg('Receiving missing data', dataReceiving.receivedBytes,
        dataReceiving.manifest and dataReceiving.manifest.size, dataReceiving.start, exchangeSpeed[1])
    end
    if dataSending then
      exchangeMsg('Sending missing data', dataSending.sentChunks and dataSending.sentChunks * chunkSize,
        dataSending.totalChunks and dataSending.totalChunks * chunkSize, dataSending.start, exchangeSpeed[2])
    end
    ui.setNextItemIcon(ui.Icons.Cancel)
    if ui.button('Cancel', vec2(340, 0)) then
      abort()
    end
  end

  local function openPopup()
    if popupOpened then return end
    if DATA_EXCHANGE_DEBUG then
      popupOpened = ui.onExclusiveHUD(function (mode)
        ui.toolWindow('test', vec2(800, 20), vec2(400, 200), function ()
          if progressUI() then
            popupOpened()
          end
        end)
      end)
    else
      popupOpened = true
      ui.modalDialog('Exchanging missing data…', function()
        if progressUI() then
          popupOpened = false
          return true
        end
        return false
      end, false)
    end
  end

  ---@param dir string @A folder to request, relative to AC root folder.
  ---@param callback fun(err: string?)|function @Callback that will be called once folder is downloaded and extracted, or if operation has failed.
  ---@param localDirOverride string? @If set, this will be real destination.
  local function request(dir, callback, localDirOverride)
    if dataReceiving then
      ac.error('In the middle of requesting missing data already')
      setTimeout(callback:bind('Already in use'))
      return
    end
    local destination = localDirOverride or ('%s/%s' % { ac.getFolder(ac.FolderID.Root), dir })
    local cacheFilename = '%s/cache-%x.bin' % {ac.getFolder(ac.FolderID.ScriptConfig), ac.checksumXXH(dir)}
    if io.fileExists(cacheFilename) then
      io.lastAccessTime(cacheFilename, os.time())
      io.extractFromZipAsync(cacheFilename, destination, { compress = true }, function(err)
        if type(callback) == 'function' then callback(err) end
      end)
      return
    end
    dataReceiving = {
      chunks = {},
      destination = destination,
      cacheFilename = cacheFilename,
      callback = callback,
      receivedBytes = 0
    }
    params.sendFn(true, 'r' .. stringify.binary { dir = dir })
    openPopup()
  end

  local function onPacket(sharingSide, message)
    if not sharingSide then
      if not dataReceiving then return end
      if message == '' then
        local totalData = table.concat(dataReceiving.chunks)
        if params.cacheLoaded then
          io.createFileDir(dataReceiving.cacheFilename)
          io.saveAsync(dataReceiving.cacheFilename, totalData, function (err) if err then ac.warn('Failed to cache:', err) end end)
        end
        io.extractFromZipAsync(totalData, dataReceiving.destination, nil, function(err)
          if type(dataReceiving.callback) == 'function' then dataReceiving.callback(err) end
          dataReceiving = nil
        end)
        -- print('%d bytes would be unzipped to %s' % {#totalData, dataReceiving.destination})
        -- dataReceiving.callback(nil)
        -- dataReceiving = nil
      else
        if not dataReceiving.manifest then
          dataReceiving.manifest = table.assign({ size = 0, chunks = 1 }, stringify.binary.tryParse(message))
          dataReceiving.start = os.preciseClock()
        else
          dataReceiving.receivedBytes = dataReceiving.receivedBytes + #message
          table.insert(dataReceiving.chunks, message)
        end
      end
    elseif message == 'c' then
      dataSending = nil
    elseif message:sub(1, 1) == 'r' then
      local args = stringify.binary.tryParse(message:sub(2))
      local dirToSend = type(args) == 'table' and args.dir and '%s/%s' % { ac.getFolder(ac.FolderID.Root), args.dir }
      if not dataSending and dirToSend and io.dirExists(dirToSend) and params.allowedToShare(dirToSend) then
        local files, totalSize = {}, 0
        local function processDir(dir, prefix)
          io.scanDir(dir, '*', function(fileName, fileAttributes)
            if fileAttributes.isDirectory then
              processDir('%s/%s' % { dir, fileName }, '%s%s/' % {prefix, fileName})
            elseif params.filesFilter(fileName, fileAttributes, prefix) then
              files[prefix..fileName] = { filename = '%s/%s' % { dir, fileName } }
              totalSize = totalSize + fileAttributes.fileSize
            end
          end)
        end
        processDir(dirToSend, '')
        if next(files) then
          dataSending = {}
          openPopup()
          -- On sending side, first, we pack the data…
          io.createZipAsync(nil, files, function(err, packedData)
            if not dataSending then return end -- aborted
            if not err and #packedData > params.maxTotalSize then
              err, packedData = 'Too large', nil
            end
            if not err and packedData then
              local chunks = math.ceil(#packedData / chunkSize)
              table.assign(dataSending,
                { packedData = packedData, sentChunks = 0, totalChunks = chunks, start = os.preciseClock() })
              -- Then, we send how many chunks there will be (for the progress bar)…
              params.sendFn(false, stringify.binary { size = #packedData, chunks = chunks })

              -- And then, we kinda just send all the chunks one by one, but with a caveat: if current sending buffer can’t fit
              -- a new chunk, we’ll wait for the next frame.
              setInterval(function ()
                if not dataSending then
                  return clearInterval
                end
                local i = dataSending.sentChunks + 1
                if i > dataSending.totalChunks then
                  -- Once all the chunks have been sent, we’re sending an empty message. All of this can be improved: for example,
                  -- we could use unreliable messages so there wouldn’t be a problem with a lost chunk blocking others from being
                  -- delivered, we could include metadata into packets so we wouldn’t have to send first and last one, all sorts.
                  -- But, really, with direct connection and low ping even this simplest variant is fine, and if connection is
                  -- relayed, there are other concerns and we can’t really send things over anyway.
                  if params.sendFn(false, '') then
                    dataSending = nil
                  end
                elseif params.remainingSpaceFn() > chunkSize + 64 * 1024 --[[ leaving 64 KB of data for other purposes, just in case ]] then
                  local piece = dataSending.packedData:sub((i - 1) * chunkSize + 1, i * chunkSize)
                  if params.sendFn(false, piece) then
                    dataSending.sentChunks = i
                  else
                    ac.error('Failed to send a chunk')
                  end
                end
              end)
            else
              ac.warn('Can’t send requested dir: ZIP failed, %s' % err)
              dataSending = nil
              params.sendFn(false, '')
            end
          end)
          return
        end
      else
        ac.warn('Can’t send requested dir: doesn’t exist, or isn’t allowed')
      end
      dataSending = nil
      params.sendFn(false, '')
    end
  end

  return {
    onPacket = onPacket,
    request = request,
    abort = abort
  }
end

local friendCache

function utils.steamFriendItemBehavior(id, extraTooltipData)
  local data = utils.getFriendInfo(id)
  if ui.itemHovered() then
    ui.setMouseCursor(ui.MouseCursor.Hand)
    ui.tooltip(function ()
      local game = steam.friends.getFriendGameIDPlayed(id)
      local state = steam.friends.getFriendPersonaState(id)
      ui.image(data.avatar, 48)
      ui.sameLine(0, 12)
      ui.beginGroup()
      ui.pushFont(ui.Font.Title)
      ui.text(data.name)
      ui.popFont()
      ui.text('Steam ID: %s' % id)
      ui.text('Status: %s' % (game and (game == 244210 and 'in Assetto Corsa' or 'in another game') or state))
      ui.text('Level: %s' % steam.friends.getFriendSteamLevel(id))
      ui.endGroup()
      if extraTooltipData then extraTooltipData() end
    end)
  end
  if ui.itemClicked(ui.MouseButton.Right) and steam.utils.isOverlayEnabled() then
    ui.popup(function ()
      if ui.selectable('Send message') then
        steam.friends.activateGameOverlayToUser('chat', id)
      end
      if ui.selectable('View stats') then
        steam.friends.activateGameOverlayToUser('stats', id)
      end
    end)
  end
end

local function textPieceFriend(id)
  local data = utils.getFriendInfo(id)
  if not data.ready then
    ui.text(data.name)
    return
  end
  ui.beginGroup()
  ui.image(data.avatar, 16)
  ui.sameLine(0, 0)
  local game = steam.friends.getFriendGameIDPlayed(id)
  local state = steam.friends.getFriendPersonaState(id)
  if game == 244210 then
    ui.setNextTextSpanStyle(1, math.huge, rgbm.colors.lime, true)
  elseif state == 'offline' then
    ui.setNextTextSpanStyle(1, math.huge, rgbm.colors.gray, true)
  else
    ui.setNextTextBold()
  end
  ui.text(data.name)
  ui.endGroup()
  if ui.itemClicked() then
    steam.friends.activateGameOverlayToUser('steamid', id)
  end
  utils.steamFriendItemBehavior(id)
end

function utils.textWithUserID(value)
  if value then
    local i = string.find(value, '{CON:', nil, true) or string.find(value, '{STU:', nil, true)
    if i then
      local j = string.find(value, '}', i + 5, true)
      if j then
        local valStr = value:sub(i + 5, j - 1)
        local valNum = tonumber(valStr)
        if valNum then
          ui.text(value:sub(1, i - 1))
          ui.sameLine(0, 0)
          textPieceFriend(string.sub(value, i + 1, i + 1) == 'C' 
            and steam.networkingSockets.getConnectionIdentityRemote(valNum)
            or steam.extra.parseUint64(valStr))
          ui.sameLine(0, 0)
          ui.text(value:sub(j + 1))
          return
        end
      end
    end
  end
  ui.text(value)
end

---@param friendSteamID SteamID
---@return {id: SteamID, name: string, avatar: ui.ImageSource, ready: boolean}
function utils.getFriendInfo(friendSteamID)
  if friendCache == nil then
    friendCache = {}
    steam.friends.onPersonaStateChange(function (arg)
      if bit.band(arg.changeFlags, 0x41) ~= 0 then -- name or avatar has changed
        friendCache[tostring(arg.steamID)] = nil
      end
    end)
  end
  local k = tostring(friendSteamID)
  local r = friendCache[k]
  if not r then
    if friendSteamID then
      r = {
        id = friendSteamID,
        name = steam.friends.getFriendPersonaName(friendSteamID),
        avatar = steam.friends.getMediumFriendAvatar(friendSteamID),
        ready = false
      }
      if r.name == '' or r.name == '[unknown]' then
        steam.friends.requestUserInformation(friendSteamID, false)
      else
        r.ready = true
      end
    else
      r = {id = steam.extra.parseUint64('0'), name = '[unknown]', avatar = 'color::#000000', ready = false}
    end
    friendCache[k] = r
  end
  return r
end

function utils.getConnectionDisplayName(connection)
  local id = steam.networkingSockets.getConnectionIdentityRemote(tonumber(connection) or 0)
  return id and utils.getFriendInfo(id).name or '[unknown]'
end

---@param callback fun(err: string?, token: string?)
function utils.getCarsFilterToken(callback)
  local carIDs = binary.writeData()
  io.scanDir(ac.getFolder(ac.FolderID.ContentCars), '*', function(fileName, fileAttributes, callbackData)
    if fileAttributes.isDirectory and io.fileExists('%s/%s/ui/ui_car.json' % { ac.getFolder(ac.FolderID.ContentCars), fileName }) then
      carIDs:uint32(ac.checksumCRC32(fileName))
    end
  end)
  parcel.store(carIDs:stringify(), callback)  
end

function utils.setLicensePlate(carIndex, driverName, nationCode)
  plates.kunos(
    ac.findNodes('carRoot:%d' % carIndex):findMeshes('{ texture:plate_d.dds & texture:plate_nm.dds }'),
    driverName, nationCode)
end

local carInstalledCache = {}

function utils.isCarInstalled(carID)
  local r = carInstalledCache[carID]
  if r == nil then
    r = io.fileExists('%s/%s/ui/ui_car.json' % { ac.getFolder(ac.FolderID.ContentCars), carID })
      or io.fileExists('%s/%s/collider.kn5' % { ac.getFolder(ac.FolderID.ContentCars), carID })
      and not io.dirExists('%s/%s/ui' % { ac.getFolder(ac.FolderID.ContentCars), carID })
    carInstalledCache[carID] = r
  end
  return r
end

function utils.isCarSkinInstalled(carID, skinID)
  local k = string.format('%s/%s', carID, skinID)
  local r = carInstalledCache[k]
  if r == nil then
    r = io.dirExists('%s/%s/skins/%s' % { ac.getFolder(ac.FolderID.ContentCars), carID, skinID })
    carInstalledCache[k] = r
  end
  return r
end

local trackInstalledCache = {}

function utils.isTrackInstalled(trackID)
  local r = trackInstalledCache[trackID]
  if r == nil then
    local pieces = string.split(trackID, '/', 2, false, false)
    r = io.fileExists('%s/%s/%s.kn5' % { ac.getFolder(ac.FolderID.ContentTracks), pieces[1], pieces[1] })
    if r and #pieces == 2 then
      r = io.fileExists('%s/%s/models_%s.ini' % { ac.getFolder(ac.FolderID.ContentTracks), pieces[1], pieces[2] })
    end
    trackInstalledCache[trackID] = r
  end
  return r
end

local carBadgeCache = {}

function utils.getCarBadge(carID)
  local r = carBadgeCache[carID]
  if r == nil then
    r = '%s/%s/ui/badge.png' % {ac.getFolder(ac.FolderID.ContentCars), carID}
    if not io.fileExists(r) then r = false end
    carBadgeCache[carID] = r
  end
  return r or nil
end

local exchangingHandshakesConnection

function utils.currentlyHandshakingConnection()
  return exchangingHandshakesConnection
end

---@generic T
---@param connection SteamConnectionHandle|nil
---@param message T?
---@param params {downloadSkins: boolean, shareSkins: boolean}?
---@param callback fun(err: string?, message: T?, extras: {itemHasBeenInstalled: nil|'car'|'skin'}?)?
function utils.handshakeDriver(connection, message, params, callback)
  exchangingHandshakesConnection = connection
  if not connection then
    return
  end

  steam.networkingSockets.sendMessageToConnection(connection, 'm' .. stringify.binary(message),
    steam.networkingSockets.flags.Reliable)

  local dataExchange, otherSideIsReady, requestingData, handshakeData, exchangeCarMode
  local function handshakeDataExchange()
    if not dataExchange then
      local directConnection = bit.band(steam.networkingSockets.getConnectionFlags(connection) or 0, 8) ~= 0
      print('Data exchange: %s' % (directConnection and 'direct' or '?'))
      if directConnection then
        -- With direct connection, we can disable send rate limits for a bit
        local origCallback = callback
        callback = function (...)
          steam.networkingUtils.setConfig(connection, { SendRateMax = math.nan, SendRateMin = math.nan })
          if origCallback then origCallback(...) end
        end
        steam.networkingUtils.setConfig(connection, { SendRateMax = 100 * 1024 * 1024, SendRateMin = 100 * 1024 * 1024 })
      end
      dataExchange = utils.dataExchangeHelper {
        sendFn = function(requestSide, packet)
          return steam.networkingSockets.sendMessageToConnection(connection, (requestSide and 'q' or 'Q') .. packet, steam.networkingSockets.flags.Reliable) == 'OK'
        end,
        remainingSpaceFn = function ()
          return steam.networkingSockets.getConnectionAvailableSendBufferSpace(connection)
        end,
        filesFilter = function(fileName, fileAttributes, relativePrefix)
          if fileAttributes.isDirectory then return false end
          fileName, relativePrefix = fileName:lower(), relativePrefix:lower()
          if string.regmatch(fileName, '^preview.*\\.jpg$|^plate_(?:d|nm)\\.dds$|\\.json') then
            return false
          end
          if exchangeCarMode then
            if relativePrefix:startsWith('skins/') and not relativePrefix:startsWith('skins/%s/' % ac.getCarSkinID(0)) then
              return false
            end
            if relativePrefix:startsWith('ui/') then
              return false
            end
            if fileName == 'logo.png' then
              return false
            end
            return true
          end
          return fileAttributes.fileSize < (directConnection and 200 or 20) * 1024 * 1024
              and not string.regmatch(fileName, '\\.ini$')
        end,
        allowedToShare = function(fullDirFilename)
          if not params or not params.shareSkins then return false end
          if io.arePathsEqual(fullDirFilename, '%s/%s/skins/%s' % { ac.getFolder(ac.FolderID.ContentCars), ac.getCarID(0), ac.getCarSkinID(0) }) then
            return true
          end
          if directConnection and io.arePathsEqual(fullDirFilename, '%s/%s' % { ac.getFolder(ac.FolderID.ContentCars), ac.getCarID(0) }) then
            exchangeCarMode = true
            return true
          end
          return false
        end,
        maxTotalSize = (directConnection and 200 or 10) * 1024 * 1024, -- smaller than file filter, because we’re zipping here
        cacheLoaded = true
      }
    end
    return dataExchange
  end

  local function shutdownHandshake(reason, partingPacket)
    ac.error('Handshake failed:', reason)
    if partingPacket then
      steam.networkingSockets.sendMessageToConnection(connection, partingPacket,
        steam.networkingSockets.flags.ReliableNoNagle)
      setTimeout(function()
        steam.networkingSockets.closeConnection(connection, true)
      end, 0.1)
    else
      steam.networkingSockets.closeConnection(connection)
    end
    if connection == exchangingHandshakesConnection then
      exchangingHandshakesConnection = nil
    end
    if callback then
      callback(reason or 'Unknown error')
      callback = nil
    end
  end

  local function handshakeApply(handshake)
    handshakeData = handshake
    steam.networkingSockets.sendMessageToConnection(connection, 'G', steam.networkingSockets.flags.ReliableNoNagle)
  end

  local itemHasBeenInstalled
  local function handshakeComplete()
    exchangingHandshakesConnection = nil
    if callback then
      callback(nil, handshakeData, {itemHasBeenInstalled = itemHasBeenInstalled})
      callback = nil
    end
  end

  -- Monitoring connection separately, waiting for a handshake from an opposing party
  setInterval(function()
    if exchangingHandshakesConnection ~= connection then
      if dataExchange then dataExchange.abort() end
      if callback then
        callback('Another party has abandoned the welcoming ritual')
        callback = nil
      end
      return clearInterval
    end
    local messages = steam.networkingSockets.receiveMessagesOnConnection(connection)
    for i = 1, #messages do
      local msgType = messages[i]:byte(1, 1)
      if msgType == const(('m'):byte(1)) then
        local handshake = stringify.binary.parse(messages[i]:sub(2))
        if type(handshake) ~= 'table' or type(handshake.car) ~= 'string' then
          shutdownHandshake('Protocol malfunction')
        elseif not utils.isCarInstalled(handshake.car) then
          if ac.isKeyDown(ui.KeyIndex.Space) and bit.band(steam.networkingSockets.getConnectionFlags(connection) or 0, 8) ~= 0 then
            requestingData, exchangeCarMode = true, true
            handshakeDataExchange().request('content/cars/%s' % handshake.car, function()
              if connection ~= exchangingHandshakesConnection then return end
              carInstalledCache = {}
              requestingData = false
              if not utils.isCarInstalled(handshake.car) then
                shutdownHandshake('Car “%s” is not installed' % handshake.car, 'r')
                ui.toast(ui.Icons.Warning, 'Couldn’t connect: car “%s” is not installed' % handshake.car)
              else
                itemHasBeenInstalled = 'car'
                handshakeApply(handshake)
                if otherSideIsReady then handshakeComplete() end
              end
            end)
          else
            shutdownHandshake('Car “%s” is not installed' % handshake.car, 'r')
            ui.toast(ui.Icons.Warning, 'Couldn’t connect: car “%s” is not installed' % handshake.car)
          end
        else
          if params and params.downloadSkins and not utils.isCarSkinInstalled(handshake.car, handshake.skin) then
            -- We can either extract a skin in car folder and delete later via `temporary` parameter, or extract it into cache folder,
            -- so user content won’t be polluted.
            local localSkinDir = DATA_EXCHANGE_EXTERNAL
              and '%s/remote_assets/%x' % {ac.getFolder(ac.FolderID.ExtCache), ac.checksumXXH(table.concat({handshake.car, handshake.skin}, '/'))}
              or nil
            if localSkinDir and io.dirExists(localSkinDir) then
              handshake.skin = '%s?%s' % {handshake.skin, localSkinDir} 
              handshakeApply(handshake)
            else
              requestingData = true
              handshakeDataExchange().request('content/cars/%s/skins/%s' % { handshake.car, handshake.skin }, function()
                if connection ~= exchangingHandshakesConnection then return end
                carInstalledCache = {}
                requestingData = false
                if localSkinDir then
                  handshake.skin = '%s?%s' % {handshake.skin, localSkinDir}
                else
                  itemHasBeenInstalled = 'skin'
                end
                handshakeApply(handshake)
                if otherSideIsReady then handshakeComplete() end
              end, localSkinDir)
            end
          else
            handshakeApply(handshake)
          end
        end
      elseif msgType == const(('G'):byte(1, 1)) then
        otherSideIsReady = true
        if not requestingData then handshakeComplete() end
      elseif msgType == const(('q'):byte(1, 1)) then
        handshakeDataExchange().onPacket(true, messages[i]:sub(2))
      elseif msgType == const(('Q'):byte(1, 1)) then
        handshakeDataExchange().onPacket(false, messages[i]:sub(2))
      elseif msgType == const(('r'):byte(1, 1)) then
        shutdownHandshake('Another player doesn’t have car “%s”' % ac.getCarID(0))
        ui.toast(ui.Icons.Warning, 'Couldn’t connect: another player doesn’t have car “%s”' % ac.getCarID(0))
      end
    end
  end)
end

function utils.getConnectionSteamID(connection)
  local info = select(3, steam.networkingSockets.getConnectionInfo(connection))
  return info and info.identityRemote
end

---@param carID string
---@param carsInviteParams string[]
---@param callback fun(result: boolean)?
function utils.isCarAllowed(carID, carsInviteParams, callback)
  local waiting = 0
  if carsInviteParams then
    for i, v in ipairs(carsInviteParams) do
      if string.regmatch(v, '^\\w') then
        if table.contains(string.split(v, ','), carID) then
          if callback then
            callback(true)
            callback = nil
          end
          return
        end
      elseif v:sub(1, 1) == '*' then
        waiting = waiting + 1
        parcel.retrieve(v:sub(2), function(err, data)
          waiting = waiting - 1
          if data and #data % 4 == 0 and callback then
            local reader = binary.readData(data)
            local carC32 = ac.checksumCRC32(carID)
            for _ = 1, reader:size(), 4 do
              if reader:uint32() == carC32 then
                callback(true)
                callback = nil
                return
              end
            end
          end
          if waiting == 0 and callback then
            callback(false)
            callback = nil
          end
        end)
      end
    end
  end
  if waiting == 0 and callback then
    callback(false)
    callback = nil
  end
end

local inviteIndex = 0

function utils.nextInviteIndex()
  inviteIndex = inviteIndex + 1
  return inviteIndex
end

---@alias LobbyInfo { friendID: SteamID, lobbyID: string|SteamID|nil, trackID: string, raceFlags: string, carID: string?, isNotAvailable: string?, inviteIndex: integer? }

---@param ownSteamID SteamID
---@param isActiveCallback fun(): boolean
---@param curLobbyHandleCallback fun(): SteamID?
---@param updateCallback fun()
---@return {getList: (fun(): LobbyInfo[]), addInvite: fun(info: LobbyInfo)}
function utils.lobbyMonitor(ownSteamID, isActiveCallback, curLobbyHandleCallback, updateCallback)
  local ownTrackID = ac.getTrackFullID('/')
  local curList = {} ---@type LobbyInfo[]

  local function findLobby(lobbyID)
    return select(1, table.findByProperty(curList, 'lobbyID', lobbyID))
  end

  ---@type fun(a: LobbyInfo, b: LobbyInfo): boolean
  local function orderFn(a, b)
    if a.inviteIndex then
      if b.inviteIndex then return a.inviteIndex < b.inviteIndex end
      return true
    end
    if b.inviteIndex then
      return false
    end
    return utils.getFriendInfo(a.friendID).name > utils.getFriendInfo(b.friendID).name
  end

  local function readLobbyProps(lobbyID)
    local mode = steam.matchmaking.getLobbyData(lobbyID, 'csp.mode')
    if mode ~= 'p2p1v1' then return nil end
    local url = steam.matchmaking.getLobbyData(lobbyID, 'cm.invite.race')
    if url == '' then return nil end
    local parsed = string.urlParse('https://a/%s' % url)
    if not parsed then return nil end
    local carID = parsed:getSearchParam('car')
    local trackID = parsed:getSearchParam('track')
    if not carID or not trackID then return nil end
    local raceFlags = select(2, utils.decodeSteamID(parsed:getSearchParam('param')))
    return {
      carID = carID,
      trackID = trackID,
      raceFlags = raceFlags,
      allowedCars = parsed.searchParams.cars,
      isNotAvailable = not utils.isCarInstalled(carID) and 'car' or not utils.isTrackInstalled(trackID) and 'track' 
        or steam.matchmaking.getLobbyMemberLimit(lobbyID) ~= 2 and 'closed' or nil,
      lobbyID = lobbyID,
    }
  end

  local function checkIfCarIsAllowed(item)
    if item.allowedCars and #item.allowedCars > 0 and not item.isNotAvailable then
      item.isNotAvailable = 'checkingOwnCar'
      utils.isCarAllowed(ac.getCarID(0) or '', item.allowedCars, function (result)
        if item.isNotAvailable == 'checkingOwnCar' then
          item.isNotAvailable = not result and 'ownCar' or nil
        end
      end)
    end
  end

  local function addInvite(item)
    table.removeItem(curList, findLobby(item.lobbyID))
    table.insert(curList, item)
    table.sort(curList, orderFn)
    checkIfCarIsAllowed(item)
    updateCallback()
  end

  local waitingOnLobbyData ---@type nil|{lobbyID: SteamID, callback: fun(args: {steamIDLobby: SteamID, steamIDMember: SteamID, success: boolean})}

  steam.friends.onGameLobbyJoinRequested(function (args)
    steam.friends.joinRequestHandled()
    local lobbyProps = readLobbyProps(args.steamIDLobby)
    if lobbyProps then
      addInvite(table.assign(lobbyProps, { friendID = args.steamIDFriend, inviteIndex = utils.nextInviteIndex() }))
    else
      waitingOnLobbyData = {lobbyID = args.steamIDLobby, callback = function (a)
        local lobbyProps = readLobbyProps(a.steamIDLobby)
        if lobbyProps then
          addInvite(table.assign(lobbyProps, { friendID = args.steamIDFriend, inviteIndex = utils.nextInviteIndex() }))
        else
          ui.toast(ui.Icons.Warning, 'Couldn’t join Steam invite, try using a link')
        end
      end}
      steam.matchmaking.requestLobbyData(args.steamIDLobby)
    end
  end)

  local function addFoundEntry(dstList, lobbyProps, friendID)
    local existingPlayer = table.findByProperty(dstList, 'friendID', friendID)
    if existingPlayer then
      existingPlayer.carID = lobbyProps.carID
      existingPlayer.trackID = lobbyProps.trackID
      existingPlayer.raceFlags = lobbyProps.raceFlags
      existingPlayer.isNotAvailable = lobbyProps.isNotAvailable
      if lobbyProps.allowedCars and not existingPlayer.allowedCars then
        existingPlayer.allowedCars = lobbyProps.allowedCars
        checkIfCarIsAllowed(existingPlayer)
      end
      return
    end

    lobbyProps.friendID = friendID
    table.insert(dstList, lobbyProps)
    if not ac.getSim().isInMainMenu and not lobbyProps.isNotAvailable then
      ac.setMessage('%s is online' % steam.friends.getFriendPersonaName(friendID),
        lobbyProps.trackID == ownTrackID and lobbyProps.raceFlags == ownRaceFlags
          and 'Your Steam friend is at the same track'
          or 'Your Steam friend is at %s' % ac.getTrackNameByID(lobbyProps.trackID))
    end
    checkIfCarIsAllowed(lobbyProps)
  end

  local requestedLobbyData = {}
  steam.matchmaking.onLobbyDataUpdate(function (args)
    if waitingOnLobbyData and waitingOnLobbyData.lobbyID == args.steamIDLobby then
      waitingOnLobbyData.callback(args)
      waitingOnLobbyData = nil
      return
    end
  
    if not args.success or not args.steamIDLobby 
      or args.steamIDLobby == curLobbyHandleCallback() or findLobby(args.steamIDLobby) then
      return
    end

    local friendID = steam.matchmaking.getLobbyOwner(args.steamIDLobby)
    if friendID == ownSteamID then return end

    local lobbyProps = readLobbyProps(args.steamIDLobby)
    if lobbyProps then
      addFoundEntry(curList, lobbyProps, friendID)
      setTimeout(updateCallback, nil, 'lobbyUpdate')
    elseif requestedLobbyData[tostring(args.steamIDLobby)] == true
      and steam.matchmaking.getLobbyDataCount(args.steamIDLobby) == 0 then
      requestedLobbyData[tostring(args.steamIDLobby)] = 1
      ac.warn('Empty lobby, or Steam API got stuck on a dead lobby? User: %s, lobby: %s' % {friendID, args.steamIDLobby})
    end
  end)

  local function itemsWithClassFilter(item) return item.inviteIndex ~= nil end
  local STEAM_FRIEND_FLAGS = const(4)

  local function getFriendsLobbies()
    local newList, anyNew = table.filter(curList, itemsWithClassFilter), false
    if isActiveCallback() then
      for i = 1, steam.friends.getFriendCount(STEAM_FRIEND_FLAGS) do
        local friendID = steam.friends.getFriendByIndex(i - 1, STEAM_FRIEND_FLAGS)
        local played = steam.friends.getFriendGamePlayed(friendID)
        if played and played.gameID == 244210 and played.steamIDLobby then
          local prevEntry = findLobby(played.steamIDLobby)
          if prevEntry then
            table.insert(newList, prevEntry)
          else
            local lobbyProps = readLobbyProps(played.steamIDLobby)
            if lobbyProps then
              addFoundEntry(newList, lobbyProps, friendID)
              anyNew = true
            elseif steam.matchmaking.getLobbyDataCount(played.steamIDLobby) == 0 then
              local k = tostring(played.steamIDLobby)
              if not requestedLobbyData[k] then
                requestedLobbyData[k] = true
                steam.matchmaking.requestLobbyData(played.steamIDLobby)
              end
            end
          end
        end
      end
    end
    if anyNew or #curList ~= #newList then
      curList = newList
      table.sort(curList, orderFn)
      setTimeout(updateCallback, nil, 'lobbyUpdate')
    end
  end

  steam.friends.onPersonaStateChange(function (data)
    if ac.getSim().isInMainMenu and bit.band(data.changeFlags, 0x8) ~= 0 then
      setTimeout(getFriendsLobbies, 0.1)
    end
  end)

  setTimeout(getFriendsLobbies)
  setInterval(function()
    getFriendsLobbies()
  end, 1)

  return {
    getList = function() return curList end,
    addInvite = addInvite
  }
end

---@param url string
---@param callback fun(err: string?, info: LobbyInfo?)
function utils.parseInviteUrl(url, callback)
  local parsed = string.urlParse(url)

  if not parsed or not parsed.pathname:endsWith('race/csp') or parsed:getSearchParam('mode') ~= 'p2p-1v1' then
    local param = parsed and parsed:getSearchParam('u')
    if param and string.urlCheck(param) then
      utils.parseInviteUrl(param, callback)
    else
      callback('Not an invite')
    end
    return
  end

  local trackID = parsed:getSearchParam('track')
  local steamID, raceFlags = utils.decodeSteamID(parsed:getSearchParam('param'))
  if not trackID or not steamID then
    callback('Malformed invite')
    return
  end

  if steamID == steam.user.getSteamID() then
    callback('Can’t join your own invite')
    return
  end

  local parsedSteamID = steam.extra.parseUint64(steamID)
  local carID = parsed:getSearchParam('car')
  if carID and not utils.isCarInstalled(carID) and not ac.isKeyDown(ui.KeyIndex.Space) then
    callback('Car “%s” is not installed' % carID)
    return
  end

  utils.isCarAllowed(ac.getCarID(0) or '', parsed.searchParams.cars, function (result)
    if not result then
      callback('%s doesn’t have car “%s” installed')
      return
    end
    callback(nil, {
      friendID = parsedSteamID,
      lobbyID = ':pasted:%s' % tostring(parsedSteamID),
      carID = carID,
      trackID = trackID,
      raceFlags = raceFlags,
      inviteIndex = utils.nextInviteIndex()
    })
  end)
end

local assistValues = {'off', 'factory', 'on'}
local origAssists

function utils.collectRaceRules()
  local sim = ac.getSim()
  local assists = ac.getAssists()
  return {
    sim.penaltiesEnabled,
    sim.wrongWayPenaltyEnabled,
    sim.allowedTyresOut,
    -- 3 items of rules
    table.indexOf(assistValues, assists.abs) or 2,
    table.indexOf(assistValues, assists.tractionControl) or 2,
    assists.autoBlip,
    assists.autoClutch,
    assists.autoShifter,
    assists.tyresBlankets,
    assists.tyresWear,
    assists.damageRate,
    assists.fuelRate,
    assists.slipstream,
    assists.stability,
    -- +11 items of assists, not syncing ideal line on purpose
    ac.getTimeZoneOffset(),
    ac.getTrackCoordinatesDeg(),
    ac.getRealTrackHeadingAngle(),
    -- +3 items of track locational configuration
    utils.packConditions()
    -- +1 for conditions
    -- total: 18
  }
end

function utils.applyRaceRules(rules)
  if type(rules) ~= 'table' or #rules ~= 18 then return end
  if not origAssists then origAssists = table.assign(utils.collectRaceRules(), { editable = true }) end
  physics.setPenalties(rules[1] == true)
  physics.setWrongWayPenalty(rules[2] == true)
  physics.setAllowedTyresOut(rules[3])
  physics.setAssists{
    abs = assistValues[rules[4]],
    tractionControl = assistValues[rules[5]],
    autoBlip = rules[6],
    autoClutch = rules[7],
    autoShifter = rules[8],
    tyresBlankets = rules[9],
    tyresWear = rules[10],
    damageRate = rules[11],
    fuelRate = rules[12],
    slipstream = rules[13],
    stability = rules[14],
    editable = false
  }
  ac.setTrackTimezoneOffset(rules[15])
  ac.setTrackCoordinatesDeg2(rules[16], rules[17])
  utils.unpackConditions(rules[18])
end

function utils.restoreRaceRules()
  if origAssists then utils.applyRaceRules(origAssists) end
end

function utils.getConfigurationMismatchMessage(myFlags, otherFlags)
  if myFlags == '' and otherFlags == 'i' then return '“Frozen drive” enabled' end
  if myFlags == 'i' and otherFlags == '' then return '“Frozen drive” disabled' end
  -- if origAssists then utils.applyRaceRules(origAssists) end
  return 'Different configuration'
end

function utils.modalButtons(confirmLabel, confirmIcon, cancelLabel, cancelIcon)
  local ret = false
  if ui.modernButton(confirmLabel or 'OK', vec2(200, 40), ui.ButtonFlags.Confirm, confirmIcon or ui.Icons.Confirm) then
    ui.closePopup()
    ret = true
  end
  ui.sameLine(0, 8)
  if ui.modernButton(cancelLabel or 'Cancel', vec2(200, 40), ui.ButtonFlags.Cancel, cancelIcon or ui.Icons.Cancel) then
    ui.closePopup()
  end
  return ret
end

local latestSessionChange = 0
local firstCarStartingFirst

function utils.checkIfFirstCarShouldStartFirst()
  local ownCar, otherCar = ac.getCar(0), ac.getCar(1)
  if not ownCar or not otherCar then return true end
  local ownLapTime = ownCar.lapTimeMs
  if ownLapTime == 0 then ownLapTime = 1e9 - (ownCar.lapCount + 0.5) * 100 end
  local otherLapTime = otherCar.lapTimeMs
  if otherLapTime == 0 then otherLapTime = 1e9 - otherCar.lapCount * 100 end
  print('Starting order lap times:', ownLapTime, otherLapTime)
  return ownLapTime < otherLapTime
end

function utils.recentSessionChangeTookPlace()
  return latestSessionChange + 1 > os.preciseClock()
end

function utils.setSessionType(connection, lapsCount)
  latestSessionChange = os.preciseClock()
  if lapsCount then
    print('Changing session to race', connection)
    if not firstCarStartingFirst or ac.getSim().raceSessionType == ac.SessionType.Practice then
      firstCarStartingFirst = utils.checkIfFirstCarShouldStartFirst()
    end
    -- Whoever has the lowest lap time will be first. If none has laptime, whoever has the most laps is starting first.
    if ac.getSim().isTrackOpen then lapsCount = 1 end
    local startTime = ac.getSim().time
    ac.overrideSession({
      laps = lapsCount,
      name = 'P2P 1v1/Race',
      type = ac.SessionType.Race,
      startTime = startTime + 10e3,
      order = firstCarStartingFirst and {0} or {1}, -- we provide index of the car starting first, another car will get its index automatically
    })
    ac.tryToStart()
    if connection and connection ~= 0 then
      steam.networkingSockets.sendMessageToConnection(connection,
        'S' .. stringify.binary{altonline.timeToTimestamp(startTime), not firstCarStartingFirst, lapsCount},
        steam.networkingSockets.flags.Reliable)
    end
  else
    print('Changing session to practice', connection)
    ac.overrideSession({
      name = 'P2P 1v1',
      type = ac.SessionType.Practice,
      resetLaps = false,
      blockTeleports = true,
    })
    if connection and connection ~= 0 then
      steam.networkingSockets.sendMessageToConnection(connection,
        'S' .. stringify.binary(false),
        steam.networkingSockets.flags.Reliable)
    end
  end
end

function utils.parseSessionMessage(msg)
  if type(msg) == 'table' and #msg == 3 then
    latestSessionChange = os.preciseClock()
    ac.setMessage('Starting a race', '%s has started a race of %d lap%s'
      % { ac.getDriverName(1) or '?', msg[3], msg[3] == 1 and '' or 's' })
    ac.overrideSession({
      laps = msg[3],
      name = 'P2P 1v1/Race',
      type = ac.SessionType.Race,
      startTime = altonline.timestampToTime(msg[1]) + 10e3,
      order = msg[2] and {0} or {1},
    })
    ac.tryToStart()
  elseif msg == false then
    utils.setSessionType(nil, nil)
  else
    ac.warn('Unknown session message', msg, type(msg))
  end
end

return utils
