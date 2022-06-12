local function getTangent(points, distances, point, previousPoint, followingPoint, genericFactory)
  local ret = genericFactory.empty()
  if point == 1 and not previousPoint or point == #points and not followingPoint then return ret end

  local mult = 1 / math.max(0.00001, distances[point + 1] - (distances[point - 1] or 0))
  genericFactory.add(ret, points[point + 1] or followingPoint, mult)
  genericFactory.add(ret, points[point - 1] or previousPoint, -mult)
  return ret
end

local vec3GenericFactory = {
  empty = vec3,
  distance = vec3.distance,
  add = vec3.addScaled,
  step = 5
}

---@generic T
---@param points T[]
---@param previousPoint T?
---@param followingPoint T?
---@param genericFactory nil|{empty: fun(), distance: fun(a: T, b: T), add: fun(a: T, b: T, mult: number), step: number}
---@return T[]
local function LineResampler(points, previousPoint, followingPoint, genericFactory)
  if not genericFactory then
    if vec3.isvec3(points[1]) then genericFactory = vec3GenericFactory end
    if genericFactory == nil then
      error('Generic factory is required for unknown type', 2)
      return nil
    end
  end

  local distance = previousPoint and -math.abs(genericFactory.distance(previousPoint, points[1])) or 0
  local totalDistances = {distance}
  for i = 2, #points do
    distance = distance + math.abs(genericFactory.distance(points[i - 1], points[i]))
    table.insert(totalDistances, distance)
  end
  if followingPoint then
    table.insert(totalDistances, distance + math.abs(genericFactory.distance(followingPoint, points[#points])))
    -- table.insert(totalDistances, distance + math.abs(genericFactory.distance(followingPoint, points[#points])) * 2)
  end

  local ret = { points[1] }
  local steps = math.ceil(distance / genericFactory.step)
  for i = 1, steps - 1 do
    local p = distance * i / steps

    local point = table.findLeftOfIndex(totalDistances, function (item, _, p_) return item > p_ end, p)
    local cur = points[point]
    local edgeLength = totalDistances[point + 1] - totalDistances[point]
    local edgePos = math.lerpInvSat(p, totalDistances[point], totalDistances[point + 1])

    local fol = point == #points and cur or points[point + 1]
    local tangentCur = getTangent(points, totalDistances, point, previousPoint, followingPoint, genericFactory)
    local tangentFol = getTangent(points, totalDistances, point + 1, previousPoint, followingPoint, genericFactory)
    local t1 = edgePos
    local t2 = t1 * t1
    local t3 = t1 * t2

    local v = genericFactory.empty()
    genericFactory.add(v, cur, 2 * t3 - 3 * t2 + 1)
    genericFactory.add(v, tangentCur, (t3 - 2 * t2 + t1) * edgeLength)
    genericFactory.add(v, fol, -2 * t3 + 3 * t2)
    genericFactory.add(v, tangentFol, (t3 - t2) * edgeLength)
    table.insert(ret, v)
  end
  table.insert(ret, points[#points])
  return ret
end

return LineResampler
