local app = worker.input ---@type AppInfo
web.get(app.meta.downloadURL, function (err, response)
  if err then error(err) end

  if not __util.native('_vasi', response.body) then error('Package is damaged') end

  -- First, extract two main files:
  local manifestFileData = io.loadFromZip(response.body, app.meta.id..'/manifest.ini')
  local mainFileData = io.loadFromZip(response.body, app.meta.id..'/'..app.meta.id..'.lua')
  if not manifestFileData or not mainFileData then error('Package is damaged') end

  -- Parse and check manifest:
  local manifest = ac.INIConfig.parse(manifestFileData, ac.INIFormat.Extended)
  local version = manifest:get('ABOUT', 'VERSION', '')
  if version == '' then error('Package manifest is damaged') end
  if app.installed == version then error('Package is obsolete') end

  -- Pause live reloads for apps:
  __util.native('_plr', true)
  using(function ()
    io.createDir(app.location)
    if not io.dirExists(app.location) then error('Failed to create directory') end

    -- Save main file first:
    if not io.save(app.location..'/'..app.meta.id..'.lua', mainFileData, true) then
      -- If failed, possibly something is blocking the app being installed, like it currently
      -- being loaded and its main file being blocked. If so, exit early.
      -- TODO: Try again after a bit of a delay?
      error('Failed to save main script file')
    end
  
    -- Go over other files and extract them all one by one:
    local manifestEntryNameLowecase = app.meta.id:lower()..'/manifest.ini'
    local mainEntryNameLowecase = app.meta.id:lower():rep(2, '/')..'.lua'
    for _, e in ipairs(io.scanZip(response.body)) do
      if e:startsWith(app.meta.id..'/') and e:lower() ~= manifestEntryNameLowecase and e:lower() ~= mainEntryNameLowecase then
        local content = io.loadFromZip(response.body, e)
        if content then
          local fileDestination = app.location..'/'..(e:sub(#app.meta.id + 2))
          io.createFileDir(fileDestination)
          if not io.save(fileDestination, content, true) then
            error('Failed to save file')
          end
        end
      end
    end
  
    -- Last, update manifest: it contains version number, so if anything fails at least app will remain looking as an old app for
    -- the next attempt:
    if not io.save(app.location..'/manifest.ini', manifestFileData, true) then
      error('Failed to save manifest file')
    end
    worker.result = version
  end, function ()
    __util.native('_plr', false)
  end)
end)
