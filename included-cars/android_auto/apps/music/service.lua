-- Service runs once every few frames. Make sure to keep it lightweight.
local prevTrack = nil
return function (dt)
  local curTrack = ac.currentlyPlaying()
  system.setStatusPriority(curTrack.isPlaying and 2 or 0)
  local first = prevTrack == nil
  if first then
    prevTrack = {}
  end
  if curTrack.title ~= prevTrack.title or curTrack.artist ~= prevTrack.artist or curTrack.isPlaying ~= prevTrack.isPlaying then
    prevTrack.title = curTrack.title
    prevTrack.artist = curTrack.artist
    prevTrack.isPlaying = curTrack.isPlaying
    if curTrack.isPlaying and curTrack.title ~= '' then
      system.setNotification(
        curTrack, curTrack.title, string.format(curTrack.artist ~= '' and 'Playing: %s by %s' or 'Playing: %s', curTrack.title, curTrack.artist), first)
    else
      system.setNotification(nil)
    end
  end
end
