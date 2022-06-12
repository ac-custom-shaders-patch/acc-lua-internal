local RailroadTrainObject = require 'RailroadTrainObject'
local RailroadUtils = require 'RailroadUtils'

---@class RailroadTrain
---@field description TrainDescription
---@field train RailroadTrainObject
---@field carts RailroadTrainObject[]
---@field length number
---@field position number
---@field light ac.LightSource
---@field phase integer
---@field ready boolean?
local RailroadTrain = class 'RailroadTrain'

---@param description TrainDescription
---@return RailroadTrain
function RailroadTrain.allocate(description)
  return {
    description = description,
    phase = 0,
    position = -1,
  }
end

local lightOffset = vec3(0, 3, 0)

---@param self RailroadTrain
local function releaseTrain(self)
  if not self.train then return end
  self.train:dispose()
  for i = 1, #self.carts do
    self.carts[i]:dispose()
  end
  self.train = nil
  table.clear(self.carts)
  self.light:dispose()
  self.ready = nil
  self.position = -1
end

local function randomDevice(seed)
  return function ()
    seed = seed + 1
    return math.seededRandom(seed)
  end
end

---@param self RailroadTrain
local function setupTrain(self, trainSeed)
  if self.train and self.seed == trainSeed or self.ready == false then return end

  self.seed = trainSeed
  releaseTrain(self)

  self.ready = false
  self.phase = self.phase + 1
  local curPhase = self.phase

  local random = randomDevice(bit.bxor(trainSeed, self.description.index % 397))
  local size = math.round(math.lerp(random(), self.description.sizeMin, self.description.sizeMax))

  RailroadUtils.whenAll(function (cb)
    RailroadTrainObject.createAsync(self.description.head, self.description, random, cb())

    for _ = 1, size do
      RailroadTrainObject.createAsync(self.description.carts, self.description, random, cb())
    end
  end, function (err, data)
    if self.phase ~= curPhase then
      return
    end

    RailroadUtils.reportError(self.description, err)
    if err then return  end

    local train = data[1]
    local carts = self.carts or {}
    local length = train.distanceTotal
    for i = 1, size do
      local cart = data[i + 1]
      carts[i] = cart
      length = length + cart.distanceTotal
    end

    self.train = train
    self.carts = carts
    self.length = length
    self.ready = true

    local light = ac.LightSource()
    light.range = 40
    light.spot = 50
    light.spotSharpness = 0
    light.shadows = true
    light.shadowsHalfResolution = false
    light.fadeAt = 400
    light.fadeSmooth = 200
    self.light = light
  end)
end

---@param posProvider RailroadSchedule
---@param posNormalized number
---@param dt any
function RailroadTrain:update(posProvider, posNormalized, doorsOpened, dt, trainSeed)
  if not posNormalized then
    releaseTrain(self)
    return
  end

  if not self.ready then
    setupTrain(self, trainSeed)
    if self.ready == false then return end
  end

  local moved = math.abs(self.position - posNormalized) > 0.001 / posProvider.length
  self.position = posNormalized

  local lightsActive = ac.getSkyFeatureDirection(ac.SkyFeature.Sun).y < 0.2 or posProvider:areLightsForcedOn(posNormalized)
  self.train:update(posProvider, posNormalized, doorsOpened, lightsActive, dt)
  posNormalized = posNormalized - self.train.offsetTrain
  for i = 1, #self.carts do
    self.carts[i]:update(posProvider, posNormalized, doorsOpened, lightsActive, dt)
    posNormalized = posNormalized - self.carts[i].offsetTrain
  end

  local emissive = self.train.emissiveIntensity * 100
  if emissive > 0.01 then
    self.light.color:set(self.train.description.tint):scale(emissive)
    if moved then
      self.light.position:set(self.train.posFront):add(lightOffset):addScaled(self.train.dir, 1)
      self.light.direction:set(self.train.dir)
    end
  else
    self.light.color:set(0)
  end
end

function RailroadTrain:dispose()
  releaseTrain(self)
end

return class.emmy(RailroadTrain, RailroadTrain.allocate)
