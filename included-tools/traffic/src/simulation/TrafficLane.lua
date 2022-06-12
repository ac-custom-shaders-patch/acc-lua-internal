local AABB = require('AABB')
local Array = require('Array')
local CubicInterpolatingLane = require('CubicInterpolatingLane')
local IntersectionLink = require('IntersectionLink')
local LaneCursor = require('LaneCursor')
local TrafficConfig = require('TrafficConfig')
local TrafficContext = require('TrafficContext')
local DistanceTags   = require('DistanceTags')

---@class EdgeMeta 
---@field dir number
---@field dirLengthInv number
---@field distanceToNextLink number @If there isn’t a link, a massive value (1e9)
---@field nextLink IntersectionLink|nil
---@field priority number
---@field spreadMult number
---@field speedLimit number
---@field allowLaneChanges boolean
---@field allowUTurns boolean
---@field side vec3
local _edgeMeta = {}

--- @param edge EdgeMeta
local function _debugMetaInfo(edge)
  return string.format('priority: %f\nspreadMult: %f\nspeedLimit: %f\ndistanceToNextLink: %f', edge.priority, edge.spreadMult, edge.speedLimit, edge.distanceToNextLink)
end

---@class TrafficLane : CubicInterpolatingLane
---@field id integer
---@field aabb AABB
---@field orderedCars LaneCursor[] @Stores cursors for cars on lane, from one that drove the most to one that just started to drive (highest distance goes first). New cars starting from beginning of the lane are added to the end. It’s important to keep this one sorted.
---@field priorityOffset number
---@field linkedIntersections IntersectionLink[] @First one is a link with smallest distance.
---@field edgesMeta EdgeMeta[]
local TrafficLane = class('TrafficLane', CubicInterpolatingLane)
local lastIndex = 0
local _msaturate = math.saturate

function TrafficLane:__tostring()
  return '<Lane: '..self.name..'>'
end

local vecUp = vec3(0, 1, 0)
local vecDown = vec3(0, -1, 0)

---@param laneDef SerializedLane
---@return TrafficLane
function TrafficLane:initialize(laneDef)
  lastIndex = lastIndex + 1
  self.index = lastIndex
  self.id = laneDef.id
  self.name = laneDef.name

  if #laneDef.points < (laneDef.loop and 3 or 2) then
    self.size = 0
    return
  end

  if laneDef.aabb then
    -- Properly finalized data
    CubicInterpolatingLane.initialize(self, laneDef.points, laneDef.loop)
    self.aabb = AABB(vec3.new(laneDef.aabb[1]), vec3.new(laneDef.aabb[2]))
  else
    -- Simply stuff from editor, need to resample and re-raycast
    local aabb = AABB()
    local baseLane = CubicInterpolatingLane(laneDef.points, laneDef.loop)
    for i = 1, #baseLane.points do
      aabb:extend(baseLane.points[i])
    end
    self.aabb = aabb:finalize()

    local length = math.ceil(baseLane.totalDistance / 3)
    local resampledPoints = Array(laneDef.loop and length or length + 1)
    resampledPoints[1] = baseLane.points[1]
    local loopLength = laneDef.loop and length - 1 or length
    for i = 1, loopLength do
      local p = baseLane:interpolate(baseLane:distanceToPointEdgePos(baseLane.totalDistance * i / length))
      p.y = p.y + 2
      local offset = physics.raycastTrack(p, vecDown, 4)
      p.y = p.y - (offset ~= -1 and offset or 2)
      resampledPoints[i + 1] = p
    end
    class.recycle(baseLane)
    CubicInterpolatingLane.initialize(self, resampledPoints, laneDef.loop, true)
  end

  -- Hashspace for world-spline coordinates conversion
  self.hashspace = ac.HashSpace(15)
  for i = 1, self.size do
    self.hashspace:addFixed(i, self.points[i])
    TrafficContext.lanesSpace:addFixed(self.id, self.points[i])
  end

  -- Some preprocessing for AIs
  self.priorityOffset = laneDef.priorityOffset
  self.edgesMeta = Array.range(self.size, function (i)
    local d = (self.points[i % self.size + 1] - self.points[i]):normalize()
    return {
      dir = d,
      dirLengthInv = d / self.edgesLength[i],
      priority = laneDef.priority or 0,
      spreadMult = 1,
      speedLimit = laneDef.speedLimit or 90,
      allowLaneChanges = laneDef.params.allowLaneChanges ~= false,
      allowUTurns = laneDef.params.allowUTurns == true,
      side = math.cross(d, vecUp)
    }
  end)

  self.linkedIntersections = Array()

  -- Dynamic storage
  self.orderedCars = Array()
