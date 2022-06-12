local function loadColorsList(filename)
  local colors = {}
  for line in io.lines(filename) do
    table.insert(colors, rgbm.new(line))
  end
  return function () return table.random(colors) end
end

local colorRandom = loadColorsList('extension/config/data_oem_colors_modern.txt')
local colorBland = loadColorsList('extension/config/data_oem_colors_vintage.txt')

--- @class CarDefinitionLights
--- @field headlights string[]
--- @field rear string[]
--- @field rearCombined string[]
--- @field brakes string[]

--- @class CarDefinitionDimensions
--- @field front number
--- @field rear number
--- @field turningOffset number
--- @field width number
--- @field wheelRadius number
--- @field fakeShadowX number
--- @field fakeShadowZ number

--- @class CarDefinitionPhysics
--- @field mass number
--- @field width number
--- @field length number
--- @field wheelsGripForce number
--- @field suspensionTravel number
--- @field suspensionForce number
--- @field suspensionDamping number
--- @field cog vec3|nil

--- @class CarDefinition
--- @field main string
--- @field lod string
--- @field collider string
--- @field dynamic number
--- @field color fun(): rgbm
--- @field lights CarDefinitionLights
--- @field dimensions CarDefinitionDimensions
--- @field physics CarDefinitionPhysics
--- @field cache any

local massMult = 1 -- set to 0.001 to have some fun with it, Driver ́’99 style (https://www.youtube.com/watch?v=DiN6OkklU1s)

--- @type CarDefinition[]
local cars = {

  {
    main = 'data/bmw_1m.kn5',
    lod = 'data/bmw_1m_lod.kn5',
    collider = 'data/bmw_1m_collider.kn5',
    dynamic = 0.8,
    color = colorRandom,
    lights = {
      headlights = { 'front_light_1', 'front_light_2', 'front_light_1_SUB0' },
      rear = 'rear_light_1',
      brakes = { 'brake_light_1', 'brake_light_2' },
    },
    dimensions = { 
      front = 0.5, 
      rear = 4, 
      turningOffset = 2.3, 
      width = 1.6,
      wheelRadius = 0.33,
      fakeShadowX = 0.8 + 0.35,
      fakeShadowZ = 2.25 + 0.15,
    },
    physics = {
      mass = 1500 * massMult,
      width = 1.5,
      length = 3,
      wheelsGripForce = 7,
      suspensionTravel = 0.05,
      suspensionForce = 30,
      suspensionDamping = 15
    },
    cache = {}
  },

  {
    main = 'data/alfaromeo_giulietta.kn5',
    lod = 'data/alfaromeo_giulietta_lod.kn5',
    collider = 'data/alfaromeo_giulietta_collider.kn5',
    dynamic = 0.4,
    color = colorBland,
    lights = {
      headlights = { 'FRONT_LIGHT1', 'FRONT_LIGHT_LED', --[[ 'polymsh_detached1_SUB4' ]] },
      rearCombined = { 'REAR_LIGHT_1', 'REAR_LIGHT_0' },
      brakes = 'REAR_LIGHT_2',
    },
    dimensions = {
      front = 0.5,
      rear = 4,
      turningOffset = 2.3,
      width = 1.6,
      wheelRadius = 0.33,
      fakeShadowX = 0.8 + 0.35,
      fakeShadowZ = 2.25 + 0.15,
    },
    physics = {
      mass = 1500 * massMult,
      width = 1.5,
      length = 3,
      wheelsGripForce = 10,
      suspensionTravel = 0.1,
      suspensionForce = 30,
      suspensionDamping = 10
    },
    cache = {}
  },

}

return cars
