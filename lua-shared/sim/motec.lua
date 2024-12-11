--[[
  A helper for creating Motec telemetry reports.
]]
---@diagnostic disable

local motec = {}

local writerMt = {
  __call = function (s, value)
    return __util.native("inner.cphys.luaLogger.write", s.name, s.attributes, value * s.multiplier)
  end,
  __index = {
      ---Write a new value to a channel.
      ---@param value number
      ---@return boolean @Returns `false` if logging is not currently available.
      write = function(s, value)
          return __util.native("inner.cphys.luaLogger.write", s.name, s.attributes, value * s.multiplier)
      end,
  },
}

---Creates a new channel in Motec telemetry. Use it from something like a car physics script.
---@param props {name: string, shortName: string?, unit: string?, frequency: 'low'|'medium'|'high'?, decimals: integer?, multiplier: number?}
---@return fun(value: number) @Call returned function each frame to add a new value.
function motec.Writer(props)
  if type(props) ~= 'table' or type(props.name) ~= 'string' then
    error('Props argument has to be a table with name property', 2)
  end
  return setmetatable({
    name = props.name,
    multiplier = props.multiplier or 1,
    attributes = {
      shortName = props.shortName and tostring(props.shortName) or props.name,
      unit = props.unit and tostring(props.unit) or '?',
      frequency = props.frequency == 'low' and 5 or props.frequency == 'high' and 200 or 100,
      decimals = tonumber(props.decimals) or 4,
    }
  }, writerMt)
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

---Create a new telemetry collection helper. Not available to scripts without I/O access.
---@param carIndex integer @0-based car index. Works only for cars that have custom physics active.
function motec.TelemetryCollector(carIndex)
  return setmetatable({ carIndex = carIndex }, collectorMt)
end

return motec