local EditorEditConnections = require('EditorEditConnections')
local FlatPolyShape = require('FlatPolyShape')

---@class EditorTabAreas
---@field editor EditorMain
---@field oldSelection EditorIntersection
local EditorTabAreas = class('EditorTabLanes')

---@param editor EditorMain
---@return EditorTabAreas
function EditorTabAreas:initialize(editor)
  self.editor = editor
  self.oldSelection = nil
end

local minItemHeight = vec2(10, 154)

function EditorTabAreas:doUI()
  ui.header('Created areas')
  ui.childWindow('##areasList', vec2(0, -50), function ()
    local areasList = self.editor.areasList
    local intersLen = #areasList
    if intersLen == 0 then
      ui.text('No areas were created yet.')
    end

    local scroll = self.editor.selectedArea ~= self.oldSelection
    if scroll then
      self.oldSelection = self.editor.selectedArea
      if not ui.mouseBusy() and  self.oldSelection then
        ui.setScrollY(minItemHeight.y * (areasList:indexOf(self.oldSelection) - 2))
      end
    end

    local toRemoveIndex = 0
    for i = 1, intersLen do
      if self:areaItem(areasList[i]) then
        toRemoveIndex = i
      end
    end

    if toRemoveIndex ~= 0 then
      local toRemove = areasList[toRemoveIndex]
      areasList:removeAt(toRemoveIndex)
      if self.editor.selectedArea == toRemove then self.editor.selectedArea = nil end
      self.editor:onChange()
      ui.toast(ui.Icons.Delete, 'Traffic area “'..toRemove.name..'” removed', function ()
        areasList:insert(math.min(toRemoveIndex, #areasList + 1), toRemove)
        self.editor:onChange()
      end)
    end
  end)

  ui.offsetCursorY(12)
  local int = self.editor.selectedArea
  if int ~= nil then
    local h = int.shapes:some(function (s)
      local s = FlatPolyShape(s[1].y, 5, s, function (t) return vec2(t.x, t.z) end)
      local h = vec3()
      render.createMouseRay():physics(h)
      s:contains(h)
      class.recycle(s)
    end)
    ui.pushFont(ui.Font.Small)
    ui.text(h and 'Mouse pointer in the selected area' or 'Mouse pointer is outside')
    ui.popFont()
  end
  self.editor:laneWorldEditor()
end

local _slider = refnumber()

local function activableCheckbox(state, changed, prop, desc)
  ui.pushID(prop)
  if state ~= nil then
    if ui.checkbox('##override', true) then state, changed = nil, true end
    if ui.itemHovered() then
      ui.setTooltip(string.format('Override “%s”', prop))
    end
    ui.sameLine(0, 4)
    if ui.checkbox(prop, state == true) then state, changed = not state, true end
    if ui.itemHovered() then
      ui.setTooltip(desc)
    end
  else
    if ui.checkbox(string.format('Override “%s”', prop), false) then state, changed = true, true end
    if ui.itemHovered() then
      ui.setTooltip(desc)
    end
  end
  ui.popID()
  return state, changed
end

---@param area EditorArea
function EditorTabAreas:areaItem(area)
  if not ui.areaVisible(minItemHeight) then
    -- simple trick for super-fast lists of items
    ui.offsetCursorY(minItemHeight.y)
    return
  end

  local c = ui.getCursorY()

  local toRemove = false
  ui.pushID(area.uniqueID)
  if ui.checkbox('##' .. area.name, area == self.editor.selectedArea) then
    self.editor:select(area ~= self.editor.selectedArea and area or nil)
  end
  ui.sameLine()
  ui.setNextItemWidth(ui.availableSpaceX() - 40)
  local newName, changed = ui.inputText('##name', area.name)
  if changed then
    area.name = newName
    self.editor:onChange()
  end
  ui.sameLine(ui.availableSpaceX() - 32)
  ui.button('…', vec2(32, 0))
  ui.itemPopup(ui.MouseButton.Left, function ()
    -- ui.separator()
    toRemove = ui.selectable('Delete area')
  end)
  ui.pushFont(ui.Font.Small)

  local _p, _c = area.params, false

  local r = self.editor.rules.laneRoles[_p.role or 0]
  ui.offsetCursorX(30)
  ui.setNextItemWidth(ui.availableSpaceX())
  ui.combo('##role', string.format('Override lanes role: %s', r and r.name or 'No'), ui.ComboFlags.None, function ()
    if ui.selectable('No', r == nil) then
      _p.role, _c = nil, true
    end
    for i, v in ipairs(self.editor.rules.laneRoles) do
      if ui.selectable(v.name, v == r) then
        _p.role, _c = i, true
      end
      if ui.itemHovered() then
        ui.setTooltip('Priority: '..tostring(v.priority))
      end
    end
  end)
  
  ui.offsetCursorX(30)
  if _p.customSpeedLimit then
    if ui.checkbox('##osl', true) then _p.customSpeedLimit, _c = false, true end
    ui.sameLine(0, 4)
    ui.setNextItemWidth(ui.availableSpaceX())
    if ui.slider('##speed', _slider:set(_p.speedLimit or 90), 5, 150, 'Speed limit: %.0f km/h', 1.6) then _p.speedLimit, _c = _slider.value, true end
  else
    if ui.checkbox('Override speed limit', false) then _p.customSpeedLimit, _c = true, true end
  end

  ui.offsetCursorX(30)
  ui.setNextItemWidth(ui.availableSpaceX())
  if ui.slider('##spreadMult', _slider:set((_p.spreadMult or 1) * 100), 0, 200, 'Spread mult.: %.0f%%') then _p.spreadMult, _c = _slider.value / 100, true end

  ui.offsetCursorX(30)
  _p.allowUTurns, _c = activableCheckbox(_p.allowUTurns, _c, 'Allow U-turns',
    'Allow turns to nearby lanes running in different directions')

  ui.offsetCursorX(30)
  _p.allowLaneChanges, _c = activableCheckbox(_p.allowLaneChanges, _c, 'Allow lane changes',
    'Allow changes to nearby lanes running in similar direction')

  ui.popFont()
  ui.popID()
  ui.offsetCursorY(8)

  if _c then
    area:recalculate()
    self.editor.onChange()
  end

  if ui.getCursorY() - c ~= minItemHeight.y then
    ac.debug('Correct area item height', ui.getCursorY() - c)
  end

  return toRemove
end

return class.emmy(EditorTabAreas, EditorTabAreas.initialize)