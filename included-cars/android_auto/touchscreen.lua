---Helper library to create touchscreen-like screens. Feel free to copy it to your projects if needed,
---it’s CC0 and everything.
---Note: for it to work properly, use `touchscreen.tapped()` instead of regular `ui…` clicks.
---@diagnostic disable-next-line: lowercase-global
touchscreen = {}

local sleep = 0
local mouseDown = false
local mouseDownTime = 0
local mouseClicked = false
local mouseReleased = false
local tappedBase = false
local tapped = false
local longTapped = false
local prevMousePosY = -1
local mouseDownDelta = 0
local scrollingVelocity = 0
local scrollingWindowHovered = false
local doubleTappedNow = false
local doubleTappedNext = false
local scrollBarVisible = 0
local vkPosition = 1e9
local vkOffset = 0
local vkActiveText = nil
local vkHovered = false
local vkActive = 0
local vkCooldown = 0
local vkHeldTimer = nil
local stopNInput = 0
local sleptFor = 0
local uis = ac.getUI()

---Call this function at the start of a frame.
function touchscreen.update(forceAwake, dt)
  if vkActiveText then
    forceAwake = true
  end
  if scrollBarVisible <= 0 and not ui.anyItemActive() and not ui.isAnyMouseDown() and ui.mouseDelta().x == 0 and not forceAwake then
    sleep = sleep + dt
    if sleep > 3 then
      if sleptFor < 0.5 then
        sleptFor = sleptFor + dt
        ac.skipFrame()
        return true
      else
        sleptFor = 0
      end
    end
  else
    if forceAwake then
      ac.boostFrameRate()
    end
    sleep = 0
  end

  tappedBase = false
  doubleTappedNow = false
  mouseClicked = false
  mouseReleased = false

  if scrollBarVisible > 0 then
    scrollBarVisible = scrollBarVisible - dt
  end
  if ui.mouseDown() ~= mouseDown then
    mouseReleased = mouseDown
    mouseDown = not mouseDown
    mouseClicked = mouseDown
    prevMousePosY = ui.mousePos().y
    if mouseDown then 
      scrollingVelocity = 0 
      mouseDownDelta = 0
      mouseDownTime = ui.time()
    else
      tappedBase = mouseDownDelta < (uis.vrController and 100 or 20)
      doubleTappedNow = tappedBase and doubleTappedNext
      doubleTappedNext = false
    end
  elseif mouseDown then
    if scrollingWindowHovered then
      scrollingVelocity = vkHovered and 0 or prevMousePosY - ui.mousePos().y
    else
      scrollingVelocity = scrollingVelocity * 0.9
    end
    prevMousePosY = ui.mousePos().y
    mouseDownDelta = mouseDownDelta + #ui.mouseDelta()
    if math.abs(scrollingVelocity) > 0.1 then
      scrollBarVisible = 2
      ac.boostFrameRate()
    end
  else
    scrollingVelocity = scrollingVelocity * 0.9
  end

  if ui.mouseDoubleClicked() then
    doubleTappedNext = true
  end

  if vkActive > 1 then 
    vkActive = vkActive - 1
  else
    if vkCooldown > 0 then vkCooldown = vkCooldown - dt end
    if vkActive > 0.999 and not vkActiveText then vkCooldown = 0.5 end
    vkActive = math.applyLag(vkActive, vkCooldown <= 0 and vkActiveText and 1 or 0, 0.8, dt) 
  end
  vkActiveText = nil

  vkPosition = math.ceil(ui.windowHeight() * (1 - math.saturateN(vkActive) * 0.64))
  vkOffset = ui.windowHeight() - vkPosition
  vkHovered = ui.mouseLocalPos().y > vkPosition
  tapped = tappedBase and not vkHovered and vkCooldown <= 0 and ui.time() - mouseDownTime < 0.5
  longTapped = mouseDown and not vkHovered and vkCooldown <= 0 and ui.time() - dt - mouseDownTime < 0.5 and ui.time() - mouseDownTime > 0.5
  if vkHeldTimer and not ui.mouseDown() then
    clearInterval(vkHeldTimer)
    vkHeldTimer = nil
  end

  scrollingWindowHovered = false
end

