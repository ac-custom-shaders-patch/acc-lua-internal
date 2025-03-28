--[[
  Helper for cubic interpolation.
]]

local cubic = {}

local function getTangent(points, distances, loop, point, size)
  if not loop and (point == 1 or point >= size) then
    if point >= size then
      return (points[size] - points[size - 1]) / distances[size]
    end
    return (points[2] - points[1]) / distances[1]
  end
  return (points[point % size + 1] - points[point == 1 and size or point - 1])
      / math.max(0.00001, distances[point > size and 1 or point] + distances[point == 1 and size or point - 1])
end

---Uses distance between vectors as interpolation input.
---@generic T: vec2|vec3|vec4
---@param points T[]
---@param loop boolean? @Default value: false.
---@return {get: fun(progress: number), getTo: fun(out: T, progress: number), length: fun(): number}
function cubic.vec(points, loop)
  loop = not not loop
  local count = #points
  local edgesLength = {}
  local totalDistance = 0
  local attributes = {}
  for i = 1, count do
    edgesLength[i] = (i == count and not loop)
      and points[i - 1]:distance(points[i])
      or points[i % count + 1]:distance(points[i])
  end
  for i = 1, count do
    local len = edgesLength[i]
    attributes[i] = {
      totalDistance = totalDistance,
      edgeLength = len,
      tangentCur = getTangent(points, edgesLength, loop, i, count),
      tangentFol = getTangent(points, edgesLength, loop, i + 1, count),
    }
    if i < count or loop then
      totalDistance = totalDistance + len
    end
  end
  local function compute(out, normalizedProgress)
    local distance = normalizedProgress * totalDistance
    local i1 = math.max(1, table.findLeftOfIndex(attributes, function(i)
      return distance < i.totalDistance
    end))
    local i2 = math.min(i1 + 1, #attributes)
    if i1 == i2 then return points[i1] end
    local edgePos = math.lerpInvSat(distance, attributes[i1].totalDistance, attributes[i2].totalDistance)
    if count < 4 then
      return math.lerp(points[i1], points[i2], edgePos)
    end
    local di = attributes[i1]
    local t1 = edgePos
    local t2 = t1 * t1
    local t3 = t1 * t2
    out:set(points[i1]):scale(2 * t3 - 3 * t2 + 1)
    out:addScaled(di.tangentCur, (t3 - 2 * t2 + t1) * di.edgeLength)
    out:addScaled(points[i2], -2 * t3 + 3 * t2)
    return out:addScaled(di.tangentFol, (t3 - t2) * di.edgeLength)
  end
  local outType = vec3
  if vec2.isvec2(points[1]) then
    outType = vec2
  elseif vec4.isvec4(points[1]) then
    outType = vec4
  end
  return {
    length = function()
      return totalDistance
    end,
    getTo = compute,
    get = function(normalizedProgress)
      local r = outType()
      compute(r, normalizedProgress)
      return r
    end
  }
end

return cubic
