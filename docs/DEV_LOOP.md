# Development loop

Testing a build used to mean closing the game, deleting the old mod in Vortex,
installing the new archive, deploying, launching through Vortex, clearing its
prompt, waiting for the main menu and pressing Continue. Most of that is gone.

## Deploying

Vortex's deploy step copies a pak and a manifest into `Mods\<name>\` and lists
that folder in `Mods\mod_order.txt`. Nothing about that needs a mod manager, so
`dev_deploy.ps1` does it directly:

```
.\tools\dev_deploy.ps1 -Launch             build, install, start the game
.\tools\dev_deploy.ps1 -NoBuild -Launch    install what was built last
.\tools\dev_deploy.ps1 -ScriptOnly         push only the Lua, game may be running
.\tools\dev_deploy.ps1 -AnimOnly           push only the animation data, same
.\tools\dev_deploy.ps1 -ParkVortexMod      move the Vortex-installed copy to mods_old\
.\tools\dev_deploy.ps1 -GameRoot "D:\..."  use an install somewhere else
```

It installs to one fixed folder, `HorseCollisionMod_dev`, rather than a
versioned one, so each build overwrites the last instead of accumulating. It
refuses to run while the game holds its paks open, and it launches with
`-devmode` (see below).

The game folder is resolved, not hardcoded, the same way `build_adb.py` resolves
it. An explicitly given path that is wrong stops the run
instead of falling through to a different install.

The release build for Nexus still goes through `build.ps1`. The dev folder is
never what ships.

## The remote console

CryEngine embeds a console server. With `log_EnableRemoteConsole = 1` in
`system.cfg` the game listens on port 4600, executes console commands sent to
it, and streams its console output back. `dev_console.py` speaks it:

```
python tools\dev_console.py --listen           watch the log stream live
python tools\dev_console.py --reload           reload the mod's Lua
python tools\dev_console.py --anim-reload      reload the Mannequin databases
python tools\dev_console.py --commands         dump every command and CVar the build has
python tools\dev_console.py "MemInfo"          run one command
python tools\dev_console.py --lua "CODE"       evaluate Lua in the running game
```

Two flags affect what is shown rather than what is sent. `--noisy` stops the
PROS and Steam chatter being filtered out. `--verbose` raises console verbosity
to 4, which is off by default because it costs frame time for output nothing
reads (see below).

`--lua` is worth knowing about: it reads the mod's live state out of the running
game, which settles questions that guessing does not.

```
python tools\dev_console.py --quiet --lua "System.LogAlways(tostring(HorseCollisionMod.Config.Knockback))"
```

Live streaming replaces reading `kcd.log` after the fact. The mod's own
telemetry arrives as it happens:

```
[log] [HorseCollisionMod] Impact tier=Walk speed=3.88 combatScale=1.0
[log] [HorseCollisionMod] Stagger action=hcm_stagger_back gender=1 ok=true err=nil
```


### Backend chatter is filtered out

Two things talk constantly and say nothing about the game:

```
PROS: authorization service state error = 3, Steam token validation failed, ...
PROS: disconnected on server side. Trying to reconnect.
[Steam] CrySteamStats: Stats stored
[Steam] Stats StatsWriteUserData return 1
```

`PROS` is Warhorse's own online backend, `Pros.Global.Api.Auth`, failing to
validate a Steam token and retrying forever. `[Steam]` is the achievement and
stats layer writing user data. Nothing in the game waits on either, and at
verbosity 4 they outnumber real log lines badly enough to make the live log
useless, which is the one thing it exists for.

Both are suppressed by default and **counted, never dropped silently**:

```
[filtered] 412 backend log lines hidden (PROS, Steam). Use --noisy to see them.
```

`--noisy` turns the filter off. `--raw` is unaffected, since raw means raw.
The patterns live in `NOISE` at the top of `dev_console.py`; add to that list
rather than filtering downstream, so the count stays accurate.

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
into nothing. `dev_console.py` therefore sends `log_Verbosity` and
`con_restricted 0` on every connection before anything else.

**The level is 2, deliberately not 4.** The mod logs through
`System.LogAlways`, which does not consult verbosity at all, so its telemetry
arrives either way. What 4 adds is every engine message, formatted, written to
the console, and forwarded over the socket one packet per frame exchange. With
the PROS backend failing twice a second that is a lot of main thread work for
output nothing reads. `--verbose` asks for 4 when engine-level detail is
actually wanted.

## Both halves reload without a restart

Reloading works, tested:

```
[log] [CONSOLE] Executing console command 'lua_reload_script Scripts/Startup/HorseCollisionMod.lua'
[log] Loading and executing script file 'Scripts/Startup/HorseCollisionMod.lua'...
[log] Loaded Scripts/Startup/HorseCollisionMod.lua
```

