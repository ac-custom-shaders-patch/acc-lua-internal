local carDir = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(car.index)
local info = io.load(carDir..'/ui/ui_car.json')
local description = string.match(info, 'description".-"(.-)"'):gsub('<br>', '\n'):gsub('[\r\t]', ''):gsub('\n\n\n', '\n\n'):trim()

local skinsDir = carDir..'/skins'
local firstSkin = skinsDir..'/'..ac.getCarSkinID(0)..'/preview.jpg'

return function (dt)
  ui.drawRectFilled(0, ui.windowSize(), rgbm.colors.black)
  system.scrollList(dt, function ()
    ui.image(firstSkin, vec2(1022, 575) * (math.min(400, ui.availableSpaceX()) / 1022))
    ui.offsetCursorY(40)
    ui.dwriteText(string.format('Driven distance: %.1f km', car.distanceDrivenTotalKm), 18)
    ui.dwriteText(string.format('Fuel: %.0f L', car.fuel), 18)
    ui.offsetCursorY(30)
    ui.dwriteTextWrapped(description, 14)
  end)
end