-- local stats = __input

local refs = {}
local lastID = 2

local function registerFix(fixItem)
  lastID = lastID + 1
  refs[lastID] = fixItem
  return lastID
end

function script.apply(key, revert)
  local r = refs[key]
  if not r then return false end
  (revert and r.revert or r.apply)()
  return true
end

---@param cfg ac.INIConfig
---@param section string
---@param key string
---@param value string|number|boolean
---@return integer
---@overload fun(args: table[]): integer
local function fix(cfg, section, key, value)
  if type(section) ~= 'string' then
    local originalValues = table.map(cfg, function (i) return i[1]:get(i[2], i[3], nil) end)
    return registerFix({
      apply = function () table.forEach(cfg, function (i) i[1]:setAndSave(i[2], i[3], i[4]) end) end,
      revert = function () table.forEach(cfg, function (i, j) i[1]:setAndSave(i[2], i[3], originalValues[j]) end) end
    })
  else
    local originalValue = cfg:get(section, key, nil)
    return registerFix({
      apply = function () cfg:setAndSave(section, key, value) end,
      revert = function () cfg:setAndSave(section, key, originalValue) end
    })
  end
end

local Impact = {
  Low = 0,
  Medium = 1,
  Big = 2
}

---@alias Solution {adj: string, fn: integer, impact: integer}

---@param value Solution
---@return string
local function formatReduction(value)
  return string.format('%s\t%s\t%s', value.adj, value.fn, value.impact)
end

---@param title string
---@param message string
---@param ... Solution
local function suggest(title, message, ...)
  _G['__suggest'](title, message, table.join({...}, '\n', formatReduction), lastID)
end

