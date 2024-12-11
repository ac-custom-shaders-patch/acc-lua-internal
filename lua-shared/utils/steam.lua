--[[
  Access to Steam API. Available to scripts with I/O access or online scripts only, others will raise an error. Also raises an error 
  if failed to get access to the Steam API.
]]
---@diagnostic disable

---Steam API namespace.
local steam = {
  ---See <https://partner.steamgames.com/doc/api/ISteamFriends>.
  friends = {},

  ---See <https://partner.steamgames.com/doc/api/ISteamUser>.
  user = {},

  ---See <https://partner.steamgames.com/doc/api/ISteamUtils>.
  utils = {},
}

---@return string
function steam.friends.getPersonaName() return __util.native('lib.steam', 'friends', 'GetPersonaName') end

---@return integer
function steam.friends.getPersonaState() return __util.native('lib.steam', 'friends', 'GetPersonaState') end

---@param flags integer? @Refers to EFriendFlags.
---@return integer
function steam.friends.getFriendCount(flags) return __util.native('lib.steam', 'friends', 'GetFriendCount', flags) end

---@param index integer @0-based index.
---@param flags integer? @Refers to EFriendFlags, should be the same as in `.getFriendCount()` call.
---@return string @Returns Steam ID.
function steam.friends.getFriendByIndex(index, flags) return __util.native('lib.steam', 'friends', 'GetFriendByIndex', index, flags) end

---@param id string @Steam ID.
---@return string
function steam.friends.getFriendPersonaName(id) return __util.native('lib.steam', 'friends', 'GetFriendPersonaName', id) end

---@param id string @Steam ID.
---@return string
function steam.friends.getFriendPersonaState(id) return __util.native('lib.steam', 'friends', 'GetFriendPersonaState', id) end

---@param id string @Steam ID.
---@param index integer @0-based index of an old name.
---@return string? @Returns `nil` if there is no such name.
function steam.friends.getFriendPersonaNameHistory(id, index) return __util.native('lib.steam', 'friends', 'GetFriendPersonaNameHistory', id, index) end

---@param id string @Steam ID.
---@return string
function steam.friends.getFriendSteamLevel(id) return __util.native('lib.steam', 'friends', 'GetFriendSteamLevel', id) end

---@param id string @Steam ID.
---@param requireNameOnly boolean @Retrieve the Persona name only (`true`)? Or both the name and the avatar (`false`)?
---@return boolean
function steam.friends.requestUserInformation(id, requireNameOnly) return __util.native('lib.steam', 'friends', 'RequestUserInformation', id, requireNameOnly) end

---@param id string @Steam ID.
---@return false|ui.ImageSource? @Returns `false` if image is currently loaded, or `nil` if image is not set.
function steam.friends.getSmallFriendAvatar(id) return __util.native('lib.steam', 'friends', 'GetSmallFriendAvatar', id) end

---@param id string @Steam ID.
---@return false|ui.ImageSource? @Returns `false` if image is currently loaded, or `nil` if image is not set.
function steam.friends.getMediumFriendAvatar(id) return __util.native('lib.steam', 'friends', 'GetMediumFriendAvatar', id) end

---@param id string @Steam ID.
---@return false|ui.ImageSource? @Returns `false` if image is currently loaded, or `nil` if image is not set.
function steam.friends.getLargeFriendAvatar(id) return __util.native('lib.steam', 'friends', 'GetLargeFriendAvatar', id) end

-- ---@param key string
-- ---@param value string
-- ---@return boolean
-- function steam.friends.setRichPresence(key, value) return __util.native('lib.steam', 'friends', 'SetRichPresence', key, value) end

-- ---@param id string @Steam ID.
-- ---@param key string
-- ---@return boolean
-- function steam.friends.getFriendRichPresence(id, key) return __util.native('lib.steam', 'friends', 'GetFriendRichPresence', id, key) end

---@return string
function steam.user.getSteamID() return __util.native('lib.steam', 'user', 'GetSteamID') end

---@return integer
function steam.user.getPlayerSteamLevel() return __util.native('lib.steam', 'user', 'GetPlayerSteamLevel') end

---@return string|nil @Actual ticket. Returns `nil` if ticket is not available.
---@return string|nil @Token for cancelling ticket when it’s no longer needed. Returns `nil` if ticket is not available.
function steam.user.getAuthSessionTicket() return __util.native('lib.steam', 'user', 'GetAuthSessionTicket') end

---@param handle string @Second value returned from `steam.user.getAuthSessionTicket()`.
function steam.user.cancelAuthTicket(handle) return __util.native('lib.steam', 'user', 'CancelAuthTicket', handle) end

---@return boolean
function steam.utils.isOverlayEnabled() return __util.native('lib.steam', 'utils', 'IsOverlayEnabled') end

return steam
