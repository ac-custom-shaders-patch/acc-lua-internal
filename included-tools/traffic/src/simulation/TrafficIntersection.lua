local Array = require('Array')
local CachingCurve = require('CachingCurve')
local FlatPolyShape = require('FlatPolyShape')
local IntersectionManeuver = require('IntersectionManeuver')
local IntersectionLink = require('IntersectionLink')
local IntersectionSide = require('IntersectionSide')
local MathUtils = require('MathUtils')
local TrafficConfig = require('TrafficConfig')
local TrafficLight = require('TrafficLight')

---@param fd IntersectionLink
---@param td IntersectionLink
---@param attr SerializedTrajectoryAttributes
---@return CachingCurve
local function curvesFactory(fd, td, attr)
  -- ac.log('Creating new curve: ' .. math.random())
  local p1, d1 = fd:getFromPosDir()
  local p2, d2 = td:getToPosDir()
  return CachingCurve(p1, d1, p2, d2, false, attr)
end

---@class TrafficIntersection
---@field shape FlatPolyShape
---@field _linksList IntersectionLink[]
---@field _sides IntersectionSide[]
---@field engaged IntersectionManeuver[]|Array
---@field traversing IntersectionManeuver[]|Array
---@field _index integer Set by TrafficGraph.
---@field _loadingDef SerializedIntersection
---@field _incompatibleTable table<TrafficLane, table<TrafficLane, integer>>
---@field _priorityTable table<TrafficLane, table<TrafficLane, boolean>>
---@field mergingIntersection boolean
local TrafficIntersection = class('TrafficIntersection')

function TrafficIntersection:__tostring()
  return '<Intersection: '..self.name..'>'
end

