if not Config:get('MISCELLANEOUS', 'DARKEN_DEFAULT_SUIT', false) then return end

local allowed = {
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::HELMET_1969.dds',
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::Helmet_Glass_1975.dds',
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::HELMET_1985.dds',
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::HELMET_2012.dds',
}

local meshes = ac.findNodes('carRoot:0'):findAny('{ driverPiece:yes & isTextureSlotDefault:txDiffuse }')
local suit = meshes:filterSkinnedMeshes('material:RT_DriverSuit')
local gloves = meshes:filterSkinnedMeshes('material:RT_Gloves')
local helmet = meshes:filterMeshes('texture:`HELMET_(?:1969|1975|1985|2012)\\.dds`')

if #suit > 0 and #gloves > 0 and #helmet > 0 then
  local suitTex = suit:getTextureSlotFilename(1, 1)
  local glovesTex = gloves:getTextureSlotFilename(1, 1)
  local helmetTex = helmet:getTextureSlotFilename(1, 1)
  local key = table.concat({suitTex, glovesTex, helmetTex}, ';')
  local i = table.indexOf(allowed, key)
  ac.log('Suit key', key, i)
  if i then
    ac.log('Suitable for darkening')
    suit:setMaterialTexture('txDiffuse', 'content/texture/driver_suit/sparco/black/2016_Suit_DIFF.dds')
    gloves:setMaterialTexture('txDiffuse', 'content/texture/driver_gloves/ac_road/Black_black/2016_Gloves_DIFF.dds')
    if i == 1 then
      helmet:setMaterialTexture('txDiffuse', 'content/texture/driver_helmet/HELMET_1969/dark/HELMET_1969.dds')
      helmet:setMaterialProperty('ksDiffuse', 0.2):setMaterialProperty('ksAmbient', 0.2)
    elseif i == 2 then
      helmet:setMaterialTexture('txDiffuse', 'content/texture/driver_helmet/HELMET_1975_Black/plain2/HELMET_1975.dds')
    elseif i == 3 then
      helmet:setMaterialTexture('txDiffuse', 'content/texture/driver_helmet/HELMET_1985/Black/HELMET_1985.dds')
    elseif i == 4 then
      helmet:setMaterialTexture('txDiffuse', 'content/texture/driver_helmet/HELMET_BASE_Black/5/HELMET_2012.dds')
    end
  end
end