local reactivateText = nil
local prevTextField = nil
local charToAdd = nil ---@type string|number
local vkBgColor = rgbm.new('#273238')
local vkBtnColor = rgbm.new('#414A51')
local vkBtnPressedColor = rgbm.new('#313A41')
local vkBtnActiveColor = rgbm.new('#6EACA7')
local vkBtnActivePressedColor = rgbm.new('#5E9C97')
local vkBtnShadowColor = rgbm.new('#111A21')
local vkBtnWidth = 70
local vkEnterIcon = ui.Icons.Enter
local vkShift = false
local vkButtonsReady
local vkLayouts = {
  base = {
    { { 'q', '1', 'Q' }, { 'w', '2', 'W' }, { 'e', '3', 'E' }, { 'r', '4', 'R' }, { 't', '5', 'T' }, { 'y', '6', 'Y' }, { 'u', '7', 'U' }, { 'i', '8', 'I' }, { 'o', '9', 'O' }, { 'p', '0', 'P' } },
    { { 'a', '@', 'A' }, { 's', '#', 'S' }, { 'd', '$', 'D' }, { 'f', '_', 'F' }, { 'g', '&', 'G' }, { 'h', '-', 'H' }, { 'j', '+', 'J' }, { 'k', '(', 'K' }, { 'l', ')', 'L' } },
    { { i = ui.Icons.Shift, s = true, w = 1.5, p = vec2(37, 11) }, { 'z', '*', 'Z' }, { 'x', '"', 'X' }, { 'c', '\'', 'C' }, { 'v', ':', 'V' }, { 'b', ';', 'B' }, { 'n', '!', 'N' }, { 'm', '?', 'M' }, { c = ui.KeyIndex.Back, i = ui.Icons.Backspace, w = 1.5 } },
    { { '?123', l = 'symbols', w = 1.5 }, { ',' }, { ' ', w = 4 }, { i = ui.Icons.Paste, p = vec2(20, 11) }, { '.' }, { i = ui.Icons.Enter, c = ui.KeyIndex.Return, p = vec2(33, 13), w = 1.5 } },
  },
  symbols = {
    { { '1' }, { '2' }, { '3' }, { '4' }, { '5' }, { '6' }, { '7' }, { '8' }, { '9' }, { '0' } },
    { { '@' }, { '#' }, { '$' }, { '%' }, { '&' }, { '-' }, { '+' }, { '(' }, { ')' } },
    { { '=\\<', l = 'symbolsAlt', w = 1.5, p = vec2(37, 11) }, { '*' }, { '"' }, { '\'' }, { ':' }, { ';' }, { '!' }, { '?' }, { c = ui.KeyIndex.Back, i = ui.Icons.Backspace, w = 1.5 } },
    { { 'ABC', l = 'base', w = 1.5 }, { ',' }, { '_' }, { ' ', w = 3 }, { '/' }, { '.' }, { i = ui.Icons.Enter, c = ui.KeyIndex.Return, p = vec2(33, 13), w = 1.5 } },
  },
  symbolsAlt = {
    { { '~' }, { '`' }, { '|' }, { '•' }, { '√' }, { 'π' }, { '÷' }, { '×' }, { '¶' }, { '∆' } },
    { { '£' }, { '¢' }, { '€' }, { '¥' }, { '∧' }, { '°' }, { '=' }, { '{' }, { '}' } },
    { { '?123', l = 'symbols', w = 1.5, p = vec2(37, 11) }, { '\\' }, { '©' }, { '®' }, { '™' }, { '‰' }, { '[' }, { ']' }, { c = ui.KeyIndex.Back, i = ui.Icons.Backspace, w = 1.5 } },
    { { 'ABC', l = 'base', w = 1.5 }, { ',' }, { '<' }, { ' ', w = 3 }, { '>' }, { '.' }, { i = ui.Icons.Enter, c = ui.KeyIndex.Return, p = vec2(33, 13), w = 1.5 } },
  }
}
local vkLayout = vkLayouts.base

local function keyboardButtonLayout(cur, char)
  local w = (char.w or 1) * vkBtnWidth
  char.p1 = cur:clone()
  char.p2 = cur + vec2(w - 10, 46)
  char.s1 = char.p1 + vec2(0, 2)
  char.s2 = char.p2 + vec2(0, 2)
  if char.i then char.ip = char.p1 + (char.p or vec2(33, 11)) end
  if char[1] then char.t1 = char.p1 + vec2((w - 10) / 2 - ui.measureDWriteText(char[1], 24).x / 2, 5) end
  if char[3] then char.t3 = char.p1 + vec2((w - 10) / 2 - ui.measureDWriteText(char[3], 24).x / 2, 5) end
  if char[2] then 
    char.t2 = char.p1 + vec2((w - 10) / 2 - ui.measureDWriteText(char[2], 24).x / 2, -50)
    char.u1 = char.p1 + vec2(w - 20 - ui.measureDWriteText(char[2], 14).x / 2, 0) 
  end
  return w
