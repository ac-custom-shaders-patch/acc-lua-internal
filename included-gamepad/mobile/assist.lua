-- Mobile app: https://snack.expo.dev/@x4fab/gamepad-app
require 'common'

-- For passing data to Small Tweaks DualSense module and for showing QR code for connection
ac.loadRenderThreadModule('module_render')

local steerSmooth = 0
local step = 0
local baseSteer = 0
local ffbSmooth = 0
local offsetSmooth = 0

local avgTimeBetweenPackets = 0
local smSteer = 0
local prevSteerSm = 0
local prevSteerSmooth = 0
local smPacketAgeMs = 0
local smPacketExpectedAgeMs = 0
local smPacketTime = 0
local smSteerSpeed = 0
local hadConnection = false
local hazardsOn = false
local stable = true

local function vibratingMechanism(minDelay, maxDelay)
	local active = 0
	local wait = 0
	return function (baseValue, value)
		if value < 0.1 then
			active = 0
			wait = 0
			return baseValue
		end
		if active > 0 then
			active = active - 1
			return 0.3
		end
		if wait > 0 then
			wait = wait - 1
		else
			active = 1
			wait = math.lerp(maxDelay or 10, minDelay or 0, value)
		end
		return baseValue
	end
end

local vibSlide = vibratingMechanism(0, 4)
local vibCurb = vibratingMechanism(3, 6)
local vibDirt = vibratingMechanism(4, 10)
local modeSwitchPrev = false
local lastPacketTime = 1e30

local modeStored = ac.storage('mode:'..ac.getCarID(0), require('shared/info/cars').isDriftCar(0))

function script.update(dt)
  local state = ac.getJoypadState()
  step = step > 100 and 0 or step + 1

  state.gas = SM.gas
  state.brake = SM.brake
  state.clutch = SM.clutch
  state.handbrake = SM.handbrake
  state.gearUp = SM.gearUp
  state.gearDown = SM.gearDown
  state.headlightsSwitch = SM.headlightsSwitch
  state.headlightsFlash = SM.headlightsFlash
  state.changingCamera = SM.changingCamera
  state.horn = SM.horn
  state.absDown = SM.absDown
  state.absUp = SM.absUp
  state.tcDown = SM.tcDown
  state.tcUp = SM.tcUp
  state.turboDown = SM.turboDown
  state.turboUp = SM.turboUp
  
  if SM.packetTime > smPacketTime then
    if smPacketTime ~= 0 then
      local timePassed = tonumber(SM.packetTime - smPacketTime)
      smSteerSpeed = tonumber(SM.steer - prevSteerSm) / timePassed
      avgTimeBetweenPackets = avgTimeBetweenPackets == 0 and timePassed or (avgTimeBetweenPackets * 29 + timePassed) / 30
      ac.debug('Time between packets', avgTimeBetweenPackets)

      if SM.packetTime < lastPacketTime then
        lastPacketTime = SM.packetTime
        SM.driftMode = modeStored:get()
      end
    end
    prevSteerSmooth = steerSmooth
    smPacketAgeMs = 0
    smPacketExpectedAgeMs = avgTimeBetweenPackets
    smPacketTime = SM.packetTime
    smSteer = SM.steer + smSteerSpeed * tonumber(SM.currentTime - SM.packetTime)
    prevSteerSm = SM.steer
  elseif SM.packetTime < smPacketTime then
    prevSteerSmooth = steerSmooth
    smPacketAgeMs = 0
    smPacketExpectedAgeMs = avgTimeBetweenPackets
    smSteerSpeed = 0
    smPacketTime = SM.packetTime
    smSteer = SM.steer
    prevSteerSm = SM.steer
  end

  -- TODO: Horrible way, find a better one
  if math.abs(smSteerSpeed) > 200 then
    ac.log('Unstable values, switching to simple mode')
    stable = false
  else
    smSteerSpeed = math.sign(smSteerSpeed) * math.min(0.1, math.abs(smSteerSpeed))
  end

  if not stable then
    prevSteerSmooth = SM.steer
    smSteer = SM.steer
    smSteerSpeed = 0
  end

  -- smSteer = SM.steer
  smPacketAgeMs = smPacketAgeMs + dt * 1e3

  if IsOffline() then
    if hadConnection then
      hazardsOn = true
      ac.setTurningLights(ac.TurningLights.Hazards)
    end
    SM.gas = math.applyLag(SM.gas, 0, 0.8, dt)
    SM.brake = math.applyLag(SM.brake, 1, 0.8, dt)
    steerSmooth = math.applyLag(steerSmooth, 0, 0.8, dt)
    if SM.absOff then
      SM.absDown = true
    end
  else
    if hazardsOn then
      hazardsOn = false 
      ac.setTurningLights(ac.TurningLights.None) 
    end
    -- steerSmooth = math.lerp(prevSteerSmooth, smSteer, math.min(1, smPacketAgeMs / smPacketExpectedAgeMs)) + smSteerSpeed * smPacketAgeMs
    steerSmooth = math.applyLag(steerSmooth, SM.steer, 0.7, dt)
    hadConnection = true

    if modeSwitchPrev ~= SM.modeSwitch then
      modeSwitchPrev = not modeSwitchPrev
      if modeSwitchPrev then
        SM.driftMode = not SM.driftMode
        modeStored:set(SM.driftMode)
        ac.setSystemMessage('Gamepad mode', 'Switched to '..(SM.driftMode and 'Drift' or 'Race'))
      end
    end
  end

  -- Steer as-is:
  -- state.steer = steerSmooth / math.pi * 360 / car.steerLock / 2
  -- if true then return end

  local gamepadAngle = steerSmooth * 0.14
  local gammed = SM.driftMode 
    and math.tan(gamepadAngle * 3.5) / 3.5
    or math.tan(gamepadAngle * 4) / 4
  local edgeLag = 0.9 * math.saturateN(math.abs(baseSteer) * 4)
  baseSteer = math.applyLag(baseSteer, gammed, edgeLag, dt)

  ffbSmooth = math.applyLag(ffbSmooth, state.ffb, 0.9, dt)
  local ffbSteer = SM.driftMode 
    and baseSteer + ffbSmooth * -0.12 * math.lerp(1, 0, math.min(1, math.abs(baseSteer) * 3) ^ 3)
    or baseSteer + ffbSmooth * -0.06

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
  state.steer = SM.driftMode
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

  -- Minor vibrations on the right
	state.vibrationRight = 0
  local wheelLF = math.abs(math.dot(math.normalize(car.wheels[0].velocity), car.wheels[0].look))
  local wheelRF = math.abs(math.dot(math.normalize(car.wheels[1].velocity), car.wheels[1].look))
  state.vibrationRight = vibSlide(state.vibrationRight, math.abs(state.ffb) 
    * math.lerpInvSat(car.speedKmh, 2, 5)
    * math.pow(math.sqrt(1 - math.pow(math.min(wheelLF, wheelRF), 2)) * 3, 1.5))

  -- Major vibrations on the left
	state.vibrationLeft = 0
  state.vibrationLeft = vibCurb(state.vibrationLeft, speedMult 
  * math.max(state.surfaceVibrationGainLeft, state.surfaceVibrationGainRight) * 2)
  state.vibrationLeft = vibDirt(state.vibrationLeft, dirt * speedMult * 0.2)

	if car.collisionDepth > 0 and car.speedKmh > 10 then
		state.vibrationLeft = 1
		state.vibrationRight = 1
	end

  SM.vibrationLeft = state.vibrationLeft * 255
  SM.vibrationRight = state.vibrationRight * 255
end
