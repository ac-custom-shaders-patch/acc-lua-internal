local DAY_DURATION = 24 * 60 * 60          -- How long is a day, in seconds
local GATE_COLLIDER_ACTIVE_DISTANCE = 200  -- Trains would have their colliders activated if closer than this to a gate, in meters
local GATE_CLOSE_DISTANCE = 200            -- Gates would close if there is a train closer than this, in meters
local GATE_OPEN_DISTANCE = 50              -- Gates would open once train gets further than this from them, in meters
local SURFACE_MESHES = nil                 -- Names of surface meshes

local LineResampler = require 'LineResampler'
local RailroadUtils = require 'RailroadUtils'

RailroadUtils.onSettingsUpdate(function (settings)
  GATE_COLLIDER_ACTIVE_DISTANCE = tonumber(settings.gateColliderActiveDistance) or GATE_COLLIDER_ACTIVE_DISTANCE
  GATE_CLOSE_DISTANCE = tonumber(settings.gateCloseDistance) or GATE_CLOSE_DISTANCE
  GATE_OPEN_DISTANCE = tonumber(settings.gateOpenDistance) or GATE_OPEN_DISTANCE
  SURFACE_MESHES = tostring(settings.surfaceMeshes or '')
end)

---@class RailroadSchedule
---@field definition ScheduleDescription
---@field stations vec3[]
---@field stationTimes integer[]
---@field spline vec3[]
---@field normalSpline vec3[]
---@field length number
---@field grid ac.HashSpace
---@field stationLocations number[]
---@field collidingGatesLocations number[]
---@field timeToPositionLut {time: number, pos: number}[]
---@field trainFactory RailroadTrainFactory
---@field trains RailroadTrain[]
---@field tweaks RailroadTweaks[]
---@field doorsOpenedTimes {[1]: number, [2]: number}[]
---@field anyGateNear integer
---@field anyCollidingLane boolean
---@field anyLightsLane boolean
local RailroadSchedule = class 'RailroadSchedule'

