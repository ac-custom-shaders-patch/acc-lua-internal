-- Separate part running in render thread (can’t exchange data with main module
-- directly)

require 'common'

ac.store('$SmallTweaks.DSEmulatorAvailable', 1)
ac.broadcastSharedEvent('$SmallTweaks.ReloadScript')

DualSenseEmulator.available = true
DualSenseEmulator.carIndex = __carIndex

local imageFilename

local function launchApp()
  local serverPort = 46557
  local filename = ac.getFolder(ac.FolderID.AppDataTemp)..'/accsp_gamepad_qr_'..tostring(serverPort)..'.png'
  
  ac.debug('Port', serverPort)
  imageFilename = nil

  if io.exists(filename) then
    io.deleteFile(filename)
    ui.unloadImage(filename)
  end

  os.runConsoleProcess({ 
    filename = ac.getFolder(ac.FolderID.ExtRoot)..'/internal/plugins/AcTools.GamepadServer.exe',
    workingDirectory = __dirname,
    environment = {
      GAMEPAD_SERVER_IMAGE = filename,
      GAMEPAD_SERVER_PORT = serverPort
    },
    inheritEnvironment = true,
    terminateWithScript = true,
    timeout = 0
  }, function (err, data)
    ac.warn('Gamepad server shut down: err='..tostring(err)..', stderr='..(data and data.stderr or '?')..
      ', stdout='..(data and data.stdout or '?'))
    setTimeout(launchApp, 3)
  end)

  setTimeout(function ()
    imageFilename = filename
  end, 3)
end

launchApp()

local snackShortURL = 'https://snack.expo.dev/@x4fab/gamepad-app'
local snackURL = 'https://snack.expo.dev/@x4fab/gamepad-app?platform=mydevice&supportedPlatforms=mydevice&theme=dark&hideQueryParams=true'
local qr = require('shared/utils/qr')
local icons = ui.atlasIcons('res/icons.png', 2, 2, {
  Android = {1, 1},
  Apple = {1, 2},
  Expo = {2, 1}
})

local function step(v)
  return (math.floor(v / 2) + math.smoothstep(math.min(v % 2, 1)))
end

local function loadingAnimation(center)
  local t = ui.time()
  ui.pathArcTo(center, 20, step(t * 1.3 + 1) * 4.5 + t * 3, step(t * 1.3) * 4.5 + 5 + t * 3, 40)
  ui.pathStroke(rgbm.colors.black, false, 4)
end

local installationGuideCur = {}
local installationGuideDone = false

