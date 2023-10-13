--[[
  Animates driver model using VR controllers. Not a proper IK thing, just a quick approximation. Something to
  work on and improve further later on.

  External scripts can use “shared/vr/grab” library to integrate with this one and override hand state so that
  fingers would wrap around grapped objects properly.
]]

-- local rig0 = VRRig.Remote(ac.getCar(0)) ---@type VRRig.Remote
-- local rig1 = VRRig.Remote(ac.getCar(2)) ---@type VRRig.Remote
-- setInterval(function ()
--   local con = ac.connect({
--     handL = ac.StructItem.mat4x4(),
--     handR = ac.StructItem.mat4x4(),
--     head = ac.StructItem.mat4x4(),
--     flags = ac.StructItem.byte(),
--     handStateL = ac.StructItem.byte(),
--     handStateR = ac.StructItem.byte(),
--   })
--   con.flags = 7
--   con.handL = mat4x4.identity()
--   con.handR = mat4x4.identity()
--   con.head = mat4x4.identity()
--   con.handL.look = vec3(0, 0, -1)
--   con.handR.look = vec3(0, 0, -1)
--   con.handL.position = vec3(0.5, math.sin(os.preciseClock() * 3), 0.5)
--   con.handR.position = vec3(-0.5, math.sin(os.preciseClock() * 4), 0.5)
--   con.head.position = vec3(math.sin(os.preciseClock() * 5), 0, 0)
--   rig0:data(con)
--   rig1:data(con)
-- end)

-- Register('simUpdate', function (dt)
--   rig0:update(dt)
--   rig1:update(dt)
-- end)

if not Sim.isOnlineRace or not Sim.directUDPMessagingAvailable then
  return
end

---@type VRRig.Remote[]
local rigs = {}
setTimeout(Register('simUpdate', function () end))

local function setExtraData()
  local ev, evDataFactory = ac.OnlineEvent({
    handL = ac.StructItem.transform(true, true, -1, 1),
    handR = ac.StructItem.transform(true, true, -1, 1),
    head = ac.StructItem.transform(true, true, -1, 1),
    flags = ac.StructItem.byte(),
    handStateL = ac.StructItem.byte(),
    handStateR = ac.StructItem.byte(),
  }, function (sender, message)
    if not sender or sender.index == 0 then return end
    local rig = rigs[sender.index]
    if not rig then
      rig = VRRig.Remote(sender)
      rigs[sender.index] = rig
    end
    rig:data(message)
  end, '$SmallTweaks.ExtraData', {range = 50})

  local car = ac.getCar(0)
  local vr = ac.getVR()
  local evData = evDataFactory()
  if car and vr then
    local encoder = VRRig.Encoder(car, vr) ---@type VRRig.Encoder
    setInterval(function ()
      if Sim.cameraMode == ac.CameraMode.Cockpit and Sim.focusedCar == 0 and (vr.headActive or vr.hands[0].active or vr.hands[1].active) then
        encoder:encode(evData)
        ev(nil)
      end
    end, 0.1)
  end

  Register('simUpdate', function (dt)
    for _, v in pairs(rigs) do
      v:update(dt)
    end
  end)
end

ac.onOnlineWelcome(function (message, config)
  if config:get('EXTRA_DATA', 'VR', false) then
    setExtraData()
  end
end)


