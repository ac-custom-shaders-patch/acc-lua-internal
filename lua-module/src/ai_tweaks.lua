if not AIRace then
  return
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

Register('core', function (dt)
  local isRace = Sim.raceSessionType == ac.SessionType.Race
  local haveTimeBeforeStart = Sim.timeToSessionStart > 0.5e3

  if isRace and aboutToStart and not haveTimeBeforeStart then
    aboutToStart = false
    if fixTrajectory then
      local maxOffset = 0.01
      for i = 0, Sim.carsCount - 1 do
        local value = carSplineOffset(i)
        maxOffset = math.max(math.abs(value), maxOffset)
        carOffsets[i] = value
        physics.setAISplineAbsoluteOffset(i, value, false)
      end
      carOffsetsApplied = maxOffset
    end
  end

  if haveTimeBeforeStart and isRace then
    aboutToStart = true
    if fixRedlining then
      throttleLimited = true
      for i = 0, Sim.carsCount - 1 do
        local noise = randomNoise(i)
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
      if value ~= 0 then
        value = value > 0 and math.max(0, value - decrease) or math.min(0, value + decrease)
        carOffsets[i] = value
        physics.setAISplineAbsoluteOffset(i, value, false)
      end
    end
  end
end)
