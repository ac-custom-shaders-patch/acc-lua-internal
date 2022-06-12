math.randomseed(1)
jit.flush()
ac.setLogSilent(true)

local json = require('lib/json')
local genericUtils = require('src/generic_utils')
local dataFilename = ac.getTrackDataFilename('traffic.json')

function ErrorPos(msg, pos)
  DebugShapes[msg] = pos
  error(msg)
end

-- Common module
package.add('src/common')

-- Editor module
package.add('src/editor')
local EditorMain = require('EditorMain')

local function loadData()
  -- return require('src/grid_generator')()
  return json.decode(io.load(dataFilename, '{}'))
end

---@type EditorMain
-- local editor = EditorMain(require('src/grid_generator')())
local editor = EditorMain(loadData())

-- Simulation module
package.add('src/simulation')
local TrafficSimulation = require('TrafficSimulation')
local TrafficConfig = require('TrafficConfig')
local TrafficDebugLayers = require('TrafficDebugLayers')

local simSettings = ac.storage{
  simulationSpeed = 1,
  clickToDelete = false,
  profileGC = false,
  debugLines = false,
  debugLayers = 'null',
  debugBehaviour = false,
  debugSpawnAround = false,
  carsNumber = 200
}

local simTraffic, simBroken = nil, false
local simDebugLayers = TrafficDebugLayers(json.decode(simSettings.debugLayers))

local function syncTrafficConfig()
  TrafficConfig.debugBehaviour = simSettings.debugBehaviour
  TrafficConfig.debugSpawnAround = simSettings.debugSpawnAround
  TrafficConfig.driversCount = simSettings.carsNumber
end

local function trafficRefresh()
  if simTraffic ~= nil then simTraffic:dispose() end
  simTraffic, simBroken = nil, false
end

local text = 'hello world'

