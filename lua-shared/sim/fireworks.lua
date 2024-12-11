--[[
  Library for adding custom dynamic firework sources. Requires fireworks particles to be active,
  otherwise won’t have any effect.

  To use, include with `local fireworks = require('shared/sim/fireworks')`.
]]
---@diagnostic disable

local fireworks = {}

do
  ---A helper for launching custom fireworks in custom positions. Call `:dispose()` when it’s no longer
  ---needed or just set intensity to 0. Custom fireworks will stop when your script unloads.
  ---@class ac.FireworksEmitter
  ---@field private key integer
  ---@field private position vec3
  ---@field private type ac.HolidayType
  ---@field private intensity number
  ---@field private dirty boolean
  ---@field private initialize function
  ---@field private applyChanges function
  local _fireworks_Emitter = class('ac.FireworksEmitter')

  ---@param position vec3 @Firework position in world space.
  ---@param intensity number? @Default value: 1.
  ---@param type ac.HolidayType? @Holiday type. Default value: `ac.HolidayType.Generic`.
  ---@return ac.FireworksEmitter
  function _fireworks_Emitter.allocate(position, intensity, type)
    return {
      key = math.randomKey(),
      position = position,
      intensity = intensity,
      type = type,
      dirty = false
    }
  end

  function _fireworks_Emitter:initialize()
    self.releaseListener = ac.onRelease(function ()
      self:dispose()
    end)
    self:applyChanges()
  end

  function _fireworks_Emitter:applyChanges()
    if self.dirty or not self.releaseListener then return end
    self.dirty = true
    setTimeout(function ()
      self.dirty = false
      ac.debug('pos', self.position)
      ac.broadcastSharedEvent('csp.fireworksCustomEmit', {
        key = self.key,
        pos = self.position,
        intensity = tonumber(self.intensity) or 1,
        holidayType = tonumber(self.type) or ac.HolidayType.Generic,
      })
    end, 0)
  end

  ---Stops and removes emitter.
  function _fireworks_Emitter:dispose()
    if self.releaseListener then
      self.releaseListener()
      ac.broadcastSharedEvent('csp.fireworksCustomEmit', {
        key = self.key
      })
      self.releaseListener = nil
    end
  end

  ---@param position vec3
  ---@return self
  function _fireworks_Emitter:setPosition(position)
    self.position = position
    self:applyChanges()
    return self
  end

  ---@param type ac.HolidayType
  ---@return self
  function _fireworks_Emitter:setType(type)
    self.type = type
    self:applyChanges()
    return self
  end

  ---@param intensity number
  ---@return self
  function _fireworks_Emitter:setIntensity(intensity)
    self.intensity = intensity
    self:applyChanges()
    return self
  end

  ---@return vec3
  function _fireworks_Emitter:getPosition()
    return self.position
  end

  ---@return ac.HolidayType
  function _fireworks_Emitter:getType()
    return self.type
  end

  ---@return number
  function _fireworks_Emitter:getIntensity()
    return self.intensity
  end

  fireworks.Emitter = class.emmy(_fireworks_Emitter, _fireworks_Emitter.allocate)
end

return fireworks