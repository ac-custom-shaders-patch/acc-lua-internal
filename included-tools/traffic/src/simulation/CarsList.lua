local function loadColorsList(filename)
  local colors = {}
  for line in io.lines(filename) do
    table.insert(colors, rgbm.new(line))
  end
  return function () return table.random(colors) end
end

local TrafficConfig = require('TrafficConfig')
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
--- @field maxSpeed number
--- @field dynamic number
--- @field chance number
--- @field color fun(): rgbm
--- @field lights CarDefinitionLights
--- @field dimensions CarDefinitionDimensions
--- @field physics CarDefinitionPhysics
--- @field cache any

local massMult = TrafficConfig.carnageMode and 0.001 or 1
local speedMultiplier = TrafficConfig.speedMultiplier or 1

--- @type CarDefinition[]
local cars = {}

---@param id string
---@return number
local function guessChance(id)
  id = id:lower():match('^[%w_]+')
  if id:find('bus') or id:find('amg') or id:find('alf') then return 0.3 end
  if id:find('fer') then return 0.2 end
  if id:find('transit') or id:find('mer') or id:find('bmw') then return 0.5 end
  return 1
end

local function rescanCars()
  local dataDir = 'extension/lua/tools/csp-traffic-tool/data'
  for _, v in ipairs(io.scanDir(dataDir, '*.json')) do
    local item = JSON.parse(io.load('%s/%s' % {dataDir, v}))
    item.main = '%s/%s' % {dataDir, item.main}
    item.lod = '%s/%s' % {dataDir, item.lod}
    item.collider = '%s/%s' % {dataDir, item.collider}
    if io.fileExists(item.main) and io.fileExists(item.lod) and io.fileExists(item.collider) then
      item.color = item.color == 'modern' and colorRandom or colorBland
      item.cache = {}
      item.dynamic = item.dynamic or 0.8
      item.maxSpeed = item.maxSpeed or 120
      item.chance = item.chance or guessChance(v)
      item.lights = table.assign({
        headlights = {},
        rear = {},
        brakes = {},
      }, item.lights)
      item.dimensions = table.assign({
        front = 0.5, 
        rear = 4, 
        turningOffset = 2.3, 
        width = 1.6,
        wheelRadius = 0.33,
        fakeShadowX = 0.8 + 0.35,
        fakeShadowZ = 2.25 + 0.15,
      }, item.dimensions)
      item.physics = table.assign({
        mass = 1500,
        width = 1.5,
        length = 3,
        wheelsGripForce = 7,
        suspensionTravel = 0.05,
        suspensionForce = 30,
        suspensionDamping = 15
      }, item.physics)
      item.physics.mass = item.physics.mass * massMult
      item.maxSpeed = item.maxSpeed * speedMultiplier
      cars[#cars + 1] = item
    end
  end
end

rescanCars()
ac.onSharedEvent('tools.TrafficTool.rescanCars', rescanCars)

return cars
