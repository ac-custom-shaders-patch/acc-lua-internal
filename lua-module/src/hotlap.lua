if not __script.hauntedHouse then
  return
end

ac.addMainMenuSettings = __util.nativ3(1998702594)
ac.overrideWeatherConditions = __util.nativ1(2601648814)

local cfg = ac.storage { keepGhosts = 10, highlightSameName = true, filterByTyres = true, filterByCar = true, defaultRecordName = '' }
local applySkins = ConfigGeneral:get('GHOST', 'USE_ORIGINAL_MATERIALS', false)
local compatibleMode = ConfigGeneral:get('GHOST_RECORDER', 'HAUNTED_COMPATIBLE', false)
local ownCarID = ac.getCarID(0)
local ghost = require('shared/sim/ghost')
local weatherUtils = require('shared/sim/weather')
local hotlapUtils = require('src/_hotlap_utils')

if applySkins then
  hotlapUtils.applyGhostSkin(ghost.getMetadata())
end

if cfg.defaultRecordName ~= '' then
  ghost.setDefaultRecordName(cfg.defaultRecordName)
end

if ac.load('.SmallTweaks.Haunted.InitialRecord') == nil then
  ac.store('.SmallTweaks.Haunted.InitialRecord', ghost.getCurrentFilename() or '')
else
  ghost.reload(ac.load('.SmallTweaks.Haunted.InitialRecord'))
end

local registerUIComponent
local records = {} ---@type RecordInfo[]
local bestRecord ---@type RecordInfo?
local lastRecord ---@type RecordInfo?
local customRecordLoaded = ac.load('.SmallTweaks.Haunted.InitialRecord') ~= ''

---@param r RecordInfo? @Pass `nil` to load the best record.
local function loadGhost(r)
  customRecordLoaded = r ~= nil
  __util.native('__ghost.useBetterGhostRecord', customRecordLoaded)
  r = r or bestRecord
  if r then
    if not ghost.reload(r.filename) then
      ui.toast(ui.Icons.Warning, 'Failed to load ghost')
    elseif applySkins then
      hotlapUtils.applyGhostSkin(ghost.getMetadata())
    end
  end
end

local lastMirrored

---@param recordToMirror RecordInfo?
local function mirrorBestRecord(recordToMirror)
  if recordToMirror and compatibleMode then
    if lastMirrored == recordToMirror.filename then
      return
    end
    lastMirrored = recordToMirror.filename
    local layoutID = ac.getTrackLayout()
    local originalGhostFilename = string.format('%s/GhostCar/%s/GHOST_CAR_%s_%s%s.ghost',
      ac.getFolder(ac.FolderID.ACDocuments), ac.getTrackID(), ac.getDriverName(0), ac.getCarID(0),
      layoutID == '' and '' or '_'..layoutID)
    setTimeout(function ()
      local existingData = ghost.getMetadata(originalGhostFilename)
      if not existingData or not existingData.laptimeMs or existingData.laptimeMs > recordToMirror.metadata.laptimeMs then
        io.createFileDir(originalGhostFilename)
        local tmpFilename = originalGhostFilename:reggsub('\\.ghost$', '.tmp')
        if ghost.stripRecordMetadata(recordToMirror.filename, tmpFilename) then
          local attributes = io.getAttributes(tmpFilename)
          if attributes.exists then
            attributes.isArchive = true
            io.setAttributes(tmpFilename, attributes)
            io.move(tmpFilename, originalGhostFilename)
          end
        else
          ac.warn('Failed to mirror best record')
        end
      end
    end)
  end
end

---@param newlyRecorded RecordInfo?
local function updateBestRecord(newlyRecorded)
  local newBestRecord = table.minEntry(records, function (item)
    return item.metadata.car == ownCarID and item.metadata.laptimeMs or nil
  end)
  lastRecord = table.maxEntry(records, function (item)
    return item.metadata.car == ownCarID and item.time or nil
  end)
  if bestRecord ~= newBestRecord then
    bestRecord = newBestRecord
    if not customRecordLoaded then
      if bestRecord and newlyRecorded == bestRecord then
        ac.setMessage('New ghost record', 'Time: %s' % ac.lapTimeToString(bestRecord.metadata.laptimeMs, true))
        mirrorBestRecord(newlyRecorded)
      end
      loadGhost()
    end
  end
