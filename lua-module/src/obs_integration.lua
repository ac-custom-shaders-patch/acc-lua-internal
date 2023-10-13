if not Config:get('OBS', 'DIRECT_PASS', false) then return end

local obsTextures, dirty = {}, false

ffi.cdef([[typedef struct {
uint32_t handle;
uint32_t nameKey;
uint16_t width;
uint16_t height;
uint16_t needsData;
uint16_t flags;
char name[48];
char description[256];
} OBSTextureEntry;]])

local knownHandles = {}
local mapped = ac.writeMemoryMappedFile('AcTools.CSP.OBSTextures.v0', [[
uint32_t aliveCounter;
int32_t itemsCount;
OBSTextureEntry items[63];]], true)
mapped.itemsCount = 0
ac.store('$SmallTweaks.OBSTextures.Initialized', 0)

local function rebuildList()
  dirty = false
  table.sort(obsTextures, function (a, b)
    return a.name < b.name
  end)
  for i = 0, #obsTextures - 1 do
    local d, s = mapped.items[i], obsTextures[i + 1]
    d.handle = knownHandles[s.name] or 0
    d.nameKey = s.nameKey
    ac.stringToFFIStruct(s.name, d.name, 48)
    ac.stringToFFIStruct(s.description, d.description, 256)
    d.width = s.size.x
    d.height = s.size.y
    d.flags = s.flags
    d.needsData = 0
    if s.connect then
      s.connect.item = d
    else
      s.callback(d, s.name)
    end
    if d.handle ~= 0 then
      knownHandles[s.name] = d.handle
    end
  end
  mapped.itemsCount = #obsTextures
end

setInterval(function ()
  local s = '%s' % mapped.itemsCount
  for i = 0, mapped.itemsCount - 1 do
    s = '%s\n%s: %s, %s' % {s, ffi.string(mapped.items[i].name), mapped.items[i].handle, mapped.items[i].needsData}
  end
end)

ac.onSharedEvent('$SmallTweaks.OBSTextures.HandleUpdate', function (args, _, senderType)
  if type(args) ~= 'table' or senderType ~= 'app' then return end
  knownHandles[args.name] = args.handle
end)

ac.onSharedEvent('$SmallTweaks.OBSTextures', function (args, _, senderType)
  if type(args) ~= 'table' or senderType ~= 'app' then return end

  args.name = (args.group or 'Unknown')..': '..args.name
  if not args.flags then
    -- Removal mode
    local i, k = table.findFirst(obsTextures, function (item, _, n) return item.name == n end, args.name)
    if i and not i.callback then
      table.remove(obsTextures, k)
    else
      ac.warn('OBS texture named “%s” is not registered' % args.name)
      goto keepClean
    end
  elseif table.some(obsTextures, function (item, _, n) return item.name == n end, args.name) then
    ac.warn('OBS texture with the name “%s” is already registered' % args.name)
  elseif #obsTextures >= 63 then
    ac.warn('Too many OBS textures (current limit is 63)')
    goto keepClean
  else
    table.insert(obsTextures, {
      nameKey = ac.checksumXXH(args.name),
      name = args.name,
      description = args.description or '',
      size = args.size,
      flags = args.flags,
      connect = ac.connect(string.format('OBSTextureEntry* item;//%s', args.name))
    })
  end

  if not dirty then
    dirty = true
    setTimeout(rebuildList)
  end

  ::keepClean::
end)

local function defaultCallbackMirror(size, drawCallback)
  local canvas, lastD
  return function (d)
    if not canvas then
      canvas = ui.ExtraCanvas(size, 1, render.AntialiasingMode.None, render.TextureFormat.R8G8B8A8.UNorm, render.TextureFlags.Shared)
      d.handle = canvas:sharedHandle(true)
      setInterval(function ()
        if lastD.needsData > 0 then
          lastD.needsData = lastD.needsData - 1
          drawCallback(canvas)
        end
      end)
    end
    lastD = d
  end
end

local function defaultCallbackYebis(size, drawCallback)
  local canvas, lastD
  return function (d)
    if not canvas then
      canvas = ui.ExtraCanvas(size, 1, render.AntialiasingMode.YEBIS, render.TextureFormat.R16G16B16A16.Float, render.TextureFlags.Shared)
      canvas:setExposure(30)
      d.handle = canvas:sharedHandle(true)
      setInterval(function ()
        if lastD.needsData > 0 then
          lastD.needsData = lastD.needsData - 1
          drawCallback(canvas)
        end
      end)
    end
    lastD = d
  end
end

setTimeout(Register('simUpdate', function () end))

