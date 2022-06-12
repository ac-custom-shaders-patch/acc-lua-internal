local RailroadSurroundLight = require 'RailroadSurroundLight'
local RailroadUtils = require 'RailroadUtils'
local movable = render.PositioningHelper()
local lastIndex = os.time()

local function nextIndex()
  lastIndex = lastIndex + 1
  return lastIndex
end

---@param prefix string
---@param items table
local function findNextName(prefix, items)
  local nextNumber = 1
  for i = 1, #items do
    if items[i] and items[i].name then
      local n = tonumber(items[i].name:match(prefix..' (%d+)'))
      if n then nextNumber = math.max(nextNumber, n + 1) end
    end
  end
  return prefix..' '..nextNumber
end

local dbgOutcomes = {}
local dbgDraw3D

---@generic T
---@param obj {index: integer}
---@param fn fun(): T
---@return T
function RailroadUtils.tryCreate(obj, fn)
  local ret = try(fn, function (err)
    dbgOutcomes[obj.index] = err
  end)
  if ret then dbgOutcomes[obj.index] = ret.draw3D and function() ret:draw3D() end or true end
  return ret
end

function RailroadUtils.reportError(obj, err)
  if type(err) == 'string' then
    ac.error(err)
  end
  dbgOutcomes[obj.index] = err or true
end

local function drawDebugOutcome(key)
  local dbg = dbgOutcomes[key]
  if dbg then
    if type(dbg) == 'string' then
      local c = ui.getCursor()
      ui.offsetCursor(vec2(8, 8))
      ui.textWrapped('Error: '..dbg)
      ui.offsetCursorY(4)
      ui.drawRect(c, vec2(c.x + ui.availableSpaceX(), ui.getCursorY()), rgbm.colors.red, 3)
      ui.drawRectFilled(c, vec2(c.x + ui.availableSpaceX(), ui.getCursorY()), rgbm(1, 0, 0, 0.1), 3)
    else
      local c = ui.getCursor()
      ui.offsetCursor(vec2(8, 8))
      ui.text(type(dbg) == 'function' and 'Created successfully:' or 'Created successfully')
      if type(dbg) == 'function' then
        ui.sameLine(0, 6)
        ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(0, 0))
        if ui.checkbox('##debug', dbg == dbgDraw3D) then dbgDraw3D = dbg ~= dbgDraw3D and dbg end
        ui.popStyleVar()
        if ui.itemHovered() then ui.setTooltip('Click to see debug outline') end
      end
      ui.offsetCursorY(4)
      ui.drawRect(c, vec2(c.x + ui.availableSpaceX(), ui.getCursorY()), rgbm.colors.green, 3)
      ui.drawRectFilled(c, vec2(c.x + ui.availableSpaceX(), ui.getCursorY()), rgbm(0, 1, 0, 0.1), 3)
    end
  end
end

---@alias TrainCartDescription {model: string, tint: rgb, probability: number, surroundLight: string}
---@param s RailroadEditor
---@return TrainCartDescription
local function newTrainCartDescription(s)
  return {
    model = '',
    tint = rgb(1, 1, 1),
    probability = 1
  }
end

---@alias TrainDescription {index: integer, name: string, mainModel: string, doubleFacedDoors: boolean, head: TrainCartDescription[], carts: TrainCartDescription[], sizeMin: integer, sizeMax: integer, smokeIntensity: number}
---@param s RailroadEditor
---@return TrainDescription
local function newTrainDescription(s)
  return {
    index = nextIndex(),
    name = findNextName('Train', s.data.trains),
    head = {},
    carts = {},
    sizeMin = 8,
    sizeMax = 12,
    headlights = rgb(40, 40, 40),
    smokeIntensity = 0,
  }
end

---@alias SchedulePointDescription {station: integer, time: integer, duration: number}
---@param s RailroadEditor
---@return SchedulePointDescription
local function newSchedulePointDescription(s)
  return {
    station = 0,
    time = 12 * 60 * 60,
    duration = 10 * 60
  }
end

