local RailroadSchedule = require 'RailroadSchedule'
local RailroadGate = require 'RailroadGate'
local RailroadTrainFactory = require 'RailroadTrainFactory'
local RailroadUtils = require 'RailroadUtils'

---@param line LineDescription
---@param from integer
---@param dir integer
local function getKey(line, from, dir)
  return bit.bxor(line.index, from * 397, dir * 397397)
end

---@param points vec3[]
local function getChunkKey(points)
  return tonumber(bit.bxor(ac.checksumXXH(points[1]), ac.checksumXXH(points[#points])))
end

---@alias RailroadTweaks {from: number, to: number, speedMultiplier: number, colliding: boolean, lights: boolean}
---@alias RailroadChunk {index: integer, line: LineDescription, points: vec3[], length: number, aabbFrom: vec3, aabbTo: vec3, connected: {chunk: RailroadChunk, chunkIndex: integer, ownIndex: integer}, name: string}

---@param chunks RailroadChunk[]
---@param point vec3
---@return RailroadChunk|nil
local function findNearestChunk(chunks, point)  
  local minDistance, minChunk = math.huge, nil
  for j = 1, #chunks do
    local chunk = chunks[j]
    if chunk.aabbFrom < point and chunk.aabbTo > point then
      for i = 2, #chunk.points do
        local d = point:distanceToLineSquared(chunk.points[i - 1], chunk.points[i])
        if d < minDistance then
          minDistance, minChunk = d, chunk
        end
      end
    end
  end
  return minChunk
end

---@param lines LineDescription[]
---@param stations vec3[]
---@return RailroadChunk[]
local function splitLinesToChunks(lines, stations)
  local space = ac.HashSpace(8)
  local stationsSpace = ac.HashSpace(40)

  for i = 1, #lines do
    local line = lines[i]
    for j = 1, #line.points do
      space:addFixed(i * 16384 + j, line.points[j])
    end
  end

  for i = 1, #stations do
    stationsSpace:addFixed(i, stations[i])
  end

  local chunks = {}
  local processed = {}
  local queue = table.map(lines, function (line) return {line, 1, 1} end)
  local foundIntersections = {}

  while #queue > 0 do
    local item = table.remove(queue, #queue)
    local line, size, from, dir = item[1], #item[1].points, item[2], item[3]
    local uniqueKey = getKey(line, from, dir)
    if not processed[uniqueKey] then
      processed[uniqueKey] = true

      local chunk = {}
      local previousStation
      for j = from, dir > 0 and size or 1, dir do
        local p = line.points[j]
        table.insert(chunk, p)

        space:iterate(p, function (id)
          local l, i = lines[math.floor(id / 16384)], id % 16384
          if l == line then return end

          local v = l.points[i]
          if v:closerToThan(p, 2) then
            if i == 1 then
              table.insert(foundIntersections, {l, i, 1})
            elseif i == #l.points then
              table.insert(foundIntersections, {l, i, -1})
            else
              table.insert(foundIntersections, {l, i, 1})
              table.insert(foundIntersections, {l, i, -1})
            end
          end
        end)

        local curStation = 0
        stationsSpace:iterate(p, function (id)
          curStation = bit.bxor(curStation * 397, id)
        end)

        if #foundIntersections > 0 or previousStation and previousStation ~= curStation then
          table.insert(queue, {line, j, dir})
          for i = 1, #foundIntersections do
            table.insert(queue, foundIntersections[i])
          end
          table.clear(foundIntersections)

          if #chunk > 1 then
            chunks[getChunkKey(chunk)] = {line = line, points = chunk, connected = {}}
          end

          if j > from then
            local newKey = getKey(line, j, dir)
            if processed[newKey] then break end
            processed[newKey] = true
          end

          chunk = {p}
        end

        previousStation = curStation
      end

      if #chunk > 1 then
        chunks[getChunkKey(chunk)] = {line = line, points = chunk, connected = {}}
      end
    end
  end
  return table.map(chunks, function (item) return item end)
end

---@param chunks RailroadChunk[]
local function setChunkConnections(chunks)
  local vertices = {}
  local function registerChunk(vertex, chunk, connectionPoint)
    for i = 1, #vertices do
      if vertices[i].point:closerToThan(vertex, 2) then
        table.insert(vertices[i].chunks, {chunk, connectionPoint})
        return
      end
    end
    table.insert(vertices, {point = vertex, chunks = {{chunk, connectionPoint}}})
  end

  for i = 1, #chunks do
    local chunk = chunks[i]
    local aabbFrom, aabbTo = vec3(math.huge, math.huge, math.huge), vec3(-math.huge, -math.huge, -math.huge)
    local len = 0
    for j = 1, #chunk.points do
      aabbFrom:min(chunk.points[j])
      aabbTo:max(chunk.points[j])
      if j > 1 then len = len + chunk.points[j]:distance(chunk.points[j - 1]) end
    end
    aabbFrom:add(-10)
    aabbTo:add(10)
    chunk.aabbFrom, chunk.aabbTo, chunk.length = aabbFrom, aabbTo, len
    chunk.name = string.format('<%.0f, %.0f>', (chunk.aabbFrom.x + chunk.aabbTo.x) / 2, (chunk.aabbFrom.z + chunk.aabbTo.z) / 2)
    chunk.index = i
    registerChunk(chunk.points[1], chunk, 1)
    registerChunk(chunk.points[#chunk.points], chunk, #chunk.points)
  end

  for i = 1, #vertices do
    table.forEach(vertices[i].chunks, function (chunk)
      local p1 = chunk[1].points[chunk[2]]
      local p2 = chunk[1].points[chunk[2] == 1 and 2 or chunk[2] - 1]
      table.forEach(vertices[i].chunks, function (other)
        if other == chunk then return end
        local o1 = other[1].points[other[2]]
        local o2 = other[1].points[other[2] == 1 and 2 or other[2] - 1]
        if math.dot(o2 - o1, p2 - p1) < 0 then
          table.insert(chunk[1].connected, {chunk = other[1], chunkIndex = other[2], ownIndex = chunk[2]})
        end
      end)
    end)
  end
end

---@param lines LineDescription[]
---@param stations vec3[]
---@return RailroadChunk[]
local function convertToGraph(lines, stations)
  local chunks = splitLinesToChunks(lines, stations)
  setChunkConnections(chunks)
  return chunks
end

---@param chunkFrom RailroadChunk
---@param chunkTo RailroadChunk
---@param preceedingIndex integer|nil
---@return RailroadChunk[]
local function findRoute(chunkFrom, chunkTo, preceedingIndex, followingIndex)
  local visited = {}
  local queue, n = {{chunkFrom, 0, {chunkFrom}, preceedingIndex}}, 1
  local foundDistance, found = math.huge, nil
  while n > 0 do
    local i = queue[n]
    local c = i[1] ---@type RailroadChunk
    n = n - 1
    local anyFound = false
    for j = 1, #c.connected do
      if c.connected[j].ownIndex ~= i[4] then
        local h = c.connected[j].chunk ---@type RailroadChunk
        local k = h.index * 10000 + c.connected[j].chunkIndex
        if h == chunkTo and c.connected[j].ownIndex ~= followingIndex then
          if i[2] < foundDistance then
            foundDistance, found = i[2], table.chain(i[3], {h})
          end
        else
          if not visited[k] or visited[k] > i[2] then
            visited[k] = i[2]
            queue[n + 1], n = {h, i[2] + h.length * (h.line.priority or 1), table.chain(i[3], {h}), c.connected[j].chunkIndex}, n + 1
          end
          anyFound = true
        end
      end
    end
    if not anyFound and not chunkTo then
      foundDistance, found = i[2], i[3]
    end
  end
  return found --or error('No route found')
end

---@param chunk RailroadChunk
---@param previousChunk RailroadChunk
---@return integer
local function findContinuationIndex(chunk, previousChunk)
  for i = 1, #chunk.connected do
    if chunk.connected[i].chunk == previousChunk then
      return chunk.connected[i].ownIndex
    end
  end
end

---@param stations {[1]: StationDescription, [2]: RailroadChunk}[]
---@param looped boolean
local function collectChunks(stations, looped)
  for i = 2, #stations do
    if stations[i - 1][2] == stations[i][2] then
      error(string.format('Stations %s and %s are within the same chunk, move them closer to vertices', stations[i - 1][1].name, stations[i][1].name))
    end
  end

  local route = findRoute(stations[1][2], stations[2][2])
  if not route then
    error(string.format('Can’t find route from %s (%s) to %s (%s)',
      stations[1][1].name, stations[1][2].name, stations[2][1].name, stations[2][2].name))
  end

  for i = 3, looped and #stations or #stations + 1 do
    local nextPiece = findRoute(stations[i - 1][2], stations[i] and stations[i][2], 
      findContinuationIndex(route[#route], route[#route - 1]))
    if not nextPiece and i <= #stations then
      error(string.format('Can’t find route from %s (%s) to %s (%s)',
        stations[i - 1][1].name, stations[i - 1][2].name, stations[i][1].name, stations[i][2].name))
    end
    if nextPiece then
      if nextPiece[1] ~= route[#route] then
        error('Unexpected continuation')
      end
      route = table.chain(route, table.slice(nextPiece, 2))
    end
  end

  if looped then
    local nextPiece = findRoute(stations[#stations][2], stations[1][2], 
      findContinuationIndex(route[#route], route[#route - 1]), findContinuationIndex(route[2], route[1]))
    if not nextPiece then
      error(string.format('Can’t find route from %s (%s) to %s (%s)',
        stations[#stations][1].name, stations[#stations][2].name, stations[1][1].name, stations[1][2].name))
    else
      route = table.chain(route, table.slice(nextPiece, 2, #nextPiece - 1))
    end
  else
    local nextPiece = findRoute(stations[1][2], nil, findContinuationIndex(route[1], route[2]))
    if nextPiece ~= nil then
      route = table.chain(table.reverse(nextPiece), table.slice(route, 2))
    end
  end

  return route
end

---@param chunks RailroadChunk[]
---@param looped boolean
---@return vec3[]
---@return RailroadTweaks[]
local function extractSplineFromChunks(chunks, looped)
  local s = findContinuationIndex(chunks[1], chunks[2]) == 1 and 0 or 1
  local p, n = {chunks[1].points[s == 1 and 1 or #chunks[1].points]}, 2
  local m, d = {}, 0
  for i = 1, #chunks do
    local c = chunks[i]
    local x = i > 1 and findContinuationIndex(chunks[i], chunks[i - 1]) or s
    for j = x == 1 and 2 or #c.points - 1, x == 1 and #c.points or 1, x == 1 and 1 or -1 do
      p[n], n = c.points[j], n + 1
    end
    local l = c.length
    table.insert(m, {from = d, to = d + l, speedMultiplier = c.line.speedMultiplier or 1, colliding = c.line.colliding or false, lights = c.line.lights or false})
    d = d + l
  end
  for i = 1, #m do
    m[i].from, m[i].to = m[i].from / d, m[i].to / d
  end
  return p, m
end

---@class Railroad
---@field schedules RailroadSchedule[]
---@field gates RailroadGate[]
---@field trainFactory RailroadTrainFactory
Railroad = class 'Railroad'

---@param data RailroadData
---@return Railroad
function Railroad.allocate(data)
  RailroadUtils.raiseSettingsUpdate(data.settings or {})
  local trainFactory = RailroadTrainFactory(data.trains)

  ac.log('Creating graph')
  local stationPoints = table.map(data.stations, function (item) return item.position end)
  local chunks = convertToGraph(data.lines, stationPoints)

  ac.log('Mapping stations')
  local mappedStations = table.map(data.stations, function (item)
    return {
      item,
      findNearestChunk(chunks, item.position) or error('Station '..item.name..' is too far from any lanes')
    }, item.index
  end)

  ac.log('Mapping schedules')
  local mappedSchedules = table.map(data.schedules, function (item) ---@param item ScheduleDescription
    return RailroadUtils.tryCreate(item, function ()
      local pathChunks = collectChunks(table.map(item.points, function (point) ---@param point SchedulePointDescription
        return mappedStations[point.station] or error('Station is missing: '..point.station)
      end), item.looped)
      local spline, tweaks = extractSplineFromChunks(pathChunks, item.looped)
      return RailroadSchedule(item, table.map(item.points, function (point) return mappedStations[point.station][1].position end), spline, tweaks, trainFactory)
    end)
  end)

  ac.log('Mapping gates')
  local mappedGates = table.map(data.gates, function (gate) ---@param gate GateDescription
    return RailroadUtils.tryCreate(gate, function ()
      local hits = table.map(mappedSchedules, function (item) ---@param item RailroadSchedule
        local located = item:locate(gate.position)
        if located and gate.colliding then
          table.insert(item.collidingGatesLocations, located)
        end
        return located and { located, item } or nil
      end)
      if #hits == 0 then
        ac.warn('No lines found next to a gate: '..gate.name)
        return nil
      end
      return RailroadGate(gate, hits)
    end)
  end)

  for i = 1, #mappedSchedules do
    local s = mappedSchedules[i] ---@type RailroadSchedule
    table.sort(s.collidingGatesLocations, function (a, b) return a < b end)
  end

  return {schedules = mappedSchedules, gates = mappedGates, trainFactory = trainFactory}
end

function Railroad:initialize()
  ac.log('Graph created')
end

function Railroad:dispose()
  for i = 1, #self.schedules do
    self.schedules[i]:dispose()
  end
  for i = 1, #self.gates do
    self.gates[i]:dispose()
  end
  self.trainFactory:dispose()
end

function Railroad:update(dt)
  for i = 1, #self.schedules do
    self.schedules[i]:update(dt)
  end
  for i = 1, #self.gates do
    self.gates[i]:update(dt)
  end
end

return class.emmy(Railroad, Railroad.allocate)
