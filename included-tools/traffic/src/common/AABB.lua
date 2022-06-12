---@class AABB : ClassBase
---@field min vec3
---@field max vec3
---@field center vec3
---@field radius number
local AABB = class('AABB')

---@return AABB
function AABB.allocate(min, max)
  return {
    min = min or vec3.new(1/0),
    max = max or vec3.new(-1/0),
    center = vec3(),
    radius = 0
  }
end

---@return AABB
function AABB.fromArray(array, callback)
  ---@type AABB
  local r = AABB()
  for i = 1, #array do
    r:extend(callback and callback(array[i]) or array[i])
  end
  return r:finalize()
end

function AABB:initialize(min, max)
  if min and max then
    self:finalize()
  end
end

function AABB:reset()
  self.min:set(1/0, 1/0, 1/0)
  self.max:set(-1/0, -1/0, -1/0)
end

---@param p vec3|AABB
function AABB:extend(p)
  if AABB.isInstanceOf(p) then
    self.min:min(p.min)
    self.max:max(p.max)
  else
    self.min:min(p)
    self.max:max(p)
  end
end

function AABB:finalize()
  self.center:set(self.min):add(self.max):scale(0.5)
  self.radius = self.max:distance(self.center)
  return self
end

---@param p vec3
---@param distance number
function AABB:closerToThan(p, distance)
  return self.center:closerToThan(p, distance + self.radius)
end

---@param aabb AABB
function AABB:horizontallyInsersects(aabb)
  return self.max.x > aabb.min.x and self.min.x < aabb.max.x
   and self.max.z > aabb.min.z and self.min.z < aabb.max.z
end

---@param p vec3
function AABB:contains(p)
  return p.x > self.min.x and p.x < self.max.x
    and p.y > self.min.y and p.y < self.max.y
    and p.z > self.min.z and p.z < self.max.z
end

---@param p vec3
function AABB:horizontallyContains(p)
  return p.x > self.min.x and p.x < self.max.x
    and p.z > self.min.z and p.z < self.max.z
end

return class.emmy(AABB, AABB.allocate)
