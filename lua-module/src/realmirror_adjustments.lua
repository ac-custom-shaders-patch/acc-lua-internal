--[[
  Rear view mirrors adjusting with hotkeys. Active only if at least a single hotkey is set.
]]

local cfg = Config:mapSection('REALMIRROR_HOTKEYS', {
  SPEED = 0.1,
  SHOW_MESSAGE = true
})

local btnNext = ac.ControlButton('__EXT_REALMIRRORS_NEXT')
local btnPrev = ac.ControlButton('__EXT_REALMIRRORS_PREVIOUS')

local buttons = table.filter({
  { ac.ControlButton('__EXT_REALMIRRORS_LEFT'), vec3(1, 0, 0) },
  { ac.ControlButton('__EXT_REALMIRRORS_RIGHT'), vec3(-1, 0, 0) },
  { ac.ControlButton('__EXT_REALMIRRORS_UP'), vec3(0, 1, 0) },
  { ac.ControlButton('__EXT_REALMIRRORS_DOWN'), vec3(0, -1, 0) },
}, function (item)
  return item[1]:configured()
end)

if #buttons == 0 then
  return
end

local activeMirror = 1

local function getMirrorName(index, totalCount)
  if totalCount == 1 then return 'only mirror' end
  if totalCount == 2 then return index == 1 and 'left mirror' or 'right mirror' end
  if totalCount == 3 then return index == 1 and 'left mirror' or index == 2 and 'center mirror' or 'right mirror' end
  return 'mirror #'..tostring(index)
end

Register('gameplay', function (dt)
  local mirrorsCount = ac.getRealMirrorCount()
  if mirrorsCount < 1 then
    if btnNext:pressed() or btnPrev:pressed() then
      ac.setMessage('Real Mirrors', 'No active mirrors')
    end
    return;
  end

  if btnNext:pressed() or btnPrev:pressed() then
    activeMirror = activeMirror + (btnNext:pressed() and 1 or -1)
    if activeMirror < 1 then activeMirror = activeMirror + mirrorsCount
    elseif activeMirror > mirrorsCount then activeMirror = 1 end
    if activeMirror == 2 and mirrorsCount == 3 and ac.getRealMirrorParams(activeMirror - 1).isMonitor then
      activeMirror = activeMirror + (btnNext:pressed() and 1 or -1)
    end
    ac.setMessage('Real Mirrors', 'Currently adjusting: '..getMirrorName(activeMirror, mirrorsCount))
  end

  for i = 1, #buttons do
    if buttons[i][1]:down() then
      local p = ac.getRealMirrorParams(activeMirror - 1)
      p.rotation:addScaled(buttons[i][2], dt * cfg.SPEED)
      ac.setRealMirrorParams(activeMirror - 1, p)
    end
  end
end)