end

local function keyboardButton(char, layer)
  local cur = char.p1
  local p2 = char.p2
  if layer == 1 then
    local enterButton = char.c == ui.KeyIndex.Return
    ui.drawRectFilled(char.s1, char.s2, vkBtnShadowColor, 8)
    ui.drawRectFilled(cur, p2, (char.s and vkShift == 2 or enterButton) and (char.hovered and vkBtnActivePressedColor or vkBtnActiveColor) 
      or char.hovered and vkBtnPressedColor or vkBtnColor, 8)

    if mouseClicked and ui.rectHovered(cur, p2) then
      char.hovered = true
      char.popup = false
      vkHeldTimer = char.c == ui.KeyIndex.Back
        and setInterval(function () charToAdd = ui.KeyIndex.Back end, 0.12)
        or char[2] and setTimeout(function () char.popup, vkHeldTimer = true, nil end, 0.3)
    elseif char.hovered and not mouseDown then
      if ui.rectHovered(cur, p2) then
        if char.s then
          vkShift = vkShift == true and 2 or not vkShift
        elseif char.l then
          vkLayout = vkLayouts[char.l]
        elseif char.i == ui.Icons.Paste then
          charToAdd = ui.getClipboardText()
        else
          charToAdd = char.c or (char.popup and char[2] or vkShift and char[3] or char[1])
          if vkShift == true then vkShift = false end
        end
      end
      char.hovered, char.popup = false, false
    end

    if char.i then
      ui.setCursor(char.ip)
      ui.icon(enterButton and vkEnterIcon or char.s and vkShift and ui.Icons.ShiftActive or char.i, 24, rgbm.colors.white)
    end
  end

  if layer == 2 and char[1] then
    ui.dwriteDrawText(vkShift and char[3] or char[1], 24, vkShift and char.t3 or char.t1, rgbm.colors.white)
    if char[2] then
      ui.dwriteDrawText(char[2], 14, char.u1, rgbm(1, 1, 1, 0.5))
    end
  end

  if layer == 3 then
    ui.pushClipRectFullScreen()
    ui.drawRectFilled(cur - vec2(0, 60), p2, vkBtnShadowColor, 8)
    ui.dwriteDrawText(char[2], 24, char.t2, rgbm.colors.white)
    ui.popClipRect()
  end
end

local function updateKeyboardButtons()
  local r = { layout = vkLayout }
  local p = (ui.availableSpace().x - vkBtnWidth * 9.6) / 2
  for i = 1, #vkLayout do
    local cur = vec2(p + (i == 2 and vkBtnWidth/2 or 0), 55 * (i - 1) + 10)
    for j = 1, #vkLayout[i] do
      cur.x = cur.x + keyboardButtonLayout(cur, vkLayout[i][j])
      table.insert(r, vkLayout[i][j])
    end
  end
  return r
end

---Call this function at the end of a frame, it would draw an on-screen keyboard if needed.
function touchscreen.keyboard()
  if vkActiveText ~= nil then
    prevTextField = vkActiveText
    vkEnterIcon = vkActiveText == 'Search' and ui.Icons.Search or ui.Icons.Enter
  end
  if not vkButtonsReady or vkButtonsReady.layout ~= vkLayout then
    vkButtonsReady = updateKeyboardButtons()
  end
  if vkActive > 0.001 then
    ui.setCursor(vec2(0, vkPosition))
    ui.childWindow('onscreenKeyboard', ui.availableSpace() + vec2(0, 10), true, bit.bor(ui.WindowFlags.NoFocusOnAppearing, ui.WindowFlags.NoScrollbar), function ()
      ui.setCursor(0)
      ui.drawRectFilled(0, ui.availableSpace(), vkBgColor)

      local btnPopup
      for i = 1, #vkButtonsReady do
        local btn = vkButtonsReady[i]
        keyboardButton(btn, 1)
        if btn.popup then btnPopup = btn end
      end
      for i = 1, #vkButtonsReady do
        keyboardButton(vkButtonsReady[i], 2)
      end
      if btnPopup then
        keyboardButton(btnPopup, 3)
      end

      if ui.windowHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem) and (ui.mouseClicked() or ui.mouseReleased()) then
        reactivateText = prevTextField
        vkActive = 3
      end
    end)
  end
