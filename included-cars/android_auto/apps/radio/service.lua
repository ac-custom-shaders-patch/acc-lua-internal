local delayUntilStop = 0

return function(dt)
  if not RadioAppData or not RadioAppData.lib then
    system.setStatusPriority(0)
    return
  end
  
  local vol = touchscreen.getVolumeIfFresh()
  if vol then
    RadioAppData.lib.setVolume(vol)
  elseif RadioAppData.lib.getVolume() ~= touchscreen.getVolume() then
    touchscreen.setVolume(RadioAppData.lib.getVolume(), true)
    touchscreen.setMuted(false, true)
  end

  if RadioAppData.lib.playing() then
    delayUntilStop = 3
  elseif delayUntilStop > 0 then
    delayUntilStop = delayUntilStop - dt
  end

  local hasAudio = RadioAppData.lib.loaded()
  local playing = delayUntilStop > 0

  system.setStatusPriority(playing and 10 or 0)
  if RadioAppData.lib.current() and playing then
    if RadioAppData.lib.getTitle() then
      system.setNotification(RadioAppData.lib.getArtwork() or system.appIcon(), RadioAppData.lib.getTitle(),
        hasAudio and string.format(RadioAppData.lib.getArtist() and 'Playing: %s by %s' or 'Playing: %s', RadioAppData.lib.getTitle(), RadioAppData.lib.getArtist()) or 'Connecting…')
    else
      system.setNotification(system.appIcon(), RadioAppData.lib.current().name, hasAudio and 'Now playing' or 'Connecting…')
    end
  else
    system.setNotification(nil)
  end
end
