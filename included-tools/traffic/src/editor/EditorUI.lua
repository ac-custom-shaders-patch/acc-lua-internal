local EditorUI = {}

local _editedElement = nil
local _sceneReferenceData = { newValue = nil, skip = false }
local _trackRoot = ac.findNodes('trackRoot:yes')
local _ref = ac.emptySceneReference()

local function _sceneReferenceDraw3D()
  if not ui.mouseBusy() then
    local ray = render.createMouseRay()
    local d, mesh = _trackRoot:raycast(ray, _ref)
    if d ~= -1 then
      local point = ray.dir * d + ray.pos
      render.debugCross(point, 0.5)
      render.debugText(point, 'Mesh: '..mesh:name(1)..'\nMaterial: '..mesh:materialName(1)..'\nPress <Backspace> to cancel selection\nPress <Enter> to skip selection', rgbm.colors.white, 0.9, render.FontAlign.Left)
      if ac.getUI().isMouseLeftKeyClicked then
        _sceneReferenceData.newValue = mesh:name(1)
      end
    end
  end

  if ui.keyPressed(ui.Key.Escape) or ui.keyPressed(ui.Key.Backspace) then    
    script.draw3DOverride = nil
    _editedElement = nil
  end

  if ui.keyPressed(ui.Key.Enter) then    
    _sceneReferenceData.skip = true
  end
end

function EditorUI.sceneReference(role, switchToNext)
  local width, newValue, changed = ui.availableSpaceX(), nil, nil
  ui.setNextItemWidth(width - 40)
  newValue, changed = ui.inputText('Mesh name or filter', role.mesh or '', ui.InputTextFlags.Placeholder)
  if changed then role.mesh = newValue end
  if ui.itemHovered() then ui.setTooltip('Could also be several meshes separated by a comma') end
  ui.sameLine(0, 4)
  if ui.button('Pick', vec2(36, 0), _editedElement == role and ui.ButtonFlags.Active or ui.ButtonFlags.None) or switchToNext then
    _editedElement = _editedElement ~= role and role or nil
    _sceneReferenceData.newValue = nil
    _sceneReferenceData.skip = false
    if not _editedElement then
      script.draw3DOverride = nil
    else
      script.draw3DOverride = _sceneReferenceDraw3D
    end
  end
  if ui.itemHovered() then ui.setTooltip('Click a mesh to use its name here') end
  if _editedElement == role then
    if _sceneReferenceData.newValue then
      role.mesh, changed = _sceneReferenceData.newValue, true
      script.draw3DOverride = nil
      _editedElement = nil
      switchToNext = true
    elseif _sceneReferenceData.skip then
      script.draw3DOverride = nil
      _editedElement = nil
      switchToNext = true
    end
  else
    switchToNext = false
  end
  return changed, switchToNext
end

local prevValues = ac.storage{ radius = 0.1 }

local _sceneTvlData = {
  ---@type EditorTrafficLightProgramDefinition
  program = nil,

  ---@type {pos:vec3, dir:vec3, radius:number}[]
  items = {},

  pos = vec3(),
  dir = vec3(),
  done = false
}

-- local vecRealUp = vec3(0, 1, 0)
-- local vecUp = vec3()
-- local vecSide = vec3()
-- local function renderQuad(pos, dir, color, radius)
--   local side = vecSide:setCrossNormalized(dir, vecRealUp):scale(radius * 0.3)
--   local up = vecUp:setCrossNormalized(dir, vecSide):scale(radius * 0.3)
--   render.glSetColor(color)
--   render.glBegin(render.GLPrimitiveType.Quads)
--   render.glVertex(pos + side + up)
--   render.glVertex(pos - side + up)
--   render.glVertex(pos - side - up)
--   render.glVertex(pos + side - up)
--   render.glEnd()
-- end

local function renderQuad(pos, dir, color, radius)
  render.setDepthMode(render.DepthMode.Normal)
  render.circle(pos, dir, radius, color, rgbm(0, 0, 0, 1))
end

