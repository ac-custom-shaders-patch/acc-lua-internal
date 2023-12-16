--[[
  Extra logic for showroom previews generation.
]]

if not Sim.isPreviewsGenerationMode then
  return
end

local cameraPos = vec3(-3.8676, 1.4236, 4.7038)
local cameraLookAt = vec3(0.0, 0.7, 0.5)
local cameraTilt = 0
local cameraFov = 30
local steerDeg = 0
local alignCar = true
local useHeadlights = true
local useBrakeLights = false
local dofDistance = -1
local groundReflection = 0
physics.setCarNoInput(true)

local weather = ac.connect({
  ac.StructItem.key('showroomPreviewsWeather'),
  set = ac.StructItem.boolean(),
  ambientTopColor = ac.StructItem.rgb(),
  ambientBottomColor = ac.StructItem.rgb(),
  lightColor = ac.StructItem.rgb(),
  lightDirection = ac.StructItem.vec3(),
  useBackgroundColor = ac.StructItem.boolean(),
  backgroundColor = ac.StructItem.rgb(),
  specularColor = ac.StructItem.rgb(),
  sunSpecularMultiplier = ac.StructItem.float(),
  shadowsOpacity = ac.StructItem.float(),
  shadowsConcentration = ac.StructItem.float(),
  disableShadows = ac.StructItem.boolean(),
  customToneParams = ac.StructItem.boolean(),
  toneFunction = ac.StructItem.int32(),
  toneExposure = ac.StructItem.float(),
  toneGamma = ac.StructItem.float(),
  whiteReferencePoint = ac.StructItem.float(),
  saturation = ac.StructItem.float(),
  fakeReflection = ac.StructItem.boolean(),
  reflectionBrightness = ac.StructItem.float(),
  reflectionSaturation = ac.StructItem.float(),
})
weather.set = true
weather.ambientTopColor:set(10, 10, 10)
weather.ambientBottomColor:set(10, 10, 10)
weather.lightColor:set(0, 0, 0)
weather.lightDirection:set(0, 1, 0)
weather.specularColor:set(10, 10, 10)
weather.sunSpecularMultiplier = 1
weather.shadowsOpacity = 1
weather.shadowsConcentration = 1
weather.saturation = 1

local rootNodes = ac.findNodes('{ carsRoot:yes }')
rootNodes:setVisible(false)

local function getPreviewFilename(carIndex)
  local destination = ac.INIConfig.raceConfig():get('__PREVIEW_GENERATION', 'DESTINATION_'..tostring(carIndex), '')
  if destination ~= '' then return destination end
  local carDirectory = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(carIndex)
  local skinDirectory = carDirectory..'/skins/'..ac.getCarSkinID(carIndex)
  return skinDirectory..'/preview_csp.jpg'
end

local function tweakSkinName(name)
  local noDigits = string.reggsub(name, '^\\d+_', '')
  if #noDigits > 0 then
    name = noDigits
  end
  return string.reggsub(name, '^[a-z]|_[a-z]', function (v)
    if v:sub(1, 1) == '_' then v = ' '..v:sub(2, 2) end
    return string.upper(v)
  end)
end

local function setMetadata(carIndex)
  local carDirectory = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(carIndex)
  local skinData = JSON.parse(io.load(carDirectory..'/skins/'..ac.getCarSkinID(carIndex)..'/ui_skin.json'))
  if skinData and skinData.author then
    __setMetadataAuthorName__(skinData.author)
  elseif ac.getCar(carIndex).isKunosCar then
    __setMetadataAuthorName__('Kunos')
  else
    local carData = JSON.parse(io.load(carDirectory..'/ui/ui_car.json'))
    if carData and carData.author then
      __setMetadataAuthorName__(carData.author)
    else
      __setMetadataAuthorName__('')
    end
  end
  local skinName = skinData and skinData.name or tweakSkinName(ac.getCarSkinID(carIndex))
  __setMetadataSubjectName__(string.format('%s - %s', ac.getCarName(carIndex), skinName))
end

local cameraAlignFn

