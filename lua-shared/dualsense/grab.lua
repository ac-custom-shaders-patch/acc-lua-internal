--[[
  If you want to use PS5 DualSense pad for something specific, use this library to stop pad from moving mouse.
  Simply add `require('shared/dualsense/grab').pad(true)`.

  Also stops pad on PS4 DualShock now (but you need to use `ac.getDualShock(controllerIndex)` to access it).
]]

local dualSensePadOverride = ac.connect({
  ac.StructItem.key('dualSensePadOverride'),
  override = ac.StructItem.boolean()
}, false, ac.SharedNamespace.Shared)

local dualSenseGrab = {}

---Stops regular pad processing (where it might move the mouse).
function dualSenseGrab.pad(active)
  dualSensePadOverride.override = active
end

return dualSenseGrab
