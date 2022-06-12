local clockColor = rgbm.new('#1D333B')
local hourColor = rgbm.new('#7E949D')
local minuteColor = rgbm.new('#B1EBFF')
local secondColor = rgbm.new('#DEE0FF')
local extraColor = rgbm.new('#1C2528')

local btnCol1 = rgbm.new('#1C2528')
local btnCol1H = btnCol1 * 1.6
local btnCol2 = rgbm.new('#97AFB8')
local btnCol2H = btnCol2 * 0.8

local citySearchDelay = 0
local timerInput = {}
local timerInactiveColor = rgbm.new('#555555')
local timerActiveColor = rgbm.new('#5BD5F9')
local timerTotalTime = 0 -- used for progress bar, does grow with +1:00
local timerOriginalTime = timerTotalTime -- used for resetting does not grow with +1:00
local timerTime = timerTotalTime
local timerPaused = false
local timerPauseFlash = false
local timerJustReset = false
local timerServiceInterval
local timerReady = touchscreen.createTransition(0.8)
local timerTransition = touchscreen.createTransition(0.8)
local stopwatchLapsTransition = touchscreen.createTransition(0.8)
local stopwatchTransition = touchscreen.createTransition(0.8)

local stopwatchActive = false
local stopwatchPauseTime = 0
local stopwatchTime = 0
local stopwatchTotalTime = 0
local stopwatchLaps = {}

local function drawClock(pivot, radius, timeTotalSeconds)
  local W = radius * 0.035
  ui.drawCircleFilled(pivot, radius - W, clockColor)
  for i = 1, 12 do
    ui.pathLineTo(pivot)
    for j = -3, 3 do
      local a1 = (i - j/6) / 12 * math.pi * 2
      local s1, c1 = math.sin(a1), math.cos(a1)
      local r = radius + W * math.cos(j * math.pi / 3)
      ui.pathLineTo(pivot + vec2(s1 * r, c1 * r))
    end
    ui.pathFillConvex(clockColor)
  end

  ui.beginRotation()
  ui.drawRectFilled(pivot - 6, pivot + vec2(radius * 0.5, 6), hourColor, 6)
  ui.endPivotRotation(-math.deg(timeTotalSeconds / 60 / 60 / 12 * math.pi * 2) - 180, pivot)

  ui.beginRotation()
  ui.drawRectFilled(pivot - 6, pivot + vec2(radius * 0.7, 6), minuteColor, 6)
  ui.endPivotRotation(-math.deg(timeTotalSeconds / 60 / 60 * math.pi * 2) - 180, pivot)

  ui.beginRotation()
  ui.drawEllipseFilled(pivot + vec2(radius * 0.85), 6, secondColor)
  ui.endPivotRotation(-math.deg(timeTotalSeconds / 60 * math.pi * 2) - 180, pivot)
end

