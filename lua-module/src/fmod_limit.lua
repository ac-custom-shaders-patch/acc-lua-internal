if ConfigGeneral:get('AUDIO', 'SILENCE_MALFUNCTIONS', false) then
  __util.native('fmod.limiter.configure', ConfigGeneral:get('AUDIO', 'SILENCE_MALFUNCTIONS_THRESHOLD', 30))
end
