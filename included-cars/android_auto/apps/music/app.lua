local function time(value)
  if value == -1 then return '--:--' end
  return string.format('%02d:%02d', math.floor(value / 60), math.floor(value % 60))
end

local progressBaseColor = rgbm(33/255, 212/255, 94/255, 1)
local blurredBg = ui.ExtraCanvas(64)
local progressCurColor = progressBaseColor
local bgColor = rgbm(0, 0, 0, 1)
local coverColor1 = rgbm(0, 0, 0, 0.2)
local coverColor2 = rgbm(0, 0, 0, 1)

local function updateCover()
  local p = ac.currentlyPlaying()
  if p.hasCover then
    blurredBg:update(function (dt)
      ui.beginBlurring()
      ui.drawImage(p, 0, ui.windowSize())
      ui.endBlurring(0.2)
    end)

    blurredBg:accessData(function (err, data)
      local c = rgbm()
      progressCurColor = rgbm()
      for y = 1, 3 do
        for x = 1, 3 do
          progressCurColor:add(data:colorTo(c, 16*x, 16*y))
        end
      end
      progressCurColor:scale(1 / progressCurColor.mult)
      local h = progressCurColor.rgb:hsv()
      h.v = 1
      h.s = math.min(h.s * 1.3, 1)
      progressCurColor.rgb:set(h:rgb())

      bgColor.rgb:set(progressCurColor.rgb):scale(0.07)
      coverColor2.rgb:set(progressCurColor.rgb):scale(0.07)
    end)
  else
    blurredBg:clear(rgbm.colors.transparent)
    progressCurColor = progressBaseColor
  end
end

updateCover()
ac.onAlbumCoverUpdate(updateCover)

return function (dt)
  local playing = ac.currentlyPlaying()
  local p = math.min(ui.windowWidth() / 2, ui.windowHeight() * 1.2)
  local x = p - 200
  local y = (ui.windowHeight() - 240) / 2

  ui.drawRectFilled(0, ui.windowSize(), bgColor)
  ui.beginBlurring()
  ui.drawImage(blurredBg, -80, ui.windowHeight() + 80)
  ui.endBlurring(0.03)
  ui.drawRectFilledMultiColor(-80, ui.windowHeight() + 80, coverColor1, coverColor2, coverColor2, coverColor1)

  ui.setCursor(vec2(x, y))
  ui.image(playing, 160)

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
    ui.pathStroke(progressCurColor, false, 2)
  end

  ui.setCursor(vec2(p + 105 - 30, y + 182))
  if touchscreen.iconButton(ui.Icons.Next, 60) then
    ac.mediaNextTrack()
  end

  system.transparentTopBar()
end
