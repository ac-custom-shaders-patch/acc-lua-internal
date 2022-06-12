local MathUtils = {}

function MathUtils.crossY(v, u)
  local a, c = v.x, v.z
  return c * u.x - a * u.z
end

---@param v1 vec2
---@param v2 vec2
---@param v3 vec2
---@param v4 vec2
---@return vec2
function MathUtils.intersect(v1, v2, v3, v4) 
  local denominator = (v4.y - v3.y) * (v2.x - v1.x) - (v4.x - v3.x) * (v2.y - v1.y)
  if denominator == 0 then return nil end

  local ua = ((v4.x - v3.x) * (v1.y - v3.y) - (v4.y - v3.y) * (v1.x - v3.x)) / denominator
  local ub = ((v2.x - v1.x) * (v1.y - v3.y) - (v2.y - v1.y) * (v1.x - v3.x)) / denominator
  if ua < 0 or ua > 1 or ub < 0 or ub > 1 then return nil end
  return v1 + ua * (v2 - v1)
end

---@param v1 vec2
---@param v2 vec2
---@param v3 vec2
---@param v4 vec2
---@return vec2
function MathUtils.hasIntersection2D(v1, v2, v3, v4) 
  local denominator = (v4.y - v3.y) * (v2.x - v1.x) - (v4.x - v3.x) * (v2.y - v1.y)
  if denominator == 0 then return false end

  local ua = ((v4.x - v3.x) * (v1.y - v3.y) - (v4.y - v3.y) * (v1.x - v3.x)) / denominator
  local ub = ((v2.x - v1.x) * (v1.y - v3.y) - (v2.y - v1.y) * (v1.x - v3.x)) / denominator
  return ua >= 0 and ua <= 1 and ub >= 0 and ub <= 1
end

---@param v1 vec3
---@param v2 vec3
---@param v3 vec3
---@param v4 vec3
---@return boolean
function MathUtils.hasIntersection3D(v1, v2, v3, v4) 
  local denominator = (v4.z - v3.z) * (v2.x - v1.x) - (v4.x - v3.x) * (v2.z - v1.z)
  if denominator == 0 then return false end

  local ua = ((v4.x - v3.x) * (v1.z - v3.z) - (v4.z - v3.z) * (v1.x - v3.x)) / denominator
  local ub = ((v2.x - v1.x) * (v1.z - v3.z) - (v2.z - v1.z) * (v1.x - v3.x)) / denominator
  if ua < 0 or ua > 1 or ub < 0 or ub > 1 then return false end
  return true
end

function MathUtils.distanceBetweenCarAndPoint(carPos, carDir, halfLength, halfWidth, point)
  local d = halfWidth - halfLength
  local ax = carPos.x - carDir.x * d
  local ay = carPos.z - carDir.z * d
  local dx = carDir.x * d * 2
  local dy = carDir.z * d * 2
  local px = point.x - ax
  local py = point.z - ay
  local h = math.saturateN((px * dx + py * dy) / (dx^2 + dy^2))
  return math.sqrt((px - dx * h)^2 + (py - dy * h)^2) - halfWidth
end

return MathUtils