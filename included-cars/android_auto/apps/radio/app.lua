RadioAppData = {
  stations = nil,
  baseStations = nil,
  userStations = nil,
  selectedStation = nil,
  selectedColor = rgbm.new('#EF5261'),
  
  ---@type ui.MediaPlayer
  mediaPlayer = nil
}

function RadioAppData:playToggle()
  if self.mediaPlayer:playing() then self.mediaPlayer:pause()
  else self.mediaPlayer:play() end
end

function RadioAppData:selectStation(station)
  if type(station) == 'number' then
    local curIndex = table.indexOf(self.stations, self.selectedStation)
    return self:selectStation(self.stations[(#self.stations + curIndex - 1 + station) % #self.stations + 1]) 
  end
  if self.selectedStation == station then return end
  self.selectedStation = station
  if not self.mediaPlayer then
    self.mediaPlayer = ui.MediaPlayer():setAutoPlay(true)
    touchscreen.syncVolume(self.mediaPlayer)
  end
  self.mediaPlayer:setSource(station and station[2])
end

local transition = touchscreen.createTransition(0.85)
local padding = system.narrowMode and 80 or 160

local function step(v)
  return (math.floor(v / 2) + math.smoothstep(math.min(v % 2, 1)))
end

local function updateStationsList()
  if not RadioAppData.baseStations then
    RadioAppData.baseStations = table.filter(table.map(io.load(io.relative('stations.txt')):split('\n'), function (line)
      if #line == 0 then return {} end
      return table.map(string.split(line, '#', 2)[1]:split('='), string.trim)
    end), function (line) return #line == 2 end)
    RadioAppData.userStations = stringify.tryParse(ac.storage.radioUserStations, nil, {})
  end
  RadioAppData.stations = table.chain(RadioAppData.userStations, RadioAppData.baseStations)
end

local function addUserStation(name, url)
  table.insert(RadioAppData.userStations, {name, url})
  RadioAppData.userStations = table.distinct(RadioAppData.userStations, function (item) return item[2] end)
  ac.storage.radioUserStations = stringify(RadioAppData.userStations)
  updateStationsList()
end

return function (dt)
  if not RadioAppData.stations then
    updateStationsList()
  end

  ui.childWindow('stationsList', vec2(400, ui.availableSpaceY()), function ()
    ui.offsetCursorY(40)
    ui.indent(padding)
    for i = 1, #RadioAppData.stations do
      local s = RadioAppData.stations[i]
      ui.dwriteText(s[1], 20, RadioAppData.selectedStation == s and RadioAppData.selectedColor or rgbm.colors.white)
      if touchscreen.itemTapped() then
        RadioAppData:selectStation(s)
      end
    end
    ui.dwriteText('Add station…', 20)
    if touchscreen.itemTapped() then
      local loaded = nil
      local headers = nil
      local loading = false
      system.openInputPopup('Enter URL', '', function (dt, value, changed)
        if changed and #value > 0 then
          loaded = value
          if table.some(RadioAppData.stations, function (item) return item[2] == value end) then
            headers = 'already added'
            loading = false
          else
            loading = true
            web.request('GET', value, { [':headers-only'] = true }, function (err, response)
              if value == loaded then
                if err then
                  headers = err:lower()
                elseif response.headers['icy-name'] then
                  headers = response.headers
                else
                  headers = 'not a station'
                end
                loading = false
              end
            end)
          end
        end
        if loading then
          ui.offsetCursor(ui.availableSpace() / 2 - 30)
          touchscreen.loading(60)
        elseif headers  then
          if type(headers) == 'string' then
            ui.textAligned('Error: '..headers, 0.5, ui.availableSpace())
          else
            ui.offsetCursorY(ui.availableSpaceY() / 2 - 40)
            ui.offsetCursorX(ui.availableSpaceX() / 2 - 100)
            ui.textAligned(string.format('Found: %s\n%s\nGenre: %s\nBitrate: %s Kbps', headers['icy-name'], headers['icy-description'] or '(No description)',
              headers['icy-genre'] or '?', headers['icy-br'] or '?'), 0, vec2(200, 60))
            ui.offsetCursorX(ui.availableSpaceX() / 2 - 100)
            if touchscreen.button('ADD', vec2(200, 24), RadioAppData.selectedColor, 11) then
              addUserStation(headers['icy-name'], value)
              return true
            end
          end
        else
          ui.offsetCursor(ui.availableSpace() / 2 - vec2(12, 40))
          ui.icon(ui.Icons.Search, 24)
          ui.textAligned('Enter or paste from clipboard station URL', vec2(0.5, 0), ui.availableSpace())
        end
      end)
    end
    ui.unindent(padding)
    ui.offsetCursorY(40)
    system.scrolling(dt)
  end)

  if not RadioAppData.mediaPlayer then return end

  local tr = transition(dt, true)
  touchscreen.syncVolumeIfFresh(RadioAppData.mediaPlayer)

  ui.pushStyleVarAlpha(tr)
  local playerX = math.max(padding + 240, ui.windowWidth() * 0.45)
  ui.setCursor(vec2(playerX + 200 * (1 - tr), 0))
  ui.childWindow('player', vec2(400, ui.windowHeight()), function ()
    ui.offsetCursorY(80)
    ui.dwriteText('Now playing:', 12)
    ui.dwriteText(RadioAppData.selectedStation[1], 30)
    ui.dwriteText(RadioAppData.selectedStation[2], 12, rgbm.colors.gray)

    local p = 140
    local y = 40
    ui.setCursor(vec2(p - 105 - 30, y + 182))
    if touchscreen.iconButton(ui.Icons.Back, 60) then
      RadioAppData:selectStation(-1)
    end
    ui.setCursor(vec2(p - 0 - 30, y + 182))
    if touchscreen.iconButton(RadioAppData.mediaPlayer:playing() and ui.Icons.Pause or ui.Icons.Play, 60) then
      RadioAppData:playToggle()
    end
    if not RadioAppData.mediaPlayer:hasAudio() then
      local c = vec2(p, y + 200 + 12)
      ui.drawCircle(c, 36, rgbm.colors.gray, 30, 2)

      local t = ui.time()
      ui.pathArcTo(c, 36, step(t * 1.3 + 1) * 4.5 + t * 3, step(t * 1.3) * 4.5 + 5 + t * 3, 40)
      ui.pathStroke(RadioAppData.selectedColor, false, 2)
    else
      ui.drawCircle(vec2(p, y + 200 + 12), 36, RadioAppData.selectedColor, 30, 2)
    end
    ui.setCursor(vec2(p + 105 - 30, y + 182))
    if touchscreen.iconButton(ui.Icons.Next, 60) then
      RadioAppData:selectStation(1)
    end
  end)

  touchscreen.volumeControl()
  ui.popStyleVar()
end