end

---@param newlyRecorded RecordInfo?
local function onRecordsListChanged(newlyRecorded)
  updateBestRecord(newlyRecorded)
  registerUIComponent()
end

---@param r RecordInfo
local function deleteGhost(r)
  local data = io.load(r.filename)
  if io.recycle(r.filename) then
    table.removeItem(records, r)
    onRecordsListChanged()
    ui.toast(ui.Icons.Trash, 'Ghost removed', function()
      io.save(r.filename, data)
      table.insert(records, r)
      onRecordsListChanged()
    end)
  else
    ui.toast(ui.Icons.Warning, 'Failed to remove ghost')
  end
end

---@param r ghost.RecordMetadata?
local function recordFits(r)
  if not r or not r.car then return false end
  if r.track ~= ac.getTrackID() or r.trackLayout ~= ac.getTrackLayout() then return false end
  if cfg.filterByCar and r.car ~= ownCarID then return false end
  if cfg.filterByTyres and (not r.tyres or r.tyres.short ~= ac.getTyresName(0)) then return false end
  return true
end

local function rescanRecords()
  local cur = hotlapUtils.getRecordByFilename()
  local wasSelected = table.contains(records, cur)
  table.clear(records)
  local initial = ac.load('.SmallTweaks.Haunted.InitialRecord')
  if initial ~= '' then
    records[1] = hotlapUtils.getRecordByFilename(initial)
  end
  local bestNewRecord ---@type RecordInfo?
  do
    local dir = ghost.getRecordsFolder()
    io.scanDir(dir, cfg.filterByCar and ownCarID .. '_*.ghost' or '*_*.ghost', function(fileName, fileAttributes)
      if not fileAttributes.isDirectory then
        local filename = dir .. '\\' .. fileName
        local r = hotlapUtils.getRecordByFilename(filename)
        if r then
          if recordFits(r.metadata) and not table.contains(records, r) then
            table.insert(records, r)
          end
          if r.metadata.car == ownCarID and r.metadata.track == ac.getTrackID() and r.metadata.trackLayout == ac.getTrackLayout()
            and (not bestNewRecord or r.metadata.laptimeMs < bestNewRecord.metadata.laptimeMs) then
            bestNewRecord = r
          end
        end
      end
    end)
  end
  mirrorBestRecord(bestNewRecord)
  do
    local oldDir = io.getParentPath(ghost.getRecordsFolder())
    local oldFilter = 'ghost_car_*_' .. (cfg.filterByCar and ownCarID or '*')
    local layout = ac.getTrackLayout()
    if layout ~= '' then
      oldFilter = oldFilter .. '_' .. layout .. '.ghost'
    else
      oldFilter = oldDir .. '.ghost'
    end
    io.scanDir(oldDir, oldFilter, function(fileName, fileAttributes)
      if not fileAttributes.isDirectory and not fileAttributes.isArchive then
        local filename = oldDir .. '\\' .. fileName
        local r = hotlapUtils.getRecordByFilename(filename)
        if r and recordFits(r.metadata) and not table.contains(records, r) then
          table.insert(records, r)
        end
      end
    end)
  end
  onRecordsListChanged()
  if not customRecordLoaded or wasSelected and not table.contains(records, cur) then
    loadGhost(nil)
  end
end