---@param intersectionDef SerializedIntersection
---@return TrafficIntersection
function TrafficIntersection:initialize(intersectionDef)
  self.id = intersectionDef.id
  self.name = intersectionDef.name
  self.shape = FlatPolyShape(intersectionDef.points[1][2], TrafficConfig.intersectionYThreshold,
    intersectionDef.points, function (t) return vec2(t[1], t[3]) end)

  self._loadingDef = intersectionDef

  self._linksList = Array()
  self._incompatibleTable = {}
  self._priorityTable = {}
  self._entryPrioritiesTable = {}
  self._sides = Array(intersectionDef.points, function (t, i)
    return IntersectionSide(i, t, intersectionDef.points[i % #intersectionDef.points + 1])
  end)

  self.engaged = Array()
  self.traversing = Array()

  self.phase = 0
  self.lowestPhase = 0
  self.mergingIntersection = false

  if intersectionDef.entryPriorityOffsets ~= nil then
    table.forEach(intersectionDef.entryPriorityOffsets, function (item)
      self._entryPrioritiesTable[item.lane] = item.offset
    end)
  end

  if intersectionDef.trafficLight ~= nil then
    self.trafficLight = TrafficLight(intersectionDef.trafficLight, self)
  end
end

---@param guide TrafficGuide
---@param currentLane TrafficLane
---@param currentLanePosition number
---@param desiredLane TrafficLane
---@param desiredLanePosition number
---@return IntersectionManeuver
function TrafficIntersection:engage(guide, currentLane, currentLanePosition, desiredLane, desiredLanePosition)
  local ret = IntersectionManeuver(self, guide,
    self:findDefFrom(currentLane, currentLanePosition),
    self:findDefTo(desiredLane, desiredLanePosition))
  self.engaged:push(ret)
  return ret
end

---@param fromDef IntersectionLink
---@param toDef IntersectionLink
---@return CachingCurve
function TrafficIntersection:getCachingCurve(fromDef, toDef)
  local l = self.trajectoryAttributes[fromDef.lane]
  local a = l and l[toDef.lane] or nil
  return fromDef.curves:get(toDef, curvesFactory, fromDef, toDef, a)
end

---@param engaged IntersectionManeuver
function TrafficIntersection:disconnectEngaged(engaged)
  if not self.engaged:remove(engaged, true) then
    ac.log('Removing non-engaged inter. maneuver')
    return
  end

  local traversing = self.traversing
  if traversing:remove(engaged, true) and engaged.phase == self.lowestPhase then
    local newLowestPhase = self.phase
    for i = 1, traversing.length do
      local tPhase = traversing[i].phase
      if tPhase < newLowestPhase then
        newLowestPhase = tPhase
      end
    end
    self.lowestPhase = newLowestPhase
  end
end

---@param lane TrafficLane
---@param lanePosition number
---@return IntersectionLink
function TrafficIntersection:findDefFrom(lane, lanePosition)
  return self._linksList:findFirst(function (def)
    return def.lane == lane and math.abs(def.lane:distanceTo(lanePosition, def.from)) < 1
  end) or error(string.format('%s does not start from %s at %.1f m', self, lane, lanePosition))
end

---@param lane TrafficLane
---@param lanePosition number
---@return IntersectionLink
function TrafficIntersection:findDefTo(lane, lanePosition)
  return self._linksList:findFirst(function (def)
    return def.lane == lane and math.abs(def.lane:distanceTo(lanePosition, def.to)) < 1
  end) or ErrorPos(string.format('%s does not end with %s at %.1f m', self, lane, lanePosition), lane:interpolateDistance(lanePosition))
end

---@param link IntersectionLink
function TrafficIntersection:_addLink(link)
  self._linksList:push(link)
  local side = self._sides:at(link.fromSide)
  if side ~= nil then side.entries:push(link) end
  local to = self._sides:at(link.toSide)
  if to ~= nil then to.exits:push(link) end
end

---@param lane TrafficLane
function TrafficIntersection:link(lane)
  if not self.shape.aabb:horizontallyInsersects(lane.aabb) then return end

  ---@param index integer
  ---@param p1 vec3
  ---@param p2 vec3
  ---@param hit vec3
  ---@param offset number
  ---@return number
  ---@return vec3
  local function calculateDistanceAndPos(index, p1, p2, hit, offset)
    local edgeInfo = lane.edgesCubic[index]
    local edgePos = hit:distance(vec2(p1.x, p1.z)) / vec2(p2.x, p2.z):distance(vec2(p1.x, p1.z))
    local totalDistance = edgeInfo.totalDistance + lane.edgesLength[index] * edgePos
    return totalDistance + offset, lane:interpolateDistance(totalDistance + offset), lane:interpolateDistance(totalDistance)
  end

  local entryPrioritiesTable = self._entryPrioritiesTable

  try(function()
    self.shape:collectIntersections(lane.points, lane.loop, function (indexFrom, posFrom, sideFrom, indexTo, posTo, sideTo)
      local offset = self._loadingDef.entryOffsets and table.findFirst(self._loadingDef.entryOffsets, function (item) return item.lane == lane.id end) or nil
      local distanceFrom, posFrom, posOrigFrom = calculateDistanceAndPos(indexFrom, lane.points[indexFrom], lane.points[indexFrom + 1], posFrom, offset and offset.offsets[1] or 0)
      local distanceTo, posTo, posOrigTo = calculateDistanceAndPos(indexTo, lane.points[indexTo], lane.points[indexTo + 1], posTo, offset and offset.offsets[2] or 0)
      local item = IntersectionLink(self, lane, distanceFrom, distanceTo, posFrom, posTo, sideFrom, sideTo, posOrigFrom, posOrigTo)
      lane:addIntersectionLink(item)
      self:_addLink(item)

      local entryMeta = lane.edgesMeta[indexFrom - 2] or lane.edgesMeta[indexFrom - 1] or lane.edgesMeta[indexFrom]
      if entryMeta ~= nil then
        if entryMeta.priority ~= 0 then
          entryPrioritiesTable[lane.id] = (entryPrioritiesTable[lane.id] or 0) + entryMeta.priority
        end
      end
    end)
  end, function (err)
    ac.error(string.format('Failed to collect intersections: %s vs %s', self.name, lane.name))
  end)
end

function TrafficIntersection:finalizeLinks()
  local sides = self._sides
  local incompatibleTable = self._incompatibleTable
  local priorityTable = self._priorityTable

  ---@param entryLane TrafficLane
  ---@param exitLane TrafficLane
  ---@param reason string
  ---@param level number @99 for user-defined incompatibilities, 10 for strict, 1 for weak (can go if either needed or intersection is empty)
  local function markLanesIncompatible(entryLane, exitLane, reason, level)
    if not level then level = 10 end
    local subTable = table.getOrCreate(incompatibleTable, entryLane, function () return {} end)
    local existing = subTable[exitLane] or 0
    if existing < level then
      if self.name == 'I1' then
        ac.log(string.format('incompatible: %s, %s (%s), %f', entryLane, exitLane, reason, level))
      end
      subTable[exitLane] = level
    end
  end

  ---@param entryLane TrafficLane
  ---@param exitLane TrafficLane
  ---@param reason string
  ---@param level number
  local function markLanesPriority(entryLane, exitLane, reason, level)
    if not level then level = 0 end
    local subTable = table.getOrCreate(priorityTable, entryLane, function () return {} end)
    subTable[exitLane] = (subTable[exitLane] or 0) + level
    if self.name == 'I1' then
      ac.log(string.format('priority+=%f: %s, %s (%s)', level, entryLane, exitLane, reason))
    end
  end

  ---@param entry IntersectionLink
  ---@param exit IntersectionLink
  ---@param reason string
  ---@param level number
  local function markIncompatible(entry, exit, reason, level)
    markLanesIncompatible(entry.lane, exit.lane, reason, level)
  end

  ---@param entry IntersectionLink
  ---@param exit IntersectionLink
  ---@param reason string
  ---@param level number
  local function markPriority(entry, exit, reason, level)
    markLanesPriority(entry.lane, exit.lane, reason, level)
  end

  if sides:sum(function (s) return s.exits.length end) == 1 and #self._priorityTable == 0 and #self._entryPrioritiesTable == 0
      and self._linksList[1].fromDir and self._linksList:every(function (s) return s.fromDir and s.fromDir:dot(self._linksList[1].fromDir) > 0.5 end) then
    self.mergingIntersection = true
  end

  sides:removeIf(function (item) return item.entries.length == 0 or item.exits.length == 0 end)
  sides:forEach(IntersectionSide.finalize)

  ---@param id integer
  local function findLaneByID(id)
    local link = self._linksList:findFirst(function (e) return e.lane.id == id end)
    return link and link.lane or error(string.format('Lane with ID=%d is missing', id))
  end

  if self._loadingDef.disallowedTrajectories ~= nil and #self._loadingDef.disallowedTrajectories > 0 then
    for i = 1, #self._loadingDef.disallowedTrajectories do
      local e = self._loadingDef.disallowedTrajectories[i]
      markLanesIncompatible(findLaneByID(e[1]), findLaneByID(e[2]), 'set via config', 99)
    end
  end

  self.trajectoryAttributes = {}
  if self._loadingDef.trajectoryAttributes ~= nil and #self._loadingDef.trajectoryAttributes > 0 then
    for i = 1, #self._loadingDef.trajectoryAttributes do
      local e = self._loadingDef.trajectoryAttributes[i] -- { laneFromID, laneToID, attributes }
      local laneFrom, laneTo = findLaneByID(e[1]), findLaneByID(e[2])
      local l = table.getOrCreate(self.trajectoryAttributes, laneFrom, function () return {} end)
      l[laneTo] = e[3]
      if e[3].po and e[3].po ~= 0 then
        markLanesPriority(laneFrom, laneTo, 'config', e[3].po)
      end
    end
  end

  -- Need to collect straight trajectories, they would have the most priority
  ---@type Array|{[1]: vec3, [2]: vec3}[]
  local straight = Array()
  sides:forEach(function (side)
    ---@param entry IntersectionLink
    side.entries:forEach(function (entry, i)
      if entry.fromPos == nil then return end
      sides:forEach(function (exitSide)
        local exit = exitSide.exits:at(i) or exitSide.exits:at(#exitSide.exits)
        if exit.toPos ~= nil and self:areLanesCompatible(entry.lane, exit.lane) then 
          if exit.toDir:dot(entry.fromDir) > 0.5 then straight:push({ entry.fromOrigPos, exit.toOrigPos }) end
          return
        end

        ---@param exit IntersectionLink
        exitSide.exits:some(function (exit)
          if exit.toPos == nil or not self:areLanesCompatible(entry.lane, exit.lane) then return false end
          if exit.toDir:dot(entry.fromDir) > 0.5 then straight:push({ entry.fromOrigPos, exit.toOrigPos }) end
          return true
        end)
      end)
    end)
  end)

  local lpT, lpA, lpD
  -- if self.name == 'Intersection #3' then
  --   lpA, lpT, lpD = Array(), Array(), Array()
  --   script.draw3D = function ()
  --     for i, l in ipairs(lpT) do
  --       render.debugArrow(l[1], l[2], 1, rgbm(3, 0, 0, 1))
  --     end
  --     for i, l in ipairs(straight) do
  --       render.debugArrow(l[1], l[2], 1, rgbm(0, 3, 0, 1))
  --     end
  --     for i, l in ipairs(lpA) do
  --       render.debugArrow(l[1], l[2], 1, rgbm(0, 0, 3, 1))
  --     end
  --     for i, l in ipairs(lpD) do
  --       render.debugArrow(l[1], l[2], 1, rgbm(0, 0, 0, 1))
  --     end
  --   end
  -- end

  sides:forEach(function (side)
    if #side.entries >= 2 then

      -- Disallow making U-turns across lanes or U-turns which are too tight
      ---@param entry IntersectionLink
      side.entries:forEach(function (entry, i)
        if i > 1 then
          side.exits:forEach(function (exit, j)
            markIncompatible(entry, exit, 'u-turn across another lane')
          end)
        elseif #side.exits > 1 and entry.fromPos:closerToThan(side.exits[1].toPos, 6)
            and self:areLanesCompatible(entry.lane, side.exits[2].lane) then
          markIncompatible(entry, side.exits[1], 'u-turn is too tight')
        end
      end)

      -- Disallow turning right from any but right lane and left from any but left lane
      sides:forEach(function (exitSide)
        if #exitSide.exits < 2 then return end

        -- If it’s a turn…
        if side.entryDir:dot(exitSide.exitDir) < 0.5 then
          -- Find index of an entry which is closest to exit — only that one would be allowed to turn there
          local i = side.entries[1].fromOrigPos:distanceSquared(exitSide.centerExits) < side.entries[#side.entries].fromOrigPos:distanceSquared(exitSide.centerExits) and 1 or #side.entries

          -- But only if that closest entry is allowed to turn there
          if not exitSide.exits:some(function (exit)
            return self:areLanesCompatible(side.entries[i].lane, exit.lane)
          end) then
            return
          end

          side.entries:forEach(function (entry, entryIndex)
            if i == entryIndex then return end
            exitSide.exits:forEach(function (exit)
              markIncompatible(entry, exit, 'no turns across lanes')
            end)
          end)
        end
      end)

      -- Disallow changing lanes during intersection (lower priority, not applied if intersection is empty)
      sides:forEach(function (exitSide)
        if #side.entries == #exitSide.exits and side.entryDir:dot(exitSide.exitDir) > -0.5 then
          side.entries:forEach(function (entry, entryIndex)
            exitSide.exits:forEach(function (exit, exitIndex)
              if entryIndex ~= exitIndex then
                markIncompatible(entry, exit, 'no changing lanes', 1)
              end
            end)
          end)
        end
      end)
    end

    -- Lower priority for turning across an intersection
    -- Then, mark any trajectories that intersect any straight ones as lower priority
    ---@param entry IntersectionLink
    side.entries:forEach(function (entry)
      if entry.fromPos == nil then return end
      sides:forEach(function (exitSide)
        ---@param exit IntersectionLink
        exitSide.exits:forEach(function (exit)
          if exit.toPos == nil then return end

          local d = exit.toDir:dot(entry.fromDir)
          if d > 0.5 then return end
          if d < -0.5 then
            markPriority(entry, exit, 'doing a U-turn', -200)
            return
          end

          if straight:some(function (pair)
            return not rawequal(pair[1], entry.fromOrigPos) and (not rawequal(pair[2], exit.toOrigPos)
                and MathUtils.hasIntersection3D(entry.fromOrigPos, exit.toOrigPos, pair[1], pair[2]))
          end) then
            markPriority(entry, exit, 'goes across a lane', -100)
            if lpT then lpT:push({ entry.fromOrigPos, exit.toOrigPos }) end
          else
            if lpA then lpA:push({ entry.fromOrigPos, exit.toOrigPos }) end
          end
        end)
      end)
    end)

  end)
end

---@param laneFrom TrafficLane
---@param laneTo TrafficLane
---@param reallyNeeded boolean?
function TrafficIntersection:areLanesCompatible(laneFrom, laneTo, reallyNeeded)
  local t = self._incompatibleTable[laneFrom]
  -- if self.name == 'I1' and laneFrom.name == 'Lane #6' and laneTo.name ~= 'Lane #8' then
  --   ac.debug('LT', laneTo)
  --   ac.debug('TTT', t[laneTo])
  -- end
  if not t then return true end

  local l = t[laneTo]
  return not l or l == 1 and (reallyNeeded or #self.engaged == 0)
  -- return not l
end

---@param laneFrom TrafficLane
---@param laneTo TrafficLane
function TrafficIntersection:getPriorityLevel(laneFrom, laneTo)
  local e = self._entryPrioritiesTable[laneFrom.id] or 0
  local t = self._priorityTable[laneFrom]
  if not t then return e end
  return (t[laneTo] or 0) + e
end

function TrafficIntersection:update(cameraPosition, dt)
  if not self.trafficLight then return end
  if self.trafficLight:update(cameraPosition, dt) then
    local phase = self.phase + 1
    self.phase = phase
    if #self.traversing == 0 then
      self.lowestPhase = phase
    end
  end
end

---@param layers TrafficDebugLayers
function TrafficIntersection:draw3D(layers)
  if not layers:near(self.shape.aabb) then return end
  
  layers:with('Names', true, function ()
    render.debugText(self.shape.aabb.center, self.name, rgbm(3, 3, 0, 1), 1.5)
  end)
  layers:with('Traversing', true, function ()
    render.debugText(self.shape.aabb.center, string.format('%d trav.\nphase=%d, low.ph.=%d\n%s', self.traversing.length, self.phase, 
      self.lowestPhase, self.traversing:map(function (x) return x.phase end):join(', ')), rgbm(3, 3, 0, 1), 0.8)
    for i = 1, #self.traversing do
      local t = self.traversing[i]
      render.debugArrow(t.guide.driver:getPosRef() + vec3(0, 5, 0), t.guide.driver:getPosRef(), 1, t.justFloorIt and rgbm.colors.purple or rgbm.colors.lime)
    end
  end)
  layers:with('Inactive engagements', function ()
    for i = 1, #self.engaged do
      if not self.engaged[i].active then
        self.engaged[i]:draw3D(layers)
      end
    end
  end)
  layers:with('Active engagements', function ()
    for i = 1, #self.engaged do
      if self.engaged[i].active then
        self.engaged[i]:draw3D(layers)
      end
    end
  end)
  
  if self.trafficLight then
    layers:with('Traffic lights', function ()
      self.trafficLight:draw3D(layers)
    end)
  end


end

return class.emmy(TrafficIntersection, TrafficIntersection.initialize)
