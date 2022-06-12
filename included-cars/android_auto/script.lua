require('touchscreen')
require('system')

function script.update(dt)
  system.update(dt)
end

-- local flames = ac.Particles.Flame({
--   color = rgbm(0.5, 0.5, 0.5, 0.5),
--   size = 0.2,
--   temperatureMultiplier = 1,
--   flameIntensity = 2
-- })

-- function script.update(dt)
--   if car.brake > 0.5 then
--     flames:emit(vec3(0, 1.5, 0), vec3(0, 1, 0), 1)
--   end
-- end
