# CSP Lua Internals

Source code for some parts of Custom Shaders Patch written in Lua. Feel free to use them for reference, fork them and create your own things, do anything you want.

- `included-apps`: a few Lua apps packaged together with CSP (rest can be accessed via App Shelf app);
- `included-cars`: car scripts shipped with CSP (well, currently a single script; look for readme for information on how to include those in your car config);
- `included-gamepad`: default GamepadFX scripts (you can also find source code of the Expo.dev mobile counterpart in `included-gamepad/mobile` folder);
- `included-new-modes`: source code for new game modes added by CSP;
- `included-pp-filters`: source code for Lua-driven post-processing effects;
- `included-tools`: some built-in tools (can be accessed with Objects Inspector);
- `lua-module`: code used by Small Tweaks module adding all sorts of small things, too small to be kept in C++ code (feel free to use those modules as examples);
- `lua-shared`: shared libraries available by any Lua script running with CSP. To include, use “shared/” prefix, like `require('shared/socket')`;
- `plugins`: not quite Lua, but those are processes running in background providing extra features to Lua, usually via shared memory.

