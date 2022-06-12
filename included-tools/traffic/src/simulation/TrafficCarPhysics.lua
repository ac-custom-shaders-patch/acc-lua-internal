local Pool = require('Pool')
local TrafficContext = require('TrafficContext')

---@class TrafficCarPhysics
---@field _definition CarDefinition
---@field _wheelAngVel number[]
---@field _suspensionOffset number[]
---@field _wheelContactPoints vec3[]
---@field _sidesDamage vec4
---@field _collider physics.RigidBody
---@field _transform mat4x4
---@field _frontWheelDir vec3
---@field _frontWheelSide vec3
---@field _cache any
local TrafficCarPhysics = class('TrafficCarPhysics')

---@param definition CarDefinition
---@return TrafficCarPhysics
function TrafficCarPhysics.allocate(definition)
  local collider = physics.RigidBody(definition.collider, definition.physics.mass, definition.physics.cog or vec3(0, 0.8, 0.2))
  collider:setDamping(0.9, 0.9)
  -- collider:setDamping(0, 0)
  collider:setSemiDynamic(true, true)
  collider:getLastHitIndex()

  local cache = definition.cache
  if not cache.wheelBasePoints then
    local w = definition.physics.width / 2
    local l = definition.physics.length / 2
    cache.wheelBasePoints = { vec3(w, 1, l), vec3(-w, 1, l), vec3(w, 1, -l), vec3(-w, 1, -l) }
    cache.fakeShadowMult = vec3(definition.dimensions.fakeShadowX / w, 1, definition.dimensions.fakeShadowZ / l)
    cache.suspensionForce = definition.physics.mass * definition.physics.suspensionForce
    cache.suspensionDamping = definition.physics.mass * definition.physics.suspensionDamping
    cache.wheelsForce = definition.physics.mass * definition.physics.wheelsGripForce
    cache.suspensionTravel = definition.physics.suspensionTravel
    cache.wheelRadiusInv = 1 / definition.dimensions.wheelRadius
  end

  return {
    _definition = definition,
    _cache = cache,
    _collider = collider,

    _crashedTime = -0.1,
    _stationaryTime = 0,
    _wheelContactPoints = { vec3(), vec3(), vec3(), vec3() },

    _wheelAngVel = { 0, 0, 0, 0 },
    _frontWheelDir = vec3(0, 0, 1),
    _frontWheelSide = vec3(1, 0, 0),

    _suspensionOffset = {0, 0, 0, 0},
    _sidesDamage = vec4(),
    _collisionIndex = -1,

    _transform = nil
  }
end

---@param car TrafficCar
function TrafficCarPhysics:_attach(car)
  self._stationaryTime = 0
  self._transform = car:getTransformationRef()

  for i = 1, 4 do self._suspensionOffset[i] = 0 end
  self._sidesDamage:set(0, 0, 0, 0)

  if car:crashed() then
    self._crashedTime = 1
    self._collisionIndex = self._collider:getLastHitIndex()
  else
    self._crashedTime = 0
    self._collisionIndex = -1
  end

  self._collider:setTransformation(self._transform, false)
  self._collider:setSemiDynamic(true, true)
  self._collider:setInWorld(true)
end

function TrafficCarPhysics:_detach()
  if self._trackerPhysics ~= nil then
    self._trackerPhysics:dispose()
    self._trackerPhysics = nil
  end

  if self._trackerBlocking ~= nil then
    self._trackerBlocking:dispose()
    self._trackerBlocking = nil
  end

  self._collider:setSemiDynamic(true, true)
  self._collider:setInWorld(false)
  self._collider:setEnabled(false)
  self._transform = nil
end

function TrafficCarPhysics:_dispose()
  self:_detach()
  self._collider:dispose()
end

local _crashBrakesDelay = 0.5
local _forceSuspensionVec = vec3()
local _forceVec = vec3()
local _dirUp = vec3(0, 1, 0)
local _dirDown = vec3(0, -1, 0)
local _dirSide = vec3(1, 0, 0)
local _shadowCenter = vec3()
local _shadowCorner = vec3()
local _shadowCorners = { vec3(), vec3(), vec3(), vec3() }
local _wheelPos = vec3()

function TrafficCarPhysics:getPos() return self._transform.position end
function TrafficCarPhysics:getDir() return self._transform.look end
function TrafficCarPhysics:crashed() return self._crashedTime > 0 end
function TrafficCarPhysics:appliesBrakes() return self._crashedTime > _crashBrakesDelay end
function TrafficCarPhysics:settled() return self._stationaryTime > 0.1 end

