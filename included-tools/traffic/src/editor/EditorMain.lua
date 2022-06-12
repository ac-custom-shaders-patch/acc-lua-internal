local EditorLane = require('EditorLane')
local EditorIntersection = require('EditorIntersection')
local EditorArea = require('EditorArea')
local Array = require('Array')
local Event = require('Event')
local EditorTabLanes = require('EditorTabLanes')
local EditorTabIntersections = require('EditorTabIntersections')
local EditorTabAreas = require('EditorTabAreas')
local EditorTabRules = require('EditorTabRules')
local EditorColors = require('EditorColors')

local sim = ac.getSim()
local uio = ac.getUI()
local storedSubUICommand = ac.storage{ command = '' }

local function ensureIDUnique(list)
  local t = {}
  for i = 1, #list do
    local e = list[i]
    while t[e.id] do e.id = e.id + 1 end
    t[e.id] = true
  end
end

---@class EditorMain
---@field lanesList EditorLane[]
---@field intersectionsList EditorIntersection[]
---@field areasList EditorArea[]
---@field selectedLane EditorLane
---@field selectedIntersection EditorIntersection
---@field selectedArea EditorArea
---@field rules SerializedRules
local EditorMain = class("EditorMain")

---@param data SerializedData
---@return EditorMain
function EditorMain:initialize(data)
  self.lanesList = data and data.lanes and Array(data.lanes, EditorLane) or Array()
  self.intersectionsList = data and data.intersections and Array(data.intersections, EditorIntersection) or Array()
  self.areasList = data and data.areas and Array(data.areas, EditorArea) or Array()

  self.tabLanes = EditorTabLanes(self)
  self.tabIntersections = EditorTabIntersections(self)
  self.tabAreas = EditorTabAreas(self)
  self.tabRules = EditorTabRules(self)

  self.onUI = Event()
  self.onDraw3D = Event()
  self.onChange = Event()

  self.tabs = Array()
  self.tabs:push({ name = 'Lanes', fn = function () self.tabLanes:doUI() end })
  self.tabs:push({ name = 'Intersections', fn = function () self.tabIntersections:doUI() end })
  self.tabs:push({ name = 'Areas', fn = function () self.tabAreas:doUI() end })
  self.tabs:push({ name = 'Rules', fn = function () self.tabRules:doUI() end })

  self.currentlyMovingPoint = nil
  self.currentlyMovingItem = nil

  self.mousePoint = nil
  self.movableHelper = render.PositioningHelper()

  self.creatingNewLane = nil
  self.selectedLane = nil
  self.highlightedPointIndex = -1

  self.creatingNewIntersection = nil
  self.selectedIntersection = nil

  self.creatingNewArea = nil
  self.selectedArea = nil

  self.rules = data.rules or {
    laneRoles = {
      { name = 'Parking', priority = -8, speedLimit = 40 },
      { name = 'Secondary', priority = -4, speedLimit = 60 },
      { name = 'Main', priority = 0, speedLimit = 80 },
      { name = 'Highway', priority = 4, speedLimit = 90 },
    },
  }

  if storedSubUICommand.command ~= '' then
    local restoreCommand = string.format('return function (self) return %s end', storedSubUICommand.command)
    try(function()
      self:subUI(loadstring(restoreCommand)()(self), storedSubUICommand.command)
    end, function (err)
      ac.debug('Restore error', err)
      ac.debug('Restore command', restoreCommand)
    end)
  end
end

---@return SerializedData
function EditorMain:serializeData()
  return {
    lanes = self.lanesList:map(EditorLane.encode, nil, {}),
    intersections = self.intersectionsList:map(EditorIntersection.encode, nil, {}),
    areas = self.areasList:map(EditorArea.encode, nil, {}),
    rules = self.rules
  }
end

---@return SerializedData
function EditorMain:finalizeData()
  return {
    lanes = self.lanesList:map(function (item) return item:finalize(self) end, nil, {}),
    intersections = self.intersectionsList:map(function (item) return item:finalize(self) end, nil, {}),
    areas = self.areasList:map(function (item) return item:finalize(self) end, nil, {}),
  }
end

function EditorMain:doUI(dt)
  if self.onUI.count > 0 then
    if self.onUI:any(dt) then return end
    self.onUI:clear()
    storedSubUICommand.command = ''
  end

  self.activeTab = nil
  ui.tabBar('tabs', function ()
    self.tabs:forEach(function (item)
      ui.tabItem(item.name, function ()
        self.activeTab = item.name
        ui.childWindow('#scrolling', item.fn)
      end)
    end)
  end)
