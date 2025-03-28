---@alias AppMeta {id: string, name: string, author: string, version: string, icon: string, description: string, size: integer, detailsURL: string, downloadURL: string, category: string}
---@alias AppInfo {meta: AppMeta, installed: string, installing: boolean|string, displaySize: string, location: string, domainName: string, newApp: boolean?}

local _config
local function config()
  if not _config then
    _config = ac.storage{
      notifyAboutNewApps = false,
      notifyAboutUpdates = true,
      automaticallyInstallUpdates = false,
      settingsOpenedOnce = false,
      openOnceInstalled = true,
      knownApps = ''
    }
  end
  return _config
end

---@param meta AppMeta
---@return AppInfo?
local function createInfo(meta)
  if meta.id:startsWith('.') then return nil end
  local location = ac.getFolder(ac.FolderID.ACAppsLua)..'\\'..meta.id
  local installedManifest = ac.INIConfig.load(location..'\\manifest.ini', ac.INIFormat.Extended)
  local installedVersion = installedManifest:get('ABOUT', 'VERSION', '')
  local domainName = meta.detailsURL and meta.detailsURL:regmatch('(?://)(?:www\\.)?([\\w\\.]+)')
  return {
    meta = meta,
    installed = #installedVersion > 0 and installedVersion,
    installing = false,
    displaySize = meta.size > 1024 * 1024 and '%.1f MB' % (meta.size / (1024 * 1024))
      or '%.0f KB' % (meta.size / 1024),
    domainName = domainName,
    location = location
  }
end

---@param app AppInfo
---@param callback fun(err: string?)? 
local function installApp(app, callback)
  if app.installing then return end
  app.installing = true
  app.newApp = false
  local openOnceInstalled = not app.installed
  local updating = app.installed
  ac.startBackgroundWorker('BackgroundInstall', app, function (err, data)
    if err then
      app.installing = err
      ui.toast(ui.Icons.Warning, '%s: failed to install' % app.meta.name)
      ac.warn(err)
      if callback then callback(err) end
    else
      app.installing = false
      app.installed = data
      ui.toast(ui.Icons.Confirm, (updating and '%s is updated to v%s' or '%s is installed') % {app.meta.name, data})
      ac.noticeNewApp(app.meta.id)
      ac.store('.appShelf.freshlyInstalled.%s' % app.meta.id, 1)
      ac.log('openOnceInstalled', openOnceInstalled)
      ac.log('config().openOnceInstalled', config().openOnceInstalled)
      if openOnceInstalled and config().openOnceInstalled then
        setTimeout(function () ac.setAppOpen(app.meta.id) end, 0.1)
      end
      if callback then callback(nil) end
    end
  end)
end

---@param app AppInfo
local function refreshApp(app)
  local location = ac.getFolder(ac.FolderID.ACAppsLua)..'\\'..app.meta.id
  local installedManifest = ac.INIConfig.load(location..'\\manifest.ini', ac.INIFormat.Extended)
  local installedVersion = installedManifest:get('ABOUT', 'VERSION', '')
  app.installed = #installedVersion > 0 and installedVersion
end

---@param app AppInfo
local function uninstallApp(app)
  if app.installing or not app.installed then
    error('Invalid state')
  end
  if ac.uninstallApp(app.meta.id) then
    app.installing = false
    app.installed = nil
    ui.toast(ui.Icons.Confirm, '%s is uninstalled' % app.meta.name)
  else
    ui.toast(ui.Icons.Warning, 'Failed to uninstall %s' % app.meta.name)
  end
end

local abTestingKeyStorage

local function abTestingKey()
  if not abTestingKeyStorage then
    abTestingKeyStorage = ac.storage('abTestingKeyStorage', math.random())
  end
  return abTestingKeyStorage:get()
end

---@param callback fun(err: string?, data: AppInfo[]?)
---@param installOwnUpdate fun(data: AppMeta)?
local function loadApps(callback, installOwnUpdate)
  web.get('https://acstuff.ru/app/app-loader/apps?target=%d' % ac.getPatchVersionCode(), function (err, data)
    if err then
      return callback(err, nil)
    end
    local parsed = JSON.parse(data.body)
    if type(parsed) == 'table' then
      local items = table.map(parsed, function (item)
        if item.id == '.AppShelf' then
          if installOwnUpdate then
            installOwnUpdate(item)
          end
          return nil 
        end
        if item.abTesting and item.abTesting > abTestingKey() then
          return nil
        end
        return createInfo(item)
      end) ---@type AppInfo[]
      table.sort(items, function (a, b)
        local ap = not a.installed and 0 or string.versionCompare(a.meta.version, a.installed) > 0 and 1 or -1
        local bp = not b.installed and 0 or string.versionCompare(b.meta.version, b.installed) > 0 and 1 or -1
        if ap ~= bp then return ap > bp end
        return a.meta.name < b.meta.name
      end)
      callback(nil, items)
    else
      ac.warn(data.body)
      callback('Data is corrupted', nil)
    end
  end)
end

return {
  createInfo = createInfo,
  installApp = installApp,
  refreshApp = refreshApp,
  uninstallApp = uninstallApp,
  loadApps = loadApps,
  config = config
}