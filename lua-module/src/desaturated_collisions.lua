if Config:get('MISCELLANEOUS', 'DESATURATING_COLLISIONS', false) then
  local speedLast = Car.speedKmh
  local hit = 0
  Register('gameplay', function(dt)
    if Sim.cameraMode == ac.CameraMode.Cockpit or Sim.cameraMode == ac.CameraMode.Drivable then
      if hit > 0 then
        hit = math.max(0, hit - dt)
      end
      if Car.collisionDepth > 0 and dt > 0 then
        local nHit = math.saturateN((speedLast - Car.speedKmh) / 60)
        if nHit > hit then
          hit = nHit
        end
      end
    else
      hit = 0
    end
    speedLast = math.applyLag(speedLast, Car.speedKmh, 0.8, dt)
    ac.setColorCorrection(false):saturation((1 - hit) ^ 2):contrast(1 + 2 * hit):brightness(1 - 0.7 * hit)
  end)
end