function TrafficCarPhysics:stealTrackerBlocking()
  local ret = self._trackerBlocking
  self._trackerBlocking = nil
  return ret
end

function TrafficCarPhysics:runWheel(wheelNodes, i, carUp, dt)
  local localPos = self._cache.wheelBasePoints[i]
  local pos = self._collider:localPosToWorld(localPos)
  local distance = physics.raycastTrack(pos, _dirDown, 4, self._wheelContactPoints[i])
  local offset = 1 - distance

  if distance ~= -1 and distance < 1 then
    local k = math.lerpInvSat(offset, 0, self._cache.suspensionTravel)
    local v = self._collider:pointVelocity(localPos, true, true)
    _forceSuspensionVec.y = (self._cache.suspensionForce * k - v.y * self._cache.suspensionDamping) * math.abs(carUp.y)
    self._collider:addForce(_forceSuspensionVec, false, pos, false)

    local wheelLv = self._collider:pointVelocity(self._wheelContactPoints[i], false, true)
    if i < 3 then
      wheelLv.x, wheelLv.z = wheelLv:dot(self._frontWheelSide), wheelLv:dot(self._frontWheelDir)
    end

    local wheelT = math.applyLag(self._wheelAngVel[i], wheelLv.z, 0.5, dt)
    if self._crashedTime > _crashBrakesDelay then wheelT = wheelT * 0.5 end
    self._wheelAngVel[i] = wheelT

    local wheelFX = -wheelLv.x * self._cache.wheelsForce
    local wheelFZ = (wheelT - wheelLv.z) * self._cache.wheelsForce
    if i < 3 then
      _forceVec:setScaled(self._frontWheelSide, wheelFX):addScaled(self._frontWheelDir, wheelFZ)
    else
      _forceVec:set(wheelFX, 0, wheelFZ)
    end
    self._collider:addForce(_forceVec, true, self._wheelContactPoints[i], false)
    if wheelNodes ~= nil then
      wheelNodes[i]:rotate(_dirSide, wheelT * self._cache.wheelRadiusInv * dt)
    end
  elseif wheelNodes ~= nil then
    wheelNodes[i]:rotate(_dirSide, self._wheelAngVel[i] * self._cache.wheelRadiusInv * dt)
  end
  if distance ~= -1 and offset > self._suspensionOffset[i] and carUp.y > 0 then
    self._suspensionOffset[i] = math.applyLag(self._suspensionOffset[i], offset, 1 - carUp.y, dt)
  end
end