local function anglesToVec3(radO, radF)
  local O = math.pi / 2 - radO;
  local sinO = math.sin(O)
  local cosO = math.cos(O)
  local sinF = math.sin(radF)
  local cosF = math.cos(radF)
  return vec3(sinO * cosF, cosO, sinO * sinF)
end

local function parseColor(color)
  if color:sub(1, 1) == '#' then
    return rgb.new(color)
  else
    return rgb.new(color):scale(1./255)
  end
end

local preset = __getPreviewsGenerationPreset__()
if preset then
  local style = JSON.parse(preset)
  cameraPos = vec3.new(style.CameraPosition)
  cameraLookAt = vec3.new(style.CameraLookAt)
  cameraTilt = style.CameraTilt or 0
  cameraFov = style.CameraFov
  steerDeg = style.SteerDeg or 0
  alignCar = style.AlignCar ~= false
  useHeadlights = style.HeadlightsEnabled ~= false
  useBrakeLights = style.BrakeLightsEnabled == true
  weather.reflectionBrightness = (style.CustomReflectionBrightness or 1) * 0.8
  weather.reflectionSaturation = 1

  local sceneTweaks = ac.configureSceneTweaks()
  sceneTweaks.forceHeadlights = useHeadlights and ac.SceneTweakFlag.ForceOn or ac.SceneTweakFlag.ForceOff
  sceneTweaks.forceBrakeLights = useBrakeLights and ac.SceneTweakFlag.ForceOn or ac.SceneTweakFlag.ForceOff
  sceneTweaks.disableDamage = true
  sceneTweaks.disableDirt = true

  local brightnessMult = 10 / math.max(style.AmbientBrightness, style.LightBrightness * 0.1)
  if style.ToneVersion == 0 then
    if style.ToneMapping == 1 then style.ToneExposure = style.ToneExposure * 0.6993 end
    if style.ToneMapping == 2 then style.ToneExposure = style.ToneExposure * 0.9921 end
    if style.ToneMapping == 3 then style.ToneExposure = style.ToneExposure * 1.3617 end
  end

  if style.CPLSettings then
    ac.setCameraCPLSettings(style.CPLSettings.Intensity, style.CPLSettings.Rotation, style.CPLSettings.Offset, style.CPLSettings.PhotoelasticityBoost)
  end

  brightnessMult = 1
  weather.customToneParams = true
  weather.toneGamma = style.ToneGamma
  weather.toneExposure = style.ToneExposure
  weather.whiteReferencePoint = style.ToneWhitePoint
  if style.ToneMapping == 6 then
    weather.toneFunction = ac.TonemapFunction.ReinhardLum
    weather.toneExposure = weather.toneExposure * 1.4
    weather.whiteReferencePoint = weather.whiteReferencePoint * 2.8
    weather.toneGamma = weather.toneGamma * 1.2
  elseif style.ToneMapping == 1 or style.ToneMapping == 2 then
    -- ReinhardLum is bluish with regular scene
    weather.toneFunction =  style.ToneMapping == 1 and ac.TonemapFunction.ReinhardLum or ac.TonemapFunction.Reinhard
    weather.toneExposure = weather.toneExposure * 2
    weather.whiteReferencePoint = weather.whiteReferencePoint * 2
  elseif style.ToneMapping == 5 then
    weather.toneFunction = ac.TonemapFunction.Log
    weather.toneExposure = weather.toneExposure * 2
    weather.whiteReferencePoint = weather.whiteReferencePoint * 2
  else
    weather.toneFunction = ac.TonemapFunction.Sensitometric
    weather.toneExposure = weather.toneExposure * 1.6
    weather.whiteReferencePoint = weather.whiteReferencePoint * 2
    weather.saturation = 0.8
    weather.reflectionBrightness = weather.reflectionBrightness * 0.5
  end
  
  weather.useBackgroundColor = true
  
  weather.ambientTopColor:set(parseColor(style.AmbientUpColor or style.AmbientUp):scale(brightnessMult * style.AmbientBrightness))
  weather.ambientBottomColor:set(parseColor(style.AmbientDownColor or style.AmbientDown):scale(brightnessMult * style.AmbientBrightness))
  weather.lightColor:set(parseColor(style.LightColor):scale(brightnessMult * style.LightBrightness))
  weather.specularColor:set(parseColor(style.LightColor):scale(brightnessMult * style.LightBrightness))
  weather.backgroundColor:set(parseColor(style.BackgroundColor):scale(brightnessMult * style.BackgroundBrightness))
  weather.shadowsOpacity = style.CarShadowsOpacity
  weather.fakeReflection = not style.Showroom or style.Showroom == ''
  if weather.fakeReflection then
    __disableFakeShadowsReprojection__()
    groundReflection = style.FlatMirror and style.FlatMirrorReflectiveness or 0
  end

  if style.ReflectionCubemapAtCamera == false then
    __setCubemapForFocusedCar__(true)
  end
  if style.UsePcss then
    __setAccumulationBlurShadowsAmount__(style.PcssLightScale * 0.5)
  end
  if style['Lightθ'] and style['Lightφ'] then 
    weather.lightDirection = anglesToVec3(math.rad(style['Lightθ']), math.rad(style['Lightφ']))
  elseif style.LightDirection then
    weather.lightDirection = vec3.new(style.LightDirection)
  end

  if style.EnableShadows == false then
    weather.disableShadows = true
  end
  if style.UseDof and (not style.UseAccumulationDof or style.AccumulationDofApertureSize > 0) then
    dofDistance = style.DofFocusPlane
  end
  if style.LeftDoorOpen then
    for i = 0, Sim.carsCount - 1 do
      ac.setDriverDoorOpen(i, true, true)
    end
  end

  if style.RightDoorOpen then
    for i = 0, Sim.carsCount - 1 do
      local root = ac.findNodes('carRoot:'..tostring(i))
      local filename = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(i)
        ..(ac.getCar(i).isLeftHandDrive and '/animations/car_door_R.ksanim' or '/animations/car_door_L.ksanim')
      root:setAnimation(filename, 1, true)
    end
  end

  cameraAlignFn = function(camera, carIndex)
    camera.transform.position = camera.transform.position + camera:alignCar(carIndex,
      style.AlignCameraHorizontally, style.AlignCameraHorizontallyOffset, style.AlignCameraHorizontallyOffsetRelative,
      style.AlignCameraVertically, style.AlignCameraVerticallyOffset, style.AlignCameraVerticallyOffsetRelative)
  end

  if style.ColorGradingData then
    -- TODO?
  end

  if style.SerializedLights then
    style.ExtraLights = JSON.parse(style.SerializedLights)
  end
  if style.ExtraLights then
    for _, v in ipairs(style.ExtraLights) do
      if v.type < 4 then
        local light = ac.LightSource(ac.LightType.Regular)
        light.position = vec3.new(v.pos)
        light.color:set(parseColor(v.color)):scale(v.brightness * brightnessMult)
        light.range = v.range or 10
        light.direction = vec3.new(v.direction)
        light.spot = v.type == 3 and 90 or v.spot or light.spot
        if v.shadows then
          light.shadows = true
        end
      end
    end
  end
