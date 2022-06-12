local delayUntilStop = 0

return function(dt)
  if not RadioAppData or not RadioAppData.mediaPlayer then
    system.setStatusPriority(0)
    return
  end

  if RadioAppData.mediaPlayer:playing() then
    delayUntilStop = 3
  elseif delayUntilStop > 0 then
    delayUntilStop = delayUntilStop - dt
  end

  local hasAudio = RadioAppData.mediaPlayer:hasAudio()
  local playing = delayUntilStop > 0

  system.setStatusPriority(playing and 10 or 0)
  if RadioAppData.selectedStation and playing then
    system.setNotification(system.appIcon(), RadioAppData.selectedStation[1], hasAudio and 'Now playing' or 'Connecting…')
  else
    system.setNotification(nil)
  end
end
