--[[
  Animates driver model using VR controllers. Not a proper IK thing, just a quick approximation. Something to
  work on and improve further later on.

  External scripts can use “shared/vr/grab” library to integrate with this one and override hand state so that
  fingers would wrap around grapped objects properly.
]]

VRRIG_DEBUG_MODE = false
if VRRIG_DEBUG_MODE then 
  ac.warn('VR RIG: DEBUG MODE')
  local car = ac.getCar(0) or error()
  local state = {
    headActive = true,
    hands = {
      [0] = { active = true, transform = mat4x4(), triggerHand = 0, triggerIndex = 0, thumbUp = false, indexPointing = false},
      [1] = { active = true, transform = mat4x4(), triggerHand = 0, triggerIndex = 0, thumbUp = false, indexPointing = false}
    }
  }
  setInterval(function ()
    if not ac.isKeyDown(ui.KeyIndex.Space) then
      for i = 0, 1 do
        -- state.hands[i].active = false
        state.hands[i].triggerHand = 0
        state.hands[i].triggerIndex = 0
        state.hands[i].thumbUp = false
        state.hands[i].indexPointing = false
      end
      return
    end
    state.hands[0].triggerIndex = math.sin(os.preciseClock() * 3.7) * 0.5 + 0.5
    state.hands[0].triggerHand = math.sin(os.preciseClock() * 1.7) * 0.5 + 0.5
    state.hands[1].thumbUp = math.sin(os.preciseClock() * 12.5) > 0
    state.hands[1].indexPointing = math.sin(os.preciseClock() * 12.7) > 0
    mat4x4.rotation(math.pi, vec3(0, 1, 0))
      :mul(mat4x4.translation(car.driverEyesPosition + vec3(math.sin(os.preciseClock() * 2.7) * 0.2 + 0.3, -0.05, 0.5)))
      :mulTo(state.hands[0].transform, car.bodyTransform)
    mat4x4.rotation(math.pi, vec3(0, 1, 0))
      :mul(mat4x4.translation(car.driverEyesPosition + vec3(math.sin(os.preciseClock() * 3.1) * 0.2 - 0.3, -0.05, 0.5)))
      :mulTo(state.hands[1].transform, car.bodyTransform)
  end)
  function ac.getVR()
    return state
  end
end

if not ConfigVRTweaks or not ConfigVRTweaks:get('CONTROLLERS_INTEGRATION', 'CONTROLLERS_RIG', false) and not VRRIG_DEBUG_MODE then
  return
end

local vr = ac.getVR()
if vr == nil then return end 

---@type VRRig.VR
local rig = VRRig.VR(Car, vr)

Register('simUpdate', function (dt)
  if Sim.cameraMode == ac.CameraMode.Cockpit and Sim.focusedCar == 0 or VRRIG_DEBUG_MODE then
    rig:update(dt)
  end
end)

