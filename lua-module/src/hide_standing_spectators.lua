--[[
  Hides standing spectators.
]]--

if Config:get('MISCELLANEOUS', 'HIDE_STANDING_SPECTATORS', false) then
  ac.findAny('texture:people_stand.dds'):setAttribute('SmallTweaks.HiddenSpectators', true):setVisible(false)
else
  ac.findAny('hasAttribute:SmallTweaks.HiddenSpectators'):setVisible(true)
end
