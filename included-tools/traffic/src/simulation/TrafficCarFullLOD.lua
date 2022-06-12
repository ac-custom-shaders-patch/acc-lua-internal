local LicensePlateGenerator = require('LicensePlateGenerator')
local SmoothEmissive = require('SmoothEmissive')
local InertialValue  = require('InertialValue')
local Pool = require('Pool')

local _licensePlateGenerator = LicensePlateGenerator()
local _pools = {}
local _lastIndex = 0
local _leftToCreate = 0

---@class TrafficCarFullLOD
---@field _modelMain ac.SceneReference
---@field _carPaint ac.SceneReference
---@field _body ac.SceneReference
---@field _wheelRadiusInv number
local TrafficCarFullLOD = class('TrafficCarFullLOD')

function TrafficCarFullLOD.get(car)
  if _leftToCreate == 0 then return nil end
  -- if true then return nil end
  _leftToCreate = _leftToCreate - 1
  local pool = table.getOrCreate(_pools, car.definition, Pool)
  return pool:get(function() return TrafficCarFullLOD(car) end, function (lod) lod:assign(car) end)
end

function TrafficCarFullLOD.resetLimit()
  _leftToCreate = 1
end

---@param car TrafficCar
---@return TrafficCarFullLOD
function TrafficCarFullLOD:initialize(car)
  _lastIndex = _lastIndex + 1

  local modelMain = car.root:loadKN5(car.definition.main)

  local carPaint = modelMain:findMeshes('shader:ksPerPixelMultiMap_damage_dirt')
  carPaint:setMaterialsFrom(car:getCarPaintMeshes())
  -- carPaint:ensureUniqueMaterials()
  -- carPaint:setMaterialTexture('txDetail', car.bodyColor)

  -- self:setBodyColor(true)
  -- self:collectNodes()

  local body = modelMain:findNodes('BODY')
  local lights = {
    headlights = SmoothEmissive(modelMain:findMeshes(car.definition.lights.headlights), rgb(50, 50, 50), rgb(0, 0, 0), 0.6, 0),
    rear = SmoothEmissive(modelMain:findMeshes(car.definition.lights.rear), rgb(5, 0, 0), rgb(0, 0, 0), 0.6, 0),
    brakes = SmoothEmissive(modelMain:findMeshes(car.definition.lights.brakes), rgb(50, 0, 0), rgb(0, 0, 0), 0.6, 0),
    rearCombined = SmoothEmissive(modelMain:findMeshes(car.definition.lights.rearCombined), rgb(50, 0, 0), rgb(0, 0, 0), 0.6, 0),
  }
  local wheels = {
    modelMain:findNodes('WHEEL_LF'),
    modelMain:findNodes('WHEEL_RF'),
    modelMain:findNodes('WHEEL_LR'),
    modelMain:findNodes('WHEEL_RR'),
  }

  local prevPositions = car.definition.cache.neutralWheelPositions
  if prevPositions == nil then
    car.definition.cache.neutralWheelPositions = table.map(wheels, function (w) return w:getPosition() end)
  end

  _licensePlateGenerator:generate(modelMain:findMeshes('texture:Plate_D.dds'))

  self._index = _lastIndex
  self._modelMain = modelMain
  self._carPaint = carPaint
  self._body = body
  self._lights = lights
  self._wheels = wheels
  self._lightSource = nil
  self._appliedTiltX = 0
  self._appliedTiltZ = 0
  self._appliedTurn = 0
  self._tiltX = InertialValue(0, 0.07, 0.94, 0.5)
  self._tiltZ = InertialValue(0, 0.1, 0.95, 0.5)
  self._wheelRadiusInv = 1 / car.definition.dimensions.wheelRadius
  self._drivenDistance = 0
end

function TrafficCarFullLOD:assign(car)
  self._tiltX:reset(0)
  self._tiltZ:reset(0)
  self._modelMain:setParent(car.root)
  self._carPaint:setMaterialsFrom(car:getCarPaintMeshes())

  local prevPositions = car.definition.cache.neutralWheelPositions
  if prevPositions ~= nil then
    for i = 1, 4 do
      self._wheels[i]:setPosition(prevPositions[i])
    end
  else
  end
end

function TrafficCarFullLOD:release(car)
  self._modelMain:setParent(nil)
  self:disposeLight()
  table.getOrCreate(_pools, car.definition, Pool):release(self)
end

function TrafficCarFullLOD:dispose()
  self._modelMain:dispose()
end

local _dirSide = vec3(1, 0, 0)

