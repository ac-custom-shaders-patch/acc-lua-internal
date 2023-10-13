local remoteExe = 'https://github.com/yt-dlp/yt-dlp/releases/download/2023.07.06/yt-dlp.exe'

---Finds optimal format from list of formats returned by yt-dlp. Prefers something with both audio and video,
---looking for the largest file.
local function findOptimalQuality(data)
  local ret = tostring(table.maxEntry(data:split('\n'), function (format)
    if not string.match(string.sub(format, 1, 1), '[0-9]') then return -1e9 end
    if string.match(format, 'audio only') then return -1e9 end
    local w = 0
    if string.match(format, 'video only') then w = w - 20 end
    if string.match(format, 'mp4_dash') then w = w + 10 end
    if string.match(format, '3gp') then w = w - 5 end
    local v, u = string.match(format, ' ([0-9.]+)([MKG])iB')
    if v then
      v = tonumber(v) or 0
      if u == 'M' then v = v * 1e3
      elseif u == 'G' then v = v * 1e6 end
    else
      v = string.match(format, ' ([0-9.]+)k') or 0
    end
    w = w + v / 1e6
    return w
  end):sub(1, 3):trim())
  if tonumber(ret) == nil then
    ac.debug('Failed to find quality', data)
  end
  return ret
end

---Gets URL of a video stream from video URL using yt-dlp.
local function findVideoStreamURL(videoURL, callback, progressCallback)
  if progressCallback then progressCallback('Getting list of available formats…') end
  ac.debug('Youtube Stream', 'Listing formats…')
  os.runConsoleProcess({ filename = remoteExe, arguments = { '-F', videoURL }, separateStderr = true }, function (err, data)
    ac.debug('Youtube Stream', string.format('Formats list: error=%s, data=%s', err, data and data.stdout))
    if err then return callback(err) end
    local quality = findOptimalQuality(data.stdout)
    if quality == nil then callback('Couldn’t find optimal quality') end
    if progressCallback then progressCallback('Getting a stream URL…') end
    ac.debug('Youtube quality', quality)
    ac.debug('Youtube video URL', videoURL)
    os.runConsoleProcess({ filename = remoteExe, arguments = { '-f', quality, '--get-url', videoURL }, separateStderr = true }, function (err, data) 
      ac.debug('Youtube Stream', string.format('URL: error=%s, data=%s', err, data and data.stdout))
      callback(err, data.stdout) 
    end)
  end)
end

---Helper library to deal with YouTube. Might not work for long. 
Youtube = {}

---@class YoutubeVideo
---@field id string
---@field thumbnail string
---@field title string
---@field published string
---@field views string
---@field loadingState string
---@field durationText string
---@field channelName string
---@field channelThumbnail string
---@field channelVerified string
---@field channelURL string
---@field channelSubscribers string @Only present in .channelMode
---@field streamError string
---@field streamURL string
local YoutubeVideo = class('YoutubeVideo', function (data) return data end)

function YoutubeVideo:getURL()
  return 'https://www.youtube.com/watch?v='..self.id
end

---@param callback fun(err: string, url: string)
function YoutubeVideo:getStreamURL(callback)
  if self.streamError ~= nil or self.streamURL ~= nil then return callback(self.streamError, self.streamURL) end
  ac.debug('Last URL', self:getURL())
  return findVideoStreamURL(self:getURL(), 
    function (err, url)
      if err == nil and string.sub(url, 1, 4) ~= 'http' then
        ac.debug('Not a URL', url)
        err, url = 'Unknown error', nil 
      end
      self.streamError, self.streamURL = err and 'Failed to get video URL: '..err or nil, url
      callback(self.streamError, self.streamURL)
    end, 
    function (state) 
      self.loadingState = state
    end)
end

