local TrafficCar = require('TrafficCar')
local CarsList = require('CarsList')
local RaceCarTracker = require('RaceCarTracker')
local json = require('lib/json')

---@type TrafficCar
local car1 = TrafficCar(CarsList[1])
car1:repaintFor(nil)

---@type TrafficCar
local car2 = TrafficCar(CarsList[1])
car2:repaintFor(nil)

local p = table.range(4, function() return { v = vec3(), m = render.PositioningHelper() } end)
p[1].v:set(3.49, 0, 2.3)
p[2].v:set(p[1].v - vec3(0.5, 0, 1))
p[3].v:set(1.73, 0, 0.86)
p[4].v:set(p[3].v + vec3(0, 0, -1))

local offset = vec3(977.24, -1079.05, 1095.1)
for i = 1, 4 do p[i].v:add(offset) end

local function test()
  car1:initializePos(p[1].v, p[2].v)
  car2:initializePos(p[3].v, p[4].v)
end

local dirty = false
local raceCar = RaceCarTracker(0)

try(function ()  
  local s = json.decode(ac.load('dbc'))
  table.forEach(p, function (v, i)
    v.v:set(s[i][1], s[i][2], s[i][3])
  end)
end, function (err)
  ac.debug('Error', err)
end)

function script.draw3D()
  local ray = render.createMouseRay()
  local rayDistance = ray:track()
  local mousePoint = ray.dir * rayDistance + ray.pos
  render.debugCross(mousePoint, 0.1)

  render.debugText((p[3].v + p[4].v) / 2, car2:freeDistanceTo(car1), rgbm(3, 3, 0, 1))

  table.clear(DebugShapes)
  render.debugText((p[1].v + p[2].v) / 2, car1:freeDistanceTo(car2), rgbm(3, 3, 0, 1))
  -- render.debugText((p[1].v + p[2].v) / 2, car1:freeDistanceTo(raceCar), rgbm(3, 3, 0, 1))
  -- render.debugText((p[3].v + p[4].v) / 2, car2:freeDistanceTo(car1), rgbm(3, 3, 0, 1))

  table.forEach(DebugShapes, function (item, key)
    render.debugCross(item, 0.5, rgbm(3, 0, 0, 1))
    render.debugText(item, key, rgbm(3, 0, 0, 1))
  end)

  local anyMoved = false
  table.forEach(p, function (item, i)
    -- if i > 2 or i == 1 then return end
    if item.m:render(item.v) then
      dirty = true
      anyMoved = true
    end
    if render.isPositioningHelperBusy() and item.m:movingInScreenSpace() and rayDistance ~= -1 then
      item.v:set(mousePoint)
    end
  end)

  if dirty and not anyMoved then
    ac.store('dbc', json.encode(table.map(p, function (item)
      return { item.v.x, item.v.y, item.v.z }
    end)))
  end

  -- local d = 0
  -- ac.perfBegin('d')
  -- for i = 1, 100000 do
  --   if i % 2 == 0 then 
  --     d = d + car1:freeDistanceTo(car2)
  --   else
  --     d = d + car2:freeDistanceTo(car1)
  --   end
  -- end
  -- ac.perfEnd('d')
end

return test