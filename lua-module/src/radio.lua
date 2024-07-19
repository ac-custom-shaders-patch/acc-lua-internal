local stationsFilename = ac.getFolder(ac.FolderID.ExtCfgUser) .. '/state/stations.json'

---@type {name: string, url: string, id: integer}[]
local stations = {}
local byID = {}
local ignoreChanges = 0

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

local function broadcastStationsUpdate()
  for _, v in ipairs(stations) do
    local f, k = table.findFirst(byID, function (i) return i.url == v.url end)
    v.id = f and f.id or #byID + 1
    byID[k or (#byID + 1)] = v
  end
  ac.store('.SmallTweaks.Radio.Stations', stringify.binary(stations))
  con.stationsPhase = con.stationsPhase + 1
end

local function reloadStations()
  local stationsData = JSON.parse(io.load(stationsFilename))
  if type(stationsData) ~= 'table' then
    stationsData = {
      -- some URLs from https://truck-simulator.fandom.com/wiki/Radio_Stations
      {name = 'Badradio', url = 'https://s2.radio.co/s2b2b68744/listen'},
      {name = 'Café Del Mar', url = 'https://streams.radio.co/se1a320b47/listen'},
      {name = 'GenX Radio', url = 'https://s2.radio.co/sf25229e16/listen'},
      {name = 'Oroko Radio', url = 'https://s5.radio.co/s23b8ada46/listen'},
      {name = 'Shady Pines Radio', url = 'https://streamer.radio.co/s3bc65afb4/listen'},
      {name = 'Primavera Sound Radio', url = 'https://streamer.radio.co/s23e62020a/listen'},
      {name = 'Eurobeat FM', url = 'https://eurobeat.stream.laut.fm/eurobeat'},
      {name = 'KL1', url = 'https://stream1.themediasite.co.uk/8006/;'},
      {name = 'RTL 2 France', url = 'http://icecast.rtl2.fr/rtl2-1-44-128'},
      {name = 'KSPK-FM', url = 'http://stream.kspk.com:8000/live.mp3'},
      {name = '181.FM The Buzz', url = 'https://listen.181fm.com/181-buzz_128k.mp3'},
      {name = 'DR Radio - P3', url = 'http://live-icy.dr.dk/A/A05H.mp3'},
      {name = 'DR Radio - P6 Beat', url = 'http://live-icy.dr.dk/A/A22H.mp3'},
      {name = 'DR Radio - P8 Jazz', url = 'http://live-icy.dr.dk/A/A29H.mp3'},
    }
  end
  stations = table.filter(stationsData, function(item) return type(item.name) == 'string' and type(item.url) == 'string' end)
  broadcastStationsUpdate()
end

local function saveStations()
  ignoreChanges = os.preciseClock() + 1
  io.save(stationsFilename, JSON.stringify(table.map(stations, function (i) return {name = i.name, url = i.url} end)))
end

reloadStations()
ac.onFileChanged(stationsFilename, function()
  if os.preciseClock() < ignoreChanges then return end
  reloadStations()
end)

local awoken = false
local function awake()
  if awoken then return end
  awoken = true

  local mediaPlayer = nil
  local playingNow = 0
  local lastVolume = -1
  local extID
  local extMode
  local extInterval
  local coLoading = false
  local coData

  con.timeTotal = -1

  local function updateCoData(updateFn)
    try(function ()
      coData = updateFn()
    end, function (e)
      ac.warn(e)
      coData = nil
    end)
    con.title = coData and coData.title or ''
    con.artist = coData and coData.artist or ''
    con.artwork = coData and coData.artwork or ''
    con.metadataPhase = con.metadataPhase + 1
    if coData and coData.artwork and coData.artwork ~= '' then
      local artworkURL = coData.artwork
      web.get(coData.artwork, function (err, response)
        if coData.artwork == artworkURL then
          require('shared/utils/playing').setCurrentlyPlaying(coData and {
            title = con.title,
            artist = coData.artist,
            cover = response and response.body,
            sourceID = 'INTERNET_RADIO'
          })
        end
      end)
    else
      require('shared/utils/playing').setCurrentlyPlaying(coData and {
        title = con.title,
        artist = coData.artist,
        sourceID = 'INTERNET_RADIO',
      } or byID[con.playing] and {
        title = byID[con.playing].name,
        sourceID = 'INTERNET_RADIO'
      })
    end
  end

  local function coUpdate()
    if not extID or coLoading then return end
    coLoading = true
    local localID = extID
    if extMode == 'co' then
      web.get('https://public.radio.co/api/v2/%s/track/current' % extID, function (err, response)
        coLoading = false
        if extID ~= localID then
          return coUpdate()
        end
        updateCoData(function ()
          local data = not err and JSON.parse(response.body)
          if not data then error('Response is damaged') end
          local pieces = data.data.title:split(' - ', 2)
          return {
            title = #pieces == 2 and pieces[2] or data.data.title,
            artist = #pieces == 2 and pieces[1] or '',
            startTime = os.parseDate(data.data.start_time, '%Y-%m-%dT%H:%M:%S'),
            artwork = data.data.artwork_urls.standard
          }
        end)
      end)
    elseif extMode == 'laut' then
      web.get('https://api.laut.fm/station/%s/current_song' % extID, function (err, response)
        coLoading = false
        if extID ~= localID then
          return coUpdate()
        end
        updateCoData(function ()
          local data = not err and JSON.parse(response.body)
          if not data then error('Response is damaged') end
          return {
            title = data.title,
            artist = data.artist.name,
            startTime = os.parseDate(data.started_at, '%Y-%m-%d %H:%M:%S %z'),
            -- artwork = data.data.artwork_urls.standard
          }
        end)
      end)
    end
  end

  setInterval(function ()
    if con.playing ~= playingNow then
      playingNow = con.playing
      if not mediaPlayer then
        mediaPlayer = ui.MediaPlayer():setAutoPlay(true)
      end
      local url = byID[con.playing] and byID[con.playing].url
      mediaPlayer:setSource(url)
      if url then
        mediaPlayer:play()
      end

      if #con.title > 0 or #con.artist > 0 or #con.artwork > 0 then
        con.title = ''
        con.artist = ''
        con.artwork = ''
        con.metadataPhase = con.metadataPhase + 1
      end

      extID = nil
      if url then
        extID, extMode = string.match(url, '.radio.co/(.-)/listen'), 'co'

        if not extID then
          extID, extMode = string.match(url, '%.laut%.fm/([^/&?#\\]+)$'), 'laut'
        end
      end

      if extID then
        if not extInterval then
          extInterval = setInterval(coUpdate, 5)
        end
        coUpdate()
      elseif extInterval then
        clearInterval(extInterval)
        extInterval = nil
        extMode = nil

        require('shared/utils/playing').setCurrentlyPlaying(byID[con.playing] and {
          title = byID[con.playing].name,
          sourceID = 'INTERNET_RADIO'
        })
      end

    end
    if mediaPlayer then
      if lastVolume ~= con.volume then
        lastVolume = con.volume
        mediaPlayer:setVolume(math.max(0, con.volume)):setMuted(con.volume <= 0)
      end
      local playing = mediaPlayer:playing()
      con.status = bit.bor(mediaPlayer:hasAudio() and 1 or 0, playing and 2 or 0)
      if playing == con.paused and mediaPlayer:hasAudio() then
        if con.paused then
          mediaPlayer:pause()
        else
          mediaPlayer:play()
        end
      end
      if coData then
        local timePlayed = os.time() - coData.startTime
        con.timePlayed = timePlayed >= 0 and timePlayed < 30 * 60 and timePlayed or -1
      end
    end
  end)
end

ac.onSharedEvent('$SmallTweaks.Radio', function (data, senderName, senderType, senderID)
  if type(data) ~= 'table' then return end
  if data.command == 'add' and type(data.name) == 'string' and type(data.url) == 'string' and not table.some(stations, function (i) return i.url == data.url end) then
    if type(data.position) == 'number' then
      table.insert(stations, data.position, {name = data.name, url = data.url})
    else
      stations[#stations + 1] = {name = data.name, url = data.url}
    end
    saveStations()
    broadcastStationsUpdate()
  end
  if data.command == 'remove' and type(data.url) == 'string' and table.some(stations, function (i) return i.url == data.url end) then
    stations = table.filter(stations, function (i) return i.url ~= data.url end)
    saveStations()
    broadcastStationsUpdate()
  end
  if data.command == 'move' and type(data.url) == 'string' and type(data.position) == 'number' then
    local found, oldPosition = table.findFirst(stations, function (i) return i.url == data.url end)
    if found and oldPosition ~= math.clamp(data.position, 1, #stations) then
      table.removeItem(stations, found)
      table.insert(stations, math.clamp(data.position, 1, #stations + 1), found)
      saveStations()
      broadcastStationsUpdate()
    end
  end
  if data.command == 'rename' and type(data.url) == 'string' and type(data.name) == 'string' then
    local found = table.findFirst(stations, function (i) return i.url == data.url end)
    if found then
      found.name = data.name
      saveStations()
      broadcastStationsUpdate()
    end
  end
  if data.command == 'awake' then
    con.awoken = true
    awake()
  end
end)

if con.awoken then
  awake()
end