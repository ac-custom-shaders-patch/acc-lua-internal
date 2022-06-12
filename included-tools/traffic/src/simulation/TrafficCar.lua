local CarBase = require('CarBase')
local TrafficConfig = require('TrafficConfig')
local TrafficCarPhysics = require('TrafficCarPhysics')
local TrafficContext = require('TrafficContext')
local MathUtils = require('MathUtils')
local TrafficCarFullLOD = require('TrafficCarFullLOD')
local TrafficCarFakeShadow = require('TrafficCarFakeShadow')
local Pool = require('Pool')

local _lastIndex = 0
local _colorDebug = rgbm(0.1, 0.1, 0.1, 1)
local _posOutside = vec3(0, 1e30, 0)
local _colorNone = rgb()
local _damageNone = vec4()
local _fakeShadowCornersPool = Pool(function() return {vec3(), vec3(), vec3(), vec3()} end)

---@class TrafficCar : CarBase
---@field active boolean
---@field definition CarDefinition
---@field root ac.SceneReference
---@field _speedKmh number
---@field _lastSpeedKmh number
---@field _carPaintMeshes ac.SceneReference
---@field _modelLod ac.SceneReference
---@field _index integer
---@field _pos vec3
---@field _dir vec3
---@field _lastPos vec3
---@field _rearPos vec3
---@field _transform mat4x4
---@field _damageSides vec4
---@field _debugValue rgb
---@field _fakeShadow TrafficCarFakeShadow
---@field _dbgColor rgbm
---@field _physics TrafficCarPhysics
---@field _crashed boolean
---@field _fullLOD TrafficCarFullLOD
---@field _horizontalOffset number
---@field _horizontalOffsetTarget number
---@field _horizontalOffsetBase number
---@param definition CarDefinition
local TrafficCar = class('TrafficCar', CarBase)

---@param definition CarDefinition
---@return TrafficCar
function TrafficCar.allocate(definition)
  _lastIndex = _lastIndex + 1

  local root = TrafficContext.carsRoot:createBoundingSphereNode('trafficCar', 3)
  local modelLod = root:loadKN5LOD(definition.lod, definition.main)
  local carPaintMeshes = modelLod:findMeshes('shader:ksPerPixelMultiMap_damage_dirt')
  local color = TrafficConfig.debugBehaviour and _colorDebug or definition.color()
  carPaintMeshes:ensureUniqueMaterials()
  carPaintMeshes:setMaterialTexture('txDetail', color)
  -- carPaintMeshes:setMaterialTexture('txDetail', _colorDebug)

  return {
    active = true,
    definition = definition,
    root = root,
  
    _index = _lastIndex,
    _transform = root:getTransformationRaw(),
    _modelLod = modelLod,
  
    -- car actor position
    _pos = vec3(),
    _dir = vec3(),
  
    -- position of car center and rear
    _lastPos = vec3(),
    _rearPos = vec3(),

    _speedKmh = 0,
    _lastSpeedKmh = 0,
  
    _frame = 0,
    _debugValue = rgb(),
    _damageSides = vec4(),
    _crashed = false,
    _lodUpdateDelay = 0,
    _distanceSquared = 0,
    _carPaintMeshes = carPaintMeshes,
    _horizontalOffsetBase = math.lerp(-0.5, 0.5, math.random()),
    _horizontalOffsetTarget = 0
  }
end

function TrafficCar:initialize(_)
  CarBase.initialize(self,
    self.root:getTransformationRaw(),
    (self.definition.dimensions.front + self.definition.dimensions.rear) / 2, self.definition.dimensions.width / 2)
end

---@param driver TrafficDriver
function TrafficCar:repaintFor(driver)
  self.active = true
  self.driver = driver

  self._pos:set(0, 0, 0)
  self._dir:set(0, 0, 0)
  self._lastPos:set(0, 0, 0)
  self._rearPos:set(0, 0, 0)

  self._frame = math.random(10)
  self._lodUpdateDelay = 0
  self._distanceSquared = 0
  self.turn = 0
  self._speedKmh = 0
  self._lastSpeedKmh = 0
  self._crashed = false
  self.stationaryFor = 0
  self.headlightsActive = false
  self.flashHighBeams = 0
  self._horizontalOffset = 0
  self._horizontalOffsetTarget = self._horizontalOffsetBase
  self:setDebugValue(_colorNone)
  self:setDamageSides(_damageNone)
  self.root:setPosition(_posOutside)
  self.root:clearMotion()

  if self._fakeShadowCorners ~= nil then
    _fakeShadowCornersPool:release(self._fakeShadowCorners)
    self._fakeShadowCorners = nil
  end
  self._fakeShadowOpacity = nil

  self._posOffset = self.definition.dimensions.front - self._halfLength
