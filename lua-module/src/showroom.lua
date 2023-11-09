-- local showroom = ac.findNodes('trackRoot:yes')
-- showroom:findMeshes('?'):setMaterialProperty('ksAmbient', 0.4)
-- showroom:findMeshes('?'):setMaterialProperty('ksDiffuse', 0.4)
-- showroom:findMeshes('?'):setMaterialTexture('txDiffuse', rgbm(1, 0.8, 0.6, 1))

if Sim.isShowroomMode then
  physics.setEngineRPM(0, 0)
  physics.setEngineStallEnabled(0, true)

  Register('core', function (dt)
    if ac.isKeyPressed(ui.KeyIndex.Space) then
      ac.setDriverDoorOpen(0, not ac.getCar(0).isDriverDoorOpen, false)
    end
    if Sim.frame < 30 then
      ac.setCurrentCamera(ac.CameraMode.OnBoardFree)
    end
    if ac.getCar(0).gas > 0.1 then
      physics.setEngineStallEnabled(0, false)
    end
  end)
end
