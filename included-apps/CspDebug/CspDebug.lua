local PHYSICS_DEBUG_PICK_CARS = false -- set to `true` to be able to activate lines for certain cars

local sim = ac.getSim()
local defaultCar = ac.getCar(0)
local currentMode = ac.VAODebugMode.Active
local debugLines = { types = {}, cars = { [1] = true } }
local lightSettings = table.chain(
  { filter = '?', count = 10, distance = 100, flags = { outline = true, bbox = true, bsphere = false, text = true }, active = false, dirty = true },
  stringify.tryParse(ac.storage.debugLightsSettings, {}))
lightSettings.active = false

local debugWeatherControl = ac.connect({
  ac.StructItem.key('weatherFXDebugOverride'),
  weatherType = ac.StructItem.byte(),
  debugSupported = ac.StructItem.boolean()
})
local debugWeatherControlExt = ac.connect({
  ac.StructItem.key('weatherFXDebugOverride.1'),
  windDirection = ac.StructItem.float(),
  windSpeedFrom = ac.StructItem.float(),
  windSpeedTo = ac.StructItem.float(),
  humidity = ac.StructItem.float(),
  pressure = ac.StructItem.float(),
  rainIntensity = ac.StructItem.float(),
  rainWetness = ac.StructItem.float(),
  rainWater = ac.StructItem.float(),
})
debugWeatherControl.weatherType = 255
debugWeatherControl.debugSupported = false

local function syncState()
  local t, c = 0, 0
  for k, v in pairs(debugLines.types) do
    if v then
      t = bit.bor(t, k)
    end
  end
  for k, v in pairs(debugLines.cars) do
    if v then
      c = bit.bor(c, bit.lshift(1, k - 1))
    end
  end

  local carIndex = math.max(0, sim.focusedCar)
  ac.setPhysicsDebugLines(c ~= 0 and t or 0, PHYSICS_DEBUG_PICK_CARS and c or bit.lshift(1, carIndex))

  if lightSettings.dirty then
    lightSettings.dirty = false
    if lightSettings.active then
      local flags = 0
      if lightSettings.flags.outline then flags = bit.bor(flags, ac.LightsDebugMode.Outline) end
      if lightSettings.flags.bbox then flags = bit.bor(flags, ac.LightsDebugMode.BoundingBox) end
      if lightSettings.flags.bsphere then flags = bit.bor(flags, ac.LightsDebugMode.BoundingSphere) end
      if lightSettings.flags.text then flags = bit.bor(flags, ac.LightsDebugMode.Text) end
      local filter = lightSettings.filter
      if filter == '' then filter = '?' end
      ac.debugLights(filter, lightSettings.count, flags, lightSettings.distance)
    else
      ac.debugLights('', 0, ac.LightsDebugMode.None, 0)
    end
  end
  ac.storage.debugLightsSettings = stringify(lightSettings)
end

local function controlSceneDetail(label, value, postfix)
  ui.text(label .. ': ')
  ui.sameLine(0, 0)
  ui.copyable(value)
  if postfix then
    ui.sameLine(0, 0)
    ui.text(' ' .. postfix)
  end
end

local function degressToCompassString(angleDeg)
  local value = math.round(angleDeg / 22.5)
  if value == 0 or value == 16 then
    return 'N'
  elseif value == 1 then
    return 'NNE'
  elseif value == 2 then
    return 'NE'
  elseif value == 3 then
    return 'ENE'
  elseif value == 4 then
    return 'E'
  elseif value == 5 then
    return 'ESE'
  elseif value == 6 then
    return 'SE'
  elseif value == 7 then
    return 'SSE'
  elseif value == 8 then
    return 'S'
  elseif value == 9 then
    return 'SSW'
  elseif value == 10 then
    return 'SW'
  elseif value == 11 then
    return 'WSW'
  elseif value == 12 then
    return 'W'
  elseif value == 13 then
    return 'WNW'
  elseif value == 14 then
    return 'NW'
  elseif value == 15 then
    return 'NNW'
  else
    return '?'
  end
end

local function controlSceneDetails()
  local cameraPos = ac.getCameraPosition()
  controlSceneDetail('Camera', string.format('%.2f, %.2f, %.2f', cameraPos.x, cameraPos.y, cameraPos.z))
  controlSceneDetail('Altitude', string.format('%.2f', ac.getAltitude()), 'm')

  local compassAngle = ac.getCompassAngle(ac.getCameraForward())
  if compassAngle < 0 then compassAngle = compassAngle + 360 end
  controlSceneDetail('Compass', string.format('%.1f°', compassAngle), degressToCompassString(compassAngle))
  controlSceneDetail('FFB (pure)', string.format('%.1f%%', defaultCar.ffbPure * 100))
  controlSceneDetail('FFB (final)', string.format('%.1f%%', defaultCar.ffbFinal * 100))

  if ui.button('set observeDigital 1', vec2(-0.1, 0)) then
    ac.consoleExecute('set observeDigital 1')
  end

  if ui.button('Dirt: 0%', vec2(ui.availableSpaceX() / 2 - 2, 0)) then
    ac.setBodyDirt(0, 0)
  end
  ui.sameLine(0, 4)
  if ui.button('Dirt: 100%', vec2(-0.1, 0)) then
    ac.setBodyDirt(0, 1)
  end
  if ui.button('Toggle replay', vec2(-0.1, 0)) then
    ac.tryToToggleReplay(not ac.getSim().isReplayActive, 30)
  end
end

local function controlRender()
  ui.text('Mode:')
  if ui.radioButton('Default', currentMode == ac.VAODebugMode.Active) then currentMode = ac.VAODebugMode.Active end
  if ui.radioButton('Disable VAO', currentMode == ac.VAODebugMode.Inactive) then currentMode = ac.VAODebugMode.Inactive end
  if ui.radioButton('VAO only', currentMode == ac.VAODebugMode.VAOOnly) then currentMode = ac.VAODebugMode.VAOOnly end
  if ui.radioButton('Normals', currentMode == ac.VAODebugMode.ShowNormals) then
    currentMode = ac.VAODebugMode
        .ShowNormals
  end
  ac.setVAOMode(currentMode)


  ui.offsetCursorY(12)
  ui.text('Mirrors:')
  ui.image('dynamic::mirror::raw', vec2(ui.availableSpaceX(), 0.25 * ui.availableSpaceX()))
end

