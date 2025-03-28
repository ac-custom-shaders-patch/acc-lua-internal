if not Sim.isReplayOnlyMode and ConfigGeneral:get('PHYSICS_EXPERIMENTS', 'STALLING', false) and Car then
  local btn0 = ac.ControlButton('__EXT_STARTER')
  local check = btn0:configured() and function ()
    return btn0:down()
  end or ac.isControllerGasPressed

  local stalledTime = 0
  local starterOverheat = 0
  local fakeAudio = 0
  local audioAltered = false
  __starterState__(1e-30)

  local function waveAdj(x)
    local i = (x % 1) ^ 2
    return math.sin(i * math.pi) ^ 2
  end

  local function updateAudio()
    if fakeAudio > 0 then
      audioAltered = true
    end
    if audioAltered then
      audioAltered = false
      local highPass = math.saturate((1 - Car.rpm / math.max(100, Car.rpmMinimum)) * 5)
      local phase = math.lerp(math.smootherstep(waveAdj(stalledTime * 3.7)), 1, 0)
      for _, v in ipairs({ac.CarAudioEventID.EngineInt, ac.CarAudioEventID.EngineExt}) do
        if fakeAudio > 0 then
          ac.CarAudioTweak.setDSP(v, 'highpass:$SmallTweaks.starter', 0, 4000 * (1 - 0.5 * phase) * fakeAudio * highPass)
        else
          ac.CarAudioTweak.setDSP(v, 'highpass:$SmallTweaks.starter', 'remove')
        end
        if fakeAudio > 0.5 then
          ac.CarAudioTweak.setParameter(v, 'throttle', 1, true)
        else
          ac.CarAudioTweak.setParameter(v, 'throttle', 0)
        end
      end
    end
  end

  Register('core', function (dt)
    local stalled = Car.rpm < Car.rpmMinimum
    if stalled then
      stalledTime = stalledTime + dt * (0.1 + Car.rpm / math.max(100, Car.rpmMinimum))
      fakeAudio = math.min(fakeAudio + dt * 10, 1)
    elseif fakeAudio > 0 then
      fakeAudio = math.max(0, fakeAudio - dt * 10)
    end

    updateAudio()

    local starterPressed = stalled and not Sim.isPaused and not Sim.isInMainMenu and check()
    if not starterPressed then
      starterOverheat = 0
    else
      if starterOverheat > 2 then
        starterPressed = false
      else
        starterOverheat = starterOverheat + dt
        local damageAmount = math.lerpInvSat(Car.engineLifeLeft, 100, 0)
        if starterPressed and damageAmount > 0.5 then
          ac.setSystemMessage('Car is stalled', 'Engine is too damaged to start')
        end
        starterPressed = Car.rpm < Car.rpmMinimum * (1 - 0.1 * damageAmount)
      end
    end

    __starterState__(starterPressed and 20 * (1 + math.sin(stalledTime * 10)) or 1e-30)
  end)
end