---@param html string
---@param pattern string
local function findString(html, pattern)
  local r = html:match(pattern)
  if r == nil or r:sub(#r, #r) ~= '\\' then return r end

  r = r:sub(1, #r - 1) .. '"'
  local _, i2 = html:find(pattern)
  local forceNext = false
  for i = i2 + 1, #html do
    local c = html:sub(i, i)
    if c == '\\' and not forceNext then
      forceNext = true
    else
      if c == '"' and not forceNext then break end
      forceNext = false
      r = r..c
    end
  end
  return r
end

local function decodeString(str)
  if not str then return nil end
  str = string.gsub(str, '\\"', '"')
  str = string.gsub(str, '\\u0026', '&')
  return str
end

local function parseYoutubeMainPageInner(html, separator)
  local ret = {}
  local index = html:find(separator)
  while index ~= nil do
    local nextIndex = html:find(separator, index + 30)
    local piece = nextIndex == nil and html:sub(index) or html:sub(index, nextIndex)
    local id = piece:match('"videoId":"(.-)"')
    local thumbnail = piece:match('"thumbnails":%[{"url":"(.-)"')
    local title = findString(piece, '"title":{"runs":%[{"text":"(.-)"}')
    local published = piece:match('"publishedTimeText":{"simpleText":"(.-)"')
    local views = piece:match('"viewCountText":{"simpleText":"(.-)"')
    if not views then
      views = piece:match('"viewCountText":{"runs":%[{"text":"(.-)"')
      if views then views = views .. ' watching' end
    end
    local durationText = piece:match('"lengthText":{.-"simpleText":"(.-)"')
    local channelName = findString(piece, '"ownerText":{"runs":%[{"text":"(.-)"')
    local channelThumbnail = piece:match('{"channelThumbnailWithLinkRenderer":{.-{"url":"(.-)"')
    local channelURL = piece:match('(/user/.-)"') or piece:match('(/c/.-)"') or piece:match('(/channel/.-)"')
    local channelVerified = channelName ~= nil and piece:match('"BADGE_STYLE_TYPE_VERIFIED"') ~= nil
    if id and thumbnail and title then
      table.insert(ret, YoutubeVideo{
        id = id,
        thumbnail = thumbnail,
        title = decodeString(title),
        published = published,
        views = views,
        durationText = durationText,
        channelName = decodeString(channelName),
        channelThumbnail = channelThumbnail,
        channelURL = channelURL,
        channelVerified = true or channelVerified
      })
    end
    index = nextIndex
  end
  return ret
end

local function parseYoutubeChannelInfo(html)
  return {
    channelName = findString(html, '"header":.-"title":"(.-)"'),
    channelThumbnail = html:match('"avatar":.-"url":"(.-)"'),
    channelVerified = html:match('BADGE_STYLE_TYPE_VERIFIED'),
    channelSubscribers = html:match('"subscriberCountText":{.-"simpleText":"(.-)"'),
    channelURL = 'https://m.youtube.com'..(html:match('(/user/.-)"') or html:match('(/c/.-)"') or html:match('(/channel/.-)"')),
  }
end

---Very simple parsing of a youtube page.
---@param html string
---@return YoutubeVideo[]
local function parseYoutubeMainPage(html)
  local ret = parseYoutubeMainPageInner(html, '"videoRenderer"')
  if #ret == 0 then
    ret = parseYoutubeMainPageInner(html, '"gridVideoRenderer"')
  end
  if #ret > 0 and table.every(ret, function (item, index, firstItem)
    return item.channelName == firstItem.channelName
  end, ret[1]) then
    ret.channelMode = parseYoutubeChannelInfo(html)
  end
  return ret
end

---@param searchQuery string
local function buildURL(searchQuery)
  searchQuery = searchQuery and searchQuery:trim() or nil
  if not searchQuery then return 'https://m.youtube.com' end
  if searchQuery:sub(1, 1) == '/' then return 'https://m.youtube.com'..searchQuery..'/videos' end
  return 'https://m.youtube.com/results?search_query='..searchQuery
end

---@param searchQuery string|nil
---@param callback fun(err: string, videos: YoutubeVideo[])
function Youtube.getVideos(searchQuery, callback)
  local cacheKey = searchQuery == nil and 'cache' or nil -- 'cache:'..tostring(searchQuery)
  local cached = ac.load(cacheKey)
  if not searchQuery and cached then
    return callback(nil, parseYoutubeMainPage(cached))
  end

  web.get(buildURL(searchQuery), { ['Accept-Language'] = 'en-US' }, function (err, response)
    if err then return callback('Failed to load YouTube: '..err, nil) end
    if cacheKey then ac.store(cacheKey, response.body) end
    local videos = try(function () return parseYoutubeMainPage(response.body) end, 
    function (err) callback('Failed to parse YouTube: '..err, nil) end)
    if videos then callback(nil, videos) end
  end)
end
