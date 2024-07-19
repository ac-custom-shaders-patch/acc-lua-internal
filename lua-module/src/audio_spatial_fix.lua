--[[
  Replaces engine attenuation distance with small values to make sure there’ll be some sort
  of stereo effect in VR.
]]

local cfgMode = ConfigVRTweaks and ConfigVRTweaks:get('EXTRA_TWEAKS', 'AUDIO_STEREO_FIX', 0) or 0
if cfgMode == 0 or cfgMode == 1 and not Sim.isVRConnected then
  return
end

local prefix = '.oav:xFp89Qsh:'
local function tweakAudio(carIndex, key, volumeBoost, minDistance, maxDistance)
  local storeKey = string.format('%s%s:%s', prefix, carIndex, key)
  local stored = ac.load(storeKey)
  if not stored then
    stored = ac.CarAudioTweak.getVolume(key)
    if math.isNaN(stored) then stored = 1 end
    ac.store(storeKey, stored)
  end
  ac.CarAudioTweak.setVolume(key, stored * volumeBoost)
  ac.CarAudioTweak.setDistanceMin(key, minDistance)
  ac.CarAudioTweak.setDistanceMax(key, maxDistance)
end

local function fixCarAudio(carIndex)
  if not ac.setTargetCar(carIndex) then
    ac.warn('Failed to alter target car')
  else
    tweakAudio(carIndex, ac.CarAudioEventID.EngineInt, 1.5, 0.8, 50)
    tweakAudio(carIndex, ac.CarAudioEventID.EngineExt, 1.5, 2.2, 350)
  end
end

using(function ()
  for i = 0, Sim.carsCount - 1 do
    fixCarAudio(i)
  end
end, function ()
  ac.setTargetCar(0)
end)
