local startKey = worker.input
local workerData = ac.connect({
  key = ac.StructItem.key('CspDebug.CarDebugWorker'),
  instanceKey = ac.StructItem.int32(),
  downforce = ac.StructItem.float(),
  activeDragLines = ac.StructItem.int32(),
  dragLines = ac.StructItem.array(ac.StructItem.struct({
    posL = ac.StructItem.vec3(),
    targetW = ac.StructItem.vec3(),
    wheel = ac.StructItem.int32(),
    force = ac.StructItem.float()
  }), 64)
})

local vecZero = vec3()
local vecDownforce = vec3()
local posW = vec3()
local deltaW = vec3()
local finalForceL = vec3()
local wheelCross0 = vec3()
local wheelCross1 = vec3()

function script.update(dt)
  if startKey ~= workerData.instanceKey then
    worker.terminate()
  else
    if workerData.downforce ~= 0 then
      vecDownforce.y = workerData.downforce
      physics.addForce(0, vecZero, true, vecDownforce, false)
    end

    for i = 0, workerData.activeDragLines - 1 do
      local link = workerData.dragLines[i]
      local transform = physics.getBodyTransform(0, link.wheel)
      transform:transformPointTo(posW, link.posL)
      deltaW:set(link.targetW):sub(posW)
      local speed = math.dot(deltaW, physics.getPointVelocity(0, posW, false)) / deltaW:length()
      speed = speed / (5 + math.abs(speed))    
      deltaW:scale((link.force * (1 - speed)) * (dt * 50))
      physics.addForce(0, posW, false, deltaW, false, link.wheel)
    
      if link.wheel ~= -1 then
        physics.getBodyTransform(0, link.wheel, true):transformVectorTo(finalForceL, deltaW)
        wheelCross0.y, wheelCross0.z = link.posL.y, link.posL.z
        local dir = wheelCross0:cross(finalForceL, wheelCross1).x
        physics.addWheelTorque(0, link.wheel, 0.1 * dir)
      end
    end
  end
end