function script.fetch()
  table.clear(refs)

  local sim = ac.getSim()
  local cVideo = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg)..'\\video.ini', ac.INIFormat.Default)
  local cExtra = ac.INIConfig.cspModule(ac.CSPModuleID.ExtraFX)
  local cGraphics = ac.INIConfig.cspModule(ac.CSPModuleID.GraphicsAdjustments)
  local cReflections = ac.INIConfig.cspModule(ac.CSPModuleID.ReflectionsFX)
  local cMirror = ac.INIConfig.cspModule(ac.CSPModuleID.SmartMirror)
  local cGrass = ac.INIConfig.cspModule(ac.CSPModuleID.GrassFX)
  local cParticles = ac.INIConfig.cspModule(ac.CSPModuleID.ParticlesFX)
  local cRain = ac.INIConfig.cspModule(ac.CSPModuleID.RainFX)
  local cShadows = ac.INIConfig.cspModule(ac.CSPModuleID.SmartShadows)

  if cVideo:get('CUBEMAP', 'SIZE', 0) > 64 and cVideo:get('CUBEMAP', 'FACES_PER_FRAME', 0) > 1 then
    local optimization = 1 / cVideo:get('CUBEMAP', 'FACES_PER_FRAME', 0)
    suggest('Use one cubemap face per frame',
      'Cut down number of cubemap faces shot per frame to 1 and reproject the rest so the reflections would remain smooth.',
      {adj = string.format('Reflections cubemap/Rendering scene`%s,%s', optimization, optimization), fn = fix{
        {cReflections, 'MAIN_CUBEMAP', 'REPROJECT_PARTIAL', 1},
        {cVideo, 'CUBEMAP', 'FACES_PER_FRAME', 1}
      }, impact = Impact.Low})
  end

  if cVideo:get('MIRROR', 'SIZE', 0) > 0 and cMirror:get('BASIC', 'ENABLED', false) then
    if cMirror:get('REAL_MIRRORS', 'ENABLED', false)
      and cMirror:get('REAL_MIRRORS', 'RENDER_PER_FRAME', 0) ~= 1
      and cMirror:get('PERFORMANCE', 'SKIP_FRAMES', 0) == 0 then
      suggest('Extrapolate mirrors',
        'Instead of rendering mirrors content every frame, skip each second frame and instead reproject reflection to keep things smooth.',
        {adj = 'Mirrors/Real mirror ?`0.5,0.6', fn = fix(cMirror, 'PERFORMANCE', 'SKIP_FRAMES', 1), impact = Impact.Low})
    end
  end

  if cVideo:get('POST_PROCESS', 'ENABLED', false) then
    if cVideo:get('POST_PROCESS', 'FXAA', false) and cGraphics:get('ANTIALIASING', 'MODE', '') == 'DEFAULT' then
      suggest('Switch to FXAA 3.11',
        'Compared to original FXAA, v3.11 runs faster and improves quality. Alternatively, you can use CMAA2 for sharper image.',
        {adj = 'Post-processing anti-aliasing/Custom replacement/FXAA (original)`1,0.6', fn = fix(cGraphics, 'ANTIALIASING', 'MODE', 'FXAA3'), impact = Impact.Low})
    end
  end

  if cVideo:get('VIDEO', 'WIDTH', 1920) > 2000 and cGraphics:get('RENDER_SCALE', 'SCALE', 1) == 1 then
    suggest('Reduce render scale',
      'Rendering AC and its UI in lower resolution can help with FPS and scale.',
      {adj = 'Final image/?`1,0.5', fn = fix(cGraphics, 'RENDER_SCALE', 'SCALE', 0.7), impact = Impact.Medium})
  end

  if cRain:get('BASIC', 'ENABLED', false) then
    if cRain:get('VISUAL_TWEAKS', 'RAIN_MAPS_QUALITY', 1) == 2 then
      suggest('Reduce rain maps quality',
        'Drops running down on glossy surfaces would look a bit worse, but it can save a lot of time.',
        {adj = 'Preparation/Post-traverse processing/RainFX/Surface drop maps`1,0.5', fn = fix(cRain, 'VISUAL_TWEAKS', 'RAIN_MAPS_QUALITY', 1), impact = Impact.Low})
    else
      suggest('Reduce rain maps quality more',
        'Rendering AC and its UI in lower resolution can help with FPS and scale.',
        {adj = 'Preparation/Post-traverse processing/RainFX/Surface drop maps`1,0.5', fn = fix(cRain, 'VISUAL_TWEAKS', 'RAIN_MAPS_QUALITY', 0), impact = Impact.Medium})
    end
  end

  if cExtra:get('BASIC', 'ENABLED', false) then
    suggest('Disable ExtraFX',
      'All these post-processing effects like screen-space reflections, HBAO+ and such require a separate render pass, so things can get expensive.',
      {adj = 'Final image/ExtraFX`0,0;Frame preparation/Light map for ExtraFX bounced light`0,0', fn = fix(cExtra, 'BASIC', 'ENABLED', false), impact = Impact.Big})
  end

  if cGrass:get('BASIC', 'ENABLED', false) then
    if cGrass:get('BASIC', 'QUALITY', 2) == 4 then
      suggest('Reduce grass quality',
        'Slightly reduce grass distance and density.',
        {adj = 'Preparation/Post-traverse processing/GrassFX generation`1,0.8', fn = fix(cGrass, 'BASIC', 'QUALITY', 3), impact = Impact.Low})
    end
    if cGrass:get('RENDERING', 'CAST_SHADOWS', false) then
      suggest('Disable grass shadows',
        'Might look worse, especially with high grass on sunsets.',
        {adj = 'Sun shadows/Cascade ?/GrassFX`0,0', fn = fix(cGrass, 'RENDERING', 'CAST_SHADOWS', false), impact = Impact.Medium})
    end
    if cExtra:get('BASIC', 'ENABLED', false) and cGrass:get('RENDERING', 'EXTRAFX_PASS', false) then
      suggest('Disable ExtraFX integration for GrassFX',
        'Can introduce some artefacts when looking through high grass, but won’t be noticeable in most cases.',
        {adj = 'Final image/ExtraFX/G-buffer/GrassFX`0,0', fn = fix(cGrass, 'RENDERING', 'EXTRAFX_PASS', false), impact = Impact.Medium})
    end
  end

  if cParticles:get('BASIC', 'ENABLED', false) then
    local downscalingKey = sim.isVRConnected and 'USE_DOWNSCALING_VR' or 'USE_DOWNSCALING'
    if cParticles:get('SMOKE', downscalingKey, false) then
      suggest('Reduce smoke resolution',
        'Rendering smoke in half resolution can greatly help with performance.',
        {adj = 'Final image/Main pass/Transparent/Events/ParticlesFX/Smoke`1,0.0.5', fn = fix(cParticles, 'SMOKE', downscalingKey, true), impact = sim.isVRConnected and Impact.Big or Impact.Low})
    end
  end

  if cShadows:get('BASIC', 'ENABLED', false) then
    if not cShadows:get('NO_CAR_SHADOWS_IN_THIRD_CASCADE', 'INTERIOR_VIEW', false) then
      suggest('Disable interior car shadows in third cascade',
        'With this option distant cars won’t cast shadows. Affects interior cameras.',
        {adj = 'Sun shadows/Cascade 3/Cars`0,0', fn = fix(cShadows, 'NO_CAR_SHADOWS_IN_THIRD_CASCADE', 'INTERIOR_VIEW', false), impact = Impact.Low})
    end
    if not cShadows:get('NO_CAR_SHADOWS_IN_THIRD_CASCADE', 'EXTERIOR_VIEW', false) then
      suggest('Disable exterior car shadows in third cascade',
        'With this option distant cars won’t cast shadows. Affects exterior cameras.',
        {adj = 'Sun shadows/Cascade 3/Cars`0,0', fn = fix(cShadows, 'NO_CAR_SHADOWS_IN_THIRD_CASCADE', 'EXTERIOR_VIEW', false), impact = Impact.Low})
    end
  end
end
