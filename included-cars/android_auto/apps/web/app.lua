local WebBrowser = require('shared/web/browser')

---@alias WebTab {url: string, title: string, browser: WebBrowser?}

local tabs = {} ---@type WebTab[]
local activeTab = 1
local keyboard
local navbar, navbarActive, navbarHold = 1, 1, 0
local searchQuery = ''
local favs = stringify.binary.tryParse(ac.storage.browserFavs, nil)
local btnSize = vec2(32, 32)
local tabsView, tabsViewActive = 0, 0

if type(favs) ~= 'table' then
  favs = {['https://m.youtube.com/'] = 'YouTube', ['https://twitch.tv/'] = 'Twitch', ['https://discord.com/'] = 'Discord'}
end

local function saveFavs()
  ac.storage.browserFavs = stringify.binary(favs)
end

local m = ac.findMeshes()
local v = m:getVertices()
if v then
  for i = 0, v:size() - 1 do
    v.raw[i].pos.y = v.raw[i].pos.y - i
  end
  m:alterVertices(v)
end

local urlRegex = '^(?:(?:javascript|about|ac|https?):|\\w(?:[\\w-]*\\w)?\\.\\w(?:[\\w.-]*\\w)?(?:/.*|$))'

local searchProviders = {
  ddg = {
    query = 'https://duckduckgo.com/?q=%s',
    icon = io.relative('search.png'),
  },
  google = {
    query = 'https://www.google.com/search?q=%s',
    icon = 'https://google.com/favicon.ico',
  },
  bing = {
    query = 'https://www.bing.com/search?q=%s',
    icon = 'https://bing.com/favicon.ico',
  },
  ecosia = {
    query = 'https://www.ecosia.org/search?q=%s',
    icon = 'https://ecosia.org/favicon.ico',
  },
}

local function userURL(input)
  return input:regfind(urlRegex) and input
    or (searchProviders[ac.load('.WebBrowser.searchProvider')] or searchProviders.ddg).query:format(input:urlEncode())
end

local function searchIcon()
  return (searchProviders[ac.load('.WebBrowser.searchProvider')] or searchProviders.ddg).icon
end

local favicons = (function ()
  local cache = {}
  local needsIcons = {}
  ---@param tab WebBrowser
  local function store(tab)
    local d = tab:domain():gsub('^www%.', '')
    setTimeout(function ()
      local d1 = tab:domain():gsub('^www%.', '')
      if d == d1 and not tab:loading() then
        local favicon = tab:favicon()
        if favicon and not tab:showingSourceCode() then          
          tab:downloadImageAsync(favicon, true, 32, function (err, data)
            if not err and data then
              local decoded = ui.decodeImage(data)
              ui.ExtraCanvas(64, 4):update(function () ui.drawImage(decoded, 0, 64) end)
                :save(__dirname..'/res/_favicon_'..bit.tohex(ac.checksumXXH(d))..'.png', ac.ImageFormat.PNG)
              cache[d] = decoded
            end
          end)
        end
      end
    end, 1)
  end
  return {
    get = function (url)
      local d = WebBrowser.getDomainName(url):gsub('^www%.', '')
      local c = cache[d]
      if not c then
        c = ui.Icons.Earth
        cache[d] = c
        local f = __dirname..'/res/_favicon_'..bit.tohex(ac.checksumXXH(d))..'.png'
        if io.fileExists(f) then
          io.loadAsync(f, function (err, data)
            cache[d] = not err and ui.decodeImage(data)
          end)
        else
          needsIcons[d] = true
        end
      end
      return c
    end,
    ---@param tab WebBrowser
    update = function (tab)
      local d = tab:domain():gsub('^www%.', '')
      if needsIcons[d] then
        needsIcons[d] = nil
        store(tab)
      end
    end,
    store = store
  }
end)()

