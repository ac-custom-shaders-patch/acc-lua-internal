--[[
  Note: libraries in `shared/unstable` can break at any moment and might not be compatible with
  upcoming CSP updates.

  This library can be used to alter camera matrices live. It can break certain rendering modes,
  so please use very carefully.
]]

local viewBuffer = {}

---@param callback fun(buffer: {view: mat4x4, projection: mat4x4, cameraPosition: vec3})
---@return ac.Disposable
function viewBuffer.on(callback)
  local con = ac.connect({
    ac.StructItem.explicit(4, 4),
    view = ac.StructItem.mat4x4(),
    projection = ac.StructItem.mat4x4(),
    _pad0 = ac.StructItem.mat4x4(),
    cameraPosition = ac.StructItem.vec3(),
  }, true, '​system/camera')
  return __util.native('inner_test_onMainCameraMatricesCompute', function ()
    callback(con)
  end)
end

return viewBuffer