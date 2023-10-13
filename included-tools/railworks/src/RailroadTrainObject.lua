local DEBUG_COLLIDERS = true          -- If `true`, shows outline for train colliders
local MAX_COLLIDING_TRAIN_SPEED = 50  -- Trains moving above that speed get their colliders disabled (for time rewinding)

local RailroadSurroundLight = require 'RailroadSurroundLight'
local RailroadUtils = require 'RailroadUtils'
local sim = ac.getSim()

---@alias RailroadTrainSmoke {emitter: ac.Particles.Smoke, transform: mat4x4, direction: vec3}
---@alias RailroadTrainDoor {side: integer, update: function}

---@param trainDescription TrainDescription
---@param rootNode ac.SceneReference
---@return RailroadTrainSmoke
local function prepareSmoke(trainDescription, rootNode)
  if trainDescription.smokeIntensity > 0 then
    local smoke = rootNode:findNodes('SMOKE')
    if #smoke > 0 then
      smoke:setParent(nil) -- TODO: verify
      return {
        transform = smoke:getTransformationRaw():clone(),
        emitter = ac.Particles.Smoke({
          color = rgbm(0.2, 0.2, 0.2, 0.5),
          colorConsistency = -2,
          thickness = 0,
          life = 20,
          size = 0.5,
          spreadK = 5,
          growK = 2,
          targetYVelocity = 1
        }),
        direction = smoke:getTransformationRaw().up * 10
      }
    end
  end
  return nil
end

---@param trainDescription TrainDescription
---@param rootNode ac.SceneReference
---@return RailroadTrainDoor[]?
local function prepareDoors(trainDescription, rootNode)
  local doors = rootNode:findNodes('DOOR_?')
  if #doors > 0 then
    if trainDescription.doubleFacedDoors then
      doors:ensureUniqueMaterials():applyShaderReplacements([[ CULL_MODE = NONE ]])
    end
    return table.range(#doors, function (i)
      local door = doors:at(i)
      local t, p = door:name():match('DOOR_([A-Z]+)_([A-Z]+)')
      local side = math.sign(door:getPosition().x)
      if t == 'SLIDE' then
        local min, max = door:findMeshes('?'):getLocalAABB()
        return {
          door = door,
          side = side,
          state = 0,
          pos = door:getPosition(),
          distance = p == 'FWD' and max.z - min.z or min.z - max.z,
          remap = (1 - math.random() ^ 4) * 0.5,
          update = function (s, param, dt)
            local newState = math.saturateN(s.state + (param and dt or -dt))
            if math.abs(newState - s.state) > 0.01 then
              s.state = newState
              local rm = math.lerpInvSat(newState, s.remap, s.remap + 0.5)
              s.door:setPosition(s.pos + vec3(math.min(rm, 0.15) * side, 0, rm * s.distance))
            end
            return newState
          end
        }
      elseif t == 'HINGE' then
        return {
          door = door,
          side = side,
          axis = p == 'CW' and vec3(0, -1, 0) or vec3(0, 1, 0),
          state = 0,
          remap = (1 - math.random() ^ 4) * 0.5,
          update = function (s, param, dt)
            local newState = math.saturateN(s.state + (param and dt or -dt))
            if math.abs(newState - s.state) > 0.01 then
              s.state = newState
              s.door:setRotation(s.axis, math.lerpInvSat(newState, s.remap, s.remap + 0.5) * math.pi / 2)
            end
            return newState
          end
        }
      else
        error('Unknown door type: '..t)
      end
    end)
  end
  return nil
end

local carsRootRef

---@return ac.SceneReference
local function getCarsRootRef()
  if not carsRootRef then
    carsRootRef = ac.findNodes('carsRoot:yes')
  end
  return carsRootRef
end

---@class RailroadTrainObject
---@field trainDescription TrainDescription
---@field description TrainCartDescription
---@field rootNode ac.SceneReference
---@field lodA ac.SceneReference
---@field lodB ac.SceneReference
---@field surroundLight RailroadSurroundLight
---@field emissiveMeshes ac.SceneReference
---@field sideLeft number
---@field sideRight number
---@field distanceFront number
---@field distanceRear number
---@field distanceTotal number
---@field smoke RailroadTrainSmoke
---@field doors RailroadTrainDoor[]?
---@field bodySize vec3
---@field bodyOffset vec3
---@field posFront vec3
---@field posRear vec3
---@field dir vec3
---@field up vec3
---@field speed number
---@field rigidBody physics.RigidBody?
local RailroadTrainObject = class 'RailroadTrainObject'

local pool = {}
local collidersPool = {}

---@param description TrainCartDescription
local function getTypePool(description)
  return table.getOrCreate(pool, description, function () return {} end)
end

---@param self RailroadTrainObject
local function getCollidersPool(self)
  local key = tonumber(bit.bxor(ac.checksumXXH(self.bodyOffset), ac.checksumXXH(self.bodySize)))
  return table.getOrCreate(collidersPool, key, function () return {} end)