end

function EditorMain:laneWorldEditor()
  if self.mousePoint == nil then return end

  if not uio.ctrlDown and self.creatingNewLane ~= nil then
    self.creatingNewLane = nil
  end

  if not uio.shiftDown and self.creatingNewIntersection ~= nil then
    if #self.creatingNewIntersection > 2 then
      self.intersectionsList:push(EditorIntersection(self.creatingNewIntersection))
      ensureIDUnique(self.lanesList)
      self:select(self.intersectionsList[#self.intersectionsList])
    end
    self.creatingNewIntersection = nil
    self:onChange()
  end

  if not uio.altDown and self.creatingNewArea ~= nil then
    if #self.creatingNewArea > 2 then
      if self.selectedArea ~= nil then
        self.selectedArea:extend(self.creatingNewArea)
      else
        self.areasList:push(EditorArea(self.creatingNewArea))
        ensureIDUnique(self.areasList)
      end
      self:select(self.areasList[#self.areasList])
    end
    self.creatingNewArea = nil
    self:onChange()
  end

  ui.pushFont(ui.Font.Small)

  if self.creatingNewLane ~= nil then
    ui.text("Click somewhere to finish creating a new lane.")
    ui.text("Afterwards, hold Ctrl held to quickly extend new line.")
    if ui.mouseClicked() then
      self.lanesList:push(EditorLane(self.creatingNewLane, self.mousePoint:clone()))
      ensureIDUnique(self.lanesList)
      self.creatingNewLane = nil
      self:select(self.lanesList[#self.lanesList])
      self:onChange()
    end
  elseif self.creatingNewIntersection ~= nil then
    ui.text("Click somewhere at least " .. (3 - #self.creatingNewIntersection) .. " more time(s).")
    if #self.creatingNewIntersection >= 3 then
      ui.text("Release Shift to finish creating an intersection.")
    end
    if ui.mouseClicked() then
      self.creatingNewIntersection:push(self.mousePoint:clone())
    end
  elseif self.creatingNewArea ~= nil then
    ui.text("Click somewhere at least " .. (3 - #self.creatingNewArea) .. " more time(s).")
    if #self.creatingNewArea >= 3 then
      ui.text("Release Alt to finish creating an area.")
    end
    if ui.mouseClicked() then
      self.creatingNewArea:push(self.mousePoint:clone())
    end
  elseif self.selectedArea ~= nil then
    if self.highlightedPointIndex ~= -1 then
      if #self.selectedArea.shapes > 1 then
        ui.text("Press Backspace button to remove a shape")
        if ui.keyPressed(ui.Key.Backspace) then
          local area = self.selectedArea
          local shape = self.selectedArea.shapes[math.floor(self.highlightedPointIndex / 1000)]
          self.selectedArea.shapes:removeAt(math.floor(self.highlightedPointIndex / 1000), true)
          self.selectedArea:recalculate()
          self:onChange()
          ui.toast(ui.Icons.Delete, 'Shape removed', function ()
            area.shapes:push(shape)
          end)
        end
      else
        ui.text("Press Insert button to add a new point nearby")
      end
      if ui.keyPressed(ui.Key.Delete) then
        self.selectedArea:removePointAt(self.highlightedPointIndex)
        self:onChange()
      end
      if ui.keyPressed(ui.Key.Insert) then
        self.selectedArea:insertPointNextTo(self.mousePoint, self.highlightedPointIndex)
        self:onChange()
      end
    else
      ui.text("Hold Alt and click to extend selected area with a new one.")
      ui.text("Un-select an area to create a new one.")
    end
    if ui.mouseClicked() then
      if uio.altDown then
        self.creatingNewArea = Array{self.mousePoint:clone()}
      end
    end
  elseif self.selectedLane ~= nil then
    if self.highlightedPointIndex ~= -1 then
      if #self.selectedLane.points > 2 then
        ui.text("Press Delete button to remove a point")
        if ui.keyPressed(ui.Key.Delete) then
          self.selectedLane:removePointAt(self.highlightedPointIndex)
          self:onChange()
        end
      end
      ui.text("Press Insert button to add a new point nearby")
      if ui.keyPressed(ui.Key.Insert) then
        self.selectedLane:insertPointNextTo(self.mousePoint, self.highlightedPointIndex)
        self:onChange()
      end
    else
      ui.text("Hold Ctrl and click to extend a selected lane.")
      if uio.ctrlDown then
        ui.text("Hold Shift to extend lane from a different end.")
      else
        ui.text("Unselect (uncheck checkbox) to create a new lane.")
      end
      if ui.mouseClicked() and uio.ctrlDown then
        self.selectedLane:extend(self.mousePoint:clone(), uio.shiftDown)
        self:onChange()
      end
    end
  else
    if self.activeTab == 'Areas' then
      ui.text("Hold Alt and click to start creating a new area.")
      ui.text("Select an area to extend it with a new one.")
    else
      ui.text("Hold Ctrl and click to start creating a new lane.")
      ui.text("Hold Shift and click to start creating a new intersection.")
    end
    if ui.mouseClicked() then
      if uio.altDown then
        self.creatingNewArea = Array{self.mousePoint:clone()}
      elseif uio.ctrlDown then
        self.creatingNewLane = self.mousePoint:clone()
      elseif uio.shiftDown then
        self.creatingNewIntersection = Array{self.mousePoint:clone()}
      end
    end
  end
  ui.popFont()
end

function EditorMain:select(item)  
  self.selectedLane = EditorLane.isInstanceOf(item) and item or nil
  self.selectedIntersection = EditorIntersection.isInstanceOf(item) and item or nil
  self.selectedArea = EditorArea.isInstanceOf(item) and item or nil
end

function EditorMain:draw3D()
  if self.onDraw3D:any() then return end
  self.onDraw3D:clear()

  local ray = render.createMouseRay()
  local _rayDistance = nil
  local function getRayDistance()
    if _rayDistance == nil then
      _rayDistance = ray:physics()
    end
    return _rayDistance
  end

  local lookForClicked = not uio.ctrlDown and not uio.shiftDown and not uio.altDown and uio.isMouseLeftKeyClicked and not ui.mouseBusy()
  local clickedItem = nil

  if self.selectedLane ~= nil and self.selectedLane.points.length > 4 then
    local trafficLane = self.selectedLane:cubicCurve()
    local steps = math.ceil(trafficLane.totalDistance)
    local prev = trafficLane:interpolate(1, 0)
    for j = 1, steps do
      local step = trafficLane:interpolateDistance(trafficLane.totalDistance * j / steps)
      render.debugLine(prev, step, EditorColors.cubicTest)
      prev:set(step)
    end
  end

  local cameraPos = ac.getSim().cameraPosition
  local shortestDistance = 1e30
  local shortestDistanceIndex = 1e30
  for i = 1, #self.lanesList do
    local lane = self.lanesList[i]
    local selected = lane == self.selectedLane
    if selected or lane.aabb:closerToThan(cameraPos, 300) then
      local laneColor = selected and EditorColors.selected or EditorColors.lane
      for j = 1, #lane.points do
        if j > 1 or lane.loop then
          local p1 = lane.points[j == 1 and #lane.points or j - 1]
          local p2 = lane.points[j]
          if selected or p1:closerToThan(cameraPos, 400) then
            render.debugArrow(p1, p2, -1, laneColor)

            if lookForClicked then
              local distanceToCamera = (p1 + p2):scale(0.5):distance(sim.cameraPosition)
              if ray:line(p1, p2, distanceToCamera * 0.01) ~= -1 then
                clickedItem = lane
              end
            end
          end
        end
        if j == math.ceil(#lane.points / 2) and (selected or lane.points[j]:closerToThan(cameraPos, 200)) then
          render.debugText(lane.points[j], lane.name, laneColor)
        end

        if selected and not uio.ctrlDown then
          local distance = ray:distance(lane.points[j])
          if distance < shortestDistance then
            shortestDistance = distance
            shortestDistanceIndex = j
          end
        end
      end
    end
  end

  for i = 1, #self.intersectionsList do
    local inter = self.intersectionsList[i]
    local selected = inter == self.selectedIntersection
    if selected or inter.aabb:closerToThan(cameraPos, 300) then
      local interColor = selected and EditorColors.selected or EditorColors.intersection
      for j = 1, #inter.points do
        local p1 = inter.points[j == 1 and #inter.points or j - 1]
        local p2 = inter.points[j]
        render.debugLine(p1, p2, interColor)

        if lookForClicked then
          local distanceToCamera = (p1 + p2):scale(0.5):distance(sim.cameraPosition)
          if ray:line(p1, p2, distanceToCamera * 0.01) ~= -1 then
            clickedItem = inter
          end
        end

        if selected and not uio.ctrlDown then
          local distance = ray:distance(inter.points[j])
          if distance < shortestDistance then
            shortestDistance = distance
            shortestDistanceIndex = j
          end
        end
      end
      render.debugText(inter.aabb.center, inter.name, interColor)
    end
  end

  for i = 1, #self.areasList do
    local inter = self.areasList[i]
    local selected = inter == self.selectedArea
    if selected or inter.aabb:closerToThan(cameraPos, 300) then
      local interColor = selected and EditorColors.selected or EditorColors.area
      for k = 1, #inter.shapes do
        local p = inter.shapes[k]
        for j = 1, #p do
          local p1 = p[j == 1 and #p or j - 1]
          local p2 = p[j]
          render.debugLine(p1, p2, interColor)

          if lookForClicked then
            local distanceToCamera = (p1 + p2):scale(0.5):distance(sim.cameraPosition)
            if ray:line(p1, p2, distanceToCamera * 0.01) ~= -1 then
              clickedItem = inter
            end
          end

          if selected and not uio.ctrlDown then
            local distance = ray:distance(p[j])
            if distance < shortestDistance then
              shortestDistance = distance
              shortestDistanceIndex = k * 1000 + j
            end
          end
        end
      end
      render.debugText(inter.aabb.center, inter.name, interColor)
    end
  end

  if lookForClicked then
    self:select(clickedItem)
  end

  local selectedItem = self.selectedLane or self.selectedIntersection or self.selectedArea
  if not render.isPositioningHelperBusy() and not uio.isMouseLeftKeyDown then
    self.highlightedPointIndex = -1
    if shortestDistance < 1e3 then
      local point = selectedItem:getPointRef(shortestDistanceIndex)
      local distanceToCamera = point:distance(sim.cameraPosition)
      if shortestDistance < distanceToCamera * 0.1 then
        self.highlightedPointIndex = shortestDistanceIndex
      end
    end
  end

  if self.currentlyMovingPoint ~= nil then
    if not self.movableHelper:render(self.currentlyMovingPoint) then
      self.currentlyMovingPoint = nil
      self.currentlyMovingItem:recalculate()
      self:onChange()
    end
    if render.isPositioningHelperBusy() and self.movableHelper:movingInScreenSpace() and getRayDistance() ~= -1 then
      self.currentlyMovingPoint:set(ray.dir * getRayDistance() + ray.pos)
    end
  elseif selectedItem ~= nil and self.highlightedPointIndex ~= -1 then
    local point = selectedItem:getPointRef(self.highlightedPointIndex)
    if self.movableHelper:render(point) then
      self.currentlyMovingPoint = point
      self.currentlyMovingItem = selectedItem
    end
  end

  if getRayDistance() == -1 then
    self.mousePoint = nil
    return
  end
  self.mousePoint = ray.dir * getRayDistance() + ray.pos

  if uio.ctrlDown or uio.shiftDown or uio.altDown then
    render.debugCross(self.mousePoint, 1, EditorColors.cursorPoint)
    if self.creatingNewLane ~= nil then
      render.debugLine(self.creatingNewLane, self.mousePoint, EditorColors.creating)
    elseif self.creatingNewIntersection ~= nil then
      local size = #self.creatingNewIntersection
      for i = 1, size do
        render.debugLine(self.creatingNewIntersection[i], i == size and self.mousePoint or self.creatingNewIntersection[i + 1], EditorColors.creating)
      end
      if size > 1 then
        render.debugLine(self.creatingNewIntersection[1], self.mousePoint, EditorColors.creating)
      end
    elseif self.creatingNewArea ~= nil then
      local size = #self.creatingNewArea
      for i = 1, size do
        render.debugLine(self.creatingNewArea[i], i == size and self.mousePoint or self.creatingNewArea[i + 1], EditorColors.creating)
      end
      if size > 1 then
        render.debugLine(self.creatingNewArea[1], self.mousePoint, EditorColors.creating)
      end
    elseif self.selectedLane ~= nil then
      render.debugLine(self.selectedLane.points[uio.shiftDown and 1 or #self.selectedLane.points], self.mousePoint, EditorColors.creating)
    end
  end
end

function EditorMain:isEmpty()
  return #self.lanesList == 0
end

function EditorMain:subUI(ui, restoreCommand)
  self.onUI:subscribe(ui)
  storedSubUICommand.command = restoreCommand or ''
end

return class.emmy(EditorMain, EditorMain.initialize)