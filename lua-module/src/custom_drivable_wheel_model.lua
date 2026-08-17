if Config:get('MISCELLANEOUS', 'HIDDEN_STEERING_WHEEL_MODEL', '') == '' then
  return
end

local kn5 = ac.findNodes('carRoot:0'):findNodes('BODYTR')
local wheel = kn5:findNodes('STEER_TRANSFORM'):at(1)
if #wheel > 0 then
  local gun = kn5:loadKN5(Config:get('MISCELLANEOUS', 'HIDDEN_STEERING_WHEEL_MODEL', ''))
  if gun then
    gun:applyShaderReplacements('INCLUDE_IN_SECONDARY_VIEWS=0\nFIXED_EMISSIVE=1')
    Register('core', function (dt)
      if Sim.hideSteeringWheel and not wheel:isActive() then -- 
        gun:setVisible(true):getTransformationRaw():set(wheel:getTransformationRaw())
      else
        gun:setVisible(false)
      end
    end)
  end
end