local function controlFocus()
  ui.childWindow('##cars', ui.availableSpace(), function()
    local s = ac.getSession(sim.currentSessionIndex)
    if s then
      for i, v in ipairs(s.leaderboard) do
        if ui.radioButton(string.format('#%d: %s', i, v.car:driverName()), sim.focusedCar == v.car.index) then
          ac.focusCar(v.car.index)
        end
      end
    else
      ---@type ac.StateCar[]
      local cars = table.range(sim.carsCount, function(index, callbackData)
        return ac.getCar(index - 1)
      end)
      table.sort(cars, function(a, b)
        return a.racePosition < b.racePosition
      end)
      for i = 1, sim.carsCount do
        if ui.radioButton(string.format('#%d: %s', i, cars[i]:driverName()), sim.focusedCar == cars[i].index) then
          ac.focusCar(cars[i].index)
        end
      end
    end
  end)
end

local function controlLights()
  ui.beginGroup()
  if ui.checkbox('Debug lights', lightSettings.active) then
    lightSettings.active = not lightSettings.active
    lightSettings.dirty = true
  end

  ui.alignTextToFramePadding()
  ui.text('Filter: ')
  ui.sameLine(0, 0)
  ui.setNextItemWidth(ui.availableSpaceX())
  lightSettings.filter = ui.inputText('?', lightSettings.filter, ui.InputTextFlags.Placeholder)
  if ui.itemHovered() then
    ui.setTooltip('Use section name as a filter with “?” for any number of any symbols')
  end

  ui.setNextItemWidth(ui.availableSpaceX())
  lightSettings.count = ui.slider('##count', lightSettings.count, 0, 100, 'Count: %.0f', 2)

  ui.setNextItemWidth(ui.availableSpaceX())
  lightSettings.distance = ui.slider('##distance', lightSettings.distance, 0, 1000, 'Distance: %.1f m', 2)

  local w = ui.availableSpaceX()
  if ui.checkbox('BBox', lightSettings.flags.bbox) then
    lightSettings.flags.bbox = not lightSettings.flags.bbox
    lightSettings.dirty = true
  end

  ui.sameLine(w / 2, 0)
  if ui.checkbox('BSphere', lightSettings.flags.bsphere) then
    lightSettings.flags.bsphere = not lightSettings.flags.bsphere
    lightSettings.dirty = true
  end

  if ui.checkbox('Outline', lightSettings.flags.outline) then
    lightSettings.flags.outline = not lightSettings.flags.outline
    lightSettings.dirty = true
  end

  ui.sameLine(w / 2, 0)
  if ui.checkbox('Text', lightSettings.flags.text) then
    lightSettings.flags.text = not lightSettings.flags.text
    lightSettings.dirty = true
  end

  ui.endGroup()
  if ui.itemEdited() then
    lightSettings.dirty = true
  end
end

local function controlVRAM()
  local vram = ac.getVRAMConsumption()
  if vram then
    ui.text(string.format('Usage:\n%.0f out of %.0f MB (%.3f%%)', vram.usage, vram.budget, 100 * vram.usage / vram
      .budget))
    ui.text(string.format('Reserved:\n%.0f out of %.0f MB (%.3f%%)', vram.reserved, vram.availableForReservation,
      100 * vram.reserved / vram.availableForReservation))
    ac.debug('vram.usage', vram.usage)
  else
    ui.textWrapped('VRAM stats are not available on this system')
  end

  local s = __util.native('alive_tex')
  if s then
    ui.offsetCursorY(8)
    ui.header('Alive textures:')
    ui.textWrapped(s)
  end
end

local savedStateFilename
local dragAround = false
local dragAroundFrame = 0
local dragTooltipFn
local applyPressure = 0
local awakeFor = 0

local _savedStates_cache = nil

---@return {name: string?, data: binary}[]
local function getSavedStates()
  if _savedStates_cache == nil then
    savedStateFilename = ac.getFolder(ac.FolderID.ExtCfgState) ..
        '/car_states/' .. ac.getTrackID() .. '__' .. ac.getCarID(0) .. '.bin'
    if not io.fileExists(savedStateFilename) then
      io.createDir(ac.getFolder(ac.FolderID.ExtCfgState) .. '/car_states')
      _savedStates_cache = {}
    else
      _savedStates_cache = stringify.binary.tryParse(io.load(savedStateFilename), {})
      if #_savedStates_cache > 0 and type(_savedStates_cache[1]) == 'string' then
        _savedStates_cache = table.map(_savedStates_cache, function(v, i)
          return { data = v, name = nil }
        end)
      end
    end
  end
  return _savedStates_cache
end

-- local carsUtils = require('shared/sim/cars')
-- setInterval(function ()
--   ac.debug('J', ac.getCar(0).extraJ)
--   if ac.isKeyPressed(ui.KeyIndex.LeftButton) then
--     ac.setExtraSwitch(9, not ac.getCar(0).extraJ)
--   end
-- end)

