local utils = {}
local settingsListeners = {}

function utils.onSettingsUpdate(callback)
  table.insert(settingsListeners, callback)
end

function utils.raiseSettingsUpdate(data)
  for i = 1, #settingsListeners do
    settingsListeners[i](data)
  end
end

---@param execCallback fun(cb: function)
---@param completionCallback fun(err: string, data: table)
function utils.whenAll(execCallback, completionCallback, dbg)
  local waiting, resultErr, result, ready, nextIndex = 0, nil, {}, false, 1
  try(function () 
    execCallback(function ()
      waiting = waiting + 1
      if dbg then ac.warn(dbg..': '..waiting) end
      local index = nextIndex
      nextIndex = index + 1
      return function (err, data)
        waiting = waiting - 1
        if err then resultErr = resultErr and resultErr..'\n'..err or err end
        if not resultErr then result[index] = data end
        if ready and waiting == 0 then
          local cc = completionCallback
          if cc then
            completionCallback = nil
            cc(resultErr, not resultErr and result or nil)
          end
        end
      end
    end)
    ready = true
    if waiting == 0 then
      local cc = completionCallback
      if cc then
        completionCallback = nil
        cc(resultErr, not resultErr and result or nil)
      end
    end
  end, function (err)
    local cc = completionCallback
    if cc then
      completionCallback = nil
      cc(err, nil)
    end
  end)
end

---@generic T
---@param fn fun(): T
---@return T?
function utils.tryCreate(obj, fn)
  return try(fn, function (err) ac.error(err) end)
end

---@param obj {index: integer}
---@param err string?
function utils.reportError(obj, err)
  if type(err) == 'string' then
    ac.error(err)
  end
end

return utils

