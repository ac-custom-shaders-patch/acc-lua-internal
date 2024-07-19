--[[
  Wrapper for shared internet-radio module.
]]

---@alias radio.RadioStation {name: string, url: string, id: integer}

local radio = {}

local stations, byID
local stationsPhase = -1
local stationsUpdateListeners = {}
local metadata
local metadataPhase = -1
local metadataUpdateListeners

---@param callback fun()
---@return fun() @Unsubscribing callback.
function radio.onStationsUpdate(callback)
  stationsUpdateListeners[#stationsUpdateListeners + 1] = callback
  return function ()
    table.removeItem(stationsUpdateListeners, callback)
  end
end

---@param callback fun()
---@return fun() @Unsubscribing callback.
function radio.onMetadataUpdate(callback)
  if not metadataUpdateListeners then
    metadataUpdateListeners = {}
    setInterval(radio.getTitle)
  end
  metadataUpdateListeners[#metadataUpdateListeners + 1] = callback
  return function ()
    table.removeItem(metadataUpdateListeners, callback)
  end
end

local con = ac.connect({
  ac.StructItem.key('radioState'),
  stationsPhase = ac.StructItem.int32(),
  metadataPhase = ac.StructItem.int32(),
  playing = ac.StructItem.int32(),
  title = ac.StructItem.string(512),
  artist = ac.StructItem.string(512),
  artwork = ac.StructItem.string(512),
  timePlayed = ac.StructItem.int16(),
  timeTotal = ac.StructItem.int16(),
  status = ac.StructItem.uint8(),
  paused = ac.StructItem.boolean(),
  awoken = ac.StructItem.boolean(),
  volume = ac.StructItem.float(),
}, false, ac.SharedNamespace.Shared)

local function syncStations()
  if stationsPhase ~= con.stationsPhase then
    stationsPhase = con.stationsPhase
    stations = stringify.binary.tryParse(ac.load('.SmallTweaks.Radio.Stations'), {})
    byID = table.map(stations, function (i) return i, i.id end)
    table.forEach(stationsUpdateListeners, function (i) i() end)
  end
end

local function getMetadata()
  if metadataPhase ~= con.metadataPhase then
    metadataPhase = con.metadataPhase
    metadata = {
      title = con.title ~= '' and con.title or nil,
      artist = con.artist ~= '' and con.artist or nil,
      artwork = con.artwork ~= '' and con.artwork or nil
    }
    if metadataUpdateListeners then
      table.forEach(metadataUpdateListeners, function (i) i() end)
    end
  end
  return metadata
end

---Fetch list of available stations.
---@return radio.RadioStation[]
function radio.stations()
  syncStations()
  return stations
end

function radio.playing()
  return bit.band(con.status, 2) ~= 0
end

function radio.loaded()
  return bit.band(con.status, 1) ~= 0
end

---@param station radio.RadioStation?
function radio.play(station)
  if not con.awoken then
    ac.broadcastSharedEvent('$SmallTweaks.Radio', {command = 'awake'})
  end
  con.playing = station and station.id or 0
end

function radio.stop()
  con.playing = 0
end

---@return radio.RadioStation?
function radio.current()
  syncStations()
  return byID[con.playing]
end

---@param paused boolean
function radio.pause(paused)
  con.paused = not not paused
end

---@param volume number
function radio.setVolume(volume)
  con.volume = volume
end

function radio.getVolume()
  return con.volume
end

function radio.getTimePlayed()
  return con.timePlayed
end

function radio.getTimeTotal()
  return con.timeTotal
end

function radio.getTitle()
  return getMetadata().title
end

function radio.getArtist()
  return getMetadata().artist
end

function radio.getArtwork()
  return getMetadata().artwork
end

---@param station radio.RadioStation
function radio.hasMetadata(station)
  if station.__hasMetadata == nil then
    station.__hasMetadata = string.match(station.url, '.radio.co/.-/listen') ~= nil
      or string.match(station.url, '%.laut%.fm/[^/&?#\\]+$') ~= nil
  end
  return station.__hasMetadata
end

---@param station radio.RadioStation
function radio.hasHistory(station)
  if station.__hasHistory == nil then
    station.__hasHistory = string.match(station.url, '.radio.co/.-/listen') ~= nil
      or string.match(station.url, '%.laut%.fm/[^/&?#\\]+$') ~= nil
  end
  return station.__hasHistory
end

---@param name string
---@param url string 
---@param position integer?
function radio.addStation(name, url, position)
  ac.broadcastSharedEvent('$SmallTweaks.Radio', {command = 'add', name = name, url = url, position = position})
end

---@param station radio.RadioStation
---@param name string
function radio.renameStation(station, name)
  ac.broadcastSharedEvent('$SmallTweaks.Radio', {command = 'rename', url = station.url, name = name})
end

---@param station radio.RadioStation
---@param position integer
function radio.moveStation(station, position)
  ac.broadcastSharedEvent('$SmallTweaks.Radio', {command = 'move', url = station.url, position = position})
end

---@param station radio.RadioStation
function radio.removeStation(station)
  ac.broadcastSharedEvent('$SmallTweaks.Radio', {command = 'remove', url = station.url})
end

---@param station radio.RadioStation
---@param callback fun(err: string?, url: string?)
function radio.getLogoAsync(station, callback)
  local coID = string.match(station.url, '%.radio%.co/([^/&?#\\]+)/listen$')
  if coID then
    web.get('https://public.radio.co/stations/%s/status' % coID, function (err, response)
      if err then return callback(err, nil) end
      local r = try(function () return JSON.parse(response.body).logo_url end)
      callback(not r and 'Failed to parse data' or nil, r)
    end)
    return
  end

  local lautID = string.match(station.url, '%.laut%.fm/([^/&?#\\]+)$')
  if lautID then
    web.get('https://api.laut.fm/station/%s' % lautID, function (err, response)
      if err then return callback(err, nil) end
      local r = try(function () return JSON.parse(response.body).images.station_120x120 end)
      callback(not r and 'Failed to parse data' or nil, r)
    end)
    return
  end

  setTimeout(function () callback(nil, nil) end)
end

---@param station radio.RadioStation
---@param callback fun(err: string?, data: {title: string, artist: string?}[]?)
function radio.getHistoryAsync(station, callback)
  local coID = string.match(station.url, '.radio.co/(.-)/listen')
  if coID then
    web.get('https://public.radio.co/stations/%s/status' % coID, function (err, response)
      if err then return callback(err, nil) end
      local parsed = try(function ()
        return table.map(JSON.parse(response.body).history, function (e)
          local p = e.title:split(' - ', 2)
          return #p == 2 and {title = p[2], artist = p[1]} or {title = e.title}
        end)
      end)
      callback(not parsed and 'Failed to parse data' or nil, parsed)
    end)
    return
  end

  local lautID = string.match(station.url, '%.laut%.fm/([^/&?#\\]+)$')
  if lautID then
    web.get('https://api.laut.fm/station/%s/last_songs' % lautID, function (err, response)
      if err then return callback(err, nil) end
      local parsed = try(function ()
        return table.map(JSON.parse(response.body), function (e)
          return {title = e.title, artist = e.artist.name}
        end)
      end)
      callback(not parsed and 'Failed to parse data' or nil, parsed)
    end)
    return
  end

  setTimeout(function () callback(nil, {}) end)
end

local streamMetadataCache = {}

---@param url string
---@param callback fun(err: string?, data: {name: string, description: string?, genre: string?, bitrateKbps: string?, url: string?}?)
function radio.getStreamMetadataAsync(url, callback)
  if streamMetadataCache[url] then
    setTimeout(function () callback(nil, streamMetadataCache[url]) end)
  else
    web.request('GET', url, {[':headers-only'] = true}, function (err, response)
      if err or response.status >= 400 or not response.headers['icy-name'] then
        return callback(err or response.status >= 400 and 'error %s' % response.status or 'Not a radio stream', nil)
      end
      streamMetadataCache[url] = {
        name = response.headers['icy-name'],
        description = response.headers['icy-description'],
        genre = response.headers['icy-genre'],
        url = response.headers['icy-url'],
        bitrateKbps = response.headers['icy-br'],
      }
      callback(nil, streamMetadataCache[url])
    end)
  end
end

return radio