-- if Sim.cameraMode == ac.CameraMode.Start then
--   local cap = ac.grabCamera('intro')
--   if cap then
--     cap.ownShare = 1
--     cap.transform.position.y = 1e9
--     cap.transform.look = vec3(0, -1, 0)
--     cap.transform.up = mat4x4.rotation(math.rad(ac.getCompassAngle(vec3(0, 0, 1))), vec3(0, 1, 0)):transformVector(vec3(0, 0, 1))
--     setInterval((function (v)
--       v[1] = v[1] + ac.getDeltaT() * 0.5
--       cap.transform.position.y = Car.position.y + math.max(0, 1 - v[1]) ^ 1.4 * 1e8
--       cap.ownShare = math.saturate((cap.transform.position.y - Car.position.y) / 1e3)
--       if cap.ownShare < 0.01 then
--         cap:dispose()
--         return clearInterval
--       end
--     end):bind({0}))
--   end
-- end
