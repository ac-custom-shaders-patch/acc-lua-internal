--[[
  Steam Networking API uses Steam Datagram Relay without an option, ignoring all the settings, but I would like
  for clients to be able to establish actual peer-to-peer connection for the lowest latency. To achieve that,
  this module replaces regular Steam Networking API with very similar Game Networking API that doesn’t use SDR at all.
]]

local steam = require('shared/utils/luasteam')
local signing = require('shared/utils/signing')
local promise = require('shared/promise')
local useGNS = true -- changing this one live is not recommended at all, I think different parts of Valve code end up crashing into each other

-- Steam P2P config
---@type SteamNetworkConfig
local p2pConfig = {
  Unencrypted = 2,
  SendTimeSincePreviousPacket = 0,
  SymmetricConnect = 1,
  DualWifi_Enable = not useGNS and 1 or nil,
}

local gns = {}
local initializing = nil ---@type string?

function gns.active()
  return useGNS
end

function gns.config()
  return p2pConfig
end

function gns.preparing()
  return initializing
end

function gns.ready()
  return not useGNS or not initializing
end

function gns.failed()
  return useGNS and initializing and string.endsWith(initializing, '.')
end

local connectPhase = 0

local function connectToNetwork()
  initializing = 'Accessing relay network…'

  -- Because at the moment I don’t really know how much it’d cost to run that relay network, I’m setting up
  -- some limits where only original version of this script can access it. Sorry about that. If I find that
  -- it’s not too expensive, I’ll definitely remove that restriction.
  -- To configure your own service, use:
  -- steam.GNS.networkingUtils.setGlobalConfig{
  --   P2P_Transport_ICE_Enable = 0x7fffffff,
  --   P2P_STUN_ServerList = {'stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302', 'stun:stun.cloudflare.com:3478' },
  --   P2P_TURN_ServerList = 'turn:openrelay.metered.ca:80?transport=udp', -- this one no longer works btw
  --   P2P_TURN_UserList = 'openrelayproject',
  --   P2P_TURN_PassList = 'openrelayproject',
  -- }
  local turnProviderHost = const('https://turn.acstuff.club')
  local curConnectPhase = connectPhase + 1
  local start = os.preciseClock()
  setInterval(function()
    local state = steam.GNS.getSignalingStatus()
    if state and state:startsWith('connected') then
      print('Signaling initialization time: %.2f s' % (os.preciseClock() - start))
      return clearInterval
    end
  end)
  connectPhase = curConnectPhase
  promise.coroutine(function ()
    local signingVerifyPromise = promise.promisify(signing.verify)
    local signingBlobPromise = promise.promisify(signing.blob, 'p')
    local webResolveDNSPromise = promise.promisify(web.resolveDNS)
    local webPostPromise = promise.promisify(web.post, 'e')
  
    local step1Res = promise.all{
      signingVerifyPromise{':self', 'impl_steam_worker.lua'},
      webPostPromise('%s/access' % turnProviderHost, {},
        JSON.stringify{machineKey = ac.encodeBase64(ac.uniqueMachineKey(), true)})
    }:await()
    if connectPhase ~= curConnectPhase then return end

    local step1 = JSON.parse(step1Res[2].body)
    if step1.error then error(step1.error, math.huge) end 
    assert(type(step1.token) == 'string')
    local signed = signingBlobPromise('{LastIntegrityCheckBase64};{UniqueMachineKeyBase64Trimmed};{CSPVersion};{CSPVersionCode};', step1.token):await()
    if connectPhase ~= curConnectPhase then return end

    local step2Res = webPostPromise('%s/access/next' % turnProviderHost, {}, JSON.stringify {
      token = step1.token,
      signature = ac.encodeBase64(signed[1], true) or '',
      header = ac.encodeBase64(signed[2], true) or '',
    }):await()
    if connectPhase ~= curConnectPhase then return end
    
    local step2 = JSON.parse(step2Res.body)
    if step2.error then error(step2.error, math.huge) end
    assert(type(step2.config) == 'table')
    if step2.config.P2P_CSP_Signaling_Service then
      steam.GNS.networkingUtils.setGlobalConfig{
        P2P_CSP_Signaling_Service = step2.config.P2P_CSP_Signaling_Service
      }
    end

    -- Should smooth out GNS initialization (it seems like its DNS lookup might be a bit blocking).
    promise.all(table.map(step2.domains, function (i) return webResolveDNSPromise(i):ok() end)):await()
    if connectPhase ~= curConnectPhase then return end

    steam.GNS.networkingUtils.setGlobalConfig(step2.config)
    initializing = nil
  end):catch(function (err)
    initializing = 'Failed to access network. %s.' % (type(err) == 'string' and err or 'Unknown error')
  end)
end

function gns.tryAgain()
  if gns.failed() then
    connectToNetwork()
  end
end

function gns.init(ownConnectID)
  if not useGNS then return end

  steam.networkingSockets = steam.GNS.networkingSockets
  steam.networkingMessages = steam.GNS.networkingMessages
  steam.networkingUtils = steam.GNS.networkingUtils
  steam.networkingUtils = steam.GNS.networkingUtils

  if ownConnectID then
    steam.GNS.configure('csp.p2p1v1', ownConnectID)
    steam.networkingSockets.connectP2P = steam.GNS.networkingSockets.connectP2PCustomSignaling
    steam.networkingSockets.initAuthentication = function() return 0 end

    -- local printed = {}
    -- steam.GNS.networkingUtils.setDebugOutputFunction('Debug', function(level, msg)
    --   -- if printed[msg] or string.find(msg, 'lock held for ', nil, true) then return end
    --   printed[msg] = true
    --   print('[LuaNetworking]', level, msg)
    -- end)

    connectToNetwork()
  end
end

return gns
