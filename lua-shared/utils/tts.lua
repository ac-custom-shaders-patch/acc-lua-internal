--[[
  A small text-to-speech library which uses Microsoft TTS engine.

  To use, include with `local tts = require('shared/utils/tts')` and then call `tts.say('phrase')`.
]]

local tts = {}
local mmf

---Says text using Microsoft TTS engine. 
---@param text string @Text to say.
function tts.say(text)
  if not text or text == '' then return end

  if mmf == nil then
    mmf = ac.writeMemoryMappedFile('AcTools.CSP.TTS.v0', {
      key = ac.StructItem.int32(),
      length = ac.StructItem.int32(),
      data = ac.StructItem.string(256)
    })
    os.runConsoleProcess({ 
      filename = ac.getFolder(ac.FolderID.ExtInternal)..'/plugins/AcTools.TextToSpeechService.exe',
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

return tts