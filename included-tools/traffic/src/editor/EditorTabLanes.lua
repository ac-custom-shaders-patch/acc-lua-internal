local Array = require('Array')
local EditorLane = require('EditorLane')

---@class EditorTabLanes
---@field editor EditorMain
local EditorTabLanes = class('EditorTabLanes')

---@param editor EditorMain
---@return EditorTabLanes
function EditorTabLanes:initialize(editor)
  self.editor = editor
  self.oldSelection = nil
end

local minItemHeight = vec2(10, 98)

---@param self EditorTabLanes
---@param filename string
local function loadFromOBJ(self, filename)
  local vertices = {}
  local nextName = nil  
  local lines = self.editor.lanesList
  lines:clear()

  for _, line in ipairs(io.load(filename, ''):split('\n', nil, true, true)) do
    local b = line:byte(1)
    if b == 118 then -- v
      local x, y, z = line:numbers(3)
      vertices[#vertices + 1] = vec3(x, z, -y)
    elseif b == 111 then -- o
      nextName = line:sub(3):trim()
    elseif b == 108 then -- l
      local points = table.map({ line:numbers() }, function (i, _, data) return data[i] end, vertices)
      if #points > 1 then
        lines:push(EditorLane{
          points = points, 
          name = nextName or error('No next name found')
        })
      end
      nextName = nil
    end
  end

  self.editor:onChange()
end

function EditorTabLanes:doUI()
  if ui.button('Replace lines with OBJ file', vec2(ui.availableSpaceX(), 0)) then
    os.openFileDialog({
      title = 'Open',
      defaultFolder = ac.getFolder(ac.FolderID.ContentTracks)..'/'..ac.getTrackID(),
      fileTypes = {
        {
          name = 'OBJ Models',
          mask = '*.obj'
        }
      },
    }, function (err, filename)
      if not err and filename then
        loadFromOBJ(self, filename)
      end
    end)
  end
  ui.offsetCursorY(12)

  ui.header('Created lanes')
  ui.childWindow('##lanesList', vec2(0, -50), function ()
    local lanesList = self.editor.lanesList
    local lanesLen = #lanesList
    if lanesLen == 0 then
      ui.text('No lanes were created yet.')
    end

    local scroll = self.editor.selectedLane ~= self.oldSelection
    if scroll then
      self.oldSelection = self.editor.selectedLane
      if self.oldSelection and not ui.mouseBusy() then
        ui.setScrollY(minItemHeight.y * (lanesList:indexOf(self.oldSelection) - 2))
      end
    end

    local toRemoveIndex = 0
    for i = 1, lanesLen do
      if self:laneItem(lanesList[i]) then
        toRemoveIndex = i
      end
    end

    if toRemoveIndex ~= 0 then
      local toRemove = lanesList[toRemoveIndex]
      if self.editor.selectedLane == toRemove then
        self.editor.selectedLane = nil
      end
      lanesList:removeAt(toRemoveIndex)
      self.editor:onChange()

      ui.toast(ui.Icons.Delete, 'Traffic lane “'..toRemove.name..'” removed', function ()
        lanesList:insert(math.min(toRemoveIndex, #lanesList + 1), toRemove)
        self.editor:onChange()
      end)
    end
  end)

  ui.offsetCursorY(12)
  self.editor:laneWorldEditor()
end

local _slider = refnumber()

---@param lane EditorLane
function EditorTabLanes:laneItem(lane)
  if not ui.areaVisible(minItemHeight) then
    -- simple trick for super-fast lists of items
    ui.offsetCursorY(minItemHeight.y)
    return
  end
  
  local c = ui.getCursorY()
  
  local toRemove = false
  ui.pushID(lane.uniqueID)
  if ui.checkbox('##' .. lane.name, lane == self.editor.selectedLane) then
    self.editor:select(lane ~= self.editor.selectedLane and lane or nil)
  end
  ui.sameLine()
  ui.setNextItemWidth(ui.availableSpaceX() - 40)
  local newName, _c = ui.inputText('##name', lane.name)
  if _c then
    lane.name, _c = newName, true
  end
  ui.sameLine(ui.availableSpaceX() - 32)
  ui.button('…', vec2(32, 0))
  ui.itemPopup('cfg', ui.MouseButton.Left, function ()
    if ui.checkbox("Loop", lane.loop) then
      lane.loop, _c = not lane.loop, true
    end
    if ui.selectable('Reverse direction', false, 1) then
      lane.points:reverse(lane.points)
      _c = true
    end
    ui.separator()
    toRemove = ui.selectable('Delete lane')
  end)
  ui.pushFont(ui.Font.Small)

  ui.offsetCursorX(30)
  ui.setNextItemWidth(120)
  local r = self.editor.rules.laneRoles[lane.role or 1]
  ui.combo('##role', string.format('Role: %s', r and r.name or tostring(lane.role or 1)), ui.ComboFlags.None, function ()
    for i, v in ipairs(self.editor.rules.laneRoles) do
      if ui.selectable(v.name, v == r) then
        lane.role, _c = i, true
      end
      if ui.itemHovered() then
        ui.setTooltip('Priority: '..tostring(v.priority))
      end
    end
  end)
  ui.sameLine(0, 4)
  ui.setNextItemWidth(ui.availableSpaceX())
  if ui.slider('##po', _slider:set(lane.priorityOffset), -10, 10, 'Priority offset: %.0f') then
    lane.priorityOffset, _c = _slider.value, true
  end

  local _p = lane.params
  ui.offsetCursorX(30)
  if ui.checkbox('Allow U-turns', _p.allowUTurns == true) then
    _p.allowUTurns, _c = not _p.allowUTurns, true
  end
  if ui.itemHovered() then
    ui.setTooltip('Allow turns to nearby lanes running in different directions')
  end
  ui.sameLine()
  if ui.checkbox('Allow lane changes', _p.allowLaneChanges ~= false) then
    _p.allowLaneChanges, _c = not _p.allowLaneChanges, true
  end
  if ui.itemHovered() then
    ui.setTooltip('Allow changes to nearby lanes running in similar direction')
  end
  
  ui.offsetCursorX(30)
  ui.text(string.format('Length: %.1f m, points: %d%s', lane.length, #lane.points, lane.loop and ', loop' or ''))

  ui.popFont()
  ui.popID()
  ui.offsetCursorY(8)

  if _c then    
    lane:recalculate()
    self.editor.onChange()
  end

  if ui.getCursorY() - c ~= minItemHeight.y then
    ac.debug('Correct area item height', ui.getCursorY() - c)
  end
  return toRemove
end

return class.emmy(EditorTabLanes, EditorTabLanes.initialize)