end

---@param descriptions TrainCartDescription[]
---@param trainDescription TrainDescription
---@param randomDevice fun(): number
---@param callback fun(err: string?, trainObject: RailroadTrainObject?)
function RailroadTrainObject.createAsync(descriptions, trainDescription, randomDevice, callback)
  local description = table.random(descriptions, function (item) return item.probability end, nil, randomDevice) ---@type TrainCartDescription

  local typePool = getTypePool(description)
  if #typePool > 0 then
    local r = table.remove(typePool) or error('Damaged pool')
    r.rootNode:setParent(getCarsRootRef())
    callback(nil, r)
    return
  end

  try(function ()
    local created = RailroadTrainObject(description, trainDescription)
    created:initializeAsync(function (err)
      if err then callback(err, nil)
      else callback(nil, created) end
    end)
  end, function (err)
    callback(err, nil)
  end)
end

---@param description TrainCartDescription
---@param trainDescription TrainDescription
---@return RailroadTrainObject
function RailroadTrainObject.allocate(description, trainDescription)
  if not description then error('No fitting description is found') end
  if not description.model or description.model == '' then error('LOD A is not set') end

  return {
    trainDescription = trainDescription,
    description = description,
    rootNode = getCarsRootRef():createBoundingSphereNode('train', 20):setVisible(false):setMotionStencil(0.2),
    emissiveIntensity = -1,
    shown = false,
    lodAShown = 0,
    posFront = vec3(),
    posRear = vec3(),
    dir = vec3(),
    up = vec3(0, 1, 0),
    speed = 0,
  }
end

local colliderFailure = false

---@param self RailroadTrainObject
---@param active boolean
local function setCollider(self, active)
  if (self.rigidBody ~= nil) == active or colliderFailure then return end
  local targetPool = getCollidersPool(self)
  if not active then
    table.insert(targetPool, self.rigidBody)
    self.rigidBody:setInWorld(false)
    self.rigidBody = nil
  else
    getCollidersPool(self)
    try(function ()
      self.rigidBody = #targetPool > 0 and table.remove(targetPool):setInWorld(true)
        or physics.RigidBody(physics.Collider.Box(self.bodySize, self.bodyOffset, nil, nil, DEBUG_COLLIDERS), 50e3):setSemiDynamic(true, false)
    end, function (err)
      ac.warn('Failed to create train collider: '..err)
      colliderFailure = true
    end)
  end
end

function RailroadTrainObject:dispose()
  setCollider(self, false)
  table.insert(getTypePool(self.description), self)
  self.rootNode:setParent(nil)
  self.offsetFront = nil
end

function RailroadTrainObject:actualDispose()
  self.lodA:dispose()
  self.lodB:dispose()
  self.rootNode:dispose()
  if self.rigidBody then
    self.rigidBody:dispose()
  end
  if self.surroundLight then
    self.surroundLight:dispose()
  end
end

function RailroadTrainObject.disposePool()
  for _, v in pairs(pool) do
    for i = 1, #v do
      v[i]:actualDispose()
    end
  end
  table.clear(pool)
  for _, v in pairs(collidersPool) do
    for i = 1, #v do
      v[i]:dispose()
    end
  end
  table.clear(collidersPool)
end

function RailroadTrainObject:initializeAsync(callback)
  local lodBFilename = self.description.model:lower():gsub('%.kn5$', '_b.kn5')
  local mainLOD = self.trainDescription.mainModel

  RailroadUtils.whenAll(function (cb)
    if mainLOD then
      self.rootNode:loadKN5LODAsync(self.description.model, mainLOD, cb())
    else
      self.rootNode:loadKN5Async(self.description.model, cb())
    end
    self.rootNode:loadKN5LODAsync(lodBFilename, mainLOD or self.description.model, cb())
  end, function (err, data)
    if err then
      return callback(err, nil)
    end

    self.lodA = data[1]
    self.lodB = data[2]
    if not self.lodA then error('Failed to load LOD A: '..self.description.model) end
    if not self.lodB then error('Failed to load LOD B: '..lodBFilename) end
  
    self.smoke = prepareSmoke(self.trainDescription, self.lodA)
    self.doors = prepareDoors(self.trainDescription, self.rootNode)

    self.emissiveMeshes = self.rootNode:findMeshes('?'):ensureUniqueMaterials()
    self.emissiveMeshes:applyShaderReplacements([[ DOUBLE_FACE_SHADOW_BIASED = 1 ]])
  
    local min, max = self.lodA:findMeshes('?'):getLocalAABB()
    self.fakeShadow = self.rootNode:createFakeShadow({
      points = {
        vec3(max.x, 0.05, min.z),
        vec3(min.x, 0.05, min.z),
        vec3(max.x, 0.05, max.z),
        vec3(min.x, 0.05, max.z),
      },
      opacity = 0.7,
      squaredness = vec2((max.x - min.x) / 3, (max.z - min.z) / 3)
    })
    
    self.distanceFront = max.z
    self.distanceRear = -min.z
    self.distanceTotal = max.z - min.z
    self.sideLeft = max.x
    self.sideRight = -min.x

    min.y = 0
    self.bodySize = max:clone():sub(min):sub(vec3(0.2, 0, 0.5))
    self.bodyOffset = min:clone():add(max):scale(0.5)
    callback(nil, nil)
  end)