end

if ac.getTrackID() == '../showroom/at_previews' then
  ac.findNodes('trackRoot:yes'):findMeshes('material:dot'):setMaterialProperty('ksAmbient', 0.4)
  -- weather.reflectionSaturation = 0
end

local camera = ac.grabCamera('Previews Generation')
if camera == nil then
  os.showMessage('Failed to generate previews')
  ac.shutdownAssettoCorsa()
  return
end

camera.transform.position = cameraPos
camera.transform.look:set(cameraLookAt):sub(cameraPos)
camera.transform.up = mat4x4.rotation(math.rad(cameraTilt), camera.transform.look).up
camera.fov = cameraFov
camera.dofFactor = dofDistance >= 0 and 1 or 0
camera.dofDistance = dofDistance
camera:normalize()

local appliedSteerValue = steerDeg / 30
for i = 0, Sim.carsCount - 1 do
  local car = ac.getCar(i)
  local offset = -car.graphicsOffset
  if alignCar then
    offset = offset - car.aabbCenter * vec3(1, 0, 1)
  end
  physics.setCarPosition(i, offset, vec3(0, 0, -1))
  physics.disableCarCollisions(i)
  physics.overrideSteering(i, math.clampN(appliedSteerValue, -1, 1))
end

local function detectImageType(filename)
  if string.regmatch(filename, '\\.png$', 1, true) then return ac.ScreenshotFormat.PNG end
  if string.regmatch(filename, '\\.dds$', 1, true) then return ac.ScreenshotFormat.DDS end
  if string.regmatch(filename, '\\.bmp$', 1, true) then return ac.ScreenshotFormat.BMP end
  return ac.ScreenshotFormat.JPG
