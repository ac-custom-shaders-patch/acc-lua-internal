---@class CacheTable : ClassBase
---@field data table
local CacheTable = class('CacheTable')

---@return CacheTable
function CacheTable.allocate()
  return { data = {} }
end

---@generic T
---@param key any
---@param callback fun(): T
---@return T
function CacheTable:get(key, callback, ...)
  local d = self.data
  local r = d[key]
  if r == nil then
    r = callback(...)
    d[key] = r
  end
  return r
end

function CacheTable:clear()
  table.clear(self.data)
end

return class.emmy(CacheTable, CacheTable.allocate)