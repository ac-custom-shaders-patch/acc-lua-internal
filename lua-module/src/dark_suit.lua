if not Config:get('MISCELLANEOUS', 'DARKEN_DEFAULT_SUIT', false) then return end

local allowed = {
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::HELMET_2012.dds',
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::Helmet_Glass_1975.dds',
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::HELMET_1969_Glass.DDS',
  'content/driver::2016_Suit_DIFF.dds;content/driver::2016_Gloves_DIFF.dds;content/driver::HELMET_1985_Glass.dds',
}

local car = ac.findNodes('carRoot:0')
local suit = car:findSkinnedMeshes('{ material:RT_DriverSuit & isTextureSlotDefault:txDiffuse & driverPiece:yes }')
local gloves = car:findSkinnedMeshes('{ material:RT_Gloves & isTextureSlotDefault:txDiffuse & driverPiece:yes }')
local helmet = car:findMeshes('{ ( material:RT_Helemt, material:RT_Helemt_trasparent, material:RT_1975_Glass, material:CASCO69_VETRO, material:RT_Visiera1 ) & isTextureSlotDefault:txDiffuse & driverPiece:yes }')
if #suit > 0 and #gloves > 0 and #helmet > 0 then
  local suitTex = suit:getTextureSlotFilename(1, 1)
  local glovesTex = gloves:getTextureSlotFilename(1, 1)
  local helmetTex = helmet:getTextureSlotFilename(1, 1)
  local key = table.concat({suitTex, glovesTex, helmetTex}, ';')
  ac.debug('Suit key', key)

  if table.contains(allowed, key) then
    ac.log('Suitable for darkening')
    suit:setMaterialProperty('ksAmbient', 0.03):setMaterialProperty('ksDiffuse', 0.03)
    gloves:setMaterialProperty('ksAmbient', 0.03):setMaterialProperty('ksDiffuse', 0.03)
    helmet:setMaterialProperty('ksAmbient', 0.03):setMaterialProperty('ksDiffuse', 0.03)
  end
end



