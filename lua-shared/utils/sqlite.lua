--[[
  Helper for loading sqlite.lua library (https://github.com/kkharji/sqlite.lua). Binaries already
  ship with CSP, all you need is to download sqlite.lua and load it after loading this library (it’ll
  add a few runtime patches to allow sqlite.lua to load without luv or fully compatible LuaJIT).

  Compatible with v1.2.2 (might work with other versions too).

  To use, add `require('shared/utils/sqlite')` before including sqlite.lua. Note that only scripts with
  proper I/O access would be able to access SQLite functions.
]]

-- Seems like luv is not really needed, so here is a plug:
package.loaded['luv'] = {
  fs_realpath = function (x) return x end,
  os_getenv = function () return '' end,
  fs_stat = function (x) return {mtime = {sec = io.lastWriteTime(x)}} end,
}

-- LuaJIT in CSP does not have ffi.load, but it can load sqlite functions from extension/internal/plugins/sqlite3.dll:
ffi.load = function () return ffi.C end
