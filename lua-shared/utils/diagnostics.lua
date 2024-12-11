--[[
  Simple library for some core-related insights.
]]
---@diagnostic disable

local diagnostics = {}

---Returns some counters from render stats app.
---@return {drawCalls: integer, sceneTriangles: integer, lights: integer, extraShadows: integer}
function diagnostics.renderStats()
  return __util.native('lib_renderStats')
end

return diagnostics
