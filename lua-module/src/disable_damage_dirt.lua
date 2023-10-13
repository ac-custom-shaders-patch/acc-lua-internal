--[[
  Disables damage and dirt from car materials.
]]--

if Config:get('MISCELLANEOUS', 'DISABLE_DAMAGE_DIRT', false) then
  ac.findAny('supportsDamage:yes'):setMaterialTexture('txDamageMask', rgbm.colors.transparent)
end