`mn_reload` re-parses the Mannequin databases, the subsystem that owns the
stagger fragments, so animation data is not restart-only either. Getting it to
actually take needed two separate fixes, covered below.

The first is **`sys_PakPriority = 2`**, which means pak-only: loose files on
disk are ignored entirely. A reload therefore re-reads the same packed bytes and
nothing changes. The CVar is flagged `REQUIRE_APP_RESTART` so it cannot be
flipped live.

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
.\tools\dev_deploy.ps1 -Launch          once, at the start of a session

                                  edit src/HorseCollisionMod.lua
.\tools\dev_deploy.ps1 -ScriptOnly      push the script to the running game
python tools\dev_console.py --reload    new code live, keep playing

                                  edit tools/build_adb.py, regenerate
.\tools\dev_deploy.ps1 -AnimOnly        push the animation databases
python tools\dev_console.py --anim-reload
```

Nothing here restarts the game. Both halves can change in one pass too: push the
script and the databases, then send both reloads.

`-ScriptOnly` and `-AnimOnly` deliberately skip the running-game guard, because
that guard is about the pak, which the engine holds open. A loose file is not
locked and can be replaced underneath a running game.

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

### Animation data reloads too

For a long time `mn_reload` looked like a no-op. It needed two things at once,
which is why it read as an engine limitation:

1. **The ADB files have to be on disk loose.** They only existed inside the pak,
   so the reload re-read the same packed bytes. `dev_deploy.ps1` now writes them
   to `Data\Animations\Mannequin\ADB` alongside the script, and `-AnimOnly`
   pushes just those under a running game.
2. **`mn_allowEditableDatabasesInPureGame` ships at 0.** A shipping build treats
   its Mannequin databases as read only, so the reload ran and was never
   permitted to replace anything. It is set in `system.cfg` and sent again ahead
   of every `mn_reload`, since it is a runtime value that resets with the game.

Either one alone changes nothing.

```
python tools\build_adb.py                  regenerate from the game's own paks
.\tools\dev_deploy.ps1 -AnimOnly           push the databases to the running game
python tools\dev_console.py --anim-reload
```

Confirmed by pointing the male stagger fragments at `ringing_alarm_bell` and
watching NPCs ring an invisible bell, then reverting, without the game
restarting. `ringing_alarm_bell` and `library_cabinet_open` exist only in the
male database, so a female-visible test needs a clip present in
`wh_female_database.adb`.

## Loose files hide pak faults

The dev loop deploys loose files at `sys_PakPriority = 0`. A player runs at
`2`, where loose files are ignored and only the pak is read. A pak whose entry
names or reference paths are wrong overrides nothing and logs nothing, and the
loose copies mask that completely.

So a packaged build has to be tested as one:

- `sys_PakPriority = 2` and `mn_allowEditableDatabasesInPureGame = 0`, both
  shipping defaults
- no loose files under `Data\Animations\` or `Data\Scripts\Startup\`
- installed from the zip
- launched without `-devmode`
## Watch out for

**There is only one `user.cfg` now.** There used to be a second in `Bin\Win64`,
and it was never read: settings placed there, `sys_PakStreamCache` and
`sys_preload` among them, had no effect at all. Everything lives in
`<game>\user.cfg` beside `system.cfg`. KCD's own graphics profile also overrides
`user.cfg` for some values, `r_TexturesStreamPoolSize` among them, so read a
CVar back rather than assuming a config line took.

**`sys_PakPriority = 0` and `mn_allowEditableDatabasesInPureGame = 1` are
development settings**, both in `system.cfg`. Priority 0 makes the engine check
the file system before the paks on every lookup, which costs a little load time.
Set it back to 2 for normal play.

**Audio going underwater is neither this mod nor this tooling.** It is
Warhorse's PROS service failing to reach its backend and retrying on the main
thread every half second, which stalls the audio buffer. It is intermittent
because whether the retry loop engages depends on what the backend does that
launch. Recorded in `TESTING_DIARY.md`; three separate wrong causes were
proposed before anyone looked there.

## Regenerating the API reference

The doc comments in `src/HorseCollisionMod.lua` are standard LDoc, and
`config.ld` configures the project. Regenerate `docs/api/` with:

```
ldoc .
```

LDoc needs a C compiler to install, because it depends on penlight which
depends on luafilesystem. On Windows without one:

```
winget install BrechtSanders.WinLibs.POSIX.UCRT --scope user
luarocks install ldoc
```

The compiler is only needed for that install; `ldoc .` runs on its own
afterwards. LDoc stamps a generation time into the output, so regenerating
always produces a one-line diff even when nothing else changed.
