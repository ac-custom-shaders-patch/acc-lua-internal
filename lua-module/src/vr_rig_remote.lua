--[[
  Animates driver model using VR controllers. Not a proper IK thing, just a quick approximation. Something to
  work on and improve further later on.

  External scripts can use “shared/vr/grab” library to integrate with this one and override hand state so that
  fingers would wrap around grapped objects properly.
]]

if not Sim.isOnlineRace and not Sim.isAltOnlineRace or not Sim.directUDPMessagingAvailable then
  return
end

---@type VRRig.Remote[]
local remoteRigs = {}

ac.onCarSwap(-1, function (carIndex) remoteRigs[carIndex] = nil end)
ac.onClientDisconnected(function (disconnectedCarIndex) remoteRigs[disconnectedCarIndex] = nil end)

local function setExtraData()
  local function getRig(sender)
    local rig = remoteRigs[sender.index]
    if not rig then
      rig = VRRig.Remote(sender)
      remoteRigs[sender.index] = rig
    end
    return rig
  end

  local ev1, ev1DataFactory = ac.OnlineEvent({
    ac.StructItem.explicit(1, 1),
    handL = ac.StructItem.transform(true, true, -1, 1),
    handR = ac.StructItem.transform(true, true, -1, 1),
    head = ac.StructItem.transform(true, true, -1, 1),
    packetIndex = ac.StructItem.byte(),
    flags = ac.StructItem.byte(),
    handStateL = ac.StructItem.byte(),
    handStateR = ac.StructItem.byte(),
  }, function (sender, message)
    if not sender or sender.index == 0 then return end
    getRig(sender):data(message, false)
  end, '$SmallTweaks.VRRig', {range = 50})
  local ev2, ev2DataFactory = ac.OnlineEvent({
    ac.StructItem.explicit(1, 1),
    head = ac.StructItem.transform(true, true, -1, 1),
    packetIndex = ac.StructItem.byte(),
    flags = ac.StructItem.byte(),
  }, function (sender, message)
    if not sender or sender.index == 0 then return end
    getRig(sender):data(message, true)
  end, '$SmallTweaks.VRRig', {range = 50})

  local vr = ac.getVR()
  local ev1Data, ev2Data = ev1DataFactory(), ev2DataFactory()
  if Car and vr then
    local encoder = VRRig.Encoder(Car, vr) ---@type VRRig.Encoder
    local prevPosL, prevPosR = vec3(), vec3()

    local sendHandsFor = 0
    local function shouldSendHands()
      if not vr.hands[0].active and not vr.hands[1].active then return false end
      if not vr.hands[0].transform.position:closerToThan(prevPosL, 0.003) then
        prevPosL:set(vr.hands[0].transform.position)
        sendHandsFor = 5
      end
      if not vr.hands[1].transform.position:closerToThan(prevPosR, 0.003) then
        prevPosR:set(vr.hands[1].transform.position)
        sendHandsFor = 5
      end
      if sendHandsFor > 0 then
        sendHandsFor = sendHandsFor - 1
        return true
      end
      return false
    end

    local prevPacketIndex = 0
    local sendFn
    sendFn = function ()
      if Sim.cameraMode == ac.CameraMode.Cockpit and Sim.focusedCar == 0 or VRRIG_DEBUG_MODE then
        local hands = shouldSendHands()
        if vr.headActive or hands then
          prevPacketIndex = (prevPacketIndex + 1) % 256
          if hands then
            encoder:encode(ev1Data, false)
            ev1Data.packetIndex = prevPacketIndex
            ev1(nil)
          else
            encoder:encode(ev2Data, true)
            ev2Data.packetIndex = prevPacketIndex
            ev2(nil)
          end
          setTimeout(sendFn, hands and 0.05 or 0.1)
          return
        end
      end
        setTimeout(sendFn, 0.2)
    end
    setTimeout(sendFn, 1)
  end
end

Register('simUpdate', function (dt)
  for _, v in pairs(remoteRigs) do
    v:update(dt)
  end
end)

ac.onOnlineWelcome(function (message, config)
  if config:get('EXTRA_DATA', 'VR', false) then
    setExtraData()
  end
end)