function TrafficCarFullLOD:disposeLight()
  if self._lightSource ~= nil then
    self._lightSource:dispose()
    self._lightSource = nil
  end
end

function TrafficCarFullLOD:getWheels()
  return self._wheels
end

local _mabs = math.abs
local _dirTurn = vec3()
local _tiltX = vec3()
local _tiltZ = vec3()

function TrafficCarFullLOD:update(car, physicsHandlesWheels, dlen, dspeed, dt)
  local updateRate = 1
  local cfrm = car._frame
  local cdsq = car._distanceSquared
  if cdsq > 20^2 then
    if cdsq > 40^2 then
      updateRate = 4
    else
      updateRate = 2
    end
  end

  if cfrm % updateRate ~= 0 then return end
  dt = dt * updateRate

  local stlx = self._tiltX
  local stlz = self._tiltZ
  stlx:update(car:getSpeedKmh() * car.turn * 0.05, dt)
  stlz:update(dspeed, dt)
  self._drivenDistance = self._drivenDistance + dlen

  -- ac.perfFrameBegin(1092)
  if physicsHandlesWheels then
    stlx:update(0, dt)
    stlz:update(0, dt)
  elseif dlen > 0.003 then
    local whls = self._wheels
    local dang = dlen * self._wheelRadiusInv
    local ctrn = car.turn
    if _mabs(self._appliedTurn - ctrn) then
      _dirTurn:set(ctrn, 0, 1)
      whls[1]:setOrientation(_dirTurn):rotate(_dirSide, self._drivenDistance * self._wheelRadiusInv)
      whls[2]:setOrientation(_dirTurn):rotate(_dirSide, self._drivenDistance * self._wheelRadiusInv)
      self._appliedTurn = ctrn
    else
      whls[1]:rotate(_dirSide, dang)
      whls[2]:rotate(_dirSide, dang)
    end
    whls[3]:rotate(_dirSide, dang)
    whls[4]:rotate(_dirSide, dang)
  end
  -- ac.perfFrameEnd(1092)

  -- ac.perfFrameBegin(1093)
  if _mabs(stlx.value - self._appliedTiltX) > 0.01 or _mabs(stlz.value - self._appliedTiltZ) > 0.01 then
    self._appliedTiltX = stlx.value
    self._appliedTiltZ = stlz.value
    self._body:setOrientation(_tiltX:set(0, 0.05 * stlz.value, 1), _tiltZ:set(-0.2 * stlx.value, 1, 0))
  end
  -- ac.perfFrameEnd(1093)

  -- ac.perfFrameBegin(1094)
  local lightsActive = car.headlightsActive
  local brakesActive = car:needsBrakes() or dspeed < -0.1 or car.stationaryFor > 0.3
  self:setHeadlightsLight(car, lightsActive)
  -- ac.perfFrameEnd(1094)

  -- ac.perfFrameBegin(1095)
  if cfrm % 4 == 0 then
    local slgh = self._lights
    slgh.headlights:update((car.flashHighBeams % 1) > 0.5 and 2 or lightsActive and 1 or 0, dt)
    slgh.rear:update(lightsActive and 1 or 0, dt)
    slgh.brakes:update(brakesActive and 1 or 0, dt)
    slgh.rearCombined:update(brakesActive and 1 or lightsActive and 0.1 or 0, dt)
  end
  -- ac.perfFrameEnd(1095)
end

---@param car TrafficCar
function TrafficCarFullLOD:setHeadlightsLight(car, active)
  if active then
    if not self._lightSource then
      self._lightSource = ac.LightSource(ac.LightType.Regular, vec3.new(car:getBodyPos()))
      self._lightSource.color = rgb(10, 10, 10)
      self._lightSource.specularMultiplier = 1
      self._lightSource.range = 10
      self._lightSource.rangeGradientOffset = 0.1
      self._lightSource.fadeAt = 60
      self._lightSource.fadeSmooth = 20
      self._lightSource.spot = 90
      self._lightSource.spotSharpness = 0.2
      self._lightSource.skipLightMap = true
      self._lightSource.showInReflections = false
      self._lightSource.longSpecular = 0
    end
    self._lightSource.position:set(0, 1, 0):add(car:getBodyPos()):addScaled(car._dir, 0.8)
    self._lightSource.direction:set(car._dir)
  elseif self._lightSource ~= nil then
    self._lightSource:dispose()
    self._lightSource = nil
  end
end

return class.emmy(TrafficCarFullLOD, TrafficCarFullLOD.initialize)
