local EditorEditConnections = require('EditorEditConnections')

---@class EditorTabRules
---@field editor EditorMain
---@field oldSelection EditorIntersection
local EditorTabRules = class('EditorTabLanes')

---@param editor EditorMain
---@return EditorTabRules
function EditorTabRules:initialize(editor)
  self.editor = editor
end

local _slider = refnumber()

function EditorTabRules:doUI()
  ui.pushFont(ui.Font.Small)
  ui.pushItemWidth(ui.availableSpaceX() - 30)
  local c = false

  ui.header('Lane roles')
  for i, v in ipairs(self.editor.rules.laneRoles) do
    ui.pushID(i)
    ui.text(string.format('%d: %s', i, v.name))
    
    ui.offsetCursorX(30)
    if ui.slider('##priority', _slider:set(v.priority), -10, 10, 'Priority: %.0f') then
      v.priority, c = _slider.value, true
    end

    ui.offsetCursorX(30)
    if ui.slider('##speedLimit', _slider:set(v.speedLimit), 0, 150, 'Speed limit: %.0f km/h') then
      v.speedLimit, c = _slider.value, true
    end

    ui.popID()
  end

  if c then
    self.editor.onChange()
  end

  ui.popItemWidth()
  ui.popFont()
end

return class.emmy(EditorTabRules, EditorTabRules.initialize)