---@alias LaneID integer
---@alias SerializedVec3 {[1]: number, [2]: number, [3]: number}

---@class SerializedTrajectoryAttributes
---@field cb number @Curve beginning parameter.
---@field ce number @Curve ending parameter.
---@field ul number @U-turn length parameter.
---@field po number @Priority offset.

---@class SerializedTrafficLightEmissiveParams
---@field mode integer @1: emissive, 2: virtual meshes, 3: multi-channel emissive.
---@field roles {mesh: string}[] @For mode #1, item per emissive role
---@field virtual {items: {pos: SerializedVec3, dir: SerializedVec3, radius: number}[]} @For mode #2, item per emissive role, then wraps around
---@field hide {mesh: string} @For mode #2

---@class SerializedTrafficLightParams
---@field duration number

---@class SerializedTrafficLightRef
---@field program string @Name of the program.
---@field params SerializedTrafficLightParams @Program parametres.
---@field emissive SerializedTrafficLightEmissiveParams[] @Emissive parametres per side.

---@class SerializedLaneProperties
---@field allowUTurns boolean
---@field allowLaneChanges boolean

---@class SerializedLane
---@field name string
---@field id integer
---@field loop boolean
---@field aabb {[1]: SerializedVec3, [2]: SerializedVec3}
---@field role integer @3 for default role, lower for lower priority.
---@field priority integer
---@field priorityOffset number
---@field speedLimit number
---@field points SerializedVec3[]
---@field params SerializedLaneProperties

---@class SerializedIntersection
---@field name string
---@field id integer
---@field points SerializedVec3[]
---@field disallowedTrajectories {[1]: LaneID, [2]: LaneID}[]
---@field trajectoryAttributes {[1]: LaneID, [2]: LaneID, [3]: SerializedTrajectoryAttributes}[]
---@field entryOffsets {lane: LaneID, offsets: {[1]: number, [2]: number}}[]
---@field entryPriorityOffsets {lane: LaneID, offset: integer}[]
---@field trafficLight SerializedTrafficLightRef

---@class SerializedAreaParams : SerializedLaneProperties
---@field role integer @0 if inactive.
---@field customSpeedLimit boolean @Is custom speed limit active.
---@field speedLimit number @Speed limit.
---@field spreadMult number
---@field priority number|nil

---@class SerializedArea
---@field name string
---@field id integer
---@field shapes SerializedVec3[][]
---@field params SerializedAreaParams

---@class SerializedLaneRole
---@field name string
---@field priority number
---@field speedLimit number

---@class SerializedRules
---@field laneRoles SerializedLaneRole[]

---@class SerializedData
---@field lanes SerializedLane[]
---@field intersections SerializedIntersection[]
---@field areas SerializedArea[]
---@field rules SerializedRules