ghost.onNewRecord(function(filename, metadata)
  print('New ghost:', filename)
  local newlyRecorded = { filename = filename, metadata = metadata, isReadOnly = false, time = os.time() }
  records[#records + 1] = newlyRecorded

  local sameTyres = table.filter(records, function(item)
    return item.metadata.tyres and item.metadata.tyres.short == metadata.tyres.short
        and item.metadata.car == ownCarID
  end)
  local byTime = table.clone(sameTyres)
  table.sort(byTime, function(a, b) return a.time > b.time end)
  local keep = {}
  for i = 1, cfg.keepGhosts do
    if sameTyres[i] then keep[sameTyres[i]] = true end
    if byTime[i] then keep[byTime[i]] = true end
  end
  print('Records to keep:', table.nkeys(keep))
  for _, v in ipairs(sameTyres) do
    if not keep[v] and not v.isReadOnly then
      print('Delete unnecessary record:', v.filename, v.metadata.laptimeMs, v.time)
      table.removeItem(records, v)
      io.deleteFile(v.filename)
    end
  end
  onRecordsListChanged(newlyRecorded)
end)

local recordsTableStart = hotlapUtils.defineTable({
  { title = '##i',         width = 48, alignRight = true,  orderBy = function(item) return -item.time end },
  { title = 'Name', width = -3, alignRight = false, orderBy = function(item) return item.metadata.recordName end },
  { title = 'Car',         width = -2, alignRight = false, orderBy = function(item) return item.metadata.car end },
  { title = 'Lap time',    width = 85, alignRight = true,  orderBy = function(item) return item.metadata.laptimeMs end },
  { title = 'Tyres',       width = 62, alignRight = true,  orderBy = function(item) return item.metadata.tyres and
    item.metadata.tyres.short or '' end },
  {
    title = 'Assists',
    width = 66,
    alignRight = true,
    orderBy = function(item)
      if not item.metadata.helpers then
        return -1
      end
      return item.metadata.helpers.abs *
          10 + item.metadata.helpers.tc * 100 + item.metadata.helpers.drs
    end
  },
  { title = 'Temperature', width = 110, alignRight = true, orderBy = function(item) return item.metadata.temperature and
    item.metadata.temperature.road or 0 end },
  { title = 'Grip',        width = 60,  alignRight = true, orderBy = function(item) return item.metadata.roadGrip or 0 end },
  { title = 'Age',         width = 90,  alignRight = true, orderBy = function(item) return -item.time end },
}, { orderByFallback = function(item) return item.time end, defaultSort = 3 })


local sizeFit = vec2(-0.1, 0)
local sizeFitGapRight = vec2(-16, 0)
local alignLeft = vec2()
local alignRight = vec2(1, 0)
local bgHighlight = rgbm(0.5, 0.5, 0.5, 0.19)
local scrollToSelected = false
local startingConditionsType = ac.getConditionsSet().currentType

ac.onTyresSetChange(0, function ()
  rescanRecords()
end)
ac.overrideWeatherConditions(nil)
setTimeout(function ()
  startingConditionsType = ac.getConditionsSet().currentType
end)

local function addIcon(icon, color, isHovered, tooltip)
  ui.dummy(14)
  ui.addIcon(icon, 14, 0.5, color, 0)
  local showTooltip = isHovered and ui.itemHovered()
  if showTooltip then
    ui.setTooltip(tooltip)
  end
  ui.sameLine(0, 6)
  return showTooltip
end

local currentRecord

local function updateCurrentlySelected()
  currentRecord = hotlapUtils.getRecordByFilename()
end

local function recordsHeader()
  local start = ui.getCursorX()
  local space = ui.availableSpaceX() / 4
  ui.setNextItemIcon(ui.Icons.Recognition)
  if ui.button('Select the best', vec2(space - 4 - 24, 0),
      bit.bor(customRecordLoaded and 0 or ui.ButtonFlags.Active, 
      (customRecordLoaded or bestRecord and bestRecord ~= currentRecord) and 0 or ui.ButtonFlags.Disabled)) then
    loadGhost(nil)
    currentRecord = bestRecord
    scrollToSelected = true
  end
  if bestRecord and ui.itemHovered() then
    ui.tooltip(function ()
      hotlapUtils.recordDetailsTooltip(bestRecord, true)
      ui.separator()
      ui.pushFont(ui.Font.Small)
      ui.textWrapped(customRecordLoaded 
        and 'Currently using an explicitly selected ghost, selection won’t change automatically.'
        or 'Currently using the best available ghost, selection will change if a better ghost record would become available.', 400)
      ui.popFont()
    end)
  end
  ui.sameLine(0, 0)
  if ui.button('…') then
    ui.popup(function ()
      ---@param target RecordInfo
      local function selectSelectable(title, target)
        if ui.selectable(title, false, target and target.filename ~= currentRecord and 0 or ui.SelectableFlags.Disabled) then
          loadGhost(target)
          currentRecord = target
          scrollToSelected = true
        end
        if target and ui.itemHovered() then
          ui.tooltip(function ()
            hotlapUtils.recordDetailsTooltip(target, true)
          end)
        end
      end
      selectSelectable('Select the worst', table.maxEntry(records, function (item)
        return item.metadata.car == ownCarID and item.metadata.laptimeMs or nil
      end))
      selectSelectable('Select the latest', table.maxEntry(records, function (item)
        return item.metadata.car == ownCarID and item.time or nil
      end))
      if not cfg.filterByCar then
        ui.separator()
        selectSelectable('Select the best among all cars', table.minEntry(records, function (item)
          return item.metadata.laptimeMs or nil
        end))
        selectSelectable('Select the worst among all cars', table.maxEntry(records, function (item)
          return item.metadata.laptimeMs or nil
        end))
        selectSelectable('Select the latest among all cars', table.maxEntry(records, function (item)
          return item.time or nil
        end))
      end
    end, { pivot = vec2(), position = ui.windowPos() + vec2(ui.itemRectMin().x, ui.itemRectMax().y) })
  end
  ui.sameLine(start + space)
  local advantange = ghost.getAdvantageMs()
  ui.setNextItemIcon(advantange ~= 0 and ui.Icons.Stopwatch or ui.Icons.SettingsAlt)
  if ui.button('Other tweaks…', vec2(space - 4, 0)) then
    ui.popup(function ()
      ui.setNextItemIcon(ui.Icons.Edit)
      if ui.selectable('Set default record name…') then
        ui.modalPrompt('Change default record name?', 'Enter new name (leave empty to use driver name):', ghost.getDefaultRecordName(), 'Rename', nil, ui.Icons.Save, nil,
          function(value)
            cfg.defaultRecordName = value and value:trim() or ''
            ghost.setDefaultRecordName(cfg.defaultRecordName)
          end)
      end
      if ui.itemHovered() then
        ui.setTooltip('This name will be used for all the future saved ghosts from now on (by default, driver name is used)')
      end
      ui.separator()
      ui.setNextItemIcon(ui.Icons.Stopwatch)
      local value, edited = ui.slider('##advantange', ghost.getAdvantageMs() / 1e3, 0, 5, 'Ghost advantage: %.2f s', 2)
      if edited then
        ghost.setAdvantageMs(value * 1e3)
      end
      if ui.itemHovered() then
        ui.setTooltip('Shift ghost forward to make things more competitive (doesn’t affect other data, such as performance meter)')
      end
      local playing, recording = ghost.getActiveFlags()
      ui.setNextItemIcon(ui.Icons.Ghost)
      if ui.selectable('Ghost playback: %s' % (playing and 'active' or 'disabled'), playing, ui.SelectableFlags.DontClosePopups) then
        ghost.setActiveFlags(not playing, nil)
      end
      if ui.itemHovered() then
        ui.setTooltip('If ghost playback is disabled, ghost will be invisible (other ghost data, such as performance meter, would still be used)')
      end
      ui.setNextItemIcon(ui.Icons.RecordAlt)
      if ui.selectable('Ghost recording: %s' % (recording and 'active' or 'disabled'), recording, ui.SelectableFlags.DontClosePopups) then
        ghost.setActiveFlags(nil, not recording)
      end
      if ui.itemHovered() then
        ui.setTooltip('Start a new lap after re-enabling recording to actually start recording something')
      end
      ui.setNextItemIcon(weatherUtils.getWeatherIcon(ac.WeatherType.Clear))
      if ui.selectable('Set conditions to optimal') then
        ac.overrideWeatherConditions(hotlapUtils.getIdealConditionsSet())
      end
      if ui.itemHovered() then
        ui.setTooltip('26° C, no wind, ideal track surface: best conditions for the optimal laps')
      end
      ui.setNextItemIcon(weatherUtils.getWeatherIcon(startingConditionsType))
      if ui.selectable('Reset conditions to starting') then
        ac.overrideWeatherConditions(nil)
      end
      if ui.itemHovered() then
        ui.setTooltip('Stop any conditions override and restore the ones configured in CM')
      end
    end, { pivot = vec2(), position = ui.windowPos() + vec2(ui.itemRectMin().x, ui.itemRectMax().y) })
  end
  if ui.itemHovered() and advantange ~= 0 then
    ui.setTooltip('Ghost advantage: %.2f ' % (advantange / 1e3))
  end
  ui.sameLine(start + space * 2)
  if ui.checkbox('Same car', cfg.filterByCar) then
    cfg.filterByCar = not cfg.filterByCar
    rescanRecords()
    setTimeout(function ()
      scrollToSelected = true
    end)
  end
  ui.sameLine(start + space * 3)
  if ui.checkbox('Same tyres', cfg.filterByTyres) then
    cfg.filterByTyres = not cfg.filterByTyres
    rescanRecords()
  end
end

local function scrollToItem(curIndex, itemHeight)  
  if curIndex then
    if curIndex * itemHeight > ui.windowHeight() + ui.getScrollY() then
      ui.setScrollY(math.max(0, curIndex * itemHeight - ui.windowHeight()))
    elseif (curIndex - 3) * itemHeight < ui.getScrollY() then
      ui.setScrollY(math.max(0, (curIndex - 3) * itemHeight))
    end
  end
end

local aiColor = rgbm(0, 0.9, 1, 1)
local function recordsTable()
  local windowWidth = ui.windowWidth()
  local wideTable = windowWidth > 600
  local colAssists = recordsTableStart.toggleColumn('Assists', wideTable)
  local colTemperature = recordsTableStart.toggleColumn('Temperature',
    wideTable and (cfg.filterByCar or cfg.filterByTyres))
  local colCar = recordsTableStart.toggleColumn('Car', not cfg.filterByCar)
  local colTyres = recordsTableStart.toggleColumn('Tyres', not cfg.filterByTyres)
  local colGrip = recordsTableStart.toggleColumn('Grip', windowWidth > 400)
  local colAge = recordsTableStart.toggleColumn('Age', windowWidth > 350)
  ui.offsetCursorX(-16)
  ui.beginGroup(ui.availableSpaceX() + 24)
  recordsTableStart.header(records, true)
  ui.endGroup()
  ui.separator()
  ui.columns(1)

  ui.offsetCursorX(-20)
  ui.childWindow('scrolling', vec2(ui.availableSpaceX() + 20, -0.1), false, ui.WindowFlags.NoScrollbar, function()
    ui.offsetCursorY(4)
    recordsTableStart.scrolling()
    ui.thinScrollbarBegin(true)
    local currentTyres = ac.getTyresName(0)
    local ownName = ac.getDriverName(0)
    local now = os.time()
    local windowHovered = ui.windowHovered()
    if ui.windowHovered() and ui.captureKeyboard(false, true, false) 
        and (ui.keyPressed(ui.Key.Down) or ui.keyPressed(ui.Key.Up)) then
      local curIndex = table.indexOf(records, currentRecord) or 1
      local newIndex = ((curIndex + (ui.keyPressed(ui.Key.Down) and 1 or -1)) + #records - 1) % #records + 1
      currentRecord, scrollToSelected = records[newIndex], true
      loadGhost(currentRecord)
    end
    if scrollToSelected then
      scrollToSelected = false
      scrollToItem(table.indexOf(records, currentRecord), 23)
    end
    for i, r in ipairs(records) do
      if not ui.areaVisibleY(20) then
        ui.dummy(14)
        recordsTableStart.skipRow()
      else
        local rowRect1, rowRect2 = recordsTableStart.rowRect()
        local isSelectedRecord = r == currentRecord
        local anyTooltip = wideTable
        local isOwnRecord = ownName == r.metadata.recordName
        local isBestRecord = r == bestRecord
        local isLastRecord = r == lastRecord
        local isHovered = windowHovered and ui.rectHovered(rowRect1, rowRect2, false)
        local isUnfair = r.metadata.valid and (not r.metadata.valid.car or not r.metadata.valid.simulation)
        local isAI = r.metadata.helpers and r.metadata.helpers.autopilot
        local iconsCount = (isBestRecord and 1 or 0) + (isLastRecord and 1 or 0) + (isUnfair and 1 or 0) + (r.isReadOnly and 1 or 0) +
            (r.metadata.tyres and 0 or 1) + (isAI and 1 or 0)
        ui.pushID(i)
        if isSelectedRecord then
          ui.pushColumnsBackground()
          ui.drawRectFilled(rowRect1, rowRect2, bgHighlight)
          ui.popColumnsBackground()
        end
        -- ui.offsetCursorX(20)
        ui.offsetCursorX(16)
        ui.textAligned('%d.' % i, alignRight, sizeFit)
        ui.nextColumn()
        if isOwnRecord and cfg.highlightSameName then
          ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.yellow)
        end
        ui.textAligned(r.metadata.recordName, alignLeft, vec2(-20 * iconsCount - 0.01, 0), true)
        if isOwnRecord and cfg.highlightSameName then
          ui.popStyleColor()
        end
        if iconsCount > 0 then
          ui.sameLine(0, 0)
          if isAI and addIcon('AP:FORM_AI', aiColor, isHovered, 'With autopilot') then
            anyTooltip = true
          end
          if isUnfair and addIcon(ui.Icons.Warning, rgbm.colors.orange, isHovered, 'Data mismatch, car physics might have been edited') then
            anyTooltip = true
          end
          if not r.metadata.tyres and addIcon(ui.Icons.Question, rgbm.colors.white, isHovered, 'Old ghost record saved without extra details') then
            anyTooltip = true
          end
          if r.isReadOnly and addIcon(ui.Icons.Pin, rgbm.colors.white, isHovered, 'Ghost is pinned and won’t be deleted even if old or not one of the fastest') then
            anyTooltip = true
          end
          if isLastRecord and addIcon(ui.Icons.New, rgbm.colors.lime, isHovered, 'Latest ghost record') then
            anyTooltip = true
          end
          if isBestRecord and addIcon(ui.Icons.Recognition, rgbm.colors.yellow, isHovered, 'Best ghost record') then
            anyTooltip = true
          end
        end
        ui.nextColumn()
        if colCar then
          local isOwnCar = r.metadata.car == ownCarID
          if isOwnCar then
            ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.yellow)
          end
          local info = hotlapUtils.getCarInfo(r.metadata.car)
          ui.beginGroup()
          ui.image(info.logo, 14)
          ui.sameLine(0, 4)
          ui.textAligned(info.shortName, alignLeft, sizeFit, true)
          ui.endGroup()
          if ui.itemHovered() then
            ui.tooltip(function()
              hotlapUtils.carTooltip(r)
            end)
          end
          if isOwnCar then
            ui.popStyleColor()
          end
          ui.nextColumn()
        end
        ui.textAligned(ac.lapTimeToString(r.metadata.laptimeMs, true), alignRight, sizeFit)
        ui.nextColumn()
        if colTyres then
          if r.metadata.tyres then
            if currentTyres == r.metadata.tyres.short then
              ui.setNextTextBold()
            end
            ui.textAligned(r.metadata.tyres.short, alignRight, sizeFit, true)
            if ui.itemHovered() then
              hotlapUtils.showTyresTooltip(r.metadata)
              anyTooltip = true
            end
          else
            ui.textAligned('?', alignRight, sizeFit, true)
          end
          ui.nextColumn()
        end
        if colAssists then
          ui.textAligned(hotlapUtils.assistsList(r), alignRight, sizeFit, true)
          if r.metadata.helpers and ui.itemHovered() then
            ui.setTooltip(string.format('%sABS: %.0f%% of the lap\nTC: %.0f%% of the lap\nDRS: %.0f%% of the lap',
              r.metadata.helpers.autopilot and 'With autopilot\n' or '',
              r.metadata.helpers.abs * 100, r.metadata.helpers.tc * 100, r.metadata.helpers.drs * 100))
            anyTooltip = true
          end
          ui.nextColumn()
        end
        if colTemperature then
          ui.pushAlignment(false, 1)
          ui.beginGroup()
          ui.text(r.metadata.temperature
            and string.format('%.0f/%.0f °C', r.metadata.temperature.ambient, r.metadata.temperature.road)
            or '?')
          ui.sameLine(0, 8)
          ui.icon(
            r.metadata.weather and weatherUtils.getWeatherIcon(r.metadata.weather.currentType) or ui.Icons.Question, 14,
            not r.metadata.weather and rgbm.colors.gray or nil)
          ui.endGroup()
          if isHovered and ui.itemHovered() and r.metadata.temperature then
            ui.tooltip(function()
              anyTooltip = true
              hotlapUtils.conditionsTooltip(r)
            end)
          end
          ui.popAlignment()
          ui.nextColumn()
        end
        if colGrip then
          ui.textAligned(r.metadata.roadGrip and '%.0f%%' % (r.metadata.roadGrip * 100) or '?', alignRight, sizeFit, true)
          if isHovered and ui.itemHovered() and r.metadata.temperature then
            ui.tooltip(function()
              anyTooltip = true
              hotlapUtils.conditionsTooltip(r)
            end)
          end
          ui.nextColumn()
        end
        if colAge then
          ui.textAligned(hotlapUtils.timeToAge(r.time, now), alignRight, sizeFitGapRight)
          if isHovered then
            if ui.itemHovered() then
              ui.setTooltip('IRL date & time: %s' % os.date('%Y/%m/%d %H:%M', r.time))
            elseif not anyTooltip and r.metadata.tyres then
              ui.tooltip(function()
                hotlapUtils.recordDetailsTooltip(r)
              end)
            end
            if ui.mouseClicked(ui.MouseButton.Right) then
              ui.popup(function()
                hotlapUtils.recordMenu(r, deleteGhost)
              end)
            end
            if ui.mouseClicked(ui.MouseButton.Left) then
              loadGhost(r)
            end
          end
          ui.nextColumn()
        end
        ui.popID()
      end
    end
    ui.columns(1)
    ui.offsetCursorY(4)
    ui.thinScrollbarEnd()
  end)
