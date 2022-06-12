---@class PackedArgs
local PackedArgs = class()

---@return PackedArgs
function PackedArgs.allocate()
  return {}
end

function PackedArgs:pack2(a, b)
  self[1] = a
  self[2] = b
  return self
end

function PackedArgs:pack3(a, b, c)
  self[1] = a
  self[2] = b
  self[3] = c
  return self
end

function PackedArgs:pack4(a, b, c, d)
  self[1] = a
  self[2] = b
  self[3] = c
  self[4] = d
  return self
end

return class.emmy(PackedArgs, PackedArgs.allocate)