end

local tmp1, tmp2 = vec3(), vec3()
local tmpRgb = rgb()

---@param posProvider RailroadSchedule
---@param posNormalized number
---@param dt any
function RailroadTrainObject:update(posProvider, posNormalized, doorsOpened, lightsActive, dt)
  local firstRun = not self.offsetFront
  if firstRun then
    self.offsetFront = self.distanceFront / posProvider.length
    self.offsetRear = self.distanceRear / posProvider.length
    self.offsetTrain = (self.distanceFront + self.distanceRear) / posProvider.length
    self.lastPN = posNormalized
  end

  local offset = (posNormalized - self.lastPN) * posProvider.length
  self.speed = math.applyLag(self.speed, offset / math.max(0.001, dt), 0.8, 0.01)

  local posRefNormalized = posNormalized - self.offsetFront
  local pn1 = posRefNormalized + 0.9 * self.offsetFront
  local pn2 = posRefNormalized - 0.9 * self.offsetRear
  local moved = math.abs(offset) > 0.0001 or firstRun
  if moved then
    posProvider:getPositionTo(self.posFront, pn1)
    posProvider:getPositionTo(self.posRear, pn2)
    posProvider:getNormalTo(self.up, posRefNormalized)
    self.dir:set(self.posFront):sub(self.posRear):normalize()
    self.posFront:scale(self.distanceRear / self.distanceTotal):addScaled(self.posRear, self.distanceFront / self.distanceTotal)
    self.lastPN = posNormalized
  end

  local showAtAll = sim.cameraPosition:closerToThan(self.posFront, 1200) and (pn1 < 1 and pn2 > 0 or posProvider.definition.looped)
  if not showAtAll then
    if self.shown then
      self.shown = false
      self.rootNode:setVisible(false)
    end
    return
  end

  local colliderActive = showAtAll and math.abs(self.speed) < MAX_COLLIDING_TRAIN_SPEED
  if colliderActive and not posProvider:needsActiveCollider(posNormalized) then
    colliderActive = false
  end
  setCollider(self, colliderActive)

  local doorsOpenedLeft, doorsOpenedRight = 0, 0
  if self.doors then
    for i = 1, #self.doors do
      local v = self.doors[i]:update(doorsOpened == self.doors[i].side, dt)
      if self.doors[i].side == 1 then
        doorsOpenedLeft = math.max(doorsOpenedLeft, v)
      else
        doorsOpenedRight = math.max(doorsOpenedRight, v)
      end
    end
  end

  if not self.shown then
    self.shown = true
    self.rootNode:setVisible(true)
  end

  local showLodA = sim.cameraPosition:closerToThan(self.posFront, 200)
  if moved then
    self.rootNode:setPosition(self.posFront)
    self.rootNode:setOrientation(self.dir, self.up)
    if self.rigidBody then
      self.rigidBody:setTransformation(self.rootNode:getTransformationRaw(), true)
    end
  end

  if showLodA ~= self.lodAShown then
    self.lodAShown = showLodA
    self.lodA:setVisible(showLodA)
    self.lodB:setVisible(not showLodA)

    if showLodA then
      self.surroundLight = RailroadSurroundLight(self.description)
    elseif self.surroundLight then
      self.surroundLight:dispose()
      self.surroundLight = nil
    end
  end

  local newIntensity = math.applyLag(self.emissiveIntensity, lightsActive and 1 or 0, firstRun and 0 or 0.9, dt)
  if math.abs(newIntensity - self.emissiveIntensity) > 0.01 then
    self.emissiveIntensity = newIntensity
    self.emissiveMeshes:setMaterialProperty('ksEmissive', tmpRgb:setScaled(self.description.tint, newIntensity * 30))
  end

  if self.surroundLight and newIntensity > 0.01 then
    self.surroundLight:update(self, doorsOpenedLeft, doorsOpenedRight, newIntensity)
  end

  if firstRun then
    self.rootNode:clearMotion()
  end

  if self.smoke then
    local smokeIntensity = math.lerpInvSat(math.abs(self.speed), 10, 25) * self.trainDescription.smokeIntensity
    if smokeIntensity > 0 then
      self.rootNode:getTransformationRaw():transformPointTo(tmp1, self.smoke.transform.position)
      self.rootNode:getTransformationRaw():transformVectorTo(tmp2, self.smoke.direction)
      self.smoke.emitter:emit(tmp1, tmp2, smokeIntensity)
    end
  end
end

return class.emmy(RailroadTrainObject, RailroadTrainObject.allocate)
