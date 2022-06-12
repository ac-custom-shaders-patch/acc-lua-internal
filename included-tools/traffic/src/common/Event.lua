local _tclear = require('table.clear')

---@class Event : ClassBase
---@field listeners function[]
---@field count integer
local Event = class('Event', class.NoInitialize)

---@return Event
function Event.allocate()
  return { listeners = {}, count = 0 }
end

function Event:clear()
  if self.count > 0 then
    _tclear(self.listeners)
    self.count = 0
  end
end

function Event:subscribe(listener)
  local n = self.count + 1
  self.count = n
  self.listeners[n] = listener
end

function Event:unsubscribe(listener)
  if table.removeItem(self.listeners, listener) then
    self.count = self.count - 1
  end
end

function Event:__call(...)
  for i = 1, self.count do
    self.listeners[i](...)
  end
end

function Event:raise(...)
  for i = 1, self.count do
    self.listeners[i](...)
  end
end

---@return boolean
function Event:any(...)
  for i = 1, self.count do
    if self.listeners[i](...) then
      return true
    end
  end
  return false
end

return class.emmy(Event, Event.allocate)