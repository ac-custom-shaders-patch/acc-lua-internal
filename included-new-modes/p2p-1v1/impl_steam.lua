local sim = ac.getSim()
local steam = require('shared/utils/luasteam')
local altonline = require('shared/sim/altonline')
local signing = require('shared/utils/signing')
local utils = require('./utils')
local gns = require('./gns')

-- Settings configurable from CM
local settings = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  DOWNLOAD_SKINS = true,
  FROZEN_DRIVE = false,
  SHARE_SKINS = true,
})

-- Basic state values
local ownCar = ac.getCar(0) or error()
local ownSteamID = steam.user.getSteamID()
local ownTrackID = ac.getTrackFullID('/')
local ownFlags = settings.FROZEN_DRIVE and 'i' or ''
local targetSteamID, targetFlags = utils.decodeSteamID(ac.INIConfig.raceConfig():get('RACE', '__CM_CUSTOM_MODE', '', 2))
if targetSteamID then
  ownFlags = targetFlags
end

local inviteBase = 'csp?mode=p2p-1v1&car=%s&track=%s&param=%s' %
    { string.urlEncode(ownCar:id()), string.urlEncode(ownTrackID), string.urlEncode(utils.encodeSteamID(ownSteamID, ownFlags)) }
local showSteamWarning = steam.extra.isAPIImplementationSuspicious()
utils.setOwnFlags(ownFlags)
gns.init(ownSteamID)

-- Some basic script settings
local stored = ac.storage {
  letFriendsJoin = false,
  lapsCount = 3
}

-- Online config for a couple of extra features (custom motion and such are enabled automatically)
altonline.configure[[
[CUSTOM_COLOR] ALLOW_EVERYWHERE=1
[EXTRA_DATA] CAMBER_TOE_STATE=1
[EXTRA_TWEAKS] JUMP_LIMIT=0.5
[EXTRA_DATA] VR=1
]]

-- A small helper to exchange connection handle with physics worker. Also, stores current connection to the opposing party.
local connect = ac.connect({
  ac.StructItem.key('mode.p2p1v1.v1'),
  handle = ac.StructItem.double(),
  ping = ac.StructItem.double(),
  roleClient = ac.StructItem.boolean(),
  unlimitedConnection = ac.StructItem.boolean(),
})
connect.handle, connect.ping, connect.unlimitedConnection = 0, 0, false

if targetSteamID == tostring(ownSteamID) then
  targetSteamID = nil
  ac.warn('Attempt to connect to own Steam ID, ignored')
end
local hostListenSocket, clientConnection, curLobbyHandle

local function ensureCarsFilterIsSet()
  ensureCarsFilterIsSet = function() end
  utils.getCarsFilterToken(function(err, token)
    if token then
      print('Cars list token: %s' % token)
      inviteBase = inviteBase .. ('&cars=%s' % string.urlEncode('*' .. token))
      if curLobbyHandle then
        steam.matchmaking.setLobbyData(curLobbyHandle, 'cm.invite.race', inviteBase)
      end
    else
      ac.warn('Failed to get cars list token: %s' % err)
    end
  end)
end

local lobbyRequested = false
local curLobbyState = false ---@type 'FriendsOnly'|'Private'|''|nil|false

---@param arg 'leave'|function|nil
local function initLobbyHandle(arg)
  -- Two reasons to use a lobby:
  -- • Much nicer invites (with rich presence, Steam freaks out about launch arguments);
  -- • Users can scan their friends to see if there are visible lobbies they can join.

  if stored.letFriendsJoin or type(arg) == 'function' then lobbyRequested = true end
  if curLobbyHandle == nil and (not hostListenSocket or not lobbyRequested) then return end

  local targetLobbyState = arg ~= 'leave' and (stored.letFriendsJoin and 'FriendsOnly' or 'Private') or false
  if curLobbyState ~= targetLobbyState then
    if curLobbyState == false then
      if not targetLobbyState then return end
      print('Creating lobby: %s' % (targetLobbyState or 'Private'))
      steam.matchmaking.createLobby(targetLobbyState or 'Private', 2, function(args)
        if args and args.steamIDLobby and tostring(args.steamIDLobby) ~= '0' then
          curLobbyHandle = args.steamIDLobby
          ac.store('.csp.p2p1v1.lobby', tostring(curLobbyHandle))

          -- If you’re working on your own lobby logic, please consider adding `csp.mode` so we can filter each other out.
          steam.matchmaking.setLobbyData(curLobbyHandle, 'csp.mode', 'p2p1v1')
          steam.matchmaking.setLobbyData(curLobbyHandle, 'cm.invite.race', inviteBase)
          print('Lobby has been created:', curLobbyHandle)
          ensureCarsFilterIsSet()
          if curLobbyState ~= targetLobbyState then
            initLobbyHandle()
          end
          if type(arg) == 'function' then
            arg()
          end
        else
          ui.toast(ui.Icons.Warning, 'Failed to create Steam lobby: %s' % args.result)
            :button(ui.Icons.Restart, 'Try again', function ()
              curLobbyState = false
              initLobbyHandle()
            end)
        end
      end)
    elseif curLobbyHandle then
      local configured = steam.matchmaking.setLobbyType(curLobbyHandle, targetLobbyState or 'Private')
      steam.matchmaking.setLobbyJoinable(curLobbyHandle, type(targetLobbyState) == 'string')
      print('Re-configuring lobby: %s' % (curLobbyHandle or 'Private'), configured)
    end
    curLobbyState = targetLobbyState
  end
  return curLobbyHandle
