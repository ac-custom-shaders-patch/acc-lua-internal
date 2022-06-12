local _slider = refnumber()

---@class EditorTrafficLightProgramDefinition
---@field name string
---@field editor fun(p: table): boolean
---@field emissives {name:string, color:rgb}[]
local _editorTrafficLightProgramDefinition = nil

---@type EditorTrafficLightProgramDefinition[]
local EditorTrafficLightPrograms = {
  {
    name = 'Basic',
    editor = function (p)
      local c = false
      if ui.slider('##gld', _slider:set(p.duration or 15), 10, 50, 'Phase duration: %.1f s') then p.duration, c = _slider.value, true end
      return c
    end,
    emissives = { 
      { name = 'Red', color = rgb(1, 0, 0) },
      { name = 'Yellow', color = rgb(1, 0.8, 0) },
      { name = 'Green', color = rgb(0, 1, 0) },
    }
  }
}

return EditorTrafficLightPrograms
