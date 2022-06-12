---@class BezierCurve
---@field p0 vec3
---@field p1 vec3
---@field p2 vec3
---@field p3 vec3
local BezierCurve = class('BezierCurve')

---@param posFrom vec3
---@param dirFrom vec3
---@param posTo vec3
---@param dirTo vec3
---@param lenFrom number
---@param lenTo number
---@return BezierCurve
function BezierCurve.allocate(posFrom, dirFrom, posTo, dirTo, lenFrom, lenTo)
  local distance = posFrom:distance(posTo)
  return {
    p0 = posFrom,
    p1 = posFrom + dirFrom * (distance * (lenFrom or 0.5)),
    p2 = posTo - dirTo * (distance * (lenTo or 0.5)),
    p3 = posTo
  }
end

---@param posFrom vec3
---@param dirFrom vec3
---@param posTo vec3
---@param dirTo vec3
---@param lenFrom number
---@param lenTo number
function BezierCurve:set(posFrom, dirFrom, posTo, dirTo, lenFrom, lenTo)
  local distance = posFrom:distance(posTo)
  self.p0:set(posFrom)
  self.p1:set(posFrom):addScaled(dirFrom, distance * (lenFrom or 0.5))
  self.p2:set(posTo):addScaled(dirTo, -distance * (lenTo or 0.5))
  self.p3:set(posTo)
end

function BezierCurve:get(t)
  local r = vec3()
  self:getInto(r, t)
  return r
end

-- local _msmoothstep = math.smoothstep

function BezierCurve:getInto(v, t)
  local cX = 3 * (self.p1.x - self.p0.x)
  local bX = 3 * (self.p2.x - self.p1.x) - cX
  local aX = self.p3.x - self.p0.x - cX - bX

  local cY = 3 * (self.p1.y - self.p0.y)
  local bY = 3 * (self.p2.y - self.p1.y) - cY
  local aY = self.p3.y - self.p0.y - cY - bY

  local cZ = 3 * (self.p1.z - self.p0.z)
  local bZ = 3 * (self.p2.z - self.p1.z) - cZ
  local aZ = self.p3.z - self.p0.z - cZ - bZ

  v.x = (aX * t ^ 3) + (bX * t ^ 2) + (cX * t) + self.p0.x
  v.y = (aY * t ^ 3) + (bY * t ^ 2) + (cY * t) + self.p0.y
  v.z = (aZ * t ^ 3) + (bZ * t ^ 2) + (cZ * t) + self.p0.z
end

function BezierCurve:length()
  local r = 0
  local v = nil
  for i = 0, 20 do
    local c = self:get(i / 20)
    if i > 0 then r = r + c:distance(v) end
    v = c
  end
  return r
end

return class.emmy(BezierCurve, BezierCurve.allocate)