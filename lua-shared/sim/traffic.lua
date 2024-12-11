--[[
  Library allowing to quickly add traffic to new modes.
]]
---@diagnostic disable

local traffic = {}

---@param checkOnlineRepo boolean?
---@param callback fun(err: string?, data: {jsonConfigurationFilename: string?, binaryConfigurationFilename: string?}?)
function traffic.lookup(checkOnlineRepo, callback)
  local dataFilename = ac.getTrackDataFilename('traffic.json') ---@type string?
  local cachedDataFilename = ac.getFolder(ac.FolderID.ExtCache)..'/traffic/'..ac.getTrackFullID('_')..'.bin'

  if dataFilename and io.fileExists(dataFilename) then
    callback(nil, { jsonConfigurationFilename = dataFilename, binaryConfigurationFilename = cachedDataFilename })
  elseif io.fileExists(cachedDataFilename) then
    callback(nil, { binaryConfigurationFilename = cachedDataFilename })
  elseif checkOnlineRepo then
    web.get('https://acstuff.club/u/traffic/'..ac.getTrackID()..'.zip', function (err, response)
      if not err and response.status < 400 then
        local data = io.loadFromZip(response.body, 'data.bin')
        if data then
          io.createFileDir(cachedDataFilename)
          io.save(cachedDataFilename, data, true)
          callback(nil, { binaryConfigurationFilename = cachedDataFilename })
          return
        end
      end
      callback('traffic data is missing', nil)
    end)
  else
    callback('traffic data is missing', nil)
  end
end

---@param params {jsonConfigurationFilename: string?, binaryConfigurationFilename: string?, driversCount: integer?, speedMultiplier: number?, carnageMode: boolean?}
function traffic.run(params)
  package.add('../../tools/csp-traffic-tool/lib')
  package.add('../../tools/csp-traffic-tool/src/common')
  package.add('../../tools/csp-traffic-tool/src/editor')
  package.add('../../tools/csp-traffic-tool/src/simulation')
  
  local TrafficConfig = require('TrafficConfig')
  TrafficConfig.driversCount = params.driversCount or 1000
  TrafficConfig.speedMultiplier = params.speedMultiplier or 1
  TrafficConfig.carnageMode = params.carnageMode or false
  TrafficConfig.debugBehaviour = false
  TrafficConfig.debugSpawnAround = false
  
  local sim = ac.getSim()
  local simTraffic, simBroken = nil, false
  local TrafficSimulation = require('TrafficSimulation')
  
  local data
  try(function ()
    do
      if not params.jsonConfigurationFilename
          or params.binaryConfigurationFilename and io.lastWriteTime(params.binaryConfigurationFilename) > io.lastWriteTime(params.jsonConfigurationFilename) then
        data = stringify.binary.parse(io.load(params.binaryConfigurationFilename))
      else
        local EditorMain = require('EditorMain')
        data = EditorMain(JSON.parse(io.load(params.jsonConfigurationFilename, '{}')) or {}):finalizeData()
        if params.binaryConfigurationFilename then
          io.createFileDir(params.binaryConfigurationFilename)
          io.save(params.binaryConfigurationFilename, stringify.binary(data))
        end
      end
    end
  end, function (err)
    ac.error(err)
  end)
  if not data then
    return nil
  end
  
  local toolDir = 'extension/lua/tools/csp-traffic-tool'
  local requiresDataInstall = #io.scanDir(toolDir..'/data', '*.json') == 0 ---@type boolean|string
  
  if requiresDataInstall then
    ui.toast(ui.Icons.LoadingSpinner, 'Loading traffic data…###TrafficTool')
    web.get('https://files.acstuff.club/TCKo/data.zip', function (err, response)
      if response and response.body then
        for _, e in ipairs(io.scanZip(response.body)) do
          if e:startsWith('data/') and not e:find('/.', nil, true) then
            local content = io.loadFromZip(response.body, e)
            if content then
              local fileDestination = toolDir..'/'..e
              io.createFileDir(fileDestination)
              io.save(fileDestination, content)
            end
          end
        end
        if #io.scanDir(toolDir..'/data', '*.json') == 0 then
          requiresDataInstall = 'Data is damaged'
        end
      else
        requiresDataInstall = err and tostring(err) or 'Data is missing'
      end
      if type(requiresDataInstall) == 'string' then
        ui.toast(ui.Icons.Warning, 'Failed to install traffic data: '..requiresDataInstall..'###TrafficTool')
      else
        ac.broadcastSharedEvent('tools.TrafficTool.rescanCars')
        setTimeout(function ()
          requiresDataInstall = false
        end)
      end
    end)
  end
  
  ac.store('newmode.traffic.active', 1)
  
  return {
    update = function(dt)
      if requiresDataInstall or sim.isReplayActive or sim.dt == 0 or sim.isOnlineRace or simBroken then
        return
      end
    
      if sim.focusedCar ~= -1 then
        local car = ac.getCar(sim.focusedCar)
        if car ~= nil and not car.extrapolatedMovement then
          -- Hacky fix. Let’s hope we’ll be able to use extrapolated movement soon.
          dt = dt + (sim.gameTime - ac.getCar(sim.focusedCar).timestamp) / 1e3
          dt = math.max(dt, 0.002)
        end
      end
    
      if simTraffic == nil then
        simTraffic = TrafficSimulation(data)
      end
    
      simBroken = true
      simTraffic:update(dt)
      simBroken = false
    end,
    draw3D = function()
      if simTraffic then
        simTraffic:drawMain()
      end
    end
  }
end

return traffic