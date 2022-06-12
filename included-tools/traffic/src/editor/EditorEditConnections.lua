local Array = require('Array')
local FlatPolyShape = require('FlatPolyShape')
local TurnTrajectory = require('TurnTrajectory')
local EditorTrafficLightPrograms = require('EditorTrafficLightPrograms')
local EditorUI = require('EditorUI')

local function calculatePos(lane, pos, point)
  local p1 = lane.points[point]
  local p2 = lane.points[point + 1]
  local d1 = pos:distance(vec2(p1.x, p1.z))
  local d2 = vec2(p2.x, p2.z):distance(vec2(p1.x, p1.z))
  return d1 / d2
  -- return math.lerp(p1, p2, d1 / d2), (p2 - p1):normalize()
end

---@class EditorConnection
---@field distance number
---@field offset number
---@field side integer
---@field lane EditorLane
local EditorConnection = class()
---@param int EditorIntersection
---@param lane EditorLane
function EditorConnection.allocate(int, lane, point, pos2, side, isExit)
  local edgePos = calculatePos(lane, pos2, point)
  local offset = int:getEntryOffset(lane, isExit)
  local priorityOffset = int:getEntryPriorityOffset(lane)
  return { lane = lane, distance = lane:cubicCurve():pointEdgePosToDistance(point, edgePos), side = side, offset = offset, priorityOffset = priorityOffset }
end
function EditorConnection:initialize()
  self:updateOffset()
end
function EditorConnection:updateOffset()
  self.pos = self.lane:cubicCurve():interpolateDistance(self.distance + self.offset)
  self.dir = self.lane:cubicCurve():interpolateDistance(self.distance + self.offset + 0.01):sub(self.pos):normalize()
end

---@class EditorEditConnections : ClassBase
---@field editor EditorMain
---@field intersection EditorIntersection
---@field shape FlatPolyShape
---@field enters Array|EditorConnection[]
---@field exits Array|EditorConnection[]
local EditorEditConnections = class('EditorEditConnections')

---@param editor EditorMain
---@param int EditorIntersection
---@return EditorEditConnections
function EditorEditConnections:initialize(editor, int)
  if not editor then error('Editor is not set') end
  if not int then error('Intersection is not set') end

  self.editor = editor
  self.intersection = int

  self.shape = FlatPolyShape(int.points[1].y, 5, int.points, function (t) return vec2(t.x, t.z) end)
  self.enters = Array()
  self.exits = Array()

  self.editor.lanesList:forEach(
    ---@param lane EditorLane
    function (lane)
    self.shape:collectIntersections(lane.points, lane.loop, function (indexFrom, posFrom, sideFrom, indexTo, posTo, sideTo)
      local fromEdgePos = calculatePos(lane, posFrom, indexFrom)
      local fromDistance = lane:cubicCurve().edgesCubic[indexFrom].totalDistance + lane:cubicCurve().edgesCubic[indexFrom].edgeLength * fromEdgePos
      if fromDistance > 0.1 then
        self.enters:push(EditorConnection(int, lane, indexFrom, posFrom, sideFrom, false))
      end

      local toEdgePos = calculatePos(lane, posTo, indexTo)
      local toDistance = lane:cubicCurve().edgesCubic[indexTo].totalDistance + lane:cubicCurve().edgesCubic[indexTo].edgeLength * toEdgePos
      if toDistance < lane:cubicCurve().totalDistance - 0.1 then
        self.exits:push(EditorConnection(int, lane, indexTo, posTo, sideTo, true))
      end
    end)
  end)

  ---@param i1 EditorConnection
  ---@param i2 EditorConnection
  self.enters:sort(function (i1, i2)
    return i1.side < i2.side or i1.side == i2.side and i1.pos:distanceSquared(self.shape.aabb.center) > i2.pos:distanceSquared(self.shape.aabb.center)
  end)

  ---@param i1 EditorConnection
  ---@param i2 EditorConnection
  self.exits:sort(function (i1, i2) 
    return i1.side < i2.side or i1.side == i2.side and i1.pos:distanceSquared(self.shape.aabb.center) > i2.pos:distanceSquared(self.shape.aabb.center)
  end)

  self.draw3D = self.draw3D:bind(self)
  self.editor.onDraw3D:subscribe(self.draw3D)
end

local _slider = refnumber()

