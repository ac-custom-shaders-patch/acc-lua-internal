if ac.setAudioEventMultiplier('event:/common/ambience', 1) then
  local cacheDir = ConfigGeneral:get('AUDIO', 'EXTENDED_AMBIENCE', false) and
  ac.getFolder(ac.FolderID.ExtCache) .. '/audio'
  local shiftAmbience = ConfigGeneral:get('AUDIO', 'SHIFTED_AMBIENCE', false)
  local groundPos = vec3()
  local dirUp = vec3(0, 1, 0)
  local dirFwd = vec3(0, 0, 1)
  local simTime = 0

  local function ambienceSource(name, mult, single)
    local audio = nil ---@type ac.AudioEvent|false|nil
    local cooldown = 0

    local function tryLoad()
      print('Loading ambient audio %s' % name)
      local filename = cacheDir .. '/' .. bit.tohex(ac.checksumXXH(name)) .. '.mp3'
      local function loadAudio()
        audio = ac.AudioEvent.fromFile({
          filename = filename,
          dopplerEffect = 0.5,
          use3D = true,
          minDistance = 10,
          maxDistance = 150,
          loop = not single
        }, true)
        audio.cameraInteriorMultiplier = 0.5
        audio.volume = 0
      end

      if string.find(name, '/', nil, true) then
        filename = name
      end

      if io.fileExists(filename) then
        loadAudio()
      elseif filename ~= name then
        if (tonumber(ac.storage.pauseStreaming) or 0) > os.time() then
          print('Assets streaming is paused')
        else
          print('Trying to load ambient audio %s from CDN' % name)
          web.get('https://acstuff.club/u/audio/' .. name .. '.zip', function(err, response)
            print(err, response and response.body and #response.body, response.status)
            if err or response.status > 399 then
              ac.warn(err or response.status)
  
              -- Failed to load: no more attempts for the next 24 hours
              ac.storage.pauseStreaming = os.time() + 24 * 60 * 60
            else
              io.extractFromZipAsync(response.body, cacheDir, name .. '.mp3', function(err)
                if not err then
                  io.move(cacheDir .. '/' .. name .. '.mp3', filename, true)
                  print('Ambient audio %s is ready' % name)
                  loadAudio()
                else
                  -- Failed to install: no more attempts for the next 48 hours
                  ac.storage.pauseStreaming = os.time() + 2 * 24 * 60 * 60
                end
              end)
            end
          end)
        end
      end
    end

    return {
      name = function()
        return name
      end,
      ready = function()
        return audio ~= nil
      end,
      sync = function(active)
        if single then
          if not active or cooldown > simTime then
            return false
          end
          if cooldown ~= -1 then
            active = math.random() < (single.chance or 1) and (not single.predicate or single.predicate())
          end
          cooldown = simTime + (0.5 + math.random()) * (single.cooldown or 60)
          if not active then
            return
          end
        end
        if not audio then
          if audio == nil and active then 
            audio = false
            if cacheDir then
              tryLoad()
            end
          end
          if single then
            cooldown = -1
          end
          return false
        end
        local playing = active or audio.volume > 0.001
        if playing then
          if groundPos.y > 1e29 then
            groundPos:set(Sim.cameraPosition.x, ac.getGroundYApproximation(), Sim.cameraPosition.z)
          end
          if single then
            local distance = (0.5 + math.random()) * (single.distance or 100)
            local angle = math.tau * math.random()
            local s, c = math.sin(angle) * distance, math.cos(angle) * distance
            audio:setPosition(vec3(s, 0, c):add(groundPos), dirUp, dirFwd, nil)
          else
            audio:setPosition(groundPos, dirUp, dirFwd, nil)
          end
        end
        if not single then
          audio:resumeIf(playing)
          audio.volume = math.applyLag(audio.volume, active and mult or 0, 0.98, Sim.dt) * ac.getAudioVolume('trackAmbient')
        elseif active then
          print('Playing ambience event %s' % name)
          audio:seek(0)
          audio:start()
          audio.volume = mult * ac.getAudioVolume('trackAmbient')
        end
        return playing
      end
    }
  end

  local ambienceSamples = {}
  local function registerSample(priority, name, volume, condition, random)
    local created = { priority, ambienceSource(name, volume, false), condition, random }
    table.insert(ambienceSamples, created)
    table.sort(ambienceSamples, function (a, b) return a[1] > b[1] end)
    print('New ambience %s registered' % name)
    return created
  end

  registerSample(-0.5, 'ambience-wind-0', 1, function() return Sim.rainIntensity > 0.005 end)
  registerSample(-1, 'ambience-night-0', 1, function() return ac.getSunAngle() > 90 end, {
    ambienceSource('event-owls-0', 1, { cooldown = 30, chance = 0.05, predicate = function ()
      return Sim.rainIntensity == 0
    end })
  })

  local allowed = { 'track_script', 'track_scriptable_display', 'server_script', 'new_modes', 'app' }
  local registered = {}

  ac.onSharedEvent('$SmallTweaks.AmbienceAudio', function(data, senderName, senderType, senderID)
    if not table.contains(allowed, senderType) or type(data) ~= 'table' or not data.conditionKey then return end
    if data.filename then
      local k = ac.connect({
        ac.StructItem.key('$SmallTweaks.AmbienceAudio.%s' % data.conditionKey),
        active = ac.StructItem.boolean()
      }, false, ac.SharedNamespace.Shared)
      registered[data.conditionKey] = registerSample(data.priority or 0, data.filename, data.volume or 1, function () return k.active end)
    else
      local toRemove = registered[data.conditionKey]
      if toRemove then
        toRemove[3] = function () return false end
        setTimeout(function ()
          table.removeItem(ambienceSamples, toRemove)
        end, 5)
      end
    end
  end)

  local function getActiveAmbience()
    for i = 1, #ambienceSamples do
      if ambienceSamples[i][3]() then
        return ambienceSamples[i][2], ambienceSamples[i][4]
      end
    end
  end

  local activeAmbience = nil
  local fadingAmbiences = {}

  local appliedBaseAmbience = 0
  local baseAmbience = 0
  local randomCooldown = 1
  Register('core', function()
    simTime = simTime + Sim.dt

    if shiftAmbience then
      groundPos:set(Sim.cameraPosition.x, ac.getGroundYApproximation(), Sim.cameraPosition.z)
      __util.native('__shiftAmbience', groundPos)
    else
      groundPos.y = 1e30
    end

    local targetAmbience, randomEvents = getActiveAmbience()
    if targetAmbience ~= activeAmbience then
      print('Switching ambient to %s' % (targetAmbience and targetAmbience.name() or '<default>'))
      if targetAmbience then
        table.removeItem(fadingAmbiences, targetAmbience)
      end
      if activeAmbience then
        table.insert(fadingAmbiences, activeAmbience)
      end
      activeAmbience = targetAmbience
    end

    if randomCooldown > 0 then
      randomCooldown = randomCooldown - Sim.dt
    elseif randomEvents then
      randomCooldown = 1
      table.random(randomEvents).sync(true)
    end

    for i = #fadingAmbiences, 1, -1 do
      if not fadingAmbiences[i].sync(false) then
        table.remove(fadingAmbiences, i)
      end
    end

    baseAmbience = math.applyLag(baseAmbience, targetAmbience and (targetAmbience.ready() and 0 or 0.1) or 1, 0.98,
      Sim.dt)
    if math.abs(baseAmbience - appliedBaseAmbience) > 0.005 then
      appliedBaseAmbience = baseAmbience
      ac.setAudioEventMultiplier('event:/common/ambience', baseAmbience)
      ac.debug('baseAmbience', baseAmbience)
    end
    if targetAmbience then
      ac.debug('Ambience is ready', targetAmbience.ready())
      targetAmbience.sync(true)
    end
  end)

  -- local audios = ac.findNodes('AC_AUDIO_?')
  -- local points = {}
  -- for i = 1, #audios do
  --   print(audios:name(i))
  --   points[i] = audios:at(i):getPosition()
  -- end
  -- render.on('main.track.transparent', function ()
  --   render.setBlendMode(render.BlendMode.Opaque)
  --   render.setCullMode(render.CullMode.None)
  --   render.setDepthMode(render.DepthMode.Off)
  --   for i = 1, #points do
  --     render.debugCross(points[i], 200, rgbm.colors.lime)
  --   end
  -- end)
end
