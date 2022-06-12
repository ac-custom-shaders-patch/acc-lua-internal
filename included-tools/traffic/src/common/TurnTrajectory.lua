local BezierCurveNormalized = require('BezierCurveNormalized')

---@class TurnBaseTrajectory
local TurnBaseTrajectory = class('TurnBaseTrajectory', class.Pool)
function TurnBaseTrajectory:initialize(from, fromDir, to, toDir, params)
  local bezier = BezierCurveNormalized(from, fromDir, to, toDir, params.cb or 0.5, params.ce or 0.5)
  local len = bezier:length()
  self._b = bezier
  self._lengthInv = 1 / len
  self.length = len
  self.fromDir = fromDir
  self.toDir = toDir
end
function TurnBaseTrajectory:__len()
  return self.length
end
function TurnBaseTrajectory:get(transition)
  local v = vec3()
  self:getInto(v, transition)
  return v
end
function TurnBaseTrajectory:getInto(v, transition, estimate)
  return self._b:getInto(v, math.saturateN(transition * self._lengthInv))
end
function TurnBaseTrajectory:getPointRef(transition)
  return self._b:getPointRef(transition * self._lengthInv)
end
function TurnBaseTrajectory:recycled()
  class.recycle(self._b)
  self._b = nil
end

---@class TurnUTurnTrajectory : TurnBaseTrajectory
local TurnUTurnTrajectory = class('TurnUTurnTrajectory', TurnBaseTrajectory, class.Pool)
function TurnUTurnTrajectory:initialize(from, fromDir, to, toDir, params)
  local halfwayDistance = to:distance(from)
  local halfwayDir = (to - from):scale(1 / halfwayDistance)
  local uTurnSize = params.ul and params.ul * halfwayDistance or (halfwayDistance < 5 and 5 or math.min(4, 0.7 * halfwayDistance))
  local halfway = (to + from):scale(0.5):add((fromDir - toDir):scale(uTurnSize))
  local b0 = BezierCurveNormalized(from, fromDir, halfway, halfwayDir, params.cb or 0.5, 0.5)
  local b1 = BezierCurveNormalized(halfway, halfwayDir, to, toDir, 0.5, params.ce or 0.5)
  local b0len = b0:length()
  local b1len = b1:length()
  self._b0 = b0
  self._b1 = b1
  self._b0len = b0len
  self._b0lenInv = 1 / b0len
  self._b1lenInv = 1 / b1len
  self.length = b0len + b1len
  self.fromDir = fromDir
  self.toDir = toDir
end
function TurnUTurnTrajectory:getInto(v, transition, estimate)
  if transition < self._b0len then
    return self._b0:getInto(v, math.saturateN(transition * self._b0lenInv))
  end
  return self._b1:getInto(v, math.saturateN((transition - self._b0len) * self._b1lenInv))
end
function TurnUTurnTrajectory:getPointRef(transition)
  if transition < self._b0len then
    return self._b0:getPointRef(transition * self._b0lenInv)
  end
  return self._b1:getPointRef((transition - self._b0len) * self._b1lenInv)
end
function TurnUTurnTrajectory:recycled()
  class.recycle(self._b0)
  class.recycle(self._b1)
  self._b0, self._b1 = nil, nil
end

local _paramsNone = {}

---@param from vec3
---@param to vec3
---@param fromDir vec3
---@param toDir vec3
---@param params table
---@return TurnBaseTrajectory
local function TurnTrajectory(from, fromDir, to, toDir, params)
  if not from then error('from == nil') end
  if not fromDir then error('fromDir == nil') end
  if not to then error('to == nil') end
  if not toDir then error('toDir == nil') end

  params = params or _paramsNone

  if fromDir:dot(toDir) < -0.8 then
    return TurnUTurnTrajectory(from, fromDir, to, toDir, params)
  end

  return TurnBaseTrajectory(from, fromDir, to, toDir, params)
end

return TurnTrajectory