---@alias ScheduleDescription {index: integer, name: string, train: integer, points: SchedulePointDescription[], looped: boolean, variation: number}
---@param s RailroadEditor
---@return ScheduleDescription
local function newScheduleDescription(s)
  return {
    index = nextIndex(),
    name = findNextName('Shedule', s.data.schedules),
    train = -1,
    points = {},
    looped = false,
    variation = 5 * 60
  }
end

---@alias StationDescription {index: integer, name: string, position: vec3}
---@param s RailroadEditor
---@param position vec3
---@return StationDescription
local function newStationDescription(s, position)
  return {
    index = nextIndex(),
    name = findNextName('Station', s.data.stations),
    position = position
  }
end

---@alias GateModelDescription {index: integer, model: string, position: vec3, direction: vec3, up: vec3, physics: boolean}
---@param s RailroadEditor
---@return GateDescription
local function newGateModelDescription(s)
  return {
    index = nextIndex(),
    model = '',
    position = vec3(0, 0, 0),
    direction = vec3(0, 0, 1),
    up = vec3(0, 1, 0),
    physics = true,
  }
end

---@alias GateDescription {index: integer, name: string, position: vec3, colliding: boolean, models: GateModelDescription[]}
---@param s RailroadEditor
---@param position vec3
---@return GateDescription
local function newGateDescription(s, position)
  return {
    index = nextIndex(),
    name = findNextName('Gate', s.data.gates),
    position = position,
    colliding = true,
    models = {}
  }
end