end

function touchscreen.keyboardHovered()
  return vkHovered
end

function touchscreen.keyboardOffset()
  return vkOffset
end

---Text input control with onscreen keyboard support. Returns updated string (which would be the input string unless it changed, so no)
---copying there. Second return value would change to `true` when text has changed. Example:
---```
---myText = ui.inputText('Enter something:', myText)
---```
---@param label string
---@param str string
---@param flags ui.InputTextFlags
---@return string
---@return boolean
function touchscreen.inputText(label, str, flags)
  local done = false
  if label == reactivateText then
    reactivateText = nil
    ui.setKeyboardFocusHere()
  elseif charToAdd ~= nil then
    if type(charToAdd) == 'number' then
      if charToAdd == ui.KeyIndex.Return then done = true end
      ui.setKeyboardButtonDown(charToAdd)
      charToAdd = nil
    elseif #charToAdd > 1 then
      ui.addInputCharacter(charToAdd:byte())
      charToAdd = charToAdd:sub(2)
    else
      ui.addInputCharacter(charToAdd:byte())
      charToAdd = nil
    end
  end

  local ret = ui.inputText(label, str, bit.bor(flags or 0, ui.InputTextFlags.NoUndoRedo))
  if stopNInput == 0 and ui.itemActive() then
    vkActiveText = label
  end
  if str and #str > 0 then
    local c = ui.getCursor()
    ui.setItemAllowOverlap()
    ui.sameLine(0, 0)
    ui.offsetCursorX(-32)
    if touchscreen.iconButton(ui.Icons.Cancel, vec2(32, ui.textLineHeightWithSpacing() * 1.1), 0.3, nil, 0.4) then
      ret = ''
    end
    if ui.itemClicked() then
      vkActiveText = nil
    end
    ui.setCursor(c)
  end
  return ret, done
end

---Adds touch scrolling to current list. Call it from a scrollable window. Pass `true` for `hidden`
---if you want to draw custom style scrollbar later.
function touchscreen.scrolling(hidden)
  if stopNInput > 0 or vkOffset > 1 then return 0 end

  ui.setScrollY(scrollingVelocity, true)
  scrollingWindowHovered = ui.windowHovered(ui.HoveredFlags.AllowWhenBlockedByActiveItem)

  local scrollMax = ui.getScrollMaxY()
  if scrollMax > 1 and not hidden then
    local window = ui.windowSize()
    local scrollY = ui.getScrollY()
    local barMarginX = 4
    local barMarginY = 4
    local barArea = window.y - barMarginY * 2
    local barX = window.x - math.lerp(-2, barMarginX, math.saturateN(scrollBarVisible * 4))
    local barHeight = math.lerp(40, barArea, window.y / (scrollMax + window.y))
    local barY = scrollY + barMarginY + scrollY / scrollMax * (barArea - barHeight)
    ui.setCursor(0)
    ui.drawLine(vec2(barX, barY), vec2(barX, barY + barHeight), rgbm.colors.white, 2)
  end
  return math.saturateN(scrollBarVisible * 4)
end

function touchscreen.scrollingVelocity()
  return (stopNInput > 0 or vkOffset > 1) and 0 or scrollingVelocity
end

---Stops input until returned function is called
function touchscreen.stopInput()
  stopNInput = stopNInput + 1
  return function ()
    stopNInput = stopNInput - 1
  end
end

---Pauses input for a bit
function touchscreen.pauseInput(time) 
  setTimeout(touchscreen.stopInput(), time or 0.3)
end

---Returns true if screen is being touched (like, mouse is down)
function touchscreen.touched()
  return mouseDown and stopNInput == 0
end

---Returns true if screen was touched in previous frame
function touchscreen.touchReleased()
  return mouseReleased and stopNInput == 0
end

---Returns true if screen was just tapped
function touchscreen.tapped()
  return tapped and stopNInput == 0
end

---Returns true if screen was long tapped
function touchscreen.longTapped()
  return longTapped and stopNInput == 0
end

---Returns true if screen was just double tapped
function touchscreen.doubleTapped()
  return doubleTappedNow and stopNInput == 0
end

