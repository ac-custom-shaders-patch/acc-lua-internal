---@class TrafficPath
---@field grid TrafficGrid
---@field nextLane TrafficLane
---@field nextLanePos number
---@field currentLane TrafficLane
local TrafficPath = class('TrafficPath', function (grid, pathOrVertexID, nextLane, nextLanePos)
  return {
    grid = grid,
    path = pathOrVertexID,
    index = 1,
    nextLane = nextLane,
    nextLanePos = nextLanePos,
    currentLane = nil
  }
end, class.NoInitialize)

function TrafficPath.getEdge(grid, from, to)
  local nextEdge = grid.graph:getGEdge(from, to)
  local nextLane = nextEdge and nextEdge.lane or error('Damaged state, unforseen intersection')
  return nextLane, nextEdge.from ~= nil and nextEdge.from.to or 0
end

function TrafficPath.tryCreateFrom(grid, pathPoints)
  local lane, lanePos = TrafficPath.getEdge(grid, pathPoints[1], pathPoints[2])
  if not lane:canSpawnAtBeginning() then return nil end
  return TrafficPath(grid, pathPoints, lane, lanePos)
end

function TrafficPath.tryCreateRandom(grid)
  local pathPoints = grid.graph:makeRandomPath()
  return pathPoints ~= nil and TrafficPath.tryCreateFrom(grid, pathPoints) or nil
end

function TrafficPath.tryCreateSpecific(grid, fromID, toID)
  local pathPoints = grid.graph:makePath(fromID, toID)
  return pathPoints ~= nil and TrafficPath.tryCreateFrom(grid, pathPoints) or nil
end

function TrafficPath.createFromPoints(grid, pathPoints)
  return TrafficPath.tryCreateFrom(grid, pathPoints) or nil
end

function TrafficPath:canChange()
  return type(self.path) == 'number'
end

function TrafficPath:changeNextTo(newLane, newLanePos)
  if self.nextLane ~= nil then error('Can’t change predetermined path point') end
  if type(self.path) ~= 'number' then error('Can’t change fixed path') end

  local nextLane = self.grid.graph:findEdgeByLane(newLane, newLanePos) 
    or error(string.format('Can’t change to lane %s at %.1f', newLane, newLanePos))
  self.path = nextLane.toID
end

function TrafficPath:changeCurrentTo(newLane, newLanePos)
  if self.nextLane ~= nil then error('Can’t change predetermined path point') end
  if type(self.path) ~= 'number' then error('Can’t change fixed path') end

  local edge = self.grid.graph:findEdgeByLane(newLane, newLanePos) 
    or error(string.format('Can’t change to lane %s at %.1f', newLane, newLanePos))
  self.path = edge.toID
  self.currentLane = newLane
end

---@param grid TrafficGrid
function TrafficPath.tryCreateWandering(grid)
  local lane = grid.lanes:random(function (lane) return lane.totalDistance end)
  local distance = lane:randomDropSpot()
  if distance ~= nil then
    local edge = grid.graph:findGEdge(lane, distance)
    if edge ~= nil then
      return TrafficPath(grid, edge.toID, lane, distance)
    end
  end
  return nil
end

---@param currentDirHint vec3|nil
function TrafficPath:next(currentDirHint)
  if self.nextLane ~= nil then
    local retLane = self.nextLane
    self.nextLane = nil
    self.currentLane = retLane
    return retLane, self.nextLanePos
  end

  local nextEdge
  if type(self.path) == 'number' then
    nextEdge = self.grid.graph:findRandomEdgeFrom(self.path, self.currentLane, currentDirHint)
    if nextEdge == nil then return nil end
    self.path = nextEdge.toID
  else
    self.index = self.index + 1
    if self.index >= #self.path then return nil end
    nextEdge = self.grid.graph:getGEdge(self.path[self.index], self.path[self.index + 1])
  end

  local nextLane = nextEdge and nextEdge.lane or error('Damaged state, unforseen intersection')
  self.currentLane = nextLane
  return nextLane, nextEdge.from ~= nil and nextEdge.from.to or nil
end

return TrafficPath
