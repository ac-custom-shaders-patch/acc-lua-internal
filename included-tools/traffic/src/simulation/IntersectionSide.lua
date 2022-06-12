local Array = require('Array')

---@class IntersectionSide
---@field index integer
---@field p1 vec3
---@field p2 vec3
---@field entries Array|IntersectionLink[]
---@field exits Array|IntersectionLink[]
---@field centerEntries vec3
---@field centerExits vec3
---@field midpoint vec3
---@field entryDir vec3
---@field exitDir vec3
---@field tlState integer
local IntersectionSide = class(function (p1, p2)
  return {
    p1 = p1,
    p2 = p2,
    entries = Array(),
    exits = Array(),
  }
end)

---@param index integer
---@param p1 vec3
---@param p2 vec3
---@return IntersectionSide
function IntersectionSide.allocate(index, p1, p2)
  return {
    index = index,
    p1 = p1,
    p2 = p2,
    entries = Array(),
    exits = Array(),
  }
end

function IntersectionSide:finalize()
  self.entryDir = self.entries:reduce(vec3(), function (c, e) return vec3.add(c, e.fromDir) end):normalize()
  self.exitDir = self.exits:reduce(vec3(), function (c, e) return vec3.add(c, e.toDir) end):normalize()
  self.centerEntries = self.entries:reduce(vec3(), function (c, e) return vec3.add(c, e.fromPos) end):scale(1 / #self.entries)
  self.centerExits = self.exits:reduce(vec3(), function (c, e) return vec3.add(c, e.toPos) end):scale(1 / #self.exits)
  self.entries:sort(function (a, b) return a.fromPos:distanceSquared(self.centerExits) < b.fromPos:distanceSquared(self.centerExits) end)
  self.exits:sort(function (a, b) return a.toPos:distanceSquared(self.centerEntries) < b.toPos:distanceSquared(self.centerEntries) end)
  self.midpoint = (self.entries[1].fromPos + self.exits[1].toPos) / 2
  self.entries:forEach(function (item) item.enterSide = self end)
end

return class.emmy(IntersectionSide, IntersectionSide.allocate)