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

local sim = ac.getSim()
local car = ac.getCar(0)

local rig = {}
rig.overrideFingersAngle = {[0] = nil, [1] = nil}
rig.overrideHandTransform = {[0] = nil, [1] = nil}

local function defaultOverrideTransform(hand, v) return v end

---@param out mat4x4
---@param m1 mat4x4
---@param m2 mat4x4
local function lerpMat4x4(out, m1, m2, blend)
  out.row1:setLerp(m1.row1, m2.row1, blend)
  out.row2:setLerp(m1.row2, m2.row2, blend)
  out.row3:setLerp(m1.row3, m2.row3, blend)
  out.row4:setLerp(m1.row4, m2.row4, blend)
end

---@param ref ac.SceneReference
---@param point vec3
---@param dirUp vec3
local function setLookAt(ref, point, dirUp, side, blend)
  local m = ref:getTransformationRaw()
  local p = point - m.position
  if side == 0 then dirUp = -dirUp end
  
  local me = blend < 0.999 and m:clone() or m
  me.up:setScaled(p, -1):normalize()
  me.look:setCrossNormalized(dirUp, -p)
  me.side:setCrossNormalized(p, me.look)
  if blend < 0.999 then
    lerpMat4x4(m, m, me, blend)
  end
  return m
end

---@class DriverFinger
local DriverFinger = class('DriverFinger')

---@param root ac.SceneReference
function DriverFinger:initialize(root, index, hand)
  self.root = root
  self.index = index
  self.hand = hand
  self.second = root:getChild()
  self.third = self.second:getChild()
  self.axis = vec3(0, index == 3 and -0.3 or index * -0.05, 1)
  self.baseOffset = index == 2 and 0.7 or index * 0.2
end

---@type table
local vrRigOverride = ac.connect([[
  int fingerOverrideActive[2];
  float fingerInAngles[30];
  float fingerOutAngles[30];
  int handOverrideActive[2];
  mat4x4 handTransform[2];  
]], false, ac.SharedNamespace.Shared)

local function fingerOverride(hand, finger, bit, v)
  if vrRigOverride.fingerOverrideActive[hand] > 0 then
    local i = hand * 15 + finger * 3 + bit
    vrRigOverride.fingerInAngles[i] = v
    return vrRigOverride.fingerOutAngles[i]
  end
  return v
end

function DriverFinger:update(touchLevel, bendLevel, blend)
  local m = self.hand == 1 and 1 or -1
  touchLevel = math.max(touchLevel, bendLevel)

  local prevMatrices
  if blend < 0.999 then
    prevMatrices = { self.root:getTransformationRaw():clone(), self.second:getTransformationRaw():clone(), self.third:getTransformationRaw():clone() }
  end

  if self.index == 0 then
    self.root:setRotation(vec3(0, 0, 1), math.lerp(0.4, 0.6, bendLevel) * m):rotate(vec3(1, 0, 0), fingerOverride(self.hand, self.index, 0, bendLevel * 0.1 - 0.7 + touchLevel * 0.5))
    self.second:setRotation(vec3(1, 0, 0), fingerOverride(self.hand, self.index, 1, bendLevel * 0.4))
    self.third:setRotation(vec3(1, 0, 0), fingerOverride(self.hand, self.index, 2, bendLevel * 0.8))
  else
    self.root:setRotation(self.axis, fingerOverride(self.hand, self.index, 0, 0.3 * (touchLevel + self.baseOffset) + bendLevel * (self.index == 1 and 0.8 or 0.6)) * m)
    self.second:setRotation(vec3(0, 0, 1), fingerOverride(self.hand, self.index, 1, 0.3 * (touchLevel + self.baseOffset) + bendLevel * 0.8) * m)
    self.third:setRotation(vec3(0, 0, 1), fingerOverride(self.hand, self.index, 2, 0.3 * (touchLevel + self.baseOffset) + bendLevel * 0.6) * m)
  end

  if blend < 0.999 then
    lerpMat4x4(self.root:getTransformationRaw(), prevMatrices[1], self.root:getTransformationRaw(), blend)
    lerpMat4x4(self.second:getTransformationRaw(), prevMatrices[2], self.second:getTransformationRaw(), blend)
    lerpMat4x4(self.third:getTransformationRaw(), prevMatrices[3], self.third:getTransformationRaw(), blend)
  end
