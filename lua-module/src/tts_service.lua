--[[
  Voices online messages.
]]

if Sim.isOnlineRace and Config:get('MISCELLANEOUS', 'USE_TTS_FOR_CHAT', false) then
  -- This is how shared TTS library can be used:
  local tts = require('shared/utils/tts')
  ac.onChatMessage(function (message, senderCarIndex, senderSessionID)
    if senderCarIndex ~= -1 and senderCarIndex ~= 0 and #message < 256 then
      tts.say(message)
    end
  end)
end
