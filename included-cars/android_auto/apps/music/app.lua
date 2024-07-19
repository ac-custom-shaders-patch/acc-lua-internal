local function time(value)
  if value == -1 then return '--:--' end
  return string.format('%02d:%02d', math.floor(value / 60), math.floor(value % 60))
end

local bg = touchscreen.blurredBackgroundImage(rgbm(33/255, 212/255, 94/255, 1))

local function updateCover()
  local p = ac.currentlyPlaying()
  bg.update(p.hasCover and p or nil)
end

updateCover()
ac.onAlbumCoverUpdate(updateCover)

return function (dt)
  local playing = ac.currentlyPlaying()
  local p = math.min(ui.windowWidth() / 2, ui.windowHeight() * 1.2)
  local x = p - 200
  local y = (ui.windowHeight() - 240) / 2

  bg.draw(dt)

  ui.setCursor(vec2(x, y))
  ui.image(playing, 160, ui.ImageFit.Fit)

  ui.setCursor(vec2(x + 160 + 34, y))
  if not playing.isPlaying then ui.pushStyleVarAlpha(0.5) end
  ui.dwriteText(playing.title ~= '' and playing.title or 'Nothing', 30)
  if not playing.isPlaying then
    ui.popStyleVar()
  else
    ui.setCursor(vec2(x + 160 + 34, y + 40))
    ui.dwriteText(playing.album, 20)
  
    ui.setCursor(vec2(x + 160 + 34, y + 70))
    ui.dwriteText(playing.artist, 20)
  
    ui.setCursor(vec2(x + 160 + 34, y + 100))
    ui.dwriteText(string.format('%s / %s', time(playing.trackPosition), time(playing.trackDuration)), 20)
  end

  ui.setCursor(vec2(p - 105 - 30, y + 182))
  if touchscreen.iconButton(ui.Icons.Back, 60) then
    ac.mediaPreviousTrack()
  end

  ui.setCursor(vec2(p - 0 - 30, y + 182))
  if touchscreen.iconButton(playing.isPlaying and ui.Icons.Pause or ui.Icons.Play, 60) then
    ac.mediaPlayPause()
  end

  ui.drawCircle(vec2(p, y + 200 + 12), 36, rgbm.colors.gray, 30, 2)
  if playing.trackPosition ~= -1 and playing.trackDuration ~= -1 then
    ui.pathArcTo(vec2(p, y + 200 + 12), 36, -math.pi / 2, -math.pi / 2 + math.pi * 2 * math.saturateN(playing.trackPosition / playing.trackDuration), 30)
    ui.pathStroke(bg.accent(), false, 2)
  end

  ui.setCursor(vec2(p + 105 - 30, y + 182))
  if touchscreen.iconButton(ui.Icons.Next, 60) then
    ac.mediaNextTrack()
  end

  system.transparentTopBar()
end