local function defaultCallbackExteriorCamera(size, updateFn, params)
  local shot, lastD
  local function init()
    if shot then
      shot:dispose()
    end
    shot = ac.GeometryShot(ac.findNodes('sceneRoot:yes'), size, 1, false, render.AntialiasingMode.YEBIS,
      render.TextureFormat.R16G16B16A16.Float, render.TextureFlags.Shared)
    shot:setBestSceneShotQuality()
    if Config:get('OBS', 'HIGH_QUALITY', false) then
      shot:setShadersType(render.ShadersType.Main)
      shot:setAlternativeShadowsSet('area')
    else
      shot:setShadersType(render.ShadersType.SimplifiedWithLights)
    end
    if params and params[3] then
      shot:setClippingPlanes(0.01, 3e3)
    else
      shot:setClippingPlanes(0.25, 5e3)
    end
  end
  return function (d, n)
    if not lastD then
      Register('simUpdate', function (dt)
        if lastD.needsData > 0 then
          if not shot or bit.band(lastD.flags, 256) ~= 0 and (lastD.width ~= size.x or lastD.height ~= size.y) then
            size:set(lastD.width, lastD.height)
            init()
            lastD.handle = shot:sharedHandle(true)
            knownHandles[n] = lastD.handle
          end
          lastD.needsData = lastD.needsData - 1
          render.measure('OBS view', function ()
            updateFn(shot, Sim.focusedCar < 0 and 0 or Sim.focusedCar)
          end)
        end
      end)
    end
    lastD = d
  end
end

local function addDefaultView(group, name, flags, description, source, callbackFactory)
  local size = type(source) == 'table' and source[1] or ui.imageSize(source)
  name = group..': '..name
  table.insert(obsTextures, {
    nameKey = ac.checksumXXH(name),
    name = name,
    description = description or '',
    size = size,
    flags = size.x == 0 and 1 or flags,
    callback = (callbackFactory or defaultCallbackMirror)(size, type(source) == 'table' and source[2] or function (canvas)
      canvas:copyFrom(source)
    end, source)
  })
end

