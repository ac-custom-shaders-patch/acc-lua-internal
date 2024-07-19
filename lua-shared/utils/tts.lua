--[[
  A small text-to-speech library which uses Microsoft TTS engine.

  To use, include with `local tts = require('shared/utils/tts')` and then call `tts.say('phrase')`.
]]

local tts = {}
local callbacks

---Says text using Microsoft TTS engine. 
---@param text string @Text to say.
---@param params {voiceID: integer?, gender: nil|'male'|'female'|'neutral', rate: integer?, volume: number?}? @Property `rate` controls speed, values are from -10 to 10 (actual speed might depend on voice implement). Property `volume` should be within 0…1 range. Property `gender` is only a hint which would work if there is an installed fitting voice. If `voiceID` is set, voice associated to the ID will be used (usually it’s an `ID % numberOfVoicesAvailable` voice).
---@param callback nil|fun() @Will be called once text is finished.
---@overload fun(text: string, callback: fun())
function tts.say(text, params, callback)
  text = text ~= '' and tostring(text) or ''
  if text == '' then return end
  if type(params) == 'function' then
    params, callback = nil, params
  end
  local key = math.randomKey()
  if callback then
    if not callbacks then
      ac.onSharedEvent('$SmallTweaks.TTS.Said', function (data)
        if type(data) ~= 'number' then return end
        local v = callbacks[data]
        if v then
          callbacks[data] = nil
          v()
        end
      end)
      callbacks = {[key] = callback}
    else
      callbacks[key] = callback
    end 
  end 
  ac.broadcastSharedEvent('$SmallTweaks.TTS.Say', {
    text = text,
    params = params,
    key = callback and key or nil
  })
end

return tts