local function trafficTab()
  ui.header('Simulation speed')
  ui.pushFont(ui.Font.Small)

  local speed = refnumber(simSettings.simulationSpeed > 1 and 1 + (simSettings.simulationSpeed - 1) / 30 or simSettings.simulationSpeed)
  if ui.slider('##simulationSpeed', speed, 0, 2, string.format('Speed: %.1f', simSettings.simulationSpeed)) then
    simSettings.simulationSpeed = speed.value > 1 and 1 + (speed.value - 1) * 30 or speed.value
  end

  if ui.button('Restart') then
    math.randomseed(ui.mousePos().x + 2000 * ui.mousePos().y)
    trafficRefresh()
  end

  ui.sameLine()
  if ui.button('Reset speed') then
    simSettings.simulationSpeed = 1
  end

  ui.separator()

  if ui.checkbox('Profile GC', simSettings.profileGC) then
    simSettings.profileGC = not simSettings.profileGC
  end

  if ui.checkbox('Click to delete cars', simSettings.clickToDelete) then
    simSettings.clickToDelete = not simSettings.clickToDelete
  end

  if ui.checkbox('Debug cars behaviour', simSettings.debugBehaviour) then
    simSettings.debugBehaviour = not simSettings.debugBehaviour
    trafficRefresh()
  end

  if ui.checkbox('Spawn cars nearby only', simSettings.debugSpawnAround) then
    simSettings.debugSpawnAround = not simSettings.debugSpawnAround
    trafficRefresh()
  end

  local newNumber, changed = ui.slider('##carsNumber', simSettings.carsNumber, 1, 2000, 'Cars: %.0f', 2)
  if changed then
    simSettings.carsNumber = newNumber
    setTimeout(trafficRefresh, 0.01, 'refresh')
  end

  ui.separator()

  if ui.checkbox('Show debug lanes', simSettings.debugLines) then
    simSettings.debugLines = not simSettings.debugLines
  end

  local function debugLayer(layer)
    ui.offsetCursorX(layer.level * 8)
    if ui.checkbox(layer.name, layer.active) then
      layer.active = not layer.active
      simSettings.debugLayers = json.encode(simDebugLayers:serialize())
    end
    if layer.active then
      ui.pushID(layer.name)
      table.forEach(layer.children, debugLayer)
      ui.popID()
    end
  end

  if simSettings.debugLines then
    table.forEach(simDebugLayers.root.children, debugLayer)
  end

  -- deg = (deg or 0) + ac.getDeltaT() * 100
  -- ui.beginRotation()
  -- ui.pushDWriteFont('License Plate:./data')
  -- ui.dwriteText('Hello world!', ((50 + 20 * math.sin(deg * 0.01)) * 3) / 3, rgbm.colors.white)
  -- ui.popDWriteFont()
  -- ui.endRotation(deg)
  -- local c = vec2(180, 320)
  -- local s = vec2(200, 140)
  -- ui.drawRect(c, c + s, rgbm.colors.red)
  -- ui.setCursor(c)
  -- ui.pushDWriteFont('Segoe UI')
  -- ui.dwriteTextAligned('Test', 60, ui.Alignment.Center, ui.Alignment.Center, s, false, rgbm(1, 1, 0.1, 1))
  -- ui.popDWriteFont()
  -- ui.text('Begin testing')
  -- ui.pushDWriteFont('License Plate:'.. __dirname .. '/data/license_plate.ttf')
  -- ui.dwriteText('Hello world!', 30, rgbm.colors.white)
  -- ui.popDWriteFont()
  -- ui.text('test')
  -- ui.pushDWriteFont('Segoe UI')
  -- ui.dwriteText('Hello world!', 15, rgbm.colors.white)
  -- ui.popDWriteFont()
  -- ui.pushDWriteFont('Segoe UI')
  -- ui.dwriteText('Hello world! This is a very very long bit of text', 35, rgbm.colors.white)
  -- ui.popDWriteFont()
  -- ui.pushDWriteFont('Segoe UI')
  -- ui.dwriteTextWrapped('Hello world! This is a very very long bit of text', 35, rgbm.colors.white)
  -- ui.popDWriteFont()
  -- ui.pushDWriteFont('License Plate:data/license_plate.ttf')
  -- ui.dwriteText('Hello world!', 15, rgbm.colors.white)
  -- ui.popDWriteFont()
  -- ui.text('Good old regular text a lot of it a lot of it a lot of it a lot of it a lot of it a lot of it a lot of it')
  -- local MyFavouriteFont = ui.DWriteFont('License Plate', './data')
  --   :weight(ui.DWriteFont.Weight.Bold)
  --   :style(ui.DWriteFont.Style.Normal)
  --   :stretch(ui.DWriteFont.Stretch.UltraExpanded)
  -- ac.debug('MyFavouriteFont', MyFavouriteFont)  
  -- ui.pushDWriteFont(MyFavouriteFont)  -- you could also just put font here, but if defined once and reused, it would generate less garbage for GC to clean up.
  -- ui.dwriteText('Hey there', 24, rgbm.colors.white)
  -- ui.popDWriteFont()

  if simBroken then
    local errorMsg = 'Sim has crashed'
    local solutionData = nil
    if ac.getLastError():match('Not allowed') then
      errorMsg = 'Can’t run: scripting physics is not allowed. Add in “surfaces.ini”:'
      solutionData = '[SURFACE_0]\
WAV_PITCH=extended-0\
\
[_SCRIPTING_PHYSICS]\
ALLOW_TRACK_SCRIPTS=1\
ALLOW_DISPLAY_SCRIPTS=1\
ALLOW_NEW_MODE_SCRIPTS=1\
ALLOW_TOOLS=1'
    end

    ui.setCursor(vec2(28, 60))
    ui.pushStyleVar(ui.StyleVar.ChildRounding, 8)
    ui.pushStyleColor(ui.StyleColor.ChildBg, rgbm(0.5, 0, 0, 1))
    ui.childWindow('simErrorMsg', vec2(0, solutionData and 148 or 48), false, 0, function ()
      ui.offsetCursor(8)
      ui.text(errorMsg)
      if solutionData ~= nil then
        ui.offsetCursorX(8)
        ui.copyable(solutionData)
      end
      ui.offsetCursorX(8)
      if ui.button('Restart') then
        simSettings.simulationSpeed = 1
        trafficRefresh()
      end
      ui.sameLine()
      if ui.button('Resume') then
        simBroken = false
      end
    end)
    ui.popStyleColor()
    ui.popStyleVar()
  end

  ui.popFont()
