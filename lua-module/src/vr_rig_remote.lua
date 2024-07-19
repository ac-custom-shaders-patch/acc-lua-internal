--[[
  Animates driver model using VR controllers. Not a proper IK thing, just a quick approximation. Something to
  work on and improve further later on.

  External scripts can use “shared/vr/grab” library to integrate with this one and override hand state so that
  fingers would wrap around grapped objects properly.
]]

--[[
  
    io.save(ac.getFolder(ac.FolderID.ExtCache)..'/vr_dump.bin', stringify.binary({
      debugReceived = debugReceived,
      debugSent = debugSent,
    }))stringify.binary({
          handL = evData.handL,
          handR = evData.handR,
          head = evData.head,
          flags = evData.flags,
          handStateL = evData.handStateL,
          handStateR = evData.handStateR,
        })
]]
-- local data = stringify.binary.tryParse(io.load('C:/test/vr_dump.bin'))
-- ac.debug('debugSent', #data.debugSent)

-- local frame = 1

-- local conAlt = ac.connect({
--   handL = ac.StructItem.transform(true, true, -1, 1),
--   handR = ac.StructItem.transform(true, true, -1, 1),
--   head = ac.StructItem.transform(true, true, -1, 1),
--   flags = ac.StructItem.byte(),
--   handStateL = ac.StructItem.byte(),
--   handStateR = ac.StructItem.byte(),
-- })

-- ac.debug('here', 'there')
-- local rig0 = VRRig.Remote(ac.getCar(0)) ---@type VRRig.Remote
-- -- local rig1 = VRRig.Remote(ac.getCar(2)) ---@type VRRig.Remote
-- local encoder = VRRig.Encoder(ac.getCar(0), nil) ---@type VRRig.Encoder
-- setInterval(function ()
--   frame = frame + 1
--   if frame > #data.debugSent then
--     frame = 1
--   end
--   local con = stringify.binary.parse(data.debugSent[frame])
--   ac.debug('con.head', con.head.position)
--   ac.debug('con.handL', con.handL.position)
--   ac.debug('con.handR', con.handR.position)
--   -- local con = ac.connect({
--   --   handL = ac.StructItem.transform(true, true, -1, 1),
--   --   handR = ac.StructItem.transform(true, true, -1, 1),
--   --   head = ac.StructItem.transform(true, true, -1, 1),
--   --   flags = ac.StructItem.byte(),
--   --   handStateL = ac.StructItem.byte(),
--   --   handStateR = ac.StructItem.byte(),
--   -- })
--   -- local h = mat4x4.identity()
--   -- h.position = vec3(math.sin(os.preciseClock() * 5), 0, 0)
--   -- con.flags = 7
--   -- con.handL = mat4x4.identity()
--   -- con.handR = mat4x4.identity()
--   -- con.head = mat4x4.identity()
--   -- con.handL.look = vec3(0, 0, -1)
--   -- con.handR.look = vec3(0, 0, -1)
--   -- con.handL.position = vec3(0.5, math.sin(os.preciseClock() * 3), 0.5)
--   -- con.handR.position = vec3(-0.5, math.sin(os.preciseClock() * 4), 0.5)
--   -- con.head = h
--   -- rig0:data(entry)
--   rig0:data(con)
--   encoder:encode(conAlt)
--   ac.debug('conAlt.head', conAlt.head.position)
--   ac.debug('conAlt.handL', conAlt.handL.position)
--   ac.debug('conAlt.handR', conAlt.handR.position)
--   -- rig1:data(con)
-- end)

-- Register('simUpdate', function (dt)
--   rig0:update(dt)
--   -- rig1:update(dt)
-- end)

if false then
  local car = ac.getCar(0)
  local carRoot = ac.findNodes('carRoot:0')
  local carRootTransform = carRoot:getWorldTransformationRaw():inverse()
  local driverRoot = carRoot:findNodes('driverRoot:0')
  local neckNode = driverRoot:findNodes('driverNeck:0')
  local headPos = carRootTransform:transformPoint(driverRoot:findNodes('DRIVER:RIG_Cest'):getWorldTransformationRaw().position):add(vec3(0, 0.28, 0))
  local matTmp = mat4x4()

  local compressor = ac.connect({
    head = ac.StructItem.transform(true, true, -1, 1),
  })

  setInterval(function ()  
    neckNode:getWorldTransformationRaw():mulTo(matTmp, car.worldToLocal)
    matTmp.position:sub(headPos)

    ac.debug('base.pos', matTmp.position)

    compressor.head = matTmp
    ac.debug('compressed.pos', compressor.head.position)
  end)
end

if not Sim.isOnlineRace or not Sim.directUDPMessagingAvailable then
  return
end

---@type VRRig.Remote[]
local rigs = {}
setTimeout(Register('simUpdate', function () end))

local function setExtraData()
  local debugReceived = {}
  local debugSent = {}

  setInterval(function ()
    io.save(ac.getFolder(ac.FolderID.ExtCache)..'/vr_dump.bin', stringify.binary({
      debugReceived = debugReceived,
      debugSent = debugSent,
    }))
  end, 30)

  local ev, evDataFactory = ac.OnlineEvent({
    -- handL = ac.StructItem.transform(true, true, -1, 1),
    -- handR = ac.StructItem.transform(true, true, -1, 1),
    -- head = ac.StructItem.transform(true, true, -1, 1),
    handL = ac.StructItem.transform(false, false),
    handR = ac.StructItem.transform(false, false),
    head = ac.StructItem.transform(false, false),
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

    table.insert(table.getOrCreate(debugReceived, sender.index, function (callbackData)
      return {}
    end), stringify.binary({
      handL = message.handL,
      handR = message.handR,
      head = message.head,
      flags = message.flags,
      handStateL = message.handStateL,
      handStateR = message.handStateR,
    }))

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

        table.insert(debugSent, stringify.binary({
          handL = evData.handL,
          handR = evData.handR,
          head = evData.head,
          flags = evData.flags,
          handStateL = evData.handStateL,
          handStateR = evData.handStateR,
        }))

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
  if config:get('EXTRA_DATA', 'VR_DEV', false) then
    setExtraData()
  end
end)


