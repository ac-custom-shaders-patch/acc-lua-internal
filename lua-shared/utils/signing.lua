--[[
  Library for signing messages using RSA to check validity of messages.

  To use, include with `local signing = require('shared/utils/signing')`.
]]

local signing = {}

---Signs a piece of data after prepending a header to it. To ensure safety, header will contain random bytes, but you can add extra stuff to it by using 
---optional `format` parameter. Known substitutes:
---- `'{ServerIP}'`: current server IP (empty string if offline).
---- `'{ServerTCPPort}'`: current server TCP port (empty string if offline).
---- `'{ServerSeed}'`: current server seed (empty string if offline).
---- `'{UniqueMachineKey}'`: value returned by `ac.uniqueMachineKey()`.
---- `'{UniqueMachineKeyChecksum}'`: result of `ac.checksumSHA256('LB83XurHhTPhpmTc'..ac.uniqueMachineKey())`.
---- `'{SteamID}'`: Steam ID used online (offline, will be read from “cfg/race.ini”). Not safe from spoofing.
---- `'{SteamIDChecksum}'`: same, but `ac.checksumSHA256('LB83XurHhTPhpmTc'..steamID)`.
---- `'{VerifiedSteamID}'`: Steam ID returned by Steam API (will be an empty string if Steam API is not available or there are traces of spoofing).
---- `'{VerifiedSteamIDChecksum}'`: same, but `ac.checksumSHA256('LB83XurHhTPhpmTc'..verifiedSteamID)`.
---Before signing, format string will be inserted between header and data, but won’t be returned as a part of `header` value. Make sure verifying side
---knows format string and can adjust accordingly.
---Checksummed entries are there so that a remote server could verify a signature without getting access to sensitive data. Actual signature will be 384 bytes long
---and might contain zero bytes, as well as the header (which size may vary, but it will never be less than 128 bytes), so you might want to do something like
---Base64 encoding before passing data further if your exchange protocol is not binary.
---@param format string? @Header format. At least 64 random bytes will be added afterwards.
---@param data binary @Binary data to sign.
---@param callback fun(signature: binary, header: binary)
function signing.blob(format, data, callback)
  __util.native('ac.signBlob', format, data, __util.expectReply(callback))
end

return signing