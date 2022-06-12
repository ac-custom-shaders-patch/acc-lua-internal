# CSP Lua Internals

Some Lua internals for reference.

- `lua-module`: code used by Small Tweaks module adding all sorts of small things, too small to be kept in C++ code (feel free to use those modules as examples);
- `lua-shared`: shared libraries available by any Lua script running with CSP. To include, use “shared/” prefix, like `require('shared/socket')`.
