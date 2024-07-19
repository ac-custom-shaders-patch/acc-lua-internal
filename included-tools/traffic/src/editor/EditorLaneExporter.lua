local CubicInterpolatingLane = require('CubicInterpolatingLane')

local function encoderFactory(typeID)
  local arg = ac.StructItem.combine({value = typeID}, true)
  return function (value)
    arg.value = value
    return ac.structBytes(arg)
  end
end 

local encode = {
  int32 = encoderFactory(ac.StructItem.int32()),
}

---@type {position: vec3, length: number, id: integer}
local tplPointBase = ac.StructItem.combine([[
  vec3 position;
  float length;
  int id;
]], true)

---@type {speed: number, gas: number, brake: number, radius: number, sideLeft: number, sideRight: number, direction: number, normal: vec3, length: number, forward: vec3, tag: number, grade: number}
local tplPointExt = ac.StructItem.combine([[
  float speed;
  float gas;
  float brake; 
  float obsoleteLatG;
  float radius;
  float sideLeft;
  float sideRight;
  float camber;
  float direction;
  vec3 normal;
  float length;
  vec3 forward;
  float tag;
  float grade;
]], true)

local vecDown = vec3(0, -1, 0)
local ai = require('shared/sim/ai')

---@param lane EditorLane
---@param filename string
return function (lane, filename, width, verticalOffset)
  local baseLane = try(function ()
    return CubicInterpolatingLane(lane.points, lane.loop)
  end, function (err)
    ac.error(string.format('Lane is damaged: %s (%s)', lane.name, err))
  end)
  if not baseLane then
    ui.toast(ui.Icons.Warning, 'Failed to resample spline')
    return
  end

  ---@type vec3[], vec3[]
  local resampledPoints, surfaceNormals
  do
    local length = math.ceil(baseLane.totalDistance / 1.51)
    resampledPoints = table.new(lane.loop and length or length + 1, 0)
    surfaceNormals = table.new(lane.loop and length or length + 1, 0)
    do    
      local n, p = vec3(), baseLane.points[1]:clone()
      p.y = p.y + 2
      local offset = physics.raycastTrack(p, vecDown, 4, nil, n)
      p.y = p.y - (offset ~= -1 and offset or 2)
      resampledPoints[1] = p
      surfaceNormals[1] = n
    end
    local loopLength = lane.loop and length - 1 or length
    for i = 1, loopLength do
      local n, p = vec3(), baseLane:interpolate(baseLane:distanceToPointEdgePos(baseLane.totalDistance * i / length))
      p.y = p.y + 2
      local offset = physics.raycastTrack(p, vecDown, 4, nil, n)
      p.y = p.y - (offset ~= -1 and offset or 2)
      resampledPoints[i + 1] = p
      surfaceNormals[i + 1] = n
    end
  end

  local pointsCount = #resampledPoints - 1
  local r = table.new(10 + pointsCount * 2, 0)
  r[#r + 1] = encode.int32(7)
  r[#r + 1] = encode.int32(pointsCount)
  r[#r + 1] = encode.int32(0)
  r[#r + 1] = encode.int32(0)
  local totalLength = 0
  for i = 1, pointsCount do
    tplPointBase.position = resampledPoints[i]
    tplPointBase.position.y = tplPointBase.position.y + verticalOffset
    tplPointBase.length = totalLength
    tplPointBase.id = i - 1
    r[#r + 1] = ac.structBytes(tplPointBase)
    if i < pointsCount then
      totalLength = totalLength + resampledPoints[i]:distance(resampledPoints[i + 1])
    end
  end
  r[#r + 1] = encode.int32(pointsCount)
  tplPointExt.sideLeft = width / 2
  tplPointExt.sideRight = width / 2
  tplPointExt.direction = 1
  for i = 1, pointsCount do
    local cur, next = resampledPoints[i], i == pointsCount and resampledPoints[1] or resampledPoints[i + 1]
    tplPointExt.length = cur:distance(next)
    tplPointExt.normal = surfaceNormals[i]
    tplPointExt.forward:set(next):sub(cur):normalize()
    if i == pointsCount and lane.loop then
      tplPointExt.forward:scale(-1)
    end
    r[#r + 1] = ac.structBytes(tplPointExt)
    tplPointExt.direction = 1
  end
  r[#r + 1] = encode.int32(0) -- without grid
  io.save(filename, table.concat(r))
  ai.spline.loadFast(filename)
  ui.toast(ui.Icons.Confirm, 'Spline exported and loaded in-game')
end
