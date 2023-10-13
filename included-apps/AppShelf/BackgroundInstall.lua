local app = worker.input ---@type AppInfo
web.get(app.meta.downloadURL, function (err, response)
  if err then error(err) end

  local data = io.loadFromZip(response.body, app.meta.id..'/manifest.ini')
  if not data then error('Package is damaged') end

  local manifest = ac.INIConfig.parse(data, ac.INIFormat.Extended)
  local version = manifest:get('ABOUT', 'VERSION', '')
  if version == '' then error('Package manifest is damaged') end
  if app.installed == version then error('Package is obsolete') end

  io.createDir(app.location)
  if not io.dirExists(app.location) then error('Failed to create directory') end

  local destinationPrefix = io.getParentPath(app.location)..'/'
  for _, e in ipairs(io.scanZip(response.body)) do
    local content = io.loadFromZip(response.body, e)
    if content then
      local fileDestination = destinationPrefix..e
      io.createFileDir(fileDestination)
      io.save(fileDestination, content)
    end
  end
  worker.result = version
end)
