---@param out mat4x4
---@param m1 mat4x4
---@param m2 mat4x4
local function lerpMat4x4(out, m1, m2, blend)
  if out == m1 and out.row4.w == 0 then blend = 1 end
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

---@param hand integer
---@param finger integer
---@param bit integer
---@param v number
---@return number
local function defaultFingerOverride(hand, finger, bit, v) return v end

---@class DriverFinger
local DriverFinger = class('DriverFinger')

---@param root ac.SceneReference
---@param fingerOverride nil|fun(hand: integer, finger: integer, bit: integer, v: number): number
---@param index integer
---@param hand integer
function DriverFinger:initialize(root, fingerOverride, index, hand)
  self.root = root
  self.fingerOverride = fingerOverride or defaultFingerOverride
  self.index = index
  self.hand = hand
  self.second = root:getChild()
  self.third = self.second:getChild()
  self.axis = vec3(0, index == 3 and -0.3 or index * -0.05, 1)
  self.baseOffset = index == 2 and 0.7 or index * 0.2
end

---@param touchLevel number
---@param bendLevel number
---@param blend number
function DriverFinger:update(touchLevel, bendLevel, blend)
  local m = self.hand == 1 and 1 or -1
  touchLevel = math.max(touchLevel, bendLevel)

  local prevMatrices
  if blend < 0.999 then
    prevMatrices = { self.root:getTransformationRaw():clone(), self.second:getTransformationRaw():clone(), self.third:getTransformationRaw():clone() }
  end

  local fingerOverride = self.fingerOverride
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

---@param car ac.StateCar
---@param carRoot ac.SceneReference
---@param handOverride nil|fun(hand: integer, v: mat4x4): mat4x4
---@param fingerOverride nil|fun(hand: integer, finger: integer, bit: integer, v: number): number
---@param hand integer
function DriverHand:initialize(car, carRoot, handOverride, fingerOverride, hand)
  local postfix = hand == 1 and 'R' or 'L'
  self.car = car
  self.handOverride = handOverride
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

  ---@type DriverFinger[]
  self.fingers = hand == 0 and {
    DriverFinger(self.hand:findNodes('DRIVER:HAND_L_Thumb1'), fingerOverride, 0, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Index1'), fingerOverride, 1, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Middle1'), fingerOverride, 2, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Pinkie1'), fingerOverride, 3, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Ring1'), fingerOverride, 4, hand),
  } or {
    DriverFinger(self.hand:findNodes('DRIVER:HAND_R_Thumb1'), fingerOverride, 0, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Index4'), fingerOverride, 1, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Middle4'), fingerOverride, 2, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Pinkie4'), fingerOverride, 3, hand),
    DriverFinger(self.hand:findNodes('DRIVER:HAND_Ring4'), fingerOverride, 4, hand),
  }

  self.activatingCounter = 0
  self.activeFor = 0
  self.activeTransition = 0
end

---@param carIndex integer
---@param vrHand ac.StateVRHand
---@param dt number
---@param driverModelUpdated boolean
---@return boolean
function DriverHand:update(carIndex, vrHand, dt, driverModelUpdated)
  -- local vrHand = vr.hands[self.index]
  if not vrHand.active then
    if self.lastPos then
      self.lastPos = nil
      self.activatingCounter = 0
      self.activeFor = 0
      self.activeTransition = 0
    end
    return false
  end

  ---@type mat4x4
  local inHandTransform = vrHand.transform
  if self.handOverride then
    inHandTransform = self.handOverride(self.index, inHandTransform)
  end

  if not self.lastPos then
    -- TODO: a bug somewhere here?
    self.lastPos = inHandTransform.position:clone()
  end

  local refPos = self.car.worldToLocal:transformPoint(inHandTransform.position + inHandTransform.look * -0.3)
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
    ac.updateDriverModel(carIndex, true)
  end

  local blend = self.activeTransition
  local mat = mat4x4.identity()
  mat.side = self.index == 1 and -inHandTransform.side or -inHandTransform.side
  mat.up = self.index == 1 and inHandTransform.look or inHandTransform.look
  mat.look = self.index == 1 and inHandTransform.up or inHandTransform.up
  mat.position = inHandTransform.position + mat.up * 0.135 + mat.side * (self.index == 0 and 1 or -1) * 0.01 + mat.look * -0.03
  -- mat.position.y = mat.position.y + 0.2

  local handTarget = mat.position

  local claveWorldTransformation = self.clave:getWorldTransformationRaw()
  local shoulderWorldTransformation = self.shoulder:getWorldTransformationRaw()
  local shoulderDistance = handTarget:distance(shoulderWorldTransformation.position)

  if shoulderDistance < 0.3 then
    local offset = self.car.look * -0.05 * math.lerpInvSat(shoulderDistance, 0.3, 0.1)
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

---@type table?
local vrRigOverride