---@param program EditorTrafficLightProgramDefinition
local function renderPoints(items, program)
  for i = 1, #items do
    local item = items[i]
    renderQuad(item.pos, item.dir, program.emissives[(i - 1) % #program.emissives + 1].color, item.radius)
  end
end

local function _sceneTvlDraw3D()
  local pos, dir, program, items, radius = _sceneTvlData.pos, _sceneTvlData.dir, _sceneTvlData.program, _sceneTvlData.items, prevValues.radius

  if not ui.mouseBusy() then 
    local ray = render.createMouseRay()
    local d = _trackRoot:raycast(ray, _ref, pos, dir)
    if d ~= -1 then
      local next = program.emissives[#items % #program.emissives + 1]
      pos:addScaled(dir, 0.01)
      renderQuad(pos, dir, rgbm.new(next.color, 0.5), radius)
      render.debugText(pos, string.format('Click to add %s light here\nUse W/S buttons to change radius\nPress <Backspace> to %s\nPress <Enter> to finish positioning', 
        next.name, #items > 0 and 'remove last item' or 'cancel selection'),
        rgbm.colors.white, 0.9, render.FontAlign.Left)
      if ac.getUI().isMouseLeftKeyClicked then
        table.insert(items, { pos = pos:clone(), dir = dir:clone(), radius = radius })
      end
    end

    radius = radius + (ui.keyPressed(ui.Key.W) and 0.001 or 0)
    radius = math.max(0.001, radius - (ui.keyPressed(ui.Key.S) and 0.001 or 0))
    prevValues.radius = radius
  end

  renderPoints(items, program)

  if ui.keyPressed(ui.Key.Escape) or ui.keyPressed(ui.Key.Backspace) then
    if #items > 0 then
      table.remove(items, #items)
    else
      script.draw3DOverride = nil
      _editedElement = nil
    end
  end

  if ui.keyPressed(ui.Key.Enter) then
    _sceneTvlData.done = true
  end
end

local _hoveredElement = nil

local function _sceneTvlDrawPreview()
  local program, items = _sceneTvlData.program, _sceneTvlData.items
  renderPoints(items, program)
end

local function _decodeItems(items)
  return table.map(table.filter(items or {}, function (item) return item.pos end), function (item) return {pos = vec3.new(item.pos), dir = vec3.new(item.dir), radius = item.radius} end)
end

local function _encodeItems(items)
  return table.map(items or {}, function (item) return {pos = item.pos:table(), dir = item.dir:table(), radius = item.radius} end)
end

---@param program EditorTrafficLightProgramDefinition
function EditorUI.trafficVirtualLights(program, data, switchToNext)
  local width, changed = ui.availableSpaceX(), nil

  local label
  if _editedElement == data then
    label = string.format('%d point%s', #_sceneTvlData.items, #_sceneTvlData.items == 1 and '' or 's')    
  elseif data.items and #data.items > 0 then
    label = string.format('%d point%s', #data.items, #data.items == 1 and '' or 's')
  else
    label = 'Not set'
  end

  if ui.button(label, vec2(width, 0), _editedElement == data and ui.ButtonFlags.Active or ui.ButtonFlags.None) or switchToNext then
    _editedElement = _editedElement ~= data and data or nil
    _sceneTvlData.program, _sceneTvlData.done = program, false
    if not _editedElement then
      script.draw3DOverride = nil
      data.items = _encodeItems(_sceneTvlData.items)
      changed = true
    else
      script.draw3DOverride = _sceneTvlDraw3D
      _sceneTvlData.items = _decodeItems(data.items)
    end
    switchToNext = false
  end
  if ui.itemHovered() then
    if script.draw3DOverride == nil and data.items then
      _hoveredElement = data
      _sceneTvlData.program, _sceneTvlData.items = program, _decodeItems(data.items)
      script.draw3DOverride = _sceneTvlDrawPreview
    end
    ui.setTooltip('Press this button and then click centers of all emissive areas to create glowing circles')
  elseif script.draw3DOverride == _sceneTvlDrawPreview and _hoveredElement == data then
    script.draw3DOverride = nil
    _hoveredElement = nil
  end

  if _editedElement == data and _sceneTvlData.done then
    script.draw3DOverride = nil
    _editedElement = nil
    data.items = _encodeItems(_sceneTvlData.items)
    changed, switchToNext = true, true
  end

  return changed, switchToNext
end

return EditorUI
