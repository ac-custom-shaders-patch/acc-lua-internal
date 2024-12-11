--[[
  A very basic library for basic interfacing with App Shelf app. Could be used by scripts without I/O access to offer users to install apps.
  Apps should either be on App Shelf or be properly signed in a certain way to ensure misuse.

  To use, include with `local appShelf = require('shared/utils/appshelf')` and then call `appShelf.offer({id = 'SetupExchange'}, function (err, result) … end)`.
  For a custom app, pass a table instead: `appShelf.offer('SetupExchange', function (err, result) … end)`.

  To prevent spam, secondary calls with the same app ID will be ignored.
]]
---@diagnostic disable

local appShelf = {}

local listener

---Offers user to install a certain app. Parameter `reason` is optional. If specified, will be used after a colon in a sentense, so keep it lowercase. 
---@param data {id: string, reason: string?}|{id: string, name: string, downloadURL: string, reason: string?} @Installation parameters.
---@param callback fun(err: string?)? @Result callback.
function appShelf.offer(data, callback)
  if not data or not data.id then error('Data is required', 2) end
  local installKey = math.randomKey()
  if data.reason then
    data.reason = tostring(data.reason)
    if #data.reason > 200 then error('Reason string is too large', 2) end
  end
  if not listener then
    listener = {}
    ac.onSharedEvent('$SmallTweaks.AppShelf.Install.Result', function (data)
      if type(data) ~= 'table' or type(data.installKey) ~= 'number' then return end
      local cb = listener[data.installKey] 
      if cb then
        listener[data.installKey] = nil
        cb(data.err)
      end
    end)
  end
  listener[installKey] = callback
  ac.broadcastSharedEvent('$SmallTweaks.AppShelf.Install', {
    meta = data,
    installKey = installKey
  })
end

return appShelf