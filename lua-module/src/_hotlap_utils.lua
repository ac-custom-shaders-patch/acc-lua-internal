---@alias RecordInfo {filename: string, isReadOnly: boolean, metadata: ghost.RecordMetadata, time: integer, tag: string?}

---@inlined-exclude: on
local ghost = require('shared/sim/ghost')
local weatherUtils = require('shared/sim/weather')

ui.onExclusiveHUD(function(mode)
  return 'debug-nonexclusive'
end)
---@inlined-exclude: off

local recordCache = {}

---@return RecordInfo?
local function getRecordByFilename(filename)
  if filename == nil then
    filename = ghost.getCurrentFilename()
    if filename == nil then return nil end
  end
  filename = filename:lower():reggsub('[/\\\\]+', '/')
  local r = recordCache[filename]
  if r == nil then
    local attr = io.getAttributes(filename)
    local metadata = attr.exists and ghost.getMetadata(filename)
    r = metadata and {
      filename = filename,
      metadata = metadata,
      time = attr.creationTime,
      isReadOnly = attr.isReadOnly,
    } or false
    recordCache[filename] = r
  end
  return r or nil
end

local carsCache = {}

local function gatherCarInfo(carID)
  local dir = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID
  local ret = {
    id = carID,
    name = carID,
    shortName = skinID,
    exists = io.dirExists(dir),
    dir = dir,
    logo = dir .. '/ui/badge.png',
    skins = {}
  }
  io.loadAsync(dir .. '/ui/ui_car.json', function(err, response)
    local d = JSON.parse(response)
    ret.name = d.name
    ret.shortName = ret.name
    if string.startsWith(ret.shortName, d.brand..' ') then
      ret.shortName = string.sub(ret.shortName, #d.brand + 2):trim()
    end
  end)
  return ret
end

local function gatherDefaultSkinID(carID)
  local dir = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carID .. '/skins'
  local ret = 'default'
  io.scanDir(dir, function(fileName, fileAttributes)
    if fileAttributes.isDirectory then
      ret = fileName
      return true
    end
  end)
  return ret
end

local function gatherSkinInfo(args)
  local carInfo, skinID = args[1], args[2]
  local dir = carInfo.dir .. '/skins/' .. skinID
  local ret = {
    id = skinID,
    name = skinID,
    exists = io.dirExists(dir),
    dir = dir,
    logo = dir .. '/livery.png',
    preview = dir .. '/preview.jpg'
  }
  io.loadAsync(dir .. '/ui_skin.json', function(err, response)
    local d = JSON.parse(response)
    ret.name = d.name or ret.name
  end)
  return ret
end

local carSkinIDsCache = {}

local function getDefaultSkinID(carID)
  return table.getOrCreate(carSkinIDsCache, carID, gatherDefaultSkinID, carID)
end

---@param carID string
local function getCarInfo(carID)
  return table.getOrCreate(carsCache, carID, gatherCarInfo, carID)
end

---@param carInfo table
---@param skinID string
local function getSkinInfo(carInfo, skinID)
  skinID = skinID or getDefaultSkinID(carInfo.id)
  return table.getOrCreate(carInfo.skins, skinID, gatherSkinInfo, { carInfo, skinID })
end

---@param r RecordInfo
local function switchCar(r)
  local carInfo = getCarInfo(r.metadata.car)
  local skinInfo = r.metadata.skin and getSkinInfo(getCarInfo(r.metadata.car), r.metadata.skin)
  if r.metadata.car ~= ac.getCarID(0) then
    ui.modalPopup('Switch car?', 'Restart the session with %s?' % carInfo.name, 'Switch', nil, nil, nil,
      function(okPressed)
        if okPressed then
          ac.restartAssettoCorsa('[RACE]\nMODEL=%s' % r.metadata.car)
        end
      end)
  elseif skinInfo and r.metadata.skin ~= ac.getCarSkinID(0) then
    if skinInfo.exists then
      ui.modalPopup('Switch skin?', 'Restart the session with this skin?', 'Switch', nil, nil, nil, function(okPressed)
        if okPressed then
          ac.restartAssettoCorsa('[RACE]\nSKIN=%s\n[CAR_0]\nSKIN=%s' % { r.metadata.skin, r.metadata.skin })
        end
      end)
    else
      ui.modalPopup('Can’t switch car', 'Skin is missing', 'OK', '-', ui.Icons.Confirm, nil)
    end
  else
    ui.modalPopup('Can’t switch car', 'You’re already driving this exact car', 'OK', '-', ui.Icons.Confirm, nil)
  end
end

---@param columns {title: string, width: number, alignRight: boolean?, orderBy: function, initialOrderDir: integer?, disabled: boolean?}[]
---@param params {orderByFallback: function, defaultSort: integer?}
local function defineTable(columns, params)
  local r, t, columnsCount, dirty = 0, 0, 0, true
  local function recompute()
    if not dirty then return end
    r, t, columnsCount, dirty = 0, 0, 0, false
    for _, c in ipairs(columns) do
      if not c.disabled then
        columnsCount = columnsCount + 1
        if c.width < 0 then
          r = r + c.width
        else
          t = t + c.width
        end
      end
    end
  end
  local byTitle = table.map(columns, function (c) return c, c.title  end)
  local sorting = { col = columns[params.defaultSort or 1].orderBy, dir = -1 }
  local sortingCallback = function(i1, i2)
    if sorting.dir == 1 then i1, i2 = i2, i1 end
    local v1, v2 = sorting.col(i1), sorting.col(i2)
    if v1 == v2 then v1, v2 = params.orderByFallback(i1), params.orderByFallback(i2) end
    return v1 < v2
  end
  local rowRect = { vec2(-8, 0), vec2() }
  return {
    skipRow = function ()
      recompute()
      for _ = 1, columnsCount do
        ui.nextColumn()
      end
    end,
    toggleColumn = function (title, enabled)
      local c = byTitle[title]
      if c.disabled ~= not enabled then
        c.disabled = not enabled
        dirty = true
        if sorting.col == c.orderBy then
          sorting.col = columns[1].orderBy
        end
      end
      return enabled
    end,
    isColumnActive = function (title)
      return not byTitle[title].disabled
    end,
    header = function(data, separator)
      recompute()
      local f = ui.availableSpaceX() - t
      ui.columns(columnsCount, ui.ColumnsFlags.NoResize)
      if separator then
        ui.separator()
      end
      local j = 0
      for i, c in ipairs(columns) do
        if not c.disabled then
          ui.setColumnWidth(j, c.width < 0 and f * c.width / r or c.width)
          if ui.columnSortingHeader(i == 1 and '\t' .. c.title or i == #columns and c.title .. '\t' or c.title, sorting.col == c.orderBy and sorting.dir or 0, c.alignRight) then
            sorting.col, sorting.dir = c.orderBy, sorting.col ~= c.orderBy and -1 or -sorting.dir
          end
          j = j + 1
        end
      end
      table.sort(data, sortingCallback)
    end,
    scrolling = function()
      recompute()
      local f = ui.availableSpaceX() - t
      ui.columns(columnsCount, ui.ColumnsFlags.NoResize)
      local j = 0
      for i, c in ipairs(columns) do
        if not c.disabled then
          ui.setColumnWidth(j, c.width < 0 and f * c.width / r or c.width)
          j = j + 1
        end
      end
    end,
    rowRect = function()
      rowRect[1].y = ui.getCursorY() - 3
      rowRect[2].x = ui.windowWidth()
      rowRect[2].y = rowRect[1].y + 22
      return rowRect[1], rowRect[2]
    end,
  }
end

local ageUnits = {
  { name = 'y',  secs = 365 * 24 * 3600 },
  { name = 'mo', secs = 30 * 24 * 3600 },
  { name = 'd',  secs = 24 * 3600 },
  { name = 'h',  secs = 3600 },
  { name = 'm',  secs = 60 },
  { name = 's',  secs = 1 },
}
local function formatAge(seconds)
  if seconds < 1 then
    return 'just now'
  end
  local parts = table.new(2, 0)
  for _, unit in ipairs(ageUnits) do
    local value = math.floor(seconds / unit.secs)
    if value > 0 then
      table.insert(parts, value .. unit.name)
      seconds = seconds % unit.secs
    end
    if #parts >= 2 or value > 5 then break end
  end
  return table.concat(parts, ' ')
end

local function timeToAge(time, now)
  return formatAge(math.ceil(now - time))
end

local parsedSetup

---@param r ghost.RecordMetadata
local function getSetupDetails(r)
  if not parsedSetup or parsedSetup[1] ~= (r.setup or '') then
    local p = ac.INIConfig.parse(r.setup or '', ac.INIFormat.Default)
    local setupData = table.map(ac.getSetupSpinners(), function(v) return v, v.name end)
    local s = {}
    for k, v in pairs(p.sections) do
      if k ~= 'TYRES' and k ~= 'ABS' and k ~= 'TRACTION_CONTROL' then
        local e = v['VALUE']
        if e and e[1] then
          local vn = tonumber(e[1])
          local sd = setupData[k]
          if sd and vn and sd.defaultValue ~= vn then
            table.insert(s, '• %s: %.1f' % { sd.label, e[1] * sd.displayMultiplier })
          end
        end
      end
    end
    table.sort(s)
    parsedSetup = { r.setup or '', table.concat(s, '\n') }
  end
  return parsedSetup[2]
end

---@param r ghost.RecordMetadata
local function showTyresTooltip(r)
  local m = 'Tyres: ' .. r.tyres.full
  if r.car == ac.getCarID(0) then
    local d = getSetupDetails(r)
    m = m .. (d == '' and '\nSetup: default' or '\nSetup:\n' .. d)
  end
  ui.setTooltip(m)
end

---@param r RecordInfo
local function setReadOnly(r, readOnly)
  if r.isReadOnly == readOnly then return end
  local a = io.getAttributes(r.filename)
  if a.exists then
    r.isReadOnly = readOnly
    a.isReadOnly = readOnly
    io.setAttributes(r.filename, a)
  end
end

local appliedSkin

---@param metadata ghost.RecordMetadata?
local function applyGhostSkin(metadata)
  if metadata and metadata.car and metadata.skin then
    local skinDir = ac.getFolder(ac.FolderID.ContentCars)..'/'..metadata.car..'/skins/'..metadata.skin
    if skinDir ~= appliedSkin then
      appliedSkin = skinDir
      ac.findNodes('ghostRoot:yes'):resetSkin():applySkin(skinDir)
    end
  end
end

---@param r RecordInfo
local function conditionsTooltip(r)
  ui.bulletText('In-game date & time: %s' % os.dateGlobal('%Y/%m/%d %H:%M', r.metadata.timestamp))
  if r.metadata.weather then
    ui.bulletText('Weather: %s' %
      (weatherUtils.getWeatherName(r.metadata.weather.currentType) or r.metadata.weather.currentType))
    if r.metadata.weather.rainIntensity > 0
        or r.metadata.weather.rainWater > 0
        or r.metadata.weather.rainWetness > 0 then
      ui.bulletText('Rain intensity: %.0f%%' %
        (math.max(r.metadata.weather.rainIntensity, r.metadata.weather.rainWetness) * 100))
      ui.bulletText('Puddles: %.0f%%' % (r.metadata.weather.rainWater * 100))
    else
      ui.bulletText('No rain')
    end
  else
    ui.bulletText('Weather: not saved')
  end
  ui.bulletText('Air temperature: %.0f °C' % r.metadata.temperature.ambient)
  ui.bulletText('Road temperature: %.0f °C' % r.metadata.temperature.road)
  ui.bulletText(ac.getUI().useImperialUnits
    and 'Wind speed: %.0f m/h' % (r.metadata.wind.speedKmh * 0.62137119)
    or 'Wind speed: %.0f km/h' % r.metadata.wind.speedKmh)
  ui.bulletText('Wind direction: %.0f°' % r.metadata.wind.directionDeg)
end

---@param r RecordInfo
local function recordDetailsTooltip(r, full)
  if full then
    ui.bulletText('Name: %s' % (r.metadata.recordName or '?'))
    ui.bulletText('Time: %s' % ac.lapTimeToString(r.metadata.laptimeMs, true))
    if r.metadata.car and r.metadata.car ~= ac.getCarID(0) then
      ui.bulletText('Car: %s' % getCarInfo(r.metadata.car).name)
    end
    ui.separator()
  end
  ui.bulletText('ABS: %.0f%% of the lap' % (r.metadata.helpers.abs * 100))
  ui.bulletText('TC: %.0f%% of the lap' % (r.metadata.helpers.tc * 100))
  ui.bulletText('DRS: %.0f%% of the lap' % (r.metadata.helpers.drs * 100))
  conditionsTooltip(r)
  if full then
    ui.separator()
    ui.bulletText('IRL date & time: %s' % os.date('%Y/%m/%d %H:%M', r.time))
  end
end

local compoundIndexCache = {}

local function getCompoundsIndex(shortName)
  local r = compoundIndexCache[shortName]
  if not r then
    r = -1
    for i = 0, 99 do
      local n = ac.getTyresName(0, i)
      if n == shortName then r = i break end
      if n == '' then break end
    end
    compoundIndexCache[shortName] = r
  end
  return r
end

local function setRecordName(r, newName)
  newName = newName and newName:sub(1, 80):trim()
  if newName and newName ~= '' and newName ~= r.metadata.recordName then
    local readOnly = r.isReadOnly
    if readOnly then setReadOnly(r, false) end
    ghost.changeRecordName(r.filename, newName)
    if readOnly then setReadOnly(r, true) end
    r.metadata.recordName = newName
  end
end

---@param r RecordInfo
local function renameGhost(r)
  ui.modalPrompt('Rename record?', 'Enter new name:', r.metadata.recordName, 'Rename', nil, ui.Icons.Save, nil,
    function(value) setRecordName(r, value) end)
end

---@param r RecordInfo
local function assistsList(r)
  local t = {}
  if not r.metadata.helpers then
    t[1] = '?'
  else
    if r.metadata.helpers.autopilot then table.insert(t, 'AI') end
    if r.metadata.helpers.abs > 0 then table.insert(t, 'ABS') end
    if r.metadata.helpers.tc > 0 and #t < 2 then table.insert(t, 'TC') end
    if r.metadata.helpers.drs > 0 and #t < 2 then table.insert(t, 'DRS') end
  end
  return t[1] and table.concat(t, '+') or 'none'
end

local function carTooltip(r)
  local carInfo = getCarInfo(r.metadata.car)
  if not carInfo.exists then
    ui.setNextTextBold()
    ui.text('Car “%s” is not installed.' % carInfo.name)
  else
    local skinInfo = getSkinInfo(getCarInfo(r.metadata.car), r.metadata.skin)
    ui.icon(carInfo.logo, 14)
    ui.sameLine(0, 8)
    ui.text(carInfo.name)
    ui.icon(skinInfo.logo, 14)
    ui.sameLine(0, 8)
    ui.text('Skin: %s' % skinInfo.name)
    ui.image(skinInfo.preview, vec2(355, 200), ui.ImageFit.Fill)
    if r.metadata.skin == ac.getCarSkinID(0) then
      ui.setNextTextBold()
      ui.text('This car with this skin is selected right now.')
    end
  end
end

---@param r RecordInfo
---@param deleteGhostFn fun(r: RecordInfo)
local function recordMenu(r, deleteGhostFn)
  local sameCar = r.metadata.car == ac.getCarID(0)
  local carInfo = getCarInfo(r.metadata.car)
  ui.setNextItemIcon(carInfo.logo)
  if ui.selectable('Change car to %s…' % carInfo.shortName, false,
        (not carInfo.exists or sameCar and (not r.metadata.skin or r.metadata.skin == ac.getCarSkinID(0)))
        and ui.SelectableFlags.Disabled or 0) then
    switchCar(r)
  end
  if ui.itemHovered() then
    ui.tooltip(function()
      carTooltip(r)
    end)
  end
  ui.setNextItemIcon(ui.Icons.Tyre)
  local canApplyTyres = r.metadata.tyres 
    and getCompoundsIndex(r.metadata.tyres.short) ~= -1 and r.metadata.tyres.short ~= ac.getTyresName(0)
  if ui.selectable('Apply the same tyres%s' % (r.metadata.tyres and ' (%s)' % r.metadata.tyres.short or ''), false,
        canApplyTyres and 0 or ui.SelectableFlags.Disabled) and r.metadata.tyres then
    ac.setSetupSpinnerValue('COMPOUND', getCompoundsIndex(r.metadata.tyres.short))
  end
  if ui.itemHovered() and r.metadata.tyres then
    ui.setTooltip(r.metadata.tyres.full)
  end
  ui.setNextItemIcon(ui.Icons.Repair)
  if ui.selectable('Apply the same setup%s' % (r.metadata.setup and '' or ' (default)'), false, sameCar and 0 or ui.SelectableFlags.Disabled) then
    local curSetup = ac.stringifyCurrentSetup(false)
    ac.loadSetup(r.metadata.setup or '')
    ui.toast(ui.Icons.Repair, 'Setup applied', function()
      ac.loadSetup(curSetup)
    end)
  end
  if ui.itemHovered() then
    local t = getSetupDetails(r.metadata)
    ui.setTooltip(t == '' and 'Default setup' or t)
  end
  ui.setNextItemIcon(weatherUtils.getWeatherIcon(r.metadata.weather and r.metadata.weather.currentType or nil))
  if ui.selectable('Apply the same weather conditions', false,
        r.metadata.weather and 0 or ui.SelectableFlags.Disabled) then
    local conditions = ac.ConditionsSet(r.metadata.weather)
    if r.metadata.temperature then
      conditions.temperatures.ambient = r.metadata.temperature.ambient
      conditions.temperatures.road = r.metadata.temperature.road
    end
    if r.metadata.wind then
      conditions.wind.speedFrom = r.metadata.wind.speedKmh
      conditions.wind.speedTo = r.metadata.wind.speedKmh
      conditions.wind.direction = r.metadata.wind.directionDeg
    end
    ac.overrideWeatherConditions(conditions)
  end
  if ui.itemHovered() then
    if r.metadata.weather then
      ui.tooltip(function()
        ui.bulletText('Weather: %s' %
          (weatherUtils.getWeatherName(r.metadata.weather.currentType) or r.metadata.weather.currentType))
        if r.metadata.weather.rainIntensity > 0
            or r.metadata.weather.rainWater > 0
            or r.metadata.weather.rainWetness > 0 then
          ui.bulletText('Rain intensity: %.0f%%' %
            (math.max(r.metadata.weather.rainIntensity, r.metadata.weather.rainWetness) * 100))
          ui.bulletText('Puddles: %.0f%%' % (r.metadata.weather.rainWater * 100))
        else
          ui.bulletText('No rain')
        end
        ui.bulletText('Air temperature: %.0f °C' % r.metadata.temperature.ambient)
        ui.bulletText('Road temperature: %.0f °C' % r.metadata.temperature.road)
        ui.bulletText(ac.getUI().useImperialUnits
          and 'Wind speed: %.0f m/h' % (r.metadata.wind.speedKmh * 0.62137119)
          or 'Wind speed: %.0f km/h' % r.metadata.wind.speedKmh)
        ui.bulletText('Wind direction: %.0f°' % r.metadata.wind.directionDeg)
      end)
    else
      ui.setTooltip('Weather data is missing from this ghost')
    end
  end
  ui.separator()
  ui.setNextItemIcon(ui.Icons.Pin)
  if ui.selectable(r.isReadOnly and 'Unpin record' or 'Pin record', r.isReadOnly) then
    setReadOnly(r, not r.isReadOnly)
  end
  if ui.itemHovered() then
    ui.setTooltip('Pinned records stay even if they’re not the latest or the best')
  end
  ui.setNextItemIcon(ui.Icons.Folder)
  if ui.selectable('View in Explorer') then
    os.showInExplorer(r.filename)
  end
  if ui.itemHovered() then
    ui.setTooltip('Open a new Windows Explorer window selecting the file for this ghost')
  end
  ui.separator()
  ui.setNextItemIcon(ui.Icons.Edit)
  if ui.selectable('Rename record…') then
    renameGhost(r)
  end
  ui.setNextItemIcon(ui.Icons.Trash)
  if ui.selectable('Delete record') then
    deleteGhostFn(r)
  end
end

local function getIdealConditionsSet()
  local c = ac.ConditionsSet()
  c.currentType = ac.WeatherType.Clear
  c.upcomingType = ac.WeatherType.Clear
  c.transition = 0
  c.humidity = 0.5
  c.temperatures.ambient = 26
  c.temperatures.road = 42
  c.trackState.sessionStart = 100
  c.trackState.sessionTransfer = 0
  c.trackState.randomness = 0
  c.trackState.lapGain = 0
  return c
end

return {
  getRecordByFilename = getRecordByFilename,
  getCarInfo = getCarInfo,
  getSkinInfo = getSkinInfo,
  switchCar = switchCar,
  defineTable = defineTable,
  timeToAge = timeToAge,
  getSetupDetails = getSetupDetails,
  showTyresTooltip = showTyresTooltip,
  setReadOnly = setReadOnly,
  applyGhostSkin = applyGhostSkin,
  conditionsTooltip = conditionsTooltip,
  recordDetailsTooltip = recordDetailsTooltip,
  assistsList = assistsList,
  recordMenu = recordMenu,
  carTooltip = carTooltip,
  getIdealConditionsSet = getIdealConditionsSet,
}