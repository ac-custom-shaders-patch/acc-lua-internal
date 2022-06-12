-- Tags for marking drivable distance
---@alias DistanceTag {name:string}

---@type table<string, DistanceTag>
local DistanceTags = {
  ErrorCursorless = {name = 'error: cursorless'},
  ErrorNoCar = {name = 'error: no car yet'},
  LaneCarInFront = {name = 'lane: car in front'},
  LaneEmpty = {name = 'lane: empty'},
  LaneCursorEmpty = {name = 'lane cursor: empty'},
  LaneCursorLoopAround = {name = 'lane cursor: loop around'},
  Blocking = {name = 'lane: blocking'},
  IntersectionDistanceTo = {name = 'intersection: distance to intersection'},
  IntersectionActive = {name = 'intersection: active'},
  IntersectionWaitingOnSecondaryRoute = {name = 'intersection: waiting on secondary'},
  IntersectionCarInFront = {name = 'intersection: car in front'},
  IntersectionMergingCarInFront = {name = 'intersection: merging car in front'},
  IntersectionDrivingStraightWithPriority = {name = 'intersection: driving straight with priority'},
  LaneChangeBase = {name = 'lane change: base'},
  LaneCursorCarInFront = {name = 'lane change: car in front'},
  LaneChangeBlocking = {name = 'lane change: blocking'},
}

return DistanceTags
