--[[
  Simple library for tracks, apps, online scripts or new modes to play custom ambience audio.
]]
---@diagnostic disable

local ambience = {}

---Register a new ambience. Each script can register up to a dozen of ambiences. Call returned function and pass it `true` to activate ambience,
---or `false` to stop it. Active ambience with highest priority will be used.
---@param filename string
---@param params nil|{volume: number?, priority: number?}
---@return fun(active: boolean)
function ambience.register(filename, params)
  local key = math.randomKey()
  local k = ac.connect({
    ac.StructItem.key('$SmallTweaks.AmbienceAudio.%s' % key),
    active = ac.StructItem.boolean()
  }, false, ac.SharedNamespace.Shared)
  k.active = false
  ac.broadcastSharedEvent('$SmallTweaks.AmbienceAudio', {
    filename = filename,
    volume = params and params.volume or 1,
    priority = params and params.priority or 0,
    conditionKey = key,
  })
  ac.onRelease(function ()
    ac.broadcastSharedEvent('$SmallTweaks.AmbienceAudio', { conditionKey = key })
  end)
  return function(active)
    k.active = not not active
  end
end

return ambience
