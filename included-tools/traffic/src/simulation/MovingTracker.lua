---@class MovingTrackerItem
---@field _tracker ac.HashSpaceItem
---@field _items CarBase[]
local MovingTrackerItem = class('MovingTrackerItem')

---@param tracker MovingTracker
---@param items table<integer, CarBase>
---@return MovingTrackerItem
function MovingTrackerItem:initialize(tracker, items)
  self._tracker = tracker
  self._items = items
end

function MovingTrackerItem:update(pos)
  self._tracker:update(pos)
end

function MovingTrackerItem:dispose()
  self._items[self._tracker:id()] = nil
  self._tracker:dispose()
end

---@class MovingTracker
---@field _space ac.HashSpace
---@field _items table<integer, CarBase>
local MovingTracker = class('MovingTracker', class.NoInitialize)

---@param cellSize number
---@return MovingTracker
function MovingTracker.allocate(cellSize)
  return { _space = ac.HashSpace(cellSize or 15), _items = {} }
end

function MovingTracker:track(tag)
  local tracker = self._space:add()
  self._items[tracker:id()] = tag
  return MovingTrackerItem(tracker, self._items)
end

function MovingTracker:iterate(pos, callback, callbackData)
  local from, to = self._space:rawPointers(pos)
  while from ~= to do
    callback(self._items[from[0]], callbackData)
    from = from + 1
  end
  return false
end

function MovingTracker:findNearest(pos, distanceCallback, distanceCallbackData)
  local from, to = self._space:rawPointers(pos)
  local retDistance, retItem = 1/0, nil
  local items = self._items
  while from ~= to do
    local item = items[from[0]]
    local distance = distanceCallback(item, distanceCallbackData)
    if distance < retDistance then
      retDistance, retItem = distance, item
    end
    from = from + 1
  end
  return retDistance, retItem
end

function MovingTracker:anyAround(pos)
  return self._space:anyAround(pos)
end

function MovingTracker:count(pos)
  return self._space:count(pos)
end

function MovingTracker:anyCloserThan(pos, len)
  local from, to = self._space:rawPointers(pos)
  while from ~= to do
    local j = self._items[from[0]]
    if j:distanceBetweenCarAndPoint(pos) < len then return true end
    from = from + 1
  end
  return false
end

return class.emmy(MovingTracker, MovingTracker.allocate)