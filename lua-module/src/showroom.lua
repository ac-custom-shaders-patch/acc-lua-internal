-- local showroom = ac.findNodes('trackRoot:yes')
-- showroom:findMeshes('?'):setMaterialProperty('ksAmbient', 0.4)
-- showroom:findMeshes('?'):setMaterialProperty('ksDiffuse', 0.4)
-- showroom:findMeshes('?'):setMaterialTexture('txDiffuse', rgbm(1, 0.8, 0.6, 1))

if Sim.isShowroomMode then
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

  Register('core', function(dt)
    if not UI.wantCaptureKeyboard and not UI.wantCaptureMouse and ac.isKeyPressed(ui.KeyIndex.Space) then
      ac.setDriverDoorOpen(0, not Car.isDriverDoorOpen, false)
    end
    if not UI.wantCaptureKeyboard and not UI.wantCaptureMouse and ac.isKeyPressed(ui.KeyIndex.Return) then
      local flyin = not flycamGrab
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
          flycamSpline = flycamSpline or require('shared/math/cubic').vec(path)
          ac.setDriverDoorOpen(0, true, false)
          transition(3, function(time)
            if not flyin then
              time = 1 - time
            end
            time = math.smootherstep(time)
            local x = flycamSpline.get(time * 0.99)
            local y = flycamSpline.get(math.lerp(time, 1, 0.5))
            flycamGrab.ownShare = math.min(time * 2, 1)
            flycamGrab.transform.up = vec3(0, 1, 0)
            flycamGrab.transform.position = math.lerp(flycamGrab.transform.position, x, time ^ 2)
            flycamGrab.transform.look = math.lerp(flycamGrab.transform.look, math.lerp((y - x):normalize(), Car.look, time ^ 4), time ^ 2)
          end, function ()
            ac.setDriverDoorOpen(0, false, false)
            if not flyin then
              flycamGrab:dispose()
              flycamGrab, flycamSpline = nil, nil
            end
          end)
        end
      end
    end
    if Sim.frame < 30 then
      ac.setCurrentCamera(ac.CameraMode.OnBoardFree)
    end
    if Car.gas > 0.1 then
      physics.setEngineStallEnabled(0, false)
    end
  end)
end
