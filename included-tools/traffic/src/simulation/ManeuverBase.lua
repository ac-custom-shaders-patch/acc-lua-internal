---@class ManeuverBase : ClassBase
local ManeuverBase = class('ManeuverBase')

ManeuverBase.ManeuverNone = 0
ManeuverBase.ManeuverRegular = 1
ManeuverBase.ManeuverTight = 2

function ManeuverBase:detach() error('Not implemented') end

---@param speedKmh number
---@param dt number
---@return boolean
function ManeuverBase:advance(speedKmh, dt) error('Not implemented') end

---@return number
function ManeuverBase:distanceToNextCar() error('Not implemented') end

function ManeuverBase:ensureActive() error('Not implemented') end

---@param v vec3
---@param estimate boolean
---@return vec3|nil @Vector if position is calculated here and LaneCursor does not need to be used
function ManeuverBase:calculateCurrentPosInto(v, estimate) error('Not implemented') end

---@return boolean
function ManeuverBase:shouldDetachFromLane() return false end

---@return boolean
function ManeuverBase:handlesDistanceToNext() return false end

---@return boolean
function ManeuverBase:handlesDistanceToBlocking() return false end

---@return boolean
function ManeuverBase:getManeuverType() return ManeuverBase.ManeuverNone end

return ManeuverBase