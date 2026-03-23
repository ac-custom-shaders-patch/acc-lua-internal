--[[
  Not much to do here for now.
]]

local cfg = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  FORCE_SNOWFLAKES = false,
})

if cfg.FORCE_SNOWFLAKES then
  ac.forceSnow()
end