if ConfigGeneral:get('AUDIO', 'ALTER_DAMAGED_ENGINE_AUDIO', false) then
  local tweakAmount = 0

  local function updateAudio()
    for _, v in ipairs({ac.CarAudioEventID.EngineInt, ac.CarAudioEventID.EngineExt}) do
      if tweakAmount > 0.01 then
        ac.CarAudioTweak.setDSP(v, 'highpass:$SmallTweaks.damage', 0, 500)
        ac.CarAudioTweak.setDSP(v, 'highpass:$SmallTweaks.damage', 'wetDry', {prewet = 1, postwet = tweakAmount, dry = 1 - tweakAmount})
      else
        ac.CarAudioTweak.setDSP(v, 'highpass:$SmallTweaks.damage', 'remove')
      end
    end
  end

  Register('core', function (dt)
    local damageAmount = math.lerpInvSat(Car.engineLifeLeft, 500, 0)
    if math.abs(damageAmount - tweakAmount) > 0.003 then
      tweakAmount = damageAmount
      updateAudio()
    end
  end)
end
