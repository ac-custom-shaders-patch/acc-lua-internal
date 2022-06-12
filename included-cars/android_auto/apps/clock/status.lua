return function (dt)
  system.statusIcon(rgbm.colors.white)
  if not StatusTimerTime then
    system.setStatusPriority(0)
    return false
  end

  local th = math.floor(StatusTimerTime / (60*60))
  local tm = math.floor(StatusTimerTime / 60 % 60)
  local ts = StatusTimerTime % 60
  ui.sameLine(0, 0)
  ui.textAligned(string.format('Time left: %02.0f:%02.0f:%02.0f', th, tm, ts), 0.5, ui.availableSpace())
end