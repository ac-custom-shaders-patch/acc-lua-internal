-- Service runs once every few frames. Make sure to keep it lightweight.

local arrowAngle
local iconBgArrowColor = rgbm(34/255, 161/255, 98/255, 1)

local function drawNextTurnArrow(size)
  -- possibly easier and better solution would be to just keep a few PNGs for different arrows,
  -- but for now this should work

  local cur = ui.getCursor()
  ui.drawCircleFilled(cur + size / 2, size / 2, iconBgArrowColor, 30)

  -- arrowAngle = ui.time() * 180 % 360 - 180
  arrowAngle = math.floor(arrowAngle / 30 + 0.5) * 30
  local s = math.sin(math.rad(arrowAngle))
  local c = math.cos(math.rad(arrowAngle))
  local p1, p2
  if arrowAngle > 100 then
    ui.pathLineTo(cur + vec2(size / 2 - size * 0.07, size * 0.8))
    ui.pathLineTo(cur + vec2(size / 2 - size * 0.07, size * 0.4))
    p1 = vec2(size / 2 + size * 0.1, size * 0.4)
    p2 = vec2(size / 2 + size * 0.1 + s * size * 0.25, size * 0.4 - c * size * 0.25)
  elseif arrowAngle < -100 then
    ui.pathLineTo(cur + vec2(size / 2 + size * 0.07, size * 0.8))
    ui.pathLineTo(cur + vec2(size / 2 + size * 0.07, size * 0.4))
    p1 = vec2(size / 2 - size * 0.1, size * 0.4)
    p2 = vec2(size / 2 - size * 0.1 + s * size * 0.25, size * 0.4 - c * size * 0.25)
  else
    local x = size / 2 - math.sign(arrowAngle) * size * 0.07
    ui.pathLineTo(cur + vec2(x, size * 0.8))
    p1 = vec2(x, size * 0.5)
    p2 = vec2(x + s * size * 0.3, size * 0.5 - c * size * 0.3)
  end
  ui.pathLineTo(cur + p1)
  ui.pathLineTo(cur + p2)
  ui.pathStroke(rgbm.colors.white, false, 3)

  p1:scale(-1):add(p2):normalize()
  ui.pathLineTo(cur + p2)
  ui.pathLineTo(cur + vec2(p1.y, -p1.x):add(p1):scale(-size * 0.18):add(p2))
  ui.pathLineTo(cur + vec2(-p1.y, p1.x):add(p1):scale(-size * 0.18):add(p2))
  ui.pathFillConvex(rgbm.colors.white)
  ui.invisibleButton('arrow', size)
end

return function (dt)
  local turn = ac.getTrackUpcomingTurn(car.index)
  local trackSector = ac.getTrackSectorName(car.splinePosition)
  if trackSector == '' then trackSector = 'Unknown' end
  local statusText = turn.x ~= -1 and string.format('%.0f m • %s', math.ceil(turn.x / 25) * 25, trackSector)
  arrowAngle = turn.y

  if statusText then
    system.setNotification(drawNextTurnArrow, statusText, 'Maps', true)
  else
    system.setNotification(nil)
  end
end
