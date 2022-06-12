local EditorEditConnections = require('EditorEditConnections')
local FlatPolyShape = require('FlatPolyShape')

---@class EditorTabIntersections
---@field editor EditorMain
---@field oldSelection EditorIntersection
local EditorTabIntersections = class('EditorTabLanes')

---@param editor EditorMain
---@return EditorTabIntersections
function EditorTabIntersections:initialize(editor)
  self.editor = editor
  self.oldSelection = nil
end

local minItemHeight = vec2(10, 58)

function EditorTabIntersections:doUI()
  ui.header('Created intersections')
  ui.childWindow('##intersectionsList', vec2(0, -50), function ()
    local intersectionsList = self.editor.intersectionsList
    local intersLen = #intersectionsList
    if intersLen == 0 then
      ui.text('No intersections were created yet.')
    end

    local scroll = self.editor.selectedIntersection ~= self.oldSelection
    if scroll then
      self.oldSelection = self.editor.selectedIntersection
      if not ui.mouseBusy() and  self.oldSelection then
        ui.setScrollY(minItemHeight.y * (intersectionsList:indexOf(self.oldSelection) - 2))
      end
    end

    local toRemoveIndex = 0
    for i = 1, intersLen do
      if self:intersectionItem(intersectionsList[i]) then
        toRemoveIndex = i
      end
    end

    if toRemoveIndex ~= 0 then
      local toRemove = intersectionsList[toRemoveIndex]
      intersectionsList:removeAt(toRemoveIndex)
      if self.editor.selectedIntersection == toRemove then self.editor.selectedIntersection = nil end
      self.editor:onChange()
      ui.toast(ui.Icons.Delete, 'Traffic intersection “'..toRemove.name..'” removed', function ()
        intersectionsList:insert(math.min(toRemoveIndex, #intersectionsList + 1), toRemove)
        self.editor:onChange()
      end)
    end
  end)

  ui.offsetCursorY(12)
  self.editor:laneWorldEditor()
end

---@param inter EditorIntersection
function EditorTabIntersections:intersectionItem(inter)
  if not ui.areaVisible(minItemHeight) then
    -- simple trick for super-fast lists of items
    ui.offsetCursorY(minItemHeight.y)
    return
  end

  local toRemove = false
  ui.pushID(inter.uniqueID)
  if ui.checkbox('##' .. inter.name, inter == self.editor.selectedIntersection) then
    self.editor:select(inter ~= self.editor.selectedIntersection and inter or nil)
  end
  ui.sameLine()
  ui.setNextItemWidth(ui.availableSpaceX() - 40)
  local newName, changed = ui.inputText('##name', inter.name)
  if changed then
    inter.name = newName
    self.editor:onChange()
  end
  ui.sameLine(ui.availableSpaceX() - 32)
  ui.button('…', vec2(32, 0))
  ui.itemPopup(ui.MouseButton.Left, function ()
    -- ui.separator()
    toRemove = ui.selectable('Delete intersection')
  end)
  ui.pushFont(ui.Font.Small)
  ui.offsetCursorX(30)
  if ui.button('Edit connections') then
    self.editor:subUI(EditorEditConnections(self.editor, inter),
      string.format('require("EditorEditConnections")(self, self.intersectionsList:findFirst(function (s) return s.name == "%s" end))', inter.name))
  end
  ui.sameLine()
  ui.text(string.format('Traffic light: %s', inter.trafficLightProgram or 'No'))
  ui.popFont()
  ui.popID()
  ui.offsetCursorY(8)
  return toRemove
end

return class.emmy(EditorTabIntersections, EditorTabIntersections.initialize)