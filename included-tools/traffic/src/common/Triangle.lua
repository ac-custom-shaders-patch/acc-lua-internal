---@class Triangle
---@field a vec2
---@field b vec2
---@field c vec2
local Triangle = class('Triangle', function (a, b, c)
  return { a = a, b = b, c = c }
end, class.NoInitialize)

function Triangle.contains(self, p3)
  local p0 = self.a
  local p1 = self.b
  local p2 = self.c
  local dX = p3.x - p2.x
  local dY = p3.z - p2.y
  local dX21 = p2.x - p1.x
  local dY12 = p1.y - p2.y
  local D = dY12 * (p0.x - p2.x) + dX21 * (p0.y - p2.y)
  local s = dY12 * dX + dX21 * dY
  local t = (p2.y - p0.y) * dX + (p0.x - p2.x) * dY
  if D < 0 then return s <= 0 and t <= 0 and s + t >= D end
  return s >= 0 and t >= 0 and s + t <= D;
end

return Triangle