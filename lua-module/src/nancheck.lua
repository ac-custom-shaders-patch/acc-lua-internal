Register('core', function (dt)
  if not math.isfinite(Sim.cameraPosition.x) then
    if not math.isfinite(Car.position.x) then
      ac.setMessage('Simulation failed', 'Consider restarting the race')
    else
      -- ac.setMessage('Camera failed', 'Change camera to a different mode')
    end
    return
  end
end)