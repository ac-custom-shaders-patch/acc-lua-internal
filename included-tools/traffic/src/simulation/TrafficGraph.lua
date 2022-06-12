local Array = require "Array"
local PackedArgs = require "PackedArgs"

package.add('lib')
local Graph = require('luagraphs.data.graph')
local Dijkstra = require('luagraphs.shortest_paths.Dijkstra')

---@class GraphEdge
---@field lane TrafficLane
---@field fromID integer
---@field toID integer
---@field fromIntersection TrafficIntersection
---@field toIntersection TrafficIntersection
---@field from number
---@field to number
---@field dir vec3
local GraphEdge = class('GraphEdge')
function GraphEdge.allocate(data) return data end

---@class TrafficGraph
---@field intersections TrafficIntersection[]
---@field _gEdges GraphEdge[]
---@field _gVertices vec3[]
---@field _gEnterIDs integer[]
---@field _gExitIDs integer[]
local TrafficGraph = class('TrafficGraph')

---@param lanes TrafficLane[]
---@param intersections TrafficIntersection[]
function TrafficGraph:initialize(lanes, intersections)
  self.intersections = intersections
  self._gVertices = Array()
  self._gEnterIDs = Array()
  self._gExitIDs = Array()
  self._gEdges = Array()

  for i = 1, #intersections do
    local inter = intersections[i]
    inter._index = i
    for j = 1, #lanes do
      inter:link(lanes[j])
    end
    inter:finalizeLinks()
    self._gVertices:push(inter.shape.aabb.center)
  end

  for j = 1, #lanes do
    ---@type TrafficLane
    local lane = lanes[j]

    local linked = lane.linkedIntersections
    local N = #linked
    linked:sort(function(a, b) return a.from < b.from end)

    if N == 0 then

      if not lane.loop then
        self._gEdges:push(GraphEdge{
          fromID = #self._gVertices + 1,
          toID = #self._gVertices + 2,
          lane = lane,
          from = nil,
          to = nil
        })
        self._gEnterIDs:push(#self._gVertices + 1)
        self._gExitIDs:push(#self._gVertices + 2)
        self._gVertices:push(lane.points[1])
        self._gVertices:push(lane.points[lane.size])
      else
        self._gEdges:push({ 
          fromID = 0,
          toID = 0,
          lane = lane,
          from = nil,
          to = nil
        })
      end

    elseif lane.loop then

      if N == 1 then

        self._gEdges:push(GraphEdge{ 
          fromID = linked[1].intersection._index,
          toID = linked[N].intersection._index,
          -- fromIntersection = linked[1].intersection,
          -- toIntersection = linked[N].intersection,
          lane = lane,
          from = linked[1],
          to = linked[N],
        })

      else

        self._gEdges:push(GraphEdge{ 
          fromID = linked[N].intersection._index,
          toID = linked[1].intersection._index,
          -- fromIntersection = linked[N].intersection,
          -- toIntersection = linked[1].intersection,
          lane = lane,
          from = linked[N],
          to = linked[1],
        })

        for i = 1, N - 1 do
          self._gEdges:push(GraphEdge{ 
            fromID = linked[i].intersection._index,
            toID = linked[i + 1].intersection._index,
            -- fromIntersection = linked[i].intersection,
            -- toIntersection = linked[i + 1].intersection,
            lane = lane,
            from = linked[i],
            to = linked[i + 1],
          })
        end

      end

    else

      if not lane:startsWithIntersection() then
        self._gEdges:push(GraphEdge{ 
          fromID = #self._gVertices + 1, 
          toID = linked[1].intersection._index,
          -- toIntersection = linked[1].intersection,
          lane = lane,
          from = nil,
          to = linked[1],
        })
        self._gEnterIDs:push(#self._gVertices + 1)
        self._gVertices:push(lane.points[1])
      end

      for i = 1, N - 1 do
        self._gEdges:push(GraphEdge{ 
          fromID = linked[i].intersection._index, 
          toID = linked[i + 1].intersection._index,
          -- fromIntersection = linked[i].intersection, 
          -- toIntersection = linked[i + 1].intersection,
          lane = lane,
          from = linked[i],
          to = linked[i + 1],
        })
      end

      if not lane:endsWithIntersection() then
        self._gEdges:push(GraphEdge{ 
          fromID = linked[N].intersection._index,
          toID = #self._gVertices + 1,
          -- fromIntersection = linked[N].intersection,
          lane = lane,
          from = linked[N],
          to = nil
        })
        self._gExitIDs:push(#self._gVertices + 1)
        self._gVertices:push(lane.points[lane.size])
      end

    end
    
    lane:finalize()
  end

  self._graph = Graph.create(#self._gVertices, true)
  self._edgesFromIDMap = {}
  for i = 1, #self._gEdges do
    local edge = self._gEdges[i]
    local fromPos = self:getGPos(edge.fromID)
    local toPos = self:getGPos(edge.toID)
    edge.dir = toPos:clone():sub(fromPos):normalize()

    table.getOrCreate(self._edgesFromIDMap, edge.fromID, Array):push(edge)
    if edge.fromID ~= 0 and edge.toID ~= 0 then
      self._graph:addEdge(edge.fromID, edge.toID, fromPos:distance(toPos))
    end
  end
end

function TrafficGraph:getGPos(id)
  return self._gVertices[id]
end

function TrafficGraph:getGEdge(fromID, toID)
  for i = 1, #self._gEdges do
    local edge = self._gEdges[i]
    if edge.fromID == fromID and edge.toID == toID then return edge end
  end 
  return nil
end

function TrafficGraph:findGEdge(lane, distance)
  local N = #self._gEdges
  for i = 1, N do
    local edge = self._gEdges[i]
    if edge.lane == lane and (edge.from and edge.from.to or 0) < distance and (edge.to and edge.to.from or lane.totalDistance) > distance then return edge end
  end 
  return nil
end

local _packed = PackedArgs()

---@param edge GraphEdge
local function findRandomEdgeFromCallback(edge, i, data)
  ---@type TrafficLane
  local currentLane = data[1]
  ---@type TrafficIntersection
  local intersection = data[2]
  ---@type vec3|nil
  local currentDirHint = data[3]
  -- ---@type TrafficGraph
  -- local graph = data[4]
  if intersection:areLanesCompatible(currentLane, edge.lane) then
    -- if currentDirHint ~= nil and edge.dir:dot(currentDirHint) < 0 then
    --   ac.debug('currentDirHint', currentDirHint)
    --   ac.debug('edge.dir', edge.dir)
    --   DebugShapes.FROM = graph:getGPos(edge.fromID)
    --   DebugShapes.TO = graph:getGPos(edge.toID)
    --   DebugShapes.TO_DIR = graph:getGPos(edge.fromID) + currentDirHint
    -- end
    -- return 1
    -- return (currentDirHint == nil or edge.dir:dot(currentDirHint) > 0) and 1 or 0
    return currentDirHint == nil and 1 or edge.dir:dot(currentDirHint) + 1.1
  else
    return 0
  end
end

---@param fromID integer
---@param currentLane TrafficLane
---@param currentDirHint vec3|nil
---@return GraphEdge|nil
function TrafficGraph:findRandomEdgeFrom(fromID, currentLane, currentDirHint)
  local intersection = self.intersections[fromID]
  if intersection == nil then return nil end
  local edges = self._edgesFromIDMap[fromID]
  if edges == nil then return nil end
  return edges:random(findRandomEdgeFromCallback, _packed:pack3(currentLane, intersection, currentDirHint)) --or ac.log(string.format('Failed to find edge: %s, from ID=%d', currentLane, fromID))
end

local function findEdgeByLaneCallback(edge, i, data)
  local lane, lanePos = data[1], data[2]
  if edge.lane ~= lane then return 1/0 end
  local from = edge.from and edge.from.to or 0
  if from > lanePos + 0.1 then return 1/0 end
  return lanePos - from
end

function TrafficGraph:findEdgeByLane(lane, lanePos)
  return self._gEdges:minEntry(findEdgeByLaneCallback, _packed:pack2(lane, lanePos))
end

function TrafficGraph:makePath(enterID, exitID)
  local dijkstra = Dijkstra.create()
  dijkstra:run(self._graph, enterID)
  if not dijkstra:hasPathTo(exitID) then
    return nil
  end

  local gPath = dijkstra:getPathTo(exitID)
  local path = { gPath:get(0):from() }
  for i = 0, gPath:size() - 1 do
    table.insert(path, gPath:get(i):to())
  end
  return path
end

function TrafficGraph:makeRandomPath()
  local enterID = table.random(self._gEnterIDs)
  local exitID = table.random(self._gExitIDs)
  if enterID == nil or exitID == nil then return nil end
  return self:makePath(enterID, exitID)
end

function TrafficGraph:draw3D(layers)
  layers:with('Vertices', true, function ()
    for i = 1, #self._gVertices do
      render.debugCross(self._gVertices[i], 2, rgbm(0, 0, 3, 1))
      render.debugText(self._gVertices[i], i,
        self._gEnterIDs:contains(i) and rgbm(0, 3, 0, 1) 
          or self._gExitIDs:contains(i) and rgbm(3, 0, 0, 1) or rgbm(3, 3, 0, 1), 2)
    end
  end)

  layers:with('Edges', function ()
    for i = 1, #self._gEdges do
      render.debugArrow(self:getGPos(self._gEdges[i].fromID), self:getGPos(self._gEdges[i].toID))
    end
  end)
end

return TrafficGraph