end

local lastCar

local function shotCar(carIndex, callback)
  for i = 0, Sim.carsCount - 1 do
    ac.setCarActive(i, i == carIndex)
  end
  if groundReflection > 0 then
    __enableMirrorGround__(carIndex, 0.5, 1.6)
  end
  if cameraAlignFn then
    local carID = ac.getCarID(carIndex)
    if carID ~= lastCar then
      lastCar = carID
      camera.transform.position = cameraPos
      cameraAlignFn(camera, carIndex)
    end
  end
  setMetadata(carIndex)
  setTimeout(function ()
    local destination = getPreviewFilename(carIndex)
    local tmpDestination = destination..'.tmp'
    ac.makeScreenshot(tmpDestination, detectImageType(destination), function (err)
      io.deleteFile(destination)
      io.move(tmpDestination, destination)
      ac.setCarActive(carIndex, false)
      if groundReflection > 0 then
        __enableMirrorGround__(-1)
      end
      callback()
    end)
  end, 0.05)
end

local function shotAll(nextIndex)
  if nextIndex == Sim.carsCount then
    setTimeout(function ()
      ac.shutdownAssettoCorsa()
    end, 0.5)
    return
  end
  shotCar(nextIndex, function ()
    shotAll(nextIndex + 1)
  end)
end

local function approximateSteering()
  if steerDeg == 0 then return end
  local curAngle = (math.deg(math.atan2(ac.getCar(0).wheels[0].look.x, ac.getCar(0).wheels[0].look.z))
    + math.deg(math.atan2(ac.getCar(0).wheels[1].look.x, ac.getCar(0).wheels[1].look.z))) / -2
  local correction = steerDeg / curAngle
  if correction > 0.01 and correction < 100 then
    appliedSteerValue = appliedSteerValue * math.lerp(1, correction, 0.5)
    physics.overrideSteering(0, math.clampN(appliedSteerValue, -1, 1))
  end
end

local frameCounter = 0
local totalTime = 0

-- __preventCarsFromRollingAway__()
Register('core', function (dt)
  frameCounter = frameCounter + 1
  local prevTotalTime = totalTime
  if frameCounter > 2 then
    totalTime = totalTime + math.min(dt, 0.04)
  end
  if totalTime < 0.8 then
    approximateSteering()
  end
  if totalTime >= 1 and prevTotalTime < 1 then
    __fixCarsInPlace__()
    rootNodes:setVisible(true)

    setTimeout(function ()
      shotAll(0)
      -- for i = 0, Sim.carsCount - 1 do
      --   ac.setCarActive(i, i == 0)
      -- end
    end, 0.1)
  end
  for i = 0, Sim.carsCount - 1 do
    ac.setTargetCar(i)
    -- ac.setHeadlights(useHeadlights)
    -- ac.setBrakingLightsThreshold(useBrakeLights and -1 or 2)
    ac.setHighBeams(false)
    ac.setDaytimeLights(false)
    if totalTime >= 0.5 and prevTotalTime < 0.5 then
      if i > 0 then
        physics.setAITyres(i, ac.getCar(0).compoundIndex)
      end
    end
  end
  ac.setTargetCar(0)
end)
