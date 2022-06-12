require('touchscreen')
require(package.relative('youtube'))

---@type ui.MediaPlayer
local youtubePlayer = nil

---@type YoutubeVideo[]
local videosList = nil

---@type YoutubeVideo
local selectedVideo = nil

local videoSelectActive = false
local videoSelectTransition = 0
local videosListError = nil
local searchQuery = nil
local resetScroll = false
local playerUIFade = 0
local playerUIVisible = 0
local playerUIRecentChange = 0
local playerUIReactToButtons = false
local playerUIStepBack = 0
local playerUIStepForward = 0
local playerUIShowRemainingTime = false
local playerUINaNTime = 0
local mpSupported

---Load Youtube page and parse it into a bunch of videos.
local function loadYoutubePage(searchQuery)
  videosList = nil
  videosListError = nil
  resetScroll = true
  Youtube.getVideos(searchQuery, function(err, videoInfos) 
    videosListError, videosList = err, videoInfos
  end)
end

---Select a video, start showing (find stream URL and get it to video player).
---@param video YoutubeVideo
local function selectVideo(video)
  if video == (videoSelectActive and selectedVideo or nil) then return end
  playerUINaNTime = 0
  if video ~= nil then
    selectedVideo = video
    videoSelectActive = true
    playerUIVisible = 2
    if mpSupported ~= false then
      video:getStreamURL(function(err, url)
        if err ~= nil or selectedVideo ~= video then return end
        youtubePlayer:setSource(url):setCurrentTime(0)
        setTimeout(function() youtubePlayer:play() end, 0.01)
      end)
    end
    system.setStatusPriority(10)
  else
    videoSelectActive = false
    youtubePlayer:setSource(''):pause()
    system.setStatusPriority(0)
  end
end

---Global object for status script to access state of currently playing video
YoutubeAppData = {
  hasVideo = function () return youtubePlayer and youtubePlayer:hasVideo() end,
  playing = function () return youtubePlayer and youtubePlayer:playing() end,
  hasNextPrevious = function ()
    local videoIndex = table.indexOf(videosList, selectedVideo)
    return videoIndex < #videosList, videoIndex > 1
  end,
  toggle = function ()
    if not youtubePlayer then return end
    if youtubePlayer:playing() then youtubePlayer:pause() else youtubePlayer:play() end
  end,
  goToNext = function () selectVideo(videosList[table.indexOf(videosList, selectedVideo) + 1]) end,
  goToPrevious = function () selectVideo(videosList[table.indexOf(videosList, selectedVideo) - 1]) end
}

local previewImageSize = vec2(240, 135)
local previewChannelCenter = vec2(16, previewImageSize.y + 24)
local previewChannelRadius = 16
local previewAreaHeight = 84
local previewSmallAreaHeight = 64
local previewTotalSize = previewImageSize + vec2(0, previewAreaHeight)
local previewTotalSmallSize = previewImageSize + vec2(0, previewSmallAreaHeight)

local previewDurationBg = rgbm(0, 0, 0, 0.7)
local previewDurationFont = 'Segoe UI;Weight=Bold'
local previewDurationFontSize = 11

local previewTitleFont = 'Segoe UI;Weight=Bold'
local previewTitleFontSize = 13

local previewInfoFontSize = 13
local previewVerifiedIconRadius = 12
local previewVerifiedIconOffset = vec2(4, 3)

