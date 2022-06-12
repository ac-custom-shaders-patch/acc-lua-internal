--[[
  Voices online messages.
]]--

if ac.getSim().isOnlineRace and Config:get('MISCELLANEOUS', 'USE_TTS_FOR_CHAT', false) then
  local mmf

  local function say(text)
    if not text or text == '' then return end

    if mmf == nil then
      mmf = ac.writeMemoryMappedFile('AcTools.CSP.TTS.v0', {
        key = ac.StructItem.int32(),
        length = ac.StructItem.int32(),
        data = ac.StructItem.string(256)
      })
      os.runConsoleProcess({ 
        filename = ac.getFolder(ac.FolderID.ExtRoot)..'/internal/plugins/AcTools.TextToSpeechService.exe',
        terminateWithScript = true,
        timeout = 0
      })
    end

    if mmf ~= nil then
      text = tostring(text)
      mmf.key = mmf.key + 1
      mmf.length = #text
      mmf.data = text
    end
  end

  ac.onChatMessage(function (message, senderCarIndex, senderSessionID)
    if senderCarIndex ~= -1 and senderCarIndex ~= 0 and #message < 256 then
      say(message)
    end
  end)
end