end

---@class DriverHand
local DriverHand = class('DriverHand')

---@param carRoot ac.SceneReference
function DriverHand:initialize(carRoot, hand)
  local postfix = hand == 1 and 'R' or 'L'
  self.index = hand
  self.clave = carRoot:findNodes('DRIVER:RIG_Clave_'..postfix)
  self.shoulder = self.clave:findNodes('DRIVER:RIG_Shoulder_'..postfix)
  self.arm = self.clave:findNodes('DRIVER:RIG_Arm_'..postfix)
  self.forearm = self.clave:findNodes('DRIVER:RIG_ForeArm_'..postfix)
  self.forearmEnd = self.clave:findNodes('DRIVER:RIG_ForeArm_END_'..postfix)
  self.hand = self.clave:findNodes('DRIVER:RIG_HAND_'..postfix)
  -- self.armLength = self.shoulder:getWorldTransformationRaw().position:distance(self.forearm:getWorldTransformationRaw().position) * 0.85
  self.armLength = 0.29
  self.indexPointing = 1
  self.thumbUp = 1
  self.fingers = hand == 0 and {
    DriverFinger(self.hand:findNodes('DRIVER:HAND_L_Thumb1'), 0, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Index1'), 1, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Middle1'), 2, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Pinkie1'), 3, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Ring1'), 4, hand),
  } or {
    DriverFinger(self.hand:findNodes('DRIVER:HAND_R_Thumb1'), 0, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Index4'), 1, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Middle4'), 2, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Pinkie4'), 3, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Ring4'), 4, hand),
  }

  self.activatingCounter = 0
  self.activeFor = 0
  self.activeTransition = 0
end