---A UI control with video preview and a very primitive animation on hover.
---@param v YoutubeVideo
---@param channelMode boolean
local function ControlVideoPreview(v, channelMode)
  local size = channelMode and previewTotalSmallSize or previewTotalSize
  if not ui.areaVisible(size) then
    ui.dummy(size)
    return
  end

  local noClick = false
  ui.beginGroup()

  -- prepare videos by precomputing and caching some values. not necessary, but why not
  if not v.infoText then
    if v.channelName then
      v.infoText = v.views and v.published and string.format('%s\n%s • %s', v.channelName, v.views, v.published) 
        or v.views and string.format('%s\n%s', v.channelName, v.views) 
        or v.channelName
    else
      v.infoText = v.views and v.published and string.format('%s • %s', v.views, v.published) or nil
    end
    v.previewTitlePos = vec2(v.channelThumbnail and 40 or 0, previewImageSize.y + 8)
    v.previewTitleSize = vec2(previewImageSize.x - 10 - v.previewTitlePos.x, 35)
    v.previewInfoSize = vec2(previewImageSize.x - 10 - v.previewTitlePos.x, 35)

    ui.pushDWriteFont(previewTitleFont)
    local titleHeight = math.min(ui.measureDWriteText(v.title, previewTitleFontSize, v.previewTitleSize.x).y, v.previewTitleSize.y)
    v.infoPos = vec2(v.previewTitlePos.x, v.previewTitlePos.y + titleHeight)
    ui.popDWriteFont()

    if v.channelVerified then
      local infoWidth = ui.measureDWriteText(v.channelName, previewInfoFontSize).x
      if infoWidth > v.previewInfoSize.x - 20 then
        v.previewInfoSize.x = v.previewInfoSize.x - 20
        infoWidth = v.previewInfoSize.x
      end
      v.verifiedMarkPos = v.infoPos + vec2(infoWidth, 0) + previewVerifiedIconOffset
    end

    if v.durationText then
      ui.pushDWriteFont(previewDurationFont)
      v.previewDurationSize = ui.measureDWriteText(v.durationText, previewDurationFontSize) + vec2(8, 4)
      v.previewDurationOffset = previewImageSize - v.previewDurationSize - 4
      ui.popDWriteFont()
    end
  end

  local c = ui.getCursor()

  -- main preview
  ui.image(v.thumbnail, previewImageSize, true)

  -- fixed offset to ensure equal spacing
  ui.offsetCursorY(channelMode and previewSmallAreaHeight or previewAreaHeight)

  -- channel icon
  if v.channelThumbnail then
    ui.beginTextureShade(v.channelThumbnail)
    ui.drawCircleFilled(c + previewChannelCenter, previewChannelRadius, rgbm.colors.white, 32)
    ui.endTextureShade(c + previewChannelCenter - previewChannelRadius, c + previewChannelCenter + previewChannelRadius)
  end

  if touchscreen.tapped() and ui.rectHovered(c + previewChannelCenter - previewChannelRadius, c + previewChannelCenter + previewChannelRadius) then
    noClick = true
    loadYoutubePage(v.channelURL)
  end

  if v.durationText then
    ui.setCursor(c + v.previewDurationOffset)
    ui.pushDWriteFont(previewDurationFont)
    ui.drawRectFilled(c + v.previewDurationOffset, c + v.previewDurationOffset + v.previewDurationSize, previewDurationBg, 3)
    ui.dwriteTextAligned(v.durationText, previewDurationFontSize, ui.Alignment.Center, ui.Alignment.Center, v.previewDurationSize, false, rgbm.colors.white)
    ui.popDWriteFont()
  end

  ui.setCursor(c + v.previewTitlePos)
  ui.pushDWriteFont(previewTitleFont)
  ui.dwriteTextAligned(v.title, previewTitleFontSize, ui.Alignment.Start, ui.Alignment.Start, v.previewTitleSize, true, rgbm.colors.white)
  ui.popDWriteFont()

  if v.infoText then
    ui.setCursor(c + v.infoPos)
    ui.dwriteTextAligned(v.infoText, previewInfoFontSize, ui.Alignment.Start, ui.Alignment.Start, v.previewInfoSize, false, rgbm.colors.white)
    if not channelMode and v.channelVerified then
      ui.setCursor(c + v.verifiedMarkPos)
      ui.icon(ui.Icons.Verified, previewVerifiedIconRadius, rgbm.colors.gray)
    end
  end

  ui.endGroup()
  return not noClick and touchscreen.itemTapped()
end

