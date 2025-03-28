---@class InertialValue
local InertialValue = class('InertialValue')

---@param value number
---@param mass number
---@param drag number
---@param limit number
---@return InertialValue
function InertialValue:initialize(value, mass, drag, limit)
  self.value = value
  self.velocity = 0
  self.drag = drag
  self.forceMult = 1 / mass
  self.limit = limit or 1
end

function InertialValue:__tostring()
  return '(' .. self.value .. ', vel.=' .. self.velocity .. ')'
end

---@param targetValue number
---@param dt number
function InertialValue:update(targetValue, dt)
  local delta = targetValue - self.value
  self.velocity = math.applyLag(self.velocity, 0, self.drag, dt) + delta * math.min(0.1, dt * self.forceMult)

  local dValue = self.velocity * dt
  if dValue > 0 then
    self.value = self.value + dValue * math.abs(self.limit - self.value)
  else
    self.value = self.value + dValue * math.abs(self.limit + self.value)
  end
end

---@param value number
function InertialValue:reset(value)
  self.value = value
  self.velocity = 0
end

return class.emmy(InertialValue, InertialValue.initialize)