end

function TrafficCar:__tostring()
  return string.format('<Car #%d>', self._index)
end

function TrafficCar:release()
  self.active = false
  self.root:setPosition(_posOutside)
  self:releaseFullLOD()
  self:releaseFakeShadow()
  self:releasePhysics()
  self:releaseTrackers()
end

local _dbgValueNone = rgb()
local _dbgValueTmp = rgb()

function TrafficCar:setDebugValue(r, g, b)
  if not TrafficConfig.debugBehaviour then return end
  local value
  if r == nil then value = _dbgValueNone
  elseif g == nil then value = _dbgValueTmp:set(r, 1 - r, 0) 
  else value = _dbgValueTmp:set(r, g, b) end
  if value == self._debugValue then return end
  self._debugValue:set(value)
  self._carPaintMeshes:setMaterialProperty('ksEmissive', value * 30)
end

function TrafficCar:setDamageSides(damageVec4)
  if self._damageSides == damageVec4 then return end
  self._damageSides:set(damageVec4)
  self._carPaintMeshes:setMaterialProperty('damageZones', damageVec4)
end

function TrafficCar:setFakeShadow(corners, opacity)
  if self._fakeShadow ~= nil then
    self._fakeShadow:setFakeShadow(corners, opacity)
  end

  local ownCorners = self._fakeShadowCorners
  if corners ~= nil then
    if ownCorners == nil then
      ownCorners = _fakeShadowCornersPool:get()
      self._fakeShadowCorners = ownCorners
    end
    for i = 1, 4 do ownCorners[i]:set(corners[i]) end
  elseif ownCorners ~= nil then
    ownCorners = nil
    _fakeShadowCornersPool:release(ownCorners)
  end
  self._fakeShadowOpacity = opacity
end

function TrafficCar:getWheels()
  return self._fullLOD and self._fullLOD:getWheels()
end

function TrafficCar:getTransformationRef()
  return self.root:getTransformationRaw()
end

function TrafficCar:getCarPaintMeshes()
  return self._carPaintMeshes
end

function TrafficCar:dispose()
  self:release()
  self.root:dispose()
end

function TrafficCar:releasePhysics()
  if self._physics ~= nil then
    self._physics:release()
    self._physics = nil
  end
  -- self:setDebugValue(rgb(), true)
end

function TrafficCar:releaseTrackers()
  if self._physicsFrozenTracker ~= nil then
    self._physicsFrozenTracker:dispose()
    self._physicsFrozenTracker = nil
  end
end

function TrafficCar:releaseFullLOD()
  if self._fullLOD ~= nil then
    self._fullLOD:release(self)
    self._fullLOD = nil
    self._modelLod:setVisible(true)
  end
end

function TrafficCar:releaseFakeShadow()
  if self._fakeShadow ~= nil then
    self._fakeShadow:release(self)
    self._fakeShadow = nil
  end
end

local sim = ac.getSim()
local _dirUp = vec3(0, 1, 0)
local _dirTmpLook = vec3()
local _mucrossY = MathUtils.crossY

function TrafficCar:getPosRef() return self._pos end
function TrafficCar:getDirRef() return self._dir end
function TrafficCar:extrapolateMovement(dlen) self._pos:addScaled(self._dir, dlen) end

function TrafficCar:setPos(posRef, speedKmh)
  self._pos:set(posRef)
  self._speedKmh = speedKmh
end

function TrafficCar:updateLODs()
  if self._distanceSquared < 80^2 ~= (self._fullLOD ~= nil) then
    if self._fullLOD == nil then
      self._fullLOD = TrafficCarFullLOD.get(self)
    else
      self:releaseFullLOD()
    end
    self._modelLod:setVisible(self._fullLOD == nil)
  end

  if self._distanceSquared < 200^2 ~= (self._fakeShadow ~= nil) then
    if self._fakeShadow == nil then
      self._fakeShadow = TrafficCarFakeShadow.get(self)
      if self._fakeShadow ~= nil and (self._fakeShadowCorners ~= nil or self._fakeShadowOpacity ~= nil) then
        self._fakeShadow:setFakeShadow(self._fakeShadowCorners, self._fakeShadowOpacity)
      end
    else
      self:releaseFakeShadow()
    end
  end
end

function TrafficCar:distanceToCameraSquared()
  return self._distanceSquared
end

local _msqrt = math.sqrt

local function _carSetupPhysics(self)
  self._physics = TrafficCarPhysics.get(self.definition, self)
  -- self:setDebugValue(rgb(0.1, 0.1, 0), true)
end

