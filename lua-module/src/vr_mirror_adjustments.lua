--[[
  Allows to adjust mirrors in VR by simply grabbing them. Activates on in VR Tweaks settings.
]]

if not Sim.isVRConnected then
  return
end

if not ConfigVRTweaks or not ConfigVRTweaks:get('CONTROLLERS_INTEGRATION', 'INTERACT_WITH_MIRRORS', true) then
  return
end

local vr = ac.getVR()
if not vr then return end

local aabbMin = vec3()
local aabbMax = vec3()

local function getHeldMirror(handPos)
  local count = ac.getRealMirrorCount()
  for j = 0, count - 1 do
    if ac.getRealMirrorAABB(j, aabbMin, aabbMax) then
      if handPos.x > aabbMin.x and handPos.x < aabbMax.x
        and handPos.y > aabbMin.y - 0.05 and handPos.y < aabbMax.y + 0.05
        and handPos.z > aabbMin.z - 0.1 and handPos.z < aabbMax.z + 0.1 then
        return j
      end
    end
  end
  return -1
end

local function isMirrorStillHeld(mirror, handPos)
  if ac.getRealMirrorAABB(mirror, aabbMin, aabbMax) then
    if handPos.x > aabbMin.x - 0.1 and handPos.x < aabbMax.x + 0.1
      and handPos.y > aabbMin.y - 0.1 and handPos.y < aabbMax.y + 0.1
      and handPos.z > aabbMin.z - 0.1 and handPos.z < aabbMax.z + 0.1 then
      return true
    end
  end
  return false
end

local mirrorHeld = {}
local startingPos = {}
local startingParams = {} ---@type ac.RealMirrorParams[]
local drawMirrorOverlay = Toggle.Draw3D()

local function vrMirror(hand)
  local held = mirrorHeld[hand]

  if vr.hands[hand].triggerHand < 0.5 then
    if held then
      mirrorHeld[hand] = nil
      ac.setVRHandBusy(hand, false)
      drawMirrorOverlay(false)
    end
    return
  end

  local handPos = Car.worldToLocal:transformPoint(vr.hands[hand].transform.position)
  if not held then
    held = getHeldMirror(handPos)
    mirrorHeld[hand] = held
    if held ~= -1 then
      startingPos[hand] = handPos
      startingParams[hand] = ac.getRealMirrorParams(held)
      ac.setVRHandBusy(hand, true)
      ac.setVRHandVibration(hand, 0, 0.1)
      drawMirrorOverlay(true)
    end
  end

  if held ~= -1 then
    local delta = handPos - startingPos[hand] ---@type vec3
    local newParams = startingParams[hand]:clone()
    if isMirrorStillHeld(held, handPos) then
      newParams.rotation.x = newParams.rotation.x + delta.x * 4
      newParams.rotation.y = newParams.rotation.y + delta.y * 4
      ac.setRealMirrorParams(held, newParams)
    else
      mirrorHeld[hand] = -1
      ac.setVRHandBusy(hand, false)
      drawMirrorOverlay(false)
    end
  end
end

local highlightColor = rgbm(0, 3, 3, 0.08)

Register('draw3D', function()
  for i = 0, 1 do
    if mirrorHeld[i] and ac.getRealMirrorAABB(mirrorHeld[i], aabbMin, aabbMax) then
      render.setBlendMode(render.BlendMode.AlphaBlend)
      render.setCullMode(render.CullMode.None)
      render.setDepthMode(render.DepthMode.Off)
      render.rectangle(Car.bodyTransform:transformPoint((aabbMin + aabbMax) / 2), Car.look, 
        aabbMax.x - aabbMin.x + 0.03, aabbMax.y - aabbMin.y + 0.03, highlightColor)
    end
  end
end)

Register('core', function (dt)
  if Sim.cameraMode ~= ac.CameraMode.Cockpit or Sim.focusedCar ~= 0 then
    if mirrorHeld[0] or mirrorHeld[1] then
      ac.setVRHandBusy(0, false)
      ac.setVRHandBusy(1, false)
      drawMirrorOverlay(false)
      mirrorHeld = {}
    end
    return
  end

  for i = 0, 1 do
    if vr.hands[i].active then
      vrMirror(i)
    elseif mirrorHeld[i] then
      mirrorHeld[i] = nil
      ac.setVRHandBusy(i, false)
      drawMirrorOverlay(false)
    end
  end
end)
