if ConfigGeneral:get('DEV', 'FMOD_LOGGING', false) then
  local hotkey = ac.ControlButton('csp.module/Dump FMOD log',
    { keyboard = { ctrl = true, alt = true, key = ui.KeyIndex.F } })
  local savingNow = false
  hotkey:onPressed(function()
    if savingNow then return end
    savingNow = true;
    ac.log('Saving FMOD log…')
    __util.native('fmod.write', 'SAVING FMOD LOG')
    local filename = ac.getFolder(ac.FolderID.Logs) .. ('/fmod_%s.log' % os.time())
    ui.toast(ui.Icons.VolumeHigh, 'Saving FMOD log for the next 5 seconds…###fmod_log')
    __util.native('fmod.dump', filename, 5, function()
      ui.toast(ui.Icons.VolumeHigh, 'FMOD log saved###fmod_log'):button(ui.Icons.File, 'View in Explorer', function()
        os.showInExplorer(filename)
      end)
      savingNow = false
    end)
  end)

  local peakReady = __util.native('fmod.peak.enable')
  local numChannels = -1
  ac.log('Enabling FMOD peak:', peakReady)

  ui.addSettings({ icon = ui.Icons.Settings, name = 'FMOD logger', size = { automatic = true } }, function()
    hotkey:control(vec2(200, 40))
    ui.text(peakReady and 'FMOD peak is accessible' or 'Failed to access FMOD peak')
    if peakReady then
      ui.text('FMOD output channels: ' .. numChannels)
    end
    ui.text('Use extra tools menu in Object Inspector to access log live')
    ui.text('Use Lua Debug App (CSP Module section) to track FMOD peaks with graphs')
  end)

  setInterval(function()
    numChannels = __util.native('fmod.peak.numchannels')
    local peakValues = { __util.native('fmod.peak.get') }
    ac.debug('FMOD.log.channels', numChannels)
    local maxPeak = 0
    for i = 1, #peakValues do
      ac.debug('FMOD.log.peak.' .. i, peakValues[i], nil, nil, 20, ac.DebugCollectMode.Maximum)
      maxPeak = math.max(maxPeak, peakValues[i])
    end
    __util.native('fmod.write', 'Peak: %s' % maxPeak)
  end)
end
