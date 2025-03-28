local utils = require('utils')
local loadedData ---@type AppInfo[]|string|true|nil

---@param app AppInfo
---@return boolean
local function appDetails(app)
  ui.offsetCursor(4)
  ui.image(app.meta.icon, 32)
  ui.sameLine(0, 16)
  ui.offsetCursorY(-4)
  ui.beginGroup()
  ui.textWrapped(app.meta.description)
  ui.offsetCursorY(8)
  ui.pushFont(ui.Font.Small)
  if app.meta.author ~= 'x4fab' then
    ui.text('Author: %s' % app.meta.author)
  end
  ui.text('Version: %s' % app.meta.version)
  ui.text('Size: %s' % app.displaySize)
  if app.domainName then
    ui.text('More: ')
    ui.sameLine(0, 0)
    if ui.textHyperlink(app.domainName) then
      os.openURL(app.meta.detailsURL)
    end
    if ui.itemHovered() then
      ui.setTooltip(app.meta.detailsURL)
    end
  end
  if app.installed then
    ui.text('Location: ')
    ui.sameLine(0, 0)
    local shortLocation = app.location:regmatch('apps\\\\lua.+')
    if ui.textHyperlink(shortLocation) then
      os.openInExplorer(app.location)
    end
    if ui.itemHovered() then
      ui.setTooltip(app.location)
    end
  end
  ui.popFont()
  ui.endGroup()

  ui.offsetCursorY(12)
  local w = ui.availableSpaceX()
  if app.installing == true then
    w = w / 2 - 4
    ui.modernButton('Installing…', vec2(w, 40), ui.ButtonFlags.Disabled, ui.Icons.LoadingSpinner)
  elseif app.installing then
    w = w / 2 - 4
    ui.modernButton('Failed to install', vec2(w, 40), ui.ButtonFlags.Disabled, ui.Icons.Warning)
  elseif app.installed == app.meta.version then
    w = w / 3 - 8
    if ui.modernButton('Open', vec2(w, 40), ui.ButtonFlags.None, ui.Icons.AppWindow) then
      ac.setAppOpen(app.meta.id)
      return true
    end
    ui.sameLine(0, 4)
    if ui.modernButton('Uninstall', vec2(w, 40), ui.ButtonFlags.None, ui.Icons.Trash) then
      utils.uninstallApp(app)
      return true
    end
  elseif app.installed then
    w = w / 3 - 8
    if ui.modernButton('Update', vec2(w, 40), ui.ButtonFlags.Confirm, ui.Icons.Download) then
      utils.installApp(app)
      return true
    end
    ui.sameLine(0, 4)
    if ui.modernButton('Uninstall', vec2(w, 40), ui.ButtonFlags.None, ui.Icons.Trash) then
      utils.uninstallApp(app)
      return true
    end
  else
    w = w / 2 - 4
    if ui.modernButton('Install', vec2(w, 40), ui.ButtonFlags.Confirm, ui.Icons.Download) then
      utils.installApp(app)
      return true
    end
  end
  ui.sameLine(0, 4)
  if ui.modernButton('Close', vec2(w, 40), ui.ButtonFlags.None, ui.Icons.Cancel) then
    return true
  end

  return false
end

local function ensureDataIsLoaded()
  if not loadedData then
    loadedData = true
    utils.loadApps(function (err, data)
      loadedData = err and tostring(err) or data
      if data then
        local cfg = utils.config()
        local knownApps = stringify.tryParse(cfg.knownApps, nil, {})
        local newApps = table.map(data, function (item)
          if not table.contains(knownApps, item.meta.id) then
            if cfg.notifyAboutNewApps then
              item.newApp = true
            end
            return item.meta.id
          else
            return nil
          end
        end)
        if #newApps > 0 then
          cfg.knownApps = stringify(table.chain(knownApps, newApps), true)
        end
      end
    end)
  end
end

