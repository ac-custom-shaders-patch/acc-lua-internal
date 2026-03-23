local altonline = require('shared/sim/altonline')
local steam = require('shared/utils/luasteam')
require('./gns').init(nil)

local ownCar = ac.getCar(0) or error()
local connect = ac.connect({
  ac.StructItem.key('mode.p2p1v1.v1'),
  handle = ac.StructItem.double(),
  ping = ac.StructItem.double(),
  roleClient = ac.StructItem.boolean(),
  unlimitedConnection = ac.StructItem.boolean(),
})
connect.ping = 0

local syncFrameIndex = 0

setInterval(function()
  if connect.handle == 0 then return end
  if syncFrameIndex == 0 or ownCar.speedKmh > 1 then
    steam.networkingSockets.sendMessageToConnection(connect.handle, '0'..altonline.packCarState1(0), steam.networkingSockets.flags.UnreliableNoDelay)
  end
  syncFrameIndex = syncFrameIndex + 1
  if syncFrameIndex > 4 then syncFrameIndex = 0 end
end, 0.02)

local timeSyncUtils = {}

-- First sync uses reliable messages: a slow sync is better than no sync
timeSyncUtils.firstMessageFlags = steam.networkingSockets.flags.ReliableNoNagle + steam.networkingSockets.flags.AppendTimestamp
timeSyncUtils.messageFlags = steam.networkingSockets.flags.UnreliableNoNagle + steam.networkingSockets.flags.AppendTimestamp

function timeSyncUtils.syncClockStart()
  -- Once connected, we’ll keep syncing clocks once every few seconds until a few successful syncs.
  if timeSyncUtils.clockSyncProcess then
    clearInterval(timeSyncUtils.clockSyncProcess)
  end
  timeSyncUtils.maxDelay = math.huge
  timeSyncUtils.curOffset = 0
  timeSyncUtils.syncsLeft = 20
  timeSyncUtils.clockSyncProcess = setInterval(function ()
    if timeSyncUtils.syncsLeft > 0 then
      timeSyncUtils.syncsLeft = timeSyncUtils.syncsLeft - 1
      timeSyncUtils.syncClock(false)
    else
      return clearInterval
    end
  end, 2)
  timeSyncUtils.syncClock(true)
end

function timeSyncUtils.syncClockEnd()
  if timeSyncUtils.clockSyncProcess then
    clearInterval(timeSyncUtils.clockSyncProcess)
    timeSyncUtils.clockSyncProcess = nil
  end
  altonline.configureTimeReference(0)
end

function timeSyncUtils.syncClock(firstSync)
  -- Something akin to NTP. First step: send a request with a time of it being sent (using `.AppendLocalTimestamp` flag). Time
  -- should be as close to the time packet is sent as possible. Note: we’re using `steam.networkingUtils.getLocalTimestamp()`
  -- because this lets us to use `receivedTime` of `steam.networkingSockets.receiveMessagesOnConnection1()`.
  steam.networkingSockets.sendMessageToConnection(connect.handle, 'T', firstSync and timeSyncUtils.firstMessageFlags or timeSyncUtils.messageFlags)
end

function timeSyncUtils.onMessage(data, receivedTime, flags)
  if #data == 8 then
    -- Second step: we got a packet with a single time in it, and we add to it time the packet was received at, and time it was sent back.
    local t1 = string.unpack('I8', data)
    local t2 = receivedTime
    steam.networkingSockets.sendMessageToConnection(connect.handle, 'T'..string.pack('I8I8', t1, t2),
      bit.band(flags, 8) ~= 0 and timeSyncUtils.firstMessageFlags or timeSyncUtils.messageFlags)
    altonline.configureTimeReference(steam.networkingUtils.getLocalTimestamp() / 1e6)
  else
    -- Now we have four times, and can use those to estimate the delay and the time difference between us and the remote client.
    local t1, t2, t3 = string.unpack('I8I8I8', data)
    local t4 = receivedTime
    local delay = t4 - t1 - (t3 - t2)
    local offset = (t2 - t1 + t3 - t4) / 2
    if delay < timeSyncUtils.maxDelay then
      -- General rules are that, when syncing time with the same host, timestamp with lowest delay is the most accurate one.
      altonline.configureTimeReference((steam.networkingUtils.getLocalTimestamp() + offset) / 1e6)
      ac.debug('Time sync/Offset (ms)', (offset - timeSyncUtils.curOffset) / 1e3)
      ac.debug('Time sync/Delay (ms)', delay / 1e3)
      timeSyncUtils.maxDelay = delay
      timeSyncUtils.curOffset = offset
    end
  end