local function _carUpdatePosDir(self, dlen, dt)
  local sfrm = self._frame
  local sdsq = self._distanceSquared
  local sho = self._horizontalOffset

  if sdsq < 200^2 or sfrm % (sdsq < 400^2 % 2 or 4) == 0 then

    sho = sho + (self._horizontalOffsetTarget - sho) * dlen * dt
    self._horizontalOffset = sho

    -- _dirTmpLook:set(self._dir)
    local tmpd = _dirTmpLook
    local sdir = self._dir
    tmpd.x, tmpd.y, tmpd.z = sdir.x, sdir.y, sdir.z

    -- self._dir:set(self._pos):sub(self._rearPos):normalize()
    local _spos = self._pos
    local _dsid = self._transform.side
    local spx, spy, spz = _spos.x + _dsid.x * sho, _spos.y, _spos.z + _dsid.z * sho

    local srps = self._rearPos
    local drx, dry, drz = spx - srps.x, spy - srps.y, spz - srps.z
    local sqr = _msqrt(drx*drx + dry*dry + drz*drz)
    local dna = sqr < 0.0001
    if dna then sqr = 0.0001 end
    local dril = 1 / sqr
    drx, dry, drz = drx * dril, dry * dril, drz * dril
    sdir.x, sdir.y, sdir.z = drx, dry, drz

    if math.isNaN(sdir.x) then 
      ac.debug('sho', sho)
      ac.debug('spx', spx)
      ac.debug('_dsid.x', _dsid.x)
      ac.debug('_spos.x', _spos.x)
      ac.debug('srps.x', srps.x)
      ac.debug('drx*drx + dry*dry + drz*drz', drx*drx + dry*dry + drz*drz)
      error('WTF') 
    end

    -- self._rearPos:set(self._dir):scale(-self.definition.dimensions.turningOffset):add(self._pos)
    local trof = self.definition.dimensions.turningOffset
    srps.x, srps.y, srps.z = spx - drx * trof, spy - dry * trof, spz - drz * trof

    -- self._bodyPos:set(self._dir):scale(self._posOffset):add(self._pos):copyTo(self._transform.position)
    -- local sbps = self._bodyPos

    if dlen > 0.01 then
      local turn = 2 * _mucrossY(tmpd, sdir) / dlen
      self.turn = math.applyLag(self.turn, turn, 0.7, dt)
    end

    if not dna and (sdir:dot(self._transform.look) < 0.99998 or sdsq < 40^2) then
      sdir:copyTo(self._transform.look)
      self._transform.side:setCrossNormalized(sdir, _dirUp)
      if math.isNaN(self._transform.side.x) then
        ac.debug('sdir', sdir)
        ac.debug('_dirUp', _dirUp)
        error('WTF #2')
      end
      self._transform.up:setCrossNormalized(self._transform.side, sdir)
    end

    local psof = self._posOffset
    local trps = self._transform.position
    trps.x, trps.y, trps.z = spx + drx * psof, spy + dry * psof, spz + drz * psof
  else
    -- self._bodyPos:set(self._dir):scale(self._posOffset):add(self._pos):copyTo(self._transform.position)
    local _spos = self._pos
    local _dsid = self._transform.side
    local spx, spy, spz = _spos.x + _dsid.x * sho, _spos.y, _spos.z + _dsid.z * sho

    local psof = self._posOffset
    local sdir = self._dir
    local trps = self._transform.position
    trps.x, trps.y, trps.z = spx + sdir.x * psof, spy + sdir.y * psof, spz + sdir.z * psof
  end
end

function TrafficCar:initializePos(from, to)
  self._distanceSquared = 0
  self._lastPos:set(from)
  self._rearPos:set(from)
  self._pos:set(to)
  _carUpdatePosDir(self, 0, 1)
  self._dbgText = string.format('%s\n%s', from, to)
end