function script.windowMain(dt)
  local cfg = utils.config()

  ensureDataIsLoaded()
  if loadedData == true then
    ui.drawLoadingSpinner(ui.windowSize() / 2 - 20, ui.windowSize() / 2 + 20)
  elseif type(loadedData) == 'table' then
    ac.setWindowNotificationCounter('main', 0)

    for i, app in ipairs(loadedData) do
      ui.pushID(i)
      local s = ui.getCursorY()
      ui.pushStyleVar(ui.StyleVar.FrameRounding, 2)
      if ui.button('##btn', vec2(-0.01, 48)) then
        ui.modalDialog(app.meta.name, function () return appDetails(app) end, true)
      end
      if ui.itemHovered() then
        ui.setTooltip(app.meta.description)
      end

      if app.newApp then
        ui.notificationCounter()
      end

      ui.setCursorY(s + 8)
      ui.offsetCursorX(16)
      ui.image(app.meta.icon, 32)
      ui.sameLine(0, 16)
      ui.beginGroup()
      ui.textAligned(app.meta.name, 0, vec2(-0.01, 0), true)
      ui.pushFont(ui.Font.Small)
      ui.drawRectFilled(ui.getCursor():add(vec2(0, -2)), ui.getCursor():add(vec2(56, 13)), rgbm(0, 0, 0, 0.3), 2)
      ui.beginScale()
      ui.drawTextClipped(app.meta.category, ui.getCursor():add(vec2(0, -3)), ui.getCursor():add(vec2(56, 14)), rgbm.colors.white, 0.5, true)
      ui.endScale(0.9)
      ui.offsetCursorX(64)
      ui.offsetCursorY(2)
      if app.installed == app.meta.version then
        ui.image(ui.Icons.Confirm, 8, rgbm.colors.lime)
        if ui.itemHovered() then
          ui.setTooltip('Latest version installed')
        end
        ui.sameLine(0, 4)
      elseif app.installed then
        ui.image(ui.Icons.ArrowUp, 8, rgbm.colors.yellow)
        if ui.itemHovered() then
          ui.setTooltip('Update is available (installed version: v%s)' % app.installed)
        end
        ui.sameLine(0, 4)
      elseif app.installing == true then
        ui.drawLoadingSpinner(ui.getCursor(), ui.getCursor() + 8, rgbm.colors.white)
        ui.dummy(8)
        if ui.itemHovered() then
          ui.setTooltip('Installing…')
        end
        ui.sameLine(0, 4)
      elseif app.installing then
        ui.image(ui.Icons.Warning, 8, rgbm.colors.orange)
        if ui.itemHovered() then
          ui.setTooltip('Failed to install: %s' % tostring(app.installing))
        end
        ui.sameLine(0, 4)
      else
        ui.image(ui.Icons.Skip, 8, rgbm.colors.white)
        if ui.itemHovered() then
          ui.setTooltip('Available to install (%s)' % app.displaySize)
        end
        ui.sameLine(0, 4)
      end
      ui.offsetCursorY(-2)
      ui.textAligned(app.meta.author ~= 'x4fab' 
        and 'v'..app.meta.version..' by '..app.meta.author
        or 'v'..app.meta.version, 0, vec2(-4, 0), true)
      ui.popFont()
      ui.endGroup()

      ui.setCursorY(s + 56)
      ui.popStyleVar()
      ui.popID()
    end
    if not cfg.settingsOpenedOnce then
      ui.pushFont(ui.Font.Small)
      ui.textWrapped('More apps are coming soon. Check App Shelf settings if you want to get a notification when a new app would be available.')
      ui.popFont()
    end
  else
    ui.offsetCursorY(12)
    ui.header('Error')
    ui.textWrapped('Failed to load list of apps:\n%s' % (loadedData or 'unknown error'))
  end
end

