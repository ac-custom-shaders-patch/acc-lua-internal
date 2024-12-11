--[[
  Library with some features to adjust ghost behavior.

  To use, include with `local ai = require('shared/sim/ghost')`.
]]
---@diagnostic disable

local ghost = {}

---Replaces currently loaded ghost with a new one. Can be used by scripts with gameplay API access only.
---@param filename string @Path to a ghost recording.
---@return boolean @Returns `false` if operation has failed.
function ghost.reload(filename)
  return __util.native('ghost.reload', filename)
end

---Forces a certain lap time for loaded ghost.
---@param timeMs number? @Time in milliseconds (pass `nil` to disable forcing).
function ghost.forceTime(timeMs)
  __util.native('ghost.forceTimeMs', tonumber(timeMs) or -1)
end

---Returns ghost time in milliseconds, or `nil` if there is no ghost.
---@return number?
function ghost.getTime()
  return __util.native('ghost.getTimeMs')
end

local transform = mat4x4()

---Returns ghost opacity and transform matrix.
---@return number @Opacity from 0 to 1, 0 for hidden ghost.
---@return mat4x4 @Current ghost transformation matrix (might be invalid if opacity is 0, as updates could be paused).
function ghost.getStateAndTransform()
  return __util.native('ghost.getStateAndTransform', transform) or 0, transform
end

---Creates a new ghost recording from positions. Callback will be called for individual time points, time is in seconds. Return car position or 
---`nil` if there is no more data. It’s expected that `carID` would match ID of main user car or at least one of cars present on a track: with that,
---the function would be able to measure relative wheel positions.
---@param driverName string
---@param track string
---@param layout string
---@param carID string
---@param callback fun(timeS: number): vec3?
---@return binary @Returns binary data that you can save as a file on your side if needed.
function ghost.create(driverName, track, layout, carID, callback)
  local car = ac.getCar(0) 
  for i = 0, ac.getSim().carsCount - 1 do
    if ac.getCarID(i) == carID then
      car = ac.getCar(0)
      break
    end
  end
  local w = require('shared/utils/binary').writeData():uint32(4):uint32(1):string(driverName):string(track):string(layout):string(carID)
  local sizeOffset, frame = w:size(), 0
  w:uint32(0):uint32(0)
  local lastPos = (callback(0) or error('At least a single point is required')):clone()
  local worldToPhysics = car.transform:inverse()
  local localWheelPosLF = (worldToPhysics:transformPoint(car.wheels[0].position) + worldToPhysics:transformPoint(car.wheels[1].position) * vec3(-1, 1, 1)) / 2
  local localWheelPosLR = (worldToPhysics:transformPoint(car.wheels[2].position) + worldToPhysics:transformPoint(car.wheels[3].position) * vec3(-1, 1, 1)) / 2
  local localWheelPositions = {localWheelPosLF, localWheelPosLF * vec3(-1, 1, 1), localWheelPosLR, localWheelPosLR * vec3(-1, 1, 1)}
  local hitPositions = {vec3(), vec3(), vec3(), vec3()}
  local totalDistance = 0
  while true do
    local timeS = 0.129 * frame + 0.001
    local pos = callback(timeS)
    if not pos then
      break
    end
    totalDistance = totalDistance + pos:distance(lastPos)
    local carTransform = mat4x4.translation(pos)
    carTransform.look:set(pos):sub(lastPos):normalize()
    carTransform.side:setCrossNormalized(carTransform.look, vec3(0, 1, 0))
    carTransform.up:setCrossNormalized(carTransform.side, carTransform.look)
    local avgOffset, avgCount = 0, 0
    for i = 1, 4 do
      local hit = physics.raycastTrack(carTransform:transformPoint(localWheelPositions[i]) + vec3(0, 2, 0), vec3(0, -1, 0), 4, hitPositions[i])
      if hit ~= -1 then
        avgOffset, avgCount = avgOffset + hit - 2 - car.wheels[i - 1].tyreRadius, avgCount + 1
      end
    end
    avgOffset = avgOffset / avgCount
    carTransform.up:setCrossNormalized(carTransform.look, hitPositions[2] - hitPositions[1])
    carTransform.side:setCrossNormalized(carTransform.look, carTransform.up)
    carTransform.position.y = carTransform.position.y - avgOffset
    lastPos:set(pos)
    w:mat4x4(carTransform)
    for i = 1, 4 do
      w:mat4x4(mat4x4.translation(localWheelPositions[i]) * carTransform)
    end
    for i = 1, 4 do
      w:mat4x4(mat4x4.translation(localWheelPositions[i]) * carTransform)
    end
    frame = frame + 1
    if frame > 1e5 then
      error('Callback should return `nil` eventually (went for %0.1f hours)' % (timeS / 3600))
    end
  end
  return w:seek(sizeOffset):uint32(129 * frame):uint32(frame):stringify()
end

return ghost