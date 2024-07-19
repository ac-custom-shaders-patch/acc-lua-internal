--[[
  Library with some extra features for advanced AI tweaks.

  To use, include with `local ai = require('shared/sim/ai')`.
]]

local ai = {
  spline = {
  }
}

---Replaces currently loaded fast spline with a new one, meant for development purposes. Can be used by scripts with gameplay API access only.
---@param filename string @Path to fast_lane.ai.
---@return boolean @Returns `false` if operation has failed.
function ai.spline.loadFast(filename)
  return __util.native('aiSpline.reload', filename)
end

return ai