---@alias LineDescription {index: integer, name: string, priority: number, speedMultiplier: number, colliding: boolean, lights: boolean, points: vec3[]}
---@param s RailroadEditor
---@return LineDescription
local function newLineDescription(s)
  return {
    index = nextIndex(),
    name = findNextName('Line', table.chain(s.data.lines, s.editedLine and #s.editedLine.points > 0 and { s.editedLine } or {})),
    priority = 1,
    speedMultiplier = 1,
    points = {}
  }
end

---@param line LineDescription
local function drawLine(line, color)
  for i = 1, #line.points do
    if i > 1 then render.debugLine(line.points[i - 1], line.points[i], color) end
    render.debugCross(line.points[i], 4, color)
  end
  if #line.points > 1 then
    render.debugText((line.points[1] + line.points[2]) / 2, line.name)
  end
end

---@param line LineDescription
---@param ray ray
local function findPointNearby(line, ray)
  return table.findFirst(line.points, function (v, _, ray_) return ray_:sphere(v, 4) ~= -1 end, ray)
end

---@param s RailroadEditor
local function saveChanges(s)
  s.onSave(stringify({
    trains = s.data.trains,
    schedules = s.data.schedules,
    stations = s.data.stations,
    gates = s.data.gates,
    lines = table.chain(s.data.lines, #s.editedLine.points > 1 and {s.editedLine} or {}),
    settings = s.data.settings,
  }, true))
  if s.currentlyMoving ~= nil then
    s.dirty = true
  elseif s.onReload ~= nil then
    s.onReload()
  end
end

---@param s RailroadEditor
---@param list table
---@param index integer
---@param name string
local function cancellableRemove(s, list, index, name)
  if index then
    local removed = table.remove(list, index)
    saveChanges(s)
    ui.toast(ui.Icons.Delete, name..' removed', function ()
      table.insert(list, index, removed)
      saveChanges(s)
    end)
  end
end

---@param self RailroadEditor
local function lineEditor(self)
  for j = 1, #self.data.lines do
    drawLine(self.data.lines[j], rgbm.colors.blue)
  end
  drawLine(self.editedLine, rgbm.colors.cyan)

  for j = 1, #self.data.stations do
    render.debugSphere(self.data.stations[j].position, 2, rgbm.colors.yellow)
    render.debugText(self.data.stations[j].position, self.data.stations[j].name)
  end

  for j = 1, #self.data.gates do
    render.debugSphere(self.data.gates[j].position, 2, rgbm.colors.green)
    render.debugText(self.data.gates[j].position, self.data.gates[j].name)
  end

  -- Inactive if mouse is taken by UI
  if ac.getUI().wantCaptureMouse then return end

  -- Removing last (or first, if selected) element if Delete button is pressed
  if ui.keyPressed(ui.Key.Delete) and #self.editedLine.points > 0 then
    local firstSelected = self.currentlyMoving == self.editedLine.points[1]
    table.remove(self.editedLine.points, firstSelected and 1 or #self.editedLine.points)
    self.currentlyMoving = self.editedLine.points[firstSelected and 1 or #self.editedLine.points]
    saveChanges(self)
  end

  -- Raycasting mouse, checking where it hits track
  local ray = render.createMouseRay()
  local distance = ray:track()
  if distance < 0 then return end
  local hit = ray.pos + ray.dir * distance

  if self.settingAxisTo then
    render.debugCross(self.settingPointTo, 0.5, rgbm.colors.blue)
    local axisPos = self.settingPointTo + self.settingAxisTo
    if movable:render(axisPos) then
      self.settingAxisTo:set((axisPos - self.settingPointTo):normalize())
      saveChanges(self)
    end
    return
  end

  if self.settingPointTo then
    render.debugCross(self.settingPointTo, 0.5, rgbm.colors.blue)
    render.debugCross(hit, 1)
    if ui.mouseReleased() then
      self.settingPointTo:set(hit)
      saveChanges(self)
    end
    return
  end

  -- If Ctrl button is pressed, adding new points, otherwise editing existing points
  if ui.keyboardButtonDown(ui.KeyIndex.Control) then
    if ui.keyboardButtonDown(ui.KeyIndex.Menu) then
      render.debugCross(hit, 4, rgbm(3, 3, 0, 1))
      if ui.mouseClicked() then
        self.currentlyMoving = nil
        for i = 1, #self.data.stations do
          if ray:sphere(self.data.stations[i].position, 2) ~= -1 then
            self.currentlyMoving = self.data.stations[i].position
          end
        end
        if not self.currentlyMoving then
          table.insert(self.data.stations, newStationDescription(self, hit))
        end
        saveChanges(self)
      end
    elseif ui.keyboardButtonDown(ui.KeyIndex.Shift) then
      render.debugCross(hit, 4, rgbm(0, 3, 0, 1))
      if ui.mouseClicked() then
        self.currentlyMoving = nil
        for i = 1, #self.data.gates do
          if ray:sphere(self.data.gates[i].position, 2) ~= -1 then
            self.currentlyMoving = self.data.gates[i].position
          end
        end
        if not self.currentlyMoving then
          table.insert(self.data.gates, newGateDescription(self, hit))
        end
        saveChanges(self)
      end
    else
      local addInFront = #self.editedLine.points > 1 and self.currentlyMoving == self.editedLine.points[1]
      if #self.editedLine.points > 0 then
        render.debugLine(addInFront and self.currentlyMoving or self.editedLine.points[#self.editedLine.points], hit)
      end
      render.debugCross(hit, 4)
      if ui.mouseClicked() then
        self.currentlyMoving = hit
        table.insert(self.editedLine.points, addInFront and 1 or #self.editedLine.points + 1, hit)
        saveChanges(self)
      end
    end
  else
    if ui.mouseReleased() then
      self.currentlyMoving = findPointNearby(self.editedLine, ray)

      -- If there is no point nearby in currently edited line, remove selection of it and checking other lines
      if self.currentlyMoving == nil then
        if #self.editedLine.points > 1 then
          table.insert(self.data.lines, self.editedLine)
          self.editedLine = newLineDescription(self)
        end

        for i = 1, #self.data.lines do
          self.currentlyMoving = findPointNearby(self.data.lines[i], ray)
          if self.currentlyMoving ~= nil then
            self.editedLine = self.data.lines[i]
            table.removeItem(self.data.lines, self.editedLine)
            break
          end
        end
      end

      if self.currentlyMoving == nil and self.dirty then
        self.dirty = false
        if self.onReload ~= nil then self.onReload() end
      end
    elseif self.currentlyMoving and movable:render(self.currentlyMoving, false) then
      self.currentlyMoving:set(hit)
      saveChanges(self)
    end
  end
end

---@alias RailroadData {lines: LineDescription[], stations: StationDescription[], gates: GateDescription[], schedules: ScheduleDescription[], trains: TrainDescription[], settings: table}

---@class RailroadEditor
---@field data RailroadData
---@field editedLine LineDescription
---@field currentlyMoving vec3?
---@field dirty boolean
---@field settingPointTo vec3?
---@field settingAxisTo vec3?
---@field onSave nil|fun(data: string)
---@field onReload nil|fun()
local RailroadEditor = class 'RailroadEditor'

---@param data string
---@param onSave nil|fun(data: string)
---@return RailroadEditor
function RailroadEditor.allocate(data, onSave)
  return {
    data = table.chain({ trains = {}, schedules = {}, stations = {}, gates = {}, lines = {}, settings = {} }, stringify.tryParse(data, nil, {})),
    editedLine = nil,
    currentlyMoving = nil,
    dirty = false,
    onSave = onSave
  }
end

function RailroadEditor:initialize()
  self.editedLine = newLineDescription(self)
end

---@param self RailroadEditor
---@param dt number
local function drawUILines(self, dt)
  local lines = table.chain(self.data.lines, #self.editedLine.points > 1 and { self.editedLine } or {})
  table.sort(lines, function (a, b) return a.index < b.index end)

  local toRemove
  for i = 1, #lines do
    ui.offsetCursorY(12)
    local line = lines[i]
    ui.pushID(line.index)
    ui.text('Line #'..i)
    ui.beginSubgroup()

    line.name = ui.inputText('##name', line.name)

    line.priority = ui.slider('##priority', (line.priority or 1) * 100, 0, 300, 'Priority: %.0f%%') / 100
    if ui.itemHovered() then
      ui.setTooltip('Reduce to increase changes of lane to be used (acts as distance multiplier when finding a shortest route)')
    end

    line.speedMultiplier = ui.slider('##speedMultiplier', (line.speedMultiplier or 1) * 100, 0, 300, 'Speed multiplier: %.0f%%') / 100
    if ui.itemHovered() then
      ui.setTooltip('Speed multiplier (not an actual limit: actual speed is controlled by schedule, making sure trains arrive on time)')
    end

    if ui.checkbox('Force colliding trains', line.colliding) then
      line.colliding = not line.colliding
      saveChanges(self)
    end
    if ui.itemHovered() then
      ui.setTooltip('If active, train on this lane would always get colliders (use it if lane can be reached by a car; if it’s an intersection, gates can enable colliders only when trains are near them)')
    end

    if ui.checkbox('Force lights', line.lights) then
      line.lights = not line.lights
      saveChanges(self)
    end
    if ui.itemHovered() then
      ui.setTooltip('If active, train on this lane will have its lights active')
    end

    if table.contains(self.data.lines, line) and ui.button('Remove lane') then toRemove = i end
    ui.endSubgroup()
    if ui.itemEdited() then saveChanges(self) end
    ui.popID()
  end

  cancellableRemove(self, self.data.lines, toRemove, 'Lane')
  ui.offsetCursorY(12)
  ui.textWrapped('To start creating new line, hold Ctrl and click on a track.')
end

local knownSurroundLightList = table.map(RailroadSurroundLight.known(), function (item, key) return { key = key, name = item.name } end)
table.sort(knownSurroundLightList, function (a, b) return a.name < b.name end)

---@param self RailroadEditor
---@param list TrainCartDescription[]
local function cartsEditor(self, list)
  if #list == 0 then
    ui.text('<Empty>')
  else
    local toRemove
    for i = 1, #list do
      ui.pushID(i)
      ui.setNextItemWidth(ui.availableSpaceX() - 84)
      list[i].model = ui.inputText('KN5 LOD A', list[i].model, ui.InputTextFlags.Placeholder)
      if ui.itemHovered() then
        ui.setTooltip('Save LOD B next to LOD A with “_b” postfix')
      end
      ui.sameLine(0, 4)
      if ui.button('Remove', vec2(80, 0)) then
        toRemove = i
      end
      ui.setNextItemWidth(ui.availableSpaceX() - 24)
      list[i].probability = ui.slider('##probability', list[i].probability * 100, 0, 100, 'Probability: %.0f%%') / 100
      ui.sameLine(0, 4)
      ui.colorButton('##color', list[i].tint, ui.ColorPickerFlags.PickerHueBar)
      
      ui.alignTextToFramePadding()
      ui.text('Surround light:')
      ui.sameLine(100)
      ui.setNextItemWidth(ui.availableSpaceX())
      local selected = RailroadSurroundLight.known()[list[i].surroundLight]
      ui.combo('##surround', selected and selected.name or '<None>', function ()
        if ui.selectable('None', not selected) then
          list[i].surroundLight = nil
          saveChanges(self)
        end
        for _, v in ipairs(knownSurroundLightList) do
          if ui.selectable(v.name, v.key == list[i].surroundLight) then
            list[i].surroundLight = v.key
            saveChanges(self)
          end
        end
      end)

      ui.popID()
    end
    if toRemove then
      cancellableRemove(self, list, toRemove, 'Item')
    end
  end
  if ui.button('New item') then
    table.insert(list, newTrainCartDescription(self))
    saveChanges(self)
  end
end

---@param self RailroadEditor
---@param dt number
local function drawUIStations(self, dt)
  local toRemove
  for i = 1, #self.data.stations do
    ui.offsetCursorY(12)
    local station = self.data.stations[i]
    ui.pushID(i)
    ui.text('Station #'..i)
    ui.beginSubgroup()
    station.name = ui.inputText('Name', station.name, ui.InputTextFlags.Placeholder)
    if ui.button('Remove station') then toRemove = i end
    ui.endSubgroup()
    if ui.itemEdited() then saveChanges(self) end
    ui.popID()
  end
  cancellableRemove(self, self.data.stations, toRemove, 'Station')

  ui.offsetCursorY(12)
  ui.textWrapped('To create a station, hold Ctrl+Alt and click at the place where a train head should get parked. To move created station, click on it while holding Ctrl+Alt and then move it.')
end

---@param self RailroadEditor
---@param list GateModelDescription[]
---@param gate GateDescription
local function gateMeshesEditor(self, list, gate)
  if #list == 0 then
    ui.text('<Empty>')
  else
    local toRemove
    for i = 1, #list do
      ui.pushID(i)
      ui.setNextItemWidth(ui.availableSpaceX() - 84)
      list[i].model = ui.inputText('Model', list[i].model, ui.InputTextFlags.Placeholder)
      ui.sameLine(0, 4)
      if ui.button('Remove', vec2(80, 0)) then
        toRemove = i
      end

      if ui.checkbox('With physics objects', list[i].physics) then
        list[i].physics = not list[i].physics
        saveChanges(self)
      end
      if ui.itemHovered() then
        ui.setTooltip('If active, objects with certain names will use physics (disable for distant gates not reachable by cars but still using the same model)')
      end

      ui.popID()
    end
    if toRemove then
      cancellableRemove(self, list, toRemove, 'Gate mesh')
    end
  end
  if ui.button('New gate mesh') then
    table.insert(list, newGateModelDescription(self))
    list[#list].position = gate.position
    saveChanges(self)
  end
end

---@param self RailroadEditor
---@param dt number
local function drawUIGates(self, dt)
  local toRemove
  for i = 1, #self.data.gates do
    ui.offsetCursorY(12)
    local gate = self.data.gates[i]
    ui.pushID(i)
    ui.text('Gate #'..i)
    ui.beginSubgroup()
    gate.name = ui.inputText('Name', gate.name, ui.InputTextFlags.Placeholder)

    if ui.checkbox('Colliding', gate.colliding) then
      gate.colliding = not gate.colliding
      saveChanges(self)
    end
    if ui.itemHovered() then
      ui.setTooltip('If active, train would get physics collider when getting near the gate, enabling collisions with cars')
    end

    ui.text('Models:')
    ui.beginSubgroup()
    gateMeshesEditor(self, gate.models, gate)
    ui.endSubgroup()

    if ui.button('Remove gate') then toRemove = i end
    drawDebugOutcome(gate.index)
    ui.endSubgroup()
    if ui.itemEdited() then saveChanges(self) end
    ui.popID()
  end
  cancellableRemove(self, self.data.gates, toRemove, 'Gate')

  ui.offsetCursorY(12)
  ui.textWrapped('To create a gate, hold Ctrl+Shift and click at the place where the road intersects a track or a bunch of tracks.  To move created gate, click on it while holding Ctrl+Shift and then move it.')
end

local editingRoot ---@type ac.SceneReference
local editingPool = {}

---@param self RailroadEditor
local function draw3DGates(self)
  if not editingRoot then
    editingRoot = ac.findNodes('$$$rw.editing')
    if #editingRoot == 0 then editingRoot = ac.findNodes('carsRoot:yes'):createBoundingSphereNode('$$$rw.editing', 1e6) end
  end

  local now = ac.getSim().timeToSessionStart
  for i = 1, #self.data.gates do
    local gate = self.data.gates[i]
    for j = 1, #gate.models do
      local m = gate.models[j]
      local r = table.getOrCreate(editingPool, m.index..':'..m.model, function ()
        return {kn5 = editingRoot:loadKN5(m.model), lastUsed = 0}
      end)
      r.lastUsed = now
      if r.kn5 then
        r.kn5:setPosition(m.position)
        r.kn5:setOrientation(m.direction, m.up)
        if movable:renderFullyAligned(m.position, m.direction, m.up) then
          saveChanges(self)
        end
      end
    end
  end

  local toRemove = {}
  for k, v in pairs(editingPool) do
    if v.lastUsed ~= now then
      if v.kn5 then v.kn5:dispose() end
      table.insert(toRemove, k)
    end
  end
  for i = 1, #toRemove do
    editingPool[toRemove[i]] = nil
  end
end

---@param self RailroadEditor
---@param dt number
local function drawUITrains(self, dt)
  local toRemove, toClone
  for i = 1, #self.data.trains do
    ui.offsetCursorY(12)
    local train = self.data.trains[i]
    ui.pushID(i)
    ui.text('Train #'..i)
    ui.beginSubgroup()

    train.name = ui.inputText('Name', train.name, ui.InputTextFlags.Placeholder)

    ui.text('Head:')
    ui.beginSubgroup()
    ui.pushID('head')
    cartsEditor(self, train.head)
    ui.popID()
    ui.endSubgroup()

    ui.text('Carts:')
    ui.beginSubgroup()
    ui.pushID('carts')
    cartsEditor(self, train.carts)
    ui.popID()
    ui.endSubgroup()

    ui.text('Size:')
    ui.offsetCursorX(20)
    ui.setNextItemWidth(ui.availableSpaceX() / 2 - 4)
    train.sizeMin = math.floor(ui.slider('##from', train.sizeMin, 0, 200, 'From: %.0f', 2))
    ui.sameLine(0, 4)
    ui.setNextItemWidth(ui.availableSpaceX())
    train.sizeMax = math.floor(ui.slider('##to', train.sizeMax, 0, 200, 'To: %.0f', 2))

    ui.text('Visual:')
    ui.beginSubgroup(20)

    ui.alignTextToFramePadding()
    ui.text('Main model:')
    ui.sameLine(100)
    train.mainModel = ui.inputText('Main model', train.mainModel, ui.InputTextFlags.Placeholder)
    if ui.itemHovered() then
      ui.setTooltip('If all of your train models share the same textures, point to KN5 saved as car (with all of them) here and use save other models as car LODs')
    end

    if ui.checkbox('Double-faced doors', train.doubleFacedDoors) then
      train.doubleFacedDoors = not train.doubleFacedDoors
      saveChanges(self)
    end

    ui.alignTextToFramePadding()
    ui.text('Smoke intensity:')
    ui.sameLine(100)
    ui.setNextItemWidth(ui.availableSpaceX())
    train.smokeIntensity = ui.slider('##smoke', train.smokeIntensity * 100, 0, 100, '%.0f%%') / 100
    ui.endSubgroup()

    if ui.button('Remove train') then toRemove = i end
    ui.sameLine(0, 4)
    if ui.button('Clone train') then toClone = i end
    drawDebugOutcome(train.index)
    ui.endSubgroup()
    if ui.itemEdited() then saveChanges(self) end
    ui.popID()
  end
  
  cancellableRemove(self, self.data.trains, toRemove, 'Train')
  if toClone then
    table.insert(self.data.trains, stringify.parse(stringify(self.data.trains[toClone])))
    saveChanges(self)
  end

  ui.offsetCursorY(12)
  if ui.button('New train') then
    table.insert(self.data.trains, newTrainDescription(self))
    saveChanges(self)
  end
end

---@param self RailroadEditor
---@param list SchedulePointDescription[]
local function schedulePointsEditor(self, list)
  if #list == 0 then
    ui.text('<Empty>')
  else
    local moveItem
    for i = 1, #list do
      ui.pushID(i)

      local currentStation = table.findByProperty(self.data.stations, 'index', list[i].station)
      ui.setNextItemWidth(ui.availableSpaceX() / 3 - 8)
      ui.combo('##station', currentStation and currentStation.name or 'No station selected', function ()
        for _, t in ipairs(self.data.stations) do
          if ui.selectable(t.name, t == currentStation) then
            list[i].station = t.index
            saveChanges(self)
          end
        end
      end)

      ui.sameLine(0, 4)
      ui.setNextItemWidth(ui.availableSpaceX() / 2 - 4)
      list[i].duration = ui.slider('##stayFor', (list[i].duration or (10 * 60)) / 60, 0, 60, 'Duration: %.0f min') * 60

      local time = string.format('%02d:%02d', math.floor(list[i].time / 3600), math.floor(list[i].time / 60 % 60))
      ui.sameLine(0, 4)
      ui.setNextItemWidth(ui.availableSpaceX() - 24 * 3)
      time = ui.inputText('Time', time, ui.InputTextFlags.Placeholder)
      if ui.itemEdited() then
        local p = time:split(':')
        local th = tonumber(p[1])
        local tm = tonumber(p[2])
        local ts = tonumber(p[3]) or 0
        if th and tm then
          list[i].time = th * 3600 + tm * 60 + ts
        end
      end

      ui.pushStyleVar(ui.StyleVar.FramePadding, vec2())
      ui.sameLine(0, 4)
      if ui.button('↑', vec2(20, 20), i == 1 and ui.ButtonFlags.Disabled) and i > 1 then moveItem = {i, i - 1, list[i]} end
      ui.sameLine(0, 4)
      if ui.button('↓', vec2(20, 20), i == #list and ui.ButtonFlags.Disabled) and i < #list then moveItem = {i, i + 1, list[i]} end
      ui.sameLine(0, 4)
      if ui.button('×', vec2(20, 20)) then moveItem = {i} end
      ui.popStyleVar()

      ui.popID()
    end
    if moveItem then
      table.remove(list, moveItem[1])
      if moveItem[2] then table.insert(list, moveItem[2], moveItem[3]) end
      saveChanges(self)
    end
  end
  if ui.button('New item') then
    table.insert(list, newSchedulePointDescription(self))
    saveChanges(self)
  end
end

---@param self RailroadEditor
---@param dt number
local function drawUISchedules(self, dt)
  local toRemove
  for i = 1, #self.data.schedules do
    ui.offsetCursorY(12)
    local schedule = self.data.schedules[i]
    ui.pushID(i)
    ui.text('Schedule #'..i)

    ui.beginSubgroup()
    schedule.name = ui.inputText('Name', schedule.name, ui.InputTextFlags.Placeholder)

    local currentTrain = table.findByProperty(self.data.trains, 'index', schedule.train)
    ui.combo('##train', currentTrain and 'Train: '..currentTrain.name or 'No train selected', function ()
      for _, t in ipairs(self.data.trains) do
        if ui.selectable(t.name, t == currentTrain) then
          schedule.train = t.index
          saveChanges(self)
        end
      end
    end)

    ui.text('Stations:')
    ui.beginSubgroup()
    schedulePointsEditor(self, schedule.points)
    ui.endSubgroup()

    if ui.checkbox('Loop route', schedule.looped) then
      schedule.looped = not schedule.looped
      saveChanges(self)
    end

    schedule.variation = ui.slider('##variation', schedule.variation / 60, 0, 15, 'Variation: %.0f min') * 60
    if ui.itemHovered() then
      ui.setTooltip('Randomized offset for schedule, to keep things from seeming too even (varies with different train runs)')
    end
    
    if ui.button('Remove schedule') then toRemove = i end
    drawDebugOutcome(schedule.index)

    ui.endSubgroup()
    if ui.itemEdited() then saveChanges(self) end
    ui.popID()
  end

  cancellableRemove(self, self.data.schedules, toRemove, 'Schedule')
  ui.offsetCursorY(12)
  if ui.button('New schedule') then
    table.insert(self.data.schedules, newScheduleDescription(self))
    saveChanges(self)
  end
end

---@param self RailroadEditor
---@param dt number
local function drawUISettings(self, dt)
  local settings = self.data.settings

  ui.beginGroup()

  ui.header('Lines:')
  ui.alignTextToFramePadding()
  ui.text('Surface meshes:')
  ui.sameLine(120)
  settings.surfaceMeshes = ui.inputText('Complex mesh filter, such as “GRASS_?” or “( GROUND_? | material:dirt ) & static:yes”##surfaceMeshes', self.data.settings.surfaceMeshes, ui.InputTextFlags.Placeholder)
  if ui.itemHovered() then
    ui.setTooltip('If set, trains will align themselves over those meshes, so they could tilt in corners. Meshes don’t have to be visible or renderable.')
  end

  ui.offsetCursorY(12)
  ui.header('Gates:')
  ui.alignTextToFramePadding()
  ui.text('Activate colliders for:')
  ui.sameLine(120)
  settings.gateColliderActiveDistance = ui.slider('#gateColliderActiveDistance', self.data.settings.gateColliderActiveDistance or 200, 20, 500, '%.0f m')
  if ui.itemHovered() then
    ui.setTooltip('Train carts get collider when closer that this to gates that activate colliders.')
  end

  ui.alignTextToFramePadding()
  ui.text('Closing distance:')
  ui.sameLine(120)
  settings.gateCloseDistance = ui.slider('#gateCloseDistance', self.data.settings.gateCloseDistance or 200, 20, 500, '%.0f m')
  if ui.itemHovered() then
    ui.setTooltip('Gates will close when a train would get closer than this distance.')
  end

  ui.alignTextToFramePadding()
  ui.text('Opening distance:')
  ui.sameLine(120)
  settings.gateOpenDistance = ui.slider('#gateOpenDistance', self.data.settings.gateOpenDistance or 50, 20, 500, '%.0f m')
  if ui.itemHovered() then
    ui.setTooltip('Gates will open when a train would get further than this distance.')
  end

  ui.endGroup()
  if ui.itemEdited() then
    saveChanges(self)
  end
end

local tabs = {
  { 'Lines', drawUILines },
  { 'Stations', drawUIStations },
  { 'Gates', drawUIGates, draw3DGates },
  { 'Trains', drawUITrains, false, function (s) return table.some(s.data.trains, function (i) return type(dbgOutcomes[i.index]) == 'string' end) end },
  { 'Schedules', drawUISchedules, false, function (s) return table.some(s.data.schedules, function (i) return type(dbgOutcomes[i.index]) == 'string' end) end  },
  { 'Settings', drawUISettings },
}

local activeTab

function RailroadEditor:drawUI(dt)
  activeTab = nil
  ui.pushFont(ui.Font.Small)
  ui.tabBar('tabs', function ()
    for _, v in ipairs(tabs) do
      ui.tabItem(v[1], v[4] and v[4](self) and ui.TabItemFlags.UnsavedDocument, function ()
        activeTab = v
        ui.childWindow('#scroll', ui.availableSpace(), function ()
          ui.pushItemWidth(ui.availableSpaceX())
          v[2](self, dt)
          ui.popItemWidth()
        end)
      end)
    end
    if _G['debugUI'] then
      ui.tabItem('Debug', function ()
        ui.childWindow('#scroll', ui.availableSpace(), function ()
          ui.pushItemWidth(ui.availableSpaceX())
          _G['debugUI']()
          ui.popItemWidth()
        end)
      end)
    end
  end)
  ui.popFont()
end

function RailroadEditor:draw3D(dt)
  if activeTab and activeTab[3] and (not ui.keyboardButtonDown(ui.KeyIndex.Control) or not ui.keyboardButtonDown(ui.KeyIndex.Shift)) then
    activeTab[3](self, dt)
  else
    lineEditor(self)
    if _G['debug3D'] then
      _G['debug3D']()
    end
    if dbgDraw3D then
      dbgDraw3D()
    end
  end
end

function RailroadEditor:isBusy()
  return activeTab and not not activeTab[3]
end

return class.emmy(RailroadEditor, RailroadEditor.allocate)