local Blanks = {
  newTab = {
    title = 'New Tab',
    url = '',
    favicon = ui.Icons.Skip,
    ---@type fun(p1: vec2, p2: vec2, tab: WebBrowser)
    onDraw = function (p1, p2, tab)
      ui.drawRectFilled(p1, p2, rgbm.colors.black)
      local p = vec2((p1.x + p2.x) / 2, (p1.y + p2.y - touchscreen.keyboardOffset()) / 2 - 40 * math.max(0, 1 - touchscreen.keyboardOffset() / ((p2.y - p1.y) * 0.6)))
      ui.drawImage(searchIcon(), p - 24, p + 24)
      ui.setCursor(p + vec2(-200, 40))
      ui.setNextItemWidth(400)
      local query, submit = touchscreen.inputText('Search', searchQuery, ui.InputTextFlags.Placeholder)
      searchQuery = query
      if submit and #query > 0 then
        tab:navigate(userURL(query))
      end
      local favsOrdered = table.map(favs, function (item, key)
        return {item, key}
      end)
      table.sort(favsOrdered, function (a, b)
        return a[1] < b[1]
      end)
      local f = math.min(#favsOrdered, 5)
      if f > 0 then
        ui.offsetCursorY(20)
        ui.setCursorX(p.x - 84 * f / 2)
        for i = 1, f do
          local e = favsOrdered[i]
          if i > 1 then
            ui.sameLine(0, 0)
          end
          ui.beginGroup(84)
          ui.offsetCursorX((84 - 32) / 2)
          ui.icon(favicons.get(e[2]), 32)
          ui.textAligned(e[1], 0.5, vec2(-0.1, 20), true)
          ui.endGroup()
          if touchscreen.itemTapped() then
            tab:navigate(e[2])
          end
        end
      end
    end
  }
}

---@return WebTab
local function createTab(url)
  return {
    url = url or WebBrowser.blankURL('newtab'),
    title = url and WebBrowser.getDomainName(url) or 'New Tab',
  }
end

---@param t WebTab
---@return WebBrowser
local function getBrowser(t)
  if not t.browser then
    t.browser = WebBrowser({
      dataKey = '',
      backgroundColor = rgbm.colors.black,
      redirectAudio = false,
      -- audioParameters = {
      --   use3D = true,
      --   insideConeAngle = 90,
      --   outsideConeAngle = 180,
      --   outsideVolume = 0.5,
      --   minDistance = 0.5,
      --   maxDistance = 5,
      --   reverb = true
      -- }
    })
    -- :onAudioEvent(function (browser, event)
    --   event.cameraInteriorMultiplier = 1
    --   event.cameraExteriorMultiplier = 0.05
    --   event.cameraTrackMultiplier = 0.02
    --   event:setPosition(vec3(0, 1, 1), vec3(0, 0, -1), vec3(0, 1, 0))
    -- end)
    :onURLChange(function (tab)
      t.url = tab:url()
    end)
    :onTitleChange(function (tab)
      t.title = tab:title(true)
    end)
    :onDrawEmpty('message')
    :setMobileMode('landscape')
    :navigate(t.url or WebBrowser.blankURL('newtab'))
    :setColorScheme('dark')
    :setPixelDensity(0.8)
    :setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/114.0.5735.99 Mobile/15E148 Safari/604.1')
    :drawTouches(rgbm(1, 1, 1, 0.5))
    :blockURLs(WebBrowser.adsFilter())
    :setBlankHandler(function (browser, url)
      if url:startsWith('newtab') then
        return Blanks.newTab
      end
    end)
    :onLoadEnd(function (browser)
      favicons.update(browser)
    end)
    :onPopup(function (tab, data)
      -- Happens when website wants to open a popup
      if data.userGesture and not data.userGesture then -- proceed only if it was a user gesture triggering the event
        tabs[#tabs + 1] = createTab(data.targetURL)
        activeTab = #tabs
      end
    end)
    :onOpen(function (tab, data)
      -- Happens when browser thinks it would be a good idea to open a thing in a new tab (like with a middle click)
      if not data.userGesture then return end
      if tab.attributes.windowTab then
        tab:navigate(data.targetURL)
      else
        tabs[#tabs + 1] = createTab(data.targetURL)
        activeTab = #tabs
      end
    end)
    :onClose(function (browser)
      setTimeout(function () -- adding a frame delay so that tabs removed from App.tabs wouldn’t break unexpected things
        table.removeItem(tabs, activeTab)
      end)
    end)
  end
  return t.browser
end

local tabsCountPrev, tabsIcon

return function (dt)
  if not tabs[1] then
    tabs[1] = createTab()
    activeTab = 1
  elseif not tabs[activeTab] then
    activeTab = #tabs
  end
 
  touchscreen.forceAwake()
  system.fullscreen()
  touchscreen.boostFrameRate()

  local page = getBrowser(tabs[activeTab])
  tabsView = math.applyLag(tabsView, tabsViewActive, 0.8, dt)
  if tabsView > 0.001 then
    local s = ui.availableSpace()
    ui.childWindow('scrollingArea', s, function()
      local w = s.x / 2 - 20
      local h = w * s.y / s.x + 32
      local toClose, toAnimate
      local function drawTab(i, v, r1, r2, tr)
        ui.drawRectFilled(r1, r2, tr and math.lerp(rgbm.colors.black, rgbm.colors.gray, tr)
          or i == activeTab and rgbm.colors.gray or rgbm.colors.black, 4, ui.CornerFlags.All)
        if v.browser then
          v.browser:draw(vec2(r1.x, r1.y + 32), r2, false)
        end
        ui.drawRect(r1, r2, tr and math.lerp(rgbm(0.24, 0.24, 0.24, 1), rgbm.colors.gray, tr)
          or i == activeTab and rgbm.colors.gray or rgbm(0.24, 0.24, 0.24, 1), 4, ui.CornerFlags.All, 2)
        ui.dwriteDrawTextClipped(v.title, 16, vec2(r1.x + 32, r1.y), vec2(r2.x - 8, r1.y + 32), ui.Alignment.Start, ui.Alignment.Center, false, i == activeTab and rgbm.colors.black or rgbm.colors.white)
        ui.drawIcon(ui.Icons.Earth, r1 + 8, r1 + 24)
      end
      for i, v in ipairs(tabs) do
        if i % 2 == 0 then
          ui.sameLine(0, 20)
        else
          ui.offsetCursorY(20)
        end
        ui.pushID(i)
        ui.beginGroup(w)
        ui.invisibleButton('select', vec2(w, h))
        if touchscreen.itemTapped() then
          tabsViewActive = 0
          activeTab = i
          navbarActive = 1
        end
        local r1, r2 = ui.itemRect()
        if i == activeTab and tabsView < 0.999 then
          toAnimate = {i, v, math.lerp(vec2(0, -32), r1, tabsView), math.lerp(s + vec2(0, 0), r2, tabsView), tabsView}
          toAnimate[3].x = math.round(toAnimate[3].x)
          toAnimate[3].y = math.round(toAnimate[3].y)
          toAnimate[4].x = math.round(toAnimate[4].x)
          toAnimate[4].y = math.round(toAnimate[4].y)
        else
          drawTab(i, v, r1, r2)
          ui.setItemAllowOverlap()
          ui.setCursor(vec2(r2.x - 32, r1.y))
          if touchscreen.button('##close', btnSize, rgbm.colors.transparent, 0, ui.Icons.Cancel, 14) then
            toClose = v
          end
        end
        ui.endGroup()
        ui.popID()
      end
      if toAnimate then
        drawTab(table.unpack(toAnimate))
      end
      if toClose then
        table.removeItem(tabs, toClose)
      end
      touchscreen.scrolling()
    end)
  else
    local size = ui.availableSpace()
    ui.dummy(size)

    page:resize(size * (1 / 0.8))  
    local r1, r2 = ui.itemRect()
    if not page:focused() then
      page:focus(true)
    end
    page:draw(r1, r2, false)
  
    if touchscreen.touched() then
      local pos = ui.mouseLocalPos()
      if pos.y < size.y - math.max(0, touchscreen.keyboardOffset() - system.bottomBarHeight) and pos.y > 32 * navbar then
        page:touchInput({pos:div(size)})
        if ui.mouseDelta().y > 20 then
          navbarActive, navbarHold = 1, os.preciseClock() + 0.5
        elseif navbarHold < os.preciseClock() then
          navbarActive = 0
        end
      else
        page:touchInput({})
      end
    else
      page:touchInput({})
      keyboard = page:requestedVirtualKeyboard()
    end
  
    if keyboard then    
      local c = touchscreen.inputBehaviour()
      if type(c) == 'string' then
        page:textInput(c)
      elseif type(c) == 'number' then
        page:keyEvent(c, false)
        page:keyEvent(c, true)
      end
    end
  end

  navbar = math.applyLag(navbar, navbarActive, 0.8, dt)
  local y = -32 + 32 * navbar
  if navbar > 0.01 or page:loading() then
    ui.setCursor(vec2(0, y))
    ui.childWindow('##navbar', vec2(ui.windowWidth(), 33), function ()
      if navbar > 0.01 then
        ui.drawRectFilled(vec2(), vec2(ui.windowWidth(), 32), rgbm.colors.black)
        ui.setCursorX(40)
        ui.setCursorY(0)
        if touchscreen.button('##back', btnSize, rgbm.colors.black, 0, ui.Icons.ArrowLeft, 14, not page:canGoBack()) then
          page:navigate('back')
        end
        ui.sameLine(0, 12)
        ui.setCursorY(0)
        if touchscreen.button('##forward', btnSize, rgbm.colors.black, 0, ui.Icons.ArrowRight, 14, not page:canGoForward()) then
          page:navigate('forward')
        end
        ui.sameLine(0, 12)
        ui.setCursorY(0)
        if touchscreen.button('##restart', btnSize, rgbm.colors.black, 0, ui.Icons.Restart, 14) then
          page:reload(true)
        end
        ui.sameLine(0, 12)
        ui.setCursorY(0)
        if touchscreen.button('##home', btnSize, rgbm.colors.black, 0, ui.Icons.Home, 14) then
          page:navigate(WebBrowser.blankURL('newtab'))
        end
        ui.sameLine(0, 20)
        ui.setCursorY(4)
        ui.setNextItemWidth(ui.availableSpaceX() - 20 - (32 * 4 + 12 * 3) - 40)
        local url, submit = touchscreen.inputText('Search query or URL', tabs[activeTab] and tabs[activeTab].url or '', ui.InputTextFlags.Placeholder)
        if submit then
          ac.warn(url)
          page:navigate(userURL(url))
        elseif tabs[activeTab] then
          tabs[activeTab].url = url
        end
        ui.sameLine(0, 20)
        ui.setCursorY(0)
        local favUrl = page:url():gsub('#.+', '')
        if touchscreen.button('##fav', btnSize, rgbm.colors.black, 0, favs[favUrl] and ui.Icons.StarFull or ui.Icons.StarEmpty, 14) then
          if favs[favUrl] then
            favs[favUrl] = nil
          else
            favs[favUrl] = page:title(true)
            favicons.store(page)
          end
          saveFavs()
        end
        ui.sameLine(0, 12)
        ui.setCursorY(0)
        if touchscreen.button('##share', btnSize, rgbm.colors.black, 0, ui.Icons.Undo, 14) then
          ac.setClipboadText(page:url())
          ui.toast(ui.Icons.Earth, 'Link to current webpage is copied to the clipboard')
        end
        ui.sameLine(0, 12)
        ui.setCursorY(0)
        if touchscreen.button('##newtab', btnSize, rgbm.colors.black, 0, ui.Icons.Plus, 14, #tabs > 8) then
          tabs[#tabs + 1] = createTab()
          activeTab = #tabs
        end
        ui.sameLine(0, 12)
        ui.setCursorY(0)
        if tabsCountPrev ~= #tabs then
          tabsCountPrev = #tabs
          if not tabsIcon then
            tabsIcon = ui.ExtraCanvas(64, 4)
          end
          tabsIcon:clear(rgbm.colors.transparent):update(function (dt)
            ui.drawRect(4, 60, rgbm.colors.white, 8, ui.CornerFlags.All, 8)
            ui.pushDWriteFont('Segoe UI;Weight=Bold')
            ui.dwriteDrawTextClipped(tabsCountPrev, 40, 0, 64, ui.Alignment.Center, ui.Alignment.Center, false)
            ui.popDWriteFont()
          end)
        end
        if touchscreen.button('##tabs', btnSize, rgbm.colors.black, 0, tabsIcon, 14) then
          tabsViewActive = 1
          navbarActive = 0
          page:focus(false)
        end
      end
      ui.drawSimpleLine(vec2(0, 32), vec2(ui.windowWidth(), 32), rgbm(0.5, 0.5, 0.5, navbar), 2)
      if page:loading() then
        ui.drawSimpleLine(vec2(0, 32), vec2(ui.windowWidth() * page:loadingProgress(), 32), rgbm(0, 0.5, 1, 1), 2)
      end
    end)
  end
end