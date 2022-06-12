-- Very simple license plate generator. Could be done better, but that should do for now

local alphabet = { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' }

local function rndLetter()
  return table.random(alphabet)
end

---@class LicensePlateGenerator
local LicensePlateGenerator = class('LicensePlateGenerator')

---@return LicensePlateGenerator
function LicensePlateGenerator.allocate()
  return {}
end

---@param meshes ac.SceneReference @License plate meshes.
function LicensePlateGenerator:generate(meshes)
  meshes:ensureUniqueMaterials() -- gotta make sure materials are unique

  local text = string.format('%s%s %03d %s%s', rndLetter(), rndLetter(), math.random(999), rndLetter(), rndLetter())

  -- local font = 'ks_ruf12r'
  -- local textSpacing = -10
  -- local textYOffset = -10
  -- local letterSize = vec2(50, 120)

  local region = {
    from = vec2(75, 18),
    size = vec2(360, 90)
  }

  local function drawLicensePlate(offsetX, offsetY, color)
    -- this function actually draws contents of a license plate
    -- this way it’s a simple trick to generate somewhat acceptable normal map as well

    -- display.text{
    --   letter = letterSize,
    --   pos = vec2(offsetX or 0, (offsetY or 0) + textYOffset),
    --   text = text,
    --   font = font,
    --   color = color or rgbm(0.1, 0.1, 0.1, 1),
    --   alignment = 0.5,
    --   spacing = textSpacing,
    --   width = region.size.x
    -- }

    ui.pushDWriteFont('License Plate:./data;Weight=Black')
    ui.setCursor(vec2(offsetX or 0, (offsetY or 0) + 6))
    ui.dwriteTextAligned(text, 86, ui.Alignment.Center, ui.Alignment.Center, region.size, false, color or rgbm(0.1, 0.1, 0.1, 1))
    ui.popDWriteFont()
  end

  meshes:setMaterialTexture('txDiffuse', {
    textureSize = vec2(512, 128),
    background = rgbm.colors.white,
    region = region,
    callback = function (dt)
      -- draw license plate once for color
      drawLicensePlate()
    end
  })

  meshes:setMaterialTexture('txNormal', {
    textureSize = vec2(512, 128),
    background = rgbm(0.5, 0.5, 1, 1),
    region = region,
    callback = function (dt)
      -- draw it a few times with different colors to get some sort of normal map
      local o = 2
      drawLicensePlate(o + 1, 0, rgbm(0, 0.5, 1, 1))
      drawLicensePlate(-o - 1, 0, rgbm(1, 0.5, 1, 1))
      drawLicensePlate(0, o, rgbm(0.5, 0, 1, 1))
      drawLicensePlate(0, -o, rgbm(0.5, 1, 1, 1))
      drawLicensePlate(0, 0, rgbm(0.5, 0.5, 1, 1))
    end
  })

end

return class.emmy(LicensePlateGenerator, LicensePlateGenerator.allocate)
