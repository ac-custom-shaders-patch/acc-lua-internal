-- Can load images from a folder:
-- local imagesDir = io.relative('res')
-- local images = table.map(io.scanDir(imagesDir, '*.jpg'), function (file) return imagesDir..'/'..file end)

-- Or from a ZIP file:
local archive = io.relative('res.zip')
local images = table.map(io.scanZip(archive), function (x) return x:match('%.jpg$') and archive..'::'..x end)

local selectedImage = images[1]
local smoothBackground = ui.ExtraCanvas(64)

return function (dt)
  if #images == 0 then
    ui.textAligned('No backgrounds found', 0.5, ui.availableSpace())
    return
  end

  touchscreen.forceAwake()
  system.transparentTopBar()
  smoothBackground:update(function (dt)
    -- silly and far from optimal way to blend between images, but this app isn’t that important and we need extra blurring step anyway
    ui.beginBlurring()
    ui.drawImage(selectedImage, 0, ui.windowSize(), rgbm(1, 1, 1, 0.1))
    ui.endBlurring(0.1)
  end)
  ui.beginBlurring()
  ui.drawImage(smoothBackground, 0, ui.windowSize())
  ui.endBlurring(0.1)

  system.scrollList(dt, function ()
    local size = vec2(465, 240)
    for i = 1, #images do
      if ui.areaVisible(size) then
        ui.image(images[i], size, rgbm.colors.white, rgbm(0, 0, 0, 0.05), true)
      else
        ui.dummy(size)
      end
    end
    local stickyMult = math.lerpInvSat(math.abs(touchscreen.scrollingVelocity()), 4, 1.2)
    ui.setScrollY((math.floor(ui.getScrollY() / 240 + 0.5) * 240 - ui.getScrollY()) * stickyMult / 5, true)
    selectedImage = images[math.floor(ui.getScrollY() / 240 + 0.5) + 1] or selectedImage
  end)

  ui.setCursor(vec2(ui.windowWidth() - 160, ui.windowHeight() / 2 - 17))
  if touchscreen.accentButton(ui.Icons.Confirm, 34) then
    system.setWallpaper(selectedImage)
    system.closeApp()
  end
end