local timeEditingValue, timeEditingStep
local function timeEditingPopup(dt)
  touchscreen.boostFrameRate()

  local p = vec2(ui.windowHeight() / 2, ui.windowHeight() / 2)
  local R = ui.windowHeight() / 2 - 20
  ui.drawCircleFilled(p, R, rgbm.colors.gray, 40)
  ui.pushFont(ui.Font.Title)

  local t = touchscreen.touched() or touchscreen.touchReleased()
  if timeEditingStep == 1 then
    local h = math.floor(timeEditingValue / 60)
    for i = 1, 12 do
      local s, c = math.sin(i / 12 * math.pi * 2), math.cos(i / 12 * math.pi * 2)

      ui.setCursor(p + vec2(R * 0.83 * s - 20, R * 0.83 * -c - 20))
      if h == i then 
        ui.drawCircleFilled(p + vec2(R * 0.83 * s, R * 0.83 * -c), 20, timerActiveColor, 20)
        ui.drawLine(p, p + vec2(R * 0.83 * s, R * 0.83 * -c), timerActiveColor, 2)
        ui.drawCircleFilled(p, 4, timerActiveColor)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.black)
      end
      ui.textAligned(i, 0.5, 40)
      if h == i then ui.popStyleColor() end
      if t and ui.rectHovered(p + vec2(R * 0.83 * s - 20, R * 0.83 * -c - 20), p + vec2(R * 0.83 * s + 20, R * 0.83 * -c + 20)) then
        timeEditingValue = i * 60 + math.floor(timeEditingValue % 60)
        if touchscreen.touchReleased() then timeEditingStep = 2 end
      end

      ui.setCursor(p + vec2(R * 0.54 * s - 20, R * 0.54 * -c - 20))
      if h == (i + 12) % 24 then 
        ui.drawCircleFilled(p + vec2(R * 0.54 * s, R * 0.54 * -c), 20, timerActiveColor, 20)
        ui.drawLine(p, p + vec2(R * 0.54 * s, R * 0.54 * -c), timerActiveColor, 2)
        ui.drawCircleFilled(p, 4, timerActiveColor)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.black)
      end
      ui.textAligned(i == 12 and '00' or i + 12, 0.5, 40)
      if h == (i + 12) % 24 then ui.popStyleColor() end
      if t and ui.rectHovered(p + vec2(R * 0.54 * s - 20, R * 0.54 * -c - 20), p + vec2(R * 0.54 * s + 20, R * 0.54 * -c + 20)) then
        timeEditingValue = ((i + 12) % 24) * 60 + math.floor(timeEditingValue % 60)
        if touchscreen.touchReleased() then timeEditingStep = 2 end
      end
    end
  else
    local h = math.floor((timeEditingValue % 60) / 5) * 5
    for i = 0, 55, 5 do
      local s, c = math.sin(i / 60 * math.pi * 2), math.cos(i / 60 * math.pi * 2)

      ui.setCursor(p + vec2(R * 0.8 * s - 20, R * 0.8 * -c - 20))
      if h == i then 
        ui.drawCircleFilled(p + vec2(R * 0.8 * s, R * 0.8 * -c), 20, timerActiveColor, 20)
        ui.drawLine(p, p + vec2(R * 0.8 * s, R * 0.8 * -c), timerActiveColor, 2)
        ui.drawCircleFilled(p, 4, timerActiveColor)
        ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.black)
      end
      ui.textAligned(string.format('%02d', i), 0.5, 40)
      if h == i then ui.popStyleColor() end
      if t and ui.rectHovered(p + vec2(R * 0.8 * s - 20, R * 0.8 * -c - 20), p + vec2(R * 0.8 * s + 20, R * 0.8 * -c + 20)) then
        timeEditingValue = math.floor(timeEditingValue / 60) * 60 + i
        if touchscreen.touchReleased() then system.closePopup(nil, timeEditingValue) end
      end
    end
  end

  ui.popFont()
  
  ui.setCursor(ui.windowSize() - vec2(98, 100))
  if touchscreen.textButton('OK', vec2(80, 40)) then system.closePopup(nil, timeEditingValue) end
  ui.setCursor(ui.windowSize() - vec2(98, 60))
  if touchscreen.textButton('Cancel', vec2(80, 40)) then system.closePopup(nil) end
end

local function stopwatchFormatTime(time, detailed)
  if stopwatchTotalTime < 60 then
    return detailed and string.format('%02.2f', time) or string.format('%02.0f', math.floor(time))
  elseif stopwatchTotalTime < 10 * 60 then
    return string.format('%2.0f:%02.0f', math.floor(time / 60), math.floor(time % 60))
  elseif stopwatchTotalTime < 60 * 60 then
    return string.format('%2.0f:%02.0f', math.floor(time / 60), math.floor(time % 60))
  elseif stopwatchTotalTime < 10 * 60 * 60 then
    ui.offsetCursorX(-4)
    return string.format('%2.0f:%02.0f:%02.0f', math.floor(time / 3600), math.floor(time / 60 % 60), math.floor(time % 60))
  else
    return string.format('%2.0f:%02.0f:%02.0f', math.floor(time / 3600), math.floor(time / 60 % 60), math.floor(time % 60))
  end
end