end

-- Steam seems to really hate clients recreating lobbies again and again, so we’re trying to
-- reuse, reduce and recycle as much as possible.
local prevLobbyHandle = ac.load('.csp.p2p1v1.lobby')
if prevLobbyHandle and prevLobbyHandle ~= 'nil' then
  curLobbyHandle = prevLobbyHandle
  curLobbyState = ''
  setTimeout(initLobbyHandle, 0.01)
  print('Using previosly set lobby: %s' % curLobbyHandle)
end

local lastInitTime, lastInitAttempt, reconnectTimeout, connectStatus = -1, nil, nil, nil
local establishingConnection

local function shutHostSide()
  if hostListenSocket then
    steam.networkingSockets.closeListenSocket(hostListenSocket)
    hostListenSocket = nil
  end
end

local refreshUI
local avatarLayer = ui.UserIconsLayer(10)

-- Some values that are broadcasted only when changed
local propsPrev
local propsPack = ac.StructItem.build({
  damage = ac.StructItem.array(ac.StructItem.uint8(), 4),
  tyres = ac.StructItem.string(8)
})

local configureControlItems

local function setConnectHandle(handle, roleClient)
  if connect.handle ~= handle then
    connect.roleClient = roleClient == true
    ac.memoryBarrier()
    connect.handle = handle
    propsPrev = nil
    altonline.blockPause(handle ~= 0)
    altonline.blockSessions(handle ~= 0 and roleClient == true)
    if handle == 0 then
      altonline.driverDisconnected(1)
      avatarLayer(1, nil)
      altonline.setPing(0, 0)
      utils.restoreRaceRules()
      if ac.getSim().raceSessionType ~= ac.SessionType.Practice then
        utils.setSessionType(nil, nil)
      end
    else
      local steamID = utils.getConnectionSteamID(handle)
      avatarLayer(1, steam.friends.getMediumFriendAvatar(steamID))
      steam.friends.setPlayedWith(steamID)
    end
    configureControlItems()
  end
  if handle == 0 then
    initLobbyHandle()
  end
  refreshUI()
end

local function closeAndResetConnection(connection, enableLinger)
  if connection and connection ~= 0 then
    if connect.handle == connection then setConnectHandle(0) end
    if establishingConnection == connection then establishingConnection = nil end
    if clientConnection == connection then clientConnection = nil end
    if connection == utils.currentlyHandshakingConnection() then utils.handshakeDriver(nil) end
    steam.networkingSockets.closeConnection(connection, enableLinger)
  end
end

local function steamReconnect(attempt, delay, enableLinger)
  if reconnectTimeout then clearTimeout(reconnectTimeout) end
  local function impl()
    lastInitTime, lastInitAttempt, reconnectTimeout = os.preciseClock(), attempt and (lastInitAttempt or 1) + 1 or nil, nil

    closeAndResetConnection(clientConnection, enableLinger)
    closeAndResetConnection(connect.handle, enableLinger)
    connectStatus = nil

    if clientConnection == 0 then
      clientConnection = nil
    end

    if not targetSteamID then
      if not hostListenSocket then
        hostListenSocket = steam.networkingSockets.createListenSocketP2P(13, gns.config())
      end
      initLobbyHandle()
    elseif steam.extra.parseUint64(targetSteamID) == ownSteamID then
      connectStatus = 'Can’t connect to yourself.'
    else
      clientConnection = steam.networkingSockets.connectP2P(steam.extra.parseUint64(targetSteamID), 13, gns.config())
      print('Trying to connect to ', targetSteamID, clientConnection)
    end
  end
  if delay >= 0 then
    reconnectTimeout = setTimeout(impl, delay)
  else
    impl()
  end
end

-- Not a security thing or anything, just some basic warning in case of a mismatch. For that, four bytes is more than enough.
local ownCarFingerprint, ownTrackFingerprint
local function computeContentFingerprints()
  -- We have to do this later for `{LastIntegrityCheckBase64}` to work properly. In the future, would be nice to
  -- think of a better approach.
  signing.verify({':car'}, function (r)
    ownCarFingerprint = tonumber(bit.band(ac.checksumXXH(r), 0xffffffff))
  end)
  signing.verify({':track'}, function (r)
    ownTrackFingerprint = tonumber(bit.band(ac.checksumXXH(r), 0xffffffff))
  end)
