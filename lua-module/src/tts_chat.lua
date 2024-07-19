--[[
  Voices online messages.
]]

if not Sim.isOnlineRace then
  return
end

local mode = Config:get('MISCELLANEOUS', 'USE_TTS_FOR_CHAT', 0)
if mode ~= 0 then
  -- This is how shared TTS library can be used:
  local tts = require('shared/utils/tts')
  ac.onChatMessage(function (message, senderCarIndex, senderSessionID)
    if senderCarIndex ~= -1 and senderCarIndex ~= 0 and #message < 256 then
      local voiceID
      if mode == 2 then
        local name = ac.getDriverName(senderCarIndex)
        if name then
          voiceID = tonumber(ac.checksumXXH(name)) % 1024
        end
      end
      tts.say(message, {voiceID = voiceID, rate = 2})
    end
  end)
end