local tabs = {
  {
    name = 'Alarm',
    icon = ClockIcons.Alarm,
    fn = function()
      local wh, ww = ui.windowHeight(), ui.windowWidth()
      local alarmActive = ClockStored.alarmActive
      local color = alarmActive and rgbm.colors.white or rgbm(1, 1, 1, 0.5)
      ui.offsetCursorX(48)
      ui.offsetCursorY(48)
      ui.pushFont(ui.Font.Title)
      ui.icon(ClockIcons.Bed, 24)
      ui.sameLine(0, 8)
      ui.text('Wake up')
      ui.popFont()
      ui.drawRectFilled(vec2(40, 90), vec2(ww - 220, 90 + 130), extraColor, 28)
      ui.setCursor(vec2(80, 92))
      if alarmActive then ui.pushDWriteFont(ui.DWriteFont('Segoe UI'):weight(ui.DWriteFont.Weight.Bold)) end
      ui.dwriteText(string.format('%02.0f:%02.0f', math.floor(ClockStored.alarmTime / 60), ClockStored.alarmTime % 60), 58, color)
      if touchscreen.itemTapped() then
        timeEditingValue, timeEditingStep = ClockStored.alarmTime, 1
        system.openCompactPopup('Set time', vec2(ui.windowHeight() + 80, ui.windowHeight() - 20), timeEditingPopup, function (result)
          if result then
            ClockStored.alarmTime = result
            ClockStored.alarmActive = true
          end
        end)
      end
      if alarmActive then ui.popDWriteFont() end
      ui.setCursor(vec2(80, 180))
      ui.dwriteText('Every day', 16, color)
      ui.setCursor(vec2(ww - 340, 170))
      if touchscreen.toggle('alarm', alarmActive, vec2(80, 40)) then ClockStored.alarmActive = not alarmActive end
    end
  },
  {
    name = 'Clock',
    icon = ClockIcons.Clock,
    fn = function()
      local wh = ui.windowHeight()
      local p = vec2(wh / 2 + 80, wh / 2)
      local R = wh * 0.3
      drawClock(p, R, sim.timeTotalSeconds)
      ui.setCursor(p + vec2(-R, R))
      ui.pushFont(ui.Font.Title)
      ui.textAligned(os.dateGlobal('%a, %b %d', sim.timestamp), 0.5, vec2(R * 2, 40))
      ui.popFont()

      ui.drawRectFilled(p + vec2(R * 2, -R), p + vec2(R * 5, R), extraColor, 20)
      ui.beginScale()
      local time = os.date("*t", os.time())
      drawClock(p + vec2(R * 2.75, -R * 0.25), R, time.hour * 3600 + time.min * 60 + time.sec)
      ui.endScale(0.5)
      ui.pushFont(ui.Font.Title)
      ui.drawText(os.date('%a, %b %d', os.time()), p + vec2(R * 2.25, R * 0.3), rgbm.colors.white)
      ui.popFont()
      ui.drawText('System time', p + vec2(R * 2.25, R * 0.65), rgbm.colors.gray)

      ui.setCursor(vec2(ui.windowWidth() - 200, wh / 2 - 17))
      if touchscreen.addButton() then
        system.openInputPopup('Search for a city', '', function (dt, value, changed)
          if changed then
            citySearchDelay = math.random()
          end
          if citySearchDelay > 0 then
            citySearchDelay = citySearchDelay - dt
            ui.offsetCursor(ui.availableSpace() / 2 - 30)
            touchscreen.loading(60)
          elseif #value > 0 then
            ui.textAligned('No cities found', 0.5, ui.availableSpace())
          else
            ui.offsetCursor(ui.availableSpace() / 2 - vec2(12, 40))
            ui.icon(ui.Icons.Search, 24)
            ui.textAligned('Search for a city', vec2(0.5, 0), ui.availableSpace())
          end
        end)
      end
    end
  },
  {
    name = 'Timer',
    icon = ClockIcons.Timer,
    fn = function(dt)
      local wh = ui.windowHeight()

      local transition = timerTransition(dt, timerTime > 0 and 1)
      if transition > 0.001 then
        ui.pushStyleVarAlpha(transition)
        ui.offsetCursorX(math.floor(200 * (1 - transition)))
        ui.childWindow('timerCounting', ui.windowSize(), function ()
          local sh, sw = ui.windowHeight(), ui.windowWidth()
          ui.drawRectFilled(0, vec2(sw, sh), system.bgColor)

          if not timerPauseFlash or timerJustReset then
            local th = math.floor(timerTime / (60*60))
            local tm = math.floor(timerTime / 60 % 60)
            local ts = timerTime % 60
            if th ~= 0 then
              ui.dwriteTextAligned(string.format('%02.0f:%02.0f:%02.0f', th, tm, ts), 40, ui.Alignment.Center, ui.Alignment.Center, vec2(sw, sh))
            elseif tm ~= 0 then
              ui.dwriteTextAligned(string.format('%02.0f:%02.0f', tm, ts), 60, ui.Alignment.Center, ui.Alignment.Center, vec2(sw, sh))
            else
              ui.dwriteTextAligned(string.format('%02.1f', ts), 60, ui.Alignment.Center, ui.Alignment.Center, vec2(sw, sh))
            end
          end

          if not timerJustReset then
            ui.setCursor(vec2(sw / 2 - 200, sh / 2))
            ui.pushStyleColor(ui.StyleColor.Text, timerActiveColor)
            ui.textAligned(timerPaused and 'Reset' or '+1:00', 0.5, vec2(400, 120))
            if touchscreen.itemTapped() then
              timerTime = timerPaused and timerOriginalTime or timerTime + 60
              timerTotalTime = timerPaused and timerOriginalTime or timerTotalTime + 60
              timerJustReset = timerPaused
            end
            ui.popStyleColor()
          end

          local a = math.pi * 2 * timerTime / timerTotalTime
          ui.drawCircle(vec2(sw / 2, sh / 2), sh * 0.4, timerInactiveColor, 60, 8)
          ui.pathArcTo(vec2(sw / 2, sh / 2), sh * 0.4, -math.pi / 2, -math.pi / 2 + a, 60)
          ui.pathStroke(timerActiveColor, false, 8)

          ui.drawCircleFilled(vec2(sw / 2, sh / 2 - sh * 0.4), 4, timerActiveColor)
          local s, c = math.sin(a), math.cos(a)
          ui.drawCircleFilled(vec2(sw / 2 + sh * 0.4 * s, sh / 2 - sh * 0.4 * c), 4, timerActiveColor)

          ui.setCursor(vec2(680, sh / 2 - 17))
          if touchscreen.accentButton(timerPaused and ui.Icons.Play or ui.Icons.Pause, 34) then
            if timerPaused then 
              clearInterval(timerPaused)
              timerPaused, timerPauseFlash, timerJustReset = nil, false, false
            else
              timerPaused = setInterval(function () timerPauseFlash = not timerPauseFlash end, 0.5)
            end
          end

          ui.setCursor(vec2(680+6, sh / 2 - 17 + 80))
          if touchscreen.roundButton(ui.Icons.Delete, 28) then
            timerTime = 0
            timerJustReset = false
            timerPaused = false
            timerPauseFlash = false
            clearInterval(timerServiceInterval)
            StatusTimerTime = nil
            system.setNotification(nil)
            system.setStatusPriority(0)
          end

        end)
        ui.popStyleVar()

        if transition > 0.999 then
          return
        end
      end

      local ready = timerReady(dt, #timerInput > 0)
      local textColor = math.lerp(rgbm.colors.white, timerActiveColor, ready)
      ui.setCursor(vec2(100, wh / 2 - 40))
      ui.dwriteText(string.format('%s%s  %s%s  %s%s',
        timerInput[6] or 0, timerInput[5] or 0, 
        timerInput[4] or 0, timerInput[3] or 0, 
        timerInput[2] or 0, timerInput[1] or 0), 60,
        textColor)
      ui.setCursor(vec2(165, wh / 2 + 3))
      ui.dwriteText('h', 20, textColor)
      ui.sameLine(0, 85)
      ui.dwriteText('m', 20, textColor)
      ui.sameLine(0, 80)
      ui.dwriteText('s', 20, textColor)

      local btnR = wh < 280 and 24 or 28
      local rowY = wh < 280 and 52 or 60
      local startY = wh < 260 and 50 or 70
      local p = vec2(460, startY)
      for i = 1, 12 do
        local h = touchscreen.touched() and ui.rectHovered(p - 28, p + 28)
        if touchscreen.tapped() and ui.rectHovered(p - 28, p + 28) then
          if i == 12 then table.remove(timerInput, 1)
          elseif #timerInput < 6 and (#timerInput > 0 or i < 10) then
            table.insert(timerInput, 1, i >= 10 and 0 or i)
            if i == 10 then table.insert(timerInput, 1, 0) end
          end
        end
        ui.drawCircleFilled(p, btnR, h and (i == 12 and btnCol2H or btnCol1H) or i == 12 and btnCol2 or btnCol1, 20)
        if i % 3 == 0 then p.x, p.y = p.x - 160, p.y + rowY
        else p.x = p.x + 80 end
      end

      p.x, p.y = 460-btnR, startY-btnR-3
      for i = 1, 12 do
        ui.setCursor(p)
        if i < 12 then
          ui.dwriteTextAligned(i == 10 and '00' or i == 11 and '0' or i, 40, ui.Alignment.Center, ui.Alignment.Center, btnR * 2)
        else
          ui.offsetCursorY(3)
          ui.icon(ui.Icons.Backspace, btnR * 2, rgbm.colors.black, 24)
        end
        if i % 3 == 0 then p.x, p.y = p.x - 160, p.y + rowY
        else p.x = p.x + 80 end
      end

      if ready > 0.001 then
        ui.beginScale()
        ui.setCursor(vec2(680, wh / 2 - 17))
        if touchscreen.accentButton(ui.Icons.Play, 34) then
          timerTime = ((timerInput[6] or 0) * 10 + (timerInput[5] or 0)) * 3600
            + ((timerInput[4] or 0) * 10 + (timerInput[3] or 0)) * 60
            + ((timerInput[2] or 0) * 10 + (timerInput[1] or 0))
          timerTotalTime = timerTime
          timerOriginalTime = timerTime
          clearInterval(timerServiceInterval)
          system.setStatusPriority(10)
          timerServiceInterval = setInterval(function ()
            if not timerPaused then
              timerTime = timerTime - dt
              if timerTime < 0 then
                clearInterval(timerServiceInterval)
                
                local th = math.floor(timerTotalTime / (60*60))
                local tm = math.floor(timerTotalTime / 60 % 60)
                local ts = timerTotalTime % 60
                system.setNotification(ClockIcons.Timer, 'Timer is finished',
                  string.format('Total time: %02.0f:%02.0f:%02.0f', th, tm, ts))
                StatusTimerTime = nil
                system.setStatusPriority(0)
              else
                local th = math.floor(timerTime / (60*60))
                local tm = math.floor(timerTime / 60 % 60)
                local ts = timerTime % 60
                system.setNotification(ClockIcons.Timer, 'Timer is ticking',
                  string.format('Time left: %02.0f:%02.0f:%02.0f', th, tm, ts), true)
                StatusTimerTime = timerTime
              end
            else
              local th = math.floor(timerTime / (60*60))
              local tm = math.floor(timerTime / 60 % 60)
              local ts = timerTime % 60
              system.setNotification(ClockIcons.Timer, 'Timer is paused',
                string.format('Time left: %02.0f:%02.0f:%02.0f', th, tm, ts), true)
            end
          end, 0)
          table.clear(timerInput)
        end
        ui.endScale(ready)
      end
    end
  },
  {
    name = 'Stopwatch',
    icon = ClockIcons.Stopwatch,
    fn = function(dt)
      local wh, ww = ui.windowHeight(), ui.windowWidth()

      local active = stopwatchTransition(dt, stopwatchTime > 0)
      local lapsActive = stopwatchLapsTransition(dt, #stopwatchLaps > 0)

      local p = vec2(ww / 2 - 100 - lapsActive * 120, wh / 2 + 30)
      ui.drawCircle(p, wh / 4, timerInactiveColor, 40, 4)

      if #stopwatchLaps > 0 then        
        local a = math.pi * 2 * stopwatchTime / stopwatchLaps[1].time
        if a >= math.pi * 2 then
          ui.drawCircle(p, wh / 4, timerActiveColor, 40, 4)
        else
          ui.pathArcTo(p, wh / 4, -math.pi / 2, -math.pi / 2 + a, 40)
          ui.pathStroke(timerActiveColor, false, 4)
  
          ui.drawCircleFilled(vec2(p.x, p.y - wh / 4), 2, timerActiveColor)
          local s, c = math.sin(a), math.cos(a)
          ui.drawCircleFilled(vec2(p.x + wh / 4 * s, p.y - wh / 4 * c), 2, timerActiveColor)
        end
      end

      if stopwatchTime == 0 or stopwatchActive or (ui.time() - stopwatchPauseTime) % 1.4 < 0.7 then
        ui.setCursor(p - wh / 4)
        local fmt = stopwatchFormatTime(stopwatchTime)
        if stopwatchTime < 60 then
          ui.dwriteTextAligned(fmt, 60, ui.Alignment.Center, ui.Alignment.End, vec2(wh / 2, wh / 4 + 16), false)
          ui.setCursor(p + vec2(0, 0))
        elseif stopwatchTime < 10 * 60 then
          ui.dwriteTextAligned(fmt, 55, ui.Alignment.Center, ui.Alignment.End, vec2(wh / 2, wh / 4 + 16), false)
          ui.setCursor(p + vec2(18, 0))
        elseif stopwatchTime < 60 * 60 then
          ui.dwriteTextAligned(fmt, 50, ui.Alignment.Center, ui.Alignment.End, vec2(wh / 2, wh / 4 + 16), false)
          ui.setCursor(p + vec2(20, 0))
        elseif stopwatchTime < 10 * 60 * 60 then
          ui.offsetCursorX(-4)
          ui.dwriteTextAligned(fmt, 38, ui.Alignment.Center, ui.Alignment.End, vec2(wh / 2, wh / 4 + 16), false)
          ui.setCursor(p + vec2(20, 0))
        else
          ui.dwriteTextAligned(fmt, 35, ui.Alignment.Center, ui.Alignment.End, vec2(wh / 2, wh / 4 + 16), false)
          ui.setCursor(p + vec2(20, 0))
        end
        ui.dwriteText(string.format('%02.0f', math.floor(stopwatchTime % 1 * 100)), 30)
      end

      if lapsActive > 0.001 then
        ui.setCursor(vec2(ww / 2 - 100 + 80, 0))
        ui.childWindow('clockSWLaps', vec2(200, wh), function ()
          ui.offsetCursorY(wh / 2)
          for i = #stopwatchLaps, 1, -1 do
            local l = stopwatchLaps[i]
            ui.text(string.format('# %d     %s     %s', i, stopwatchFormatTime(l.time, true), stopwatchFormatTime(l.total, true)))
          end
          ui.offsetCursorY(wh / 2)
          touchscreen.scrolling()
        end)
      end

      ui.setCursor(vec2(ww - 160 - 3 * active, wh / 2 - 17 - 3 * active))
      if touchscreen.accentButton(stopwatchActive and ui.Icons.Pause or ui.Icons.Play, 34 + 3 * active) then
        if stopwatchActive then 
          clearInterval(stopwatchActive)
          stopwatchActive = false
          stopwatchPauseTime = ui.time()
        else
          stopwatchActive = setInterval(function () 
            stopwatchTime = stopwatchTime + ui.deltaTime()
            stopwatchTotalTime = stopwatchTotalTime + ui.deltaTime()
          end, 0)
        end
      end

      if active > 0.001 then
        ui.setCursor(vec2(ww - 160 + 6, wh / 2 - 17 + 80))
        ui.beginScale()
        if touchscreen.roundButton(ui.Icons.Restart, 28) then
          if stopwatchActive or stopwatchTime > 0 then
            clearInterval(stopwatchActive)
            stopwatchActive = false
            stopwatchTime = 0
            stopwatchTotalTime = 0
            table.clear(stopwatchLaps)
          end
        end
        ui.endScale(active)

        ui.setCursor(vec2(ww - 160 + 6, wh / 2 - 17 - 68))
        ui.beginScale()
        if touchscreen.roundButton(ui.Icons.Clock, 28) then
          if stopwatchActive then
            table.insert(stopwatchLaps, { time = stopwatchTime, total = stopwatchTotalTime })
            stopwatchTime = 0
          end
        end
        ui.endScale(active)
      end
    end
  },

  selected = 1,
  color = rgbm.new('#1E2B2F')
}

return function (dt)
  touchscreen.tabs(tabs, dt)
end