end

setInterval(function ()
  connectStatus = gns.preparing()
  if not connectStatus then
    computeContentFingerprints()
    steamReconnect(false, -1)
    return clearInterval
  end
end)
steam.networkingSockets.initAuthentication()

avatarLayer(0, steam.friends.getMediumFriendAvatar(ownSteamID))
local ownName = steam.friends.getPersonaName()
physics.setDriverName(ownName)
utils.setLicensePlate(0, ownName, ac.getDriverNationCode(0))

local hideLobbiesAtLaunch = false
local function showFriendsList()
  return connect.handle == 0 and not utils.currentlyHandshakingConnection() and not hideLobbiesAtLaunch
end

local lobbies = utils.lobbyMonitor(ownSteamID, showFriendsList,
  function () return type(curLobbyHandle) == 'string' and curLobbyHandle or nil end, function ()
    if refreshUI then refreshUI() end
    hideLobbiesAtLaunch = false
  end)

if targetSteamID then
  lobbies.addInvite({
    lobbyID = ':launch',
    friendID = steam.extra.parseUint64(targetSteamID),
    inviteIndex = utils.nextInviteIndex()
  })
  hideLobbiesAtLaunch = true
end

local addedUI
refreshUI = function()
  if addedUI then
    addedUI()
    addedUI = nil
  end
  if connect.handle ~= 0 then return end
  addedUI = ac.addMainMenuSettings(function()
    if not clientConnection and not connectStatus then
      ui.offsetCursorY(5)
      ui.pushAlignment()
      ui.dummy(14)
      ui.drawLoadingSpinner(ui.itemRect())
      ui.sameLine(0, 8)
      ui.text('Waiting for another driver to connect…')
      ui.popAlignment()
      ui.offsetCursorY(11)

      local w = math.round((ui.availableSpaceX() - 40) / 3)
      ui.beginGroup(w)
      
      ensureCarsFilterIsSet()
      ui.setNextItemIcon(ui.Icons.Copy)
      if ui.button('Copy invite link', vec2(-22, 0)) then
        ac.setClipboardText('https://acstuff.club/s/q:race/%s' % inviteBase)
        ui.toast(ui.Icons.Copy, 'Invite link copied to clipboard')
      end
      if ui.itemHovered() then
        ui.setTooltip('Send this invite link via Discord, Steam or something like that.\n\nNote: for any of these options to work, both you and your friend have to own a copy of Assetto Corsa on Steam.')
      end

      ui.sameLine(0, 0)
      if ui.button('\t', vec2(-0.1, 0)) then
        utils.parseInviteUrl(ui.getClipboardText(), function (err, entry)
          if err then
            ui.toast(ui.Icons.Warning, err)
          elseif entry then
            lobbies.addInvite(entry)
            targetSteamID = tostring(entry.friendID)
            steamReconnect(false, 0)
          end
        end)
      end
      ui.addIcon(ui.Icons.Paste, 14, 0.5, nil, 0)
      if ui.itemHovered() then
        ui.setTooltip('If somebody sent you an invite link to one of those P2P 1v1 sessions on the same track, copy the link and press this button to join without restarting the race.')
      end

      ui.endGroup()
      ui.sameLine(0, 20)
      local sepCol = ui.styleColor(ui.StyleColor.Separator)
      ui.drawSimpleLine(ui.getCursor() - vec2(10, 4), ui.getCursor() + vec2(-10, 28), sepCol, 1)
      ui.beginGroup(w)

      ui.setNextItemIcon(ui.Icons.Steam)
      if ui.button('Invite via Steam', vec2(-0.1, 0), (curLobbyHandle or not lobbyRequested) and 0 or ui.ButtonFlags.Disabled) then
        if not curLobbyHandle then
          initLobbyHandle(function ()
            steam.friends.activateGameOverlayInviteDialog(curLobbyHandle)
          end)
        elseif type(curLobbyHandle) == 'string' then
          steam.friends.activateGameOverlayInviteDialog(curLobbyHandle)
        end
      end
      if ui.itemHovered() then
        ui.setTooltip('Send an invite via Steam to one of your Steam friends.\n\nFor it to work, the recipient has to either:\n• Configure “Full integration” for Steam in Content Manager.\n• Or, enable regular Steam integration in Content Manager, and have Content Manager running.\n• Or, have a race launched with the same mode and on the same track.')
      end

      ui.endGroup()
      ui.sameLine(0, 20)
      ui.drawSimpleLine(ui.getCursor() - vec2(10, 4), ui.getCursor() + vec2(-10, 28), sepCol, 1)
      ui.beginGroup(-0.1)

      local recentInit = os.preciseClock() - lastInitTime < 1
      if recentInit then ui.pushDisabled() end
      if ui.checkbox('Let Steam friends join', stored.letFriendsJoin) then
        stored.letFriendsJoin = not stored.letFriendsJoin
        initLobbyHandle()
      end
      if recentInit then ui.popDisabled() end
      if ui.itemHovered() then
        ui.setTooltip(
          'With this option, your Steam friends will be able to see you racing and join you from this menu, or from Steam messages or your profile page (last two options require enabled Steam integration in Content Manager).')
      end

      ui.endGroup()
    else
      ui.pushAlignment(false, 0.5)
      ui.pushAlignment(true, 0.1)
      if not connectStatus or not string.endsWith(connectStatus, '.') then
        ui.dummy(14)
        ui.drawLoadingSpinner(ui.itemRect())
        ui.sameLine(0, 8)
      end
      utils.textWithUserID(connectStatus
        or lastInitAttempt and 'Connecting to {STU:%s} (attempt %d)…' % {targetSteamID or '', lastInitAttempt}
        or ('Connecting to {STU:%s}…' % (targetSteamID or '')))
      ui.popAlignment()
      ui.popAlignment()

      ui.setCursorY(120 - 32)
      ui.setNextItemIcon(ui.Icons.Constellation)
      if ui.button((targetSteamID and gns.ready()) and 'Become a host' or 'Try again', vec2(-0.1, 0),
          (gns.ready() or gns.failed()) and 0 or ui.ButtonFlags.Disabled) then
        print('Try again', {['gns.ready()'] = gns.ready(), targetSteamID = targetSteamID, connectStatus = connectStatus})
        if not gns.ready() then
          gns.tryAgain()
        else
          if hideLobbiesAtLaunch then
            hideLobbiesAtLaunch = false
            refreshUI()
          end
          targetSteamID = nil
          connectStatus = nil
          steamReconnect(false, 0)
        end
      end
      if ui.itemHovered() then
        ui.setTooltip(
          'If the invite you used to get here doesn’t seem to be working, press this button and invite your friend instead')
      end
    end
    local lobbiesList = lobbies.getList()
    if #lobbiesList > 0 then
      ui.setCursorY(120)
      ui.separator()
      ui.text('Join:')
      ui.childWindow('##friends', vec2(-0.1, -0.1), false, bit.bor(ui.WindowFlags.HorizontalScrollbar, ui.WindowFlags.ThinScrollbar), function()
        for i = 1, #lobbiesList do
          local e = lobbiesList[i]
          if not e then break end
          local friendInfo = utils.getFriendInfo(e.friendID)
          local isSelected, isNotAvailable, trackSwitch = tostring(e.friendID) == targetSteamID, e.isNotAvailable, e.trackID and ownTrackID ~= e.trackID
          ui.pushID(i)
          if isNotAvailable then ui.pushDisabled() end
          local clicked = ui.button('', vec2(220, 66))
          local p1, p2 = ui.itemRect()
          if isSelected then ui.drawRect(p1 + 1, p2 - 1, rgbm.colors.lime, 0, 0, 2) end
          ui.setNextTextBold()
          ui.drawTextClipped(friendInfo.name, p1 + vec2(66, 8), p2, nil, vec2(), true)
          ui.pushFont(ui.Font.Small)
          if e.inviteIndex then
            ui.drawTextClipped('Invite', p1 + vec2(66, 26), p2, rgbm.colors.lime, vec2(), true)
          else
            ui.drawTextClipped('Friend online', p1 + vec2(66, 26), p2, nil, vec2(), true)
          end
          if e.trackID and trackSwitch then
            ui.drawTextClipped('Different track: %s' % ac.getTrackNameByID(e.trackID), p1 + vec2(66, 42), p2, rgbm.colors.orange, vec2(), true)
          elseif e.raceFlags ~= ownFlags then
            ui.drawTextClipped(utils.getConfigurationMismatchMessage(ownFlags, e.raceFlags), p1 + vec2(66, 42), p2, rgbm.colors.orange, vec2(), true)
          elseif e.isNotAvailable == 'checkingOwnCar' then
            local p = p1 + vec2(66, 42)
            ui.drawLoadingSpinner(p, p + 12)
            p.x = p.x + 16
            ui.drawTextClipped('Checking car…', p, p2, nil, vec2(), true)
          elseif e.isNotAvailable == 'ownCar' then
            ui.drawTextClipped('Can’t join with %s' % ac.getCarName(0), p1 + vec2(66, 42), p2, rgbm.colors.orange, vec2(), true)
          elseif e.carID then
            local p = p1 + vec2(66, 42)
            local badgeFilename = utils.getCarBadge(e.carID)
            if badgeFilename then
              ui.drawImage(badgeFilename, p, p + 12)
              p.x = p.x + 16
            end
            ui.drawTextClipped(ac.getCarNameByID(e.carID), p, p2, e.isNotAvailable == 'car' and rgbm.colors.orange or nil, vec2(), true)
          end
          ui.popFont()
          ui.drawImage(friendInfo.avatar, p1 + 8, p1 + 58)
          if isNotAvailable then ui.popDisabled() end
          ui.popID()
          ui.sameLine(0, 20)
          if ui.itemHovered() then
            utils.steamFriendItemBehavior(e.friendID, function ()
              if isNotAvailable then
                ui.separator()
                ui.icon(ui.Icons.Warning, 16, rgbm.colors.orange)
                ui.sameLine(0, 4)
                ui.text(isNotAvailable == 'ownCar' and '%s doesn’t have your car installed' % friendInfo.name
                  or isNotAvailable == 'checkingOwnCar' and 'Checking if your car would work…'
                  or isNotAvailable == 'closed' and 'Closed lobby'
                  or 'You don’t have a %s required for this race' % isNotAvailable)
              elseif trackSwitch then
                ui.separator()
                ui.icon(ui.Icons.Restart, 16, rgbm.colors.white)
                ui.sameLine(0, 4)
                ui.text('To join, you would have to change the track')
              elseif e.raceFlags ~= ownFlags then
                ui.separator()
                ui.icon(ui.Icons.Restart, 16, rgbm.colors.white)
                ui.sameLine(0, 4)
                ui.text('To join, you would have to restart the race to sync configuration')
              end
            end)
          end
          if clicked and not isNotAvailable then
            if trackSwitch then
              ui.modalPopup('Switch track?', 'To join, you have to reload onto a different track. Reload now?', 'Reload', nil, ui.Icons.Restart, nil, function (okPressed)
                if okPressed then
                  local s = e.trackID:split('/', 2, false, false)
                  ac.restartAssettoCorsa('[RACE]\nTRACK=%s\nCONFIG_TRACK=%s\n__CM_CUSTOM_MODE=p2p-1v1,%s' % {s[1], s[2] or '', utils.encodeSteamID(e.friendID, e.raceFlags)})
                end
              end)
            elseif e.raceFlags ~= ownFlags then
              ui.modalPopup('Restart the race?', 'To join, you have to use the same configuration, and for that, you would need to reload the race. Reload now?', 'Reload', nil, ui.Icons.Restart, nil, function (okPressed)
                if okPressed then
                  local s = e.trackID:split('/', 2, false, false)
                  ac.restartAssettoCorsa('[RACE]\n__CM_CUSTOM_MODE=p2p-1v1,%s' % {utils.encodeSteamID(e.friendID, e.raceFlags)})
                end
              end)
            else
              targetSteamID = tostring(e.friendID)
              connectStatus = nil
              steamReconnect(false, 0)
            end
          end
        end
      end)
    end
    if showSteamWarning then
      ui.setCursorY(ui.windowHeight() - 100)
      ui.separator()
      ui.offsetCursor(vec2(0, 14))
      ui.image(ui.Icons.Warning, 32)
      ui.sameLine(0, 12)
      ui.offsetCursorY(-14)
      ui.beginGroup()
      ui.header('Warning')
      ui.textWrapped('It seems like your Steam DLL (“steam_api64.dll”) in Assetto Corsa folder is not the original one. Because of that, this mode might not function correctly. Verifying integrity of Assetto Corsa in Steam should help.')
      ui.setNextItemIcon(ui.Icons.Repair)
      if ui.button('Close Assetto Corsa & verify integrity', vec2(-0.1, 0)) then
        os.openURL('steam://validate/244210')
        setTimeout(function ()
          ac.shutdownAssettoCorsa()
        end, 0.1)
      end
      ui.endGroup()
    end
  end, nil, 120 + (showFriendsList() and #lobbies.getList() > 0 and 110 or 0) + (showSteamWarning and 100 or 0))
end
refreshUI()

---All of our packets have a character in front specifying the type of a packet.
---@param msg string
local function processMessage(msg)
  local t = msg:byte(1, 1)
  if t == const(('c'):byte(1, 1)) then
    altonline.chatMessageFrom(1, msg:sub(2))
  elseif t == const(('p'):byte(1, 1)) then
    ac.fillStructWithBytes(propsPack, msg:sub(2))
    altonline.setDamage(1, { propsPack.damage[0], propsPack.damage[1], propsPack.damage[2], propsPack.damage[3] })
    altonline.setTyres(1, propsPack.tyres)
  elseif t == const(('g'):byte(1, 1)) then
    local ownPing = string.unpack('xH', msg)
    altonline.setPing(0, ownPing)
  elseif t == const(('w'):byte(1, 1)) then
    utils.unpackConditions(msg:sub(2))
  elseif t == const(('R'):byte(1, 1)) then
    ac.setMessage('Assists changed', '%s has edited assist settings' % ac.getDriverName(1))
    utils.applyRaceRules(stringify.binary.tryParse(msg:sub(2)))
  elseif t == const(('S'):byte(1, 1)) then
    utils.parseSessionMessage(stringify.binary.tryParse(msg:sub(2)))
  elseif t == const(('x'):byte(1, 1)) then
    if connect.handle ~= 0 then
      local w = msg:sub(2, 2)
      ui.toast(ui.Icons.Steam, w == 'd'
        and '%s has disconnected' % ac.getDriverName(1)
        or '%s has left the race' % ac.getDriverName(1))
    end
    targetSteamID = nil
    steamReconnect(false, -1)
  end
end

local function quickDisconnect()
  steam.networkingSockets.sendMessageToConnection(connect.handle, 'xd', steam.networkingSockets.flags.Reliable)
  targetSteamID = nil
  steamReconnect(false, 0, true)
end

local prevItems = {} ---@type fun()[]|nil

configureControlItems = function()
  if prevItems then table.forEach(prevItems, function (item) item() end) end
  prevItems = {}
  if connect.handle == 0 then return end
  table.insert(prevItems, ui.registerOnlineExtra(ui.Icons.Exit,
    {title = 'Disconnect', tooltip = 'Leave the race and go back to looking for a player to connect to (“/disconnect”)'}, nil,
    function ()
      ui.text('Disconnect?')
      if utils.modalButtons('Disconnect', ui.Icons.Exit) then
        quickDisconnect()
      end
      return false
    end, nil, ui.OnlineExtraFlags.None))
  if not connect.roleClient then
    table.insert(prevItems, ac.getSim().raceSessionType == ac.SessionType.Practice and ui.registerOnlineExtra(ui.Icons.Finish,
      {title = 'Start a race', tooltip = 'Teleport to the starting line and start a new race session (“/race <laps>”)'}, nil,
      function ()
        ui.text('Start a new race?')
        if not ac.getSim().isTrackOpen then
          stored.lapsCount = math.clamp(math.round(ui.slider('##lapsCount', stored.lapsCount, 1, 50, 'Laps: %.0f', 2)), 1, 1000)
        end
        if utils.modalButtons('Start', ui.Icons.Start) then
          utils.setSessionType(connect.handle, stored.lapsCount)
        end
        return false
      end, nil, ui.OnlineExtraFlags.None) or ui.registerOnlineExtra(ui.Icons.Directions, 
      {title = 'Stop the race', tooltip = 'Terminate the race and switch back to practice (“/practice”)'}, nil,
      function ()
        ui.text('Stop the race?')
        if utils.modalButtons('Stop', ui.Icons.Cancel) then
          utils.setSessionType(connect.handle, nil)
        end
        return false
      end, nil, ui.OnlineExtraFlags.None))
  end
end

ac.onSessionStart(function (sessionIndex, restarted)
  if restarted and not utils.recentSessionChangeTookPlace() then
    if connect.handle ~= 0 and connect.roleClient then
      -- If a random restart triggered by something like clicking on the restart button in race results,
      -- disconnect so we can properly start again.
      quickDisconnect()
      ac.tryToOpenRaceMenu('info')
    elseif (connect.handle == 0 or not connect.roleClient) and ac.getSim().raceSessionType ~= ac.SessionType.Practice then
      utils.setSessionType(connect.handle, stored.lapsCount)
    end
  end
  configureControlItems()
end)

altonline.onSendingChatMessage(function(msg)
  if connect.handle == 0 then
    altonline.failedToSendChatMessage(msg)
    return
  end
  if msg:sub(1, 1) == '/' then
    if msg == '/disconnect' then
      quickDisconnect()
    end
    if not connect.roleClient then
      if msg == '/restart' then
        ac.tryToRestartSession()
      end
      if msg == '/practice' and ac.getSim().raceSessionType ~= ac.SessionType.Practice then
        utils.setSessionType(connect.handle, nil)
      end
      local i, _, lapsCount = msg:regfind('/race(?: (\\d+))?')
      if i then
        stored.lapsCount = tonumber(lapsCount) or 1
        utils.setSessionType(connect.handle, stored.lapsCount)
      end
    end
    return
  end
  steam.networkingSockets.sendMessageToConnection(connect.handle, 'c' .. msg, steam.networkingSockets.flags.Reliable)
  altonline.chatMessageFrom(0, msg)
end)

-- Physics worker is the thing which will collect all the packets. This way, it can respond to physics state
-- the fastest. Other packets will be sent here using a basic shared event.
ac.onSharedEvent('mode.p2p1v1.v1', function(data)
  if type(data) == 'string' then processMessage(data) end
end)

physics.startPhysicsWorker('impl_steam_worker', function()
  ac.warn('Physics worker is finished')
end)

local trackObjectsSeed, trackObjectsTime = math.randomKey(), os.preciseClock()
ac.resetDynamicTrackObjects(trackObjectsSeed, 0)

steam.networkingSockets.onConnectionChanged(function (data)
  print('Connection changed:', data.state)
  if data.state == 'Connecting' then
    if data.connection ~= clientConnection then
      if connect.handle ~= 0 or utils.currentlyHandshakingConnection() then
        print('Discarding secondary connection: %s…' % (connect.handle == 0 and 'doing a handshake' or 'already connected'))
        steam.networkingSockets.closeConnection(data.connection)
      else
        print('Accepting a connection…')
        connectStatus = 'Establishing a connection with {CON:%s}…' % data.connection
        closeAndResetConnection(establishingConnection) -- this way, we can handle the case where both clients are trying to connect to each other at the same time
        establishingConnection = data.connection
        steam.networkingSockets.acceptConnection(data.connection)
      end
    end
  elseif data.state == 'FindingRoute' then
    connectStatus = 'Finding optimal route to {CON:%s}…' % data.connection
  elseif data.state == 'Connected' then
    connectStatus = 'Exchanging warm welcomes with {CON:%s}…' % data.connection
    initLobbyHandle('leave')
    utils.handshakeDriver(data.connection, {
      name = ownCar:driverName(),
      nation = ownCar:driverNationCode(),
      car = ownCar:id(),
      skin = ownCar:skin(),
      fingerprint = {ownCar.extendedPhysics, ownCarFingerprint, ownTrackFingerprint},
      rules = data.connection ~= clientConnection and {utils.collectRaceRules(), trackObjectsSeed, os.preciseClock() - trackObjectsTime} or nil,
      laps = altonline.packLaps(0)
    }, { downloadSkins = settings.DOWNLOAD_SKINS, shareSkins = settings.SHARE_SKINS }, function(err, handshake, args)
      refreshUI()
      if err then
        connectStatus = '%s.' % err or 'Couldn’t establish a connection with {CON:%s}.' % data.connection 
        initLobbyHandle()
        return
      end

      local connectedAsClient = data.connection == clientConnection

      -- For clients to be in sync, one way is to set a time reference. The simplest way is to just use NTP to get accurate time
      -- on both clients, and use that as time reference:
      -- altonline.configureTimeReference({ 'time.cloudflare.com', 'time.windows.com', 'time.apple.com',
      --   '0.pool.ntp.org', '1.pool.ntp.org', '2.pool.ntp.org', '3.pool.ntp.org' })
      -- This script, however, instead uses NTP-like approach to get host time on a client. See `timeSyncUtils` in physics worker
      -- for details (it doesn’t have to be there, but why not, it’s closer to receiving messages).

      connectStatus = 'Connected!'
      if handshake.rules then
        utils.applyRaceRules(handshake.rules[1])
        ac.resetDynamicTrackObjects(handshake.rules[2], handshake.rules[3])
      end
      altonline.driverConnected(1, {
        driverName = handshake.name,
        driverNation = handshake.nation,
        carID = handshake.car,
        carSkinID = handshake.skin,
        temporary = args.itemHasBeenInstalled,
        carLoadedCallback = function ()
          utils.setLicensePlate(1, handshake.name, handshake.nation)
        end
      })

      local integrityWarnings = {}
      if ownCar:id() == handshake.car then
        if handshake.fingerprint[2] ~= ownCarFingerprint then
          table.insert(integrityWarnings, 'Car files aren’t an exact match')
        elseif handshake.fingerprint[1] ~= ownCar.extendedPhysics then
          table.insert(integrityWarnings, (ownCar.extendedPhysics and '%s doesn’t use extended car physics' or '%s uses extended car physics') % handshake.name)
        end
      end
      if handshake.fingerprint[3] ~= ownTrackFingerprint then
        table.insert(integrityWarnings, 'Track files differ')
      end
      local showIntegityWarning = #integrityWarnings ~= 0 
        and 'Physics might not be perfectly synced:\n• %s.' % table.concat(integrityWarnings, '.\n• ')
        or nil
      if showIntegityWarning then
        setTimeout(function ()
          altonline.serverChatMessage(showIntegityWarning)  
        end)
      end

      if handshake.laps then
        altonline.unpackLaps(1, handshake.laps)
      end
      if connectedAsClient then
        shutHostSide()
      end
      altonline.setPitIndex(0, connectedAsClient and 1 or 0, true)
      setConnectHandle(data.connection, connectedAsClient)
    end)
    hideLobbiesAtLaunch = false
    refreshUI()
  elseif data.state == 'ClosedByPeer' or data.state == 'ProblemDetectedLocally' then
    local handshakeFailed = connectStatus and connectStatus:endsWith('.')
    if clientConnection == data.connection then
      clientConnection = nil
      if not handshakeFailed then
        print('Closed connection: %s' % (connect.handle == data.connection))
        connectStatus = connect.handle == data.connection
          and 'Connection terminated, going to try and reconnect…'
          or targetSteamID
            and 'Failed to connect, next attempt to connect to {STU:%s} in a bit…' % targetSteamID 
            or 'Failed to connect, next attempt to connect in a bit…'
        steamReconnect(connect.handle == 0, (lastInitAttempt or 1) > 10 and 7 or 3)
      end
    elseif not handshakeFailed then
      connectStatus = nil
    end
    if connect.handle == data.connection then 
      setConnectHandle(0)
    end
    closeAndResetConnection(data.connection)
  end
end)

do
  -- Host broadcasts weather and time
  local prevSyncedTime = math.huge
  local prevConditionsClock = -1
  local curConditions = ac.ConditionsSet()
  local prevConditions, prevTimeMult = nil, 0
  setInterval(function()
    if connect.handle == 0 or connect.roleClient then
      prevSyncedTime, prevConditionsClock = math.huge, -1
      return
    end
    ac.getConditionsSetTo(curConditions)
    local timePassed = os.preciseClock() - prevConditionsClock
    local curTime = sim.timestamp - sim.timePhotoModeOffset
    local majorChange = math.abs(curTime - (prevSyncedTime + timePassed * prevTimeMult)) > 10
        or prevConditions and utils.conditionsAreDifferent(curConditions, prevConditions)
    if timePassed > (majorChange and 0.1 or 5) then
      local packed
      packed, prevConditions, prevTimeMult = utils.packConditions()
      steam.networkingSockets.sendMessageToConnection(connect.handle, 'w' .. packed, steam.networkingSockets.flags.Unreliable)
      prevSyncedTime = curTime
      prevConditionsClock = os.preciseClock()
    end
  end, 0.1)
end

ac.onAssistsChanged(function ()
  if connect.handle == 0 or connect.roleClient then return end
  setTimeout(function ()
    steam.networkingSockets.sendMessageToConnection(connect.handle, 'R' .. stringify.binary(utils.collectRaceRules()),
      steam.networkingSockets.flags.Reliable)
  end, 0.1, 'updatingRules')
end)

-- Rarely changing state:
setInterval(function()
  for i = 0, 3 do propsPack.damage[i] = ownCar.damage[i] end
  propsPack.tyres = ac.getTyresName(0)
  local s = ac.structBytes(propsPack)
  if s ~= propsPrev then
    propsPrev = s
    steam.networkingSockets.sendMessageToConnection(connect.handle, 'p' .. s, steam.networkingSockets.flags.Reliable)
  end
  connect.unlimitedConnection = connect.handle ~= 0 and gns.active()
    and bit.band(steam.networkingSockets.getConnectionFlags(connect.handle) or 0, 8 --[[ k_nSteamNetworkConnectionInfoFlags_Fast ]]) ~= 0
  if __monitored then
    local flags = steam.networkingSockets.getConnectionFlags(connect.handle) or 0
    ac.debug('Connection', bit.band(flags, 8) ~= 0 and 'direct' or bit.band(flags, 16) ~= 0 and 'relayed' or '?')
    ac.debug('Connection info', {steam.networkingSockets.getConnectionInfo(connect.handle)})
    ac.debug('Detailed status', steam.networkingSockets.getDetailedConnectionStatus(connect.handle))
    if gns.active() then
      ac.debug('Signaling', steam.GNS.getSignalingStatus())
    end

    -- To make sure conditions are synced correctly:
    ac.debug('Current time', os.dateGlobal('%Y-%m-%d %H:%M:%S', sim.timestamp) .. ' (x' .. sim.timeMultiplier .. ')')
    ac.debug('Heading angle', ac.getRealTrackHeadingAngle())
    ac.debug('Coordinates', ac.getTrackCoordinatesDeg())
    ac.debug('Timezone', ac.getTimeZoneOffset())
  end
end, 0.05)

-- Once every two seconds, we can send an optional packet to the opposing party with the delay we’ve measured for them.
setInterval(function()
  if connect.handle ~= 0 and connect.ping ~= 0 then
    steam.networkingSockets.sendMessageToConnection(connect.handle, 'g' .. string.pack('H', math.clamp(connect.ping, 0, 999)),
      steam.networkingSockets.flags.Unreliable)
  end
end, 2)

ac.onRelease(function()
  local handshake = utils.currentlyHandshakingConnection()
  if handshake then steam.networkingSockets.closeConnection(handshake) end
  if connect.handle ~= 0 then
    steam.networkingSockets.sendMessageToConnection(connect.handle, 'xe', steam.networkingSockets.flags.Reliable)
    steam.networkingSockets.closeConnection(connect.handle, true)
    altonline.driverDisconnected(1) 
  end
  if hostListenSocket then steam.networkingSockets.closeListenSocket(hostListenSocket) end
  if clientConnection and connect.handle ~= clientConnection then steam.networkingSockets.closeConnection(clientConnection) end
  if curLobbyHandle then
    -- steam.matchmaking.leaveLobby(curLobbyHandle)
  end
  physics.setAssists{ editable = true }
  utils.setSessionType(nil, nil)
  hostListenSocket, clientConnection, curLobbyHandle, connect.handle = nil, nil, nil, 0
end)