local btnSaveState = ac.ControlButton('app.CspDebug/Record car state')
local btnLoadState = ac.ControlButton('app.CspDebug/Load last car state')
btnSaveState:onPressed(function()
  if #getSavedStates() >= 99 then
    ui.toast(ui.Icons.Warning, 'Too many states saved, use CSP Debug app to remove old ones')
    return
  end
  ac.saveCarStateAsync(function(err, data)
    if err then
      ui.toast(ui.Icons.Warning, 'Failed to save car state: ' .. err)
      return
    end
    local savedStates = getSavedStates()
    table.insert(savedStates, { name = nil, data = data })
    ui.toast(ui.Icons.Save, 'Car state saved')
    io.save(savedStateFilename, stringify.binary(savedStates))

    -- ac.log(ac.getCar(0).position)
    -- ac.log(carsUtils.getCarStateTransform(data).position)

    -- -- local tr = mat4x4.translation(vec3(0, 1, 0))
    -- -- local tr = mat4x4.translation(-ac.getCar(0).position)
    -- --   :mulSelf(mat4x4.rotation(math.pi / 10, vec3(0, 1, 0)))
    -- --   :mulSelf(mat4x4.translation(ac.getCar(0).position))
    -- local tr = mat4x4.translation(-ac.getCar(0).position)
    --   :mulSelf(mat4x4.scaling(vec3(1, 1, -1)))
    --   :mulSelf(mat4x4.translation(ac.getCar(0).position))
    -- -- local tr = mat4x4.identity()
    -- local altered = carsUtils.alterCarStateTransform(data, tr)
    -- if altered then
    --   -- ac.log(carsUtils.getCarStateTransform(altered).position)
    --   ac.loadCarState(altered, 40)
    -- end
  end)
end)
btnLoadState:onPressed(function()
  local savedStates = getSavedStates()
  if #savedStates > 0 then
    if not ac.loadCarState(savedStates[#savedStates].data, 30) then
      ui.toast(ui.Icons.Warning, 'Can’t restore car state')
    end
  end
end)

function script.windowMainSettings()
  ui.alignTextToFramePadding()
  ui.text('Reset car:')
  ui.sameLine(160)
  ac.ControlButton('__EXT_CMD_RESET'):control(vec2(120, 0))

  ui.alignTextToFramePadding()
  ui.text('Reset & step back:')
  ui.sameLine(160)
  ac.ControlButton('__EXT_CMD_STEP_BACK'):control(vec2(120, 0))

  ui.alignTextToFramePadding()
  ui.text('Save car state:')
  ui.sameLine(160)
  btnSaveState:control(vec2(120, 0))

  ui.alignTextToFramePadding()
  ui.text('Load last car state:')
  ui.sameLine(160)
  btnLoadState:control(vec2(120, 0))

  ui.offsetCursorY(12)
  ui.pushFont(ui.Font.Small)
  ui.textWrapped('There bindings are available in offline practice sessions only.', 280)
  ui.popFont()
end

local clickToTeleport

local function controlCarUtils()
  local w = ui.availableSpaceX() / 2 - 2
  local w3 = (ui.availableSpaceX() - 8) / 3
  ui.text('Visual:')
  local car = ac.getCar(sim.focusedCar) or defaultCar
  if ui.button('Hide driver', vec2(w, 0), car.isDriverVisible and 0 or ui.ButtonFlags.Active) then
    ac.setDriverVisible(car.index, not car.isDriverVisible)
  end
  ui.sameLine(0, 4)
  if ui.button('Open door', vec2(w, 0), car.isDriverDoorOpen and ui.ButtonFlags.Active or 0) then
    ac.setDriverDoorOpen(car.index, not car.isDriverDoorOpen)
  end

  if not ac.isCarResetAllowed() then
    return
  end

  ui.offsetCursorY(12)
  ui.text('Helpers:')

  if not physics.allowed() then
    if ui.button('Reset', vec2(w, 0)) then
      ac.resetCar()
    end
    ui.sameLine(0, 4)
    if ui.button('Step back', vec2(w, 0)) then
      ac.takeAStepBack()
    end
    return
  end

  if ui.button('Reset', vec2(w3, 0)) then
    ac.resetCar()
  end
  ui.sameLine(0, 4)
  if ui.button('Step back', vec2(w3, 0)) then
    ac.takeAStepBack()
  end
  ui.sameLine(0, 4)
  if ui.button('Repair', vec2(w3, 0)) then
    physics.resetCarState(0)
  end

  if ui.button('Drag car around', vec2(ui.availableSpaceX() / 2 - 4, 0), dragAround and ui.ButtonFlags.Active or 0) then
    dragAround = not dragAround
    ac.disableCarRecovery(dragAround)
    ac.setCurrentCamera(ac.CameraMode.Free)
  end
  if dragAround and dragTooltipFn then
    dragTooltipFn()
  end
  if ui.itemHovered() then
    ui.setTooltip('Click right mouse button when dragging to fix a point and add a second one')
  end
  ui.sameLine(0, 4)
  if ui.button('Click to teleport', vec2(-0.1, 0), clickToTeleport and ui.ButtonFlags.Active) then
    if clickToTeleport then
      clearInterval(clickToTeleport)
      clickToTeleport = nil
    else
      clickToTeleport = setInterval(function()
        if ac.getUI().isMouseLeftKeyClicked and not ac.getUI().wantCaptureMouse then
          local pos = vec3()
          if render.createMouseRay():physics(pos) ~= -1 then
            physics.setCarPosition(0, pos, -ac.getSim().cameraLook)
          end

          clearInterval(clickToTeleport)
          clickToTeleport = nil
        end
      end)
    end
  end

  if ui.button('Blow tyres', vec2(w, 0)) then
    physics.blowTyres(0, ac.Wheel.All)
    -- physics.setTyresTemperature(0, ac.Wheel.All, 360)
    awakeFor = awakeFor + 5
  end
  ui.sameLine(0, 4)
  if ui.button('Do a jump', vec2(w, 0)) then
    physics.awakeCar(0)
    physics.addForce(0, vec3(), true, vec3(0, car.mass * 1000, 0), false)
    awakeFor = awakeFor + 5
  end

  ui.setNextItemWidth(ui.availableSpaceX() - 28)
  applyPressure = ui.slider('##pressure', applyPressure, -10, 20, 'Apply pressure: %.3f t', 2)
  ui.sameLine(0, 4)
  if ui.iconButton(ui.Icons.Backspace) then
    applyPressure = 0
  end

  if dragAround or applyPressure ~= 0 then
    dragAroundFrame = os.preciseClock()
  end

  ui.offsetCursorY(12)
  ui.text('State:')
  local savedStates = getSavedStates()

  local toRemove
  for i = 1, #savedStates do
    local state = savedStates[i]
    ui.pushID(i)
    if ui.button(state.name or ('State #' .. i), vec2(-48, 0)) then
      if not ac.loadCarState(state.data, 30) then
        ui.toast(ui.Icons.Warning, 'Can’t restore car state')
      end
    end
    if ui.itemHovered() then
      ui.setTooltip(i == #savedStates and btnLoadState:boundTo() and 'Load car state (%s)' % btnLoadState:boundTo() or
        'Load car state')
    end
    ui.sameLine(0, 4)
    if ui.iconButton(ui.Icons.Edit) then
      local edit = state
      ui.modalPrompt('Rename', 'New name for car state:', edit.name or '', function(value)
        if value then
          state.name = value
          io.save(savedStateFilename, stringify.binary(savedStates))
        end
      end)
    end
    ui.sameLine(0, 4)
    if ui.iconButton(ui.Icons.Delete) then
      toRemove = i
    end
    ui.popID()
  end
  if toRemove then
    local removed = table.remove(savedStates, toRemove)
    io.save(savedStateFilename, stringify.binary(savedStates))
    if removed then
      ui.toast(ui.Icons.Confirm, 'Car state removed', function()
        table.insert(savedStates, toRemove, removed)
        io.save(savedStateFilename, stringify.binary(savedStates))
      end)
    end
  end
  if ui.button('Save state', vec2(ui.availableSpaceX(), 0)) then
    ac.saveCarStateAsync(function(err, data)
      if err then
        ui.toast(ui.Icons.Warning, 'Failed to save car state: ' .. err)
        return
      end
      savedStates[#savedStates + 1] = { name = nil, data = data }
      ui.toast(ui.Icons.Save, 'Car state saved')
      io.save(savedStateFilename, stringify.binary(savedStates))
    end)
  end
  if ui.itemHovered() then
    ui.setTooltip(btnSaveState:boundTo() and 'Save car state (%s)' % btnSaveState:boundTo() or 'Save car state')
  end
end

local function controlTime()
  ui.text(os.dateGlobal('%Y-%m-%d %H:%M:%S', sim.timestamp) .. ' (x' .. sim.timeMultiplier .. ')')

  if sim.isOnlineRace then
    return
  end

  ui.offsetCursorY(12)
  ui.text('Offset:')
  if ui.smallButton('−12h') then ac.setWeatherTimeOffset(-12 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−4h') then ac.setWeatherTimeOffset(-4 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−1h') then ac.setWeatherTimeOffset(-1 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−20m') then ac.setWeatherTimeOffset(-20 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−1m') then ac.setWeatherTimeOffset(-1 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−5s') then ac.setWeatherTimeOffset(-5, true) end --ui.sameLine(0, 2)
  if ui.smallButton('+12h') then ac.setWeatherTimeOffset(12 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+4h') then ac.setWeatherTimeOffset(4 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+1h') then ac.setWeatherTimeOffset(1 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+20m') then ac.setWeatherTimeOffset(20 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+1m') then ac.setWeatherTimeOffset(1 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+5s') then ac.setWeatherTimeOffset(5, true) end --ui.sameLine(0, 2)

  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(3.5, 0))
  if ui.smallButton('−day') then ac.setWeatherTimeOffset(-24 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−week') then ac.setWeatherTimeOffset(-7 * 24 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−month') then ac.setWeatherTimeOffset(-30 * 24 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('−year') then ac.setWeatherTimeOffset(-365 * 24 * 60 * 60, true) end --ui.sameLine(0, 2)
  if ui.smallButton('+day') then ac.setWeatherTimeOffset(24 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+week') then ac.setWeatherTimeOffset(7 * 24 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+month') then ac.setWeatherTimeOffset(30 * 24 * 60 * 60, true) end
  ui.sameLine(0, 2)
  if ui.smallButton('+year') then ac.setWeatherTimeOffset(365 * 24 * 60 * 60, true) end --ui.sameLine(0, 2)
  ui.popStyleVar()

  ui.offsetCursorY(12)
  ui.text('Time flow:')
  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(6, 0))
  if ui.smallButton('0x') then ac.setWeatherTimeMultiplier(0) end
  ui.sameLine(0, 2)
  if ui.smallButton('1x') then ac.setWeatherTimeMultiplier(1) end
  ui.sameLine(0, 2)
  if ui.smallButton('60x') then ac.setWeatherTimeMultiplier(60) end
  ui.sameLine(0, 2)
  if ui.smallButton('600x') then ac.setWeatherTimeMultiplier(600) end
  ui.sameLine(0, 2)
  if ui.smallButton('6000x') then ac.setWeatherTimeMultiplier(6000) end
  ui.popStyleVar()
end

local currentConditions = ac.ConditionsSet()
local weatherTypes = {
  { 'Clear',            15 },
  { 'Few clouds',       16 },
  { 'Scattered clouds', 17 },
  { 'Broken clouds',    18 },
  { 'Overcast clouds',  19 },
  false,
  { 'Mist', 21 },
  { 'Fog',  20 },
  false,
  { 'Drizzle (light)',       3 },
  { 'Drizzle (medium)',      4 },
  { 'Drizzle (heavy)',       5 },
  { 'Rain (light)',          6 },
  { 'Rain (medium)',         7 },
  { 'Rain (heavy)',          8 },
  { 'Thunderstorm (light)',  0 },
  { 'Thunderstorm (medium)', 1 },
  { 'Thunderstorm (heavy)',  2 },
  { 'Sleet (light)',         12 },
  { 'Sleet (medium)',        13 },
  { 'Sleet (heavy)',         14 },
  { 'Snow (light)',          9 },
  { 'Snow (medium)',         10 },
  { 'Snow (heavy)',          11 },
  false,
  { 'Tornado',   27 },
  { 'Hurricane', 28 },
  false,
  { 'Smoke',   22 },
  { 'Haze',    23 },
  { 'Sand',    24 },
  { 'Dust',    25 },
  { 'Squalls', 26 },
  { 'Cold',    29 },
  { 'Hot',     30 },
  { 'Windy',   31 },
  { 'Hail',    32 }
}

local function controlWeatherSelector(current, callback)
  ui.setNextItemWidth(ui.availableSpaceX())
  ui.combo('##Types', 'Selected: ' .. (current and current[1] or '?'), ui.ComboFlags.HeightLarge, function()
    for _, k in ipairs(weatherTypes) do
      if not k then
        ui.separator()
      else
        if ui.selectable(k[1], k[2] == currentConditions.currentType) then
          callback(k[2])
        end
      end
    end
  end)
end

local function controlUI()
  for i, v in ipairs(ac.getAppWindows()) do
    ui.text('%s [%s]: %s, P=%s, S=%s, L=%s' %
      { v.name, v.title, not v.visible and 'hidden' or v.collapsed and 'collapsed' or v.pinned and 'pinned' or 'visible',
        v
            .position, v.size, v.layer })
  end
end

local function controlWeather()
  ac.getConditionsSetTo(currentConditions)

  local current = table.findFirst(weatherTypes, function(item, index, callbackData)
    return item and item[2] == currentConditions.currentType
  end)

  if sim.isOnlineRace then
    ui.text('Weather: ' .. (current and current[1] or '?'))
    return
  end

  if sim.isReplayActive then
    controlWeatherSelector(current, function(value)
      currentConditions.currentType = value
      currentConditions.upcomingType = value
      currentConditions.transition = 0
      ac.overrideReplayConditions(currentConditions)
    end)
    ui.pushItemWidth(ui.availableSpaceX())

    ui.beginGroup()
    ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
    currentConditions.wind.direction = ui.slider('##windd', currentConditions.wind.direction, 0, 360, 'Wind: %.0f°')
    ui.sameLine(0, 4)
    ui.setNextItemWidth(-0.1)
    currentConditions.wind.speedFrom = ui.slider('##winds', currentConditions.wind.speedFrom, 0, 100, '%.1f km/h', 2)
    currentConditions.wind.speedTo = currentConditions.wind.speedFrom
    ui.separator()
    ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
    currentConditions.humidity = ui.slider('##humidity', currentConditions.humidity * 100, 0, 100, 'Humidity: %.0f%%') /
        100
    ui.sameLine(0, 4)
    ui.setNextItemWidth(-0.1)
    currentConditions.pressure = ui.slider('##pressure', currentConditions.pressure / 1e3, 100, 120, 'Pressure: %.0f hpa') *
        1e3
    if ac.isModuleActive(ac.CSPModuleID.RainFX) then
      ui.separator()
      currentConditions.rainIntensity = ui.slider('##raini', currentConditions.rainIntensity * 100, 0, 100,
        'Rain: %.1f%%', 2) / 100
      if ui.itemHovered() then
        ui.setTooltip(require('shared/sim/weather').rainDescription(debugWeatherControlExt.rainIntensity))
      end
      ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
      currentConditions.rainWetness = ui.slider('##rainw', currentConditions.rainWetness * 100, 0, 100, 'Wetness: %.1f%%',
        2) / 100
      ui.sameLine(0, 4)
      ui.setNextItemWidth(-0.1)
      currentConditions.rainWater = ui.slider('##raint', currentConditions.rainWater * 100, 0, 100, 'Water: %.1f%%', 2) /
          100
    end
    ui.endGroup()

    if ui.itemEdited() then
      ac.overrideReplayConditions(currentConditions)
    end

    ui.popItemWidth()
    if ui.button('Reset replay override', vec2(-0.1, 0)) then
      ac.overrideReplayConditions(nil)
    end
    return
  end

  if not debugWeatherControl.debugSupported then
    ui.textWrapped('Needs default or compatible controller to override weather type during the race')
    return
  end

  controlWeatherSelector(current, function(value)
    debugWeatherControl.weatherType = value
  end)
  if debugWeatherControl.weatherType == 255 then
    debugWeatherControlExt.windDirection = sim.windDirectionDeg
    debugWeatherControlExt.windSpeedFrom = sim.weatherConditions.wind.speedFrom
    debugWeatherControlExt.windSpeedTo = sim.weatherConditions.wind.speedTo
    debugWeatherControlExt.pressure = sim.weatherConditions.pressure
    debugWeatherControlExt.humidity = sim.weatherConditions.humidity
    debugWeatherControlExt.rainIntensity = sim.rainIntensity
    debugWeatherControlExt.rainWetness = sim.rainWetness
    debugWeatherControlExt.rainWater = sim.rainWater
  end
  ui.pushItemWidth(-0.1)
  ui.beginGroup()
  ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
  debugWeatherControlExt.windDirection = ui.slider('##windd', debugWeatherControlExt.windDirection, 0, 360, 'Wind: %.0f°')
  ui.sameLine(0, 4)
  ui.setNextItemWidth(-0.1)
  debugWeatherControlExt.windSpeedFrom = ui.slider('##winds', debugWeatherControlExt.windSpeedFrom, 0, 100, '%.1f km/h',
    2)
  debugWeatherControlExt.windSpeedTo = debugWeatherControlExt.windSpeedFrom
  ui.separator()
  ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
  debugWeatherControlExt.humidity = math.max(
    ui.slider('##humidity', debugWeatherControlExt.humidity * 100, 0, 100, 'Humidity: %.0f%%') / 100, 1e-30)
  ui.sameLine(0, 4)
  ui.setNextItemWidth(-0.1)
  debugWeatherControlExt.pressure = ui.slider('##pressure', debugWeatherControlExt.pressure / 1e3, 80, 120,
    'Pressure: %.0f kPa') * 1e3
  if ac.isModuleActive(ac.CSPModuleID.RainFX) then
    ui.separator()
    debugWeatherControlExt.rainIntensity = ui.slider('##raini', debugWeatherControlExt.rainIntensity * 100, 0, 100,
      'Rain: %.1f%%', 2) / 100
    if ui.itemHovered() then
      ui.setTooltip(require('shared/sim/weather').rainDescription(debugWeatherControlExt.rainIntensity))
    end
    ui.setNextItemWidth(ui.availableSpaceX() / 2 - 2)
    debugWeatherControlExt.rainWetness = ui.slider('##rainw', debugWeatherControlExt.rainWetness * 100, 0, 100,
      'Wetness: %.1f%%', 2) / 100
    ui.sameLine(0, 4)
    ui.setNextItemWidth(-0.1)
    debugWeatherControlExt.rainWater = ui.slider('##raint', debugWeatherControlExt.rainWater * 100, 0, 100,
      'Water: %.1f%%', 2) / 100
  end
  ui.endGroup()
  if ui.itemEdited() then
    debugWeatherControl.weatherType = current[2]
  end
  ui.popItemWidth()
  if debugWeatherControl.weatherType ~= 255 and ui.button('Reset override', vec2(-0.1, 0)) then
    debugWeatherControl.weatherType = 255
  end
end

local isRacingLineDebugActive = false
local isCollidersDebugActive = nil
local isCollidersDebugOriginal = nil
local physicsDebugLines

---@param tyre ac.StateWheel
local function drawTyre(tyre, p1, p2)
  local rp = tyre.contactPoint - tyre.position
  local dx = 12 * rp:dot(tyre.transform.side) / tyre.tyreWidth
  local dz = 12 * rp:dot(tyre.transform.look) / tyre.tyreWidth
  ui.drawRectFilled(p1, p2, rgbm.colors.white, 2)
  ui.drawCircleFilled(vec2.tmp():set((p1.x + p2.x) / 2, (p1.y + p2.y) / 2), 1.5, rgbm(0, 0, 0, 0.1))
  ui.drawCircleFilled(vec2.tmp():set((p1.x + p2.x) / 2 - dx, (p1.y + p2.y) / 2 - dz), 1.5, rgbm.colors.black)
end

math.randomseed(1)
local colorsShuffled = table.range(8, function()
  return rgbm.new(hsv(math.random() * 360, 1, 1):rgb(), 1)
end)

local function controlPhysicsDebugLines()
  local car = ac.getCar(0)
  if car and car.focused then
    local y = ui.getCursorY() + 12
    local p = ui.getCursorX() + ui.availableSpaceX() - 28 - 12
    local h = 2 * car.wheels[1].tyreRadius / car.wheels[1].tyreWidth
    drawTyre(car.wheels[0], vec2(p, y), vec2(p + 12, y + 12 * h))
    drawTyre(car.wheels[1], vec2(p + 16, y), vec2(p + 28, y + 12 * h))
    drawTyre(car.wheels[2], vec2(p, y + 12 * h + 4), vec2(p + 12, y + 24 * h + 4))
    drawTyre(car.wheels[3], vec2(p + 16, y + 12 * h + 4), vec2(p + 28, y + 24 * h + 4))

    if ui.rectHovered(vec2(p, y), vec2(p + 36, y + 32 * h + 4)) then
      if car.extendedPhysics then
        ui.setTooltip('Contact points relative to tyres')
      else
        ui.setTooltip('Contact points relative to tyres (use extended physics for more accurate behaviour)')
      end
    end
  end

  ui.text('Debug lines:')
  if PHYSICS_DEBUG_PICK_CARS then
    ui.text('Types:')
  end
  if not physicsDebugLines then
    physicsDebugLines = table.map(ac.PhysicsDebugLines, function(item, index, callbackData)
      return index
    end)
    table.sort(physicsDebugLines)
  end
  for _, k in ipairs(physicsDebugLines) do
    local v = ac.PhysicsDebugLines[k]
    if v ~= 0 and ui.checkbox(k, debugLines.types[v] or false) then
      debugLines.types[v] = not debugLines.types[v]
    end
  end
  if PHYSICS_DEBUG_PICK_CARS then
    ui.text('Cars:')
    for i = 1, math.min(sim.carsCount, 63) do
      if ui.checkbox(string.format('Car #%d (%s)', i, ac.getCarID(i - 1)), debugLines.cars[i] or false) then
        debugLines.cars[i] = not debugLines.cars[i]
      end
    end
  end

  ui.offsetCursorY(12)
  ui.text('Other visuals:')
  if ui.checkbox('Rain racing line debug', isRacingLineDebugActive) then
    isRacingLineDebugActive = not isRacingLineDebugActive
    ac.debugRainRacingLine(isRacingLineDebugActive)
  end
  if ui.checkbox('Colliders', isCollidersDebugActive or false) then
    if isCollidersDebugActive == nil then
      render.on('main.root.transparent', function()
        if not isCollidersDebugActive then return end
        for i = 0, 2 do
          local focused = ac.getCar.ordered(i)
          if not focused then return end
          render.setBlendMode(render.BlendMode.AlphaBlend)
          render.setDepthMode(render.DepthMode.Normal)
          render.setCullMode(render.CullMode.None)
          render.mesh({
            mesh = ac.SimpleMesh.carCollider(focused.index, not isCollidersDebugOriginal),
            transform = focused.bodyTransform,
            textures = {},
            values = {},
            shader = [[float4 main(PS_IN pin) {
              float g = dot(normalize(pin.NormalW), normalize(pin.PosC));
              return float4(float3(saturate(-g), saturate(g), 1) * gWhiteRefPoint, pow(1 - abs(g), 2));
            }]]
          })

          render.setTransform(focused.transform, true)
          for i, v in ipairs(ac.getCarColliders(focused.index, not isCollidersDebugOriginal)) do
            local c = colorsShuffled[(i - 1) % #colorsShuffled + 1]
            render.debugBox(v.position, v.size, c)
          end
          render.setDepthMode(render.DepthMode.Off)
          for i, v in ipairs(ac.getCarColliders(focused.index, not isCollidersDebugOriginal)) do
            local c = colorsShuffled[(i - 1) % #colorsShuffled + 1]
            render.debugBox(v.position, v.size, rgbm.new(c.rgb, 0.05))
            render.debugText(focused.transform:transformPoint(v.position), 'Collider #%s' % i, c)
          end
        end
      end)
    end
    isCollidersDebugActive = not isCollidersDebugActive
  end
  if isCollidersDebugActive then
    ui.sameLine(80)
    if ui.checkbox('Unedited', isCollidersDebugOriginal) then
      isCollidersDebugOriginal = not isCollidersDebugOriginal
    end
  end
end

local function tabItem(label, fn)
  ui.tabItem(label, 0, function()
    ui.offsetCursorX(8)
    local s = ui.availableSpace()
    s.x = s.x - 8
    ui.childWindow('content', s, fn)
  end)
end

local carRef ---@type ac.SceneReference
local grabPoint
local grabActiveLink
local grabLinks = {}
local lastForce = 100000

---@param ref ac.SceneReference
local function findWheelIndex(ref)
  if #ref:filterAny('{ insideNthWheel:0, insideNthSuspension:0 }') > 0 then return 0 end
  if #ref:filterAny('{ insideNthWheel:1, insideNthSuspension:1 }') > 0 then return 1 end
  if #ref:filterAny('{ insideNthWheel:2, insideNthSuspension:2 }') > 0 then return 2 end
  if #ref:filterAny('{ insideNthWheel:3, insideNthSuspension:3 }') > 0 then return 3 end
  return -1
end

local lastDragLine = 0
local workerData = ac.connect({
  key = ac.StructItem.key('CspDebug.CarDebugWorker'),
  instanceKey = ac.StructItem.int32(),
  downforce = ac.StructItem.float(),
  activeDragLines = ac.StructItem.int32(),
  dragLines = ac.StructItem.array(ac.StructItem.struct({
    posL = ac.StructItem.vec3(),
    targetW = ac.StructItem.vec3(),
    wheel = ac.StructItem.int32(),
    force = ac.StructItem.float()
  }), 64)
})

workerData.instanceKey = 0
workerData.activeDragLines = 0

---@param car ac.StateCar
local function updateGrabLink(car, link, dt)
  local d = workerData.dragLines[lastDragLine]
  if link.wheel == -1 then
    car.graphicsToPhysicsTransform:transformPointTo(d.posL, link.posL)
  else
    d.posL:set(link.posL)
  end
  if link.wheel == -1 then
    link.posW = car.bodyTransform:transformPoint(link.posL)
  else
    link.posW = car.wheels[link.wheel].transformWheel:transformPoint(link.posL)
  end
  d.wheel = link.wheel
  d.targetW = link.target
  d.targetW = link.target
  d.force = link.force
  lastDragLine = lastDragLine + 1
end

dragTooltipFn = function()
  if dragAround and grabActiveLink then
    ui.setTooltip('Force: %.0f N\nUse [ and ] buttons to change the force' % grabActiveLink.force)
  end
end

function script.update(dt)
  if awakeFor > 0 then
    awakeFor = awakeFor - dt
    physics.awakeCar(0)
  end

  if os.preciseClock() > dragAroundFrame + 1 or applyPressure == 0 and sim.cameraMode ~= ac.CameraMode.Free then
    dragAround = false
    applyPressure = 0
    ac.disableCarRecovery(false)
  end

  if dragAround or applyPressure ~= 0 then
    if workerData.instanceKey == 0 then
      workerData.instanceKey = math.random(1, 1e9)
      physics.startPhysicsWorker('CarDebugWorker', workerData.instanceKey, function(err)
        ac.log('CarDebugWorker stopped', err)
      end)
    end
    workerData.downforce = applyPressure * 1e3 * sim.gravity
    workerData.activeDragLines = 0
    physics.awakeCar(0)
  elseif workerData.instanceKey ~= 0 then
    workerData.instanceKey = 0
  end

  if not dragAround then
    if carRef then
      carRef = nil
      grabActiveLink = nil
      table.clear(grabLinks)
    end
    return
  end

  local car = ac.getCar(0)
  local uis = ac.getUI()
  if not car then return end
  if not carRef then carRef = ac.findNodes('carRoot:0') end

  local ray = render.createMouseRay()
  local toRemove
  lastDragLine = 0
  for i = 1, #grabLinks do
    updateGrabLink(car, grabLinks[i], dt)
    if not grabActiveLink and ray:sphere(grabLinks[i].target, 0.05) ~= -1 then
      grabLinks[i].hovered = true
      if uis.isMouseLeftKeyClicked then
        grabActiveLink = grabLinks[i]
        toRemove = i
      end
    else
      grabLinks[i].hovered = false
    end
  end
  if toRemove then
    table.remove(grabLinks, toRemove)
  end

  if not grabActiveLink and not uis.wantCaptureMouse and #grabLinks < 64 then
    local hitDistance, hitMesh = carRef:raycast(ray, true)
    if hitDistance ~= -1 and hitMesh then
      grabPoint = ray.pos:clone():addScaled(ray.dir, hitDistance)
      if uis.isMouseLeftKeyClicked and not toRemove then
        local wheel = findWheelIndex(hitMesh)
        local posL
        if wheel == -1 then
          posL = car.worldToLocal:transformPoint(grabPoint)
        else
          posL = car.wheels[wheel].transformWheel:inverse():transformPoint(grabPoint)
        end
        grabActiveLink = {
          wheel = wheel,
          posL = posL,
          posW = vec3(),
          target = grabPoint,
          targetDistance = hitDistance,
          force = lastForce,
          hovered = false
        }
        grabPoint = nil
      end
    else
      grabPoint = nil
    end
  end

  if grabActiveLink then
    if not uis.isMouseLeftKeyDown then
      grabActiveLink = nil
      return
    end
    if uis.isMouseRightKeyClicked then
      grabLinks[#grabLinks + 1] = grabActiveLink
      grabActiveLink = nil
    else
      if ac.isKeyDown(ac.KeyIndex.SquareOpenBracket) then
        grabActiveLink.force = math.max(0, grabActiveLink.force - 2e3)
        lastForce = grabActiveLink.force
      end
      if ac.isKeyDown(ac.KeyIndex.SquareCloseBracket) then
        grabActiveLink.force = grabActiveLink.force + 2e3
        lastForce = grabActiveLink.force
      end
      grabActiveLink.target = ray.pos + ray.dir * grabActiveLink.targetDistance
      updateGrabLink(car, grabActiveLink, dt)
    end
  end

  workerData.activeDragLines = lastDragLine
end

local function drawLink(link, active)
  render.setDepthMode(render.DepthMode.Off)
  render.debugLine(link.posW, link.target, rgbm.colors.gray)
  render.setDepthMode(render.DepthMode.ReadOnly)
  render.debugLine(link.posW, link.target, rgbm.colors.black)
  render.setDepthMode(render.DepthMode.Off)
  render.circle(link.posW, sim.cameraPosition - link.posW, 0.05, active and rgbm.colors.lime or rgbm.colors.gray)
  render.circle(link.target, sim.cameraPosition - link.target, 0.05,
    active and rgbm.colors.lime or link.hovered and rgbm.colors.yellow or rgbm.colors.gray)
end

function script.draw3D()
  if not dragAround then return end
  for i = 1, #grabLinks do
    drawLink(grabLinks[i], false)
  end
  if grabActiveLink then
    drawLink(grabActiveLink, true)
  end
  if grabPoint then
    render.circle(grabPoint, sim.cameraPosition - grabPoint, 0.05, rgbm.colors.lime)
  end
end

local TAB_FLAGS = const(ui.TabBarFlags.TabListPopupButton + ui.TabBarFlags.FittingPolicyScroll +
  ui.TabBarFlags.NoTabListScrollingButtons + ui.TabBarFlags.SaveSelected)

function script.windowMain(dt)
  ui.pushFont(ui.Font.Small)

  ui.tabBar('tabs', TAB_FLAGS, function()
    tabItem('Details', controlSceneDetails)
    tabItem('Car', controlCarUtils)
    if sim.carsCount > 1 then
      tabItem('Cars', controlFocus)
    end
    tabItem('Physics', controlPhysicsDebugLines)
    tabItem('Render', controlRender)
    tabItem('Lights', controlLights)
    tabItem('Time', controlTime)
    tabItem('Weather', controlWeather)
    -- tabItem('UI', controlUI)
    -- tabItem('VRAM', controlVRAM)
  end)

  ui.popFont()

  syncState()
end

local cfgVideo = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. '\\video.ini', ac.INIFormat.Default)
local cfgGraphics = ac.INIConfig.load(ac.getFolder(ac.FolderID.Root) .. '\\system\\cfg\\graphics.ini',
  ac.INIFormat.Default)
local cfgProximityIndicator = ac.INIConfig.load(ac.getFolder(ac.FolderID.Root) .. '\\system\\cfg\\proximity_indicator.ini',
  ac.INIFormat.Default)

local function applyChange(section, key, value)
  cfgVideo:setAndSave(section, key, value)
  ac.refreshVideoSettings()
end

local function applyGraphicsChange(section, key, value)
  cfgGraphics:setAndSave(section, key, value)
  ac.refreshVideoSettings()
end

function script.windowSettings(dt)
  ui.pushFont(ui.Font.Small)
  ui.pushItemWidth(ui.availableSpaceX())
  local newValue

  ui.header('View')
  if ui.checkbox('Hide arms', cfgVideo:get('ASSETTOCORSA', 'HIDE_ARMS', false)) then
    applyChange('ASSETTOCORSA', 'HIDE_ARMS', not cfgVideo:get('ASSETTOCORSA', 'HIDE_ARMS', false))
  end
  if ui.checkbox('Hide steering wheel', cfgVideo:get('ASSETTOCORSA', 'HIDE_STEER', false)) then
    applyChange('ASSETTOCORSA', 'HIDE_STEER', not cfgVideo:get('ASSETTOCORSA', 'HIDE_STEER', false))
  end
  if ui.checkbox('Lock steering wheel', cfgVideo:get('ASSETTOCORSA', 'LOCK_STEER', false)) then
    applyChange('ASSETTOCORSA', 'LOCK_STEER', not cfgVideo:get('ASSETTOCORSA', 'LOCK_STEER', false))
  end

  ui.offsetCursorY(12)
  ui.header('Quality')
  newValue = ui.slider('##qwd', cfgVideo:get('ASSETTOCORSA', 'WORLD_DETAIL', 5), 0, 5, 'World detail: %.0f')
  if ui.itemEdited() then
    applyChange('ASSETTOCORSA', 'WORLD_DETAIL', math.round(newValue))
  end

  local shadows = { 0, 32, 64, 128, 256, 512, 1024, 2048, 3072, 4096, 6144, 8192 }
  newValue = table.indexOf(shadows, cfgVideo:get('VIDEO', 'SHADOW_MAP_SIZE', 0)) or 1
  newValue = ui.slider('##qsm', newValue, 1, #shadows,
    string.format('Shadows: %s', newValue == 1 and 'off' or (shadows[newValue] or 0) .. 'x'))
  if ui.itemEdited() then
    applyChange('VIDEO', 'SHADOW_MAP_SIZE', shadows[math.round(newValue)] or 0)
  end

  local levels = { 0, 2, 4, 8, 16 }
  newValue = table.indexOf(levels, cfgVideo:get('VIDEO', 'ANISOTROPIC', 0)) or 1
  newValue = ui.slider('##qan', newValue, 1, #levels,
    string.format('Anisotropic filtering: %s', newValue == 1 and 'off' or (levels[newValue] or 0) .. 'x'))
  if ui.itemEdited() then
    applyChange('VIDEO', 'ANISOTROPIC', levels[math.round(newValue)] or 0)
  end

  if cfgVideo:get('POST_PROCESS', 'ENABLED', true) then
    ui.offsetCursorY(12)
    ui.header('Post-processing')

    newValue = ui.slider('##ppq', cfgVideo:get('POST_PROCESS', 'QUALITY', 1), 0, 5, 'Quality: %.0f')
    if ui.itemEdited() then
      applyChange('POST_PROCESS', 'QUALITY', math.round(newValue))
    end

    newValue = ui.slider('##ppg', cfgVideo:get('POST_PROCESS', 'GLARE', 1), 0, 5, 'Glare: %.0f')
    if ui.itemEdited() then
      applyChange('POST_PROCESS', 'GLARE', math.round(newValue))
    end

    newValue = ui.slider('##ppd', cfgVideo:get('POST_PROCESS', 'DOF', 1), 0, 5, 'DOF: %.0f')
    if ui.itemEdited() then
      applyChange('POST_PROCESS', 'DOF', math.round(newValue))
    end

    if cfgVideo:get('EFFECTS', 'MOTION_BLUR', 0) > 0 and not ac.getSim().isVRConnected then
      newValue = ui.slider('##ppm', cfgVideo:get('EFFECTS', 'MOTION_BLUR', 1), 1, 12, 'Motion blur: %.0f')
      if ui.itemEdited() then
        applyChange('EFFECTS', 'MOTION_BLUR', math.round(newValue))
      end
    end

    if ui.checkbox('Sunrays', cfgVideo:get('POST_PROCESS', 'RAYS_OF_GOD', false)) then
      applyChange('POST_PROCESS', 'RAYS_OF_GOD', not cfgVideo:get('POST_PROCESS', 'RAYS_OF_GOD', false))
    end

    if ui.checkbox('Heat shimmer', cfgVideo:get('POST_PROCESS', 'HEAT_SHIMMER', false)) then
      applyChange('POST_PROCESS', 'HEAT_SHIMMER', not cfgVideo:get('POST_PROCESS', 'HEAT_SHIMMER', false))
    end
  end

  ui.offsetCursorY(12)
  ui.header('Reflections')

  if cfgVideo:get('CUBEMAP', 'FACES_PER_FRAME', 1) > 0 then
    newValue = ui.slider('##cfpf', cfgVideo:get('CUBEMAP', 'FACES_PER_FRAME', 1), 1, 6, 'Faces per frame: %.0f')
    if ui.itemEdited() then
      applyChange('CUBEMAP', 'FACES_PER_FRAME', math.round(newValue))
    end
  end

  newValue = ui.slider('##cfp', cfgVideo:get('CUBEMAP', 'FARPLANE', 1), 100, 2500, 'Rendering distance: %.0f m')
  if ui.itemEdited() then
    applyChange('CUBEMAP', 'FARPLANE', math.round(newValue))
  end

  ui.offsetCursorY(12)
  ui.header('Tweaks')

  newValue = ui.slider('##fps', 1e3 / cfgVideo:get('VIDEO', 'FPS_CAP_MS', 100), 0, 200, 'FPS cap: %.0f')
  if ui.itemEdited() then
    applyChange('VIDEO', 'FPS_CAP_MS', 1e3 / math.round(newValue))
  end

  newValue = ui.slider('##mip', cfgGraphics:get('DX11', 'MIP_LOD_BIAS', 0), -5, 5, 'MIP LOD bias: %.1f')
  if ui.itemEdited() then
    applyGraphicsChange('DX11', 'MIP_LOD_BIAS', newValue)
  end

  if not ac.isModuleActive(ac.CSPModuleID.WeatherFX) then
    newValue = ui.slider('##srg', cfgGraphics:get('DX11', 'SKYBOX_REFLECTION_GAIN', 1) * 100, 0, 200,
      'Skybox gain: %.0f%%')
    if ui.itemEdited() then
      applyGraphicsChange('DX11', 'SKYBOX_REFLECTION_GAIN', newValue / 100)
    end
  end

  newValue = ui.slider('##tsa', cfgVideo:get('SATURATION', 'LEVEL', 100), 0, 200, 'Saturation: %.0f%%')
  if ui.itemEdited() then
    applyChange('SATURATION', 'LEVEL', math.round(newValue))
  end

  ui.offsetCursorY(12)
  ui.header('HUD')
  if ui.checkbox('Proximity indicator', not cfgProximityIndicator:get('SETTINGS', 'HIDE', false)) then
    cfgProximityIndicator:setAndSave('SETTINGS', 'HIDE', not cfgProximityIndicator:get('SETTINGS', 'HIDE', false))
  end

  ui.popItemWidth()
  ui.popFont()
end

ac.onRelease(function()
  ac.setVAOMode(ac.VAODebugMode.Active)
  ac.debugLights('', 0, ac.LightsDebugMode.None, 0)
  ac.setPhysicsDebugLines(ac.PhysicsDebugLines.None)
  debugWeatherControl.weatherType = 255
end)