end

local simulationTabName = 'Simulation'
editor.tabs:insert(1, { name = simulationTabName, fn = trafficTab })

-- Tool script
-- function script.asyncUpdate()
--   if not simSettings.profileGC then
--     collectgarbage()
--   end
-- end

local sim = ac.getSim()

function script.simUpdate(dt)
  if true then
    -- require('src/test/distance_between_cars')()
    -- require('src/test/perf_enum')()
    -- require('src/test/test_class')()
    -- require('src/test/test_dynamic_texture')()
    -- return
  end

  if sim.isReplayActive or sim.dt == 0 or sim.isOnlineRace then
    -- Paused or in replay
    return
  end

  if simSettings.simulationSpeed == 0 or simBroken then
    return
  end

  if not editor:isEmpty() and simTraffic == nil then
    simBroken = true
    syncTrafficConfig()
    -- simTraffic = TrafficSimulation(editor:serializeData())
    simTraffic = TrafficSimulation(editor:finalizeData())
    simBroken = false
  end

  if simSettings.profileGC then
    collectgarbage()
  end

  if sim.focusedCar ~= -1 then
    local car = ac.getCar(sim.focusedCar)
    if car ~= nil and not car.extrapolatedMovement then
      -- Hacky fix. Let’s hope we’ll be able to use extrapolated movement soon.
      dt = dt + (sim.time - ac.getCar(sim.focusedCar).timestamp) / 1e3
      dt = math.max(dt, 0.002)
    end
  end

  if simTraffic ~= nil and not simBroken then
    simBroken = true
    for _ = 1, math.ceil(simSettings.simulationSpeed) do
      simTraffic:update(math.saturateN(simSettings.simulationSpeed) * dt)
    end
    simBroken = false
  end

  if simSettings.profileGC then
    genericUtils.runGC()
  end
end

function script.update(dt)
  editor:doUI(dt)
end

-- function update(dt)
--   editor:doUI(dt)
-- end

-- For easier debugging
DebugShapes = {}

function script.draw3D()
  if script.draw3DOverride then
    script.draw3DOverride()
  end

  if simTraffic then
    simTraffic:drawMain()
  end

  if editor.activeTab ~= simulationTabName then
    render.setDepthMode(render.DepthMode.Off)
    pcall(function() editor:draw3D() end)
  elseif simTraffic ~= nil and simSettings.debugLines then
    simDebugLayers:start()
    simTraffic:draw3D(simDebugLayers, simSettings.clickToDelete)

    table.forEach(DebugShapes, function (item, key)
      ac.debug(key, item)
      render.debugCross(item, 2, rgbm(3, 0, 0, 1))
      render.debugText(item, key, rgbm(3, 0, 0, 1))
    end)
  end

end

-- Updating simulation and saving on change
local refreshTimeout = nil
editor.onChange:subscribe(function ()
  setTimeout(function ()
    io.save(dataFilename, json.encode(editor:serializeData()))
  end, 3, 'save')

  clearTimeout(refreshTimeout)
  refreshTimeout = setTimeout(function ()
    trafficRefresh()
  end, 0.5)
end)

-- setInterval(function ()
--   trafficRefresh()
-- end, 0.3)

-- ac.debug('cfg', ac.getTrackConfig().number('CONDITION_1', 'DELAY', 0))

-- local v = ac.getTrackConfig('CONDITION_1', 'DELAY', 0)
-- ac.debug('cfg2', ac.getTrackConfig('CONDITION_1', 'DELAY', 0))
