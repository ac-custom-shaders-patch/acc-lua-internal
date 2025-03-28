if not AIRace or not ConfigNewBehaviour then
  return
end

if Sim.customAISplinesAllowed then
  local aiFolder = '%s/ai' % ac.getFolder(ac.FolderID.CurrentTrackLayout)
  local altSplines = io.scanDir(aiFolder, 'ext_alt_fast_lane_*.ai')
  if #altSplines > 0 then
    math.randomseed(math.randomKey())
    for i = 0, Sim.carsCount - 1 do
      local s = math.random(#altSplines + 1)
      if s <= #altSplines then
        physics.setAISpline(i, '%s/%s' % {aiFolder, altSplines[s]})
        ac.log('AI #%s' % i, '%s/%s' % {aiFolder, altSplines[s]})
      end
    end
  end
end

local fixRedlining = ConfigNewBehaviour:get('AI_TWEAKS', 'START_REDUCE_REDLINING', false)
local fixTrajectory = ConfigNewBehaviour:get('AI_TWEAKS', 'START_STRAIGHTEN_TRAJECTORY', false)
if not fixRedlining and not fixTrajectory then
  return
end

local carOffsets = {}
local carOffsetsApplied = 0
local throttleLimited = false 

local function randomNoise(seed)
  local time = os.preciseClock() + seed * 0.1
  return math.sin(time * 1.71) * 0.6 + math.sin(time * 3.17 + seed) * 0.3 + math.sin(time * 11.71 + seed) * 0.1
end

local function carSplineOffset(i)
  local t = ac.worldCoordinateToTrack(ac.getCar(i).position)
  local s = ac.getTrackAISplineSides(t.z)
  return t.x < 0 and t.x * s.x or t.x * s.y
end

local aboutToStart = false
local v3A = vec3()
local v3B = vec3()

local function carSplineDir(i, shift)
  local aiCar = ac.getCar(i)
  ac.trackProgressToWorldCoordinateTo((aiCar.splinePosition + (shift + 20) / Sim.trackLengthM) % 1, v3A, true)
  ac.trackProgressToWorldCoordinateTo((aiCar.splinePosition + shift / Sim.trackLengthM) % 1, v3B, true)
  return v3A:sub(v3B):normalize()
end

Register('core', function (dt)
  local isRace = Sim.raceSessionType == ac.SessionType.Race
  local haveTimeBeforeStart = Sim.timeToSessionStart > 1e3

  if isRace and aboutToStart and not haveTimeBeforeStart then
    aboutToStart = false
    if fixTrajectory then
      local maxOffset = 0.01
      for i = 0, Sim.carsCount - 1 do
        local value = math.clamp(carSplineOffset(i), -10, 10)
        maxOffset = math.max(math.abs(value), maxOffset)
        carOffsets[i] = {value, carSplineDir(i, 0):clone()}
        physics.setAISplineAbsoluteOffset(i, value, false)
        ac.debug('AI offset: %s' % i, value)
      end
      carOffsetsApplied = maxOffset
      ac.debug('Max AI offset', maxOffset)
    end
  end

  if haveTimeBeforeStart and isRace then
    aboutToStart = true
    if fixRedlining then
      throttleLimited = true
      for i = 0, Sim.carsCount - 1 do
        local noise = randomNoise(i)
        if Sim.timeToSessionStart < 1.5e3 and ac.getCar(i).turboCount > 0 then
          noise = 1
        end
        physics.setAIThrottleLimit(i, noise > 0.6 and 1 or 0)
      end
    end
  elseif throttleLimited then
    throttleLimited = false
    for i = 0, Sim.carsCount - 1 do
      physics.setAIThrottleLimit(i, 1)
    end
  end

  if carOffsetsApplied > 0 and Sim.timeToSessionStart < -0.5e3 then
    local decrease = dt * 0.5
    carOffsetsApplied = math.max(0, carOffsetsApplied - decrease)
    for i = 0, Sim.carsCount - 1 do
      local value = carOffsets[i]
      if value[1] ~= 0 then
        local decreaseBoost = 1 + math.lerpInvSat(carSplineDir(i, 100):dot(value[2]), 0.99, 0.5) * 10
        value[1] = math.sign(value[1]) * math.max(0, math.abs(value[1]) - decrease * decreaseBoost)
        physics.setAISplineAbsoluteOffset(i, math.clamp(value[1], -8, 8), false)
        ac.debug('AI offset: %s' % i, value[1])
      end
    end
  end
end)
