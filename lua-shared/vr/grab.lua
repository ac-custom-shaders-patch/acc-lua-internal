--[[
  This small library can be used to overwrite finger angles and hand position in VR with driver
  animation enabled, for example, to get fingers to wrap around grabbed object, or, if, for example,
  a gun is shooting, to add a bit of kickback for the hand.

  To use, include with `local vrGrab = require('shared/vr/grab')` and then call `vrGrab.fingers()`
  to override finger angles for the next couple of frames, or `vrGrab.hand()` to override hand position.
]]

---@type table
local data = ac.connect([[
  int fingerOverrideActive[2];
  float fingerInAngles[30];
  float fingerOutAngles[30];
  int handOverrideActive[2];
  mat4x4 handTransform[2];  
]], false, ac.SharedNamespace.Shared)

local vrGrab = {}

---Overrides finger angles for a given hand.
---@param hand integer @Either 0 for left hand, or 1 for right hand.
---@param callback fun(finger: integer, bit: integer, currentAngle: number): number @Callback called for each bit of each finger (each finger has three bits). Indices are 0-based. Angles are in radians.
---@param frames integer @For how many frames keep current angles. Default value: 2.
function vrGrab.fingers(hand, callback, frames)
  if not callback then
    data.fingerOverrideActive[hand] = 0
    return
  end
  data.fingerOverrideActive[hand] = frames or 2
  for finger = 0, 4 do
    for bit = 0, 2 do
      local i = hand * 15 + finger * 3 + bit
      data.fingerOutAngles[i] = callback(finger, bit, data.fingerInAngles[i]) or data.fingerInAngles[i]
    end
  end
end

---Overrides certain hand transformation.
---@param hand integer @Either 0 for left hand, or 1 for right hand.
---@param transform mat4x4 @New transformation matrix.
function vrGrab.hand(hand, transform)
  data.handOverrideActive[hand] = transform and 2 or 0
  if transform then data.handTransform[hand] = transform end
end

return vrGrab
