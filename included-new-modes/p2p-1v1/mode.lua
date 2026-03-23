--[[
This is an example of a mode adding an alternative online race implementation. Feel free to use it as a base
for your version, although, if you just edit this script, it will stop working: it uses my relay network, and
for now it’s locked to this script only. You can switch to using Steam relay network instead though.

If you’re interested in developing your own online variant, here are some key points:
- This script is an absolute mess:
  - “impl_steam” is the main logic part: connections, UI, exchange of data such as conditions or selected tyres.
  - “impl_steam_worker” is a physics worker: if sending and receiving car state is done from physics thread,
  latency is noticeably lower, and there wouldn’t be strange spikes if graphics thread is suddenly freezes.
  - “utils” is a bunch of helper functions, such as a function doing the handshake, a helper to download missing
  data and a lot more.
  - “gns” is the thing connecting to the custom relay network, and setting it in place of Steam relay network,
  in hope of reducing latency. If you want to make your own version, start by turning it off (the second variable
  in the file).
- Check out `shared/sim/altonline`: this is a great entry point for something like this. It has a function
taking a table describing state of a remote car, or, better yet, a couple of functions allowing to encode
and decode car state using only 36 bytes.
- For better results, consider setting up a physics worker to send player’s car state, and to apply remote car
state too. Connection handle is easy to transfer via `ac.connect()`, or any other way, like with worker arguments.
- When you submit car state, CSP expects you to specify the time of car state (in milliseconds, using the same
units as `ac.getSim().time`). If not provided, it’ll assume current time, and it might look reasonable sometimes,
but be vary: if it takes 50 ms for a packet to arrive from player A to player B, at 200 km/h player A’s car will
appear 3 meters behind of where it actually is. AC has uses clever logic to compensate and extrapolate car state,
but for that it has to know by how much to actually extrapolate. If you’re using that CSP state packing
(`altonline.packCarState1()`), there is a simpler alternative: simply use `altonline.configureTimeReference()`
and it’ll sync things for you. All you need to do is to call it at player A side at time T1 passing N, and 
at player B side at time T2 passing N+(T2-T1). The simplest approach is to use NTP to get precise world time,
and pass that (you can pass the list of NTP servers to `altonline.configureTimeReference()` for it to handle
things). However, for something better you could just syncronize time between clients in a fashion similar to NTP:
check out “impl_steam_worker” for an example.
- For something like racing, there is `ac.overrideSession()`. However, it has the same problem with syncronizing,
so make sure you specify the session start time explicitly.
- You don’t really have to use Steam and its functions, including Steam ID, if you’re setting up a custom relay
network. The whole `luasteam` library is optional, but if you want to use GameNetworkingSockets library
by Valve, it’s available as `require('shared/utils/luasteam').GNS`. While it does take a Steam ID as an identity
for initializing, you can simply generate a random user ID with `luasteam.extras.randomUint64()`, and pass that.
- If you’re using Steam lobbies for invites and such, two notes: first, please, add `csp.mode` data key to it with
some unique ID so scripts could differentiate between each other; and second, it seems like Steam isn’t happy
about a game constantly recreating lobbies, so maybe try to reuse one you created as much as possible.
- If you’re using Steam for anything, it’s always a good idea to consult Steam documentation:
<https://partner.steamgames.com/doc/api>.
- For the bare minimum, all you need is to send and receive car state, and call `altonline.driverConnected()` 
when appropriate. All the other stuff, like exchanging chat messages, extra CSP messages, syncing conditions, rules
and such, is optional.
- Value passed as “param” in CM invite link will be added second to “__CM_CUSTOM_MODE” in “race.ini”: use it to
encode anything you might need on receiving side.
- To keep network packets small, there are a few built-in mechanisms you can use, all of them you can see in action
in this script. The simplest (but heaviest), is `stringify.binary` (using an array instead of a table helps to reduce
size a lot). For smaller packets, use `string.pack()`. Another alternative is to define a struct using
`ac.StructItem.build()`, and then encode it with `ac.structBytes()` and decode it with `ac.fillStructWithBytes()`.
And for something the most compact and dynamic, there is `require('shared/utils/binary')` library for writing and
reading binary data with ease.
- To keep network packets even smaller, you can always encode flags as bits, meaning that a single byte will give
you eight switches. Use `bit.…` library of LuaJIT to manipulate bits efficiently.
- Make sure to disconnect at exit (tracking it with `ac.onRelease()`), so that opposing party wouldn’t have to wait
for you to timeout.
- Another use of this library could be something like taking real-life telemetry and using it to drive a car. Or,
do something like implement some weird drifting AI that doesn’t have to obey rules of physics.
- For some online modes, you might want to be able to check script on the remote side hasn’t been altered, and car
data matches as well. For that, `shared/utils/signing` library should help.

I’ll keep adding more tips if I’ll think of any. Please feel free to DM me on Telegram or Discord if you have any
questions or bugs to report. - x4fab
]]

-- Something for my dev setup to sync script with a testing laptop
-- if ac.getPatchVersion():endsWith('-dev') then
--   TESTING_ENV = io.fileExists('u:/Games/AssettoCorsa/acs__orig.exe') and 'ROOT'
--     or io.fileExists('c:/development/.bak/acc-rendering-adv_bak/.ldm') and 'TEST' or nil
--   if TESTING_ENV then
--     ac.warn('Testing: %s' % TESTING_ENV)
--     ui.onExclusiveHUD(function(mode) return 'debug-nonexclusive' end)
--     if TESTING_ENV ~= 'TEST' then
--       ac.startBackgroundWorker('_dev/lan_sync', nil, function (err)
--         print('Sync worker has finished, err:', err)
--       end)
--     else
--       -- physics.setCarAutopilot(true, false)
--     end
--   end
-- end

-- Actual implementation
require './impl_steam'