end

function TrafficLane:finalize()
  for i = 1, self.size do
    local e = self.edgesMeta[i]
    local n = self.edgesMeta[i % self.size + 1]
    local straight = i > self.size - 2 and not self.loop and 1 or _msaturate(e.dir:dot(n.dir))
    local speedLimit = math.lerp(math.clamp(math.max(10, e.speedLimit * 0.2), 5, 30), e.speedLimit, straight ^ 2 or 0)

    local distance = self.edgesCubic[i].totalDistance
    local link = self:findClosestIntersectionLink(self.edgesCubic[i].totalDistance)
    if link ~= nil then
      e.nextLink = link
      local distanceToNextLink = self:distanceToUpcoming(distance, link.from)
      e.distanceToNextLink = distanceToNextLink
      if distanceToNextLink < 24 and speedLimit > 40 then        
        local interCloseness = math.lerpInvSat(distanceToNextLink, 24, 8)
        speedLimit = math.lerp(speedLimit, 40, interCloseness)
      end
    else
      e.distanceToNextLink = 1e9
    end

    e.speedLimit = speedLimit
  end

  for i = 10, self.size do
    local limit = self.edgesMeta[i].speedLimit
    local steps = math.min(i - 1, math.floor(40 - limit / 3))
    for j = 1, steps do
      local prev = self.edgesMeta[i - j]
      local localLimit = limit + j * 3
      if prev.speedLimit > localLimit then
        prev.speedLimit = localLimit
      end
    end
  end
end

local sim = ac.getSim()

function TrafficLane:addIntersectionLink(link)
  if not IntersectionLink.isInstanceOf(link) then error('Not a link') end
  self.linkedIntersections:push(link)
end

function TrafficLane:canSpawnAtBeginning()
  if not self.points[1]:closerToThan(sim.cameraPosition, TrafficConfig.maxSpawnDistance) then
    return false
  end

  local carsCount = self.orderedCars.length
  if carsCount == 0 then
    return true
  end

  local cars = self.orderedCars
  local lastCar = cars[carsCount]
  if lastCar.distance < 10 then
    return false
  end

  if self.loop and self.totalDistance - cars[1].distance < 10 then
    return false
  end
  
  return true
end

local function closestIntersectionLinkCallback(link, i, distance) return link.from > distance end

---Finds next intersection link.
---@param distance number @Lane distance (`0`…`totalDistance`)
function TrafficLane:findClosestIntersectionLink(distance)
  local linters = self.linkedIntersections
  local ret = linters[linters:findLeftOfIndex(closestIntersectionLinkCallback, distance) + 1]
  if ret == nil and self.loop and distance > self.totalDistance / 2 then
    ret = linters[1]
  end
  return ret
end

function TrafficLane:distanceTo(distanceThis, distanceNext)
  local ret = distanceNext - distanceThis
  if self.loop then
    if ret < -self.totalDistance / 2 then return self.totalDistance + ret end
    if ret > self.totalDistance - 30 then return ret - self.totalDistance end
  end
  return ret
end

function TrafficLane:distanceToUpcoming(distanceThis, distanceNext)
  local ret = distanceNext - distanceThis
  if self.loop and ret < -self.totalDistance / 2 then
    return self.totalDistance + ret
  end
  return ret
end

local function findClosestLeftIndexCallback(car, i, distance) return car.distance < distance end

---Finds index of a cursor which is just in front of given distance. Next cursor (`index + 1`) would 
---refer to a cursor behind given distance.
---@param distance number @Lane distance (`0`…`totalDistance`)
function TrafficLane:findClosestLeftIndex(distance)
  return self.orderedCars:findLeftOfIndex(findClosestLeftIndexCallback, distance)
end

