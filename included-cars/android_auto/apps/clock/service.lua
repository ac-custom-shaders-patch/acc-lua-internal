-- shared stuff:
ClockIcons = ui.atlasIcons(io.relative('clock_icons.png'), 4, 2, {
  Alarm = {1, 1},
  Clock = {1, 2},
  Timer = {1, 3},
  Stopwatch = {1, 4},
  Bed = {2, 1}
})

ClockStored = ac.storage({
  alarmTime = 7.5 * 60,
  alarmActive = false
}, 'clock')

local lastTime = -1

return function ()
  if not ClockStored.alarmActive then return end

  local alarmTime = ClockStored.alarmTime * 60
  if lastTime ~= -1 and lastTime < alarmTime and sim.timeTotalSeconds >= alarmTime and sim.timeTotalSeconds < alarmTime + 3600 then
    local time = string.format('%02.0f:%02.0f', math.floor(ClockStored.alarmTime / 60), ClockStored.alarmTime % 60)
    system.openPopup('', function ()
      ui.offsetCursorY(-40)
      ui.dwriteTextAligned(time, 60, ui.Alignment.Center, ui.Alignment.Center, vec2(ui.availableSpaceX(), 80))
      ui.dwriteTextAligned('Alarm', 20, ui.Alignment.Center, ui.Alignment.Center, vec2(ui.availableSpaceX(), 30))
      ui.offsetCursorX(ui.availableSpaceX() / 2 - 40)
      ui.offsetCursorY(40)
      if touchscreen.roundButton(ui.Icons.Confirm, 40, 16) then
        system.closePopup(nil)
      end
    end)
    -- system.setNotification(ClockIcons.Alarm, string.format('%02.0f:%02.0f', math.floor(ClockStored.alarmTime / 60), ClockStored.alarmTime % 60), 'Alarm')
  end
  lastTime = sim.timeTotalSeconds
end