function TrafficCar:update(dt)
  -- ac.perfFrameBegin(1010)
  if not self.active then return end

  -- Keeping track of lifespan
  local frame = self._frame + 1
  self._frame = frame
  
  -- Measuring distance to camera and choosing current LOD
  if self._lodUpdateDelay > 0 then
    self._lodUpdateDelay = self._lodUpdateDelay - 1
  else
    self._distanceSquared = self._pos:distanceSquared(sim.cameraPosition)
    self._lodUpdateDelay = self._distanceSquared > 200^2 and 20 or self._distanceSquared > 80^2 and 10 or 4
    self:updateLODs()
  end

  -- After we crashed, we’ll go the different route
  if self._crashed then
    self:updateCrashed(dt)
    return
  end
  -- ac.perfFrameEnd(1010)

  -- ac.perfFrameBegin(1030)
  local isNearby = self._distanceSquared < 80^2 and frame > 15
  if self._physics == nil and frame > 15 and (isNearby or frame % 8 == 0) and TrafficContext.trackerPhysics:anyAround(self._pos) then
    _carSetupPhysics(self)
  end
  -- ac.perfFrameEnd(1030)

  -- ac.perfFrameBegin(1040)
  -- How long car was stationary
  local speedKmh = self._speedKmh
  self.stationaryFor = speedKmh < 1 and self.stationaryFor + dt or 0

  -- Calculate how much car has moved, if not a whole lot, we could skip a frame
  local dlen = (self._speedKmh / 3.6) * dt

  -- Calculate actual position and orientation of a 3d model
  -- ac.perfFrameBegin(1050)
  if dlen > 0.0003 then
    _carUpdatePosDir(self, dlen, dt)
    self._lastPos:set(self._pos)
  end
  -- ac.perfFrameEnd(1050)

  -- Flashing high beams
  -- ac.perfFrameBegin(1060)
  if self.flashHighBeams > 0 then
    self.flashHighBeams = math.max(self.flashHighBeams - dt * 5, 0)
  end

  -- Calculate current speed and its rate of change
  local dspeed = speedKmh - self._lastSpeedKmh
  self._lastSpeedKmh = speedKmh
  -- ac.perfFrameEnd(1060)

  -- Run physics
  -- ac.perfFrameBegin(1080)
  local physicsHandlesWheels = (self._crashed or self._physics) and self:updatePhysics(dlen, dt)
  -- ac.perfFrameEnd(1080)

  -- Run full LOD update
  -- ac.perfFrameBegin(1090)
  if self._fullLOD then
    self._fullLOD:update(self, physicsHandlesWheels, dlen, dspeed, dt)
  end
  -- ac.perfFrameEnd(1090)
end

function TrafficCar:getBodyPos()
  return self._transform.position
end

function TrafficCar:getSpeedKmh()
  return self._speedKmh
end

function TrafficCar:getDistanceToNext()
  return self.driver:getDistanceToNext()
end

-- After a collision, car is controlled by TrafficCarPhysics
function TrafficCar:updateCrashed(dt)
  local physicsHandlesWheels = self:updatePhysics(0, dt)
  if self._fullLOD ~= nil then
    self._fullLOD:update(self, physicsHandlesWheels, 0, 0, dt)
  end
end

function TrafficCar:needsBrakes()
  local sph = self._physics
  return sph ~= nil and sph:appliesBrakes() or self._physicsFrozenTracker ~= nil
end

function TrafficCar:crashed()
  return self._crashed
end

function TrafficCar:updatePhysics(dlen, dt)
  if self._physicsFrozenTracker ~= nil then
    local isNearby = self._distanceSquared < 80^2
    if self._frame % (isNearby and 6 or 60) == 0 and TrafficContext.trackerPhysics:anyCloserThan(self._pos, 10) then
      -- self:setDebugValue(rgb(0, 0.1, 0), true)
      self._physics = TrafficCarPhysics.get(self.definition, self)
      self._physicsFrozenTracker:dispose()
      self._physicsFrozenTracker = nil
    end
    return true
  end

  if self._physics == nil then
    return false
  end

  if self._physics:update(self, dlen, dt) then
    self._pos:set(self._physics:getPos())
    self._dir:set(self._physics:getDir())
    if self._physics:settled() and self._frame % 30 == 0 and not TrafficContext.trackerPhysics:anyAround(self._pos) then
      self._physicsFrozenTracker = self._physics:stealTrackerBlocking()
      self:releasePhysics()
      -- self:setDebugValue(rgb(0.1, 0, 0), true)
    end
    return true
  elseif self._frame % 30 == 0 and not TrafficContext.trackerPhysics:anyAround(self._pos) then
    self:releasePhysics()
  end
  return false
end

function TrafficCar:draw3D(layers)
  local dbgText = {}

  if self._distanceSquared < 50^2 then
    layers:with('Turn', function ()
      dbgText[#dbgText + 1] = string.format('turn: %.2f', self.turn)
    end)

    layers:with('Number of blocking cars around', function ()
      dbgText[#dbgText + 1] = string.format('blocking: %d', TrafficContext.trackerBlocking:count(self._pos))
    end)

    layers:with('Number of physics cars around', function ()
      dbgText[#dbgText + 1] = string.format('physics: %d', TrafficContext.trackerPhysics:count(self._pos))
    end)

    layers:with('Debug message', function ()
      dbgText[#dbgText + 1] = string.format('debug: %s', self._dbgText or '-')
    end)
  end

  if #dbgText > 0 then
    render.debugText(self._pos, table.concat(dbgText, '\n'), rgbm(2, 2, 2, 1), 0.8, render.FontAlign.left)
  end
end

return class.emmy(TrafficCar, TrafficCar.initialize)