---A UI control with video player. Again, very primitive, uses sliders for time and volume bars. Of course, could be done better,
---but for an example that should be all right.
---@param size vec2
---@return boolean @If true, video needs to close
local function ControlVideoPlayer(size, dt)
  ui.drawRectFilled(ui.getCursor(), ui.getCursor() + size, rgbm.colors.black)

  local width = size.x
  local height = math.ceil(width * 9 / 16)
  if height > size.y then
    height = size.y
    local newWidth = math.ceil(height * 16 / 9)
    ui.offsetCursorX((width - newWidth) / 2)
    width = newWidth
  end
  local pos = ui.getCursor()

  -- if video is not yet ready, show loading animation
  if mpSupported == false then
    ui.setCursor(pos)
    ui.textAligned('Not supported on this device', 0.5, vec2(width, height))
  elseif selectedVideo.streamError then
    ui.setCursor(pos)
    ui.textAligned(selectedVideo.streamError, 0.5, vec2(width, height))
  elseif not selectedVideo.streamURL then
    ui.setCursor(pos + vec2(width / 2 - 30, height / 2 - 30))
    touchscreen.loading(60)
  else
    -- video itself, drawn first if URL is ready
    ui.image(youtubePlayer, vec2(width, height), true)
  end

  -- once tapped, show UI for two seconds
  if touchscreen.tapped() or touchscreen.touched() then
    playerUIVisible = 2
    playerUIRecentChange = math.max(playerUIRecentChange, 1)
  end

  if ui.mouseClicked() then
    playerUIReactToButtons = playerUIFade > 0.95
  end
    
  -- play/pause icon showing when middle is tapped (later)
  local duration = youtubePlayer:duration()
  if playerUIRecentChange > 0 and selectedVideo.streamURL and not math.isNaN(duration) then
    playerUIRecentChange = playerUIRecentChange - dt
    ui.pushStyleVarAlpha(math.saturateN(playerUIRecentChange * 4))
    
    ui.setCursor(pos + vec2(width / 2 - 40, height / 2 - 40))
    if touchscreen.iconButton(youtubePlayer:playing() and ui.Icons.Pause or ui.Icons.Play, 80) and playerUIReactToButtons then
      if youtubePlayer:playing() then
        playerUIRecentChange = 3
        youtubePlayer:pause()
      else
        playerUIRecentChange = 1
        youtubePlayer:play()
      end
    end

    local videoIndex = table.indexOf(videosList, selectedVideo)
    if videoIndex < #videosList then
      ui.setCursor(pos + vec2(width / 2 - 40 + 80, height / 2 - 40))
      if touchscreen.iconButton(ui.Icons.Next, 80) and playerUIReactToButtons then
        selectVideo(videosList[videoIndex + 1])
      end
    end

    if videoIndex > 1 then
      ui.setCursor(pos + vec2(width / 2 - 40 - 80, height / 2 - 40))
      if touchscreen.iconButton(ui.Icons.Back, 80) and playerUIReactToButtons then
        selectVideo(videosList[videoIndex - 1])
      end
    end

    if playerUIStepBack > 0 then
      playerUIStepBack = playerUIStepBack - dt
      ui.setCursor(pos + vec2(width / 2 - 80 - 200, height / 2 - 80))
      if touchscreen.iconButton(ui.Icons.Rewind, 160, playerUIStepBack * 4) then
        youtubePlayer:setCurrentTime(youtubePlayer:currentTime() - 10)
        playerUIStepBack = 0.5
      end
    elseif touchscreen.doubleTapped() and ui.rectHovered(pos + vec2(width / 2 - 80 - 200, height / 2 - 80), pos + vec2(width / 2 + 80 - 200, height / 2 + 80)) then
      youtubePlayer:setCurrentTime(youtubePlayer:currentTime() - 10)
      playerUIStepBack = 0.5
    end

    if playerUIStepForward > 0 then
      playerUIStepForward = playerUIStepForward - dt
      ui.setCursor(pos + vec2(width / 2 - 80 + 200, height / 2 - 80))
      if touchscreen.iconButton(ui.Icons.FastForward, 160, playerUIStepForward * 4) then
        youtubePlayer:setCurrentTime(youtubePlayer:currentTime() + 10)
        playerUIStepForward = 0.5
      end
    elseif touchscreen.doubleTapped() and ui.rectHovered(pos + vec2(width / 2 - 80 + 200, height / 2 - 80), pos + vec2(width / 2 + 80 + 200, height / 2 + 80)) then
      youtubePlayer:setCurrentTime(youtubePlayer:currentTime() + 10)
      playerUIStepForward = 0.5
    end

    ui.popStyleVar()
  end

  if selectedVideo.streamURL ~= nil and math.isNaN(duration) then
    playerUINaNTime = playerUINaNTime + dt
    if playerUINaNTime > 10 then
      ac.debug('Failed video: stats for nerds', youtubePlayer:debugText())
      ac.debug('Failed video: URL', selectedVideo.streamURL)
      selectedVideo.streamError = 'Failed to stream video'
      selectedVideo.streamURL = nil
      youtubePlayer:pause()
    end
  end

  -- if UI is not visible, early exit
  if playerUIVisible <= 0 then return youtubePlayer:ended() end

  -- UI with fading
  playerUIVisible = playerUIVisible - dt
  playerUIFade = math.applyLag(playerUIFade, math.saturateN(playerUIVisible * 4), 0.8, dt)
  ui.pushStyleVarAlpha(playerUIFade)

  -- darker areas (with gradient) on top and bottom
  local gradientColor = rgbm(0, 0, 0, 0.7)
  ui.drawRectFilledMultiColor(pos, pos + vec2(width, height * 0.3), 
    gradientColor, gradientColor, rgbm.colors.transparent, rgbm.colors.transparent)
  ui.drawRectFilledMultiColor(pos + vec2(0, height * 0.7), pos + vec2(width, height), 
    rgbm.colors.transparent, rgbm.colors.transparent, gradientColor, gradientColor)

  -- if video is ready to be streamed, some video controls
  if selectedVideo.streamURL ~= nil and not math.isNaN(duration) then
    ui.setCursor(pos + vec2(20, height - 40))
    ui.pushStyleVarAlpha(0.001)  -- invisible slider for input. could be done with a custom control too, but this is faster
    ui.setNextItemWidth(width - 40)
    local time = youtubePlayer:currentTime()
    local newTime = ui.slider('##position', time, 0, duration, '')
    if ui.itemEdited() then
      if youtubePlayer:playing() then setTimeout(function() youtubePlayer:play() end, 0.01) end
      youtubePlayer:setCurrentTime(newTime)
    end
    ui.popStyleVar()

    local thumb = pos + vec2(math.lerp(20, width - 20, math.saturateN(time / duration)), height - 29)
    ui.drawLine(pos + vec2(20, height - 29), pos + vec2(width - 20, height - 29), rgbm(1, 1, 1, 0.2), 2)
    ui.drawLine(pos + vec2(20, height - 29), thumb, rgbm.colors.red, 2)
    ui.drawCircleFilled(thumb, 6, rgbm.colors.red)

    local timeToShow = playerUIShowRemainingTime and duration - time or time
    local timePos = pos + vec2(24, height - 59)
    ui.setCursor(timePos)
    ui.text(string.format(playerUIShowRemainingTime and '-%.0f:%02.0f' or '%.0f:%02.0f', math.floor(timeToShow / 60), timeToShow % 60))
    ui.sameLine(0, 0)
    ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
    ui.text(string.format(' / %.0f:%02.0f', math.floor(duration / 60), duration % 60))
    ui.popStyleColor()
    if touchscreen.tapped() and ui.rectHovered(timePos, timePos + vec2(100, 20)) then
      playerUIShowRemainingTime = not playerUIShowRemainingTime
    end

    if touchscreen.volumeControl(pos, width, height) then
      playerUIVisible = 2
    end
  end

  ui.setCursor(pos + vec2(20, 20))
  local closeVideo = touchscreen.iconButton(ui.Icons.Skip, 36, nil, 0)
  ui.sameLine(0, 12)
  ui.offsetCursorY(4)
  ui.dwriteTextAligned(selectedVideo.title, 20, ui.Alignment.Start, ui.Alignment.Start, vec2(width - 130, 36), false, rgbm.colors.white)

  ui.setCursor(pos + vec2(width - 20 - 36, 20))
  if touchscreen.iconButton(ui.Icons.Undo, 36, nil, nil, vec2(-1, 1)) then
    ac.setClipboadText(selectedVideo:getURL())
    ui.toast(ui.Icons.YoutubeSolid, 'Link to current video is copied to the clipboard')
  end

  ui.popStyleVar()  
  return closeVideo or youtubePlayer:ended()
