--[[
  Animates driver model using VR controllers. Not a proper IK thing, just a quick approximation. Something to
  work on and improve further later on.

  External scripts can use “shared/vr/grab” library to integrate with this one and override hand state so that
  fingers would wrap around grapped objects properly.
]]

if not ConfigVRTweaks:get('CONTROLLERS_INTEGRATION', 'CONTROLLERS_RIG', false) then
  return
end

local vr = ac.getVR()
if vr == nil then return end

local car = ac.getCar(0)
if car == nil then return end

---@type VRRig.VR
local rig = VRRig.VR(car, vr)

Register('simUpdate', function (dt)
  if Sim.cameraMode == ac.CameraMode.Cockpit and Sim.focusedCar == 0 then
    rig:update(dt)
  end
end)