local function defaultVRRigInitialize()
  if vrRigOverride then return end

  vrRigOverride = ac.connect([[
    int fingerOverrideActive[2];
    float fingerInAngles[30];
    float fingerOutAngles[30];
    int handOverrideActive[2];
    mat4x4 handTransform[2];  
  ]], false, ac.SharedNamespace.Shared)

  Register('simUpdate', function ()
    if vrRigOverride.fingerOverrideActive[0] > 0 then vrRigOverride.fingerOverrideActive[0] = vrRigOverride.fingerOverrideActive[0] - 1 end
    if vrRigOverride.fingerOverrideActive[1] > 0 then vrRigOverride.fingerOverrideActive[1] = vrRigOverride.fingerOverrideActive[1] - 1 end
    if vrRigOverride.handOverrideActive[0] > 0 then vrRigOverride.handOverrideActive[0] = vrRigOverride.handOverrideActive[0] - 1 end
    if vrRigOverride.handOverrideActive[1] > 0 then vrRigOverride.handOverrideActive[1] = vrRigOverride.handOverrideActive[1] - 1 end
  end)
end

local function fingerOverride(hand, finger, bit, v)
  if vrRigOverride and vrRigOverride.fingerOverrideActive[hand] > 0 then
    local i = hand * 15 + finger * 3 + bit
    vrRigOverride.fingerInAngles[i] = v
    return vrRigOverride.fingerOutAngles[i]
  end
  return v
end

local function handOverride(hand, v)
  return vrRigOverride and vrRigOverride.handOverrideActive[hand] > 0 and vrRigOverride.handTransform[hand] or v
end

VRRig = {}

---@class VRRig.VR
VRRig.VR = class('VRRig.VR')

---@param car ac.StateCar
---@param vr ac.StateVR
function VRRig.VR:initialize(car, vr)
  defaultVRRigInitialize()
  self.car = car
  self.vr = vr
  local driverRoot = ac.findNodes('driverRoot:'..car.index)
  self.handL = DriverHand(car, driverRoot, handOverride, fingerOverride, 0) ---@type DriverHand
  self.handR = DriverHand(car, driverRoot, handOverride, fingerOverride, 1) ---@type DriverHand
end

function VRRig.VR:update(dt)
  local driverModelUpdated = self.handL:update(self.car.index, self.vr.hands[0], dt, false)
  self.handR:update(self.car.index, self.vr.hands[1], dt, driverModelUpdated)
end

---@param car ac.StateCar
local function collectReferencePoints(car)
  -- Done this way, we can send local coordinates instead of global meaning it’ll function normally independent of car movement,
  -- but also with coordinates close to their initial points we can store position in 3 bytes and it should be enough.
  local carRoot = ac.findNodes('carRoot:'..car.index)
  local carRootTransform = carRoot:getWorldTransformationRaw():inverse()
  local driverRoot = carRoot:findNodes('driverRoot:'..car.index)
  local neck = driverRoot:findNodes('driverNeck:'..car.index)
  return {
    shoulderPosL = carRootTransform:transformPoint(driverRoot:findNodes('DRIVER:RIG_Shoulder_L'):getWorldTransformationRaw().position),
    shoulderPosR = carRootTransform:transformPoint(driverRoot:findNodes('DRIVER:RIG_Shoulder_R'):getWorldTransformationRaw().position),
    headPos = carRootTransform:transformPoint(driverRoot:findNodes('DRIVER:RIG_Cest'):getWorldTransformationRaw().position):add(vec3(0, 0.28, 0)),
    neckNode = neck,
    neckBaseTransform = neck:getWorldTransformationRaw():mul(carRootTransform)
  }
end

---@class VRRig.Remote
VRRig.Remote = class('VRRig.Remote')

---@param car ac.StateCar
function VRRig.Remote:initialize(car)
  self.car = car
  local carRoot = ac.findNodes('carRoot:'..car.index)
  self.refs = collectReferencePoints(car)

  self.lastSyncTime = -1e9
  self.headActive = false
  self.baseHeadTransform = mat4x4.identity()
  self.smoothHeadTransform = mat4x4()
  self.headTransform = mat4x4.identity()
  self.gHands = {} ---@type DriverHand[]
  self.vrHands = {} ---@type (ac.StateVRHand|{baseTransform: mat4x4, smoothTransform: mat4x4})[]
  for i = 1, 2 do
    self.gHands[i] = DriverHand(car, carRoot, nil, nil, i - 1)
    self.vrHands[i] = {
      active = false,
      baseTransform = mat4x4.identity(),
      smoothTransform = mat4x4(),
      transform = mat4x4.identity(),
      triggerIndex = 0,
      triggerHand = 0,
      thumbstick = vec2(),
      thumbUp = false,
      indexPointing = false,
      busy = false,
      openVRButtons = 0,
      openVRTouches = 0,
      openVRAxis = {},
    }
  end
end

---@param out ac.StateVRHand|{baseTransform: mat4x4}
---@param transform mat4x4
---@param state integer
local function syncHandState(out, transform, state)
  out.baseTransform:set(transform)
  out.triggerHand = state % 16 / 15
  out.triggerIndex = math.floor(state / 16) / 15
