local types = {
  locomotiveDoubleSided = {
    name = 'Double-sided locomotive',
    factory = function ()
      return {
        intensity = table.range(4, function () return 3 + 3 * math.random() end),
        lights = table.range(2, function ()
          local light = ac.LightSource(ac.LightType.Regular)
          light.range = 15
          light.spot = 290
          light.diffuseConcentration = 0.85
          light.spotSharpness = 0.5
          light.specularMultiplier = 0
          return light
        end),
        update = function (s, trainObject, doorOffsetLeft, doorOffsetRight, lightIntensity)
          local mat = trainObject.rootNode:getTransformationRaw()
          for i = 1, 2 do
            local light = s.lights[i]
            local i1 = 6 * lightIntensity
            light.color:setScaled(trainObject.description.tint, i1)
            mat:transformPointTo(light.position, vec3(0, 2.5, i == 1 and trainObject.distanceFront - 1 or -trainObject.distanceRear + 1))
            mat:transformVectorTo(light.direction, vec3(0, 1, i == 1 and 0.7 or -0.7))
          end
        end
      }
    end
  },
  passenger = { 
    name = 'Passenger cart',
    factory = function ()
      return {
        intensity = table.range(4, function () return 3 + 3 * math.random() end),
        lights = table.range(2, function ()
          local light = ac.LightSource(ac.LightType.Line)
          light.range = 10
          light.spot = 190
          light.diffuseConcentration = 0.5
          light.spotSharpness = 0.5
          light.specularMultiplier = 0
          return light
        end),
        update = function (s, trainObject, doorOffsetLeft, doorOffsetRight, lightIntensity)
          local mat = trainObject.rootNode:getTransformationRaw()
          for i = 1, 2 do
            local light = s.lights[i]
            local insertRight = 4 - 2 * (i == 1 and doorOffsetLeft or doorOffsetRight)
            local side = i == 1 and trainObject.sideLeft or -trainObject.sideRight
            local i1, i2 = s.intensity[i * 2 - 1] * lightIntensity, s.intensity[i * 2] * lightIntensity
            light.color:setScaled(trainObject.description.tint, i1)
            light.lineColor:setScaled(trainObject.description.tint, i2)
            mat:transformPointTo(light.position, vec3(side, 3, trainObject.distanceFront - insertRight))
            mat:transformPointTo(light.linePos, vec3(side, 3, -trainObject.distanceRear + insertRight))
            mat:transformVectorTo(light.direction, vec3(i == 1 and 1 or -1, 0, 0))
          end
        end
      }
    end
  },
}

---@class RailroadSurroundLight
---@field lights ac.LightSource[]
local RailroadSurroundLight = class 'RailroadSurroundLight'

---@param description TrainCartDescription
---@return RailroadSurroundLight
function RailroadSurroundLight.allocate(description)
  return types[description.surroundLight] and types[description.surroundLight].factory() or {}
end

function RailroadSurroundLight.known()
  return types
end

---@param trainObject RailroadTrainObject
---@param doorOffsetLeft number
---@param doorOffsetRight number
---@param lightIntensity number
function RailroadSurroundLight:update(trainObject, doorOffsetLeft, doorOffsetRight, lightIntensity) end

function RailroadSurroundLight:dispose()
  if not self.lights then return end
  for i = 1, #self.lights do
    self.lights[i]:dispose()
  end
end

return class.emmy(RailroadSurroundLight, RailroadSurroundLight.allocate)