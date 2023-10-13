local virtualSteer = 0
local steerAngle = 0
local steerVelocity = 0
local driverSteerAngle = 0
local driverSteerVelocity = 0

ac.onCarJumped(0, function ()
  steerVelocity = 0
  steerAngle = 0
  driverSteerAngle = 0
  driverSteerVelocity = 0
end)

local steerStickSpeedBase = 20
local steerForceVelocityDecrease = 1
local ffbPositionMultSameDirection = 0.5
local ffbPositionMultOppositeDirection = 1
local ffbPositionMultGamma = 1
local steerAngleFadeBase = 0.9943
local steerVelocityBoundaryMult = 0.8
local speedForceBase = 0.39
local forceFactorBase = 12

local function update(dt)
  -- Assist-related data
  local data = ac.getJoypadState()

  -- Input steer angle (TODO: switch to data.steerStick to use original settings)
  -- local steer = ac.getGamepadAxisValue(0, ac.GamepadAxis.LeftThumbX)

  -- A bit of gamma correction to improve deadzone situation (TODO: also add regular deadzone)
  -- steer = math.pow(steer, 2) * math.sign(steer)
  -- steer = math.lerpInvSat(math.abs(steer), 0.1, 1) * math.sign(steer)

  -- Actual steering input:
  local steer = virtualSteer
  local speedForce = speedForceBase
  local forceFactor = forceFactorBase
  local steerAngleFade = steerAngleFadeBase
  speedForce = speedForce - (math.abs(data.steerStickX)^2)*0.14
  local steerAD = ((math.abs(data.localAngularVelocity.y) + 0.5) / (1 + (math.abs(data.localVelocity.x)^0.3)))
   if steerAD > 0.7 then
	steerAD = 0.7
  end 
   if steerAD < 0.3 then
	steerAD = 0.3
  end 
  speedForce = speedForce * (1 + steerAD/8)*(1 + (data.speedKmh / 1000))
  if (data.ndSlipRR + data.ndSlipRL)/2 < 1 then
    steerAD = 0.3
	steerAngleFade = 0.993
	speedForce = 0.1
  end  
  local newSteerStick = data.steerStickX * steerAD
  local steerStickSpeed = steerStickSpeedBase
  local steerDelta = newSteerStick - steer
  steer = steer + math.min(steerStickSpeed * dt, math.abs(steerDelta)) * math.sign(steerDelta)
  virtualSteer = steer

  -- Base steering force:
  local steerForce = steer
   
  -- FFB force:
  local ffbForce = -data.ffb * speedForce
  local ffbPositionMult = math.sign(steerAngle) == math.sign(ffbForce) and ffbPositionMultSameDirection or ffbPositionMultOppositeDirection
  ffbForce = ffbForce * math.lerp(1, ffbPositionMult, math.pow(math.abs(steerAngle), ffbPositionMultGamma))

  -- Resulting force is the sum of both:
  local force = steerForce + ffbForce

  -- Applying tonemapping-like correction to make sure force would not exceed 1
  force = force / (1 + math.abs(force))

  -- Force and velocity application with a bit of drag
  local dSteer = (data.steerStickX * (data.localVelocity.x * 0.001)) * (-0.05) + (1 + math.abs(data.localVelocity.x)^0.3) * 0.00025
  steerAngleFade = steerAngleFade + dSteer
  if steerAngleFade > 0.997 then
	steerAngleFade = 0.997
  end 
  steerVelocity = steerVelocity * steerAngleFade + forceFactor * force * dt  
  steerAngle = steerAngle * steerAngleFade + steerVelocity * dt

  -- Driver steering
  --local driverSteerShare = math.max(math.min(1, math.abs(steer * 10)), math.lerpInvSat(data.speedKmh, 20, 10))
  --driverSteerVelocity = driverSteerVelocity * steerAngleFade + 50 * force * dt * driverSteerShare
  --driverSteerAngle = math.clamp(driverSteerAngle * math.lerp(driverSteerAngleFade, steerAngleFade, driverSteerShare) + driverSteerVelocity * dt, -1, 1)
  
  --ac.setCustomDriverModelSteerAngle(driverSteerAngle * ac.getCar(0).steerLock)

  -- Very important part
  if steerAngle < -1 or steerAngle > 1 then
    steerVelocity = steerVelocity * steerVelocityBoundaryMult
  end  

  -- Writing new steer angle with a bit of smoothing just in case (completely ignoring original value)
  data.steer = math.clamp(steerAngle, -1, 1)

  -- Vibrations
  local baseForce = math.saturate(data.speedKmh / 20 - 0.5) * math.abs(ffbForce * 4) * math.saturate(math.abs(ffbForce - steerForce) * 2 - 0.5)
  local offset = data.gForces.x / (1 + math.abs(data.gForces.x)) -- slightly offset vibrations based on X g-force (might have a wrong sign though)
  data.vibrationLeft = baseForce * (1 + offset) + math.saturate(data.speedKmh / 100) * data.surfaceVibrationGainLeft / 20
  data.vibrationRight = baseForce * (1 - offset) + math.saturate(data.speedKmh / 100) * data.surfaceVibrationGainRight / 20
  
  -- Debug:
  --ac.debug('data.localVelocity.x', data.localVelocity.x)
  --ac.debug('speedForce', speedForce) 
  --ac.debug('forceFactor', forceFactor)
  --ac.debug('steerAngleFade', steerAngleFade)  
  --ac.debug('steerAD', steerAD)  
  --ac.debug('dSteer', dSteer) 
end

return {
  name = 'Drift',
  update = update, 
  sync = function (m) steerAngle, steerVelocity = m.export() end,
  export = function () return steerAngle, steerVelocity end,
}

