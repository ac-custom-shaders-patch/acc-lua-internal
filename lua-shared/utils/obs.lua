--[[
  A helper library for passing textures to OBS Studio. Works if user enabled integration in Small Tweaks settings (also
  needs an OBS plugin made specifically for AC, also available there).

  To use, include with `local obs = require('shared/utils/obs')` and then call `obs.register(obs.Groups.Extra, 'Texture name', …, function (canvas) … end)`.

  Few notes:
  • If you are using a manual update, might be better to not use `obs.register()` straight away, but instead first set `obs.notify()`. 
    There isn’t much overhead in `obs.register()`, but if you’re adding multiple textures it might add up.
  • Content callbacks or texture copying only occurs if OBS is using the texture, so don’t worry about making them a bit 
    on a heavy side.
  • Maximum number of textures available is currently limited by 63 (and a few of them are already used by CSP).
  • If you want to render scene on your own, use `ManualUpdate` flag with manual update in `[SIM_CALLBACKS] UPDATE` function.
    This should help with smoothness and give you an entry point to an appropriate render state.
  • Textures can be added and removed live, but don’t overdo it, there is still a bit of overhead associated with this process.
    So, like, feel free to register your textures only when OBS becomes available, but it’s better to not change the list of
    textures every second.
  • If you already have a dynamic texture used for something else and you want to mirror it to OBS, simply pass it instead of callback
    to `obs.register()` and this glue library will copy its content when required. 
]]

ffi.cdef([[typedef struct {
uint32_t handle;
uint32_t nameKey;
uint16_t width;
uint16_t height;
uint16_t needsData;
uint16_t flags;
char name[48];
} OBSTextureEntry;]])

local obs = {}

obs.Flags = {
  Unavailable = 1,    -- Mark  texture as not available in this session. 
  Opaque = 0,         -- Opaque texture (default flag). 
  Transparent = 2,    -- Semi-transparent texture. 
  SRGB = 4,           -- Texture in SRGB format. 
  Monochrome = 8,     -- Monochrome texture (adds a convertation step). 
  HDR = 16,           -- HDR texture. 
  ManualUpdate = 32,  -- Do not update texture automatically, instead wait for `:update()` call. 
  ApplyCMAA = 64,     -- Apply CMAA antialiasing to the resulting texture. 
  UserSize = 128,     -- Size is specified by user. 
}

obs.Groups = {
  Basic = 'Basic',
  Camera = 'Camera',
  Effects = 'Effects',
  Extra = 'Extra',
  FromOutside = 'Camera', ---@deprecated Use `Camera` instead
  Widgets = 'Widgets',
}

---Set a callback to be called when AC detects running OBS plugin. Perfect place to set extra textures as to not waste time and memory waiting for OBS that might not arrive. If OBS is already launched, callback will be called in the next frame.
---@param callback fun()
function obs.notify(callback)
  if ac.load('$SmallTweaks.OBSTextures.Initialized') == 1 then
    setTimeout(callback)
  else
    ac.onSharedEvent('$SmallTweaks.OBSTextures.Init', callback)
  end
end

