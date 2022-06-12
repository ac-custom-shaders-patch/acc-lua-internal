local TurnTrajectory = require('TurnTrajectory')
local CacheTable = require('CacheTable')

local _mceil = math.ceil
local _mfloor = math.floor
local _mmax = math.max

---@param a TurnBaseTrajectory
---@param b TurnBaseTrajectory
local function _curvesIntersect(a, b)
  local as = _mceil(#a / 4)
  local bs = _mceil(#b / 4)
  local ad, am = #a * 0.05, #a * 0.95 / as
  local bd, bm = #b * 0.05, #b * 0.95 / bs
  for i = 0, as do
    local ap = a:getPointRef(ad + am * i)
    for j = 0, bs do
      local bp = b:getPointRef(bd + bm * j)
      if ap:distanceSquared(bp) < 3^2 then
        return true
      end
    end
  end
  return false
end

---@param a TurnBaseTrajectory
---@param b TurnBaseTrajectory
local function _curvesIntersectAfter(a, b, relOffsetA, relOffsetB)
  local as = _mceil(#a / 4)
  local bs = _mceil(#b / 4)
  local ad, am = #a * 0.05, #a * 0.95 / as
  local bd, bm = #b * 0.05, #b * 0.95 / bs
  for i = _mfloor(_mmax(relOffsetA, 0) * as), as do
    local ap = a:getPointRef(ad + am * i)
    for j = _mfloor(_mmax(relOffsetB, 0) * bs), bs do
      local bp = b:getPointRef(bd + bm * j)
      -- if not ap or not bp then 
      --   ac.debug('IA: ap', ap)
      --   ac.debug('IA: bp', bp)
      --   ac.debug('IA: relOffsetA', relOffsetA)
      --   ac.debug('IA: relOffsetB', relOffsetB)
      --   error('ap==nil or bp==nil') 
      -- end
      if ap and bp and ap:distanceSquared(bp) < 3^2 then
        return true
      end
    end
  end
  return false
end

---@class CachingCurve : ClassPool
---@field curve TurnBaseTrajectory
---@field compatibleTable CacheTable
local CachingCurve = class('CachingCurve', class.Pool)

---@param from vec3
---@param fromDir vec3
---@param to vec3
---@param toDir vec3
---@param dynamic boolean
---@param trajectoryParams SerializedTrajectoryAttributes
---@return CachingCurve
function CachingCurve:initialize(from, fromDir, to, toDir, dynamic, trajectoryParams)
  self.curve = TurnTrajectory(from, fromDir, to, toDir, trajectoryParams)
  if self.compatibleTable == nil and not dynamic then self.compatibleTable = CacheTable() end
end

function CachingCurve:recycle()
  class.recycle(self.curve)
  if self.compatibleTable then self.compatibleTable:clear() end
end

---@param curve1 CachingCurve
---@param curve2 CachingCurve
local function compatibleTableFactory(curve1, curve2)
  return _curvesIntersect(curve1.curve, curve2.curve)
end

---@param cCurve CachingCurve
---@return boolean
function CachingCurve:intersects(cCurve)
  -- return curvesIntersect(self.curve, cCurve.curve)

  if not self.compatibleTable or not cCurve.compatibleTable then return _curvesIntersect(self.curve, cCurve.curve) end
  return self.compatibleTable:get(cCurve, compatibleTableFactory, self, cCurve)

  -- ac.perfFrameBegin(1)
  -- local r
  -- if not self.compatibleTable or not cCurve.compatibleTable then r = _curvesIntersect(self.curve, cCurve.curve) 
  -- else r = self.compatibleTable:get(cCurve, compatibleTableFactory, self, cCurve) end
  -- ac.perfFrameEnd(1)
  -- return r
end

---@param cCurve CachingCurve
function CachingCurve:intersectsAfter(cCurve, offsetSelf, offsetOther)
  return _curvesIntersectAfter(self.curve, cCurve.curve, offsetSelf / self.curve.length, offsetOther / cCurve.curve.length)
end

return class.emmy(CachingCurve, CachingCurve.initialize)
