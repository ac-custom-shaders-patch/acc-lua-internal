local Pool = require('Pool')

local _tableDefault = {}
local _pools = {}
local _leftToCreate = 0

---@param car TrafficCar
local function prepareDefaultPoints(car)
  local fsx = car.definition.dimensions.fakeShadowX
  local fsz = car.definition.dimensions.fakeShadowZ
  return {
    vec3(-fsx, 0, fsz),
    vec3(fsx, 0, fsz),
    vec3(-fsx, 0, -fsz),
    vec3(fsx, 0, -fsz)
  }
end

---@param fakeShadow ac.SceneReference
---@param car TrafficCar
local function setPoints(fakeShadow, car)
  fakeShadow:setFakeShadowPoints(table.getOrCreate(_tableDefault, car.definition, prepareDefaultPoints, car))
end

---@class TrafficCarFakeShadow
---@field _fakeShadow ac.SceneReference
local TrafficCarFakeShadow = class('TrafficCarFakeShadow')

function TrafficCarFakeShadow.get(car)
  if _leftToCreate == 0 then return nil end
  _leftToCreate = _leftToCreate - 1
  local pool = table.getOrCreate(_pools, car.definition, Pool)
  return pool:get(function() return TrafficCarFakeShadow(car) end, function (lod) lod:assign(car) end)
end

function TrafficCarFakeShadow.resetLimit()
  _leftToCreate = 20
end

---@param car TrafficCar
---@return TrafficCarFakeShadow
function TrafficCarFakeShadow.allocate(car)
  local fakeShadow = car.root:createFakeShadow{ opacity = 0.9, squaredness = vec2(1.2, 2) }
  setPoints(fakeShadow, car)
  return { _fakeShadow = fakeShadow }
end

function TrafficCarFakeShadow:assign(car)
  self._fakeShadow:setParent(car.root)
  setPoints(self._fakeShadow, car)
  self._fakeShadow:setFakeShadowOpacity(0.9)
end

function TrafficCarFakeShadow:release(car)
  self._fakeShadow:setParent(nil)
  table.getOrCreate(_pools, car.definition, Pool):release(self)
end

function TrafficCarFakeShadow:dispose()
  self._fakeShadow:dispose()
end

function TrafficCarFakeShadow:setFakeShadow(corners, opacity)
  if corners ~= nil then self._fakeShadow:setFakeShadowPoints(corners) end
  if opacity ~= nil then self._fakeShadow:setFakeShadowOpacity(opacity) end
end

return class.emmy(TrafficCarFakeShadow, TrafficCarFakeShadow.allocate)