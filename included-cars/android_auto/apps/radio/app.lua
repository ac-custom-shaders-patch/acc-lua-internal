RadioAppData = {
  lib = nil,
  selectedColor = rgbm.new('#EF5261'),
}

local bg = touchscreen.blurredBackgroundImage(rgbm.new('#EF5261'))

local function time(value)
  if value == -1 then return '--:--' end
  return string.format('%02d:%02d', math.floor(value / 60), math.floor(value % 60))
end

function RadioAppData:playToggle()
  self.lib.pause(self.lib.playing())
end

function RadioAppData:selectStation(station)
  if type(station) == 'number' then
    local stations = RadioAppData.lib.stations()
    if #stations == 0 then return end
    local curIndex = table.indexOf(stations, RadioAppData.lib.current()) or stations[1]
    return self:selectStation(stations[(#stations + curIndex - 1 + station) % #stations + 1]) 
  end
  RadioAppData.lib.play(station)
end

local transition = touchscreen.createTransition(0.85)
local padding = system.narrowMode and 80 or 160

local function step(v)
  return (math.floor(v / 2) + math.smoothstep(math.min(v % 2, 1)))
end

local function addUserStation(name, url)
  RadioAppData.lib.addStation(name, url, 1)
end

local previousArtwork

return function (dt)
  if not RadioAppData.lib then
    RadioAppData.lib = require('shared/utils/radio')
    RadioAppData.lib.setVolume(touchscreen.getVolume())
    for i, v in ipairs(stringify.tryParse(ac.storage.radioUserStations, nil, {})) do
      RadioAppData.lib.addStation(v[1], v[2], i)
    end
    -- ac.storage.radioUserStations = nil -- TODO
    RadioAppData.lib.onMetadataUpdate(function ()
      if previousArtwork then
        ui.unloadImage(previousArtwork)
      end
      local curArtwork = RadioAppData.lib.getArtwork()
      previousArtwork = curArtwork
      if previousArtwork then
        ui.onImageReady(previousArtwork, function ()
          if curArtwork == previousArtwork then
            bg.update(RadioAppData.lib.getArtwork())
          end
        end)
      else
        bg.update(nil)
      end
    end)
  end

  if dt == false then
    return
  end

  RadioAppData.selectedColor:set(bg.accent())
  bg.draw(dt)

  ui.childWindow('stationsList', vec2(400, ui.availableSpaceY()), function ()
    ui.offsetCursorY(40)
    ui.indent(padding) 
    for _, s in ipairs(RadioAppData.lib.stations()) do
      ui.dwriteText(s.name, 20, s == RadioAppData.lib.current() and RadioAppData.selectedColor or rgbm.colors.white)
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
          if table.some(RadioAppData.lib.stations(), function (item) return item.url == value end) then
            headers = 'already added'
            loading = false
          else
            loading = true
            RadioAppData.lib.getStreamMetadataAsync(value, function (err, data)
              if value == loaded then
                headers = err and err:lower() or data
                loading = false
              end
            end)
          end
        end
        if loading then
          ui.offsetCursor(ui.availableSpace() / 2 - 30)
          touchscreen.loading(60)
        elseif headers then
          if type(headers) == 'string' then
            ui.textAligned('Error: '..headers, 0.5, ui.availableSpace())
          else
            ui.offsetCursorY(ui.availableSpaceY() / 2 - 40)
            ui.offsetCursorX(ui.availableSpaceX() / 2 - 100)
            ui.textAligned(string.format('Found: %s\n%s\nGenre: %s\nBitrate: %s Kbps', headers.name, headers.description or '(No description)',
              headers.genre or '?', headers.bitrateKbps or '?'), 0, vec2(200, 60))
            ui.offsetCursorX(ui.availableSpaceX() / 2 - 100)
            if touchscreen.button('ADD', vec2(200, 24), RadioAppData.selectedColor, 11) then
              addUserStation(headers.name, value)
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

  local current = RadioAppData.lib.current()
  if not current then return end

  local tr = transition(dt, true)

  ui.pushStyleVarAlpha(tr)
  local playerX = math.max(padding + 240, ui.windowWidth() * 0.45)
  ui.setCursor(vec2(playerX + 200 * (1 - tr), 0))
  ui.childWindow('player', vec2(ui.windowWidth() - (playerX + 200 * (1 - tr)) - 80, ui.windowHeight()), function ()
    ui.offsetCursorY(80)
    ui.dwriteText('Now playing:', 12)
    if RadioAppData.lib.hasMetadata(current) then
      if RadioAppData.lib.getArtwork() then 
        ui.offsetCursorY(8)
        ui.image(RadioAppData.lib.getArtwork(), 80)
        ui.sameLine(0, 12)
        ui.beginGroup()
      end
      ui.dwriteText(RadioAppData.lib.getTitle() or current.name, 30)
      ui.dwriteText(RadioAppData.lib.getArtist() or RadioAppData.lib.getTitle() and current.name or current.url, 12, rgbm.colors.gray)
      if RadioAppData.lib.getTimePlayed() >= 0 then
        ui.dwriteText(string.format('%s / %s', time(RadioAppData.lib.getTimePlayed()), time(RadioAppData.lib.getTimeTotal())), 12, rgbm.colors.gray)
      end
      if RadioAppData.lib.hasHistory(current) and RadioAppData.lib.getArtwork() then 
        ui.endGroup()
        if touchscreen.itemTapped() then
          local stationName, loaded = current.name, nil
          RadioAppData.lib.getHistoryAsync(current, function (err, data)
            loaded = err and err:lower() or data
          end)
          system.openPopup('History', function (dt)
            if loaded == nil then
              ui.offsetCursor(ui.availableSpace() / 2 - 30)
              touchscreen.loading(60)
            elseif type(loaded) == 'string' then
              ui.textAligned('Error: %s' % loaded, 0.5, ui.availableSpace())
            elseif type(loaded) == 'table' then
              system.scrollList(dt, function ()
                for _, v in ipairs(loaded) do
                  if _ > 1 then
                    ui.separator()
                  end
                  ui.dwriteText(v.title, 30)
                  ui.dwriteText(v.artist or stationName, 30)
                end
              end)
            end
          end)
        end
      end
    else
      ui.dwriteText(current.name, 30)
      ui.dwriteText(current.url, 12, rgbm.colors.gray)
    end

    local p = 140
    local y = 40
    ui.setCursor(vec2(p - 105 - 30, y + 182))
    if touchscreen.iconButton(ui.Icons.Back, 60) then
      RadioAppData:selectStation(-1)
    end
    ui.setCursor(vec2(p - 0 - 30, y + 182))
    if touchscreen.iconButton(RadioAppData.lib.playing() and ui.Icons.Pause or ui.Icons.Play, 60) then
      RadioAppData:playToggle()
    end
    if not RadioAppData.lib.loaded() then
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