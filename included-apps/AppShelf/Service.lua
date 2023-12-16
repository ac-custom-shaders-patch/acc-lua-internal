local utils = require('utils')
local cfg = utils.config()
local shelfRunning = ac.isLuaAppRunning('AppShelf')
if not cfg.automaticallyInstallUpdates and not cfg.notifyAboutNewApps and not cfg.notifyAboutUpdates 
  or #cfg.knownApps == ''
  or shelfRunning then
  return
end
ac.log('AppShelf: checking app updates')
utils.loadApps(function (err, data)
  if not data then
    ac.log('AppShelf: failed to load list of apps', err)
    return
  end
  local counter = 0
  local knownApps = stringify.tryParse(cfg.knownApps, nil, {})
  for _, app in ipairs(data) do
    ac.log('AppShelf: entry %s, installed: %s, available: %s' % {app.meta.id, app.installed, app.meta.version})
    if app.installed and string.versionCompare(app.meta.version, app.installed) > 0 then
      if cfg.automaticallyInstallUpdates and not ac.isLuaAppRunning(app.meta.id) then
        utils.installApp(app)
      elseif cfg.notifyAboutUpdates then
        counter = counter + 1
      end
    elseif cfg.notifyAboutNewApps and not app.installed and not table.contains(knownApps, app.meta.id) then
      counter = counter + 1
    end
  end
  ac.log('AppShelf: notify counter=%s' % counter)
  ac.setWindowNotificationCounter('main', counter)
end, function (meta)
  local location = ac.getFolder(ac.FolderID.ExtInternal)..'\\lua-apps\\AppShelf'
  local installedManifest = ac.INIConfig.load(location..'\\manifest.ini', ac.INIFormat.Extended)
  local installedVersion = installedManifest:get('ABOUT', 'VERSION', '')
  if string.versionCompare(meta.version, installedVersion) > 0 then
    ac.log('AppShelf update found: %s (installed: %s)' % {meta.version, installedVersion})
    web.get(meta.downloadURL, function (err, response)
      if err then
        ac.warn(err)
        return
      end
    
      local data = io.loadFromZip(response.body, 'AppShelf/manifest.ini')
      if not data then error('Package is damaged') end
    
      local manifest = ac.INIConfig.parse(data, ac.INIFormat.Extended)
      local version = manifest:get('ABOUT', 'VERSION', '')
      if version == '' then error('Package manifest is damaged') end
      if installedVersion == version then error('Package is obsolete') end
      if not io.dirExists(location) then error('Corrupted state') end
    
      local destinationPrefix = io.getParentPath(location)..'/'
      for _, e in ipairs(io.scanZip(response.body)) do
        local content = io.loadFromZip(response.body, e)
        if content then
          local fileDestination = destinationPrefix..e
          io.createFileDir(fileDestination)
          io.save(fileDestination, content)
        end
      end
    end)
  end
end)
