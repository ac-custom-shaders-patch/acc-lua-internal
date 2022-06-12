# CSP Lua Internals

Some Lua internals for reference.

- `included-cars`: shared car scripts shipped with CSP builds (look for readme for information on how to include those in your car config);
- `included-tools`: shared tools shipped with CSP builds (can be accessed with Objects Inspector);
- `lua-module`: code used by Small Tweaks module adding all sorts of small things, too small to be kept in C++ code (feel free to use those modules as examples);
- `lua-shared`: shared libraries available by any Lua script running with CSP. To include, use “shared/” prefix, like `require('shared/socket')`.