---@param distance number @Lane distance (`0`…`totalDistance`)
---@param offset number
---@return number, CarBase|nil, DistanceTag
function TrafficLane:distanceToNextCar(distance, offset)
  if offset == nil then offset = 0 end
  local nextCursor = self.orderedCars[self:findClosestLeftIndex(distance + offset)]
  if nextCursor == nil then return 1e9, nil, DistanceTags.LaneEmpty end
  local baseDistance = nextCursor:rearDistance() - distance
  if baseDistance < offset or baseDistance > self.totalDistance then return 1e9, nil, DistanceTags.LaneEmpty end
  return baseDistance, nextCursor.driver:getCar(), DistanceTags.LaneCarInFront
end

local _mmin = math.min

---@param distance number @Lane distance (`0`…`totalDistance`).
---@return number @Distance to nearest car.
---@return LaneCursor|nil @Lane cursor following the given distance (use to to check their speed).
function TrafficLane:distanceToNearest(distance)
  local ordered = self.orderedCars
  if ordered.length == 0 then 
    return 1e9, nil
  end
  local nextCursorIndex = self:findClosestLeftIndex(distance)
  if nextCursorIndex == 0 then
    local followingCar = self.orderedCars[1]
    return followingCar and self:distanceTo(followingCar.distance, distance) or 1e9, followingCar
  else
    local nextCar = self.orderedCars[nextCursorIndex]
    local followingCar = self.orderedCars:at(nextCursorIndex + 1)
    return _mmin(
      nextCar and self:distanceTo(distance, nextCar.distance) or 1e9,
      followingCar and self:distanceTo(followingCar.distance, distance) or 1e9), followingCar
  end
end

---@param distance number @Lane distance (`0`…`totalDistance`).
---@return number @Distance to nearest obstacle (car, maneuver area, boundary).
---@return LaneCursor|nil @Lane cursor following the given distance (use to to check their speed).
function TrafficLane:freeSpace(distance)
  local ret, car = self:distanceToNearest(distance)
  local toEdge = _mmin(distance, self.totalDistance - distance)
  if toEdge < ret then
    ret = toEdge
  end

  local links = self.linkedIntersections
  local interBehindIndex = links:findLeftOfIndex(closestIntersectionLinkCallback, distance)
  local interBehind = links[interBehindIndex]
  local interInFront = links[interBehindIndex + 1]
  if ret == nil and self.loop and distance > self.totalDistance / 2 then
    ret = links[1]
  end

  if interBehind then
    local d = self:distanceTo(interBehind.to, distance)
    if d < ret then ret = d end
  end

  if interInFront then
    local d = self:distanceTo(distance, interInFront.from)
    if d < ret then ret = d end
  end

  return ret, car
end

local vecTmp = vec3()

---@param vPos vec3
---@param vDir vec3
---@param point integer
---@param edgePos number
---@param estimate boolean
function TrafficLane:getPositionDirectionInto(vPos, vDir, point, edgePos, estimate)
  local sf = edgePos < 0.5
  self:interpolateInto(vPos, point, edgePos, estimate)
  self:interpolateInto(vDir, point, sf and edgePos + 0.1 or edgePos - 0.1, estimate)
  if sf then vDir:sub(vPos)
  else vDir:scale(-1):add(vPos) end
  return vPos, vDir:normalize()
end

---@param v vec3
function TrafficLane:getDirectionInto(v, distance)
  local point, edgePos = self:distanceToPointEdgePos(distance)
  self:interpolateInto(v, point, edgePos + 0.01)
  self:interpolateInto(vecTmp, point, edgePos - 0.01)
  return v:sub(vecTmp):normalize()
end

function TrafficLane:getDirection(distance)
  local r = vec3()
  return self:getDirectionInto(r, distance)
end

local justJumped = true
local _randomPointPos = vec3()
local _mrandom = math.random
local _pcar = ac.getCar(0)

local function spawnPointFits(pos)
  if TrafficConfig.debugSpawnAround then
    if not justJumped and pos:closerToThan(sim.cameraPosition, 100) then return false end
    if not pos:closerToThan(sim.cameraPosition, 400) then return false end
  else
    if not pos:closerToThan(sim.cameraPosition, justJumped and TrafficConfig.distantSpawnFrom or TrafficConfig.distantSpawnTo) then return false end
    if not justJumped and pos:closerToThan(sim.cameraPosition, TrafficConfig.distantSpawnFrom) then return false end
  end

  if _pcar.pos:closerToThan(pos, 10) then return false end
  if TrafficContext.trackerBlocking:anyCloserThan(pos, 5) then return false end
  return true
