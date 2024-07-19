---@ext
--[[
  Simple library providing a new web browser control using Chromium Embedded Framework (CEF) for
  offscreen rendering and accessing output via shared texture to keep things fast.

  Usage:

  ```lua
  local WebBrowser = require('shared/web/browser')
  
  local browser = WebBrowser()
  browser:navigate('google.com')

  function script.windowMain()
    ui.dummy(ui.availableSpace())
    browser:draw(ui.itemRect(), true)
  end
  ```

  Note: don’t use any fields starting with “_”, those might be changed later. Also, use 
  `ui.beginPremultipliedAlphaTexture()`/`ui.endPremultipliedAlphaTexture()` when drawing browser 
  if you want your browser to be semi-transparent.
]]

local DEBUG_EXCHANGE = const(false)

local connect = ac.connect{
  ac.StructItem.key('cefState'),
  tabsCount = ac.StructItem.int32(),
  cefState = ac.StructItem.byte(), -- 0: ready, 1: installing, ≥10: errors
  cefLoop = ac.StructItem.boolean(),
  noProxyServer = ac.StructItem.boolean(),
  useTimer = ac.StructItem.boolean(),
  setGPUDevicePriority = ac.StructItem.int8(),
  setGPUProcessPriority = ac.StructItem.int8(),
  targetFPS = ac.StructItem.int32(),
}

---@alias WebBrowser.Features {imageLoading: boolean?, javascript: boolean?, remoteFonts: boolean?, localStorage: boolean?, databases: boolean?, webGL: boolean?, shrinkImagesToFit: boolean?, textAreaResize: boolean?, tabToLinks: boolean?}
---@alias WebBrowser.Settings {size: vec2?, directRender: boolean?, redirectAudio: boolean?, audioParameters: {use3D: boolean, reverb: boolean}, backgroundColor: rgbm?, acceptLanguages: string?, dataKey: string?, features: WebBrowser.Features?, automaticallyRestartOnBackendCrash: boolean?, attributes: {}}
---@alias WebBrowser.BlankOverride {title: string, url: string, favicon: string, onDraw: fun(p1: vec2, p2: vec2, tab: WebBrowser), onRelease: fun(), attributes: any}
---@alias WebBrowser.CertificateActor {commonName: string, organizationNames: string[], organizationUnitNames: string[]}
---@alias WebBrowser.CertificateDescription {issuer: WebBrowser.CertificateActor, subject: WebBrowser.CertificateActor, chainSize: integer, validPeriod: {creation: integer, expiration: integer}}
---@alias WebBrowser.SSLStatus {secure: boolean, faultsMask: integer, SSLVersion: integer, certificate: WebBrowser.CertificateDescription?}
---@alias WebBrowser.NavigationEntry {current: boolean, displayURL: string, title: string, hasPostData: boolean, HTTPCode: integer, transitionType: integer}
---@alias WebBrowser.PageState {status: integer, flags: integer, post: boolean, secure: boolean}
---@alias WebBrowser.LoadError {failedURL: string, errorCode: integer, errorText: string}
---@alias WebBrowser.Cookie {name: string, value: string, domain: string?, path: string?, secure: boolean, HTTPOnly: boolean, creationTime: integer, lastAccessTime: integer, expirationTime: integer?}
---@alias WebBrowser.DownloadQuery {ID: integer, downloadURL: string, originalURL: string, mimeType: string, contentDisposition: string?, suggestedName: string, totalBytes: integer?}
---@alias WebBrowser.DownloadItem {attributes: {}, ID: integer, downloadURL: string, originalURL: string, mimeType: string, contentDisposition: string?, suggestedName: string, receivedBytes: integer, totalBytes: integer?, currentSpeed: integer, destination: string, state: 'loading'|'complete'|'cancelled'|'paused', control: fun(self: WebBrowser.DownloadItem, command: 'pause'|'resume'|'cancel')}

local ACCSP_FRAME_SIZE = const(128 * 1024)
local ACCSP_MAX_COMMAND_SIZE = const(1 * 1024)
local ACCSP_BUFFER_SIZE = const(112 + 2 * ACCSP_FRAME_SIZE)
local ACCSP_AUDIO_STEAM_SIZE = const(16 * 4 + 1920 * 32 * 4)

local CommandFE = const({
  LargeCommand = const(string.byte('\2', 1)),

  LoadStart = const(string.byte('/', 1)),
  LoadEnd = const(string.byte('0', 1)),
  OpenURL = const(string.byte('1', 1)),
  Popup = const(string.byte('2', 1)),
  JavaScriptDialog = const(string.byte('3', 1)),
  Download = const(string.byte('4', 1)),
  ContextMenu = const(string.byte('5', 1)),
  LoadFailed = const(string.byte('6', 1)),
  FoundResult = const(string.byte('7', 1)),
  FileDialog = const(string.byte('8', 1)),
  AuthCredentials = const(string.byte('9', 1)),
  FormData = const(string.byte(':', 1)),
  CustomSchemeBrowse = const(string.byte(';', 1)),

  RequestReply = const(string.byte('\1', 1)),
  DataFromScript = const(string.byte('R', 1)),
  URLMonitor = const(string.byte('m', 1)),
  CSPSchemeRequest = const(string.byte('S', 1)),
  DownloadUpdate = const(string.byte('r', 1)),
  Close = const(string.byte('x', 1)),

  Favicon = const(string.byte('I', 1)),
  URL = const(string.byte('U', 1)),
  Title = const(string.byte('T', 1)),
  Status = const(string.byte('?', 1)),
  Tooltip = const(string.byte('O', 1)),
  Audio = const(string.byte('A', 1)),
  VirtualKeyboardRequest = const(string.byte('v', 1)),
})

local IsCommandFECarriesLSON = const(function (command) return command >= CommandFE.OpenURL and command <= CommandFE.CustomSchemeBrowse end)

local CommandBE = const({
  LargeCommand = const(string.byte('\2')),

  Navigate = const(string.byte('N')),
  SetOption = const(string.byte('i')),
  FilterResourceURLs = const(string.byte('f')),
  SetHeaders = const(string.byte('h')),
  InjectJavaScript = const(string.byte('j')),
  InjectStyle = const(string.byte('s')),

  Zoom = const(string.byte('z')),
  Reload = const(string.byte('R')),
  Stop = const(string.byte('S')),
  Lifespan = const(string.byte('U')),
  Download = const(string.byte('W')),
  Command = const(string.byte('C')),
  Input = const(string.byte('I')),
  KeyDown = const(string.byte('>')),
  KeyUp = const(string.byte('<')),
  Find = const(string.byte('d')),
  Mute = const(string.byte('M')),
  CaptureLost = const(string.byte('A')),
  Execute = const(string.byte('E')),
  DevToolsMessage = const(string.byte('w')),
  Send = const(string.byte('e')),
  Scroll = const(string.byte('l')),
  
  Reply = const(string.byte('\1')),
  HTML = const(string.byte('H')),
  Text = const(string.byte('T')),
  History = const(string.byte('Y')),
  WriteCookies = const(string.byte('o')),
  ReadCookies = const(string.byte('c')),
  SSL = const(string.byte('L')),
  DownloadImage = const(string.byte('n')),
  ControlDownload = const(string.byte('r')),
  FillForm = const(string.byte('F')),
  Awake = const(string.byte('K')),
  ColorScheme = const(string.byte('m')),
})

---@type {fileKey: integer, dataSize: integer}
---@diagnostic disable-next-line: assign-type-mismatch
local PackedCommand = ac.StructItem.combine([[int fileKey;int dataSize;]])

---@type {ID: integer, flags: integer, receivedBytes: integer, totalBytes: integer, currentSpeed: integer}
---@diagnostic disable-next-line: assign-type-mismatch
local DownloadUpdate = ac.StructItem.combine([[uint32_t ID,flags;int64_t totalBytes,currentSpeed,receivedBytes;]])

local sim = ac.getSim()
local faviconCache = {}

local function encodeBrowserParameter(v)
  return type(v) == 'boolean' and (v and '1' or '0')
    or rgbm.isrgbm(v) and '0x'..v:hex():sub(2) or v
end

