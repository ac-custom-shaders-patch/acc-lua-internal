--[[
  Library for verifying integrity and signing messages using RSA.

  To use, include with `local signing = require('shared/utils/signing')`.
]]
---@diagnostic disable

local signing = {}

---Compute a fingerprint of multiple files. Filenames should be loaded in AC root folder or in AC documents folder. Returned fingerprint
---can contain zeroes, so you might want to do something like
---Base64 encoding (`ac.encodeBase64()`) before passing data further if your exchange protocol is not binary.
---
---Missing files will have a different result from empty files, so the function could also be used to verify a certain file
---does not exist.
---
---Resulting fingerprint is 18 bytes long. Any files opened in the process will remain opened until the session is finished.
---@param files string[]
---@param callback fun(fingerprint: string)
function signing.verify(files, callback)
  __util.native('ac.verifyIntegrity', table.concat(files, '\n'), __util.expectReply(callback))
end

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
---- `'{LastIntegrityCheckBase64}'`: Base64-encoded result of the last `signing.verify()` call (available once `signing.verify()` callback has been called).
---Before signing, format string will be inserted between header and data, but won’t be returned as a part of `header` value. Make sure verifying side
---knows format string and can adjust accordingly.
---Checksummed entries are there so that a remote server could verify a signature without getting access to sensitive data. Actual signature will be 384 bytes long
---and might contain zero bytes, as well as the header (which size may vary, but it will never be less than 128 bytes), so you might want to do something like
---Base64 encoding (`ac.encodeBase64()`) before passing data further if your exchange protocol is not binary.
---
---To verify integrity of a signed message using NodeJS, a function like this can be used:
---```js
---const crypto = require('crypto');
---const verifyCSPSignature = ((store, message, signature) => {
---  if (!store.key) {
---    store.key = crypto.createPublicKey({
---      key: Buffer.from(`MIIBoDANBgkqhkiG9w0BAQEFAAOCAY0AMIIBiAKCAYEAv255WL89kNUX4xn6oWsR6YIASm9ulWqiEmWesuRzQ+LTaaOWeN6/0AKhs7TLQOb2LF9ektX3lptLVCHUpg/RzHcbQPCn/ke7vbX8HMNZUmm5cHUvhx7VdkKjtdIuF7DWnKd81XnK2xxU8+Sh7nBaraCOb4qOw6PkP/DYsd/k1UxXzEOCWsWJ8S+LZ4P6vfcB6+PujuPhXKQ+UzQkhHo7K2wVzoMl0LGFEqby8YVPH39yAk59bQkRkOz8qVMpaPKFYB+3e4rhCbAV3+yHOKlE5QZ5PTr0L2M7mL4SlevopTen6410bFI879jgCC+lEiVLRQJRb25cUYLF2plWfmc7IhuYUyrsOieiU0p8tBLH69HrcRIxgtm22/sE9j9nAeCXYVnG5VWMwox0Pm8QyuedX2y2zRN0XdDhZ7WBIrNDDvuMDTYiB7/3NyMHKGfjZpEboZ1k7L2rRG/Plq+O6i8NBYJezZC84l2FEmMinH3JGPA8pQXYE8WsB7gDVHkHmYL9AgER`, 'base64'),
---      format: 'der',
---      type: 'spki',
---    });
---  }
---  const sign = crypto.createVerify('RSA-SHA1');
---  sign.update(message);
---  return sign.verify(store.key, signature);
---}).bind(null, {});
---
---// Usage example:
---const data = JSON.parse(req.body);
---console.log(verifyCSPSignature(data.message, Buffer.from(data.signature, 'base64'))); // prints `true` if signature is valid.
---```
---@param format string? @Header format. At least 64 random bytes will be added afterwards.
---@param data binary @Binary data to sign.
---@param callback fun(signature: binary, header: binary)
function signing.blob(format, data, callback)
  __util.native('ac.signBlob', format, data, __util.expectReply(callback))
end

return signing