local MathUtils = require('MathUtils')

---@class CarBase : ClassBase
local CarBase = class('CarBase')

---@param transformRef mat4x4
---@param halfLength number
---@param halfWidth number
function CarBase:initialize(transformRef, halfLength, halfWidth)
  self._transform = transformRef
  self._halfLength = halfLength
  self._halfWidth = halfWidth
end

---@return vec3
function CarBase:getDirRef()
  return self._transform.look
end

---@return vec3
function CarBase:getPosRef()
  return self._transform.position
end

---@return number
function CarBase:getSpeedKmh()
  error('Not implemented')
end

---@return number
function CarBase:getDistanceToNext()
  error('Not implemented')
end

---@param point vec3
---@return number
function CarBase:distanceBetweenCarAndPoint(point)
  local t = self._transform
  return MathUtils.distanceBetweenCarAndPoint(t.position, t.look, self._halfLength, self._halfWidth, point)
end

local _mabs = math.abs
local _msqrt = math.sqrt
local _msaturate = math.saturateN

---@param otherCar CarBase
---@param futureDirHint vec3
---@return number
function CarBase:freeDistanceTo(otherCar, futureDirHint)
  -- oh = half dimensions of other car
  local ohX, ohY = otherCar._halfWidth, otherCar._halfLength

  -- op = position of other car
  local _op = otherCar._transform.position
  local opX, opY = _op.x, _op.z

  -- mp = center of own car relative to other car
  local _mp = self._transform.position
  local mpX, mpY = _mp.x - opX, _mp.z - opY

  -- md = direction of own car
  local _md = futureDirHint or self._transform.look
  local mdX, mdY = _md.x, _md.z

  -- od = direction of other car
  local _od = otherCar._transform.look
  local odX, odY = _od.x, _od.z
  local osX, osY = -odY, odX

  -- if other car is behind or this car is driving away, early exit
  if (mpX * osX + mpY * osY > 0) == (mdX * osX + mdY * osY > 0) and (mpX * osX + mpY * osY > ohY) then
    return 100
  end

  -- ms = side vector of own car
  local msX, msY = mdY, -mdX

  -- mp → shift to front edge
  local dmf = self._halfLength
  mpX, mpY = mpX + mdX * dmf, mpY + mdY * dmf

  -- ac.debug('mpX * osX + mpY * osY', mpX * osX + mpY * osY)
  -- ac.debug('mdX * osX + mdY * osY', mdX * osX + mdY * osY)
  -- DebugShapes.op = vec3(opX, -1079, opY)
  -- DebugShapes['op+mp'] = vec3(opX + mpX, -1079, opY + mpY)

  -- mp → shift to a corner of own car that is nearest to other car
  local shw = self._halfWidth
  -- local mfX, mfY = mpX + mdX, mpY + mdY
  -- if mpX * msX + mpY * msY > 0 then shw = -shw end
  -- if mdX * odX + mdY * odY < 0 then shw = -shw end
  -- mpX, mpY = mpX + msX * shw, mpY + msY * shw

  -- either left or right front corner to measure
  local mpX1, mpY1 = mpX + msX * shw, mpY + msY * shw
  local mpX2, mpY2 = mpX + msX * -shw, mpY + msY * -shw

  -- couldn’t figure out a good way to determine which corner to take (attempts ↑), so here is a simple SDF approach
  local ohD = ohX - ohY
  local ax, ay = odX * -ohD, odY * -ohD
  local bax, bay = odX * ohD * 2, odY * ohD * 2
  local pax1, pay1 = mpX1 - ax, mpY1 - ay
  local pax2, pay2 = mpX2 - ax, mpY2 - ay
  local badi = 1 / (bax * bax + bay * bay)
  local h1 = _msaturate((pax1 * bax + pay1 * bay) * badi)
  local h2 = _msaturate((pax2 * bax + pay2 * bay) * badi)
  local rx1, ry1 = pax1 - bax * h1, pay1 - bay * h1
  local rx2, ry2 = pax2 - bax * h2, pay2 - bay * h2
  if rx1 * rx1 + ry1 * ry1 < rx2 * rx2 + ry2 * ry2 then
    mpX, mpY = mpX1, mpY1
  else
    mpX, mpY = mpX2, mpY2
  end

  -- DebugShapes['op+fmp'] = vec3(opX + mpX, -1079, opY + mpY)

  -- if other car is behing this car, even just by a bit, keep moving
  local sameDir = mdX * odX + mdY * odY > 0
  local oY = sameDir and ohY or -ohY
  local ofX, ofY = opX + odX * oY, opY + odY * oY
  local mfX, mfY = opX + mpX - ofX, opY + mpY - ofY
  -- DebugShapes.of = vec3(ofX, -1079, ofY)
  local dotMfOd = mfX * odX + mfY * odY
  if (sameDir and dotMfOd or -dotMfOd) > 0 then
    return 50
  end

  -- if cars are parallel, simply measure distance between them for early exit if there is enough space
  local movingAlong = _mabs(mdX * odX + mdY * odY)
  if movingAlong > 0.997 then
    local dw = _mabs(msX * mpX + msY * mpY)
    if dw > ohX + 0.3 then return 10 end
  end

  -- if other is stationary, check if we could follow forwards and drive around it
  local drivingAway = mpX * odX + mpY * odY < 0
  if drivingAway or otherCar:getSpeedKmh() < 1 then
    -- takes into account whole rect shape of a car, so works with any angle
    local sd = _mabs(mpX * msX + mpY * msY) - ohX * _mabs(osX * msX + osY * msY) - ohY * _mabs(odX * msX + odY * msY)
    if sd > 0.1 then
      return drivingAway and 30 or 5
    end
  end

  mpX, mpY = mpX + odX * ohD, mpY + odY * ohD

  local dx, dy = odX * ohD * 2, odY * ohD * 2
  local h = _msaturate((mpX * dx + mpY * dy) / (dx * dx + dy * dy))
  local rx, ry = mpX - dx * h, mpY - dy * h
  return _msqrt(rx * rx + ry * ry) - ohX
end

return CarBase