end

---@alias EncodedRig {handL: mat4x4, handR: mat4x4, head: mat4x4, flags: integer, handStateL: integer, handStateR: integer}
---@param ev EncodedRig
function VRRig.Remote:data(ev)
  self.lastSyncTime = os.preciseClock()
  self.baseHeadTransform:set(ev.head)
  self.baseHeadTransform.position:add(self.refs.headPos)
  
  syncHandState(self.vrHands[1], ev.handL, ev.handStateL)
  syncHandState(self.vrHands[2], ev.handR, ev.handStateR)
  self.vrHands[1].baseTransform.position:add(self.refs.shoulderPosL)
  self.vrHands[2].baseTransform.position:add(self.refs.shoulderPosR)

  self.headActive = bit.band(ev.flags, 1) ~= 0
  self.vrHands[1].active = bit.band(ev.flags, 2) ~= 0
  self.vrHands[2].active = bit.band(ev.flags, 4) ~= 0
  self.vrHands[1].thumbUp = bit.band(ev.flags, 8) ~= 0
  self.vrHands[2].thumbUp = bit.band(ev.flags, 16) ~= 0
  self.vrHands[1].indexPointing = bit.band(ev.flags, 32) ~= 0
  self.vrHands[2].indexPointing = bit.band(ev.flags, 64) ~= 0
end

local matTmp = mat4x4()

function VRRig.Remote:update(dt)
  local stillFresh = os.preciseClock() - self.lastSyncTime < 2

  if self.headActive and stillFresh then
    lerpMat4x4(self.smoothHeadTransform, self.smoothHeadTransform, self.baseHeadTransform, 0.15)
  else
    lerpMat4x4(self.smoothHeadTransform, self.smoothHeadTransform, self.refs.neckBaseTransform, 0.15)
  end
  self.smoothHeadTransform:mulTo(self.headTransform, self.car.bodyTransform)

  for i = 1, 2 do
    if not stillFresh then
      self.vrHands[i].active = false
    end

    lerpMat4x4(self.vrHands[i].smoothTransform, self.vrHands[i].smoothTransform, self.vrHands[i].baseTransform, 0.15)
    self.vrHands[i].smoothTransform:mulTo(matTmp, self.car.bodyTransform)
    self.vrHands[i].transform:set(matTmp)
    self.gHands[i].activeFor = self.vrHands[i].active and 10 or 0
  end

  if self.car.distanceToCamera < 400 and not self.car.focusedOnInterior then
    local driverModelUpdated = self.gHands[1]:update(self.car.index, self.vrHands[1], dt, false)
    self.gHands[2]:update(self.car.index, self.vrHands[2], dt, driverModelUpdated)

    self.headTransform:mulTo(
      self.refs.neckNode:getTransformationRaw(),
      self.refs.neckNode:getParent():getWorldTransformationRaw():inverse())
    self.applied = true
  elseif self.applied then
    self.applied = false
    ac.updateDriverModel(self.car.index)
  end
end

---@class VRRig.Encoder
VRRig.Encoder = class('VRRig.Encoder')

---@param car ac.StateCar
---@param vr ac.StateVR
function VRRig.Encoder:initialize(car, vr)
  self.car = car
  self.vr = vr
  self.refs = collectReferencePoints(car)
end

---@param out EncodedRig
function VRRig.Encoder:encode(out)
  local vr = self.vr
  local flags = (not vr or vr.headActive) and 1 or 0
  if vr then
    if vr.hands[0].active then flags = flags + 2 end
    if vr.hands[1].active then flags = flags + 4 end
    if vr.hands[0].thumbUp then flags = flags + 8 end
    if vr.hands[1].thumbUp then flags = flags + 16 end
    if vr.hands[0].indexPointing then flags = flags + 32 end
    if vr.hands[1].indexPointing then flags = flags + 64 end
  end

  -- Encoded rig uses `ac.StructItem.transform()` to store transform compactly. Because of that we can’t write directly to it.
  if vr then
    vr.hands[0].transform:mulTo(matTmp, self.car.worldToLocal)
    matTmp.position:sub(self.refs.shoulderPosL)
    out.handL = matTmp -- instead, convertation happens on assignment
    vr.hands[1].transform:mulTo(matTmp, self.car.worldToLocal)
    matTmp.position:sub(self.refs.shoulderPosR)
    out.handR = matTmp
  end
  self.refs.neckNode:getWorldTransformationRaw():mulTo(matTmp, self.car.worldToLocal)
  matTmp.position:sub(self.refs.headPos)
  out.head = matTmp

  out.flags = flags
  if vr then
    out.handStateL = math.round(vr.hands[0].triggerIndex * 15) * 16 + math.round(vr.hands[0].triggerHand * 15)
    out.handStateR = math.round(vr.hands[1].triggerIndex * 15) * 16 + math.round(vr.hands[1].triggerHand * 15)
  end
end
