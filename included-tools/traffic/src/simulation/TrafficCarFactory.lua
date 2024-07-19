local TrafficCar = require('TrafficCar')
local TrafficConfig = require('TrafficConfig')
local TrafficCarPhysics = require('TrafficCarPhysics')
local Pool = require('Pool')
local Array = require('Array')

---@class TrafficCarFactory
---@field definitions CarDefinition[]
---@field pools table<CarDefinition, Pool>
---@field activeCars Array|TrafficCar[]
local TrafficCarFactory = class('TrafficCarFactory')

---@generic T
---@param items T[]
---@param weightProvider fun(item: T, index: integer): number
---@return fun(): T
local function weightedRandom(items, weightProvider)
  local totalWeight = 0
  local weights = table.map(items, function (item, key)
    totalWeight = totalWeight + weightProvider(item, key)
    return totalWeight
  end)
  local function weightedRandom_s(item, _, pos)
    return item > pos
  end
  return function ()
    return items[table.findLeftOfIndex(weights, weightedRandom_s, math.random() * totalWeight) + 1]
  end
end

---@param definitions CarDefinition[]
---@return TrafficCarFactory
function TrafficCarFactory:initialize(definitions)
  if #definitions == 0 then
    error('Models are missing')
  end

  self.definitions = definitions
  self.pools = table.map(definitions, function (def) 
    return Pool(function (pool)
      local ret = TrafficCar(def)
      ret.__pool = pool
      return ret
    end) 
  end)

  self.activeCars = Array()
  self.randomDevice = weightedRandom(self.pools, function (item, index)
    return definitions[index].chance
  end)
  -- distantCars = {}

  self.carsToGiveOut = 10
  self.frame = 0

  for i = 1, #definitions do
    TrafficCarPhysics.prepare(definitions[i])
  end
end

local justJumped = false

function TrafficCarFactory:dispose()
  self.activeCars:clear(function (car) car:dispose() end)

  -- for i = 1, #self.distantCars do
  --   self.distantCars[i]:dispose()
  -- end
  -- self.activeCars = {}
  -- self.distantCars = {}
  -- self.activeCarsCount = 0

  table.forEach(self.pools, function (pool)
    pool:dispose(function (item)
      item:dispose()
    end)
  end)
end

function TrafficCarFactory:get(driver)
  if self.carsToGiveOut == 0 and not justJumped then return end
  self.carsToGiveOut = self.carsToGiveOut - 1

  local pool = self.randomDevice()
  local ret = pool:get()
  self.activeCars:push(ret)
  ret:repaintFor(driver)
  return ret
end

function TrafficCarFactory:update(dt)
  if dt == 0 then return end

  self.carsToGiveOut = TrafficConfig.maxSpawnPerFrame
  self.frame = self.frame + 1

  local c = self.activeCars.length
  -- local p = 0
  -- local d = {}

  for i = 1, c do
    local e = self.activeCars[i]
    -- ac.perfFrameBegin(100)
    e:update(dt)
    -- ac.perfFrameEnd(100)
    -- if e._physics ~= nil then p = p + 1 end
    -- if e:distanceToCameraSquared() > 150^2 then
    --   table.remove(self.activeCars, i)
    --   table.insert(d, e)
    -- end
  end

  -- local cd = #self.distantCars
  -- if self.frame % 2 == 1 then
  --   for i = cd, 1, -1 do
  --     local e = self.distantCars[i]
  --     e:update(dt)
  --     if e._physics ~= nil then p = p + 1 end
  --     if e:distanceToCameraSquared() < 100^2 then
  --       table.remove(self.distantCars, i)
  --       table.insert(self.activeCars, e)
  --     end
  --   end
  -- end
  -- for i = 1, #d do
  --   table.insert(self.distantCars, d[i])
  -- end

  ac.debug('Active cars', c)
  -- ac.debug('Distant cars', cd)
  -- ac.debug('Cars with physics', p)
end

function TrafficCarFactory:draw3D(layers)
  local c = self.activeCars.length
  for i = 1, c do
    self.activeCars[i]:draw3D(layers)
  end
end

function TrafficCarFactory:release(car)
  self.activeCars:remove(car, true)
  car.__pool:release(car)
  car:release()
end

function TrafficCarFactory.setJumped(value)
  justJumped = value
end

return class.emmy(TrafficCarFactory, TrafficCarFactory.initialize)
