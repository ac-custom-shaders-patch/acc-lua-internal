ac.ControlButton('__EXT_MUSIC_PLAYPAUSE'):onPressed(function ()
  ac.mediaPlayPause()
end)

ac.ControlButton('__EXT_MUSIC_NEXT'):onPressed(function ()
  ac.mediaNextTrack()
end)

ac.ControlButton('__EXT_MUSIC_PREVIOUS'):onPressed(function ()
  ac.mediaPreviousTrack()
end)

ac.ControlButton('__EXT_QMP_SHOW'):onPressed(function ()
  __util.native('qmp_sendInput', 0)
end)

ac.ControlButton('__EXT_SCREENSHOT_ALT', { keyboard = { key = ui.KeyIndex.F8, alt = true } }):setAlwaysActive(true):onPressed(function ()
  ac.makeScreenshot(nil, {accumulation = false}, nil)
end)

