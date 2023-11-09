local gamepadAngle = 0
local baseSteer = 0
local ffbSmooth = 0
local offsetSmooth = 0
local bodyYVelPrev = 0
local collisionCooldown = 0

---@param state ac.StateJoypadData
---@param driftMode boolean
---@param step integer
---@param dt number
return function(state, driftMode, step, dt)
  local ds = ac.getDualShock(state.gamepadIndex)
  if ds == nil then return end

  -- Adding accelerometer to steering  
  local accDir = ds.accelerometer:clone():normalize()
  local accAngle = -math.atan2(accDir.x, #vec2(accDir.y, accDir.z)) * 0.2    
  local fastTurning = math.pow(math.saturateN(math.abs(ds.gyroscope.x * 0.03) - 0.1), 3)
  local fastTurningLag = math.lerp(0.95, 0.5, fastTurning)
  gamepadAngle = gamepadAngle - ds.gyroscope.z * dt * 0.0037
  gamepadAngle = math.applyLag(gamepadAngle, accAngle, fastTurningLag, dt)

  local gammed = driftMode
    and math.tan(gamepadAngle * 3.5) / 3.5
    or math.tan(gamepadAngle * 4) / 4
  local edgeLag = 0.9 * math.saturateN(math.abs(baseSteer) * 4)
  baseSteer = math.applyLag(baseSteer, gammed, edgeLag, dt)
	local finalSteer = baseSteer * ScriptSettings.SENSITIVITY * 2

  ffbSmooth = math.applyLag(ffbSmooth, state.ffb, 0.9, dt)
  local ffbSteer = driftMode
    and finalSteer + ffbSmooth * -0.12 * math.lerp(1, 0, math.min(1, math.abs(finalSteer) * 3) ^ 3)
    or finalSteer + ffbSmooth * -0.06

  local offsetMult = math.lerpInvSat(state.speedKmh, 5, 10)
  local carDirection = math.normalize(car.velocity)
  local drivingFwd = math.dot(carDirection, car.look)
  local offsetSteer = offsetMult > 0 and -math.dot(carDirection, car.side) or 0
  if drivingFwd < 0 then
    offsetSteer = math.sign(offsetSteer) * math.lerpInvSat(drivingFwd, -1, -0.85)
  else
    offsetSteer = math.smoothstep(math.abs(offsetSteer)) * math.sign(offsetSteer)
  end
  offsetSmooth = math.applyLag(offsetSmooth, offsetMult * offsetSteer, 0.7, dt)
  state.steer = driftMode
    and math.clampN((state.steer + ffbSteer + offsetSmooth * 0.2) * 900 / car.steerLock, -1, 1)
    or math.clampN((state.steer + ffbSteer + offsetSmooth * 0) * 500 / car.steerLock, -1, 1)

  -- Analyzing surface for estimating vibrations
  local speedMult = math.lerpInvSat(state.speedKmh, 20, 60)
  local dirt, ndSlip = 0, 0
  for i = 0, 1 do
    local mult = car.wheels[i].loadK
    dirt = dirt + car.wheels[i].surfaceDirt * mult
    ndSlip = math.max(ndSlip, car.wheels[i].ndSlip * mult)
  end

  local bodyYVel = math.dot(car.velocity, car.groundNormal)
  local bodyYDelta = bodyYVel - bodyYVelPrev
  bodyYVelPrev = math.applyLag(bodyYVelPrev, bodyYVel, 0.6, dt)

  -- Minor vibrations on the right
  state.vibrationRight = (car.absMode == 0 or step % 50 < 25)
    and math.min(car.brake * 20, 1) * math.lerpInvSat(ndSlip, 0.3, 1) or 0
  state.vibrationRight = math.max(state.vibrationRight, dirt * speedMult * 0.2)
  state.vibrationRight = math.max(state.vibrationRight, math.lerpInvSat(math.abs(bodyYDelta), 0.15, 1) * speedMult)

  -- Major vibrations on the left
  local wheelLF = math.abs(math.dot(math.normalize(car.wheels[0].velocity), car.wheels[0].look))
  local wheelRF = math.abs(math.dot(math.normalize(car.wheels[1].velocity), car.wheels[1].look))
  state.vibrationLeft = math.abs(state.ffb) 
    * math.lerpInvSat(car.speedKmh, 2, 5)
    * math.pow(math.sqrt(1 - math.pow(math.min(wheelLF, wheelRF), 2)) * 3, 1.5)    
  state.vibrationLeft = math.max(state.vibrationLeft,
    speedMult * math.max(state.surfaceVibrationGainLeft, state.surfaceVibrationGainRight) * 2)

  -- Ton of vibrations on active collision
  if car.collisionDepth > 0 and car.speedKmh > 10 then
    if collisionCooldown <= 0 then
      state.vibrationLeft = 1
      state.vibrationRight = 1
    end
    collisionCooldown = 0.1
  elseif collisionCooldown > 0 then
    collisionCooldown = collisionCooldown - dt
  end
end

