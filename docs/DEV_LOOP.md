# Development loop

Change the mod and see the change in a running game, without restarting it.

## Requirements

`system.cfg`, in the game root:

```
log_EnableRemoteConsole = 1              opens the console port
sys_PakPriority = 0                      read loose files before paks
mn_allowEditableDatabasesInPureGame = 1  allow Mannequin reloads
```

`sys_PakPriority` is flagged `REQUIRE_APP_RESTART` and cannot be changed live.
At its shipping value of `2` the engine reads only paks, and every loose file
below is ignored.

## Deploying

```
.\tools\dev_deploy.ps1 -Launch             build, install, start the game
.\tools\dev_deploy.ps1 -NoBuild -Launch    install what was built last
.\tools\dev_deploy.ps1 -ScriptOnly         push only the Lua, game may be running
.\tools\dev_deploy.ps1 -AnimOnly           push only the animation data, same
.\tools\dev_deploy.ps1 -ParkVortexMod      move the Vortex-installed copy to mods_old\
.\tools\dev_deploy.ps1 -GameRoot "D:\..."  use an install somewhere else
```

It installs to `Mods\HorseCollisionMod_dev`, overwriting the last build, and
launches with `-devmode`. It refuses to run while the game holds its paks open.
`-ScriptOnly` and `-AnimOnly` skip that guard, because loose files are not
locked and can be replaced under a running game.

Loose files go under `<game>\Data`, mirroring the pak layout:

```
Data\Scripts\Startup\HorseCollisionMod.lua
Data\Animations\Mannequin\ADB\*.adb
```

A file one level higher is never read, and nothing is logged when that happens.

The game folder is resolved, not hardcoded: `-GameRoot`, then `KCD_PATH`, then
the usual Steam and GOG locations, then every Steam library in
`libraryfolders.vdf`. A wrong explicit path stops the run instead of falling
through to another install. `build_adb.py` resolves the same way, with
`--game-root`.

Releases go through `build.ps1`. The dev folder never ships.

## The remote console

CryEngine listens on port 4600 and streams console output back.

```
python tools\dev_console.py --listen           watch the log stream live
python tools\dev_console.py --reload           reload the mod's Lua
python tools\dev_console.py --anim-reload      reload the Mannequin databases
python tools\dev_console.py --commands         dump every command and CVar
python tools\dev_console.py "MemInfo"          run one command
python tools\dev_console.py --lua "CODE"       evaluate Lua in the running game
```

`--lua` reads and writes the mod's live state:

```
python tools\dev_console.py --quiet --lua "System.LogAlways(tostring(HorseCollisionMod.Config.Knockback))"
```

Backend chatter from `PROS` and `[Steam]` is filtered out; `--noisy` shows it.
Verbosity is raised on connect, since it resets on every game restart;
`--verbose` raises it further for engine-level messages.

Cheat-marked commands, `lua_reload_script` among them, need `-devmode`, which
`dev_deploy.ps1` passes.

## The loop

```
.\tools\dev_deploy.ps1 -Launch          once, at the start of a session

                                  edit src/HorseCollisionMod.lua
.\tools\dev_deploy.ps1 -ScriptOnly      push the script
python tools\dev_console.py --reload    new code live

                                  edit tools/build_adb.py, regenerate
.\tools\dev_deploy.ps1 -AnimOnly        push the animation databases
python tools\dev_console.py --anim-reload
```

Both halves can change in one pass. Nothing here restarts the game.

`--reload` re-executes the script and then calls the mod's entry point:

```
#HorseCollisionMod:uiActionListener('sys_loadingimagescreen', 'OnEnd', nil)
```

That second step is required. The mod starts its detection loop only from that
listener, so a bare re-execution leaves the mod silent until a save is loaded. A
successful reload ends with:

```
[log] [HorseCollisionMod] Load screen ended. v3.0.0 initializing physics timer loop 1
```

## Testing a packaged build

The loop above runs on loose files. A player runs on paks only, where a pak with
wrong entry names or reference paths overrides nothing and logs nothing.

Before publishing, test the zip as one:

- `sys_PakPriority = 2` and `mn_allowEditableDatabasesInPureGame = 0`, both
  shipping defaults
- no loose files under `Data\Animations\` or `Data\Scripts\Startup\`
- installed from the zip
- launched without `-devmode`

## Regenerating the API reference

```
ldoc .
```

`config.ld` configures the project. LDoc needs a C compiler to install, because
it depends on penlight, which depends on luafilesystem:

```
winget install BrechtSanders.WinLibs.POSIX.UCRT --scope user
luarocks install ldoc
```

The compiler is only needed for that install.