end

local function mainMenuEmptyUI()
  updateCurrentlySelected()
  recordsHeader()
  ui.separator()
  ui.text('No saved ghosts.')
  ui.offsetCursorY(8)
  ui.pushFont(ui.Font.SmallItalic)
  ui.textWrapped(
    'Drive a few laps and go back here to set a name for the best lap time, or select a specific ghost record to race against.')
  ui.popFont()
end

local function mainMenuRecordsUI()
  updateCurrentlySelected()
  recordsHeader()
  ui.pushClipRect(vec2(), ui.windowSize(), false)
  recordsTable()
  ui.popClipRect()
end

local function mainMenuSettings()
  cfg.keepGhosts = ui.slider('##keep', cfg.keepGhosts, 5, 25, 'Keep ghosts: %.0f')
  if ui.itemHovered() then
    ui.setTooltip('How many of best and recent records keep around')
  end
  if ui.checkbox('Highlight records with matching name', cfg.highlightSameName) then
    cfg.highlightSameName = not cfg.highlightSameName
  end
  if ui.itemHovered() then
    ui.setTooltip('Highlight records with name matching current driver name in yellow')
  end
end

local addedMenu
registerUIComponent = function()
  if addedMenu then
    addedMenu()
  end
  if #records == 0 then
    addedMenu = ac.addMainMenuSettings(mainMenuEmptyUI, mainMenuSettings, 140)
  else
    addedMenu = ac.addMainMenuSettings(mainMenuRecordsUI, mainMenuSettings, math.min(400, 128 + #records * 23))
  end
end

rescanRecords()
if not customRecordLoaded then
  loadGhost(nil)
end