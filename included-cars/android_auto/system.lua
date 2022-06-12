require('touchscreen')

ac.setLogSilent(true)
ui.setAsynchronousImagesLoading(true)

local size = ac.currentDisplaySize()

---System, like a simple version of some sort of operating system running
---apps. Use its functions to run other apps, set notifications and more.
---@diagnostic disable-next-line: lowercase-global
system = {
  bgColor = rgbm(0.05, 0.05, 0.05, 1),
  statusColor = rgbm(0.2, 0.2, 0.2, 1),
  statusIconColor = rgbm(1, 1, 1, 1),
  statusWidth = 260,
  statusHeight = 34,
  topBarHeight = 24,
  bottomBarHeight = 50,
  narrowMode = size.x / size.y < 1.75  -- reduce side padding if `narrowMode` is `true`
}

local appCurrent, appNext, appRunning
local appTransition = 1
local appTransitionBack = false
local fullscreenNext = false
local fullscreenTransition = 0
local transparentTopBarNext = false
local btnHomePressed = 0
local appStatus = false
local appStatusTransition = 0
local apps = {}
local services = {}

local serviceDelay = 0  -- services update rarely
local notifications = {}  -- app to its notification table (single notification per app)
local notificationsSorted = {}
local showNotifications = false
local notificationsTransition = 0
local popupNotification = nil  -- latest notification to be shown as a popup
local popupTransition = 0
local popupDraggingOffset = 0
local newNotifications = false
local topBarColor = rgbm(0, 0, 0, 0.3)
local showPreviousApps = false
local previousAppsTransition = 0

local scrollBtn1 = 0
local scrollBtn2 = 0
local scrollV1, scrollV2 = vec2(), vec2()

local appIconSize = 64
local appIconMarginX = 32
local appIconMarginY = 32
local appIconTextSize = vec2(80, 24)
local appIconSideMargin = system.narrowMode and 60 or 140
local appIconArea = vec2(appIconMarginX + appIconTextSize.x, 4 + appIconMarginY + appIconSize + appIconTextSize.y)

local popups = {} ---@type {id: string, title: string, callback: function, fade: number, closed: boolean}[]

-- patching some of library APIs to make sure `appRunning` would be correct for callbacks called later
local function patchFn(g, name, n)
  local bak = g[name]
  if n == 1 then g[name] = function (cb, ...) local r = appRunning return bak(function (...) appRunning = r cb(...) end, ...) end end
  if n == 2 then g[name] = function (a1, cb, ...) local r = appRunning return bak(a1, function (...) appRunning = r cb(...) end, ...) end end
  if n == 3 then g[name] = function (a1, a2, cb, ...) local r = appRunning return bak(a1, a2, function (...) appRunning = r cb(...) end, ...) end end
end
patchFn(_G, 'setTimeout', 1)
patchFn(_G, 'setInterval', 1)
patchFn(ac, 'OnlineEvent', 2)
patchFn(ac, 'onAlbumCoverUpdate', 1)
patchFn(ac, 'onClientConnected', 1)
patchFn(ac, 'onClientDisconnected', 1)
patchFn(ac, 'onRelease', 1)
patchFn(ac, 'onScreenshot', 1)

local function closeAllPopups()
  for i = 1, #popups do
    popups[i].closed = true
  end
end

---@param size number
local function drawAppIcon(app, size)
  if app.dynamicIcon then
    appRunning = app
    local pos = ui.getCursor()
    app.dynamicIcon(pos, size)
    ui.setCursor(pos)
    ui.dummy(size)
  else
    ui.image(app.icon, size)
  end
end

local function drawAppListIcon(app)
  if not ui.areaVisible(appIconArea) then
    ui.dummy(appIconArea)
    return
  end
  ui.pushID(app.id)
  ui.offsetCursorX(appIconMarginX)
  ui.beginGroup()
  ui.offsetCursorX((appIconTextSize.x - appIconSize) / 2)
  ui.offsetCursorY(appIconMarginY)
  drawAppIcon(app, appIconSize)
  if app.notificationMark then
    local c = ui.getCursor()
    c.x = c.x + appIconSize
    c.y = c.y - 12
    ui.drawCircleFilled(c, 8, rgbm.colors.red)
  end
  ui.textAligned(app.name, 0.5, appIconTextSize)
  ui.endGroup()
  ui.popID()
  if touchscreen.itemTapped() then
    system.openApp(app)
  end
end