end

local function ControlYoutubeLogo()
  ui.beginGroup()
  ui.icon(ui.Icons.YoutubeSolid, 24, rgbm(1, 0, 0, 1))
  ui.sameLine(0, 2)
  local p = ui.getCursor()
  ui.beginScale()
  ui.pushDWriteFont('Segoe UI;Weight=Bold') -- I’m too lazy to convert original svg to png, so here we go, close enough
  ui.offsetCursorY(-3)
  ui.dwriteText('YouTube', 20)
  ui.popDWriteFont()
  ui.endPivotScale(vec2(0.65, 1), p)
  ui.endGroup()
end

local function ControlVideosList()
  local size = ui.availableSpace()

  ui.sameLine(0, 120)
  ui.offsetCursorY(4)
  ControlYoutubeLogo()
  if touchscreen.itemTapped() then
    searchQuery = ''
    loadYoutubePage(nil)
  end
  ui.sameLine(0, 8)
  ui.offsetCursorY(4)
  ui.setNextItemWidth(ui.availableSpaceX() - 220)
  local changed
  searchQuery, changed = touchscreen.inputText('Search', searchQuery, ui.InputTextFlags.Placeholder)
  if changed then
    loadYoutubePage(searchQuery)
  end
  ui.sameLine(0, 0)
  if touchscreen.button('##search', vec2(60, 22), rgbm(0.12, 0.12, 0.12, 1), 0, ui.Icons.Search, 14) then
    loadYoutubePage(searchQuery)
  end
  ui.offsetCursorY(8)

  size.y = ui.availableSpaceY()

  if not videosList then
    -- ui.textAligned(videosListError or 'Loading list of videos…', 0.5, size)
    ui.offsetCursor(vec2(size.x / 2 - 30, size.y / 2 - 30))
    touchscreen.loading(60)
  elseif #videosList == 0 then
    ui.textAligned('No videos found', 0.5, size)
  else
    local channelMode = videosList.channelMode
    ui.childWindow('scrollingArea', size, function()
      local w = ((ui.availableSpaceX() + 4) % (previewImageSize.x + 4)) / 2
      ui.indent(w)

      if resetScroll then
        ui.setScrollY(0)
        resetScroll = false
      end

      if channelMode then
        ui.offsetCursorY(20)
        local c = ui.getCursor()
        local channelInfoX = 24 + previewImageSize.x + 4
        ui.beginTextureShade(channelMode.channelThumbnail)
        ui.drawCircleFilled(c + vec2(channelInfoX, 24), 24, rgbm.colors.white, 32)
        ui.endTextureShade(c + vec2(channelInfoX, 24) - 24, c + vec2(channelInfoX, 24) + 24)
        ui.setCursor(c + vec2(channelInfoX+24+16, 0))
        ui.dwriteTextAligned(channelMode.channelName, 20, ui.Alignment.Start, ui.Alignment.Center, vec2(0, 28))
        if channelMode.channelVerified then
          ui.setCursor(c + vec2(channelInfoX+24+16 + ui.measureDWriteText(channelMode.channelName, 20).x + 8, 10))
          ui.icon(ui.Icons.Verified, previewVerifiedIconRadius, rgbm.colors.gray)
        end
        ui.setCursor(c + vec2(previewImageSize.x * 3 + 8 - 100, 12))
        ui.pushDWriteFont('Segoe UI;Weight=Bold')
        if touchscreen.button('SUBSCRIBE', vec2(100, 24), rgbm(0.8, 0, 0, 1), 11) then
          ac.setClipboadText(channelMode.channelURL)
          ui.toast(ui.Icons.YoutubeSolid, 'Channel URL is copied to the clipboard')
        end
        ui.popDWriteFont()
        ui.setCursor(c + vec2(channelInfoX+24+16, 24))
        ui.dwriteTextAligned(channelMode.channelSubscribers, 13, ui.Alignment.Start, ui.Alignment.Center, vec2(0, 28))
        ui.offsetCursorY(16)
      end

      for _, v in ipairs(videosList) do
        if ControlVideoPreview(v, channelMode) then selectVideo(v) end
        ui.sameLine(0, 4)
        if ui.availableSpaceX() < previewImageSize.x then ui.newLine() end
      end
      ui.unindent(w)
      touchscreen.scrolling()
    end)
  end
