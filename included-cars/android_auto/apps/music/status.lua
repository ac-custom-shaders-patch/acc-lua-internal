local iconBgColor = rgbm(0, 0, 0, 1)

return function (dt)
  system.statusIcon(system.appIcon(), iconBgColor)

  if system.statusButton(ui.Icons.Back, 34) then
    ac.mediaPreviousTrack()
  end

  if system.statusButton(ac.currentlyPlaying().isPlaying and ui.Icons.Pause or ui.Icons.Play, 34) then
    ac.mediaPlayPause()
  end

  if system.statusButton(ui.Icons.Next, 34) then
    ac.mediaNextTrack()
  end
end