---Register a new OBS texture. Could either be a filename (could be something dynamic, like `dynamic::hdr`, a video or a GIF player) or a callback receiving `ui.ExtraCanvas` to update.
---@param group string? @Group name to be added as a prefix. Default ones are listed in `obs.Groups`, please use them if possible. Default value: `'Unknown'`.
---@param name string @Texture name to be shown in OBS Studio. Can’t exceed 47 characters (and that is with group prefix that will be added by supporting code).
---@param flags integer @Flags from `obs.Flags`. Use `bit.bor()` to combine flags together (or just add them up if they are binary).
---@param size vec2|integer|fun(size: vec2)|nil @Texture size. Might be omitted if `content` is a string with known file size (if its size is not available, texture will be marked as not available). For textures with dynamic size you can optionally pass a callback that will be called when size changes.
---@param content string|fun(canvas: ui.ExtraCanvas, size: vec2) @Either a string pointing to a texture or a function receiving `ui.ExtraCanvas` to update.
---@return {update: nil|fun(), dispose: fun()} @Method `:update()` is only available if `obs.Flags.ManualUpdate` has been set!
function obs.register(group, name, flags, size, content)
  if not group then
    group = 'Unknown'
  end
  if #group + #name + 2 >= 47 then
    error('Name is too long', 2)
  end

  if type(content) ~= 'function' then
    local source = content
    content = tostring(content)
    local sourceSize = ui.imageSize(content)
    if sourceSize.x == 0 then
      flags = 1
    end
    if size == nil then
      size = sourceSize
    end
    content = function (s) s:copyFrom(source) end
  elseif bit.band(flags, 128) ~= 0 then
    if type(size) ~= 'function' then
      size = function () end
    end
  elseif size == nil then
    error('Size is optional only if content is a string', 2)
  end

  local fullName = (group or 'Unknown')..': '..name
  local connect = ac.connect(string.format('OBSTextureEntry* item;//%s', fullName))
  connect.item = nil

  local finalSize = bit.band(flags, 1) ~= 0 and vec2()
    or vec2.isvec2(size) and size:clone()
    or type(size) == 'function' and vec2()
    or vec2.new(size)
  ac.broadcastSharedEvent('$SmallTweaks.OBSTextures', {
    group = group,
    name = name,
    size = finalSize,
    flags = flags,
  })

  local canvas, interval, canvasPreprocess, releaseCallback
  local contentBase = content
  local function update()
    local d = connect.item
    if d ~= nil and d.needsData > 0 then
      d.needsData = d.needsData - 1
      if bit.band(d.flags, 256) ~= 0 and type(size) == 'function' and canvas ~= false then
        if finalSize.x ~= d.width or finalSize.y ~= d.height then
          finalSize:set(d.width, d.height)
          d.handle = 0
          if canvas then canvas:dispose() end
          if canvasPreprocess then canvasPreprocess:dispose() end
          size(finalSize)
          canvas = nil
          canvasPreprocess = nil
        end
      end
      if finalSize.x > 0 then
        if canvas == nil then
          canvas = ui.ExtraCanvas(finalSize, 1, render.AntialiasingMode.None,
            bit.band(flags, 16) ~= 0 and render.TextureFormat.R16G16B16A16.UNorm or render.TextureFormat.R8G8B8A8.UNorm, render.TextureFlags.Shared)
          if bit.band(flags, 8) ~= 0 then
            canvasPreprocess = ui.ExtraCanvas(finalSize, 1, render.AntialiasingMode.None, render.TextureFormat.R16.UNorm)
            content = function (s)
              contentBase(canvasPreprocess)
              s:updateWithShader({
                textures = {
                  ['txI.1'] = canvasPreprocess
                },
                shader = bit.band(flags, 2) ~= 0
                  and [[float4 main(PS_IN I){return float4(1,1,1,txI.Sample(samLinear,I.Tex).x);}]]
                  or [[float4 main(PS_IN I){return float4(txI.Sample(samLinear,I.Tex).xxx,1);}]]
              })
            end
          end
          canvas:setName('OBS: %s' % name)
          d.handle = canvas:sharedHandle(true)
          ac.broadcastSharedEvent('$SmallTweaks.OBSTextures.HandleUpdate', {
            name = fullName,
            handle = tonumber(d.handle)
          })
        end
        content(canvas, finalSize)
      end
    end
  end

  if bit.band(flags, 32) == 0 then    
    if ac.load('$SmallTweaks.OBSTextures.Initialized') == 1 then
      interval = setInterval(update)
    else
      interval = ac.onSharedEvent('$SmallTweaks.OBSTextures.Init', function ()
        interval()
        interval = setInterval(update)
      end)
    end
  end

  local function dispose()
    if canvas == false then return end
    if canvas then
      canvas:dispose()
      canvas = false
    end
    if releaseCallback then releaseCallback() end
    if type(interval) == 'function' then interval() else clearInterval(interval) end
    ac.broadcastSharedEvent('$SmallTweaks.OBSTextures', {group = group, name = name})
    finalSize:set(0, 0)
  end

  releaseCallback = ac.onRelease(dispose)
  return bit.band(flags, 32) ~= 0 and {dispose = dispose, update = update} or {dispose = dispose}
end

return obs
