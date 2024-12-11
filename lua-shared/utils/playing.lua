--[[
  If your script is playing music, this library can help to announce details about currently playing track
  overriding data CSP would be guessing from system otherwise.
]]
---@diagnostic disable

local playing = {}

---@param details nil|{sourceID: string?, title: string, artist: string?, album: string?, isPlaying: boolean?, albumTracksCount: integer?, trackNumber: integer?, trackDuration: integer?, trackPosition: integer?, cover: binary?}
function playing.setCurrentlyPlaying(details)
  __util.native('media.currentlyPlaying', details)
end

return playing
