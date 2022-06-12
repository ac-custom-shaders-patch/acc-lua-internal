--[[
  A small script running during loading before most of AC is ready, with limited API.
  Used for patching some Python apps, adding missing data and such.
]]

local function proTyresSync(carIndex, proTyresPath)
  if io.dirExists(proTyresPath) then
    ac.debug('found dir', proTyresPath)

    local tyresIni = ac.INIConfig.carData(carIndex, 'tyres.ini')
    if #tyresIni:get('FRONT', 'NAME', '') ~= 0 then
      local srcCarDir = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(carIndex)..'/data'
      local dstCarDir = proTyresPath..'/'..ac.getCarID(carIndex)
      io.createDir(dstCarDir)

      local filesToCopy = {}
      for i = 0, 100 do
        local wf = tyresIni:get(i == 0 and 'FRONT' or 'FRONT_'..tostring(i), 'WEAR_CURVE', '')
        local wr = tyresIni:get(i == 0 and 'REAR' or 'REAR_'..tostring(i), 'WEAR_CURVE', '')
        local sf = tyresIni:get(i == 0 and 'THERMAL_FRONT' or 'THERMAL_FRONT_'..tostring(i), 'PERFORMANCE_CURVE', '')
        local sr = tyresIni:get(i == 0 and 'THERMAL_REAR' or 'THERMAL_REAR_'..tostring(i), 'PERFORMANCE_CURVE', '')
        if #sf == 0 and #sr == 0 and #wf == 0 and #wr == 0 then break end
        table.insert(filesToCopy, wf)
        table.insert(filesToCopy, wr)
        table.insert(filesToCopy, sf)
        table.insert(filesToCopy, sr)
      end

      ac.debug('filesToCopy', stringify(filesToCopy))
      if #filesToCopy > 0 then
        for _, name in ipairs(table.distinct(filesToCopy)) do
          if #name > 0 then
            local data = ac.readDataFile(srcCarDir..'/'..name)
            if #data > 0 then io.save(dstCarDir..'/'..name, data) end
          end
        end
        tyresIni:save(dstCarDir..'/tyres.ini')
      end
    end
  end
end

proTyresSync(0, ac.getFolder(ac.FolderID.Root)..'/apps/python/proTyres/cars')
proTyresSync(0, ac.getFolder(ac.FolderID.Root)..'/apps/python/proTyres/cars_extra')