function EditorEditConnections:trajectoriesGrid()
  local c = ui.getCursor()

  ui.setCursor(c)
  ui.beginRotation()
  ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0, 0, 1))
  self.exits:forEach(function (item)
    ui.textAligned(item.lane.name, vec2(0, 0), vec2(60, 0))
  end)
  ui.popStyleColor()
  ui.endPivotRotation(180, c + vec2(74, -4))
  
  ui.setCursor(c + vec2(0, 80))
  ui.pushStyleColor(ui.StyleColor.Text, rgbm(0, 1, 0, 1))
  self.enters:forEach(function (item)
    ui.textAligned(item.lane.name, vec2(1, 0), vec2(60, 0))
  end)
  ui.popStyleColor()

  ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.4, 0.4, 0.4, 1))
  local hEnter, hExit = nil, nil
  self.enters:forEach(
    ---@param enter EditorConnection
    function (enter, i)
    ui.setCursor(c + vec2(76, 61 + 18 * i))
    self.exits:forEach(      
    ---@param exit EditorConnection
      function (exit)
      local selected = self.sEnter == enter and self.sExit == exit
      local allowed = self.intersection:isTrajectoryAllowed(enter.lane, exit.lane)
      if not allowed then ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.4, 0.2, 0.2, 1)) 
      elseif self.hEnterRow == enter then ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.4, 0.5, 0.4, 1))
      elseif self.hExitRow == exit then ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.5, 0.4, 0.4, 1)) end
      ui.button(' ', vec2(17, 17), selected and ui.ButtonFlags.Active or 0)

      if not allowed or self.hEnterRow == enter or self.hExitRow == exit then ui.popStyleColor() end
      if ui.itemHovered() then
        hEnter, hExit = enter, exit
        if ui.mouseClicked(1) then
          self.intersection:setTrajectoryAllowed(enter.lane, exit.lane, not allowed)
          self.editor.onChange()
        end
      end
      ui.sameLine(0, 1)

      local attributes = self.intersection:getTrajectoryAttributes(enter.lane, exit.lane)
      local laneRolePo = self.editor.rules.laneRoles[enter.lane.role] and self.editor.rules.laneRoles[enter.lane.role].priority or 0
      local laneBasePo = enter.lane.priorityOffset
      local lanePo = self.intersection:getEntryPriorityOffset(enter.lane)
      local finalPo = laneRolePo + laneBasePo + lanePo + (attributes and attributes.po or 0)
      if ui.itemHovered() then
        ui.setTooltip(string.format('Role priority: %.0f\nLane offset: %.0f\nEntry offset: %.0f\nTrajectory offset: %.0f', 
          laneRolePo, laneBasePo, lanePo, attributes and attributes.po or 0))
      end
      if finalPo ~= 0 then
        local c = ui.getCursor()
        ui.offsetCursor(vec2(-20, -3))
        ui.beginScale()
        ui.textAligned(string.format('%.0f', finalPo), 0.5, 21)
        ui.endScale(0.8)
        ui.setCursor(c)
      end
    end)
  end)
  ui.popStyleColor()

  self.hEnter, self.hExit = hEnter, hExit
  if hEnter ~= nil and ui.mouseClicked() then
    if self.sEnter == hEnter and self.sExit == hExit then
      self.sEnter, self.sExit = nil, nil
    else
      self.sEnter, self.sExit = hEnter, hExit
    end
  end

  self.hEnterRow, self.hExitRow = nil, nil
  self.enters:forEach(function (enter, i)
    if ui.rectHovered(c + vec2(-10, (61) + 18 * i), c + vec2(76, (61+18) + 18 * i)) then
      self.hEnterRow = enter
      if ui.mouseClicked(1) then
        self.exits:forEach(function (exit)
          local allowed = self.intersection:isTrajectoryAllowed(enter.lane, exit.lane)
          self.intersection:setTrajectoryAllowed(enter.lane, exit.lane, not allowed)
        end)
        self.editor.onChange()
      end
    end
  end)
  self.exits:forEach(function (exit, i)
    if ui.rectHovered(c + vec2(57 + 18 * i, -10), c + vec2((57+18) + 18 * i, 76)) then
      self.hExitRow = exit
      if ui.mouseClicked(1) then
        self.enters:forEach(function (enter)
          local allowed = self.intersection:isTrajectoryAllowed(enter.lane, exit.lane)
          self.intersection:setTrajectoryAllowed(enter.lane, exit.lane, not allowed)
        end)
        self.editor.onChange()
      end
    end
  end)

  ui.setCursor(c + vec2(0, 61 + 18 * (#self.enters + 1) + 12))
  ui.pushFont(ui.Font.Small)

  if self.sEnter ~= nil then

    self:trajectoryAttributes(self.sEnter, self.sExit)

  else
    ui.textWrapped('Hover square or column/row and click right mouse button to quickly toggle the trajectory.')
  end

  ui.popFont()
end

---@param conFrom EditorConnection
---@param conTo EditorConnection
function EditorEditConnections:trajectoryAttributes(conFrom, conTo)
  local allowed = self.intersection:isTrajectoryAllowed(conFrom.lane, conTo.lane)
  if ui.checkbox('Allowed', allowed) then
    self.intersection:setTrajectoryAllowed(conFrom.lane, conTo.lane, not allowed)
    self.editor.onChange()
  end

  local attributes, changed = self.intersection:getTrajectoryAttributes(conFrom.lane, conTo.lane) or {}, false

  if ui.slider('##po', _slider:set(attributes.po or 0), -10, 10, 'Priority offset: %.0f') then
    attributes.po, changed = _slider.value ~= 0 and _slider.value or nil, true
  end
  if ui.itemHovered() then
    ui.setTooltip('Offsets lane priority')
  end

  ui.separator()

  if ui.slider('##cb', _slider:set(attributes.cb or 0.5), 0, 2, 'Curvature (start): %.2f') then
    attributes.cb, changed = _slider.value, true
  end

  if ui.slider('##ce', _slider:set(attributes.ce or 0.5), 0, 2, 'Curvature (end): %.2f') then
    attributes.ce, changed = _slider.value, true
  end

  if conFrom.dir:dot(conTo.dir) < -0.8 then
    if ui.slider('##ul', _slider:set(attributes.ul or 0.5), 0, 2, 'U-turn (length): %.2f') then
      attributes.ul, changed = _slider.value, true
    end
  end

  if changed then
    self.intersection:setTrajectoryAttributes(conFrom.lane, conTo.lane, attributes)
    self.editor.onChange()
  end
end

function EditorEditConnections:entryParams()
  ui.pushFont(ui.Font.Small)
  self.hEnterOffset = nil

  local function entryOffset(invert, enter, i)
    ui.pushID(i)
    ui.textAligned(enter.lane.name, vec2(), vec2(80, 0))
    ui.sameLine()
    if ui.slider('##offset', _slider:set(invert and -enter.offset or enter.offset), 0, 30, invert and '-%.1f m' or '%.1f m') then
      enter.offset = invert and -_slider.value or _slider.value
      enter:updateOffset()
      self.intersection:setEntryOffset(enter.lane, enter.offset, invert)
      self.editor.onChange()
    end
    if ui.itemHovered() then
      self.hEnterOffset = enter
    end
    ui.popID()
  end

  ui.offsetCursorY(12)
  ui.header('Entry priority offsets')
  ui.pushID(1)
  self.enters:forEach(function (enter, i)
    ui.pushID(i)
    ui.textAligned(enter.lane.name, vec2(), vec2(80, 0))
    ui.sameLine()
    if ui.slider('##po', _slider:set(enter.priorityOffset), -10, 10, '%.0f') then
      enter.priorityOffset = _slider.value
      self.intersection:setEntryPriorityOffset(enter.lane, enter.priorityOffset)
      self.editor.onChange()
    end
    if ui.itemHovered() then
      self.hEnterOffset = enter
    end
    ui.popID()
  end)
  ui.popID()
  ui.textWrapped('Resulting trajectory priority: lane type priority + region priority offset + entry priority offset + trajectory priority offset')

  ui.offsetCursorY(12)
  ui.header('Entry offsets')
  ui.pushID(1)
  self.enters:forEach(entryOffset:bind(false))
  ui.popID()

  ui.offsetCursorY(12)
  ui.header('Exit offsets')
  ui.pushID(2)
  self.exits:forEach(entryOffset:bind(true))
  ui.popID()
  ui.popFont()

end


local _emissiveModes = {
  {
    name = 'Separate emissives',
    ---@param program EditorTrafficLightProgramDefinition
    ---@param params SerializedTrafficLightEmissiveParams
    editor = function (program, params, switchToNext)
      local changed = false
      for i, v in ipairs(program.emissives) do
        ui.offsetCursorX(30)
        ui.pushID(i)
        ui.textColored(v.name..':', v.color)
        ui.offsetCursorX(30)
        if not params.roles[i] then params.roles[i] = {} end
        local role = params.roles[i]
        local c, s = EditorUI.sceneReference(role, switchToNext)
        if c then changed = true end
        switchToNext = s
        ui.popID()
      end
      return changed, switchToNext
    end
  },
  {
    name = 'Virtual meshes',
    ---@param program EditorTrafficLightProgramDefinition
    ---@param params SerializedTrafficLightEmissiveParams
    editor = function (program, params, switchToNext)
      local changed, c = false, nil
      if not params.hide then params.hide = {} end
      ui.offsetCursorX(30)
      ui.text('Meshes to hide:')
      ui.offsetCursorX(30)
      c, switchToNext = EditorUI.sceneReference(params.hide, switchToNext)
      if c then changed = true end

      if not params.virtual then params.virtual = {} end
      ui.offsetCursorX(30)
      ui.text('Geometry:')
      ui.offsetCursorX(30)
      c, switchToNext = EditorUI.trafficVirtualLights(program, params.virtual)
      if c then changed = true end

      return changed, switchToNext
    end
  },
  --[[ {
    name = 'Multi-channel emissives',
    ---@param program EditorTrafficLightProgramDefinition
    ---@param params SerializedTrafficLightEmissiveParams
    editor = function (program, params)
    end
  }, ]]
}

---@param program EditorTrafficLightProgramDefinition
---@param params SerializedTrafficLightEmissiveParams
---@return boolean
local function _emissiveParams(program, params, switchToNext)
  local changed = false
  ui.combo('##mode', 'Mode: '.._emissiveModes[params.mode or 1].name, ui.ComboFlags.None, function ()
    for i, v in ipairs(_emissiveModes) do
      if ui.selectable(v.name, i == (params.mode or 1)) then
        params.mode = i
        changed = true
      end
    end
  end)

  if not params.roles then params.roles = {} end

  if not _emissiveModes[params.mode or 1] then
    ui.text('Unknown mode: '..tostring(params.mode))
  else 
    local c
    c, switchToNext = _emissiveModes[params.mode or 1].editor(program, params, switchToNext)
    if c then changed = true end
  end
  return changed, switchToNext
end

function EditorEditConnections:trafficLight()
  ui.pushFont(ui.Font.Small)

  local changed = false
  ui.offsetCursorY(3)
  ui.text('Traffic light:')
  ui.sameLine()
  ui.offsetCursorY(-3)
  ui.setNextItemWidth(ui.availableSpaceX())
  ui.combo('##program', self.intersection.trafficLightProgram or 'None', function ()
    local inter = self.intersection
    if ui.selectable('None', inter.trafficLightProgram == 'None', ui.SelectableFlags.None) then
      inter.trafficLightProgram, changed = nil, true
    end
    for i = 1, #EditorTrafficLightPrograms do
      local p = EditorTrafficLightPrograms[i]
      local selected = inter.trafficLightProgram == p.name
      if ui.selectable(p.name, selected, ui.SelectableFlags.None) then
        inter.trafficLightProgram, changed = p.name, true
      end
    end
  end)

  if self.intersection.trafficLightProgram ~= nil then
    local selectedProgram = table.findFirst(EditorTrafficLightPrograms, function (item)
      return item.name == self.intersection.trafficLightProgram
    end)
    if selectedProgram then
      ui.pushItemWidth(ui.availableSpaceX())
      ui.offsetCursorY(12)
      ui.header('Program parameters')
      if selectedProgram.editor(self.intersection.trafficLightParams) then
        changed = true
      end

      if selectedProgram.emissives then
        if not self.intersection.trafficLightEmissive then self.intersection.trafficLightEmissive = {} end
        ui.offsetCursorY(12)
        ui.header('Emissive parameters')
        ui.offsetCursorY(4)
        local inter = self.intersection
        local switchToNext = false
        for i = 1, #inter.points do
          ui.text('Side '..tostring(i)..':')
          ui.pushID(i)
          local emissiveParams = self.intersection.trafficLightEmissive[i]
          if not emissiveParams then
            emissiveParams = {}
            self.intersection.trafficLightEmissive[i] = emissiveParams
          end
          local c
          c, switchToNext = _emissiveParams(selectedProgram, emissiveParams, switchToNext)
          if c then
            changed = true
          end
          ui.popID()
          ui.offsetCursorY(12)
        end

      end

      ui.popItemWidth()
    else
      ui.text(string.format('Error: unknown program “%s”', self.intersection.trafficLightProgram))
    end
  end

  if changed then    
    self.intersection:recalculate()
    self.editor.onChange()
  end

  ui.popFont()

end

function EditorEditConnections:__call()
  ui.pushFont(ui.Font.Small)
  if ui.button('← back') then
    self.editor.onDraw3D:unsubscribe(self.draw3D)
    ui.popFont()
    return false
  end
  ui.popFont()
  ui.sameLine()
  ui.header(self.intersection.name)

  ui.tabBar('tabs', function ()
    ui.tabItem('Trajectories grid', function ()
      ui.childWindow('scrolling', function ()
        self._curTab = 'grid'
        self:trajectoriesGrid()
      end)
    end)
    ui.tabItem('Entry params', function ()
      ui.childWindow('scrolling', function ()
        self._curTab = 'entryParams'
        self:entryParams()
      end)
    end)
    ui.tabItem('Traffic light', function ()
      ui.childWindow('scrolling', function ()
        self._curTab = 'trafficLight'
        self:trafficLight()
      end)
    end)
  end)
  return true
end

---@type SerializedTrajectoryAttributes
local _emptyAttributes = {}

---@param enter EditorConnection
---@param exit EditorConnection
---@param color rgbm
function EditorEditConnections:drawTrajectory(enter, exit, color)
  local attributes = self.intersection:getTrajectoryAttributes(enter.lane, exit.lane) or _emptyAttributes
  local trajectory = TurnTrajectory(enter.pos, enter.dir, exit.pos, exit.dir, attributes)
  local start = enter.pos
  for i = 1, 10 do
    local nextStep = trajectory:get(i / 10 * trajectory.length)
    render.debugArrow(start, nextStep, 0.3, color)
    start = nextStep
  end
  class.recycle(trajectory)
end

function EditorEditConnections:draw3D()
  if self.hEnter ~= nil then
    self:drawTrajectory(self.hEnter, self.hExit, rgbm(0, 0, 0, 1))
  elseif self.hEnterRow ~= nil then
    self.exits:forEach(function (exit)
      local allowed = self.intersection:isTrajectoryAllowed(self.hEnterRow.lane, exit.lane)
      self:drawTrajectory(self.hEnterRow, exit, rgbm(allowed and 0 or 3, allowed and 3 or 0, 0, 1))
    end)
  elseif self.hExitRow ~= nil then
    self.enters:forEach(function (enter)
      local allowed = self.intersection:isTrajectoryAllowed(enter.lane, self.hExitRow.lane)
      self:drawTrajectory(enter, self.hExitRow, rgbm(allowed and 0 or 3, allowed and 3 or 0, 0, 1))
    end)
  end

  if self.sEnter ~= nil then
    self:drawTrajectory(self.sEnter, self.sExit, rgbm(0, 3, 3, 1))
  end

  local hEnterOffset = self.hEnterOffset
  for i = 1, #self.enters do
    local e = self.enters[i]
    local h = hEnterOffset == nil or hEnterOffset == e
    render.debugArrow(e.pos, e.pos + e.dir * 3, 0.5, h and rgbm(0, 3, 0, 1) or rgbm(0, 0, 0, 1))
    render.debugText(e.pos - vec3(0, 2, 0), e.lane.name, h and rgbm(0, 1, 0, 1) or rgbm(1, 1, 1, 1), 0.8)
  end

  for i = 1, #self.exits do
    local e = self.exits[i]
    local h = hEnterOffset == nil or hEnterOffset == e
    render.debugArrow(e.pos, e.pos + e.dir * 3, 0.5, h and rgbm(3, 0, 0, 1) or rgbm(0, 0, 0, 1))
    render.debugText(e.pos - vec3(0, 2, 0), e.lane.name, h and rgbm(1, 0, 0, 1) or rgbm(1, 1, 1, 1), 0.8)
  end

  local int = self.intersection
  for i = 1, #int.points do
    render.debugLine(int.points[i], int.points[i % #int.points + 1], rgbm(3, 3, 0, 1))
    render.debugText((int.points[i] + int.points[i % #int.points + 1]) / 2, string.format('Side %d', i), rgbm(3, 2, 1, 3), 2)
  end

  return true
end

return class.emmy(EditorEditConnections, EditorEditConnections.initialize)