--[[
  Sets accent color for hardware such as gamepads. Use this library to get all the supported hardware to work
  (plus it would also guarantee the support for future types of hardware added).
  Simply add `require('shared/dualsense/accent').color(rgbm(1, 0, 0, 1), 10, 5)` (second argument for priority;
  third argument for time to hold the color for, subsequent calls override previously set values).
]]

local dualSenseAccent = {}

---Stops regular pad processing (where it might move the mouse).
function dualSenseAccent.color(color, priority, holdFor)
  local ds = ac.setDualSense(0, priority, holdFor)
  if ds ~= nil then ds.lightBar = color end

  local dh = ac.setDualShock(0, priority, holdFor)
  if dh ~= nil then dh.lightBar = color end
end

return dualSenseAccent
