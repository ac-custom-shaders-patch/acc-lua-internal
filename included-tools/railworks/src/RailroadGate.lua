local DEBUG_COLLIDERS = false   -- If `true`, shows outline for train colliders
local PHYSICS_MASS = 1          -- Physics mass in kg
local ANIMATION_LAG = 0.95      -- Physics mass in kg

local trackRootRef

---@return ac.SceneReference
local function getTrackRootRef()
  if not trackRootRef then
    trackRootRef = ac.findNodes('trackRoot:yes')
  end
  return trackRootRef
end

---@alias RailroadGateEntry {element: ac.SceneReference, transformationBase: mat4x4, angle: number, rigidBody: physics.RigidBody?, offset: mat4x4, offsetInv: mat4x4}

---@class RailroadGate
---@field description GateDescription
---@field lines {[1]: number, [2]: RailroadSchedule}[]
---@field entries RailroadGateEntry[]
---@field physicsEntries RailroadGateEntry[]
---@field models ac.SceneReference[]
---@field closed number
---@field age number
local RailroadGate = class 'RailroadGate'

local rotationAxis = vec3(-1, 0, 0)

---@param entry RailroadGateEntry
---@param closed number
local function setGateRotation(entry, closed)
  if not entry.rigidBody or entry.rigidBody:isSemiDynamic() then
    entry.element:getTransformationRaw():set(mat4x4.rotation((1 - closed) * entry.angle, rotationAxis):mulSelf(entry.transformationBase))
    if entry.rigidBody then
      entry.rigidBody:setTransformationFrom(entry.element, entry.offset)
    end
  elseif entry.rigidBody:isEnabled() then
    entry.element:setTransformationFrom(entry.rigidBody, entry.offsetInv)
  end
end

---@param description GateDescription
---@param lines {[1]: number, [2]: RailroadSchedule}[]
---@return RailroadGate
function RailroadGate.allocate(description, lines)
  local kn5s = {}
  local entries = {}
  local physicsEntries = {}

  for i = 1, #description.models do
    local d = description.models[i]
    getTrackRootRef():loadKN5Async(d.model, function (err, kn5)
      if err then
        return ac.error(err)
      end

      table.insert(kn5s, kn5)
      kn5:setPosition(d.position)
      kn5:setOrientation(d.direction, d.up)
  
      for _, element in ipairs(kn5:findNodes('GATE_?')) do  
        local name = element:name()
        local transformationBase = element:getTransformationRaw():clone()
        local entry = {
          element = element,
          transformationBase = transformationBase,
          angle = math.rad(tonumber(name:match('_ANG:(%d+)') or 0))
        }
        table.insert(entries, entry)

        if d.physics then
          local paramRB = name:match('_RB:([A-Z]+)')
          local paramRK = name:match('_RK:([A-Z]+)')
          if paramRB and paramRK then error('An element can either have a RB or RK parameter') end

          local colliderType = paramRB or paramRK
          local useKinematicBody = paramRK ~= nil
          if colliderType then
            local collider
            local min, max = element:getChildren():getLocalAABB()

            if colliderType == 'BOX' then
              collider = physics.Collider.Box(max - min, vec3(), nil, nil, DEBUG_COLLIDERS)
            elseif colliderType == 'CAPSULE' then
              collider = physics.Collider.Capsule(max.z - min.z, max.x - min.x, vec3(), nil, DEBUG_COLLIDERS)
            elseif colliderType == 'CYLINDER' then
              collider = physics.Collider.Cylinder(max.z - min.z, max.x - min.x, vec3(), nil, DEBUG_COLLIDERS)
            else
              ac.error('Uknown collider type: '..colliderType)
            end
      
            if collider then
              try(function ()
                entry.rigidBody = physics.RigidBody(collider, PHYSICS_MASS, vec3())
                entry.rigidBody:setSemiDynamic(true, not useKinematicBody)
                local center = (min + max):scale(0.5)
                entry.offset = mat4x4.translation(center)
                entry.offsetInv = mat4x4.translation(center:scale(-1))
                table.insert(physicsEntries, entry)
              end, function (err)
                ac.warn('Failed to create gate collider: '..err)
              end)
            end
          end
        end
      end
    end)
  end

  return {
    description = description,
    lines = lines,
    entries = entries,
    physicsEntries = physicsEntries,
    models = kn5s,
    closed = -1,
    age = 0,
    keepAlive = false,
  }
end

function RailroadGate:update(dt)
  if #self.entries == 0 then
    return
  end

  local needsClosing = false
  for i = 1, #self.lines do
    local line = self.lines[i]
    if line[2]:isPointBusy(line[1], self.description.colliding) then
      needsClosing = true
    end
  end

  local veryNew = self.age < 1
  if veryNew then
    self.age = self.age + dt
  end

  local newClosed = math.applyLag(self.closed, needsClosing and 1 or 0, veryNew and 0 or ANIMATION_LAG, dt)
  local movedABit = math.abs(self.closed - newClosed) > 0.0001
  if self.keepAlive or movedABit then
    local entries = movedABit and self.entries or self.physicsEntries
    for i = 1, #entries do
      setGateRotation(entries[i], newClosed)
    end
    self.closed = newClosed
  else
    for i = 1, #self.physicsEntries do
      if not self.physicsEntries[i].rigidBody:isSemiDynamic() then
        self.keepAlive = true
      end
    end
  end
end

function RailroadGate:dispose()
  for i = 1, #self.entries do
    if self.entries[i].rigidBody then
      self.entries[i].rigidBody:dispose()
    end
  end
  for i = 1, #self.models do
    self.models[i]:dispose()
  end
end

return class.emmy(RailroadGate, RailroadGate.allocate)