---Returns true if previous item was just tapped
function touchscreen.itemTapped()
  return tapped and ui.itemHovered() and stopNInput == 0
end

---Returns true if previous item was double tapped
function touchscreen.itemLongTapped()
  return longTapped and ui.itemHovered() and stopNInput == 0
end

local defBaseSize = vec2(24, 24)
local defSize = vec2(24, 24)

---Touch button with an icon
---@param icon ui.Icons
---@param size vec2|nil
---@param iconAlphaOrColor number|rgbm|nil
---@param iconAngle number|nil
---@param iconScale number|nil
---@return boolean
function touchscreen.iconButton(icon, size, iconAlphaOrColor, iconAngle, iconScale, iconSize)
  local p = ui.getCursor()
  if not vec2.isvec2(size) then size = defBaseSize:set(size or 40, size or 40) end
  if not vec2.isvec2(iconSize) then iconSize = defSize:set(iconSize or 24, iconSize or 24) end
  ui.offsetCursorX((size.x - defSize.x) / 2)
  ui.offsetCursorY((size.y - defSize.y) / 2)
  if iconAngle ~= nil then ui.beginRotation() end
  if iconScale ~= nil then ui.beginScale() end
  if type(iconAlphaOrColor) == 'number' then ui.pushStyleVarAlpha(iconAlphaOrColor) end
  ui.icon(icon, defSize, rgbm.isrgbm(iconAlphaOrColor) and iconAlphaOrColor or nil)
  if iconAngle ~= nil then ui.endRotation(iconAngle) end
  if iconScale ~= nil then ui.endScale(iconScale) end
  if type(iconAlphaOrColor) == 'number' then ui.popStyleVar() end
  ui.setCursor(p)
  ui.invisibleButton(icon, size)
  return tapped and stopNInput == 0 and ui.itemHovered()
end

local iconSizeValue = vec2(24, 24)

---Touch button with an icon
---@param label string
---@param buttonSize vec2
---@param buttonColor rgbm
---@param fontSize number
---@param icon ui.Icons?
---@param iconSize vec2?
---@return boolean
function touchscreen.button(label, buttonSize, buttonColor, fontSize, icon, iconSize)
  local p = ui.getCursor()
  ui.invisibleButton(label, buttonSize)
  ui.drawRectFilled(p, p + buttonSize, 
    ui.itemActive() and rgbm(buttonColor.r * 0.8, buttonColor.g * 0.8, buttonColor.b * 0.8, buttonColor.mult) or buttonColor)
  ui.setCursor(p)
  if fontSize ~= 0 then
    ui.dwriteTextAligned(label, fontSize, ui.Alignment.Center, ui.Alignment.Center, buttonSize)
  end
  if icon ~= nil then
    if iconSize then iconSizeValue:set(iconSize) end
    ui.offsetCursorX((buttonSize.x - iconSizeValue.x) / 2)
    ui.offsetCursorY((buttonSize.y - iconSizeValue.y) / 2)
    ui.icon(icon, iconSizeValue)
  end
  return tapped and stopNInput == 0 and ui.itemHovered()
end

local loadingSize = vec2()

local function step(v)
  return (math.floor(v / 2) + math.smoothstep(math.min(v % 2, 1)))
end

function touchscreen.loading(size)
  local s = loadingSize:set(size)
  local t = ui.time()
  local r = math.min(s.x, s.y) / 2
  ui.pathArcTo(ui.getCursor() + s * 0.5, r, step(t * 1.3 + 1) * 4.5 + t * 3, step(t * 1.3) * 4.5 + 5 + t * 3, 40)
  ui.pathStroke(rgbm.colors.white, false, r / 5)
  ui.dummy(s)
  sleep = 0
end

function touchscreen.boostFrameRate()
  ac.boostFrameRate()
  sleep = 0
end

function touchscreen.forceAwake()
  sleep = 0
end

local storedValues = ac.storage{ muted = false, volume = 0.5 }
local volumeFresh = -1

---@param mediaPlayer ui.MediaPlayer
function touchscreen.syncVolume(mediaPlayer)
  mediaPlayer:setVolume(storedValues.volume):setMuted(storedValues.muted)
end

function touchscreen.syncVolumeIfFresh(mediaPlayer)
  if ui.time() - volumeFresh < 0.5 then
    mediaPlayer:setVolume(storedValues.volume):setMuted(storedValues.muted)
  end
end