---@param settings WebBrowser.Settings
local function initWebHost(settings)
  if connect.tabsCount >= 255 then
    error('Too many tabs', 3)
  end

  local config = {}
  for k, v in pairs(settings) do
    if type(v) == 'table' then
      for kf, kv in pairs(v) do
        config[#config + 1] = string.format('%s=%s', kf, encodeBrowserParameter(kv))
      end
    elseif k ~= 'size' and k ~= 'attributes' then
      config[#config + 1] = string.format('%s=%s', k, encodeBrowserParameter(v))
    end
  end

  local newTab = math.randomKey()
  if next(debug) == nil then
    newTab = bit.bor(newTab, 1)
  else
    newTab = bit.band(newTab, bit.bnot(1))
  end
  local prefix = string.format(next(debug) == nil and 'AcTools.CSP.Limited.CEF.v0.%u' or 'AcTools.CSP.CEF.v0.%u', newTab)
  
  ---@type {beAliveTime: integer, beFlags: integer, handle: integer, commandsSet: integer, commands: any, responseSet: integer, response: any, needsNextFrame: integer, popupHandle: integer, width: integer, height: integer, mouseX: integer, mouseY: integer, mouseFlags: integer, mouseWheel: integer, loadingProgress: integer, touches: vec2[], cursor: integer, feFlags: integer, scrollOffset: vec2, audioPeak: integer, popup0: vec2, popup1: vec2, zoomLevel: number}
  local mapped = ac.writeMemoryMappedFile(prefix, const(string.format([[uint64_t beAliveTime;
float zoomLevel;
uint32_t _pad0;
uint64_t handle;  
uint64_t popupHandle;
vec2 popup0;  
vec2 popup1;  
uint32_t width;
uint32_t height;  
uint16_t loadingProgress;
uint8_t cursor;
uint8_t audioPeak;
uint32_t feFlags;
uint16_t mouseX;
uint16_t mouseY;
int16_t mouseWheel;
uint8_t mouseFlags;    
uint8_t needsNextFrame;    
uint64_t beFlags;
vec2 touches[2];
const vec2 scrollOffset;
uint32_t commandsSet;
uint32_t responseSet;
uint8_t commands[%d];
uint8_t response[%d];]], ACCSP_FRAME_SIZE, ACCSP_FRAME_SIZE)), false)
  mapped.width = math.round(settings.size.x)
  mapped.height = math.round(settings.size.y)
  mapped.beFlags = 1
  mapped.beAliveTime = sim.systemTime
  mapped.touches[0].x = math.huge
  mapped.touches[1].x = math.huge
  mapped.response = table.concat(config, '\n')
  ac.broadcastSharedEvent('$SmallTweaks.CEF', {added = newTab})
  return mapped, string.format('%s.T', prefix), function ()
    ac.broadcastSharedEvent('$SmallTweaks.CEF', {removed = newTab})
  end
end

local function readInt16(data, offset)
  return data[offset] + data[offset + 1] * 256
end

local function writeInt16(data, offset, value)
  data[offset] = value
  data[offset + 1] = value / 256
end

local function copyStringToBinaryData(data, offset, str, len)
  local o = offset - 1
  for i = 1, len do
    data[i + o] = string.byte(str, i)
  end
end

local getStringFromBinaryData = ffi.string
if getStringFromBinaryData == nil then
  local cache = {}
  getStringFromBinaryData = function(data, len)
    table.clear(cache)
    for i = 1, len do
      cache[i] = string.char(data[i - 1])
    end
    return table.concat(cache)
  end
end

local instances = setmetatable({}, {__mode = 'v'})

---@class WebBrowser
---@field private _crashReported boolean
local webBrowser = class('WebBrowser')

---@param self WebBrowser
local function submitCommands(self)
  if self._initializing then
    return
  end

  ac.memoryBarrier()
  if self._mm.commandsSet ~= 0 then
    if self._queued == -1 then
      self._queued = setTimeout(function ()
        self._queued = -1
        submitCommands(self)
      end)
    end
    return
  end

  if #self._largeBuffers > 0 then
    for i = 1, #self._largeBuffers do
      ac.disposeMemoryMappedFile(self._largeBuffers[i])
    end
    table.clear(self._largeBuffers)
  end

  local p, e, c = self._mm.commands, self._mm.commands + (ACCSP_FRAME_SIZE - 20), 0
  for i = 1, #self._commands, 2 do
    local key, data = self._commands[i], self._commands[i + 1]
    local dataSize = #data
    if dataSize > ACCSP_MAX_COMMAND_SIZE and p <= e then
      local fileKey = math.randomKey()
      -- ac.warn('Writing large MMF', self._prefix..'_'..fileKey)
      local destination = ac.writeMemoryMappedFile(self._prefix..'_'..fileKey, dataSize + 2)
      if DEBUG_EXCHANGE then ac.log('↑↑', string.char(key), data) end
      destination[0] = key
      copyStringToBinaryData(destination, 1, data, dataSize)
      table.insert(self._largeBuffers, destination)
      PackedCommand.fileKey, PackedCommand.dataSize = fileKey, dataSize + 1
      key, data, dataSize = CommandBE.LargeCommand, ac.structBytes(PackedCommand), 8
    else
      if p + dataSize > e then
        ac.warn('Too many commands at once')
        self._commands = table.slice(self._commands, i)
        ac.memoryBarrier()
        self._mm.commandsSet = c
        return
      end
      if DEBUG_EXCHANGE then ac.log('↑', string.char(key), data) end
    end
    p[0] = key
    writeInt16(p, 1, dataSize)
    copyStringToBinaryData(p, 3, data, dataSize)
    c, p = c + 1, p + (dataSize + 3)
  end
  ac.memoryBarrier()
  self._mm.commandsSet = c
  table.clear(self._commands)
end

---@param self WebBrowser
local function expectReply(self, callback, proc)
  if callback then
    local r = tostring(math.randomKey())
    self._awaiting[r] = proc and function (data)
      callback(proc(data))
    end or callback
    return r
  else
    return ''
  end
end

---@param data boolean|number|string|table|nil
---@param j string?
---@return string
local function serializeItem(data, j)
  local t = type(data)
  if t == 'boolean' then return data and '1' or '0' end
  if t == 'number' or t == 'string' then return tostring(data) end
  if t == 'table' and j then
    local c = {}
    if table.isArray(data) then
      for i = 1, #data do
        c[i] = serializeItem(data[i])
      end
    else
      local n = 1
      for k, v in pairs(data) do
        c[n], c[n + 1], n = k, serializeItem(v), n + 2
      end
    end
    return table.concat(c, j)
  end
  if data == nil then return '' end
  error('Unsupported type: '..t, 2)
end

---@param self WebBrowser
---@param key integer
local function removeCommands(self, key, param)
  for i = #self._commands - 1, 1, -2 do
    if self._commands[i] == key then
      table.remove(self._commands, i + 1)
      table.remove(self._commands, i)
    end
  end
end

---@param self WebBrowser
---@param key integer
---@param param string|boolean|number|table|nil
---@param removeOld boolean?
local function addCommand(self, key, param, removeOld)
  if removeOld then
    removeCommands(self, key)
  end
  table.insert(self._commands, key)
  table.insert(self._commands, serializeItem(param, '\1'))
  submitCommands(self)
end

---@param self WebBrowser
local function addReply(self, replyID, data)
  if replyID == '' then return end
  if tonumber(replyID) == nil then error('Invalid replyID: '..tostring(replyID)) end
  if type(data) == 'table' then
    data = table.chain({replyID}, data)
  else
    data = {replyID, data}
  end
  addCommand(self, CommandBE.Reply, data)
end

---@param self WebBrowser
---@param method string
---@param params table
local function devToolsMessage(self, method, params)
  addCommand(self, CommandBE.DevToolsMessage, {method, JSON.stringify(params)})
end

local CommandData = {
  string = function (dataPtr, dataLength)
    return getStringFromBinaryData(dataPtr, dataLength)
  end,
  char = function (dataPtr)
    return string.char(dataPtr[0])  
  end,
  split = function (dataPtr, dataLength)
    for i = 0, dataLength - 1 do
      if dataPtr[i] == 1 then return getStringFromBinaryData(dataPtr, i), dataPtr + (i + 1), dataLength - (i + 1) end
    end
    return getStringFromBinaryData(dataPtr, dataLength), dataPtr + dataLength, 0
  end,
}

local function awakeRender(self)
  self._mm.needsNextFrame = 3
end

---@param self WebBrowser
---@param url string
---@return WebBrowser.BlankOverride?
---@return string
local function getBlankPage(self, url)
  local h = self._blankHandler
  if not h or url:byte(1) ~= const(string.byte('a')) or not url:startsWith('about:') then return nil, '' end
  local s = url:find('#')
  local k = s and url:sub(s + 1) or url:sub(url:find(':') + 1)
  return h(self, k), k
end

---@param url string
---@return string?
function webBrowser.getBlankID(url)
  if not url or url:byte(1) ~= const(string.byte('a')) or not url:startsWith('about:') then return nil end
  local s = url:find('#')
  return s and url:sub(s + 1) or url:sub(url:find(':') + 1)
end

---@param self WebBrowser
local function processCommand(self, key, dataPtr, dataLength, largeCommand)
  if key == CommandFE.LargeCommand then
    ac.fillStructWithBytes(PackedCommand, CommandData.string(dataPtr, dataLength))
    local filename = self._prefix..'_'..PackedCommand.fileKey
    -- ac.warn('Reading large MMF', filename)
    local data = ac.readMemoryMappedFile(filename, PackedCommand.dataSize)
    processCommand(self, data[0], data + 1, PackedCommand.dataSize - 2, true)
    ac.disposeMemoryMappedFile(data)
    return
  end
  
  if DEBUG_EXCHANGE then 
    ac.log(largeCommand and '↓↓' or '↓', string.char(key), dataLength < 1024 and CommandData.string(dataPtr, dataLength) or '<%d bytes>' % dataLength) 
  end
  if key == CommandFE.RequestReply then
    local k, argPtr, argLength = CommandData.split(dataPtr, dataLength)
    local c = self._awaiting[k]
    if c then
      self._awaiting[k] = nil
      c(CommandData.string(argPtr, argLength))
    else
      ac.warn('Nothing expected a reply with ID='..k)
    end
  elseif key == CommandFE.DataFromScript then
    local replyID, restPtr, restLength = CommandData.split(dataPtr, dataLength)
    local output = nil
    if restLength > 0 then
      local receiverID, argPtr, argLength = CommandData.split(restPtr, restLength)
      local receiver = self._receivers[receiverID]
      if receiver then
        local s, r = pcall(receiver, self, JSON.parse(CommandData.string(argPtr, argLength)))
        if s then output = r end
      else
        ac.warn('No listener', receiverID)
      end
    end
    if replyID ~= '' then
      addReply(self, replyID, JSON.stringify(output))
    end
  elseif key == CommandFE.CSPSchemeRequest then
    local replyID, restPtr, restLength = CommandData.split(dataPtr, dataLength)
    local listener = self._listeners[key]
    local status, mimeType, headers, body
    if listener then 
      local url, method, inHeaders, inBody
      url, restPtr, restLength = CommandData.split(restPtr, restLength)
      method, restPtr, restLength = CommandData.split(restPtr, restLength)
      inHeaders, restPtr, restLength = CommandData.split(restPtr, restLength)
      inBody = CommandData.string(restPtr, restLength)

      local success
      success, status, mimeType, headers, body = pcall(listener, self, url, method, stringify.parse(inHeaders), inBody, function (s, m, h, b)
        if success and status == nil then
          addReply(self, replyID, {tonumber(s) or 200, m and tostring(m) or 'text/html', serializeItem(h, '\2'), b})
        end
      end)
      if success and status == nil then
        return
      elseif not success or type(status) ~= 'number' or status < 100 or status > 999 then
        status, mimeType, body = 500, nil, 'Error: '..status
      end
    else
      status, mimeType, body = 404, nil, 'No listener is set on Lua side. Add `:onCSPSchemeRequest()` handler.'
    end
    if replyID ~= '' then
      addReply(self, replyID, {status, mimeType and tostring(mimeType) or 'text/html', serializeItem(headers, '\2'), body})
    end
  elseif key == CommandFE.DownloadUpdate then
    ac.fillStructWithBytes(DownloadUpdate, CommandData.string(dataPtr, dataLength))
    local item = self._downloadsMap[tonumber(DownloadUpdate.ID)]
    if item then
      local newTotalBytes = tonumber(DownloadUpdate.totalBytes) or 0
      if newTotalBytes > 0 then item.totalBytes = newTotalBytes end
      item.receivedBytes = tonumber(DownloadUpdate.receivedBytes) or 0
      item.currentSpeed = tonumber(DownloadUpdate.currentSpeed) or 0
      if bit.band(DownloadUpdate.flags, 2) ~= 0 then
        item.state = 'cancelled'
      elseif bit.band(DownloadUpdate.flags, 1) ~= 0 then
        item.state = 'complete'
      else
        local l = self._listeners[258]
        if l then l(self, item) end
        return
      end
      self._downloadsMap[item.ID] = nil
      table.removeItem(self._downloadsList, item)
      local l = self._listeners[258]
      if l then l(self, item) end
      l = self._listeners[256]
      if l then l(self, item) end
    end
  elseif key == CommandFE.Audio then
    if dataPtr[0] == const(string.byte('1')) and not self._audio then
      local params = table.assign({use3D = false, reverb = false}, self._settings.audioParameters,
        {stream = {name = self._prefix..'!', size = ACCSP_AUDIO_STEAM_SIZE}})
      self._audio = ac.AudioEvent.fromFile(params,
        self._settings.audioParameters and self._settings.audioParameters.reverb == true)
      ac.log('Audio event created', self:url())
      if not params.use3D then
        self._audio.cameraExteriorMultiplier = 1
        self._audio.cameraInteriorMultiplier = 1
        self._audio.cameraTrackMultiplier = 1
      end
      if self._onAudioEvent then
        self._onAudioEvent(self, self._audio)
        self._onAudioEvent = nil
      end
    end
  else
    -- All these commands will trigger self._listeners
    if key == CommandFE.URL then 
      local url = CommandData.string(dataPtr, dataLength)
      self._pageState = nil
      self._working = true

      if url ~= 'about:blank#blocked' then
        self._loadError = nil
      end
      self._favicon = ''

      local blankHandler = getBlankPage(self, url)
      if self._urlIgnore == url then
        blankHandler = nil
      end
      self._urlIgnore = nil
      if blankHandler then
        self._blankPage = blankHandler
        self._blankPageURL = url
      elseif not self._sourceView then
        self._url = url
        self._domain = ''

        if self._blankPage then
          self._blankHeldPage, self._blankPage = self._blankPage, nil
          awakeRender(self)
          setTimeout(function () 
            local fn = self._blankHeldPage and self._blankHeldPage.onRelease
            if fn then fn() end
            if self._title:startsWith('about:') then self._title = '' end
            self._blankHeldPage = nil
          end, 0.05)
        end
      end
    elseif key == CommandFE.Title then 
      self._title = CommandData.string(dataPtr, dataLength)
    elseif key == CommandFE.Favicon then 
      self._favicon = CommandData.string(dataPtr, dataLength)
      if self._favicon ~= '' then
        faviconCache[self:domain()] = self._favicon
      end
    elseif key == CommandFE.Status then 
      self._status = CommandData.string(dataPtr, dataLength)
    elseif key == CommandFE.Tooltip then 
      self._tooltip = CommandData.string(dataPtr, dataLength)
    elseif key == CommandFE.Close then
      self._suspended = true
    end
    local listener = self._listeners[key]
    local parsed
    if key == CommandFE.LoadStart or key == CommandFE.LoadEnd then
      parsed = stringify.parse(CommandData.string(dataPtr, dataLength))
      self._pageState = parsed
    elseif key == CommandFE.LoadFailed then
      parsed = stringify.parse(CommandData.string(dataPtr, dataLength))
      self._loadError = parsed
    elseif key == CommandFE.VirtualKeyboardRequest then
      parsed = dataLength ~= 0 and CommandData.string(dataPtr, dataLength) or nil
      self._virtualKeyboardRequested = parsed
      if listener then listener(self, parsed) end
      return
    end
    if listener then
      if not parsed then
        local data = CommandData.string(dataPtr, dataLength)
        if key == CommandFE.URLMonitor then
          local e1, e2 = data:byte(#data - 1, #data)
          local blocked = false
          if e1 == 1 then
            data = data:sub(1, #data - 2)
            blocked = e2 == const(string.byte('1'))
          end
          listener(self, data, blocked)
          return
        end
        parsed = not IsCommandFECarriesLSON(key) and data or stringify.parse(data)
      end
      listener(self, parsed)
    end
  end
end

---@param self WebBrowser
local function syncImpl(self)
  self._syncing = true
  local D = self._mm.response
  local dataSize = tonumber(self._mm.responseSet)
  ac.memoryBarrier()
  for _ = 1, dataSize do
    local key = D[0]
    local size = readInt16(D, 1)
    D = D + 3
    processCommand(self, key, D, size, false)
    D = D + size
  end
end

local _drawDisposed
local function disposeImpl(self, restarting)
  if not self._dispose then return end
  if not restarting then table.removeItem(instances, self) end
  if self._texture then 
    self._texture:dispose()
    self._texture = nil
  end
  if self._audio then 
    self._audio:dispose()
    self._audio = nil
  end
  if next(self._downloadsList) then
    local list = self._downloadsList
    self._downloadsMap = {}
    self._downloadsList = {}
    for _, v in ipairs(list) do
      v.state = 'cancelled'
      v.currentSpeed = 0
      local l = self._listeners[258]
      if l then l(self, v) end
      l = self._listeners[256]
      if l then l(self, v) end
    end
  end
  if not restarting then
    self._gc = nil
    self._release()
  end
  self._dispose()
  self._dispose = nil

  if not restarting then
    self.draw = _drawDisposed
    self.crash = function () return {errorCode = 21, errorText = 'ERR_ACEF_DISPOSED', errorDescription = 'This instance was disposed'} end
  end
end

---Restarts tab. Might not always work perfectly (for example, if you were running custom developer tools commands, their effect might get lost). Can
---help in extreme cases though, such as when backend crashes.
---@return WebBrowser
function webBrowser:restart()
  local url, scroll = self._url == '' and self._blankPageURL ~= '' and self._blankPageURL or self._url, self:scroll().y
  if self._blankPage then
    url = self._blankPageURL or url
  end

  self._settings.size = self:size()
  local zoomOld = self._mm.zoomLevel
  disposeImpl(self, true)
  if self._mm then
    ac.disposeMemoryMappedFile(self._mm)
  end
  self._mm, self._prefix, self._dispose = initWebHost(self._settings)
  self._mm.handle = 0
  self._dragging = false
  self._commands = table.clone(self._initCommands or {}, false)
  
  self._lastHandle = -1
  self._lastPopupHandle = -1

  self._status = ''
  self._tooltip = ''
  self._initializing = true
  self._blankPage = nil
  self._blankHeldPage = nil

  local bak
  if self._pixelDensity ~= 1 then
    bak, self._pixelDensity = self._pixelDensity, nil
    self:setPixelDensity(bak)
  end
  if self._colorScheme ~= nil then
    bak, self._colorScheme = self._colorScheme, nil
    self:setColorScheme(bak)
  end
  if self._mobileMode ~= nil then
    bak, self._mobileMode = self._mobileMode, nil
    self:setMobileMode(bak)
  end
  if zoomOld ~= 0 then
    self:setZoom(zoomOld)
  end
  if self._timezone ~= nil then
    bak, self._timezone = self._timezone, nil
    self:setTimezone(bak)
  end
  if self._forceVisible ~= nil then
    bak, self._forceVisible = self._forceVisible, nil
    self:forceVisible(bak)
  end
  if self._scrollbarsHidden ~= nil then
    bak, self._scrollbarsHidden = self._scrollbarsHidden, nil
    self:hideScrollbars(bak)
  end
  if self._muted ~= nil then
    bak, self._muted = self._muted, nil
    self:mute(bak)
  end
  if self._blockURLs ~= nil then
    bak, self._blockURLs = self._blockURLs, nil
    self:blockURLs(bak)
  end
  if self._ignoreCertificateErrors ~= nil then
    bak, self._ignoreCertificateErrors = self._ignoreCertificateErrors, nil
    self:ignoreCertificateErrors(bak)
  end
  if self._userAgent ~= nil then
    self:setUserAgent(self._userAgent)
  end
  if self._cacheDisabled then
    self._cacheDisabled = false
    self:disableCache(true)
  end
  if self._networkConditions then
    self:emulateNetworkConditions(self._networkConditions)
  end
  if self._listeners[CommandFE.URLMonitor] then
    addCommand(self, CommandBE.SetOption, {'collectResourceURLs', true})
  end
  if self._headers then
    local t = stringify.binary.parse(self._headers)
    if type(t) == 'table' then self:setHeaders(t) end
  end
  if self._injectJavaScript then
    local t = stringify.binary.parse(self._injectJavaScript)
    if type(t) == 'table' then self:injectJavaScript(t) end
  end
  if self._injectStyle then
    local t = stringify.binary.parse(self._injectStyle)
    if type(t) == 'table' then self:injectStyle(t) end
  end

  self:navigate(url)
  if scroll ~= 0 then
    self:scrollTo(0, scroll)
  end

  if self._suspended then
    self._suspended = nil
    self:suspend(true)
  end

  setTimeout(function ()
    self._initializing = false
    submitCommands(self)
  end)
  return self
end

---@param self WebBrowser
local function getResizePaddingColor(self)
  if not self._settings.backgroundColor or self._settings.backgroundColor.mult < 0.5 then
    return rgbm.colors.transparent
  end
  return self._settings.backgroundColor:luminance() < 0.5 and self._settings.backgroundColor or rgbm.colors.gray
end

---@param settings WebBrowser.Settings
function webBrowser:initialize(settings)
  -- Flag `externalBeginFrameEnabled` makes things slow, but stable. Seems like when using externalBeginFrameEnabled, 
  -- sometimes OAP2 is simply not being called despite calling SendExternalBeginFrame()?
  
  self._uuid = math.randomKey()
  settings = table.assign({size = vec2(800, 480), directRender = true}, settings, {UUID = self._uuid, externalBeginFrameEnabled = 0})
  self._settings = settings ---@type WebBrowser.Settings
  self.attributes = settings.attributes or {} ---Store of all your user data needs associated with the browser here.
  self._mm, self._prefix, self._dispose = initWebHost(settings)
  self._mm.handle = 0
  self._dragging = false
  self._commands = {}
  self._largeBuffers = {}
  self._listeners = {}
  self._receivers = {}
  self._awaiting = {}
  self._downloadsList = {} ---@type WebBrowser.DownloadItem[]
  self._downloadsMap = {} ---@type WebBrowser.DownloadItem[]
  self._emptyMode = 'message'
  self._url = ''
  self._title = ''
  self._favicon = ''
  self._domain = ''
  self._status = ''
  self._tooltip = ''
  self._queued = -1
  self._pixelDensity = 1
  self._syncing = false
  self._initializing = true
  self._blankPage = nil
  self._blankHeldPage = nil
  self._virtualKeyboardRequested = nil
  self._audio = nil ---@type ac.AudioEvent?
  self._resizePaddingColor = getResizePaddingColor(self)
  instances[#instances + 1] = self

  setTimeout(function ()
    self._initializing = false
    self._initCommands = table.clone(self._commands, false)
    submitCommands(self)
  end)

  -- Prebound functions to reduce GC load
  self._syncStep1 = function () syncImpl(self) end
  self._syncStep2 = function ()
    ac.memoryBarrier()
    self._mm.responseSet = 0
    self._syncing = false
  end

  -- Default handler for events returning a reply returning nothing
  self._listeners[CommandFE.JavaScriptDialog] = function (s, data) addReply(s, data.replyID, {false, nil}) end
  self._listeners[CommandFE.AuthCredentials] = function (s, data) addReply(s, data.replyID, nil) end
  self._listeners[CommandFE.FileDialog] = function (s, data) addReply(s, data.replyID, nil) end
  self._listeners[CommandFE.Download] = function (s, data) addReply(s, data.replyID, nil) end

  -- A simple way to collect garbage collected browsers which didn’t have `:dispose()` called on them
  self._gc = newproxy(true)
  getmetatable(self._gc).__gc = function (s)
    if not self._gc then
      ac.warn('WebBrowser was properly disposed')
    elseif self._gc ~= s then
      ac.error('WebBrowser got GCed in the wrong time!')
    else
      ac.warn('WebBrowser got GCed')
      disposeImpl(self, false)
    end
  end
  self._release = ac.onRelease(function (i) i:dispose() end, self)
end

---@param handler fun(browser: WebBrowser, url: string): WebBrowser.BlankOverride?
---@return WebBrowser
function webBrowser:setBlankHandler(handler)
  self._blankHandler = handler
  return self
end

---Change user agent live. Could be called once when creating a webpage.
---@param userAgent string @Pass “{}” and it’ll be replaced with default user agent prefix with browser version. Recommended value: `'{} MyAppName/1.0'`.
---@return WebBrowser
function webBrowser:setUserAgent(userAgent)
  if not userAgent then error('Argument is required', 2) end
  userAgent = userAgent:replace('{}', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.134 Safari/537.36')
  self._userAgent = userAgent
  devToolsMessage(self, 'Emulation.setUserAgentOverride', {userAgent = tostring(userAgent)})
  return self
end

---Clears browser cache (using a developer tools command).
---@return WebBrowser
function webBrowser:clearCache()
  devToolsMessage(self, 'Emulation.clearBrowserCache', {})
  return self
end

---Clears browser cookies (using a developer tools command).
---@return WebBrowser
function webBrowser:clearCookies()
  devToolsMessage(self, 'Emulation.clearBrowserCookies', {})
  return self
end

---@return WebBrowser
function webBrowser:disableCache(disabled)
  disabled = disabled ~= false
  if disabled ~= (self._cacheDisabled or false) then
    self._cacheDisabled = disabled
    devToolsMessage(self, 'Emulation.setCacheDisabled', {cacheDisabled = disabled})
  end
  return self
end

---@return boolean
function webBrowser:cacheDisabled()
  return self._cacheDisabled or false
end

---@param params {offline: boolean?, latencyMs: integer?, downloadSpeedBytesPerSecond: integer?, uploadSpeedBytesPerSecond: integer?}?
---@return WebBrowser
function webBrowser:emulateNetworkConditions(params)
  self._networkConditions = params
  params = params or {}
  devToolsMessage(self, 'Emulation.emulateNetworkConditions', {
    offline = params.offline == true, 
    latency = tonumber(params.latencyMs) or 0, 
    downloadThroughput = tonumber(params.downloadSpeedBytesPerSecond) or -1, 
    uploadThroughput = tonumber(params.uploadSpeedBytesPerSecond) or -1
  })
  return self
end

---Switch to mobile mode with thin scrollbars and different zooming logic.
---@param mode nil|'portrait'|'landscape'
---@return self
function webBrowser:setMobileMode(mode)
  if self._mobileMode ~= mode then
    self._mobileMode = mode
    devToolsMessage(self, 'Emulation.setDeviceMetricsOverride', {
      width = 0, height = 0, deviceScaleFactor = 0, mobile = mode ~= nil, 
      screenOrientation = {type = mode == 'landscape' and 'landscapePrimary' or 'portraitPrimary', angle = 0}
    })
  end
  return self
end

---@return nil|'portrait'|'landscape'
function webBrowser:mobileMode()
  return self._mobileMode
end

---Set preferred color scheme. Call with `'dark'` to switch supporting websites to dark mode. Default mode is light. Mode `'dark-auto'` applies forced dark theme
---to all websites. Mode `'dark-forced'` changes default background, text and inputs style as well as scrollbar style. Both `'dark-forced'` and `'dark-auto'` might break some poorly made websites, so use carefully.
---@param colorScheme 'light'|'dark'|'dark-forced'|'dark-auto'
---@return self
function webBrowser:setColorScheme(colorScheme)
  if (self._colorScheme or 'light') ~= colorScheme then
    self._colorScheme = colorScheme
    addCommand(self, CommandBE.ColorScheme, colorScheme)
  end
  return self
end

---@return 'light'|'dark'|'dark-forced'|'dark-auto'
function webBrowser:colorScheme()
  return self._colorScheme or 'light'
end

---@param suspend boolean? @Default value: `true`.
---@return self
function webBrowser:suspend(suspend)
  suspend = suspend ~= false
  if suspend ~= (self._suspended or false) then
    self._suspended = suspend
    addCommand(self, CommandBE.Lifespan, suspend and 'suspend' or 'resume')
  end
  return self
end

---@param self WebBrowser
local function backendUnresponsive(self)
  return sim.systemTime - self._mm.beAliveTime > 4
end

---Tries to close browser nicely, asking JavaScript if it wants to complete its thing, etc. If successful, `:onClose()` callback will be called. From it
---you can either `:dispose()` the browser, or keep a reference to it for later and call `:suspend(false)` to restore it when needed (for example, if
---there is an active download happening and you don’t want to cancel it closing browser).
---@return self
function webBrowser:tryClose()
  if connect.cefState ~= 0 or self:disposed() or backendUnresponsive(self) then
    local listener = self._listeners[CommandFE.Close]
    if listener then 
      setTimeout(listener ^ self)
    else
      ac.warn('No listener for close event is set')
    end
  else
    addCommand(self, CommandBE.Lifespan, 'close')
  end
  return self
end

---@return boolean
function webBrowser:suspended()
  return self._suspended or false
end

---Definitely wouldn’t hurt to call this function once browser is no longer needed (but, as usual, no need to call it if your script is shutting down).
function webBrowser:dispose()
  disposeImpl(self, false)
end

---Sets a callback which will be called when an audio event is created. Available only if browser was created with `redirectAudio`
---parameter set to `true`. Can be used for things like positioning audio in space (add
---`audioParameters = { use3D = true, reverb = true, … }` to browser settings during creation to tweak audio settings further.
---@param callback fun(browser: WebBrowser, event: ac.AudioEvent)
---@return self
function webBrowser:onAudioEvent(callback)
  if not self._settings.redirectAudio then error('Can only be called if “redirectAudio” in settings is set to `true`', 2) end
  if self._audio then
    setTimeout(function ()
      if self._audio then callback(self, self._audio) end
    end)
  else
    self._onAudioEvent = callback
  end
  return self
end

---Returns `true` if audio is currently playing. Available only if browser was created with `redirectAudio` parameter set to `true`.
---@return boolean
function webBrowser:playingAudio()
  return not self._muted and bit.band(self._mm.beFlags, 256) ~= 0
end

---Available only if browser was created with `redirectAudio` parameter set to `true`.
---@return number @Peak from 0 to 1.
function webBrowser:audioPeak()
  return self._muted and 0 or self._mm.audioPeak / 255
end

---@param self WebBrowser
local function sync(self)
  if self._mm.responseSet > 0 and self._dispose and not self._syncing then
    using(self._syncStep1, self._syncStep2)
  end
  if not self._crashReported and self._listeners[260] then
    local crash = self:crash()
    if crash then
      self._crashReported = true
      self._listeners[260](self, crash)
    end
  end
end

---Navigate to a certain URL, or just back or forward.
---@param url 'back'|'forward'|string @URL to load, or a command.
---@return self
function webBrowser:navigate(url)
  if not url:startsWith('javascript:') then
    local blankPage, blankID = getBlankPage(self, url)
    self._sourceView = url:startsWith('view-source:')
    if not blankPage and (self._sourceView or connect.cefState ~= 0) then
      self._url = url
      if connect.cefState ~= 0 then
        self._title = ''
        self._favicon = ''
        self._blankPage = nil
        self._blankHeldPage = nil
        self._domain = webBrowser.getDomainName(url)
        removeCommands(self, CommandBE.Navigate)
      end
    else
      if blankPage then
        url = blankPage.url
      end
      if self._url == '' or self._blankPage then
        if self._blankPage then
          self._urlIgnore = self._blankPageURL
          self._title = ''
        end
        self._url = url
      end
      self._pageState = nil
      self._loadError = nil
      if blankPage then
        self._blankPage = blankPage
        self._blankHeldPage = nil
        url = webBrowser.blankURL(blankID)
        self._blankPageURL = url
      else
        self._favicon = ''
      end
    end
  end
  addCommand(self, CommandBE.Navigate, url)
  return self
end

---@return boolean
function webBrowser:showingSourceCode()
  return not not self._sourceView
end

---Called if `:reload()` is called on a page loaded with POST data. If you need to reload anyway, call `callback`. If not set, browser will not reload.
---@param listener fun(browser: WebBrowser, callback: fun())
---@return self
function webBrowser:onFormResubmission(listener)
  self._listeners[259] = listener
  return self
end

---Reload current webpage.
---@param full boolean? @Set to `true` to ignore cache. Default value: `false`.
---@return self
function webBrowser:reload(full)
  if connect.cefState ~= 0 then
    if connect.cefState < 10 then
      ac.log('Can’t reload during initialization')
    else
      ac.log('Requesting a restart')
      webBrowser.restartProcess()
    end
  elseif backendUnresponsive(self) then
    ac.log('Backend seems to be dead for more than %s seconds, restarting…' % (sim.systemTime - self._mm.beAliveTime))
    webBrowser.restartProcess()
  elseif self._suspended then
    self:suspend(false)
  elseif self:postedData() then
    local l = self._listeners[259]
    if l then
      l(self, function ()
        self._pageState = nil
        self._loadError = nil
        addCommand(self, CommandBE.Reload, full and 'nocache' or '')
      end)
    end
  else
    self._pageState = nil
    self._loadError = nil
    addCommand(self, CommandBE.Reload, full and 'nocache' or '')
  end
  return self
end

---Stop current loading.
---@return self
function webBrowser:stop()
  if connect.cefState == 0 then
    addCommand(self, CommandBE.Stop, nil, true)
  end
  return self
end

---Set a piece of CSS to be injected early into loaded pages. Only affects pages with `text/html` MIME type (and ignores URLs ending with “.js” to avoid breaking some poorly configured websites).
---@param styles table<string, string>? @Key: regex to test against URL of a webpage being loaded. Value: CSS code itself (has to be valid code).
---@return self
function webBrowser:injectStyle(styles)
  self._injectStyle = stringify.binary(styles)
  addCommand(self, CommandBE.InjectStyle, styles, true)
  return self
end

---Set a piece of HTML to be injected early into loaded pages. Only affects pages with `text/html` MIME type (and ignores URLs ending with “.js” to avoid breaking some badly set up websites).
---@param code table<string, string>? @Key: regex to test against URL of a webpage being loaded. Value: JavaScript code itself (has to be valid code, should not contain “</script>”).
---@return self
function webBrowser:injectJavaScript(code)
  self._injectJavaScript = stringify.binary(code)
  removeCommands(self, CommandBE.InjectJavaScript)
  addCommand(self, CommandBE.InjectJavaScript, code, true)
  return self
end

---Extends and replaces original headers with ones provided in the table.
---@param headers table<string, table<string, string>>? @URL regex for a key with a key-value table for headers.
---@return self
function webBrowser:setHeaders(headers)
  local d, n = {}, 1
  self._headers = stringify.binary(headers)
  for u, p in pairs(headers or {}) do
    if next(p) then
      if n > 1 then d[n], n = '\1', n + 1 end
      d[n], n = u, n + 1
      d[n], n = '\1', n + 1
      local f = false
      for k, v in pairs(p) do
        if f then d[n], n = '\2', n + 1 else f = true end
        d[n], n = k, n + 1
        d[n], n = '\2', n + 1
        d[n], n = v, n + 1
      end
    end
  end
  addCommand(self, CommandBE.SetHeaders, table.concat(d), true)
  return self
end

---Runs a piece of JavaScript in the main frame. Use `AC.send()` to send data back to Lua if needed.
---@param javaScript string @JavaScript code to execute.
---@return self
function webBrowser:execute(javaScript)
  addCommand(self, CommandBE.Execute, javaScript)
  return self
end

---Create new browser with developer tools for this one.
---@param settings WebBrowser.Settings?
---@param inspect vec2? @Inspection point.
---@return WebBrowser
function webBrowser:devTools(settings, inspect)  
  return webBrowser(table.assign({}, settings, {
    backgroundColor = rgbm.colors.white,
    devTools = self._uuid,
    devToolsInspect = inspect and '%d,%d' % {inspect.x, inspect.y},
  }))
end

---Apply a developer tools command.
---@param method string
---@param params table
---@return WebBrowser
function webBrowser:devToolsCommand(method, params)
  --[[
    Some interesting commands:
    :devToolsCommand('Overlay.setShowFPSCounter', {show = true})
  ]]
  devToolsMessage(self, method, params)
  return self
end

---Send focus event.
---@param focus boolean? @Default value: `true`.
---@return self
function webBrowser:focus(focus)
  self._mm.feFlags = bit.bor(focus ~= false and 1 or 0, bit.band(self._mm.feFlags, bit.bnot(1)))
  return self
end

---Returns `true` if browser is currently focused.
---@return boolean
function webBrowser:focused()
  return bit.band(self._mm.feFlags, 1) ~= 0
end

---Override background color.
---Note: use `ui.beginPremultipliedAlphaTexture()`/`ui.endPremultipliedAlphaTexture()` if you want your browser to be semi-transparent.
---@param color rgbm
---@return self
function webBrowser:setBackgroundColor(color)
  if color and color ~= self._settings.backgroundColor then
    self._settings.backgroundColor = color
    self._resizePaddingColor = getResizePaddingColor(self)
    self:devToolsCommand('Emulation.setDefaultBackgroundColorOverride', {color = {r=color.rgb.r * 255, g=color.rgb.g * 255, b=color.rgb.b * 255, a=color.mult}})
    if color.mult < 1 then
      addCommand(self, CommandBE.SetOption, {'invalidateView', '1'})
    end
  end
  return self
end

---@return rgbm
function webBrowser:backgroundColor()
  return self._settings.backgroundColor or rgbm.colors.transparent
end

---Invert of a background color, or white if background color is transparent.
---@return rgbm
function webBrowser:contentColor()
  return self._settings.backgroundColor and self._settings.backgroundColor.rgb:value() > 0.5 and rgbm.colors.black or rgbm.colors.white
end

---@param hide boolean? @Default value: `true`.
---@return self
function webBrowser:hideScrollbars(hide)
  hide = hide ~= false
  if hide ~= self._scrollbarsHidden then
    devToolsMessage(self, 'Emulation.setScrollbarsHidden', {hidden = hide})
    self._scrollbarsHidden = hide
  end
  return self
end

---@return boolean
function webBrowser:scrollbarsHidden()
  return self._scrollbarsHidden or false
end

---Override current timezone.
---@param timezoneID string @Timezone in “Country/City” format.
---@return self
function webBrowser:setTimezone(timezoneID)
  timezoneID = timezoneID or ''
  if self._timezone ~= timezoneID then
    self._timezone = timezoneID
    self:devToolsCommand('Emulation.setTimezoneOverride', {timezoneId = timezoneID})
  end
  return self
end

---Look for some text on the webpage.
---@param text string? @Text to look for. Pass empty string to stop the search.
---@param forward boolean? @Default value: `true`.
---@param matchCase boolean? @Default value: `false`.
---@param findNext boolean? @Default value: `false`.
---@return self
function webBrowser:find(text, forward, matchCase, findNext)
  if connect.cefState == 0 then
    addCommand(self, CommandBE.Find, string.format('%s%s%s%s', forward ~= false and '1' or '0', matchCase and '1' or '0', findNext and '1' or '0', text or ''))
  end
  return self
end

---Switch muted state.
---@param muted boolean? @Default value: `true`.
---@return self
function webBrowser:mute(muted)
  muted = muted ~= false
  if muted ~= self._muted then
    self._muted = muted
    addCommand(self, CommandBE.Mute, muted, true)
  end
  return self
end

---Browser will proceed even if SSL is not working as it should for requests matching this regular expression. Use carefully!
---@param ignore string? @Regular expression for request URLs to be tested against (use `.` to ignore any errors everywhere). Pass `nil` to re-enable default behavior.
---@return self
function webBrowser:ignoreCertificateErrors(ignore)
  if self._ignoreCertificateErrors ~= ignore then
    self._ignoreCertificateErrors = ignore
    addCommand(self, CommandBE.SetOption, {'ignoreCertificateErrors', ignore})
  end
  return self
end

---Change pixel density. Could be used to simulate high-density screens (like smartphone displays) by setting smaller browser resolution but higher density.
---@param value number? @New pixel density (set below 1 to render things faster with lower resolution).
---@return self
function webBrowser:setPixelDensity(value)
  value = tonumber(value) or 1
  if self._pixelDensity ~= value then
    addCommand(self, CommandBE.SetOption, {'scaleFactor', value})
    self._pixelDensity = value
  end
  return self
end

---Return current pixel density. By default the value is 1.
---@return number
function webBrowser:pixelDensity()
  return self._pixelDensity
end

---Blocks all requests that match given filter. Good for speeding things up. Use `:collectURLs()` if you need to see what are the URLs that are being loaded.
---@param regex string? @Regular expression for blocking out some requests. Pass `nil` or an empty string to disable.
---@return self
function webBrowser:blockURLs(regex)
  if self._blockURLs ~= regex then
    self._blockURLs = regex
    addCommand(self, CommandBE.FilterResourceURLs, regex, true)
  end
  return self
end

---Set a listener for request URLs being send. Useful to collect some data for blocking unnecessary overhead requests with `:blockURLs()`.
---@param listener fun(browser: WebBrowser, url: string, blocked: boolean)? @Function receiving URLs being loaded.
---@return self
function webBrowser:collectURLs(listener)
  self._listeners[CommandFE.URLMonitor] = listener
  addCommand(self, CommandBE.SetOption, {'collectResourceURLs', listener ~= nil})
  return self
end

---@alias WebBrowser.FormData {actionURL: string, originURL: string, form: table<string, {type: string, value: string}>}
---@alias WebBrowser.Handler.FormData fun(browser: WebBrowser, data: WebBrowser.FormData)

---Set a listener for some POST requests with form data present. Experimental and might not always work.
---@param listener WebBrowser.Handler.FormData?
---@return self
function webBrowser:collectFormData(listener)
  self._listeners[CommandFE.FormData] = listener
  addCommand(self, CommandBE.SetOption, {'trackFormData', listener ~= nil})
  return self
end

function webBrowser:fillForm(actionURL, data)
  if connect.cefState == 0 then
    addCommand(self, CommandBE.FillForm, {actionURL, serializeItem(data, '\1')})
  end
end

---@alias OpenDisposition 'currentTab'|'singletonTab'|'newForegroundTab'|'newBackgroundTab'|'newPopup'|'newWindow'|'saveToDisk'|'offTheRecord'|'ignoreAction'|'unknown'
---@alias WebBrowser.Handler.Open fun(browser: WebBrowser, data: {userGesture: boolean, originalURL: string, targetURL: string, targetDisposition: OpenDisposition})

---Set a listener for when there is a new URL being opened which might be better opened in a new tab. If listener is not `nil`, disables default behaviour (opening page in the current tab). 
---@param listener WebBrowser.Handler.Open?
---@return self
function webBrowser:onOpen(listener)
  self._listeners[CommandFE.OpenURL] = listener
  addCommand(self, CommandBE.SetOption, {'redirectNavigation', listener ~= nil})
  return self
end

---@alias WebBrowser.Handler.Popup fun(browser: WebBrowser, data: {userGesture: boolean, originalURL: string, targetURL: string, targetFrameName: string, targetDisposition: OpenDisposition, features: {width: integer?, height: integer?, x: integer?, y: integer?, menuBarVisible: boolean, statusBarVisible: boolean, toolBarVisible: boolean, scrollbarsVisible: boolean}})

---Set a listener for popup windows. By default all of them are simply blocked.
---@param listener WebBrowser.Handler.Popup? 
---@return self
function webBrowser:onPopup(listener)
  self._listeners[CommandFE.Popup] = listener
  return self
end

---@alias WebBrowser.Handler.AuthCredentials fun(browser: WebBrowser, data: {host: string, port: integer, realm: string, scheme: 'basic'|'digest'|string, proxy: boolean, originURL: string}, callback: fun(username: string?, password: string?))

---Set a listener for auth dialogs (basic HTTP auth). Return `nil` to the callback to cancel.
---@param listener WebBrowser.Handler.AuthCredentials? 
---@return self
function webBrowser:onAuthCredentials(listener)
  self._listeners[CommandFE.AuthCredentials] = listener and function (s, data)
    listener(s, data, function (username, password)
      addReply(s, data.replyID, username and {username, password} or nil)
      data.replyID = ''
    end)
  end or function (s, data) addReply(s, data.replyID, nil) end
  return self
end

---@alias WebBrowser.Handler.JavaScriptDialog fun(browser: WebBrowser, data: {type: 'alert'|'confirm'|'prompt'|'beforeUnload', message: string, defaultPrompt: string?, originURL: string?, reload: boolean?}, callback: fun(success: boolean, data: string?))

---Set a listener for JavaScript dialogs. By default all of them are ignored.
---@param listener WebBrowser.Handler.JavaScriptDialog? @Field `defaultPrompt` is only for `prompt` type. For `beforeUnload` type, there will be no `originURL` field, but there will be `reload` flag.
---@return self
function webBrowser:onJavaScriptDialog(listener)
  self._listeners[CommandFE.JavaScriptDialog] = listener and function (s, data)
    listener(s, data, function (success, ret)
      addReply(s, data.replyID, {success, ret})
      data.replyID = ''
    end)
  end or function (s, data) addReply(s, data.replyID, {false, nil}) end
  return self
end

---@alias WebBrowser.Handler.FileDialog fun(browser: WebBrowser, data: {type: 'open'|'openMultiple'|'openFolder'|'save', title: string?, defaultFilePath: string?, acceptFilters: string[]}, callback: fun(selectedFilePaths: string[]?))

---Set a listener for file dialogs. By default all of them are ignored.
---@param listener WebBrowser.Handler.FileDialog? 
---@return self
function webBrowser:onFileDialog(listener)
  self._listeners[CommandFE.FileDialog] = listener and function (s, data)
    listener(s, data, function (selectedFilePaths)
      addReply(s, data.replyID, selectedFilePaths)
      data.replyID = ''
    end)
  end or function (s, data) addReply(s, data.replyID, nil) end
  return self
end

---@alias WebBrowser.VirtualKeyboardMode nil|'default'|'text'|'tel'|'url'|'email'|'numeric'|'decimal'|'search'
---@alias WebBrowser.Handler.VirtualKeyboardRequest fun(browser: WebBrowser, data: WebBrowser.VirtualKeyboardMode)

---Set a listener for keyboard request.
---@param listener WebBrowser.Handler.VirtualKeyboardRequest?
---@return self
function webBrowser:onVirtualKeyboardRequest(listener)
  self._listeners[CommandFE.VirtualKeyboardRequest] = listener
  return self
end

---@return WebBrowser.VirtualKeyboardMode
function webBrowser:requestedVirtualKeyboard()
  return self._virtualKeyboardRequested
end

---Start a new download. Make sure to set `:onDownload()` listener so you can specify location and track the download process.
---@return self
function webBrowser:download(url)
  addCommand(self, CommandBE.Download, url)
  return self
end

---List of the active downloads, ordered from oldest to newest. Once download is complete or cancelled, it’ll be removed and send to `:onDownloadFinished()` listener.
---@return WebBrowser.DownloadItem[]
function webBrowser:downloads()
  return self._downloadsList
end

---@alias WebBrowser.Handler.Download fun(browser: WebBrowser, data: WebBrowser.DownloadQuery, callback: fun(downloadPath: string?))

---Set a listener for new downloads (which by default are simply ignored).
---@param listener WebBrowser.Handler.Download?
---@return self
function webBrowser:onDownload(listener)
  self._listeners[CommandFE.Download] = listener and function (s, data)
    listener(s, data, function (downloadPath)
      if downloadPath then
        data.attributes = {}
        data.currentSpeed = 0
        data.receivedBytes = 0
        data.state = 'loading'
        data.destination = downloadPath
        data.control = function (i, newState)
          if s:disposed() then
            i.state = 'cancelled'
            i.currentSpeed = 0
          else
            if i.state == 'loading' or i.state == 'paused' then
              if newState == 'pause' then
                i.state = 'paused'
              elseif newState == 'resume' then
                i.state = 'loading'
              end
              addCommand(s, CommandBE.ControlDownload, {i.ID, newState:sub(1, 1)})
            end
          end
        end
        table.insert(s._downloadsList, data)
        s._downloadsMap[data.ID] = data
        local fn = s._listeners[257]
        if fn then fn(s, data) end
      end
      addReply(s, data.replyID, downloadPath)
      data.replyID = ''
    end)
  end or function (s, data) addReply(s, data.replyID, nil) end
  return self
end

---@alias WebBrowser.Handler.DownloadStarted fun(browser: WebBrowser, data: WebBrowser.DownloadItem))
---@param listener WebBrowser.Handler.DownloadStarted?
---@return self
function webBrowser:onDownloadStarted(listener)
  self._listeners[257] = listener
  return self
end

---@alias WebBrowser.Handler.DownloadUpdated fun(browser: WebBrowser, data: WebBrowser.DownloadItem))
---@param listener WebBrowser.Handler.DownloadUpdated?
---@return self
function webBrowser:onDownloadUpdated(listener)
  self._listeners[258] = listener
  return self
end

---@alias WebBrowser.Handler.DownloadFinished fun(browser: WebBrowser, data: WebBrowser.DownloadItem))
---@param listener WebBrowser.Handler.DownloadFinished?
---@return self
function webBrowser:onDownloadFinished(listener)
  self._listeners[256] = listener
  return self
end

---@alias WebBrowser.Handler.ContextMenu fun(browser: WebBrowser, data: {originURL: string, x: integer, y: integer, editable: boolean, sourceURL: string?, linkURL: string?, unfilteredLinkURL: string?, selectedText?: string})

function webBrowser:triggerContextMenu()
  local fn = self._listeners[CommandFE.ContextMenu]
  if fn then
    fn(self, {originURL = self._url, x = 0, y = 0, editable = false})
  end
  return self
end

---Set a listener for context menu event.
---@param listener WebBrowser.Handler.ContextMenu?
---@return self
function webBrowser:onContextMenu(listener)
  self._listeners[CommandFE.ContextMenu] = listener
  return self
end

---Set a listener for found result.
---@param listener fun(browser: WebBrowser, data: {identifier: integer, index: integer, count: integer, final: boolean, rect: {x: number, y: number, width: number, height: number}})?
---@return self
function webBrowser:onFoundResult(listener)
  self._listeners[CommandFE.FoundResult] = listener
  return self
end

---Set a listener for loading starts.
---@param listener fun(browser: WebBrowser, data: WebBrowser.PageState)?
---@return self
function webBrowser:onLoadStart(listener)
  self._listeners[CommandFE.LoadStart] = listener
  return self
end

---Set a listener for loading completions.
---@param listener fun(browser: WebBrowser, data: WebBrowser.PageState)?
---@return self
function webBrowser:onLoadEnd(listener)
  self._listeners[CommandFE.LoadEnd] = listener
  return self
end

---Set a listener for loading failures.
---@param listener fun(browser: WebBrowser, data: WebBrowser.LoadError)?
---@return self
function webBrowser:onLoadError(listener)
  self._listeners[CommandFE.LoadFailed] = listener
  return self
end

---Set a listener for engine crashes.
---@param listener fun(browser: WebBrowser, data: WebBrowser.Crash)?
---@return self
function webBrowser:onCrash(listener)
  self._listeners[260] = listener
  return self
end

---Prevents navigating webpages with URLs matching given regular expression, with optional callback. Could be used for redirecting custom URL schemes. If so, list of standard schemes you might not want to redirect: https, ftp, file, data, blob, about, chrome, chrome-extension, javascript, ac.
---@param listener fun(browser: WebBrowser, data: {originURL: string, targetURL: string, userGesture: boolean, redirect: boolean})?
---@return self
function webBrowser:preventNavigation(regex, listener)
  self._listeners[CommandFE.CustomSchemeBrowse] = listener
  addCommand(self, CommandBE.SetOption, {'redirectNonStandardSchemes', regex})
  return self
end

---@param dx number?
---@param dy number?
---@return self
function webBrowser:scrollBy(dx, dy)
  addCommand(self, CommandBE.Scroll, {false, math.round(dx or 0), math.round(dy or 0)})
  return self
end

---@param tx number?
---@param ty number?
---@return self
function webBrowser:scrollTo(tx, ty)
  addCommand(self, CommandBE.Scroll, {true, math.round(tx or 0), math.round(ty or 0)})
  return self
end

---Set a listener for a request sent to “ac://” protocol. You can use it to implement custom backend, exchange data with JavaScript, provide assets and such.
---@param listener nil|fun(browser: WebBrowser, url: string, method: 'GET'|'POST'|string, headers: table, body: string, callback: fun(status: integer, mimeType: string?, headers: table?, body: binary?)): integer?, string?, table?, binary? @Expected to return HTTP status code, mime type, optional table with headers and the response. Alternatively, return a single `nil` and call the `callback` later instead if your response is computed asyncronously.
---@return self
function webBrowser:onCSPSchemeRequest(listener)
  self._listeners[CommandFE.CSPSchemeRequest] = listener
  return self
end

---Set a listener for JavaScript sending data back with `AC.send(<string>)` function.
---@param listener nil|fun(browser: WebBrowser, data: number|boolean|string|table?): number|boolean|string|table
---@return WebBrowser
function webBrowser:onReceive(key, listener)
  self._receivers[key] = listener
  return self
end

---Set a listener for when URL changes.
---@param listener fun(browser: WebBrowser, data: string)? @Function that will be called.
---@return self
function webBrowser:onURLChange(listener)
  self._listeners[CommandFE.URL] = listener
  return self
end

---Set a listener for when title changes.
---@param listener fun(browser: WebBrowser, data: string)? @Function that will be called.
---@return self
function webBrowser:onTitleChange(listener)
  self._listeners[CommandFE.Title] = listener
  return self
end

---Set a listener for when it’s time for web browser to close. Generally speaking you wouldn’t need it, just `:dispose()` when it’s no longer needed, but if you want better support for webpages which might, for example, warn users about unsaved data, you can instead just call `:tryClose()` and dispose browser from this callback instead. 
---Note: simply calling `:dispose()`, or having browser to be garbage collected won’t trigger this callback. Also, if once you are done with browser in this
---callback, make sure to call `:dispose()` or it’ll wait for GC to clean things up.
---@param listener fun(browser: WebBrowser)? @Function that will be called.
---@return self
function webBrowser:onClose(listener)
  self._listeners[CommandFE.Close] = listener
  return self
end

---Send data to JavaScript that will arrive to a function set with `AC.onReceive(key, callback)`. Whatever value is returned by JS callback will be passed to
---this callback.
---@param key string @Key defining which function to call.
---@param data boolean|number|string|table? @Data to send to JavaScript (JSON will be used to encode and decode the data).
---@param callback fun(reply: boolean|number|string|table?)? @Callback receiving value returned by receiver on JavaScript side.
---@return self
function webBrowser:sendAsync(key, data, callback)
  addCommand(self, CommandBE.Send, {expectReply(self, callback, JSON.parse), key, JSON.stringify(data)})
  return self
end

---Asynchronously collect all navigation entries for the current tab.
---@param direction 'both'|'back'|'forward'
---@param callback fun(reply: WebBrowser.NavigationEntry[])
---@return self
function webBrowser:getNavigationEntriesAsync(direction, callback)
  if connect.cefState ~= 0 then
    setTimeout(function() callback({}) end)
  else
    addCommand(self, CommandBE.History, {expectReply(self, function (data)
      if callback then 
        local parsed = stringify.parse(data)
        if type(parsed) ~= 'table' then parsed = {} end
        for _, v in ipairs(parsed) do
          if self._blankHandler and v.displayURL:startsWith('about:') then
            local h = getBlankPage(self, v.displayURL)
            if h then
              v.displayURL = h.url
              v.title = h.title
            end
          end
        end
        callback(parsed)
      end
    end), direction})
  end
  return self
end

---Asynchronously extract HTML source code for the opened webpage.
---@param callback fun(reply: string)
---@return self
function webBrowser:getPageHTMLAsync(callback)
  if connect.cefState ~= 0 then
    setTimeout(function() callback('') end)
  else
    addCommand(self, CommandBE.HTML, expectReply(self, callback))
  end
  return self
end

---Asynchronously extract text from the opened webpage.
---@param callback fun(reply: string)
---@return self
function webBrowser:getPageTextAsync(callback)
  if connect.cefState ~= 0 then
    setTimeout(function() callback('') end)
  else
    addCommand(self, CommandBE.Text, expectReply(self, callback))
  end
  return self
end

---Asynchronously collect SSL information.
---@param callback fun(reply: WebBrowser.SSLStatus)
---@return self
function webBrowser:getSSLStatusAsync(callback)
  if connect.cefState ~= 0 then
    setTimeout(function() callback({secure = false, faultsMask = 0}) end)
  else
    addCommand(self, CommandBE.SSL, expectReply(self, callback, stringify.parse))
  end
  return self
end

function webBrowser:cookiesAccessAllowed()
  return true -- TODO
end

---Asynchronously collect cookies for a given URL.
---@param mode 'basic'|'detailed' @Mode `basic` only provides name and value, and in `detailed` all the things are provided.
---@param url string? @Target URL. Pass `nil` to collect all the cookies (might be slow).
---@param callback fun(reply: WebBrowser.Cookie[])
---@return self
function webBrowser:getCookiesAsync(mode, url, callback)
  if mode ~= 'basic' then mode = 'detailed' end
  addCommand(self, CommandBE.ReadCookies, {expectReply(self, callback, stringify.parse), mode, url})
  return self
end

---Delete cookie or cookies fitting conditions.
---@param url string? @Pass `nil` to remove cookies on all websites.
---@param name string? @Pass `nil` to remove cookies of any names (to remove all cookies for a certain website pass its domain rather than URL).
---@return self
function webBrowser:deleteCookies(url, name)
  addCommand(self, CommandBE.WriteCookies, {url or '', name or ''})
  return self
end

---Remove all cookies newer than provided time threshold.
---@param maxAge integer @Time in seconds.
---@return self
function webBrowser:deleteRecentCookies(maxAge)
  addCommand(self, CommandBE.WriteCookies, {'@recent', maxAge})
  return self
end

---Set a value of a certain cookie.
---@param url string
---@param cookie WebBrowser.Cookie
---@return self
function webBrowser:setCookie(url, cookie)
  if cookie and cookie.name then
    addCommand(self, CommandBE.WriteCookies, {url, cookie.name, serializeItem(cookie, '\2')})
  end
  return self
end

---Asynchronously collect cookies for a given URL.
---@param url string? @Target URL. Pass `nil` to collect all the cookies (might be slow).
---@param callback fun(reply: integer)
---@return self
function webBrowser:countCookiesAsync(url, callback)
  addCommand(self, CommandBE.ReadCookies, {expectReply(self, callback, tonumber), 'count', url})
  return self
end

---Download image from the remote URL. Could be used to download favicons using Chromium. Returns a PNG file (use `ui.decodeImage()` to render it if needed).
---@param url string @URL of an image to download.
---@param favicon boolean? @Set to `true` for favicon mode: with it, no cookies will be sent to the server or received from it.
---@param maxSize integer? @If set, limits maximum image size, forcing Chromium to resize image if needed.
---@param callback fun(err: string?, data: binary?)
---@return self
function webBrowser:downloadImageAsync(url, favicon, maxSize, callback)
  addCommand(self, CommandBE.DownloadImage, {expectReply(self, function (data)
    callback(#data == 0 and 'Failed to download' or nil, #data > 0 and data or '')
  end), tostring(url), favicon or false, tonumber(maxSize) or 0})
  return self
end

---Resize browser.
---@param newSize vec2 @New size in pixels.
---@return self
function webBrowser:resize(newSize)
  local w, h = math.max(math.round(newSize.x), 4), math.max(math.round(newSize.y), 4)
  if self._mm.width ~= w or self._mm.height ~= h then
    self._mm.width = w
    self._mm.height = h
  end
  return self
end

---Change zoom level. Note: zoom level is shared across webpages with the same domain.
---@param value number? @Zoom value, `0` for normal scale. Default value: `0`.
---@return self
function webBrowser:setZoom(value)
  value = tonumber(value) or 0
  value = math.clamp(value, const(math.log(0.25, 1.2)), const(math.log(5, 1.2) + 1e-5))
  if self._mm.zoomLevel ~= value then
    self._mm.zoomLevel = value
    addCommand(self, CommandBE.Zoom, value, true)
  end
  return self
end

---Shortcut allowing to set zoom in actual scale.
---@param value number? @Zoom value, `1` for normal scale. Default value: `1`. CEF supports scales from 25% to 500%.
---@return self
function webBrowser:setZoomScale(value)
  return self:setZoom(math.log(tonumber(value) or 1, 1.2))
end

---Force browser to do layouting and such even if it’s not being drawn. By default browser starts to act as hidden a few frames after being drawn last time.
---@param value boolean? @Default value: `true`.
---@return self
function webBrowser:forceVisible(value)
  value = value ~= false
  if self._forceVisible ~= value then
    self._forceVisible = value
    self._mm.feFlags = bit.bor(value ~= false and 2 or 0, bit.band(self._mm.feFlags, bit.bnot(1)))
  end
  return self
end

---@return boolean @Returns `true` if browser service is currently initializing.
function webBrowser:initializing() return connect.cefState == 1 or connect.cefState == 2 end

---@return boolean @Returns `true` if everything is ready and texture is working.
function webBrowser:working() return self._working end

---Forces syncing. Usually is called automatically when needed, but if you don’t access any methods of a browser for awhile, but want it to stay updated, use this function.
---@return self
function webBrowser:sync()
  sync(self)
  return self
end

---@return string @Currently loaded URL.
function webBrowser:url()
  sync(self)
  if self._blankPage then
    return self._blankPage.url or ''
  end
  return self._url 
end

local domainNameCache = setmetatable({}, {__mode = 'k'})

---@param url string
function webBrowser.getDomainName(url)
  local c = domainNameCache[url]
  if not c then
    local i = url:find('://') or -2
    local j = url:find('[/#&?]', i + 3)
    c = j and url:sub(i + 3, j - 1) or url:sub(i + 3)
    -- if c:sub(1, 4) ==  'www.' then c = c:sub(5) end
    domainNameCache[url] = c
  end
  return c
end

---@return string @Domain name for the currently loaded URL.
function webBrowser:domain()
  if self._blankPage then
    return self._blankPage.title or ''
  end
  if self._domain == '' then
    self._domain = webBrowser.getDomainName(self._url) or self._url
  end
  return self._domain
end

---Try and find favicon for given URL based on previously seen webpages.
---@param url string
---@return string?
function webBrowser.faviconURLForPage(url)
  return faviconCache[webBrowser.getDomainName(url)]
end

---@param any boolean? @Set to `true` to get domain name if tab is not set.
---@return string @Title for current tab.
function webBrowser:title(any)
  sync(self)
  if self._blankPage then
    return self._blankPage.title or ''
  end
  if any and self._title == '' then
    return self:domain()
  end
  return self._title
end

---@return string? @URL for the main favicon.
function webBrowser:favicon()
  local r = self._favicon ---@type string|false
  if self._blankPage then
    return self._blankPage.favicon
  end
  sync(self)
  if r == '' then
    r = faviconCache[self:domain()] or false
    self._favicon = r
  end
  return r or nil
end

local function remapCursor(cefType)
  -- if cefType == 1 then return ui.MouseCursor.None end
  if cefType == 2 then return ui.MouseCursor.Hand end
  if cefType == 3 then return ui.MouseCursor.TextInput end
  if cefType == 37 then return ui.MouseCursor.None end
  if cefType == 14 or cefType == 19 or cefType == 22 or cefType == 25 or cefType == 43 then return ui.MouseCursor.ResizeNS end
  if cefType == 15 or cefType == 18 or cefType == 21 or cefType == 28 or cefType == 44 then return ui.MouseCursor.ResizeEW end
  if cefType ~= 0 then
    ac.debug('Unknown CEF cursor', cefType)
  end
  return ui.MouseCursor.Arrow
end

---@return string @Status message (usually an URL for currently hovered hyperlink), or an empty string.
function webBrowser:status() return self._status end

---@return string @Tooltip that browser might want to show at the moment, or an empty string.
function webBrowser:tooltip() return self._tooltip end

---@return ui.MouseCursor @Mouse cursor browser might want to use.
function webBrowser:mouseCursor() return remapCursor(self._mm.cursor) end

---@return vec2 @Mouse position.
function webBrowser:mousePosition() return vec2(self._mm.mouseX, self._mm.mouseY) end

---@return number @Current zoom (0 for default zoom). Use `:setZoom()` to change.
function webBrowser:zoom() return self._mm.zoomLevel end

---@return number @Webpage scale computed from current zoom level. CEF supports scales from 25% to 500%.
function webBrowser:zoomScale() return math.clamp(math.pow(1.2, self:zoom()), 0.25, 5) end

---@return boolean @Returns `true` if browser is currently loading something.
function webBrowser:loading() 
  if bit.band(self._mm.beFlags, 1) ~= 0 then
    if connect.cefState >= 10 or self._blankPage then return false end
    return self._mm.loadingProgress ~= 65535 
  end
  return false
end

---@return number @Returns loading progress from 0 to 1.
function webBrowser:loadingProgress() return (connect.cefState >= 10 or self._blankPage) and 1 or self._mm.loadingProgress / 65535 end

---@return boolean @Returns `true` if there is a page to navigate back to.
function webBrowser:canGoBack() return bit.band(self._mm.beFlags, 2) ~= 0 end

---@return boolean @Returns `true` if there is a page to navigate forward to.
function webBrowser:canGoForward() return bit.band(self._mm.beFlags, 4) ~= 0 end

---@return boolean @Returns `true` if there is no loaded document. Warning: apparently, this method might misbehave because of some CEF internal stuff.
function webBrowser:empty() return bit.band(self._mm.beFlags, 8) == 0 end

---@return WebBrowser.BlankOverride? @Returns currently active blank handler if any.
function webBrowser:blank() return self._blankPage end

---@return boolean @Returns `true` if browser is muted.
-- function webBrowser:muted() return bit.band(self._mm.beFlags, 16) ~= 0 end
function webBrowser:muted() return self._muted end

---@return boolean @Returns `true` if browser is in fullscreen mode.
function webBrowser:fullscreen() return bit.band(self._mm.beFlags, 64) ~= 0 end

---@return boolean @Returns `true` if current page was loaded with POST data.
function webBrowser:postedData() return bit.band(self._mm.beFlags, 128) ~= 0 end

---@return integer @Returns browser width in pixels.
function webBrowser:width() return self._mm.width end

---@return integer @Returns browser height in pixels.
function webBrowser:height() return self._mm.height end

---@return vec2 @Returns browser size in pixels.
function webBrowser:size() return vec2(self:width(), self:height()) end

---@return vec2 @Returns browser scroll in pixels.
function webBrowser:scroll() return self._mm.scrollOffset end

---@return WebBrowser.PageState? @Returns table with current page state details if any.
function webBrowser:pageState() return connect.cefState == 0 and not backendUnresponsive(self) and self._pageState or nil end

---@return WebBrowser.LoadError? @Returns table with current load error if any.
function webBrowser:loadError()
  return connect.cefState == 0 and self._loadError or nil
end

---@return boolean @Returns `true` if browser is forced to be visible.
function webBrowser:forcedVisible() return self._forceVisible end

---@return WebBrowser.Settings @Returns settings used for creating this browser. Changing won’t have any effect until browser is restarted.
function webBrowser:settings() return self._settings end

---Exit fullscreen (like if F11 would be pressed with YouTube opened in fullscreen mode in regular browser).
function webBrowser:exitFullscreen()
  addCommand(self, CommandBE.Command, 'exitFullscreen')
end

local uv1 = vec2(0, 1)
local uv2 = vec2(1, 0)
local popup0 = vec2()
local popup1 = vec2()

---Returns `true` if the browser has been disposed. Do not use these ones, they wouldn’t work anyway.
---@return boolean
function webBrowser:disposed()
  return not self._dispose 
end

---@return self
function webBrowser:awake()
  addCommand(self, CommandBE.Awake)
  return self
end

---@return self
function webBrowser:invalidateView()
  addCommand(self, CommandBE.SetOption, {'invalidateView', '1'})
  return self
end

---If activated, browser won’t release texture when suspending. Increases VRAM consumption, but does allow to keep drawing suspended browsers.
---@param keep boolean? @Default value: `true`.
---@return self
function webBrowser:keepSuspendedTexture(keep)
  keep = keep ~= false
  if (self._keepSuspendedTexture or false) ~= keep then
    self._keepSuspendedTexture = keep
    addCommand(self, CommandBE.SetOption, {'keepSuspendedTexture', keep})
  end
  return self
end

---@alias WebBrowser.InstallationState {message: string, progress: number}
---@alias WebBrowser.Crash {errorCode: integer, errorText: string, errorDetails: string}

local installingProgress
local function getInstallationProgress()
  if not installingProgress then
    installingProgress = ac.connect{
      ac.StructItem.key('cefState.install'),
      progress = ac.StructItem.float(),
      message = ac.StructItem.string(256),
    }
  end
  return installingProgress
end

local crashData ---@type WebBrowser.Crash?
local crashMessages = {
  [10] = 'ERR_ACEF_EXITED',
  [11] = 'ERR_ACEF_FAILED_TO_START',
  [12] = 'ERR_ACEF_UNAVAILABLE_TEXTURE',
  [13] = 'ERR_ACEF_FAILED_TO_RESHARE',
  [14] = 'ERR_ACEF_UNCAUGHT_EXCEPTION',
  [15] = 'ERR_ACEF_INSTALLATION_ERROR',
  [16] = 'ERR_ACEF_UNKNOWN_ERROR',
  [17] = 'ERR_ACEF_UNKNOWN_CRASH',
  [18] = 'ERR_ACEF_BOOTLOOP',
}

---@param self WebBrowser
---@return WebBrowser.Crash
local function getCrash(self)
  if not crashData then crashData = {} end
  crashData.errorCode = tonumber(connect.cefState) or 17
  if crashData.errorCode < 10 then 
    -- Custom case for error related to texture access failure
    if self._texture and not self._texture:valid() then
      crashData.errorCode = 20
      crashData.errorText = 'ERR_ACEF_UNDRAWABLE_TEXTURE'
      crashData.errorDetails = 'Failed to render CEF texture.'
    else
      crashData.errorText = 'ERR_ACEF_NOT_AN_ERROR'
      crashData.errorDetails = 'Should not have happen.'
    end
  else
    crashData.errorText = crashMessages[crashData.errorCode] or 'ERR_ACEF_UNKNOWN_ERROR'
    local r = ac.load('.SmallTweaks.CEFInstallError')
    crashData.errorDetails = type(r) == 'string' and r ~= '' and r or 'Unknown CEF error.'
  end
  return crashData
end

---Returns the installation state if CEF is currently being installed.
---@return WebBrowser.InstallationState?
function webBrowser:installing()
  return (connect.cefState == 2 or self._installingCEF and self._installingCEF ~= 'Creating a browser…') and getInstallationProgress() or nil 
end

---@type WebBrowser.Crash
local nonresponsiveCrash = {
  errorCode = 28,
  errorText = 'ERR_ACEF_BACKEND_DOES_NOT_RESPOND',
  errorDetails = 'Failed to connect to AC CEF layer.'
}

---Returns details about current crash (if any).
---@return WebBrowser.Crash?
function webBrowser:crash()
  return connect.cefState >= 10 and getCrash(self) 
    or backendUnresponsive(self) and nonresponsiveCrash 
    or self._texture and not self._texture:valid() and getCrash(self)
    or nil
end

---Specify what should browser draw if there is no webpage or blank to display.
---@param mode fun(p1: vec2, p2: vec2, tab: WebBrowser, key: 'loading'|'loadError'|'crash')|'message'|'background'|'skip' @Draw using a custom function, display a simple message, show solid background color or do nothing.
---@return self
function webBrowser:onDrawEmpty(mode)
  self._emptyMode = mode
  return self
end

local alignCenter = vec2(0.5, 0.5)

---@param self WebBrowser
---@param p1 vec2
---@param p2 vec2
---@param displayMessage string
---@param responseKey 'loading'|'loadError'|'crash'
---@param responseData nil|WebBrowser.InstallationState|WebBrowser.BlankOverride|WebBrowser.LoadError|WebBrowser.Crash
local function drawSkip(self, p1, p2, displayMessage, responseKey, responseData)
  if type(self._emptyMode) == 'function' then
    ui.backupCursor()
    ui.pushClipRect(p1, p2, true)
    self._emptyMode(p1, p2, self, responseKey)
    ui.restoreCursor()
    ui.popClipRect()
  elseif self._emptyMode ~= 'pass' then
    if self._settings.backgroundColor then
      ui.drawRectFilled(p1, p2, self._settings.backgroundColor)
    end
    if self._emptyMode == 'message' then
      ui.drawTextClipped(displayMessage, p1, p2, self:contentColor(), alignCenter)
    end
  end
  return responseKey, responseData
end

---@param self WebBrowser
_drawDisposed = function(self, p1, p2, realScale)
  return drawSkip(self, p1, p2, 'Browser has been disposed', 'crash', self:crash() or getCrash(self))
end

---Draw browser within given rect. Uses up to two `ui.drawImage()` calls inside (second one for possible popup layer like
---an opened dropdown list). If there is an error, draws an error message instead.
---@param p1 vec2 @Position for the upper left corner.
---@param p2 vec2 @Position for the bottom right corner.
---@param realScale boolean? @Pass `true` to draw browser in 1:1 scale. Helps to fix issues with resizing.
---@return nil|'loading'|'blank'|'loadError'|'crash'
---@return nil|WebBrowser.InstallationState|WebBrowser.BlankOverride|WebBrowser.LoadError|WebBrowser.Crash
function webBrowser:draw(p1, p2, realScale)
  sync(self)

  self._alive = false
  local h = self._blankHeldPage or self._blankPage
  if h then 
    if h.onDraw then
      ui.backupCursor()
      ui.pushClipRect(p1, p2, true)
      h.onDraw(p1, p2, self)
      ui.restoreCursor()
      ui.popClipRect()
    end
    return 'blank', h
  end

  -- ac.debug('connect.cefState', connect.cefState)
  if connect.cefState ~= 0 then
    self._mm.beAliveTime = sim.systemTime
    if connect.cefState == 2 then
      local p = getInstallationProgress()
      self._installingCEF = p.message or 'Installing…'
      return drawSkip(self, p1, p2, self._installingCEF, 'loading', p)
    elseif connect.cefState == 1 then
      if not self._installingCEF then self._installingCEF = 'Creating a browser…' end
      return drawSkip(self, p1, p2, self._installingCEF, 'loading',
        self._installingCEF and self._installingCEF ~= 'Creating a browser…' and getInstallationProgress() or nil)
    else
      return drawSkip(self, p1, p2, 'Service crashed: '..getCrash(self).errorText, 'crash', getCrash(self))
    end
  end

  if self._loadError then
    return drawSkip(self, p1, p2, 'Failed to load: '..self._loadError.errorText, 'loadError', self._loadError)
  end

  awakeRender(self)

  if self._mm.handle == 0 then
    if backendUnresponsive(self) then
      self._installingCEF = nil
      self._mm.beFlags = 0
      return drawSkip(self, p1, p2, 'Backed does not respond', 'crash', nonresponsiveCrash)
    end
    return drawSkip(self, p1, p2, self._installingCEF or '', 'loading', 
      self._installingCEF and self._installingCEF ~= 'Creating a browser…' and getInstallationProgress() or nil)
  end

  if not self._texture or self._lastHandle ~= self._mm.handle then
    self._working = true
    if self._installingCEF then self._installingCEF = nil end
    if self._texture then self._texture:dispose() end
    self._lastHandle = self._mm.handle
    if self._settings.directRender then
      self._texture = ui.SharedTexture(self._prefix..'.'..tonumber(self._mm.handle))
      self._textureResolution = self._texture:resolution():clone():scale(1 / self._pixelDensity)
    else
      self._texture = ui.SharedTexture(self._mm.handle)
    end
    if self._invalidatingViewCount and self._texture:valid() then
      self._invalidatingViewCount = nil
    end
  end

  if not self._texture:valid() then
    ac.warn(string.format('Texture is not valid: %d, %d', self._mm.width, self._mm.height))
    if (self._invalidatingViewCount or 0) < 3 then
      -- up to five invalidations to try and fix the texture before crashing
      if sim.gameTime - (self._invalidatingViewTime or 0) > 0.1 then
        self._invalidatingViewTime = sim.gameTime
        self._invalidatingViewCount = (self._invalidatingViewCount or 0) + 1
        addCommand(self, CommandBE.SetOption, {'invalidateView', '1'})
      end
      if self._settings.backgroundColor then
        ui.drawRectFilled(p1, p2, self._settings.backgroundColor)
      end
      return
    end
    return drawSkip(self, p1, p2, 'Texture is not available', 'crash', getCrash(self))
  end
  
  self._alive = true
  if self._settings.directRender then
    if self._mm.popupHandle ~= 0 then
      if not self._popupTexture or self._lastPopupHandle ~= self._mm.popupHandle then
        if self._popupTexture then self._popupTexture:dispose() end
        self._lastPopupHandle = self._mm.popupHandle
        self._popupTexture = ui.SharedTexture(self._prefix..'.'..tonumber(self._mm.popupHandle))
      end
    elseif self._popupTexture then
      self._popupTexture:dispose()
      self._popupTexture = nil
    end

    uv1.x, uv1.y = 0, 1
    local size = self._textureResolution
    if realScale and (size.x ~= p2.x - p1.x or size.y ~= p2.y - p1.y) then
      uv2.x = (p2.x - p1.x) / size.x
      uv2.y = 1 - (p2.y - p1.y) / size.y
      if uv2.x > 1 or uv2.y < 0 then
        ui.drawRectFilled(p1, p2, self._resizePaddingColor)

        local p3 = p2:clone()
        p3.x = math.lerp(p1.x, p2.x, math.min(1, 1 / uv2.x))
        p3.y = math.lerp(p1.y, p2.y, math.min(1, 1 / (1 - uv2.y)))
        p2 = p3
        uv2.x = math.min(1, uv2.x)
        uv2.y = math.max(0, uv2.y)
      end
    else
      uv2.x, uv2.y = 1, 0
    end

    ui.drawImage(self._texture, p1, p2, nil, uv1, uv2)
    if self._popupTexture and self._popupTexture:valid() then
      ui.drawImage(self._popupTexture, popup0:set(p2):sub(p1):mul(self._mm.popup0):add(p1), popup1:set(p2):sub(p1):mul(self._mm.popup1):add(p1), nil, uv1, uv2)
    end
  else
    ui.drawImage(self._texture, p1, p2)
  end

  if self._drawTouches then
    if math.abs(self._mm.touches[0].x) < 1e30 then
      ui.drawCircleFilled(p1 + (p2 - p1) * self._mm.touches[0] / vec2(self._mm.width, self._mm.height), 8, self._drawTouches)
    end
    if math.abs(self._mm.touches[1].x) < 1e30 then
      ui.drawCircleFilled(p1 + (p2 - p1) * self._mm.touches[1] / vec2(self._mm.width, self._mm.height), 8, self._drawTouches)
    end
  end

  return nil
end

---Enters given text into currently selected input.
---@param text string @Text to enter. There will be a 10 ms delay between each symbol just in case.
---@return self
function webBrowser:textInput(text)
  if text and #text > 0 and connect.cefState == 0 then addCommand(self, CommandBE.Input, text) end
  return self
end

---Simulate a key event. For typing things use `:input()`.
---@param key integer @Key index from 1 to 255 or something like that.
---@param released boolean @Set to `true` for key-up event.
---@return self
function webBrowser:keyEvent(key, released)
  if connect.cefState == 0 then
    addCommand(self, released and CommandBE.KeyUp or CommandBE.KeyDown, tonumber(key) or 0)
  end
  return self
end

local mouseTable = {false, false, false}

---Simulate mouse input.
---@param mousePos vec2 @Mouse position in 0…1 range.
---@param mousePressed boolean|boolean[] @State of mouse buttons: left, right, middle (`true` for pressed).
---@param mouseWheel number? @Mouse wheel movement.
---@param wheelForZoom boolean? @Set to `true` to use mouse wheel for zoom instead of scrolling.
---@return self
function webBrowser:mouseInput(mousePos, mousePressed, mouseWheel, wheelForZoom)
  local px = mousePos.x * self._mm.width
  local py = mousePos.y * self._mm.height
  if type(mousePressed) ~= 'table' then mousePressed, mouseTable[1] = mouseTable, mousePressed == true end
  local hovered = (px > 0 and px < self._mm.width and py > 0 and py < self._mm.height or self._dragging) and self._alive
  if not mouseWheel then mouseWheel = 0 end
  if hovered then
    self._mm.mouseX = math.clamp(px, 1, self._mm.width - 1)
    self._mm.mouseY = math.clamp(py, 1, self._mm.height - 1)
    self._mm.mouseFlags = (mousePressed[1] and 1 or 0) + (mousePressed[2] and 4 or 0) + (mousePressed[3] and 2 or 0)
    if wheelForZoom and mouseWheel ~= 0 then
      self:setZoom(self:zoom() + mouseWheel * 0.2)
    else
      self._mm.mouseWheel = mouseWheel * 80
    end
    self._dragging = mousePressed[1]
  else
    self._mm.mouseX = 65535
    self._mm.mouseY = 0
    self._mm.mouseFlags = 0
    self._mm.mouseWheel = 0
    self._dragging = false
  end
  return self
end

---Draw touches sent with `:touchInput()`.
---@param color rgbm? @Set to `nil` to disable drawing.
---@return self
function webBrowser:drawTouches(color)
  self._drawTouches = color
  return self
end

---Simulate touch input.
---@param touches vec2[] @Active touches. Currently up to two touches are supported.
---@return self
function webBrowser:touchInput(touches)
  local t1 = touches[1] and touches[1].x >= 0 and touches[1].x <= 1 and touches[1].y >= 0 and touches[1].y <= 1 and touches[1]
  local t2 = touches[2] and touches[2].x >= 0 and touches[2].x <= 1 and touches[2].y >= 0 and touches[2].y <= 1 and touches[2]
  if not t1 and not t2 or not self._alive then
    self._mm.touches[0].x = math.huge
    self._mm.touches[1].x = math.huge
    self._mm.mouseFlags = 0
  else
    if t1 then t1 = t1 * self:size() end
    if t2 then t2 = t2 * self:size() end
    local p1, p2 = self._mm.touches[0].x < 1e30, self._mm.touches[1].x < 1e30
    if t1 and not t2 and not p1 and p2 or t2 and not t1 and not p2 and p1 or t1 and t2 and (
      p1 and t1:distanceSquared(self._mm.touches[0]) > t2:distanceSquared(self._mm.touches[0]) or
      p2 and t1:distanceSquared(self._mm.touches[1]) < t2:distanceSquared(self._mm.touches[1])) then
      t1, t2 = t2, t1
    end    
    if t1 then
      self._mm.touches[0]:set(t1)
    else
      self._mm.touches[0].x = math.huge
    end
    if t2 then
      self._mm.touches[1]:set(t2)
    else
      self._mm.touches[1].x = math.huge
    end
    self._mm.mouseFlags = 1
  end
  self._mm.mouseX = 0
  self._mm.mouseY = 0
  self._mm.mouseWheel = 0
  self._dragging = false
  return self
end

---Process some extra standard browser hotkeys.
---@param state ui.CapturedKeyboard
---@return boolean @Returns `true` if any of keyboard hotkeys were detected and it would make sense to ignore keyboard events for this frame.
function webBrowser:shortcuts(state)
  if ui.mouseClicked(ui.MouseButton.Extra1) then
    self:navigate('back')
  elseif ui.mouseClicked(ui.MouseButton.Extra2) then
    self:navigate('forward')
  end
  if state:hotkeyCtrl() then
    if ui.keyboardButtonReleased(ui.KeyIndex.R) then
      self:reload()
    else
      return false
    end
  elseif state:hotkeyAlt() then
    if ui.keyboardButtonReleased(ui.KeyIndex.Left) then
      self:navigate('back')
    elseif ui.keyboardButtonReleased(ui.KeyIndex.Right) then
      self:navigate('forward')
    else
      return false
    end
  else
    return false
  end
  return true;
end

---Enable keyboard shortcuts and input for the browser window.
---@param state ui.CapturedKeyboard
---@return WebBrowser
function webBrowser:keyboard(state)
  if self._alive then
    for i = 0, state.pressedCount - 1 do
      addCommand(self, CommandBE.KeyDown, state.repeated[i] and '\1'..state.pressed[i] or state.pressed[i])
    end
    for i = 0, state.releasedCount - 1 do
      addCommand(self, CommandBE.KeyUp, state.released[i])
    end
    self:textInput(state:queue())
  end
  return self
end

---Send a simple command.
---@param command 'selectAll'|'copy'|'cut'|'paste'|'delete'|'undo'|'redo'|'print'|'exitFullscreen'
---@return self
function webBrowser:command(command)
  if self._alive then
    addCommand(self, CommandBE.Command, command)
  end
  return self
end

function webBrowser.restartProcess(reinstall)
  ac.broadcastSharedEvent('$SmallTweaks.CEF', {restart = true, reinstall = reinstall})
end

ac.onSharedEvent('$SmallTweaks.CEF.Restart', function ()
  ac.warn('CEF needs a restart', #instances)
  for i = 1, #instances do
    if instances[i]._settings.automaticallyRestartOnBackendCrash ~= false then
      instances[i]:restart()
    end
  end
end)

---@param callback fun()
function webBrowser.onProcessRestart(callback)
  ac.onSharedEvent('$SmallTweaks.CEF.Restart', callback)
end

---@param url string
function webBrowser.knownProtocol(url)
  return #url > 0 
    and not url:startsWith('about:') and not url:startsWith('file:') 
    and not url:startsWith('chrome-extension:') and not url:startsWith('data:') 
    and not url:startsWith('ac:')
end

---@param accept string[]
local function guessGroupName(accept)
  for i, v in ipairs(accept) do
    if v == '.png' or v == '.jpg' then return 'Images' end
    if v == '.mp3' or v == '.wav' then return 'Audio' end
  end
  return 'Files'
end

---@param id string
---@return string
function webBrowser.blankURL(id)
  return 'about:blank#'..id
end

---@param url string
---@return string
function webBrowser.sourceURL(url)
  return 'view-source:'..url
end

---@param accept string[]?
---@return {name: string, mask: string}[]?
function webBrowser.convertAcceptFiltersToFileTypes(accept)
  if not accept or #accept == 0 then return nil end
  if table.every(accept, function (item) return string.startsWith(item, '.') end) then
    return {{name = guessGroupName(accept), mask = '*'..table.join(accept, ';*')}}
  end
  ac.debug('Unknown accept', accept)
  return nil
end

---@return boolean
function webBrowser.usesCEFLoop()
  return connect.cefLoop
end

---@return integer
function webBrowser.targetFPS()
  return connect.targetFPS
end

---@return boolean
function webBrowser.skipsProxyServer()
  return connect.noProxyServer
end

---Call this function to tweak global CEF behavior. Feel free to not include parameters you don’t want to be changed.
---- `useCEFLoop`: let Chromium engine handle updates and message processing instead of a custom implementation, might be smoother and more stable, but adds up to 16 ms of extra latency.
---- `useTimer`: use Windows Multimedia API to set the wrapper loop instead of using `Sleep()` for timing, pretty useless but just in case.
---- `skipProxyServer`: do not load system proxy settings, helps with initialization speed.
---- `targetFPS`: FPS for browser to render at, default value is 60 FPS.
---- `setGPUProcessPriority`: argument for calling `D3DKMTSetProcessSchedulingPriorityClass()` for all CEF processes, valid values are within 0…5 range.
---- `setGPUDevicePriority`: argument for calling `SetGPUThreadPriority()` for main process, won’t make difference if `directRender` is disabled.
---@param requestedSettings {useCEFLoop: boolean?, useTimer: boolean?, setGPUDevicePriority: integer?, setGPUProcessPriority: integer?, skipProxyServer: boolean?, targetFPS: integer?}?
function webBrowser.configure(requestedSettings) 
  if type(requestedSettings) ~= 'table' then return end
  if requestedSettings.useCEFLoop ~= nil then ac.store('.SmallTweaks.CEF.useCEFLoop', requestedSettings.useCEFLoop and 1 or 0) end
  if requestedSettings.useTimer ~= nil then ac.store('.SmallTweaks.CEF.useTimer', requestedSettings.useTimer and 1 or 0) end
  if requestedSettings.skipProxyServer ~= nil then ac.store('.SmallTweaks.CEF.skipProxyServer', requestedSettings.skipProxyServer and 1 or 0) end
  if type(requestedSettings.targetFPS) == 'number' then ac.store('.SmallTweaks.CEF.targetFPS', requestedSettings.targetFPS) end
  if type(requestedSettings.setGPUDevicePriority) == 'number' then ac.store('.SmallTweaks.CEF.setGPUDevicePriority', requestedSettings.setGPUDevicePriority) end
  if type(requestedSettings.setGPUProcessPriority) == 'number' then ac.store('.SmallTweaks.CEF.setGPUProcessPriority', requestedSettings.setGPUProcessPriority) end
end

---@type fun(settings: WebBrowser.Settings?): WebBrowser
local constructor = webBrowser.initialize
return class.emmy(webBrowser, constructor)