function script.windowMainSettings()
  local cfg = utils.config()
  cfg.settingsOpenedOnce = true

  if ui.checkbox('Notify about new apps', cfg.notifyAboutNewApps) then
    cfg.notifyAboutNewApps = not cfg.notifyAboutNewApps
  end
  if ui.itemHovered() then
    ui.setTooltip('Show notification mark in taskbar if there are new apps on the shelf ready to be installed')
  end

  if cfg.automaticallyInstallUpdates then ui.pushDisabled() end
  if ui.checkbox('Notify about updates', cfg.notifyAboutUpdates) then
    cfg.notifyAboutUpdates = not cfg.notifyAboutUpdates
  end
  if cfg.automaticallyInstallUpdates then ui.popDisabled() end
  if ui.itemHovered() then
    ui.setTooltip('Show notification mark in taskbar if there are new updates to be installed')
  end
  if ui.checkbox('Install updates automatically', cfg.automaticallyInstallUpdates) then
    cfg.automaticallyInstallUpdates = not cfg.automaticallyInstallUpdates
  end
  if ui.itemHovered() then
    ui.setTooltip('Automatically install new apps when possible')
  end

  if ui.checkbox('Open new apps immediately', cfg.openOnceInstalled) then
    cfg.openOnceInstalled = not cfg.openOnceInstalled
  end
  if ui.itemHovered() then
    ui.setTooltip('Automatically open new apps after installing')
  end
end

local rescanning = false
ac.onFolderChanged(ac.getFolder(ac.FolderID.ACAppsLua), '?', false, function (files)
  if rescanning then return end
  rescanning = true
  setTimeout(function ()
    rescanning = false
    if type(loadedData) == 'table' then
      for _, v in ipairs(loadedData) do
        utils.refreshApp(v)
      end
    end
  end, 0.5)
end)

local attemped = {}

---@param app AppInfo|{reason: string?}
---@param originName string
---@param callback fun(err: string?)? 
local function installThirdPartyApp(app, originName, callback)
  ensureDataIsLoaded()
  if loadedData == true then
    setTimeout(installThirdPartyApp:bind(app, originName, callback), 1)
  elseif type(loadedData) == 'table' then
    if not attemped[app.meta.id] then
      attemped[app.meta.id] = true
    elseif callback then
      callback('Already tried') 
      return
    end
    
    for i = 1, #loadedData do
      if loadedData[i].meta.id == app.meta.id then
        if not loadedData[i].installed and not loadedData[i].installing then
          ui.modalPopup('Install %s?' % loadedData[i].meta.name,
            '%s offers to install an app %s%s. Would you like to proceed?'
            % {originName, loadedData[i].meta.name, app.reason and ': %s' % app.reason or ''}, function (agreed)
            if agreed then
              utils.installApp(loadedData[i], callback)
            elseif callback then
              callback('Cancelled')  
            end
          end)
        elseif callback then
          callback(nil)
        end
        return
      end
    end
    if type(app.meta.downloadURL) == 'string' and type(app.meta.name) == 'string' then
      web.get(app.meta.downloadURL, function (err, response)
        if __util.native('_vasi', response.body) then
          ui.modalPopup('Install %s?' % app.meta.name,
            '%s offers to install an app %s%s. Would you like to proceed?'
            % {originName, app.meta.name, app.reason or ''}, function (agreed)
            if agreed then
              utils.installApp(app, callback)
            elseif callback then
              callback('Cancelled') 
            end
          end)
        elseif callback then
          callback('Package is damaged')  
        end
      end)
    elseif callback then
      callback('App is not available')
    end
  elseif callback then
    callback('App Shelf is not available')
  end
end

ac.onSharedEvent('$SmallTweaks.AppShelf.Install', function (app, senderName)
  if type(app) == 'table' and type(app.meta) == 'table' and type(app.meta.id) == 'string' then
    app.location = ac.getFolder(ac.FolderID.ACAppsLua)..'\\'..app.meta.id
    installThirdPartyApp(app, senderName, function (err)
      ac.broadcastSharedEvent('$SmallTweaks.AppShelf.Install.Result', {err = err, installKey = app.installKey})
    end)
  end
end)