--[[
  At the moment this one is actually some C++ code I wrote a long time ago. Might redo it in Lua a bit later.
]]

ac.applyLiveConfigEdit('walking_out.ini', '[BASIC] SHOW_E_MESSAGE=%d' % (
  ac.INIConfig.scriptSettings():get('SETTINGS', 'SHOW_E_MESSAGE', true) and 1 or 0))

function script.update()
end
