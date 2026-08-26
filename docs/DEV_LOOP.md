# Development loop

Testing a build used to mean closing the game, deleting the old mod in Vortex,
installing the new archive, deploying, launching through Vortex, clearing its
prompt, waiting for the main menu and pressing Continue. Most of that is gone.

## Deploying

Vortex's deploy step copies a pak and a manifest into `Mods\<name>\` and lists
that folder in `Mods\mod_order.txt`. Nothing about that needs a mod manager, so
`dev_deploy.ps1` does it directly:

```
.\dev_deploy.ps1 -Launch          build, install, start the game
.\dev_deploy.ps1 -NoBuild -Launch  install what was built last
.\dev_deploy.ps1 -ParkVortexMod    move the Vortex-installed copy to mods_old\
```

It installs to one fixed folder, `HorseCollisionMod_dev`, rather than a
versioned one, so each build overwrites the last instead of accumulating. It
refuses to run while the game holds its paks open, and it launches with
`-devmode` (see below).

The release build for Nexus still goes through `build.ps1`. The dev folder is
never what ships.

## The remote console

CryEngine embeds a console server. With `log_EnableRemoteConsole = 1` in
`system.cfg` the game listens on port 4600, executes console commands sent to
it, and streams its console output back. `dev_console.py` speaks it:

```
python dev_console.py --listen           watch the log stream live
python dev_console.py --reload           reload the mod's Lua
python dev_console.py --anim-reload      reload the Mannequin databases
python dev_console.py --commands         dump every command and CVar the build has
python dev_console.py "MemInfo"          run one command
```

Live streaming replaces reading `kcd.log` after the fact. The mod's own
telemetry arrives as it happens:

```
[log] [HorseCollisionMod] Impact tier=Walk speed=3.88 combatScale=1.0
[log] [HorseCollisionMod] Stagger action=hcm_stagger_back gender=1 ok=true err=nil
```

### Protocol notes

Each packet is one event-type character, the payload, then a zero byte. The
event type is written as an **ASCII digit**, `'0' + type`, not a raw byte, so
the server's opening `b"1\x00"` is type 1 and not 49.

The exchange is **server-driven and strictly alternating**. The server sends one
packet and waits. A client that answers only the explicit requests receives a
single packet and then silence. Answer every packet, with a queued command if
there is one and a noop if not, and the stream flows.

## Dev mode is a command-line switch

`sys_DevMode` is **not a CVar in this build**; querying it answers "Unknown
command", so the `sys_DevMode = 1` line in `system.cfg` has never done anything.
Dev mode comes from the command line, `-devmode`, which `dev_deploy.ps1` passes.

Without it the console refuses everything marked `VF_CHEAT`:

```
[error] [CVARS]: [EXECUTE] command lua_reload_script is marked [VF_CHEAT]
```

Related: the console expression prefix is `!`, not `#` (`wh_con_expr_prefix`).

## Console verbosity resets on restart

`log_Verbosity` is a runtime value. A session started after a game restart is
silent until it is raised again, which looks exactly like commands vanishing
into nothing. `dev_console.py` therefore sends `log_Verbosity 4` and
`con_restricted 0` on every connection before anything else.

## Both halves reload, but the pak is in the way

Reloading works, tested:

```
[log] [CONSOLE] Executing console command 'lua_reload_script Scripts/Startup/HorseCollisionMod.lua'
[log] Loading and executing script file 'Scripts/Startup/HorseCollisionMod.lua'...
[log] Loaded Scripts/Startup/HorseCollisionMod.lua
```

`mn_reload` likewise re-parses the Mannequin databases, which is the subsystem
that owns the stagger fragments, so animation data is not restart-only either.

What blocks a true edit-and-reload loop is **`sys_PakPriority = 2`**, which
means pak-only: loose files on disk are ignored entirely. A reload therefore
re-reads the same packed bytes and nothing changes. The CVar is flagged
`REQUIRE_APP_RESTART` so it cannot be flipped live.

`system.cfg` therefore now carries `sys_PakPriority = 0`, loose files first,
which takes effect on the next restart. `dev_deploy.ps1` writes the script loose
alongside the pak, and warns if the CVar is not 0 rather than leaving a silent
no-op to be found later. `-NoLooseScript` skips it.

The packed copy inside the pak is untouched and remains what ships. The loose
file is only what the running game reads first.

### Loose files go under Data

`sys_game_folder` is `Data`, so the engine's file system is rooted at
`<game>\Data`. A loose script belongs at

```
<game>\Data\Scripts\Startup\HorseCollisionMod.lua
```

One level higher is never found, and the failure is silent: "Loading and
executing script file" is logged **before** the read is attempted, and a miss
logs nothing at all. That reads exactly like a script that loaded and did
nothing, which cost a round of wrong diagnosis. Confirmed by reloading a probe
script that existed only as a loose file: under `Data` it executed and printed,
one level up it did not.

## The loop

```
.\dev_deploy.ps1 -Launch          once, at the start of a session

                                  edit HorseCollisionMod.lua
.\dev_deploy.ps1 -ScriptOnly      push the script to the running game
python dev_console.py --reload    new code live, keep playing
```

`-ScriptOnly` deliberately skips the running-game guard, because that guard is
about the pak, which the engine holds open. A loose `.lua` is not locked and can
be replaced underneath a running game.

### Reloading has to restart the detection loop

Re-executing the script is not enough on its own. The mod's loop is started only
by its UI listener when a loading screen ends, because a Startup script has no
"game loaded" hook. A reload rebuilds the `HorseCollisionMod` table with
`TimerTick` unset, so the loop still running from before sees its generation no
longer match and stops, and nothing starts a new one. The mod goes silent and
the game looks completely vanilla until a save is loaded.

`--reload` therefore calls the entry point directly afterwards, which stands in
for that loading screen:

```
#HorseCollisionMod:uiActionListener('sys_loadingimagescreen', 'OnEnd', nil)
```

A successful reload now ends with the mod announcing its new loop:

```
[log] [HorseCollisionMod] Load screen ended. v2.0.0 initializing physics timer loop 1
```

Both console Lua prefixes, `#` and `!`, work once the game is in dev mode. They
do nothing without it, which is what made `#` look broken earlier.

Animation data changes need a rebuild and `--anim-reload`, since the ADB files
live in the pak rather than loose.

## Watch out for

`Bin\Win64\user.cfg` sets `sys_PakStreamCache = 1` and `sys_preload = 1`. Those
are aggressive caching settings and are the first suspects if a loose-file
override does not take even at priority 0.