end

function TrafficLane:randomDropSpot(r)
  if not self.aabb:closerToThan(sim.cameraPosition, TrafficConfig.distantSpawnTo) then return end

  -- if self.name ~= 'Lane #6' then return end

  local randomPoint = _mrandom(self.size - 2)
  local randomEdgePos = _mrandom()
  local distance = self.edgesCubic[randomPoint].totalDistance + self.edgesLength[randomPoint] * randomEdgePos
  if self.totalDistance - distance > 60 or self:endsWithIntersection() then 
    local randomPointPos = _randomPointPos:setLerp(self.points[randomPoint], self.points[randomPoint + 1], randomEdgePos)

    -- Spawning in front of player car to test driving behaviour
    -- if not randomPointPos:closerToThan(_pcar.pos + _pcar.look * 20, 20) then
    --   return (r or 0) < 100 and self:randomDropSpot((r or 0) + 1) or nil
    -- end

    -- if not randomPointPos:closerToThan(_pcar.pos, 10) then
    --   return (r or 0) < 100 and self:randomDropSpot((r or 0) + 1) or nil
    -- end

    if spawnPointFits(randomPointPos) then
      if not self.linkedIntersections:some(function (linked)
        return self:distanceTo(linked.to, distance) < 5 and self:distanceTo(linked.from, distance) > -5
      end) then
        local nlIndex = self:findClosestLeftIndex(distance)
        local nl = self.orderedCars:at(nlIndex)
        local nr = self.orderedCars:at(nlIndex + 1)
        if (nl == nil or nl.distance > distance + 10) and (nr == nil or nr.distance < distance - 10) then
          return distance
        end
      end
    end
  end

  if justJumped and (r or 0) < 10 then
    return self:randomDropSpot((r or 0) + 1)
  end

  return nil
end

function TrafficLane:startCursor(driver, startingDistance, precisePosition)
  if type(driver) ~= 'table' then error('Driver is required') end
  if startingDistance == nil then error('Starting distance is required') end

  if startingDistance == 0 then
    local ret = LaneCursor(self, 1, 0, self.orderedCars.length + 1, 0, driver)
    self.orderedCars:push(ret)
    return ret
  end

  local cursorIndex = self:findClosestLeftIndex(startingDistance)
  local edgeIndex, edgePos = self:distanceToPointEdgePos(startingDistance)
  if precisePosition ~= nil then
    -- TODO: to use this one, either resample spline so you wouldn’t need cubic, or figure out a
    -- a world→spline conversion route working with cubic
    -- edgePos = _relPos:set(precisePosition):sub(self.points[edgeIndex]):dot(self.edgesMeta[edgeIndex].dir) / self.edgesLength[edgeIndex]
  end
  local ret = LaneCursor(self, edgeIndex, edgePos, cursorIndex + 1, startingDistance, driver)
  local cars = self.orderedCars
  cars:insert(ret.index, ret)
  local carsCount = cars.length
  for i = cursorIndex + 2, carsCount do
    cars[i].index = i
  end
  return ret
end

function TrafficLane:startCursorOnEdge(driver, point, edgePos)
  if type(driver) ~= 'table' then error('Driver is required') end
  if point == nil then error('Starting distance is required') end
  if point >= self.size or point < 1 then error(string.format('Incorrect point value: %d (size=%d)', point, self.size)) end

  local startingDistance = self:pointEdgePosToDistance(point, edgePos)
  local cursorIndex = self:findClosestLeftIndex(startingDistance)
  local ret = LaneCursor(self, point, edgePos, cursorIndex + 1, startingDistance, driver)
  local cars = self.orderedCars
  cars:insert(ret.index, ret)
  local carsCount = cars.length
  for i = cursorIndex + 2, carsCount do
    cars[i].index = i
  end
  return ret
end