---@param definition ScheduleDescription
---@param stations vec3[]
---@param spline vec3[]
---@param tweaks RailroadTweaks[]
---@param trainFactory RailroadTrainFactory
---@return RailroadSchedule
function RailroadSchedule.allocate(definition, stations, spline, tweaks, trainFactory)
  for _ = 1, 2 do
    spline = LineResampler(spline, definition.looped and spline[#spline - 1], definition.looped and spline[2])
  end

  local normalSpline
  if SURFACE_MESHES and #SURFACE_MESHES > 0 then
    local surfaces = ac.findNodes('trackRoot:yes'):findMeshes('{'..SURFACE_MESHES..'}')
    if #surfaces > 0 then
      local ray = render.createRay(vec3(), vec3(0, -1, 0))
      local normal, normalIndex = vec3(0, 1, 0), 1
      local hitmesh = ac.emptySceneReference()
      normalSpline = {}
      for i = 1, #spline, 4 do
        local item = spline[i]
        ray.pos:set(item)
        ray.pos.y = ray.pos.y + 1
        normalSpline[normalIndex], normalIndex = normal, normalIndex + 1
        if surfaces:raycast(ray, hitmesh, nil, normal) ~= -1 then
          normal = vec3(0, 1, 0)
        end
      end
    end
  end

  local length = definition.looped and spline[#spline]:distance(spline[1]) or 0
  for i = 2, #spline do
    length = length + spline[i - 1]:distance(spline[i])
  end

  local grid = ac.HashSpace(10)
  for i = 1, #spline do
    grid:addFixed(i, spline[i])
  end

  local stationTimes, timeOffset = {}, 0
  for i = 1, #stations do
    local time = definition.points[i].time + timeOffset
    if #stationTimes > 0 and time < stationTimes[#stationTimes] then
      timeOffset = timeOffset + DAY_DURATION
      time = time + DAY_DURATION
    end
    table.insert(stationTimes, time)
  end

  return {
    definition = definition,
    stations = stations,
    stationTimes = stationTimes,
    collidingGatesLocations = {},
    spline = spline,
    normalSpline = normalSpline,
    tweaks = tweaks,
    length = length,
    grid = grid,
    trainFactory = trainFactory,
    anyGateNear = 0,
    anyCollidingLane = table.some(tweaks, function (item) return item.colliding end),
    anyLightsLane = table.some(tweaks, function (item) return item.lights end),
  }
end

---@param spline vec3[]
---@param out vec3
---@param location number @From 0 to 1.
---@return vec3
local function getSplineValue(spline, out, location)
  location = math.clamp(location, 0.000001, 0.999999)
  local v = location * (#spline - 1)
  local i = math.floor(v)
  return out:setLerp(spline[i + 1], spline[i + 2], v - i)
end

---@param spline vec3[]
---@param location number @From 0 to 1.
---@return number
local function getSplineValueY(spline, location)
  location = math.clamp(location, 0.000001, 0.999999)
  local v = location * (#spline - 1)
  local i = math.floor(v)
  return math.lerp(spline[i + 1].y, spline[i + 2].y, v - i)
end

local function callbackFindTweaks(item, _, basePos)
  return basePos < item.from
end

---@param dst {time: number, pos: number}[]
---@param spline vec3[]
---@param tweaks RailroadTweaks[]
---@param length number
---@param from {time: number, pos: number}
---@param to {time: number, pos: number}
---@param o integer
local function interpolateMovement(dst, spline, tweaks, length, from, to, o)
  local time = math.max(to.time - from.time, 10 * 60)
  local acceleration = math.max(20 * 60, time * 0.1)  -- time it takes to get to the full speed (and to slow down)
  local m = math.min(acceleration / time, 0.45)       -- half of how much of time between stations is spent accelerating and decelerating
  local p = 2                                         -- how intense are accelerations and decelerations
  local s = 1 / (p - 2 * m * (p - 1))

  local steps = math.clamp(math.floor(time / 150), 20, 200)
  local previousPos = from.pos
  local previousTime = from.time
  local previousPosY = getSplineValueY(spline, from.pos)
  local totalTime = 0
  local timeMultSmooth = 1

  -- On first pass record time deltas between frames instead of actual times, and keep track of total time
  for i = 1, steps - 1 do
    -- Smoothstep here distributes more points towards the ends, to add more details there
    local j = (i / steps + math.smoothstep(i / steps)) / 2
    local x = j > 1 - m and 1 - m * math.lerpInvSat(j, 1, (1 - m)) ^ p * s
      or j < m and m * math.lerpInvSat(j, 0, m) ^ p * s or math.lerp(m * s, 1 - m * s, math.lerpInvSat(j, m, (1 - m)))

    -- Twist ends if this is the first or last bit: we don’t need to fully stop on enters and exists
    if o == -1 then x = math.lerp(j, x, math.min(j * 2, 1))
    elseif o == 1 then x = math.lerp(j, x, math.min(2 - j * 2, 1)) end

    -- Base position and time values
    local basePos = math.lerp(from.pos, to.pos, x)
    local baseTime = math.lerp(from.time, to.time, j)

    -- Slightly alter speed based on altitude changes
    local posY = getSplineValueY(spline, basePos)
    local dPosY = (posY - previousPosY) * 4
    if math.abs(dPosY) > 0.6 then dPosY = dPosY * 0.6 / math.abs(dPosY) end
    local timeMult = 1 + dPosY / (1 + math.abs(dPosY))

    -- Some lines might need train to move faster or slower
    local tweaksIndex = table.findLeftOfIndex(tweaks, callbackFindTweaks, basePos)
    if tweaksIndex > 0 then
      timeMult = timeMult / tweaks[tweaksIndex].speedMultiplier
    end
    timeMultSmooth = math.lerp(timeMultSmooth, timeMult, 0.2)

    -- Frame in semi-prepared state is ready
    local dt = baseTime - previousTime
    table.insert(dst, {time = dt * timeMultSmooth, pos = basePos})
    if i > 1 then totalTime = totalTime + dt * timeMultSmooth end

    -- Checking if speed is not too high
    local speed = (basePos - previousPos) * length / (dt * timeMultSmooth)
    if dt == 0 or speed > 200 then
      error('Speed is too high: '..(speed * 3.6)..' km/h. Verify schedule timings, station delays might be too high')
    end

    -- Updating previous values
    previousTime, previousPos, previousPosY = baseTime, basePos, posY
  end

  -- Then, do another pass, set time to actual values, but also rescale it to make sure we fit the schedule with all those speed variations
  local i1 = #dst - (steps - 2)
  local i2 = #dst
  local t1 = math.lerp(from.time, to.time, (1 / steps + math.smoothstep(1 / steps)) / 2)
  local t2 = math.lerp(from.time, to.time, ((steps - 1) / steps + math.smoothstep((steps - 1) / steps)) / 2)
  local timeMult = (t2 - t1) / totalTime

  dst[i1].time = t1
  dst[i2].time = t2
  for i = i1 + 1, i2 - 1 do
    local d = dst[i]
    t1 = t1 + d.time * timeMult
    d.time = t1
  end

  table.insert(dst, to)
end

function RailroadSchedule:initialize()
  self.stationLocations = {}
  self.stationSides = {}
  for i = 1, #self.stations do
    local location, side = self:locate(self.stations[i])
    if not location then
      error('Failed to locate: '..tostring(self.stations[i]))
    end
    table.insert(self.stationLocations, location)
    table.insert(self.stationSides, side)
  end

  local totalScheduleTime = self.stationTimes[#self.stationTimes] - self.stationTimes[1]
  local totalScheduleDistance = (self.stationLocations[#self.stationLocations] - self.stationLocations[1])
  local averageSpeed = totalScheduleDistance / totalScheduleTime -- P/s, where P is normalized position
  local timeToFirstStation = self.stationLocations[1] / averageSpeed
  local timeToLastStation = (1 - self.stationLocations[#self.stationLocations]) / averageSpeed
  local totalTime = totalScheduleTime + timeToFirstStation + timeToLastStation -- in seconds
  local startingTime = self.stationTimes[1] - timeToFirstStation
  if startingTime < -1e6 then error('Starting time is too negative') end
  
  if self.definition.looped then
    local newTotalTime = math.ceil(totalTime / DAY_DURATION) * DAY_DURATION
    local totalTimeIncrease = newTotalTime / totalTime
    timeToFirstStation = timeToFirstStation * totalTimeIncrease
    timeToLastStation = timeToLastStation * totalTimeIncrease
    totalTime = newTotalTime
    startingTime = self.stationTimes[1] - timeToFirstStation
  end

  while startingTime < 0 do
    startingTime = startingTime + DAY_DURATION
    for i = 1, #self.stationTimes do
      self.stationTimes[i] = self.stationTimes[i] + DAY_DURATION
    end
  end

  local daysForRun = math.ceil((startingTime + totalTime) / DAY_DURATION)
  local timeToPositionLut = {{time = startingTime, pos = 0}}
  local doorsOpenedTimes = {}
  for i = 1, #self.stationLocations do
    local p = self.stationLocations[i]
    local stationaryTime = self.definition.points[i].duration or (10 * 60)
    if stationaryTime > 0 then
      local doorsOpenDelay = math.min(30, stationaryTime * 0.2)
      local doorsCloseDelay = math.min(60, stationaryTime * 0.2)
      interpolateMovement(timeToPositionLut, self.spline, self.tweaks, self.length, timeToPositionLut[#timeToPositionLut], {time = self.stationTimes[i] - stationaryTime * 0.5, pos = p}, i == 1 and -1 or 0)
      table.insert(timeToPositionLut, {time = self.stationTimes[i] + stationaryTime * 0.5, pos = p})
      table.insert(doorsOpenedTimes, {self.stationTimes[i] - stationaryTime * 0.5 + doorsOpenDelay, self.stationTimes[i] + stationaryTime * 0.5 - doorsCloseDelay})
    end
  end
  interpolateMovement(timeToPositionLut, self.spline, self.tweaks, self.length, timeToPositionLut[#timeToPositionLut], {time = startingTime + totalTime, pos = 1}, 1)

  --[[ timeToPositionLut = LineResampler(timeToPositionLut, nil, nil, {
    distance = function (a, b) return math.abs(b.time - a.time) end,
    empty = function () return {time = 0, pos = 0} end,
    add = function (a, b, m)
      a.time = a.time + b.time * m
      a.pos = a.pos + b.pos * m
    end,
    step = 20
  }) ]]

  --[[ _G['debugUI'] = function ()
    local w = ui.availableSpaceY() / 1.2
    local s = ui.availableSpaceX() / (1.2 * DAY_DURATION)
    for i = 2, #self.timeToPositionLut do
      local p1 = self.timeToPositionLut[i - 1]
      local p2 = self.timeToPositionLut[i]
      ui.drawLine(vec2(p1.time * s, p1.pos * w), vec2(p1.time * s, p1.pos * w - 10), rgbm.colors.yellow)
      ui.drawLine(vec2(p1.time * s, p1.pos * w), vec2(p2.time * s, p2.pos * w), rgbm.colors.red)
    end
  end ]]

  self.timeToPositionLut = timeToPositionLut
  self.doorsOpenedTimes = doorsOpenedTimes
  self.trains = table.range(daysForRun, function () return self.trainFactory:get(self.definition.train) end)
end

function RailroadSchedule:getStationSide(scheduleTime)
  local i = table.findLeftOfIndex(self.doorsOpenedTimes, function (item, index, scheduleTime_)
    return item[1] > scheduleTime_
  end, scheduleTime + 1)
  local f = self.doorsOpenedTimes[i]
  if f and scheduleTime > f[1] and scheduleTime < f[2] then
    return self.stationSides[i]
  end
  return 0
end

function RailroadSchedule:getTrainTime(trainIndex)
  local day = (self.currentDay + trainIndex) % #self.trains
  return day * DAY_DURATION + self.currentTime
end

function RailroadSchedule:isPointBusy(point, collidingGate)
  local ret = false
  for i = 1, #self.trains do
    local train = self.trains[i]
    local isNearby = train.position > point - GATE_CLOSE_DISTANCE / self.length and train.position < point + (GATE_OPEN_DISTANCE + train.length) / self.length
    if isNearby then
      if collidingGate then self.anyGateNear = 2 end
      ret = true
    end
  end
  return ret
end

local function callbackAreCollidingGatesNearby(item, _, point)
  return item > point
end

function RailroadSchedule:areLightsForcedOn(point)
  if not self.anyLightsLane then return false end
  local tweaksIndex = table.findLeftOfIndex(self.tweaks, callbackFindTweaks, point)
  return tweaksIndex > 0 and self.tweaks[tweaksIndex].lights
end

function RailroadSchedule:needsActiveCollider(point)
  if self.anyCollidingLane then
    local tweaksIndex = table.findLeftOfIndex(self.tweaks, callbackFindTweaks, point)
    if tweaksIndex > 0 and self.tweaks[tweaksIndex].colliding then
      return true
    end
  end

  if self.anyGateNear == 0 then return false end
  local i = table.findLeftOfIndex(self.collidingGatesLocations, callbackAreCollidingGatesNearby, point + GATE_COLLIDER_ACTIVE_DISTANCE / self.length)
  return i > 0 and math.abs(self.collidingGatesLocations[i] - point) < GATE_COLLIDER_ACTIVE_DISTANCE / self.length
end

local function callbackGetNormalizedPositionByTime(item, _, time)
  return item.time > time
end

---@param time number
---@return number
function RailroadSchedule:getNormalizedPositionByTime(time)
  local i = table.findLeftOfIndex(self.timeToPositionLut, callbackGetNormalizedPositionByTime, time)
  if i == 0 or i == #self.timeToPositionLut then
    return nil
  end
  local p1 = self.timeToPositionLut[i]
  local p2 = self.timeToPositionLut[i + 1]
  return math.lerp(p1.pos, p2.pos, math.lerpInvSat(time, p1.time, p2.time))
end

---@param out vec3
---@param location number @From 0 to 1.
---@return vec3
function RailroadSchedule:getPositionTo(out, location)
  if self.definition.looped then
    location = math.fmod(location + 1, 1)
  end
  return getSplineValue(self.spline, out, location)
end

---@param out vec3
---@param location number @From 0 to 1.
---@return vec3
function RailroadSchedule:getNormalTo(out, location)
  if self.normalSpline then 
    return getSplineValue(self.normalSpline, out, location)
  else
    return out
  end
end

---@param pos vec3
---@return number? @From 0 to 1
---@return number? @Side, either 1 or -1
function RailroadSchedule:locate(pos)
  local closest, closestDistance = nil, math.huge
  self.grid:iterate(pos, function (id)
    local p1, p2 = self.spline[id], self.spline[id % #self.spline + 1]
    local distance = pos:distanceToLineSquared(p1, p2)
    if distance < closestDistance then
      closest, closestDistance = id, distance
    end
  end)
  if closest == nil then return nil end
  local dpos = pos - self.spline[closest]
  local dedge = self.spline[closest % #self.spline + 1] - self.spline[closest]
  closest = closest + math.dot(dpos, dedge) / dedge:lengthSquared()
  local side = math.sign(math.cross(dedge, dpos).y)
  return (closest - 1) / (#self.spline - 1), side
end

function RailroadSchedule:dispose()
  for i = 1, #self.trains do
    self.trainFactory:release(self.trains[i])
  end
  table.clear(self.trains)
end


function RailroadSchedule:update(dt)
  if self.anyGateNear > 0 then self.anyGateNear = self.anyGateNear - 1 end

  local trackTime = ac.getTrackDateTime()
  if trackTime == 0 then return end

  self.currentDay = math.floor(trackTime / DAY_DURATION)
  self.currentTime = trackTime % DAY_DURATION

  for i = 1, #self.trains do
    local time = self:getTrainTime(i)
    local seed = self.currentDay - math.floor(time / DAY_DURATION)
    local offset = (math.seededRandom(bit.bor(seed, self.definition.index % 397)) - 0.5) * self.definition.variation
    local position = self:getNormalizedPositionByTime(time + offset)
    ac.debug('Train #'..i, string.format('Time: %.2f, position: %.8s', time, position))
    self.trains[i]:update(self, position, self:getStationSide(time), dt, seed)
  end
end

function RailroadSchedule:draw3D()
  for i = 2, #self.spline do
    render.debugArrow(self.spline[i - 1], self.spline[i])
    if self.normalSpline then
      render.debugArrow(self.spline[i], self.spline[i] + self.normalSpline[i])
    end
  end

  local r = render.createMouseRay()
  local p = r.pos + r.dir * r:track()
  local l = self:locate(p)
  if l then
    render.debugCross(self:getPositionTo(vec3(), l), 4)
  end
end

return class.emmy(RailroadSchedule, RailroadSchedule.allocate)
