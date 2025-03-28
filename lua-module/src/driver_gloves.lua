if Sim.isVRConnected and Config:get('MISCELLANEOUS', 'HIDE_DRIVER_SUIT', false) then
  local car = ac.findNodes('carRoot:0')
  local suit = car:findSkinnedMeshes('material:RT_DriverSuit')
  car:findSkinnedMeshes('material:RT_Gloves'):applyShaderReplacements('CULL_MODE=NONE')
  local hidden = false
  setInterval(function ()
    local shouldBeHidden = Sim.cameraMode == ac.CameraMode.Cockpit
    if shouldBeHidden ~= hidden then
      hidden = shouldBeHidden
      suit:setVisible(not shouldBeHidden)
    end
  end)
  ac.onRelease(function ()
    suit:setVisible(true)
  end)
end
