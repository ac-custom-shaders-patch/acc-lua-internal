local sorted, flattenedBase

local function scanImages()
  local grouped = {}
  local thisYear = os.date('%Y')
  local thisDay = os.date('%Y %m %d')
  local prevDay = os.date('%Y %m %d', os.time() - 24*60*60)
  local added = 0
  local subDirs = {}

  local function procFile(fileName, fileAttributes, parentDir)
    if added > 100 then return false end
    if not fileAttributes.isDirectory and fileAttributes.fileSize < 1e6 and (fileName:match('%.jpg$') or fileName:match('%.png$')) then
      local creationTime = tonumber(fileAttributes.creationTime)
      local date = os.date('%Y %m %d', creationTime)
      table.insert(table.getOrCreate(grouped, date, function ()
        local sameYear = os.date('%Y', creationTime) == thisYear
        return { title = date == thisDay and 'Today'
          or date == prevDay and 'Yesterday'
          or os.date(sameYear and '%a, %B %d' or '%B %d, %Y', creationTime) }
      end), {creationTime, parentDir..'/'..fileName})
      added = added + 1
    elseif fileAttributes.isDirectory then
      table.insert(subDirs, {tonumber(fileAttributes.creationTime), parentDir..'/'..fileName})
    end
  end

  io.scanDir(ac.getFolder(ac.FolderID.Screenshots), '*.*', procFile, ac.getFolder(ac.FolderID.Screenshots))  

  table.sort(subDirs, function (a, b)
    return a[1] > b[1]
  end)
  for i = 1, #subDirs do
    if added > 100 then break end
    io.scanDir(subDirs[i][2], '*.*', procFile, subDirs[i][2])
  end

  sorted = table.map(grouped, function (item, key) return {key, item} end)
  table.sort(sorted, function (a, b) return a[1] > b[1] end)
  for i = 1, #sorted do
    sorted[i] = sorted[i][2]
  end

  flattenedBase = {}
  for i = 1, #sorted do
    table.sort(sorted[i], function (a, b) return a[1] > b[1] end)
    for j = 1, #sorted[i] do
      sorted[i][j] = sorted[i][j][2]
      table.insert(flattenedBase, sorted[i][j])
    end
  end
end

ac.onScreenshot(function ()
  setTimeout(function () sorted = nil end, 0.3)
end)

local selectedImage
local selectedName
local selectedTransition = touchscreen.createTransition(0.8)

local function getName()
  return type(selectedImage) == 'string' and selectedImage:gsub('.+[/\\]', '') or 'Screenshot'
end

local function drawCategory(title, images)
  ui.text(title)
  ui.offsetCursorY(12)
  for j = 1, #images do
    if j > 1 and ui.availableSpaceX() < 200 then
      ui.newLine()
    end
    if ui.areaVisible(200) then
      ui.image(images[j], 200, true)
      if touchscreen.itemTapped() then
        selectedImage = images[j]
        selectedName = getName()
      end
    else
      ui.dummy(200)
    end
    ui.sameLine(0, 4)
  end
  ui.newLine(40)
end

local prevImage, prevImageOffset, prevImageFitSize
local curImageOffset = 0
local prevScreenshots = -1
local flattened

return function (dt)
  if not sorted then
    prevScreenshots = -1
    scanImages()
  end

  if prevScreenshots ~= #system.screenshots then
    flattened = table.chain(system.screenshots, flattenedBase)
  end

  local size = ui.availableSpace()
  local tr = selectedTransition(dt, selectedImage)
  if selectedImage then
    system.fullscreen()
  end
  ui.offsetCursorX(-math.floor(size.x * tr))

  system.scrollList(dt, size, function ()
    ui.pushFont(ui.Font.Title)

    if #system.screenshots > 0 then
      drawCategory('Screenshots', system.screenshots)
    end
    for i = 1, #sorted do
      local images = sorted[i]
      drawCategory(images.title, images)
    end
    ui.popFont()
  end)

  if tr > 0.001 then
    local pos = vec2(size.x - math.floor(size.x * tr), 0)
    ui.drawRectFilled(pos, pos + size, rgbm.colors.black)    
    ui.setCursor(pos)
    local imageSize = ui.imageSize(selectedImage)
    local fitSize = vec2(imageSize.x / imageSize.y * size.y, size.y)
    ui.offsetCursor((size - fitSize) / 2)

    local swipe = ui.mouseDragDelta(ui.MouseButton.Left, 1).x
    if math.abs(swipe) > 1 then
      local index = table.indexOf(flattened, selectedImage)
      if swipe > 0 and index == 1 or swipe < 0 and index == #flattened then
        swipe = 0
      else
        touchscreen.boostFrameRate()
        if touchscreen.touchReleased() then
          selectedImage = flattened[index - math.sign(swipe)]
          selectedName = getName()
          swipe = 0
        else
          prevImage, prevImageOffset, prevImageFitSize = selectedImage, swipe, fitSize
          curImageOffset = -math.sign(swipe) * ui.windowWidth()
        end
      end
    end
    if swipe ~= 0 then
      ui.offsetCursorX(swipe)
    elseif prevImage then
      prevImageOffset = prevImageOffset + dt * math.sign(prevImageOffset) * 5e3
      if math.abs(prevImageOffset) > ui.windowWidth() then
        prevImageOffset = 0
        prevImage = nil
      else
        local c = ui.getCursor()
        ui.offsetCursorX(prevImageOffset)
        ui.image(prevImage, prevImageFitSize)
        ui.setCursor(c)
      end
      curImageOffset = math.applyLag(curImageOffset, 0, 0.8, dt)
      ui.offsetCursorX(curImageOffset)
    end
    ui.image(selectedImage, fitSize)

    local uiShow = touchscreen.hidingControls(dt)
    if uiShow > 0 then
      ui.pushStyleVarAlpha(math.saturateN(uiShow))
      local gradientColor = rgbm(0, 0, 0, 0.7)
      ui.drawRectFilledMultiColor(pos, pos + vec2(size.x, size.y * 0.3), 
        gradientColor, gradientColor, rgbm.colors.transparent, rgbm.colors.transparent)
      ui.drawRectFilledMultiColor(pos + vec2(0, size.y * 0.7), pos + vec2(size.x, size.y), 
        rgbm.colors.transparent, rgbm.colors.transparent, gradientColor, gradientColor)
      
      ui.setCursor(pos + vec2(20, 20))
      if touchscreen.iconButton(ui.Icons.ArrowLeft, 36) then
        selectedImage = nil
      end
      ui.sameLine(0, 12)
      ui.offsetCursorY(4)
      ui.dwriteTextAligned(selectedName, 20, ui.Alignment.Start, ui.Alignment.Start, vec2(size.x - 130, 36), false, rgbm.colors.white)
      ui.setCursor(pos + vec2(size.x - 20 - 36, 20))
      if touchscreen.iconButton(ui.Icons.Undo, 36, nil, nil, vec2(-1, 1)) then
        ac.setClipboadText(selectedImage)
        ui.toast(ui.Icons.Copy, 'Path to the image is copied to the clipboard')
      end
      ui.popStyleVar()
    end
  end

  if #sorted == 0 then
    ui.textAligned('No images', 0.5, ui.windowSize())
  end
end
