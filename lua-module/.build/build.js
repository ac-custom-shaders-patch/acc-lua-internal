let code = $.readText('module.lua');
code = code.replace(/--@includes:start[\s\S]+--@includes:end/, () => $.glob('src/*.lua')
  .map(x => `-- ${x}\n;(function ()\n${$.readText(x)}\nend)()`).join('\n\n'));
fs.writeFileSync('module.lua.compiled', code);

const luaJit = $[process.env['LUA_JIT']];
await luaJit('-bg', `module.lua.compiled`, `module.luac`);
// $.rm('module.lua.compiled');

await luaJit('-bg', `python_prepare.lua`, `python_prepare.luac`);
await luaJit('-bg', `performance_hints.lua`, `performance_hints.luac`);
$.echo('Lua module updated');