---@param car TrafficCar
---@param dlen number
---@param dt number
---@return boolean
function TrafficCarPhysics:update(car, dlen, dt)
  local notCrashedYet = self._crashedTime == 0
  local isSemiDynamic = self._collider:isSemiDynamic()

  if isSemiDynamic and notCrashedYet then
    self._collider:setTransformation(self._transform, true)
    if self._collider:isEnabled() then self._collider:setEnabled(false) end
    -- car:setDebugValue(rgb(math.random(), math.random(), math.random()):scale(0.1), true)
    return false
  end

  if not self._collider:isEnabled() then
    if self._trackerPhysics ~= nil then
      self._trackerPhysics:dispose()
      self._trackerPhysics = nil
      self._stationaryTime = 0.2
      self._collider:setSemiDynamic(true, true)
      -- car:setDebugValue(rgb(0, 0, 0.1), true)
    end
    return true
  end

  if notCrashedYet then
    car._crashed = true
    self._crashedTime = 0.001
    self._frontWheelDir:set(car.turn, 0, 1):normalize()
    self._frontWheelDir:cross(_dirUp, self._frontWheelSide):normalize()
    local angVelBase = dlen / math.max(dt, 0.005)
    for i = 1, 4 do
      self._wheelAngVel[i] = angVelBase
    end
    self._collider:addForce(vec3(0, 2000, 0), false, vec3(0, 0, -3), true)
  end

  if self._trackerPhysics == nil and not isSemiDynamic then
    self._trackerPhysics = TrafficContext.trackerPhysics:track(car)
  end
  if self._trackerPhysics ~= nil then
    self._trackerPhysics:update(self:getPos())
  end

  if self._trackerBlocking == nil then
    self._trackerBlocking = TrafficContext.trackerBlocking:track(car)
  end
  if self._trackerBlocking ~= nil then
    self._trackerBlocking:update(self:getPos())
  end

  local lastHitIndex = self._collider:getLastHitIndex()
  if self._collisionIndex ~= lastHitIndex then
    self._collisionIndex = lastHitIndex
    local lastHit = self._collider:getLastHitPos()
    if lastHit ~= vec3() then
      local hitRelative = self._collider:worldPosToLocal(lastHit)
      if hitRelative.x > math.abs(hitRelative.z) * 0.25 then self._sidesDamage.x = 1 end
      if -hitRelative.x > math.abs(hitRelative.z) * 0.25 then self._sidesDamage.z = 1 end
      if hitRelative.z > math.abs(hitRelative.x) * 0.9 then self._sidesDamage.w = 1 end
      if -hitRelative.z > math.abs(hitRelative.x) * 0.9 then self._sidesDamage.y = 1 end
      car:setDamageSides(self._sidesDamage)
    end
  end

  local speedThreshold = car._distanceSquared > 80^2 and 2 or 0.5
  local angularSpeedThreshold = car._distanceSquared > 80^2 and 0.05 or 0.005
  if self:appliesBrakes() and self._collider:getSpeedKmh() < speedThreshold and self._collider:getAngularSpeed() < angularSpeedThreshold then
    self._stationaryTime = self._stationaryTime + dt
    if self._stationaryTime > 0.1 then
      self._collider:setSemiDynamic(true, true)
      self._collider:setEnabled(false)
      -- car:setDebugValue(rgb(0, 0, 0.1), true)
      if self._trackerPhysics ~= nil then
        self._trackerPhysics:dispose()
        self._trackerPhysics = nil
      end
      return true
    end
  else
    -- car:setDebugValue(rgb(0, 0.1, 0.1), true)
    self._stationaryTime = 0
  end

  self._crashedTime = self._crashedTime + dt
  self._transform:set(self._collider:getTransformation())

  local carUp = self._collider:localDirToWorld(_dirUp)
  for i = 1, 4 do
    self._suspensionOffset[i] = math.applyLag(self._suspensionOffset[i], -self._cache.suspensionTravel * carUp.y, 0.8, dt)
  end

  local wheelNodes = car:getWheels()
  if carUp.y > 0.5 then
    for i = 1, 4 do self:runWheel(wheelNodes, i, carUp, dt) end

    local wc = self._wheelContactPoints
    local fc = _shadowCenter:set(wc[1]):add(wc[2]):add(wc[3]):add(wc[4]):scale(0.25)
    for i = 1, 4 do
      _shadowCorners[i]:set(self._collider:worldPosToLocal(_shadowCorner:set(wc[i]):sub(fc)
        :mul(self._cache.fakeShadowMult):add(fc)))
    end
    car:setFakeShadow(_shadowCorners, math.lerpInvSat(carUp.y, 0.5, 0.8) * math.lerpInvSat(self._transform.position.y - fc.y, 2, 0.2))
  else
    for i = 1, 4 do
      if self._crashedTime > _crashBrakesDelay then self._wheelAngVel[i] = self._wheelAngVel[i] * 0.5 end
      if wheelNodes ~= nil then 
        wheelNodes[i]:rotate(_dirSide, self._wheelAngVel[i] * self._cache.wheelRadiusInv * dt) 
      end
    end
    car:setFakeShadow(nil, 0)
  end

  if wheelNodes ~= nil then
    for i = 1, 4 do
      wheelNodes[i]:setPosition(_wheelPos:set(0, self._suspensionOffset[i], 0):add(self._cache.neutralWheelPositions[i]))
    end
  end

  return true
end

-- Recycling physics entities
local _pools = {}

---@param definition CarDefinition
local function getPool(definition)
  local pool = _pools[definition]
  if pool == nil then
    --[[
    Car physics entries consider driveable until they lose semidynamic state (which usually
    means collision has occured). Checking semidynamic state is an instant operation, but changing it is not,
    as it would have to happen in physics thread. That’s why there is a delay on releasing an item back to
    the pool.
    ]]
    pool = Pool(function () return TrafficCarPhysics(definition) end, true)
    _pools[definition] = pool
  end
  return pool
end

---@param definition CarDefinition
---@param car TrafficCar
function TrafficCarPhysics.get(definition, car)
  local ret = getPool(definition):get()
  ret:_attach(car)
  return ret
end

---Creates and moves to pool a single instance to make sure collider model is preloaded.
---@param definition CarDefinition
function TrafficCarPhysics.prepare(definition)
  local pool = getPool(definition)
  pool:release(pool:get())
end

---@param instance TrafficCarPhysics
function TrafficCarPhysics.release(instance)
  getPool(instance._definition):release(instance)
  instance:_detach()
end

return class.emmy(TrafficCarPhysics, TrafficCarPhysics.allocate)
