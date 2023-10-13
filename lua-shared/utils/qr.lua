--[[
  Simple QR encoder using “AcTools.GamepadServer.exe” plugin (it already has a library for that).

  To use, include with `local qr = require('shared/utils/qr')` and then call `qr.encode('https://…', 'file.jpg', function (err, result) … end)`.
  Alternatively, do not pass callback and instead just use returned value in UI functions (without cache or destination set result will be
  cached across calls).
]]

local qr = {}
local lastIndex = 0
local encodeCache = {}

---Encodes data in a QR code and saves it in a file. 
---@param data string @Text to encode.
---@param destination string? @Destination filename (if not set, temporary filename will be used).
---@param callback fun(err: string?, data: string?) @Result callback (if everything goes well, `data` points to filename).
---@return string @Not a string, but can be used in UI API as an image.
function qr.encode(data, destination, callback)
  if not data then error('Data is required', 2) end

  local compactMode = not destination and not callback
  if compactMode and encodeCache[data] then
    return encodeCache[data]
  end

  if type(destination) == 'function' then
    callback = destination
    destination = nil
  end

  if not destination then
    lastIndex = lastIndex + 1
    destination = ac.getFolder(ac.FolderID.AppDataTemp)..'/accsp_qr_'..tostring(lastIndex)..'.png'
  end

  local filename = ''
  os.runConsoleProcess({ 
    filename = ac.getFolder(ac.FolderID.ExtRoot)..'/internal/plugins/AcTools.GamepadServer.exe',
    environment = {
      GAMEPAD_QR_DATA = data,
      GAMEPAD_QR_FILENAME = destination
    },
    inheritEnvironment = true,
    terminateWithScript = true,
    timeout = 0
  }, function (err, data)
    if err or data.exitCode ~= 0 then
      callback(err or data.stderr:trim(), nil)
      return
    end
    filename = destination
    callback(nil, filename)
  end)

  local ret = setmetatable({}, { __tostring = function() return filename end })
  if compactMode then encodeCache[data] = ret end
  return ret
end

return qr