end

local TYPE_CAR_STATE = const(('0'):byte(1))
local TYPE_TIME_SYNC = const(('T'):byte(1))
local TYPE_NEW_LAP = const(('L'):byte(1))
local TYPE_EXTRA_MESSAGE = const(('E'):byte(1))
local timeSynced = false

local function processLapMessage(message)
  local parsed = stringify.binary.tryParse(message)
  if parsed and #parsed == 6 then
    altonline.onLapCompleted(1, {
      lapTime = parsed[1],
      valid = parsed[2],
      cuts = parsed[3],
      lapsCount = parsed[4],
      splits = parsed[5],
      lineCrossTimestamp = parsed[6]
    })
  end
end

ac.onLapCompleted(0, function (carIndex, lapTime, valid, cuts, lapsCount, splits, lapCrossTime)
  if connect.handle == 0 then return end
  steam.networkingSockets.sendMessageToConnection(connect.handle, 'L'..stringify.binary{
    lapTime, valid, cuts, lapsCount, splits, altonline.timeToTimestamp(lapCrossTime)
  }, steam.networkingSockets.flags.ReliableNoNagle)
end)

altonline.onSendingExtraMessage(function (args)
  if connect.handle ~= 0 and (not args.to or args.to == 1) then
    if args.unreliable and not connect.unlimitedConnection
      or args.range and not ac.getCar(1).position:closerToThan(ac.getCar(0).position, args.range) then
      return
    end
    steam.networkingSockets.sendMessageToConnection(connect.handle, 'E'..args.data,
      args.unreliable and steam.networkingSockets.flags.Unreliable or steam.networkingSockets.flags.Reliable)
  end
end)

function script.update()
  if connect.handle == 0 then 
    if timeSynced then
      timeSynced = false
      timeSyncUtils.syncClockEnd()
    end
    return
  end

  if not timeSynced then
    timeSynced = true
    ac.memoryBarrier()
    if connect.roleClient then
      timeSyncUtils.syncClockStart() -- client syncs clock with the host
    end
  end

  -- Physics worker receives all the messages, so it could react to state packet the fastest. Most of the messages
  -- are redirected to the main script in graphics thread.
  local n, msgs = steam.networkingSockets.receiveMessagesOnConnection1(connect.handle)
  for i = 0, n - 1 do
    local msgType = msgs[i].data[0]
    if msgType == TYPE_CAR_STATE then
      local packetPing = altonline.submitPackedState1(1, ffi.string(msgs[i].data + 1, msgs[i].size - 1))
      connect.ping = math.lerp(connect.ping, packetPing or 0, connect.ping == 0 and 1 or 0.05)
    elseif msgType == TYPE_TIME_SYNC then
      timeSyncUtils.onMessage(ffi.string(msgs[i].data + 1, msgs[i].size - 1), msgs[i].receivedTime, msgs[i].flags)
    elseif msgType == TYPE_NEW_LAP then
      processLapMessage(ffi.string(msgs[i].data + 1, msgs[i].size - 1))
    elseif msgType == TYPE_EXTRA_MESSAGE then
      altonline.extraMessageFrom(1, ffi.string(msgs[i].data + 1, msgs[i].size - 1))
    else
      ac.broadcastSharedEvent('mode.p2p1v1.v1', ffi.string(msgs[i].data, msgs[i].size))
    end
  end
end