local function drawListOfApps(dt)
  ui.childWindow('appsList', ui.availableSpace(), function ()
    ui.offsetCursorX(appIconSideMargin)
    ui.beginGroup()
    for i = 1, #apps do
      local app = apps[(i - 1) % #apps + 1]
      drawAppListIcon(app)
      ui.sameLine(0, appIconMarginX)
      if ui.availableSpaceX() < appIconSideMargin + appIconTextSize.x + appIconMarginX then
        ui.newLine()
      end
    end
    ui.endGroup()
    ui.offsetCursorY(40)
    system.scrolling(dt)
  end)
end

local settings = ac.storage({
  background = __dirname..'/res/background.jpg'
}, 'system')
local backgroundOverride

local appLauncher = {
  main = function (dt)
    system.transparentTopBar()
    ui.drawImage(backgroundOverride or settings.background, 0, ui.windowSize(), true)
    ui.offsetCursorY(system.topBarHeight)
    drawListOfApps(dt)
  end
}

local _offsetPos, _scrollOffset = vec2(), vec2()

local function drawApp(app, space, dt, offset)
  ui.setAsynchronousImagesLoading(true)
  local offsetPos = _offsetPos:set(offset ^ 2 * math.sign(offset) * space.x, 0)
  local resumeInput = notificationsTransition > 0.01 and touchscreen.stopInput()
  ui.setCursor(offsetPos)
  ui.childWindow(app.name, space, function ()
    if app.displays then
      for i = 1, #app.displays do 
        ac.setDynamicTextureShift(app.displays[i], 1, offsetPos) 
      end
      touchscreen.forceAwake()
    else
      local o = _scrollOffset:set(ui.getScrollX(), ui.getScrollY())
      ui.drawRectFilled(o, ui.availableSpace():add(o), system.bgColor)
    end
    appRunning = app
    if type(app.main) == 'function' then
      app.main(dt, app.args)
      if app.args then app.args = nil end
    elseif offset < 0.5 and type(app.main) == 'string' then
      app.main = require(app.main)
    end
  end)
  if resumeInput then resumeInput() end
end

local function drawTopBar(space, transition)
  if transition < 0.001 then return end
  ui.setCursor(vec2(0, math.ceil(system.topBarHeight * (transition - 1))))
  ui.childWindow('__topBar', vec2(space.x, system.topBarHeight), function ()
    ui.drawRectFilledMultiColor(vec2(0, 0), vec2(space.x, system.topBarHeight),
      topBarColor, topBarColor, rgbm.colors.transparent, rgbm.colors.transparent)
    ui.pushFont(ui.Font.Title)
    ui.textAligned(string.format('%02d:%02d', sim.timeHours, sim.timeMinutes), 0.5, vec2(68, system.topBarHeight))

    ui.sameLine(ui.windowWidth() - 126*24/32 - 8 - 60)
    ui.setCursorY(4)
    ui.icon(ui.weatherIcon(sim.weatherType), system.topBarHeight - 4)
    ui.sameLine(ui.windowWidth() - 126*24/32 - 8 - 30)
    ui.setCursorY(0)
    ui.textAligned(string.format('%.0f°', sim.ambientTemperature), vec2(0, 0.5), vec2(25, system.topBarHeight))
    ui.popFont()

    ui.sameLine(ui.windowWidth() - 126*24/32 - 8)
    ui.offsetCursorY(2)
    local c = ui.getCursor()
    ui.drawImage(__dirname..'/res/toolbar.png', c, c + vec2(126*24/32, 24))
    local s = ac.estimateSatelliteOcclusion()
    s = math.ceil(s * 6) / 6
    ui.drawTriangleFilled(c + vec2(52, 22), c + vec2(70, 22), c + vec2(70, 4), rgbm(0.2, 0.2, 0.2, 1))
    ui.drawTriangleFilled(c + vec2(52, 22), c + vec2(52 + 18 * s, 22), c + vec2(52 + 18 * s, 22 - 18 * s), rgbm.colors.white)
  end)
end

local function drawBottomBar(space, dt)
  -- Find app with largest status priority if current one is unknown
  if appStatus == false then
    appStatus = table.maxEntry(apps, function (app) return app.status ~= nil and app.statusPriority > 0 and (app == appCurrent and 0.001 or app.statusPriority) or 0 end)
    if appStatus and (appStatus.statusPriority <= 0 or not appStatus.status) then appStatus = nil end
    if appStatus and type(appStatus.status) == 'string' then
      appStatus.status = require(appStatus.status)
    end
  end

  -- Background
  ui.drawRectFilled(vec2(0, space.y), vec2(space.x, space.y + system.bottomBarHeight), rgbm.colors.black)

  -- Home button
  ui.drawCircleFilled(vec2(40, space.y + system.bottomBarHeight * 0.5), system.bottomBarHeight * (0.27 + 0.05 * btnHomePressed), rgbm.colors.white, 24)
  ui.drawCircle(vec2(40, space.y + system.bottomBarHeight * 0.5), system.bottomBarHeight * 0.35, rgbm.colors.white, 24, 2)
  ui.setCursor(vec2(0, space.y))
  ui.invisibleButton('__btnHome', vec2(80, system.bottomBarHeight))
  if touchscreen.itemTapped() then
    if showPreviousApps then showPreviousApps = false
    else system.openApp(appLauncher, true) end
    closeAllPopups()
  elseif touchscreen.itemLongTapped() then
    showPreviousApps = true
    closeAllPopups()
  end
  btnHomePressed = math.applyLag(btnHomePressed, ui.itemHovered() and ui.mouseDown(ui.MouseButton.Left) and 1 or 0, 0.8, dt)

  -- App status
  if appStatus and appStatus.status then
    ui.setCursor(vec2(80, space.y))
    local width = math.lerp(system.statusHeight, system.statusWidth, appStatusTransition)
    local m = (system.bottomBarHeight - system.statusHeight) / 2
    ui.drawRectFilled(
      vec2(80 + system.statusHeight / 2, space.y + m),
      vec2(80 + width - system.statusHeight / 2, space.y + system.statusHeight + m), system.statusColor)
    ui.drawEllipseFilled(vec2(80 + width - system.statusHeight / 2, space.y + system.bottomBarHeight / 2), system.statusHeight / 2, system.statusColor, 20)
    ui.drawEllipseFilled(vec2(80 + system.statusHeight / 2, space.y + system.bottomBarHeight / 2), system.statusHeight / 2, system.statusIconColor, 20)
    ui.offsetCursorY(m)
    local appStatusWide = true
    ui.childWindow('__status', vec2(width, system.statusHeight), function ()
      ui.pushFont(ui.Font.Title)
      appRunning = appStatus
      if appStatus.status(dt) == false then
        appStatusWide = false
      end
      ui.popFont()
    end)
    appStatusTransition = math.applyLag(appStatusTransition, appStatusWide and 1 or 0, 0.85, dt)
  else
    appStatusTransition = math.applyLag(appStatusTransition, 0, 0.85, dt)
  end

  ui.setCursor(vec2(space.x - 60, space.y))
  if touchscreen.iconButton(newNotifications and ui.Icons.NotificationsAny or ui.Icons.Notifications, system.bottomBarHeight) then
    showNotifications = not showNotifications
    newNotifications = false
    if popupNotification then popupNotification.time = -1e9 end
  end
end

appNext = appLauncher

local previewBaseSize = ac.currentDisplaySize() - vec2(0, system.bottomBarHeight + system.topBarHeight)
local previewBasePos = ac.currentDisplayPosition() + vec2(0, system.topBarHeight)
local previewSize = previewBaseSize / 3

local function updateCurrentAppCanvas(app)
  if app ~= nil then
    if app.canvas == nil then app.canvas = ui.ExtraCanvas(previewBaseSize) end
    app.canvas:update(function (dt)
      ui.drawImage('dynamic::android_auto', 0, ui.availableSpace(),
        previewBasePos / ac.currentDisplayTextureResolution(),
        (previewBasePos + previewBaseSize) / ac.currentDisplayTextureResolution())
    end)
  end
end

local function onAppOpen(app, args)
  closeAllPopups()
  app.opened = ui.time()
  app.args = args
  if app.dynamicTextures then
    table.forEach(app.dynamicTextures, function (d) ac.setRenderingCameraActive(d, true) end)
  end
end

local function onAppClose(app)
  if app.displays then
    table.forEach(app.displays, function (d) ac.setDynamicTextureShift(d, 0) end)
  end
  if app.dynamicTextures then
    table.forEach(app.dynamicTextures, function (d) ac.setRenderingCameraActive(d, false) end)
  end
end

local notificationBgColor = rgbm(0.12, 0.12, 0.12, 1)

local function drawNotificationContent(notification, from, size)
  ui.setCursor(from + 25)
  if type(notification.icon) == 'function' then
    appRunning = notification.app
    notification.icon(50)
  else
    ui.icon(notification.icon, 50)
  end

  ui.setCursor(from + vec2(100, 25))
  ui.pushFont(ui.Font.Title)
  ui.text(notification.content)
  ui.popFont()

  ui.setCursor(from + vec2(100, 55))
  ui.pushStyleVarAlpha(0.5)
  ui.text(notification.details)
  ui.popStyleVar()

  if notification.nonPersistent then
    ui.drawLine(from + vec2(size.x - size.y, 20), from + vec2(size.x - size.y, size.y - 20), rgbm.colors.gray, 1)
    ui.setCursor(from + vec2(size.x - size.y, 0))
    if touchscreen.iconButton(ui.Icons.Cancel, vec2(size.y, size.y), rgbm.colors.white, nil, nil, 16) then
      appRunning = notification.app
      system.setNotification(nil)
    end
  end
end

local function drawNotification(notification, size)
  if not ui.areaVisible(size) then
    ui.dummy(size)
    return
  end

  local c = ui.getCursor()
  ui.drawRectFilled(c - 1, c + size + vec2(1, 4), rgbm(0, 0, 0, 0.25), 8)
  ui.drawRectFilled(c - 3, c + size + vec2(3, 6), rgbm(0, 0, 0, 0.15), 12)
  ui.drawRectFilled(c - 5, c + size + vec2(5, 8), rgbm(0, 0, 0, 0.1), 14)
  ui.drawRectFilled(c, c + size, notificationBgColor, 8)

  ui.pushID(notification.app.id)
  drawNotificationContent(notification, c, size)

  ui.setCursor(c)
  ui.invisibleButton(notification.app.id, size)
  ui.popID()
  return notification.content and touchscreen.itemTapped()
end

local popupRunning
local popupClosing = 0 -- increased by one while calling callback for closed popup; during that time, new popups end up behind main closing popup already opened

local function addPopup(popup)
  if #popups > 10 then
    error('Too many popups', 3)
  end

  popup.app = appRunning
  popup.fade = 0
  popup.id = popup.title..tostring(math.random())
  popup.closed = false

  touchscreen.pauseInput()
  local underlying = #popups > 0 and popups[#popups].closed and popupClosing > 0
  if underlying then
    popup.fade = 1
    table.insert(popups, #popups, popup)
  else
    table.insert(popups, popup)
  end
  return popup.id
end

local function closePopup(p)      
  p.closed = true
  if p.resultCallback then
    appRunning, popupRunning = p.app, p
    popupClosing = popupClosing + 1
    p.resultCallback(nil)
    popupClosing = popupClosing - 1
  end
end

local function drawPopups(space, popupStoppedInput, dt)
  touchscreen.forceAwake()
  local toRemove, retValue
  for i = 1, #popups do
    local p = popups[i]
    p.fade = math.applyLag(p.fade, p.closed and 0 or 1, 0.8, dt)
    ui.setCursor(vec2(math.floor(p.mirror and space.x * (p.fade - 1) or space.x * (1 - p.fade)), 0))
    if p.fade > 0.001 and p.fade < 0.999 then
      touchscreen.boostFrameRate()
    end

    if p.size then
      ui.childWindow(p.id, space, function ()
        ui.pushClipRectFullScreen()
        ui.drawRectFilled(-ui.windowPos(), space - ui.windowPos(), rgbm(0, 0, 0, p.fade * 0.8))
        ui.popClipRect()
        ui.offsetCursor((space - p.size) / 2)
        ui.childWindow(p.id..':content', p.size, function ()
          ui.drawRectFilled(0, p.size, system.bgColor, p.size and 20)
          if i == #popups and popupStoppedInput then
            popupStoppedInput()
            retValue = true
          end
          appRunning, popupRunning = p.app, p
          if p.callback(dt) == true then
            closePopup(p)
          end
        end)
        if ui.windowHovered() and touchscreen.tapped() then          
          closePopup(p)
        end
      end)
    else
      ui.childWindow(p.id, space, function ()
        ui.drawRectFilled(0, space, system.bgColor, p.size and 20)
        if i == #popups and popupStoppedInput then
          popupStoppedInput()
          retValue = true
        end

        ui.setCursor(vec2(20, 20 + system.topBarHeight))
        if touchscreen.iconButton(ui.Icons.ArrowLeft, 36) then
          closePopup(p)
        end
        ui.sameLine(0, 12)
        ui.offsetCursorY(4)

        if p.inputValue ~= nil then
          ui.pushFont(ui.Font.Title)
          ui.setNextItemWidth(ui.availableSpaceX() - 20)
          local changed
          p.inputValue, changed = touchscreen.inputText(p.title, p.inputValue, ui.InputTextFlags.Placeholder)
          if not p.inputFocused then
            ui.setKeyboardFocusHere()
            p.inputFocused = true
          end
          ui.popFont()
          appRunning, popupRunning = p.app, p
          if p.callback(dt, p.inputValue, changed) == true then
            closePopup(p)
          end
        else
          ui.dwriteTextAligned(p.title, 20, ui.Alignment.Start, ui.Alignment.Start, vec2(space.x - 130, 36), false, rgbm.colors.white)
          appRunning, popupRunning = p.app, p
          if p.callback(dt) == true then
            closePopup(p)
          end
        end
      end)
    end

    if p.fade < 0.001 and p.closed then
      toRemove = i
    end
  end
  if toRemove then
    table.remove(popups, toRemove)
  end
  return retValue
end

local function drawNotifications(space, dt)
  notificationsTransition = math.applyLag(notificationsTransition, showNotifications and 1 or 0, 0.8, dt)
  if notificationsTransition > 0.001 then
    local padding = system.narrowMode and 120 or 200
    ui.setCursor(vec2(0, 0))
    ui.childWindow('__notificationsList', vec2(space.x, math.ceil(space.y * notificationsTransition)), function ()
      ui.drawRectFilled(0, ui.windowSize(), rgbm.new(system.bgColor.rgb, 0.9), 0)
      ui.setCursor(vec2(0, 0))
      ui.childWindow('__notificationsScrolling', space, function ()
        ui.offsetCursorY(40)
        ui.indent(padding)
        local any = false
        for i = 1, #notificationsSorted do
          -- local n = notificationsSorted[(i - 1) % #notificationsSorted + 1]
          local n = notificationsSorted[i]
          if n.content then
            if drawNotification(n, vec2(ui.windowWidth() - padding * 2, 100)) then
              showNotifications = false
              local data = n.launchArgs
              if n.nonPersistent then
                appRunning = n.app
                system.setNotification(nil)
              end
              system.openApp(n.app, false, data)
            end
            ui.offsetCursorY(20)
            any = true
          end
        end
        if not any then
          ui.pushFont(ui.Font.Title)
          ui.text('No notifications')
          ui.popFont()
        end
        ui.unindent(padding)
        system.scrolling(dt)
      end)
    end)
  end
end

local popupNofiticationDisableInput

local function drawPopupNotification(space, dt)
  if popupNofiticationDisableInput then
    popupNofiticationDisableInput()
    popupNofiticationDisableInput = nil
  end

  local popupActive = popupNotification and ui.time() - popupNotification.time < 5
  popupTransition = math.applyLag(popupTransition, popupActive and 1 or 0, 0.8, dt)
  if popupActive then touchscreen.forceAwake() end

  if popupTransition > 0.001 then
    ui.setCursor(vec2(40, math.floor(math.lerp(-110, 20, popupTransition) + popupDraggingOffset)))
    ui.childWindow('__notificationPopup', vec2(space.x - 80, 100), function ()
      ui.pushClipRectFullScreen()
      ui.drawRectFilled(-1, ui.windowSize() + vec2(1, 4), rgbm(0, 0, 0, 0.25), 8)
      ui.drawRectFilled(-3, ui.windowSize() + vec2(3, 6), rgbm(0, 0, 0, 0.15), 12)
      ui.drawRectFilled(-5, ui.windowSize() + vec2(5, 8), rgbm(0, 0, 0, 0.1), 14)
      ui.popClipRect()
      ui.drawRectFilled(0, ui.windowSize(), notificationBgColor, 8)

      drawNotificationContent(popupNotification, vec2(), ui.windowSize())

      if ui.mouseDown() and ui.windowHovered() then
        popupDraggingOffset = popupDraggingOffset + ui.mouseDelta().y
      elseif popupDraggingOffset < -20 then
        popupNotification.time = -1e9
        newNotifications = false
      else
        popupDraggingOffset = math.applyLag(popupDraggingOffset, 0, 0.85, dt)
      end

      if touchscreen.tapped() and ui.windowHovered() and popupNotification.content then
        local data = popupNotification.launchArgs
        if popupNotification.nonPersistent then
          appRunning = popupNotification.app
          system.setNotification(nil)
        end
        system.openApp(popupNotification.app.id, false, data)
        popupNotification.time = -1e9
        newNotifications = false
      end

      if ui.windowHovered() then
        popupNofiticationDisableInput = touchscreen.stopInput()
      end
    end)
  else
    popupDraggingOffset = 0
  end
end

local function drawPreviousApps(space, dt)
  local wasShown = previousAppsTransition > 0.001
  previousAppsTransition = math.applyLag(previousAppsTransition, showPreviousApps and 1 or 0, 0.8, dt)
  if previousAppsTransition > 0.001 then
    if not wasShown then updateCurrentAppCanvas(appNext) end

    local offsetY = math.floor(space.y * (1 - previousAppsTransition))
    if space.y - offsetY < 1.5 then return end
    ui.setCursor(vec2(0, offsetY))
    ui.childWindow('__previousAppsList', vec2(space.x, space.y - offsetY), function ()
      ui.drawRectFilled(0, ui.windowSize(), rgbm.colors.black, 8)
      ui.setCursor(0)

      ui.childWindow('__previousAppsScrolling', space, function ()
        ui.offsetCursorY(40)
        ui.indent(200)

        local appsSorted = table.filter(apps, function (app)
          return app.opened ~= nil
        end)
        table.sort(appsSorted, function (a, b)
          return a.opened > b.opened
        end)

        ui.pushFont(ui.Font.Title)
        for i = 1, #appsSorted do
          local app = appsSorted[i]
          local cur = ui.getCursor()
          if app.canvas then
            ui.drawImage(app.canvas, cur, cur + previewSize)
          else
            ui.drawRectFilled(cur, cur + previewSize, rgbm.colors.black)
          end
          ui.offsetCursorY(previewSize.y + 10)
          drawAppIcon(app, 24)
          ui.sameLine(0, 8)
          ui.text(app.name)
          ui.setCursor(cur)
          ui.invisibleButton(app.id, previewSize + vec2(0, 40))
          if touchscreen.itemTapped() then
            showPreviousApps = false
            system.openApp(app)
          end
          ui.offsetCursorY(20)
        end
        ui.popFont()

        if #appsSorted == 0 then
          ui.pushFont(ui.Font.Title)
          ui.text('No recent apps')
          ui.popFont()
        end
        ui.unindent(200)
        system.scrolling(dt)
      end)
    end)
  end
end

local padding = system.narrowMode and 80 or 160
local screenshotTime = 0
system.lastScreenshot = nil ---@type ui.ExtraCanvas
system.screenshots = {}

-----------------------
-- Public system API --
-----------------------

---@alias App {id: string, name: string, icon: string, statusPriority: number, notificationPriority: number}

---Adds a new app.
---@param appID string
---@param appFolder string
function system.addApp(appID, appFolder)
  local manifestFilename = __dirname..'/'..appFolder..'/manifest.ini'
  if not io.fileExists(manifestFilename) then return end
  if io.fileExists(__dirname..'/'..appFolder..'/condition.lua') and require(appFolder..'/condition') == false then return end

  local manifest = ac.INIConfig.load(manifestFilename, ac.INIFormat.Extended)
  if manifest == nil then
    -- TODO: Why it was a nil that one time?
    ac.log('Failed to load manifest: '..manifestFilename)
    -- ac.debug('manifest', ac.INIConfig.load(manifestFilename, ac.INIFormat.Extended))
    return
  end

  local app = {
    id = appID,
    name = manifest:get('ABOUT', 'NAME', appID),
    displays = manifest:get('SCRIPTABLE_DISPLAY', 'DISPLAY', ac.INIConfig.OptionalList),
    dynamicTextures = manifest:get('DYNAMIC_TEXTURE', 'RENDERING_CAMERA', ac.INIConfig.OptionalList),
    icon = __dirname..'/'..appFolder..'/icon.png',
    main = io.fileExists(__dirname..'/'..appFolder..'/app.lua') and appFolder..'/app' or nil,
    status = io.fileExists(__dirname..'/'..appFolder..'/status.lua') and appFolder..'/status' or nil,
    statusPriority = manifest:get('STATUS', 'BASE_PRIORITY', 0),
    notificationPriority = manifest:get('NOTIFICATIONS', 'PRIORITY', 0),
  }
  appRunning = app
  if io.fileExists(__dirname..'/'..appFolder..'/service.lua') then
    local suc, ret = pcall(require, appFolder..'/service')
    if not suc then
      ac.log('App '..appID..' is not available: '..ret)
      return
    end
    app.service = ret
  end
  ac.log('App added: '..appID)
  if io.fileExists(__dirname..'/'..appFolder..'/icon.lua') then
    app.dynamicIcon = require(appFolder..'/icon')
  end
  if app.service and app.service ~= true then
    services[#services + 1] = app
  end
  if app.displays then
    table.forEach(app.displays, function (d) ac.setDynamicTextureShift(d, 0) end)
  end
  apps[#apps + 1] = app
  table.sort(apps, function (a, b) return a.name < b.name end)
end

---Launches an app.
---@param app string|table|nil @Either an app ID or a reference to app table. If `nil`, currently ran app is opened (to use in services or statuses).
---@param moveBack boolean? @If set to `true`, animation for opening app is played backwards.
---@param args any? @If set, value will be passed to the app in an argument after `dt`.
function system.openApp(app, moveBack, args)
  if app == nil then app = appRunning end
  if appNext == app then return end
  if type(app) == 'string' then
    app = table.findFirst(apps, function (a) return a.id == app end) or ac.warn('App is missing: '..app)
    if not app then return end
  end
  
  touchscreen.pauseInput()
  updateCurrentAppCanvas(appNext)
  appCurrent = appNext
  appNext = app
  appTransition = 0
  appTransitionBack = moveBack or app == appLauncher
  onAppOpen(app, args)
end

---Closes current app, returns to app launcher.
function system.closeApp()
  system.openApp(appLauncher, true)
end

---Sets app priority to show a status block. App with highest priority which is not
---currently opened will be shown in status block.
---@param priority number @If set to 0, status block will be hidden.
function system.setStatusPriority(priority)
  if appRunning and appRunning.statusPriority ~= priority then 
    appRunning.statusPriority = priority
    appStatus = false
  end
end

---Draws an icon of a current app in status block which, if tapped, launches the app.
---@param image string @If not set, app icon is used.
---@param iconBgColor rgbm
---@overload fun(iconBgColor: rgbm)
function system.statusIcon(image, iconBgColor)
  if image == nil or iconBgColor == nil then image, iconBgColor = iconBgColor, image end
  system.statusIconColor = iconBgColor
  if image == nil then
    local c = ui.getCursor()
    drawAppIcon(appRunning, ui.windowHeight())
    ui.setCursor(c)
  else
    ui.drawImageRounded(image, 0, ui.windowHeight(), rgbm.colors.white, 0, 1, ui.windowHeight() / 2)
  end
  ui.invisibleButton('__appIcon', ui.windowHeight())
  if touchscreen.itemTapped() then system.openApp() end
end

---Adds a new button to a status block, returns `true` if button was tapped.
---@param icon ui.Icons
function system.statusButton(icon, offsetX, isAvailable)
  ui.sameLine(0, offsetX)
  local u = ui.getCursorX()
  ui.invisibleButton(icon, system.statusHeight)
  ui.setCursorX(u + 10)
  ui.setCursorY(10)
  ui.icon(icon, ui.windowHeight() - 20, isAvailable ~= false and rgbm.colors.white or rgbm.colors.gray)
  return isAvailable ~= false and touchscreen.itemTapped()
end

---Sets or removes notification for the current app (call without arguments to remove notification).
---@param icon string|function @Icon, can be either a filename or a function to draw something custom.
---@param content string? @Notification title.
---@param details string? @Notification message.
---@param silent boolean? @If silent, there won’t be a popup, just a notification in notifications list.
---@param nonPersistent boolean? @If set, nofitication will disappear when clicked and can be discarded.
---@param launchArgs any? @If set, value will be passed to app when notification is clicked.
function system.setNotification(icon, content, details, silent, nonPersistent, launchArgs)
  if not appRunning then return end

  local data = notifications[appRunning]
  if not data then
    data = { app = appRunning }
    notifications[appRunning] = data
    notificationsSorted[#notificationsSorted + 1] = data
    table.sort(notificationsSorted, function (a, b)
      return a.app.notificationPriority == b.app.notificationPriority and a.app.name > b.app.name or a.app.notificationPriority > b.app.notificationPriority
    end)
  end

  data.icon = icon
  if data.content ~= content or data.details ~= details then
    data.nonPersistent = nonPersistent
    data.launchArgs = launchArgs
    data.content = content
    data.details = details
    data.time = ui.time()
    if not showNotifications and data.content and not silent and appRunning ~= appCurrent then
      touchscreen.forceAwake()
      popupNotification = data
      newNotifications = true
    elseif popupNotification == data then
      popupNotification.time = -1e9
    end
    if content == nil then      
      local any = false
      for i = 1, #notificationsSorted do
        if notificationsSorted[i].content then
          any = true
        end
      end
      if not any then
        newNotifications = false
      end
    end
  end
end

---Closes app’s nofication if `launchArgs` matches one set in nofitication.
function system.closeNotificationWith(launchArgs)
  local data = notifications[appRunning]
  if data and data.launchArgs == launchArgs then
    system.setNotification(nil)
  end
end

---Sets or removes notification mark
function system.notificationMark(active)
  appRunning.notificationMark = active
end

---Switches to fullscreen mode (hides top bar). Call each frame to keep fullscreen mode active.
function system.fullscreen()
  fullscreenNext = true
end

---Switches top bar to transparent. Call each frame to keep it this way.
function system.transparentTopBar()
  transparentTopBarNext = true
end

---Returns `true` if current app is active app (can be used in services or status blocks).
function system.isAppActive()
  return appRunning == appCurrent
end

---Returns active app. Please do not alter any properties apart from ones described in App alias.
---@return App
function system.foregroundApp()
  return appCurrent
end

---Returns currently running app. Please do not alter any properties apart from ones described in App alias.
---@return App
function system.runningApp()
  return appRunning
end

---Returns icon for the current app.
---@return string
function system.appIcon()
  return appRunning.icon
end

---Opens popup window.
---@param title string
---@param callback fun(dt: number)
---@param resultCallback nil|fun(result: any)
---@return string @Returns popup ID.
function system.openPopup(title, callback, resultCallback)
  return addPopup{
    title = title,
    callback = callback, resultCallback = resultCallback
  }
end

---Opens compact popup window.
---@param title string
---@param size string
---@param callback fun(dt: number)
---@param resultCallback nil|fun(result: any)
---@return string @Returns popup ID.
function system.openCompactPopup(title, size, callback, resultCallback)
  return addPopup{
    title = title, size = size,
    callback = callback, resultCallback = resultCallback
  }
end

---Opens popup window with text input.
---@param title string
---@param defaultValue string
---@param callback fun(dt: number, value: string, changed: boolean)
---@param resultCallback nil|fun(result: any)
---@return string @Returns popup ID.
function system.openInputPopup(title, defaultValue, callback, resultCallback)
  return addPopup{
    title = title, inputValue = defaultValue or '',
    callback = callback, resultCallback = resultCallback
  }
end

---Sets data associated with popup.
---@param popupID string
---@param data any
function system.setPopupData(popupID, data)
  local p = table.findFirst(popups, function (p) return p.id == popupID end)
  if p then
    p._extraData = data
  end
end

---Gets data associated with popup.
---@param popupID string @If not set, current popup is used
function system.getPopupData(popupID)
  local p = not popupID and popupRunning or table.findFirst(popups, function (p) return p.id == popupID end)
  if p then
    return p._extraData
  end
end

---Closes popup with a given ID, optionally sets a reply to pass to a popup opening function.
---@param popupID string @If not set, current popup is used
---@param result any
function system.closePopup(popupID, result)
  local p = not popupID and popupRunning or table.findFirst(popups, function (p) return p.id == popupID end)
  if p then
    p.closed, p.result = true, result
    if p.resultCallback then 
      appRunning, popupRunning = p.app, p
      popupClosing = popupClosing + 1
      p.resultCallback(result)
      popupClosing = popupClosing - 1
    end
  end
end

---Special scrollbar styled to look similar to Android Auto
---@param dt number
function system.scrolling(dt, offsetX)
  local opacity = touchscreen.scrolling(true)

  local scrollMax = ui.getScrollMaxY()
  if scrollMax > 1 then
    local window = ui.windowSize()
    local scrollY = ui.getScrollY()
    local barMarginY = 80
    local barArea = window.y - barMarginY * 2
    local barX = (system.narrowMode and 40 or 120) + (offsetX or 0)
    local barHeight = math.lerp(40, barArea, window.y / (scrollMax + window.y))
    local barY = scrollY + barMarginY + scrollY / scrollMax * (barArea - barHeight)
    local btnSize = 8
    local btn1Y = barMarginY + scrollY - 34
    local btn2Y = barMarginY + barArea + scrollY + 34
    local itemColor = rgbm(1, 1, 1, 0.3 + 0.3 * opacity)
    ui.setCursor(0)
    ui.drawLine(scrollV1:set(barX, barY), scrollV2:set(barX, barY + barHeight), itemColor, 3)

    itemColor.mult = 0.3 + 0.3 * scrollBtn1
    ui.pathLineTo(scrollV1:set(barX - btnSize, btn1Y + btnSize))
    ui.pathLineTo(scrollV1:set(barX, btn1Y))
    ui.pathLineTo(scrollV1:set(barX + btnSize, btn1Y + btnSize))
    ui.pathStroke(itemColor, false, 3)
    if ui.mouseDown() and ui.rectHovered(scrollV1:set(barX - 40, btn1Y - 40), scrollV2:set(barX + 40, btn1Y + 40)) then
      ui.setScrollY(-40, true)
      scrollBtn1 = math.applyLag(scrollBtn1, 1, 0.8, dt)
    else
      scrollBtn1 = math.applyLag(scrollBtn1, 0, 0.8, dt)
    end

    itemColor.mult = 0.3 + 0.3 * scrollBtn2
    ui.pathLineTo(scrollV1:set(barX - btnSize, btn2Y - btnSize))
    ui.pathLineTo(scrollV1:set(barX, btn2Y))
    ui.pathLineTo(scrollV1:set(barX + btnSize, btn2Y - btnSize))
    ui.pathStroke(itemColor, false, 3)
    if ui.mouseDown() and ui.rectHovered(scrollV1:set(barX - 40, btn2Y - 40), scrollV2:set(barX + 40, btn2Y + 40)) then
      ui.setScrollY(ui.getScrollY() + 40, true)
      scrollBtn2 = math.applyLag(scrollBtn2, 1, 0.8, dt)
    else
      scrollBtn2 = math.applyLag(scrollBtn2, 0, 0.8, dt)
    end
  end
end

---AA scrolling list automatically handling padding and all that.
---@param dt number
---@param size vec2
---@param callback fun(dt: number)
---@overload fun(dt: number, callback: function)
function system.scrollList(dt, size, callback)
  if type(size) == 'function' then size, callback = ui.availableSpace(), size end
  ui.offsetCursorX(padding)
  ui.childWindow('scrollList', size - vec2(padding * 2, 0), function ()
    ui.offsetCursorY(40)
    callback(dt)
    ui.offsetCursorY(40)
    ui.pushClipRectFullScreen()
    system.scrolling(dt, -padding)
    ui.popClipRect()
  end)
end

---Adds fading out for the top bit of a scrolling list.
function system.scrollFadeTop()
  ui.drawRectFilledMultiColor(vec2(0, ui.getScrollY()), vec2(ui.windowWidth(), ui.getScrollY() + 8),
    system.bgColor, system.bgColor, rgbm.new(system.bgColor.rgb, 0), rgbm.new(system.bgColor.rgb, 0))
end

---Draws contact icon. Default size: 40.
function system.contactIcon(carIndex, driverName, size)
  size = size or 40
  local c = ui.getCursor()
  local firstLetter = (driverName or ac.getDriverName(carIndex) or ''):match('[A-Za-z]')
  local themeName = 'car'..tostring(carIndex)..'::special::theme'
  if ui.imageSize(themeName).x == 0 then
    ui.drawCircleFilled(c + size / 2, size / 2, rgbm.colors.black, 24)
  else
    ui.drawImageRounded(themeName, c, c + size, 20)
  end
  ui.dwriteTextAligned(firstLetter and firstLetter:upper() or '?', 30 * size / 40, ui.Alignment.Center, ui.Alignment.Center, vec2(size + 1, size - 2))
end

---Changes wallpaper, re-saves given image locally (image can be a canvas).
function system.setWallpaper(image)
  local customFilename = __dirname..'/res/_custom_background.jpg'
  ui.setAsynchronousImagesLoading(false)
  ui.unloadImage(customFilename)
  ui.ExtraCanvas(ui.imageSize(image)):update(function () ui.drawImage(image, 0, ui.windowSize()) end):save(customFilename)
  settings.background = customFilename
  backgroundOverride = image
  ui.setAsynchronousImagesLoading(true)
end

----------------------------------------------------------------------------
-- Main update function (which can change dynamically to alter behaviour) --
----------------------------------------------------------------------------

local function checkCompatibility()
  if size.y < 320 or size.x < 640 then
    return string.format('Display is too small: %d×%d\nFor system to function, resolution should be at least 320×640',
      size.y, size.x)
  end
  if size.y > 800 or size.x > 1280 then
    return string.format('Display is too large: %d×%d\nFor system to function, resolution should not be larger than 800×1280',
      size.y, size.x)
  end
  if size.x < size.y * 4/3 then
    return string.format('Display is too narrow: %d×%d (%.2f)\nFor system to function, aspect ratio should be at least 4:3 (1.33)',
      size.y, size.x, size.x / size.y)
  end
  if car.year < 2015 and not ac.configValues({aftermarketComponent = false}).aftermarketComponent then
    return string.format('Car is too old to have this system as a factory-installed component (this OS was released in 2015, car was made in %d)\nIf you are adding it as an aftermarket component, add “aftermarketComponent=1” to the config', car.year)
  end
end

local function actualUpdate(dt)
  ui.setAsynchronousImagesLoading(true)
  touchscreen.update(appNext ~= appCurrent, dt)

  if serviceDelay > 0 then
    serviceDelay = serviceDelay - dt
  else
    serviceDelay = 0.5
    for i = 1, #services do
      appRunning = services[i]
      services[i].service(0.5)
    end
  end

  local space = ui.availableSpace()
  space.y = space.y - system.bottomBarHeight

  local popupStoppedInput
  if #popups > 0 then
    popupStoppedInput = touchscreen.stopInput()
  end

  fullscreenNext = false
  transparentTopBarNext = false
  if previousAppsTransition < 0.5 then
    if appNext ~= appCurrent then
      appTransition = appTransition + dt * 4
      if appTransition >= 1 then
        if appCurrent then onAppClose(appCurrent) end
        appCurrent = appNext
        appStatus = false
        drawApp(appCurrent, space, dt, 0)
      else
        drawApp(appCurrent, space, dt, appTransitionBack and appTransition or -appTransition)
        drawApp(appNext, space, dt, appTransitionBack and appTransition - 1 or 1 - appTransition)
      end
    else
      drawApp(appCurrent, space, dt, 0)
    end
  end
  fullscreenTransition = math.applyLag(fullscreenTransition, fullscreenNext and 1 or 0, 0.8, dt)
  topBarColor.mult = math.applyLag(topBarColor.mult, transparentTopBarNext and 0 or 0.5, 0.8, dt)

  if #popups > 0 and drawPopups(space, popupStoppedInput, dt) then popupStoppedInput = nil end
  if ac.isSkippingFrame() then return end

  ui.pushFont(ui.Font.Main)
  drawNotifications(space, dt)
  drawPreviousApps(space, dt)
  drawTopBar(space, 1 - fullscreenTransition)
  drawBottomBar(space, dt)
  drawPopupNotification(space, dt)
  ui.popFont()

  if popupStoppedInput then
    popupStoppedInput()
  end

  touchscreen.keyboard()

  if ac.isControllerGearDownPressed() and ac.isControllerGearUpPressed() and screenshotTime <= 0 then
    system.lastScreenshot = ui.ExtraCanvas(ui.windowSize())
    system.lastScreenshot:update(function ()
      ui.drawImage('dynamic::android_auto', 0, ui.availableSpace(),
        ac.currentDisplayPosition() / ac.currentDisplayTextureResolution(),
        (ac.currentDisplayPosition() + ac.currentDisplaySize()) / ac.currentDisplayTextureResolution())
    end)
    if #system.screenshots >= 9 then
      table.remove(system.screenshots, 1)
    end
    table.insert(system.screenshots, system.lastScreenshot)
    screenshotTime = 1
  end
  if screenshotTime > 0 then
    touchscreen.boostFrameRate()
    ui.setCursor(0)
    ui.childWindow('screenshot', ui.windowSize(), function ()
      local pad = (1 - math.saturate(screenshotTime * 1.8 - 0.8) ^ 2) * 0.35
      local off = (1 - screenshotTime) ^ 2
      local offset = vec2(-pad * ui.windowWidth() + 40, (ui.windowHeight() - 40) * off)
      ui.drawRectFilled(ui.windowSize() * pad + offset - 8, ui.windowSize() * (1 - pad) + offset + 8, system.bgColor, 28)
      ui.drawImageRounded(system.lastScreenshot, ui.windowSize() * pad + offset, ui.windowSize() * (1 - pad) + offset, 20)
      ui.drawRectFilled(0, ui.windowSize(), rgbm(1, 1, 1, math.saturate(screenshotTime * 3 - 2)))
    end)
    if screenshotTime > 0.452 then
      screenshotTime = screenshotTime - dt * math.lerpInvSat(screenshotTime, 0.45, 0.55)
    elseif car.gas < 0.8 or car.brake < 0.8 then
      screenshotTime = screenshotTime - dt * math.lerpInvSat(screenshotTime, 0.455, 0.35)
    end
  end
end

-- If screen does not have right dimensions, `update()` would just draw a warning.
local compatibilityError = checkCompatibility()
if compatibilityError then
  function system.update(dt)
    ui.drawRectFilled(0, ui.windowSize(), rgbm.colors.black)
    ui.offsetCursor(20)
    ui.textWrapped(compatibilityError)
  end
  return
end

if ac.configValues({alignmentTest = false}).alignmentTest then
  function system.update(dt)
    ui.drawRectFilled(0, ui.windowSize(), rgbm.colors.blue)
    for i = 1, 9 do
      ui.drawLine(vec2(0, ui.windowHeight() * i / 10), vec2(ui.windowWidth(), ui.windowHeight() * i / 10), rgbm.colors.white, 2)
    end
    for i = 1, 19 do
      ui.drawLine(vec2(ui.windowWidth() * i / 20, 0), vec2(ui.windowWidth() * i / 20, ui.windowHeight()), rgbm.colors.white, 2)
    end
  end
  return
end


-- Otherwise, at first `update()` would load list of apps and then load apps one by one to keep things running smooth.
local appsToAdd
function system.update(dt)
  ui.setAsynchronousImagesLoading(true)
  if appsToAdd == nil then
    appsToAdd = {}
    io.scanDir(io.relative('apps'), function (fileName, fileAttributes)
      if fileAttributes.isDirectory then
        appsToAdd[#appsToAdd + 1] = fileName
      end
    end)
  elseif #appsToAdd > 0 then
    system.addApp(appsToAdd[1], 'apps/'..appsToAdd[1])
    table.remove(appsToAdd, 1)
  else
    system.update = actualUpdate
    -- system.openApp('wallpapers')
    -- system.openApp('gallery')
    -- system.openApp('radio')
  end

  ui.drawRectFilled(0, ui.windowSize(), rgbm.colors.black)
  ui.setCursor(ui.windowSize() / 2 - 30)
  touchscreen.loading(60)
end