local function installationGuideStep(title, qrFilename, nextStep)
  local c = ui.getCursor()
  ui.offsetCursorX(135)
  ui.text(title)
  ui.offsetCursorX(135)
  ui.drawRectFilled(ui.getCursor(), ui.getCursor() + 200, rgbm.colors.white, 6)
  loadingAnimation(ui.getCursor() + 100)
  ui.drawImageRounded(qrFilename, ui.getCursor(), ui.getCursor() + 200, 6)
  ui.setCursor(c + vec2(0, 92))
  if ui.modernButton('Back', vec2(60, 60), ui.ButtonFlags.VerticalLayout, ui.Icons.ArrowLeft) then
    table.remove(installationGuideCur)
  end  
  ui.setCursor(c + vec2(140 * 3 + 16 - 40, 92))
  if ui.modernButton(nextStep and 'Next' or 'OK', vec2(60, 60), (nextStep and 0 or ui.ButtonFlags.Confirm) + ui.ButtonFlags.VerticalLayout, 
      nextStep and ui.Icons.ArrowRight or ui.Icons.Confirm) then
    if nextStep then installationGuideCur[#installationGuideCur + 1] = nextStep else installationGuideDone = true end
  end
  ui.setCursor(c + vec2(0, 230))
end

local function installationGuide()
  if #installationGuideCur > 0 then
    return installationGuideCur[#installationGuideCur]()
  end

  ui.text('What is your mobile OS?')
  local w = 140
  if ui.modernButton('Android', vec2(w, 40), ui.ButtonFlags.None, icons.Android) then
    installationGuideCur[#installationGuideCur + 1] = function ()
      installationGuideStep('Install Expo Go:', qr.encode('https://play.google.com/store/apps/details?id=host.exp.exponent'),
        function ()
          installationGuideStep('Scan QR code with Expo Go:', qr.encode('exp://exp.host/@x4fab/gamepad-app+bmA8u2NOvS'),
            function ()
              installationGuideStep('Start Gamepad FX app and scan:', imageFilename)
            end)
        end)
    end
  end
  ui.sameLine(0, 8)
  if ui.modernButton('iOS', vec2(w, 40), ui.ButtonFlags.None, icons.Apple) then
    installationGuideCur[#installationGuideCur + 1] = function ()
      installationGuideStep('Install Expo Go:', qr.encode('https://itunes.apple.com/app/apple-store/id982107779'),
        function ()
          installationGuideStep('Scan QR code with camera:', qr.encode('exp://exp.host/@x4fab/gamepad-app+bmA8u2NOvS'),
            function ()
              installationGuideStep('Start Gamepad FX app and scan:', imageFilename)
            end)
        end)
    end
  end
  ui.sameLine(0, 8)
  if ui.modernButton('Custom', vec2(w, 40), ui.ButtonFlags.None, icons.Expo) then
    installationGuideCur[#installationGuideCur + 1] = function ()
      ui.textWrapped('Get this Expo Snack written with React Native to run on your device somehow:')
      if ui.textHyperlink(snackShortURL) then os.openURL(snackURL) end
      if ui.itemHovered() then ui.setTooltip('Click to open URL in browser') end
      ui.offsetCursorY(12)
    end
  end
end

function script.drawUI()
  ui.setCursor(vec2(ui.windowWidth() - 252, 90))
  ui.childWindow('qrCodePopup', vec2(224, 272), function ()
    ui.drawRectFilled(vec2(0, 0), vec2(224, 272), rgbm(0, 0, 0, 0.4), 10)
    ui.drawRectFilled(vec2(12, 60), vec2(212, 260), rgbm.colors.white, 8)
    loadingAnimation(vec2(112, 160))
    ui.drawImageRounded(imageFilename, vec2(12, 60), vec2(212, 260), 8)

    ui.pushFont(ui.Font.Title)
    ui.textAligned('Gamepad FX Mobile', 0.5, vec2(224, 38))
    ui.popFont()
    ui.setCursor(vec2(20, 39))
    ui.pushFont(ui.Font.Small)
    ui.text('Scan QR code with')
    ui.sameLine()
    if ui.textHyperlink('Gamepad FX app') then
      installationGuideCur = {}
      installationGuideDone = false
      ui.modalDialog('Gamepad FX Installation', function ()
        installationGuide()
        ui.offsetCursorY(5)
        return ui.modernButton('Close', vec2(ui.availableSpaceX(), 40), ui.ButtonFlags.Cancel, ui.Icons.Cancel) or installationGuideDone
      end)
    end
    ui.popFont()
  end)
end

function script.frameBeginPreview(dt)
  DualSenseEmulator.touch1Pos.x = SM.touch1X
  DualSenseEmulator.touch1Pos.y = SM.touch1Y
  DualSenseEmulator.touch2Pos.x = SM.touch2X
  DualSenseEmulator.touch2Pos.y = SM.touch2Y
  DualSenseEmulator.batteryCharge = SM.batteryCharge / 100
  DualSenseEmulator.batteryCharging = SM.batteryCharging
end

local sim = ac.getSim()
local car = ac.getCar(__carIndex)
local aiIni = ac.INIConfig.carData(__carIndex, 'ai.ini')
local rpmUp = aiIni:get('GEARS', 'UP', 9000)
local rpmDown = math.max(aiIni:get('GEARS', 'DOWN', 6000), aiIni:get('GEARS', 'UP', 9000) / 2)
local prevPressed = {}

function script.update(dt)
  ac.setDrawUIActive(IsOffline() and imageFilename and io.fileExists(imageFilename))

  if #installationGuideCur > 0 and not IsOffline() then
    installationGuideDone = true
  end

  SM.lightBarColor[2] = math.saturateN(DualSenseEmulator.lightBarColor.r) * 255
  SM.lightBarColor[1] = math.saturateN(DualSenseEmulator.lightBarColor.g) * 255
  SM.lightBarColor[0] = math.saturateN(DualSenseEmulator.lightBarColor.b) * 255
  SM.lightBarColor[3] = math.saturateN(DualSenseEmulator.lightBarColor.mult) * 255
  SM.relativeRpm = 65535 * math.lerpInvSat(car.rpm, rpmDown, rpmUp)

  if sim.isPaused or sim.isInMainMenu or sim.isReplayActive or not sim.isWindowForeground then
    SM.vibrationLeft = 0
    SM.vibrationRight = 0
  end

  SM.headlightsActive = car.headlightsActive
  SM.lowBeamsActive = car.lowBeams
  SM.absOff = car.absModes > 0 and car.absMode == 0
  SM.tcOff = car.tractionControlModes > 0 and car.tractionControlMode == 0
  SM.absPresent = car.absModes > 0
  SM.tcPresent = car.tractionControlModes > 0
  SM.turboPresent = car.adjustableTurbo
  SM.clutchPresent = not car.autoClutch
  SM.wipersPresent = car.wiperModes > 1
  SM.headlightsPresent = car.headlightsAreHeadlights
  SM.needsDPad = sim.needsDPad
  SM.gearsCount = car.gearCount
  SM.gear = car.gear + 1
  SM.paused = sim.isPaused or sim.isInMainMenu or sim.isReplayActive or sim.isLookingAtSessionResults
  -- ac.debug('sim.needsDPad', sim.needsDPad)

  if SM.wiperDown ~= (prevPressed.wiperDown == true) then
    prevPressed.wiperDown = not prevPressed.wiperDown
    if prevPressed.wiperDown then ac.setWiperMode((car.wiperMode + car.wiperModes - 1) % car.wiperModes) end
  end

  if SM.wiperUp ~= (prevPressed.wiperUp == true) then
    prevPressed.wiperUp = not prevPressed.wiperUp
    if prevPressed.wiperUp then ac.setWiperMode((car.wiperMode + 1) % car.wiperModes) end
  end

  if SM.neutralGear ~= (prevPressed.neutralGear == true) then
    prevPressed.neutralGear = not prevPressed.neutralGear
    if prevPressed.neutralGear then ac.switchToNeutralGear() end
  end

  if SM.lowBeams ~= (prevPressed.lowBeams == true) then
    prevPressed.lowBeams = not prevPressed.lowBeams
    if prevPressed.lowBeams then ac.setHighBeams(car.lowBeams) end
  end
  
  local r = 0
  if SM.povDir == 1 then r = r + ac.GamepadButton.DPadUp
  elseif SM.povDir == 2 then r = r + ac.GamepadButton.DPadRight
  elseif SM.povDir == 3 then r = r + ac.GamepadButton.DPadDown
  elseif SM.povDir == 4 then r = r + ac.GamepadButton.DPadLeft end
  if SM.povClick then r = r + ac.GamepadButton.A end
  if SM.pause then r = r + ac.GamepadButton.Start end
  -- ac.debug('SM.povDir', SM.povDir)
  -- ac.debug('SM.povClick', SM.povClick)
  -- ac.debug('SM.pause', SM.pause)
  ac.setButtonPressed(r)
end