end

return function(dt)
  if youtubePlayer == nil then
    youtubePlayer = ui.MediaPlayer():setAutoPlay(true)
    touchscreen.syncVolume(youtubePlayer)
    loadYoutubePage()
    -- loadYoutubePage('cats')

    ui.MediaPlayer.supportedAsync(function (supported)
      mpSupported = supported
    end)
  else
    touchscreen.syncVolumeIfFresh(youtubePlayer)
  end

  ui.setCursor(0)
  local size = ui.availableSpace()
  videoSelectTransition = math.applyLag(videoSelectTransition, videoSelectActive and 1 or 0, 0.9, dt)

  if videoSelectTransition > 0.001 then
    if videoSelectActive then system.fullscreen() end
    touchscreen.boostFrameRate()
  end

  if videoSelectTransition > 0.001 then
    ui.offsetCursorY(-math.floor(size.y * (1 - videoSelectTransition)))
    if ControlVideoPlayer(size, dt) then
      selectVideo(nil)
    end
    ui.setCursor(0)
  elseif youtubePlayer:playing() then
    youtubePlayer:pause()
  end

  if videoSelectTransition < 0.999 then
    ui.offsetCursorY(math.floor(size.y * videoSelectTransition) + system.topBarHeight)
    size.y = size.y - system.topBarHeight
    ui.childWindow('listOfVideos', size, ControlVideosList)
  end
end
