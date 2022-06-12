local v = rgb()

local meta = {
  __index = {
    update = function(self, value, dt)
      local newValue = math.floor(10 * math.applyLag(self.value, value, self.lag, dt)) / 10
      if newValue ~= self.value then
        if not self.uniqueMaterialsSet then
          self.uniqueMaterialsSet = true
          self.meshes:ensureUniqueMaterials()
        end
        v:setLerp(self.colorInactive, self.colorActive, newValue)
        self.meshes:setMaterialProperty('ksEmissive', v)
        self.value = newValue
      end
    end
  }
}

return function(meshes, colorActive, colorInactive, lag, initialValue)
  return setmetatable({ 
    meshes = meshes,
    colorActive = colorActive,
    colorInactive = colorInactive,
    lag = lag,
    value = initialValue or -1e9,
    uniqueMaterialsSet = false
  }, meta)
end