local listener
local addRedirectedAppsSettings = function ()
  local redirected = stringify.tryParse(ac.storage.redirectedApps, nil, {})
  if type(redirected) ~= 'table' then redirected = {} end
  for k, v in pairs(redirected) do
    local r = ac.accessAppWindow(k)
    if r then
      r:setRedirectLayer(1, v)
    end
  end

  ui.addSettings({
    icon = ui.Icons.AppWindow,
    name = 'OBS Apps Redirection',
    size = {
      min = vec2(320, 80),
      max = vec2(320, 2000)
    }
  }, function ()
    local w = ui.availableSpaceX()
    ui.pushFont(ui.Font.Small)
    ui.textWrapped('Select apps to hide from the main screen and show up in a separate layer passed to OBS Studio:', w)
    ui.popFont()

    ui.offsetCursorY(12)
    
    ui.columns(3)
    ui.setColumnWidth(0, w - 140)
    ui.setColumnWidth(1, 70)
    ui.setColumnWidth(2, 70)
    ui.separator()
    ui.text('Window')
    ui.nextColumn()
    ui.text('Redirect')
    ui.nextColumn()
    ui.text('Duplicate')
    ui.nextColumn()
    ui.separator()
    for i, v in ipairs(ac.getAppWindows()) do
      if v.visible and v.layer == 0 and v.title ~= 'OBS Apps Redirection' or v.layer == 1 then
        ui.pushID(i)
        local t = v.title:trim()
        ui.text(#t > 0 and t or v.name)
        ui.nextColumn()
        if ui.checkbox('##redirect', v.layer == 1 and not v.layerDuplicate) then
          if v.layer == 1 and not v.layerDuplicate then
            ac.accessAppWindow(v.name):setRedirectLayer(0, false)
            redirected[v.name] = nil
          else
            ac.accessAppWindow(v.name):setRedirectLayer(1, false)
            redirected[v.name] = false
          end
          ac.storage.redirectedApps = stringify(redirected, true)
        end
        if ui.itemHovered() then
          ui.setTooltip('Redirected apps are hidden from the main screen and ignore mouse inputs, so you can use some apps purely as OBS widgets')
        end
        ui.nextColumn()
        if ui.checkbox('##duplicate', v.layer == 1 and v.layerDuplicate) then
          if v.layer == 1 and v.layerDuplicate then
            ac.accessAppWindow(v.name):setRedirectLayer(0, false)
            redirected[v.name] = nil
          else
            ac.accessAppWindow(v.name):setRedirectLayer(1, true)
            redirected[v.name] = true
          end
          ac.storage.redirectedApps = stringify(redirected, true)
        end
        if ui.itemHovered() then
          ui.setTooltip('Duplicated apps are shown in both OBS HUD layer and in the main screen, and continue to receive mouse inputs, that option might be a better fit if you’re using HUDless OBS layer for capturing the footage')
        end
        ui.nextColumn()
        ui.popID()
      end
    end
    ui.columns(1)
  end)

  ac.onRelease(function ()
    for _, v in ipairs(ac.getAppWindows()) do
      if v.layer == 1 then
        ac.accessAppWindow(v.name):setRedirectLayer(0)
      end
    end
  end)
end

local function initOBSIntegration()
  ac.log('OBS plugin is live')

  addDefaultView('Basic', 'Clean view', 0,
   'Main image without HUD (for VR, use an option in VR tweaks to disable HUD in mirroring instead). Make sure FXAA in AC Video settings is enabled for better quality.', 
    'dynamic::final::clean')
  addDefaultView('Basic', 'Include HUD', 0,
    'Regular output, the same Game Capture would provide.',
    'dynamic::final')
  addDefaultView('Basic', 'Virtual mirror', 0,
    'Virtual rear view mirror (might deactivate real mirrors if virtual mirror integration is not enabled in Smart Mirror settings).', 
    {vec2(1024, 256), function (canvas) 
      canvas:clear()
      canvas:update(function () 
        ui.drawVirtualMirror(vec2(), ui.windowSize(), rgbm.colors.white) 
      end)
    end}, defaultCallbackYebis)

  addDefaultView('Extra', 'VR HUD', 2,
    'The whole HUD should be accessible here in VR mode.',
    'dynamic::hud')
  addDefaultView('Extra', 'Redirected apps', 2,
    'Use OBS Apps Redirection app in AC (in settings category) to set the list of apps to be redirected here and hidden from the main screen.',
    {vec2(Sim.windowWidth, Sim.windowHeight), function (canvas)
      canvas:copyFrom('dynamic::hud::redirected::1')
      if addRedirectedAppsSettings then
        addRedirectedAppsSettings()
        addRedirectedAppsSettings = nil
      end
    end})
  addDefaultView('Extra', 'Android Auto', 0, 
    'If your car has an Android Auto display, it can be mirrored here for whatever reason.',
    'car0::dynamic::android_auto')

  addDefaultView('Camera', 'Above', 64 + 128, nil,
    {vec2(640, 640), function (shot, carIndex) 
    local car = ac.getCar(carIndex) or ac.getCar(0)
    if not car then return end
    local dir = vec3(0, -1, 0):add(car.look)
    shot:update(car.position:clone():addScaled(car.velocity, 0.1):addScaled(dir, -70), dir, nil, 15)
  end}, defaultCallbackExteriorCamera)
  for i = 0, 5 do
    local camera = ac.accessCarCamera(i)
    if camera then
      addDefaultView('Camera', 'Car %d' % (i + 1), 64 + 128, nil,
        {vec2(640, 640), function (shot, carIndex)
          local car = ac.getCar(carIndex) or ac.getCar(0)
          if not car then return end
          local pos = car.bodyTransform:transformPoint(camera.transform.position)
          local look = car.bodyTransform:transformVector(camera.transform.look):scale(-1)
          local up = car.bodyTransform:transformVector(camera.transform.up)
          shot:setExposure(camera.exposure)
          shot:update(pos, look, up, camera.fov)
        end, true}, defaultCallbackExteriorCamera)
    end
  end
  addDefaultView('Camera', 'Chase', 64 + 128, nil,
    {vec2(640, 640), (function (ctx, shot, carIndex)
    local car = ac.getCar(carIndex) or ac.getCar(0)
    if not car then return end
    ctx.x = math.applyLag(ctx.x, car.acceleration.x, 0.95, Sim.dt)
    ctx.z = math.applyLag(ctx.z, car.acceleration.z, 0.95, Sim.dt)
    shot:update(car.position - car.look * (8 + ctx.z * 0.5) + car.up * (2 + ctx.z * 0.3) + car.side * (ctx.x * -1), car.look + car.side * (ctx.x * 0.3), nil, 45)
  end):bind({x = 0, z = 0})}, defaultCallbackExteriorCamera)
  addDefaultView('Camera', 'Track camera', 64 + 128, nil,
    {vec2(640, 640), function (shot, carIndex) shot:updateWithTrackCamera(carIndex) end}, defaultCallbackExteriorCamera)

  ac.broadcastSharedEvent('$SmallTweaks.OBSTextures.Init')
  ac.store('$SmallTweaks.OBSTextures.Initialized', 1)
  setTimeout(listener)
  setTimeout(rebuildList)
end

listener = Register('core', function (dt)
  if mapped.aliveCounter > 0 and ac.load('$SmallTweaks.OBSTextures.Initialized') ~= 1 then
    initOBSIntegration()
  end
end)

ac.onRelease(function ()
  mapped.itemsCount = -1
end)
