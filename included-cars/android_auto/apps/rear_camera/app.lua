return function (dt)
  local sh = ui.windowHeight()
  local sw = ui.windowWidth()
  local w = sh * 4 / 3
  ui.drawRectFilled(vec2((sw - w) / 2, 0), vec2((sw + w) / 2, sh), rgbm.colors.black)
  ui.drawImage('dynamic::camera_rear_distorted', vec2((sw - w) / 2, 0), vec2((sw + w) / 2, sh), rgbm.colors.white, vec2(1, 0), vec2(0, 1))
  system.fullscreen()
  touchscreen.forceAwake()

  local startL = vec2((sw - w) / 2 + w * 0.08, sh * 0.7)
  local startR = vec2((sw - w) / 2 + w * 0.92, sh * 0.7)
  local direction = vec2(35, -25):normalize()
  local lineLen = 160
  local steps = 9
  local currentPosL = startL:clone()
  local currentPosR = startR:clone()
  local color = rgbm.colors.red
  for i = 1, steps do
    local newPosL = startL + direction * (i * (lineLen / steps))
    local newPosR = startR + vec2(-direction.x, direction.y) * (i * (lineLen / steps))
    local drawAcrossColor = color
    if i == 4 then
      color = rgbm.colors.yellow
    elseif i == 7 then
      color = rgbm(0, 0.75, 0, 1)
    else
      drawAcrossColor = i == 9 and color or nil
    end
    ui.drawLine(currentPosL, newPosL, color, 4)
    ui.drawLine(currentPosR, newPosR, color, 4)
    if drawAcrossColor ~= nil then
      ui.drawLine(currentPosL, currentPosR, drawAcrossColor, 4)
    end
    currentPosL = newPosL
    currentPosR = newPosR
    direction:add(vec2(0, 0.015)):normalize()
  end

  if math.abs(car.steer) > 10 then
    direction = vec2(35, -25):normalize()
    currentPosL = startL
    currentPosR = startR
    local steerOffset = car.steer * 0.25
    for i = 1, steps do
      local newPosL = startL + direction * (i * (lineLen / steps)) + vec2(steerOffset * (i / steps) ^ 2, 0)
      local newPosR = startR + vec2(-direction.x, direction.y) * (i * (lineLen / steps)) + vec2(steerOffset * (i / steps) ^ 2, 0)
      ui.drawLine(currentPosL, newPosL, rgbm.colors.blue, 4)
      ui.drawLine(currentPosR, newPosR, rgbm.colors.blue, 4)
      currentPosL = newPosL
      currentPosR = newPosR
      direction:add(vec2(0, 0.015)):normalize()
    end
  end

  ui.drawRectFilled(vec2(sw * 0.2, sh * 0.85), vec2(sw * 0.8, sh * 0.85 + 40), rgbm(0, 0, 0, 0.8))
  ui.setCursor(vec2(sw * 0.2, sh * 0.85))
  ui.pushFont(ui.Font.Title)
  ui.textAligned('Check surroundings for safety', 0.5, vec2(sw * 0.6, 40))
  ui.popFont()
end