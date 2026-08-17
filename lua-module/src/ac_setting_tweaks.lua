if Sim.isVRConnected and Config:get('MISCELLANEOUS', 'SHOW_DRIVER_AND_HANDS_IN_VR', false) then
  ac.applyLiveConfigEdit('video.ini', '[ASSETTOCORSA]\nHIDE_STEER=0\nHIDE_ARMS=0')
end

if Sim.isVRConnected and Config:get('MISCELLANEOUS', 'ALWAYS_ALLOW_FREE_CAMERA', false) then
  ac.applyLiveConfigEdit('assetto_corsa.ini', '[CAMERA]\nALLOW_FREE_CAMERA=1')
end
