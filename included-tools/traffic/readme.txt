A small experiment with adding traffic to Assetto Corsa (nothing fancy, offline and without replay support
for now).

To use it:

1. Download missing data and extract data folder to “csp-traffic-tool” (not included by default to keep 
  CSP lighter): https://files.acstuff.ru/shared/IeBU/data.zip. Data contains car models, colliders and
  font to generate license plates on fly. Models are LOD C and D of a couple of original cars.

  If you would want to add new cars, just use those LODs and move all nodes but wheels to a node “BODY”
  so that car body can be moved as car accelerates or slows down.

2. Prepare track: for scripting physics to work, track should have custom physics enabled and explicitly
  allow for scripts to alter physics. For that, edit track’s “surfaces.ini” (can be found in 
  “content/tracks/trackfolder/data” or in “content/tracks/trackfolder/layout/data”). Note: after doing so,
  you would not be able to use this track online (if server would verify integrity) or with original
  Assetto Corsa, that’s the whole point of custom physics. So, consider making a backup file.

  Actual edits are:
  • Change WAV_PITCH in SURFACE_0 to “extended-0” (this activates custom track physics);
  • Add following somewhere:
  
    [_SCRIPTING_PHYSICS]
    ALLOW_TOOLS=1

3. Run Assetto Corsa in regular practice session on that track. Find in-game app Objects Inspector, open
  it, click “Tools” and select traffic planner. This tool allows to both edit traffic grid and test it live.

  Traffic grid is saved as “traffic.json” next to “surfaces.ini”. If you have track Daikoku Parking by Soyo, 
  here is a prepared patch: https://files.acstuff.ru/shared/y37I/data.zip

Whole thing is currently in a pretty rough shape and needs some improvements, but it should work. Also, it’s
possible to split editor and traffic-running-script and move traffic to act like a track script (it would
require adding “ALLOW_TRACK_SCRIPTS=1” to that section in “surfaces.ini” though).

If you would be interested in forking script and turning it into something else, please feel free to do so.
It’s mostly just an example and a testing ground of how new Lua APIs can be used.
