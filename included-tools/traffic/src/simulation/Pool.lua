local Array = require('Array')

local delayedSet = false

---@type any[]
local delayedItems = Array()

local function _processDelayed()
  local d = delayedItems.length
  if d > 0 then
    for i = 1, d do
      local e = delayedItems[i]
      e.target.items:push(e.item)
    end
    delayedItems:clear()
  end
end

---@class Pool
---@field items any[]
---@field releaseDelay number
---@field factory function|nil
local Pool = class('Pool')

---@param factory fun(): any
---@param releaseDelay number
---@return Pool
function Pool.allocate(factory, releaseDelay)
  if releaseDelay and not delayedSet then
    delayedSet = true
    setInterval(_processDelayed, 0.5)
  end
  return {
    items = Array(),
    factory = factory,
    releaseDelay = releaseDelay == true
  }
end

function Pool:get(factory, prepareExisting)
  local ret = self.items:pop()
  if ret ~= nil then
    if prepareExisting ~= nil then prepareExisting(ret) end
    return ret
  end
  return factory ~= nil and factory() or (self.factory ~= nil and self:factory() or {})
end

function Pool:release(item)
  if self.releaseDelay then
    delayedItems:push({ item = item, target = self })
  else
    self.items:push(item)
  end
end

function Pool:dispose(itemCallback)
  self.items:clear(itemCallback)
end

return class.emmy(Pool, Pool.allocate)