function touchscreen.setMuted(muted)
  storedValues.muted = muted ~= false
  volumeFresh = ui.time()
end

function touchscreen.setVolume(volume)
  storedValues.volume = tonumber(volume) or 0
  volumeFresh = ui.time()
end

function touchscreen.volumeControl(pos, width, height)
  pos = pos or vec2()
  width = width or ui.windowWidth()
  height = height or ui.windowHeight()

  local ret = false
  local muted = storedValues.muted
  local volume = storedValues.volume
  local volumePivotX = width + 4
  local volumePivotY = height / 2 - 12
  ui.setCursor(pos + vec2(volumePivotX - 60, volumePivotY + 72))
  if touchscreen.iconButton((muted or volume == 0) and ui.Icons.Mute
      or volume < 0.33 and ui.Icons.VolumeLow
      or volume < 0.67 and ui.Icons.VolumeMedium
      or ui.Icons.VolumeHigh, 40) then
        touchscreen.setMuted(not muted)
    storedValues.muted = not muted
    touchscreen.forceAwake()
    ret = true
  end
  local p1 = vec2(volumePivotX - 40, volumePivotY + 60)
  local p2 = vec2(volumePivotX - 40, volumePivotY - 60)
  ui.drawLine(pos + p1, pos + p2, rgbm(1, 1, 1, 0.2), 8)
  ui.drawLine(pos + p1, pos + math.lerp(p1, p2, volume), rgbm.colors.white, 8)
  if stopNInput == 0 and ui.mouseDown() and ui.rectHovered(pos + vec2(volumePivotX - 60, volumePivotY - 80), pos + vec2(volumePivotX - 20, volumePivotY + 80)) then
    local newVolume = math.lerpInvSat(ui.mouseLocalPos().y, p1.y, p2.y)
    touchscreen.setVolume(newVolume)
    storedValues.volume = newVolume
    if muted then
      touchscreen.setMuted(false)
      storedValues.muted = false
    end
    touchscreen.boostFrameRate()
    ret = true
  end
  return ret
end

local hidingControlsLastTime = 0
local hidingControlsPopup = 0
local hidingControlsTime = 0

function touchscreen.hidingControls(dt)
  local time = ui.time()
  if touchscreen.tapped() or time - hidingControlsLastTime > 1 then
    hidingControlsPopup = 1
  end
  if hidingControlsPopup > 0 then
    hidingControlsTime = math.min(hidingControlsTime + dt * 10, 1)
    hidingControlsPopup = hidingControlsPopup - dt
  elseif hidingControlsTime > 0 then
    hidingControlsTime = math.max(hidingControlsTime - dt * 2, 0)
  end
  hidingControlsLastTime = time
  return math.smoothstep(hidingControlsTime)
end


local accentColor = rgbm.new('#5BD5F9')
local accentPushedColor = accentColor * 0.8
local roundColor = rgbm.new('#DEE0FF')
local roundPushedColor = roundColor * 0.8

function touchscreen.accentButton(icon, radius, iconSize)
  ui.drawCircleFilled(ui.getCursor() + radius, radius, mouseDown and ui.rectHovered(ui.getCursor(), ui.getCursor() + radius * 2) and accentPushedColor or accentColor, 30)
  return touchscreen.iconButton(icon, radius * 2, rgbm.colors.black, nil, nil, iconSize or 16)
end

function touchscreen.addButton(radius)
  return touchscreen.accentButton(ui.Icons.Plus, radius or 34, 12)
end

function touchscreen.roundButton(icon, radius, iconSize)
  ui.drawCircleFilled(ui.getCursor() + radius, radius, mouseDown and ui.rectHovered(ui.getCursor(), ui.getCursor() + radius * 2) and roundPushedColor or roundColor, 30)
  return touchscreen.iconButton(icon, radius * 2, rgbm.colors.black, nil, nil, iconSize or 16)
end

function touchscreen.listItem(itemSize)
  if not touchscreen.tapped() and not touchscreen.touched() then return end
  local c, r = ui.getCursor(), false
  if touchscreen.tapped() and ui.rectHovered(c, c + itemSize)  then
    r = true
  elseif touchscreen.touched() and ui.rectHovered(c, c + itemSize)  then
    ui.drawRectFilled(c, c + itemSize, rgbm(1, 1, 1, 0.03), 4)
  end
  return r
end