function DriverHand:update(dt, driverModelUpdated)
  local vrHand = vr.hands[self.index]
  if not vrHand.active then
    if self.lastPos then
      self.lastPos = nil
      self.activatingCounter = 0
      self.activeFor = 0
      self.activeTransition = 0
    end
    return false
  end

  local inHandTransform = vrRigOverride.handOverrideActive[self.index] > 0 and vrRigOverride.handTransform[self.index] or vrHand.transform

  if not self.lastPos then
    -- TODO: a bug somewhere here?
    self.lastPos = inHandTransform.position:clone()
  end

  local refPos = car.worldToLocal:transformPoint(inHandTransform.position + inHandTransform.look * -0.3)
  if not self.lastPos:closerToThan(refPos, 0.003) then
    self.lastPos:set(refPos)
    self.activatingCounter = self.activatingCounter + 1
  else
    self.activatingCounter = math.max(0, self.activatingCounter - 2)
  end

  if self.activatingCounter > 10 or vrHand.triggerHand > 0.1 or vrHand.triggerIndex > 0.1 then
    self.activeFor = 2
    self.activatingCounter = 8
  end

  if self.activeFor > 0 then
    self.activeFor = self.activeFor - dt
  end
  self.activeTransition = math.applyLag(self.activeTransition, self.activeFor > 0 and 1 or 0, 0.75, dt)

  if self.activeTransition < 0.001 then
    return false
  end

  if not driverModelUpdated then
    ac.updateDriverModel(0)
  end

  local blend = self.activeTransition
  local transform = (rig.overrideHandTransform[self.index] or defaultOverrideTransform)(self.index, inHandTransform)
  local mat = mat4x4.identity()
  mat.side = self.index == 1 and -transform.side or -transform.side
  mat.up = self.index == 1 and transform.look or transform.look
  mat.look = self.index == 1 and transform.up or transform.up
  mat.position = transform.position + mat.up * 0.135 + mat.side * (self.index == 0 and 1 or -1) * 0.01 + mat.look * -0.03
  -- mat.position.y = mat.position.y + 0.2

  local handTarget = mat.position

  local claveWorldTransformation = self.clave:getWorldTransformationRaw()
  local shoulderWorldTransformation = self.shoulder:getWorldTransformationRaw()
  local shoulderDistance = handTarget:distance(shoulderWorldTransformation.position)

  if shoulderDistance < 0.3 then
    local offset = car.look * -0.05 * math.lerpInvSat(shoulderDistance, 0.3, 0.1)
    self.clave:getTransformationRaw().position:add(self.clave:getParent():getWorldTransformationRaw():inverse():transformVector(offset))
  end

  local worldToClave = claveWorldTransformation:inverse()
  local handPos = worldToClave:transformPoint(handTarget)
  local shoulderPos = worldToClave:transformPoint(shoulderWorldTransformation.position)
  local middlePoint = (handPos + shoulderPos) / 2
  local halfDistance = #(middlePoint - shoulderPos)
  local elbowOffset = math.sqrt(math.max(0, self.armLength^2 - halfDistance^2)) * 0.6

  local elbowDir = -(handPos - shoulderPos):cross(worldToClave:transformVector(inHandTransform.side)):normalize()
  elbowDir = (elbowDir + worldToClave:transformVector(vec3(0, 1, 0))):normalize()
  if halfDistance < 0.2 then
    elbowDir = math.lerp(elbowDir, vec3(self.index == 0 and -1 or 1, -0.3, math.clampN((shoulderPos.x - handPos.x) * 2, 0, 0.5)), math.lerpInvSat(halfDistance, 0.2, 0.1)):normalize()
  end
  local elbowPos = middlePoint - elbowDir * elbowOffset

  local armTransform = setLookAt(self.arm, elbowPos, elbowDir, self.index, blend)
  worldToClave = worldToClave:mul(armTransform:inverse())

  local forearmTransform = setLookAt(self.forearm, worldToClave:transformPoint(handTarget), vec3(0, 0, 1), self.index, blend)
  worldToClave = worldToClave:mul(forearmTransform:inverse())

  local forearmEndTransform = setLookAt(self.forearmEnd, worldToClave:transformPoint(handTarget), (self.index == 1 and 1 or -1) * worldToClave:transformVector(vrHand.transform.up + vrHand.transform.side * 2), self.index, blend)
  worldToClave = worldToClave:mul(forearmEndTransform:inverse())

  -- self.hand:getTransformationRaw():set(mat:mul(worldToClave))
  local handTransform = self.hand:getTransformationRaw()
  lerpMat4x4(handTransform, handTransform, mat:mul(worldToClave), blend)

  self.thumbUp = math.applyLag(self.thumbUp, vrHand.thumbUp and 1 or 0, 0.7, dt)
  self.indexPointing = math.applyLag(self.indexPointing, vrHand.indexPointing and 1 or 0, 0.7, dt)

  for i = 1, #self.fingers do
    local touch = 1
    if i == 1 then touch = 1 - self.thumbUp
    elseif i == 2 then touch = 1 - self.indexPointing end
    self.fingers[i]:update(touch, i == 2 and vrHand.triggerIndex or i == 3 and math.max(vrHand.triggerHand, vrHand.triggerIndex / 2) or vrHand.triggerHand, blend)
  end

  -- self.hand:getTransformationRaw():set(mat:mul(self.hand:getParent():getWorldTransformationRaw():inverse()))
  return true
end

local carRoot = ac.findNodes('carRoot:0')
local handL = DriverHand(carRoot, 0)
local handR = DriverHand(carRoot, 1)

Register('simUpdate', function (dt)
  if sim.cameraMode == ac.CameraMode.Cockpit and sim.focusedCar == 0 then
    local driverModelUpdated = handL:update(dt, false)
    handR:update(dt, driverModelUpdated)
  end

  if vrRigOverride.fingerOverrideActive[0] > 0 then vrRigOverride.fingerOverrideActive[0] = vrRigOverride.fingerOverrideActive[0] - 1 end
  if vrRigOverride.fingerOverrideActive[1] > 0 then vrRigOverride.fingerOverrideActive[1] = vrRigOverride.fingerOverrideActive[1] - 1 end
  if vrRigOverride.handOverrideActive[0] > 0 then vrRigOverride.handOverrideActive[0] = vrRigOverride.handOverrideActive[0] - 1 end
  if vrRigOverride.handOverrideActive[1] > 0 then vrRigOverride.handOverrideActive[1] = vrRigOverride.handOverrideActive[1] - 1 end
end)