function TrafficLane:stop(cursor)
  local cars = self.orderedCars
  local N = cars.length
  if N == 0 then
    error('Empty lane')
  end

  if N == 1 and cars[1] == cursor then
    cars:clear()
    return
  end

  for i = 1, N do
    if cars[i] == cursor then
      for j = i + 1, N do
        local c = cars[j]
        cars[j - 1] = c
        c.index = j - 1
      end
      cars.length = N - 1
      return
    end
  end
end

function TrafficLane:restart(cursor)
  local cars = self.orderedCars
  local N = cars.length
  local m = false
  for i = 1, N - 1 do
    if cars[i] == cursor then
      m = true
    end
    if m then
      cars[i] = cars[i + 1]
      cars[i].index = i
    end
  end
  if m then
    cars[N] = cursor
    cursor.index = N
  end
end

function TrafficLane:interpolateDistance(distance)
  for i = 2, self.size do
    if self.edgesCubic[i].totalDistance > distance then
      return self:interpolate(i - 1, math.lerpInvSat(distance, self.edgesCubic[i - 1].totalDistance, self.edgesCubic[i].totalDistance))
    end
  end
  return self:interpolate(self.size, math.lerpInvSat(distance, self.edgesCubic[self.size].totalDistance - 0.0001, self.totalDistance))
end

function TrafficLane:startsWithIntersection()
  return self.linkedIntersections:some(function (link) return link.from == 0 end)
end

function TrafficLane:endsWithIntersection()
  return self.linkedIntersections:some(function (link) return link.to == self.totalDistance end)
end

---@param p vec3
function TrafficLane:worldToPointEdgePos(p)
  local from, to = self.hashspace:rawPointers(p)
  if from == to then
    return 0, 0
  end

  local ps = self.points
  local i1 = from[0]
  local p1 = ps[i1]
  local d1 = p:distanceSquared(p1)
  from = from + 1

  while from ~= to do
    local i = from[0]
    local pn = ps[i]
    local dn = p:distanceSquared(pn)
    if dn < d1 then
      i1, p1, d1 = i, pn, dn
    end
    from = from + 1
  end

  local p21 = ps[i1 - 1]
  local p22 = ps[i1 + 1]
  if not p22 or (p21 and p:distanceSquared(p21) < p:distanceSquared(p22)) then
    i1, p1 = i1 - 1, p21
  end

  local x, y, z = p.x - p1.x, p.y - p1.y, p.z - p1.z
  local i = self.edgesMeta[i1].dirLengthInv
  local d = x * i.x + y * i.y + z * i.z
  return i1, d < 0 and 0 or d > 1 and 1 or d
end

---@param p vec3
function TrafficLane:worldToDistance(p)
  return self:pointEdgePosToDistance(self:worldToPointEdgePos(p))
end

local _colorName = rgbm(3, 0.5, 0, 1)
local _colorLane = rgbm(0, 3, 3, 1)
local _sim = ac.getSim()

