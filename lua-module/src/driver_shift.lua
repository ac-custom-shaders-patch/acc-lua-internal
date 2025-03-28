--[[
  Allows to shift driver weight using hotkeys, TrackIR or VR. Only for cars with explicitly specified shift range.
]]

local weightShift = ac.DriverWeightShift(0)
if not weightShift then return end

local btn0 = ac.ControlButton('__EXT_DRIVER_SHIFT_LEFT')
local btn1 = ac.ControlButton('__EXT_DRIVER_SHIFT_RIGHT')
if not btn0:configured() and not btn1:configured() and not Sim.isVRMode then
  return
end

local vr = Sim.isVRMode and ac.getVR()
local trackIR = not vr and ac.getTrackIR()

local btnShift = 0
local appliedValue = 0
Register('gameplay', function (dt)
  local target = 0  
  if btn0:down() then target = target + weightShift.range end
  if btn1:down() then target = target - weightShift.range end
  btnShift = math.applyLag(btnShift, target, 0.92, dt)

  local finalValue = btnShift
  if vr and Car.focusedOnInterior then
    finalValue = finalValue + Car.worldToLocal:transformPoint(vr.headTransform.position).x - Car.driverEyesPosition.x
  elseif trackIR then
    finalValue = finalValue + trackIR.position.x
  end

  if math.abs(finalValue - appliedValue) > 0.001 then
    weightShift.input = finalValue
    appliedValue = finalValue
  end
end)
