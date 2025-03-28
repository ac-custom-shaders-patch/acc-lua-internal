--[[
  A helper for creating Motec telemetry reports.
]]
---@diagnostic disable

local motec = {}

---@return boolean @Returns `true` if any Motec recording is currently active.
function motec.active()
  return __util.native("inner.cphys.luaLogger.isActiveGen")
end

local collectorMt = {
  __index = {
    ---Start collecting data.
    ---@return boolean @Returns `false` if failed to start or if already started before.
    begin = function(s)
      return __util.native('inner.cphys.luaLogger.begin', s.carIndex)
    end,
    ---Stop collecting data and drop anything already collected.
    ---@return boolean @Returns `false` if failed or if collection wasn’t active to begin with.
    drop = function (s)
      return __util.native('inner.cphys.luaLogger.drop', s.carIndex)
    end,
    ---Stop collecting data and write collected stuff into a file. Another file with a postfix “x” with binary data will be stored next to the main file.
    ---Saves data asyncronously to prevent physics thread from lagging.
    ---@param filename string @Full path to the destination file. Make sure the directory exists.
    ---@param callback fun(err: string, savedChannels: integer) @Callback that will be called once data is saved.
    finishAsync = function(s, filename, callback)
      __util.native('inner.cphys.luaLogger.finishAsync', s.carIndex, filename, callback)
    end,
    ---Checks if data collection is currently active.
    ---@return boolean
    active = function(s)
      return __util.native('inner.cphys.luaLogger.isActive', s.carIndex)
    end,
    ---Returns the time in seconds data collection was active for.
    ---@return number
    time = function(s)
      return __util.native('inner.cphys.luaLogger.getTime', s.carIndex)
    end, 
  }
}

---Create a new telemetry collection helper. Scripts without I/O access can only save telemetry in “Documents/AC/telemetry”.
---@param carIndex integer @0-based car index. Works only for cars that have custom physics active.
function motec.TelemetryCollector(carIndex)
  return setmetatable({ carIndex = carIndex }, collectorMt)
end

return motec