---@param layers TrafficDebugLayers
function TrafficLane:draw3D(layers)
  if not layers:near(self.aabb) then return end

  layers:with('Names', true, function ()
    -- render.debugText((self.points[1] + self.points[2]) / 2 + vec3(0, 5, 0), self.name, _colorName, 1.5)
    local d1 = self.points[1]:distanceSquared(_sim.cameraPosition)
    local d2 = self.points[#self.points]:distanceSquared(_sim.cameraPosition)
    render.debugText(d1 < d2 and self.points[1] or self.points[#self.points], self.name, _colorName, 0.7)
  end)

  for i = 2, self.size do
    if layers:near(self.points[i]) then
      render.debugArrow(self.points[i - 1], self.points[i], 0.5, _colorLane)
    end
  end

  layers:with('Intersection overlays', function ()
    for i = 2, self.size do
      if layers:near(self.points[i]) then
        local edgeFrom = self.edgesCubic[i - 1].totalDistance
        local edgeTo = self.edgesCubic[i].totalDistance
        for j = 1, self.linkedIntersections.length do
          local link = self.linkedIntersections[j]
          local from = (not self.loop or link.from < link.to) and link.from or 0
          if edgeFrom >= from and edgeTo <= link.to then
            render.debugLine(self.points[i - 1], self.points[i], rgbm(3, 0, 3, 1))
          elseif link.from > edgeFrom and link.to < edgeTo and link.to > link.from then
            render.debugLine(link.fromPos, link.toPos, rgbm(3, 0, 3, 1))
          elseif from > edgeFrom and from < edgeTo then
            render.debugLine(link.fromPos, self.points[i], rgbm(3, 0, 3, 1))
          elseif link.to > edgeFrom and link.to < edgeTo then
            render.debugLine(link.toPos, self.points[i - 1], rgbm(3, 0, 3, 1))
          end
        end
      end
    end
  end)

  layers:with('Nearest lane points', function ()
    local from, to = self.hashspace:rawPointers(layers:mousePoint())
    while from ~= to do
      local i = from[0]
      render.debugCross(self.points[i], 1, rgbm(0, 1, 0, 1))
      from = from + 1
    end
  end)

  layers:with('World-to-lane projection', function ()
    local point, edgePos = self:worldToPointEdgePos(layers:mousePoint())
    if point ~= 0 then
      local onLane = self:interpolate(point, edgePos)
      render.debugCross(onLane, 1, rgbm(0, 0, 3, 1))

      local meta = self.edgesMeta[point]
      render.debugText(onLane, _debugMetaInfo(meta), rgbm(0, 3, 0, 1), 0.8, render.FontAlign.Left)
    end
  end)

  if self.loop then
    render.debugArrow(self.points[self.size], self.points[1], 0.5, rgbm(0, 0.7, 3, 1))
    layers:with('Intersection overlays', function ()
      local edgeFrom = self.edgesCubic[self.size].totalDistance
      local edgeTo = 0
      for j = 1, self.linkedIntersections.length do
        local link = self.linkedIntersections[j]
        if link.from > edgeFrom and link.from < self.totalDistance then
          render.debugLine(link.fromPos, self.points[1], rgbm(3, 0, 3, 1))
        -- elseif link.to > edgeFrom and link.to < edgeTo then
        --   render.debugLine(link.toPos, self.points[i - 1], rgbm(3, 0, 3, 1))
        end
      end
    end)
  end

  layers:with('Intersection enters and exits', function ()
    for j = 1, #self.linkedIntersections do
      local link = self.linkedIntersections[j]
      if link.fromPos ~= nil then
        render.debugArrow(link.fromPos, link.fromPos + self:getDirection(link.from), 0.2, rgbm(0, 3, 0, 1))
        render.debugText(link.fromPos, string.format('from %s\nto %s at %.1f m\nside: %d', self, link.intersection, link.from, link.fromSide), rgbm(0, 3, 0, 1), 0.8, render.FontAlign.Left)
      end
      if link.toPos ~= nil then
        render.debugArrow(link.toPos, link.toPos + self:getDirection(link.to), 0.2, rgbm(3, 0, 0, 1))
        render.debugText(link.toPos, string.format('from %s\nto %s at %.1f m\nside: %d', link.intersection, self, link.to, link.toSide), rgbm(3, 0, 0, 1), 0.8, render.FontAlign.Left)
      end
    end
  end)

  local dbgText = nil

  layers:with('Cars on lanes', function ()
    dbgText = (dbgText and dbgText .. '\n' or '') .. string.format('%s: %d cars', self.name, #self.orderedCars)
    for i = 1, #self.orderedCars do
      local car = self.orderedCars[i]
      dbgText = dbgText .. string.format('\n  %d: %.2f', i, car.distance)

      local pos = self:interpolateDistance(car.distance)
      render.debugArrow(pos + vec3(0, 5, 0), pos, 0.5, rgbm(0, 3, 0, 1))
    end
  end)

  layers:with('Connected intersections', function ()
    dbgText = string.format('%s: %d intersections', self.name, #self.linkedIntersections)
    self.linkedIntersections:forEach(function (i)
      dbgText = string.format('%s\n  %s from: %f, to: %f', dbgText, i.intersection.name, i.from, i.to)
    end)
  end)

  if dbgText ~= nil then
    render.debugText((self.points[1] + self.points[2]) / 2 + vec3(0, 5, 0), dbgText, rgbm(3, 3, 3, 1), 1, render.FontAlign.Left)
  end
end

function TrafficLane.setJumped(value)
  justJumped = value
end

return class.emmy(TrafficLane, TrafficLane.initialize)