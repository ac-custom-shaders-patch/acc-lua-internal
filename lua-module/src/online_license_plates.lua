if not Sim.isOnlineRace or not Config:get('MISCELLANEOUS', 'DRIVER_NAMES_ON_LICENSE_PLATES_ONLINE', false) then
  return
end

local plates = require('shared/sim/plates')

local function updateCarLicensePlate(carIndex)
  local car = ac.getCar(carIndex)
  if car and car.isActive then
    local meshes = ac.findNodes('carRoot:%d' % carIndex)
      :findMeshes('{ texture:plate_d.dds & texture:plate_nm.dds }')
    if #meshes > 0 then
      local driverName = ac.getDriverName(carIndex)
      if car.isConnected and driverName then
        plates.kunos(meshes, driverName, ac.getDriverNationCode(carIndex))
      else
        plates.reset(meshes, carIndex)
      end
    end
  end
end

for i = 0, Sim.carsCount - 1 do
  setTimeout(function ()
    updateCarLicensePlate(i)
  end, 1 + i * 0.1)
end

ac.onClientConnected(function (connectedCarIndex)
  setTimeout(function ()
    updateCarLicensePlate(connectedCarIndex)
  end, 0.1)
end)
ac.onClientDisconnected(function (disconnectedCarIndex, disconnectedSessionID)
  setTimeout(function ()
    updateCarLicensePlate(disconnectedCarIndex)
  end, 0.1)
end)
