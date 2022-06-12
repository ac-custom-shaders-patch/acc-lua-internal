Plug this script to your car config to get some recreation of Android Auto: navigator, rear view camera, music, radio, youtube and other
apps user might add later. Here is how it can be used:


[INCLUDE: android_auto/config.ini]
[Display_AndroidAuto]
Meshes = GEO_display_COMM  ; display mesh
Resolution = 1024, 1024    ; texture resolution
Size = 1013, 397           ; size of the screen area
Offset = 5, 5              ; left top corner of screen area
Scale = 1                  ; might need adjusting to get the scale right
RearCameraPosition = 0, 0.75, -2.5  ; position of rear view camera


Also might be useful:


[EXTRA_FX]
GLASS_FILTER = GEO_display_COMM       ; reduce ghostiness of the display
SKIP_GBUFFER = center_interior_glass  ; if display is covered by glass, improve look and performance by removing it from G-buffer pass

[INCLUDE: common/materials_interior.ini]
[Material_DigitalScreen]  ; set digital screen material
Materials = INT_displays_COMM
ScreenScale = 600
ScreenAspectRatio = 0.5
MatrixType = TN

[DATA]
DISABLE_DI_TEXT_NODES = 9  ; disable some original digital instruments if needed


Pro tip: hold “Home” button (circle in left bottom corner) to access list of running apps.

New apps can be added in “apps” folder. Main file defining an app is “manifest.ini” (also don’t forget about icon; it would look better
if icon would be circular too). Apps consist of three parts, all optional:

• app.lua
  
  Loaded when app first opens, returns a function which will be called to draw main app UI. If not present, app would not have UI (useful
  for apps like navigator one, where UI is done by dynamic texture).
  
• status.lua

  Used for showing app status in bottom bar. If app has active status with largest priority, function from this file will be called to
  create UI of that control (might be used to draw some text or buttons). If function returns false, status control reduces to a compact
  shape with nothing but icon.

• service.lua

  Loaded from the start and runs a couple of times per second, can be used for some background processing. Keep these things lightweight.
  If upon initializing service throws an error, rest of an app will not be loaded (can be used for optionally appearing apps).

A few tips for making new apps:

• Add some prefix to names of your app folders, similar to “ks_” prefix for original content to avoid conflicts;
• When you refer to an image or a file in an app, use “io.relative()” function instead of writing full file path;
• When you refer to a different Lua file in an app, use “package.relative()” function instead of writing full file path;
• Try to keep things lightweight to make sure things would run smoothly;
• When not interacted with, framerate drops to one update per second. Use `touchscreen.forceAwake()` to keep frame rate app if you need it.
