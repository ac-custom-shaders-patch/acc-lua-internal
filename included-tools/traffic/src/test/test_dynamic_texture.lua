return function ()
  if math.random() > 0.95 then
    ac.findMeshes('7WALL'):setMaterialTexture('txDiffuse', {
      callback = function (dt)
        display.rect({ pos = vec2(), size = vec2(200 + 200 * math.random(), 200), color = rgbm.colors.white })
      end,
      textureSize = vec2(512, 512),
      region = {
        from = vec2(0, 0),
        size = vec2(512, 512)
      },
      background = nil
    })
  end
end