function touchscreen.textButton(label, size)
  local r = touchscreen.listItem(size)
  ui.pushFont(ui.Font.Title)
  ui.pushStyleColor(ui.StyleColor.Text, accentColor)
  ui.textAligned(label, 0.5, size)
  ui.popStyleColor()
  ui.popFont()
  return r
end

function touchscreen.smoothValue(id, target, lag)
  ui.pushID(id)
  local t = ui.loadStoredNumber(0, -1)
  local nt = math.applyLag(t, target, t == -1 and 0 or lag or 0.7, ui.deltaTime())
  if math.abs(nt - t) > 0.001 then
    touchscreen.boostFrameRate()
    ui.storeNumber(0, nt)
  end
  ui.popID()
  return nt
end

local toggleColorBg = rgbm.new('#40484C')
local toggleColorThumb = rgbm.new('#071E25')
local toggleColorBgActive = rgbm.new('#CFE6F0')

function touchscreen.toggle(id, active, size)
  local c, b = ui.getCursor(), active and toggleColorBgActive or toggleColorBg
  ui.drawRectFilled(vec2(c.x + size.y / 2, c.y), vec2(c.x + size.x - size.y / 2, c.y + size.y), b)
  local p, o = vec2(c.x + size.y / 2, c.y + size.y / 2), size.x - size.y
  ui.drawCircleFilled(p, size.y / 2, b, 24)
  p.x = p.x + o
  ui.drawCircleFilled(p, size.y / 2, b, 24)
  p.x = p.x - o * touchscreen.smoothValue(id, active and 0 or 1)
  ui.drawCircleFilled(p, size.y / 2.7, toggleColorThumb, 24)
  if touchscreen.tapped() and ui.rectHovered(c, c + size) then
    return true
  end
end

function touchscreen.tabs(tabs, dt)
  local sw = ui.windowWidth()
  local sh = ui.windowHeight()
  local tabBgColor = tabs.color or rgbm.colors.black
  ui.drawRectFilled(vec2(0, sh - 60), vec2(sw, sh), tabBgColor)

  local selected = tabs.selected or 1
  local itemWidth = sw / #tabs
  local itemPos = vec2(0, sh - 60)
  local sizeIcon = vec2(itemWidth, 40)
  local sizeText = vec2(itemWidth, 50)
  for i = 1, #tabs do
    local tab = tabs[i]
    local s = i == selected
    ui.setCursor(itemPos)
    if s then 
      ui.drawRectFilled(
        itemPos + vec2(itemWidth / 2 - 40, 8), itemPos + vec2(itemWidth / 2 + 40, 32), rgbm.colors.white, 12)
      touchscreen.iconButton(tab.icon, sizeIcon, tabBgColor)
    else
      touchscreen.iconButton(tab.icon, sizeIcon)
    end
    ui.setCursor(itemPos)
    ui.textAligned(tab.name, vec2(0.5, 1), sizeText)
    ui.setCursor(itemPos)
    ui.invisibleButton(tab.name, sizeText)
    if not s and touchscreen.itemTapped() then
      tabs.selectedPrevious = selected
      tabs.selectedTransition = 1
      tabs.selectedTransitionInvert = selected > i
      tabs.selected = i
    end
    itemPos.x = itemPos.x + itemWidth
  end

  local transition = tabs.selectedTransition or 0
  local invert = tabs.selectedTransitionInvert and -1 or 1
  if transition > 0.001 then
    touchscreen.boostFrameRate()
    transition = math.applyLag(transition, 0, 0.85, dt)
    tabs.selectedTransition = transition

    local previous = tabs[tabs.selectedPrevious]
    if previous and previous.fn then
      ui.setCursor(vec2(math.floor((transition - 1) * sw) * invert, 0))
      ui.childWindow('__tabPrevious', vec2(sw, sh - 60), function ()
        previous.fn(dt)
      end)
    end
  end

  local current = tabs[selected]
  if current and current.fn then
    ui.setCursor(vec2(math.floor(transition * sw) * invert, 0))
    ui.childWindow('__tab', vec2(sw, sh - 60), function ()
      current.fn(dt)
    end)
  end
end

function touchscreen.createTransition(lag, initialValue)
  local value = initialValue or 0
  return function (dt, condition)
    value = math.applyLag(value, condition and 1 or 0, lag, dt)
    if value > 0.001 and value < 0.999 then
      touchscreen.boostFrameRate()
    end
    return value
  end
end
