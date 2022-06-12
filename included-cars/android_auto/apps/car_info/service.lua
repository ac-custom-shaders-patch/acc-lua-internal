local brand = ac.getCarBrand(0)
if car.year < 2015 or #brand < 3 or #brand > 9 or brand:sub(1, 1):upper() ~= brand:sub(1, 1) or brand:match('[^A-Za-z ]') then
  error('Might not be fitting app for this car')
end

local brandColors = {
  ['Audi'] = rgbm.colors.black
}

system.runningApp().name = 'My '..brand

-- Alternative way of making a dynamic icon: just set it to an extra canvas. Works well here,
-- because it only needs to be updated once.
system.runningApp().icon = ui.ExtraCanvas(64):clear(rgbm.colors.transparent):update(function (dt)
  ui.setAsynchronousImagesLoading(false)
  ui.drawCircleFilled(32, 30.3, brandColors[brand] or rgbm.colors.white, 30)
  ui.renderTexture({
    filename = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(0)..'/ui/badge.png',
    p1 = vec2(0, 0),
    p2 = vec2(64, 64),
    uv1 = vec2(-0.15, -0.15),
    uv2 = vec2(1.3, 1.3),
    mask1 = io.relative('icon.png'),
    mask1Flags = render.TextureMaskFlags.UseAlpha
  })
end)
