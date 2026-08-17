-- local showroom = ac.findNodes('trackRoot:yes')
-- showroom:findMeshes('?'):setMaterialProperty('ksAmbient', 0.4)
-- showroom:findMeshes('?'):setMaterialProperty('ksDiffuse', 0.4)
-- showroom:findMeshes('?'):setMaterialTexture('txDiffuse', rgbm(1, 0.8, 0.6, 1))

if not Sim.isShowroomMode then
  return
end

physics.setEngineRPM(0, 0)
physics.setEngineStallEnabled(0, true)

local function transition(time, callback, endCallback)
  local cur = os.preciseClock()
  setInterval(function()
    local now = os.preciseClock() - cur
    if now > time then
      if endCallback then pcall(endCallback) end
      return clearInterval
    else
      callback(now / time)
    end
  end)
  callback(0)
end

local flycamGrab, flycamSpline
local flycamCur, flycamTarget = 0, 0

local function setFlyCam(progress)
  local time = math.smootherstep(progress)
  local x = flycamSpline.get(time * 0.99)
  local y = flycamSpline.get(math.lerp(time, 1, 0.9))
  flycamGrab.ownShare = math.min(time * 2, 1)
  flycamGrab.transform.up = vec3(0, 1, 0)
  flycamGrab.transform.position = math.lerp(flycamGrab.transform.position, x, time ^ 2)
  flycamGrab.transform.look = math.lerp(flycamGrab.transform.look, math.lerp((y - x):normalize(), Car.look, time ^ 4), time ^ 2)    
end

local function switchFlyIn()
  flycamGrab = flycamGrab or ac.grabCamera('Flycam')
  if flycamGrab then
    local ordered = {}
    do
      local flycams = ac.findNodes('carRoot:0'):findNodes('FLYCAM_L_?')
      for i = 1, #flycams do
        ordered[i] = { flycams:name(i), flycams:at(i):getPosition() }
      end
      table.sort(ordered, function(a, b) return a[1] < b[1] end)
    end

    local path = { Sim.cameraPosition:clone() }
    for _, v in ipairs(ordered) do
      path[#path + 1] = v[2]
    end

    if #path > 1 then
      if not flycamSpline then
        flycamSpline = require('shared/math/cubic').vec(path)
        setInterval(function ()
          if flycamCur == flycamTarget then return end
          flycamCur = math.saturateN(flycamCur + math.sign(flycamTarget - flycamCur) * Sim.dt * 0.5)
          setFlyCam(flycamCur)
          if flycamCur == flycamTarget then
            ac.setDriverDoorOpen(0, false, false)
            if flycamCur == 0 and flycamGrab then
              flycamGrab:dispose()
              flycamGrab = nil
            end
          end
        end)
      end
      flycamTarget = 1 - flycamTarget
      ac.setDriverDoorOpen(0, true, false)
    end
  end
end

ac.ControlButton('__cspinner_showroom_doors', { keyboard = { key = ui.KeyIndex.Space } }):onPressed(function ()
  ac.setDriverDoorOpen(0, not Car.isDriverDoorOpen, false)
end)

ac.ControlButton('__cspinner_showroom_flyin', { keyboard = { key = ui.KeyIndex.Return } }):onPressed(function ()
  switchFlyIn()
end)

local busy = nil
local curSkinID = ac.getCarSkinID(0)

local function carSwapAction(carID, skinID, physics)
  curSkinID = skinID
  if busy then
    busy = carSwapAction:bind(carID, skinID, physics)
    return
  end
  busy = true
  if not carID then
    carID = ac.getCarID(0)
  end
  if not skinID then
    skinID = io.scanDir(ac.getFolder(ac.FolderID.ContentCars)..'/'..carID..'/skins')[1] or ''
    curSkinID = skinID
  end
  __util.native('__replace_remote_car_model', 0, carID, skinID, physics or false, function ()
    if type(busy) == 'function' then setTimeout(busy) end
    busy = false
  end)
end

local function switchSkin(step)
  local skins = io.scanDir(ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(0)..'/skins')
  if #skins > 1 then
    local curSkinIndex = table.indexOf(skins, curSkinID)
    carSwapAction(nil, skins[((curSkinIndex or 1) - 1 + step) % #skins + 1])
  end
end

local carsCache = nil

---@return {id: string, name: string?, icon: string}
local function getCarsList()
  if not carsCache then
    carsCache = {}
    setTimeout(function ()
      for _, id in ipairs(io.scanDir(ac.getFolder(ac.FolderID.ContentCars))) do
        table.insert(carsCache, {id = id, icon = ac.getFolder(ac.FolderID.ContentCars)..'/'..id..'/logo.png'})
      end
    end)
  end
  return carsCache
end

ac.ControlButton('__cspinner_showroom_prevskin', { keyboard = { key = ui.KeyIndex.Prior } }):onPressed(function () switchSkin(-1) end)
ac.ControlButton('__cspinner_showroom_nextskin', { keyboard = { key = ui.KeyIndex.Next } }):onPressed(function () switchSkin(1) end)

local changingCar = false
local idByName = {}

ac.ControlButton('__cspinner_showroom_changecar', { keyboard = { key = ui.KeyIndex.Oem3, alt = true } }):onPressed(function ()
  if changingCar then
    changingCar = false
    return
  end
  changingCar = true
  ui.modalDialog('Change car', function ()
    local canReadName = true
    local done = false
    for i, v in ipairs(getCarsList()) do
      if ui.areaVisibleY(20) then
        ui.pushID(i)
        if not v.name and canReadName then
          v.name = ac.getCarNameByID(v.id)
          idByName[v.name] = (idByName[v.name] or 0) + 1
          canReadName = false
        end
        ui.setNextItemIcon(v.icon)
        if ui.selectable(not v.name and v.id 
            or idByName[v.name] > 1 and ('%s (%s)' % {v.name, v.id})
            or v.name, v.id == ac.getCarID(0), ui.SelectableFlags.SpanClipRect, vec2(120, 18)) then
          carSwapAction(v.id, nil, true)
          done = true
        end
        ui.popID()
      else
        ui.offsetCursorY(24)
      end
    end
    return done or not changingCar
  end, true, function ()
    changingCar = false
  end)
end)

Register('core', function(dt)
  if Car.gas > 0.1 then
    physics.setEngineStallEnabled(0, false)
  end
end)
