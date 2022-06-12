-- Unlike BezierCurve, this one can produce linear motion from start to finish by building
-- actual curve beforehand and resampling it in time

local BezierCurve = require('BezierCurve')
local Array = require('Array')

local samples = 30

---@class BezierCurveNormalized
local BezierCurveNormalized = class('BezierCurveNormalized', class.Pool)

local _curve = BezierCurve(vec3(), vec3(), vec3(), vec3())
local _points = Array.range(samples + 1, function() return { pos = vec3(), length = 0 } end)
local _fnFindPoint = function (v, _, j) return j < v.length end

---Copies values of vectors to its own points, so feel free to pass references.
---@param posFrom vec3 @Could be a reference.
---@param dirFrom vec3 @Could be a reference.
---@param posTo vec3 @Could be a reference.
---@param dirTo vec3 @Could be a reference.
---@param lenFrom number
---@param lenTo number
---@return BezierCurveNormalized
function BezierCurveNormalized:initialize(posFrom, dirFrom, posTo, dirTo, lenFrom, lenTo)
  if math.isNaN(dirFrom.x) then error('NaN in dirFrom') end
  if math.isNaN(posTo.x) then error('NaN in posTo') end

  local curve = _curve
  _curve:set(posFrom, dirFrom, posTo, dirTo, lenFrom, lenTo)

  local points = _points
  points[1].pos:set(posFrom)
  local prevPoint = posFrom
  local totalLength = 0
  for i = 1, samples - 1 do
    local newPoint = points[i + 1].pos
    curve:getInto(newPoint, i / samples)
    totalLength = totalLength + newPoint:distance(prevPoint)
    points[i + 1].length = totalLength
    prevPoint = newPoint
  end
  totalLength = totalLength + posTo:distance(prevPoint)
  points[samples + 1].pos:set(posTo)
  points[samples + 1].length = totalLength

  local resampled = self._points
  if resampled == nil then
    resampled = { vec3():set(posFrom) }
    self._points = resampled
  else
    resampled[1]:set(posFrom)
  end

  for i = 1, samples - 1 do
    local j = totalLength * i / samples
    local x = points:findLeftOfIndex(_fnFindPoint, j)

    local p1 = points[x]
    local p2 = points[x + 1]
    if p1 == nil or p2 == nil then 
      ac.debug('Broken bezier: posFrom', posFrom)
      ac.debug('Broken bezier: dirFrom', dirFrom)
      ac.debug('Broken bezier: posTo', posTo)
      ac.debug('Broken bezier: dirTo', dirTo)
      ac.debug('Broken bezier: lenFrom', lenFrom)
      ac.debug('Broken bezier: lenTo', lenTo)
      error(string.format('Unexpected: x=%d', x))
    end
    local mix = math.lerpInvSat(j, p1.length, p2.length)
    local d = resampled[i + 1]
    if d == nil then
      d = vec3()
      resampled[i + 1] = d
    end
    d:setLerp(p1.pos, p2.pos, mix)
  end

  local d = resampled[samples + 1]
  if d == nil then
    d = vec3()
    resampled[samples + 1] = d
  end
  d:set(posTo)

  self._length = totalLength
end

function BezierCurveNormalized:get(t)
  local v = vec3()
  self:getInto(v, t)
  return v
end

function BezierCurveNormalized:startPosition()
  return self._points[1]
end

function BezierCurveNormalized:endPosition()
  return self._points[samples]
end

local _mfloor = math.floor
local _mceil = math.ceil

---@param v vec3
---@param t number
function BezierCurveNormalized:getInto(v, t)
  local i = t * samples + 1
  local j = _mfloor(i)
  local p = self._points
  local p1 = p[j]
  local p2 = p[j + 1] or p1
  return v:setLerp(p1, p2, i - j)
end

---@param t integer
---@return vec3 @Returns a reference, so do not change it.
function BezierCurveNormalized:getPointRef(t)
  return self._points[_mceil(t * samples)]
end

function BezierCurveNormalized:length()
  return self._length
end

return class.emmy(BezierCurveNormalized, BezierCurveNormalized.initialize)