# Development loop

Change the mod and see the change in a running game, without restarting it.

## The workflow

`tools\flow.ps1` is the only entry point. Each verb puts the repository and the
install into one state, and running a verb again in that state re-syncs rather
than failing.

```
.\tools\flow.ps1 status          where the branch, version, install and game stand
.\tools\flow.ps1 branch NAME     start a topic branch and seed its testing world
.\tools\flow.ps1 test            deploy, and reload into a running game
.\tools\flow.ps1 test -Launch    the same, and start the game if it is closed
.\tools\flow.ps1 world           print the testing world
.\tools\flow.ps1 shipping        park the mod to test a release build
.\tools\flow.ps1 land "msg"      finish the branch
```

`tools\dev_deploy.ps1` is `flow`'s internal helper and is not run directly.

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

`flow.ps1 shipping` switches the install to the shipping values and parks every
loose file; `flow.ps1 test` switches it back. The deploy refuses an install
configured for play, because at `sys_PakPriority = 2` a deploy, a reload and a
console command all report success while the game keeps running the packed
build. Restart the game after either switch.

## Deploying

The game install is found through `KCD_PATH`, then the usual Steam and GOG
locations, then every Steam library in `libraryfolders.vdf`. A wrong `KCD_PATH`
stops the run instead of falling through to another install. `build_adb.py`
resolves the same way.

With the game closed, `test` builds, installs to `Mods\HorseCollisionMod_dev`,
overwriting the last build, and copies the loose files; `-Launch` then starts
the game with `-devmode`. The build is named `<version>-dev`, so it never
overwrites a release zip.

With the game running, the engine holds the installed pak open, so `test`
copies only the loose files whose contents differ from the repository and runs
the console reload for whichever halves moved. A change to the testing world
counts as a script change. It reports `nothing changed since the last deploy`
when everything matches. The comparison is on contents rather than timestamps,
because a regeneration rewrites the animation databases and a Mannequin reload
is a visible hitch in the running game.

Loose files go under `<game>\Data`, mirroring the pak layout:

```
Data\Scripts\Startup\HorseCollisionMod.lua
Data\Scripts\Startup\HorseCollisionMod_Settings.lua
Data\Scripts\HorseCollisionMod\*.lua
Data\Animations\Mannequin\ADB\*.adb
Data\Libs\Config\hcm_actionmaps.xml
Data\Libs\Tables\rpg\*__horsecollisionmod.xml
```

The settings file is a Startup script in its own right. Left out, the running
game reads the packed values while the edited file sits on disk looking
applied.

The action map and the tables are read once per session, so a change to either
takes effect at the next game start.

Releases go through `build.ps1`. The dev folder never ships.

## The testing world

What a branch changes about the installed settings, so a test is not
interrupted by the mod's shipping behavior. The default, `[dev]` in
`tools/testworlds.ini`, switches off the crime, the throw from the saddle and
the bolt on an emptied horse, retaliation and its pull-down and surrender prompt, women
raising the alarm, and both fear bands.

It is branch state. `flow.ps1 branch` seeds the default, every `test`
re-applies it, anything asked for on a later `test` is added to it, and `land`
clears it.

```
tools/flow.ps1 world                              what is live
tools/flow.ps1 test -Preset stamina               add a named world
tools/flow.ps1 test -Set CollisionIsCrime=true    change one setting
tools/flow.ps1 test -Set StaminaShareByTier.Gallop=0
tools/flow.ps1 test -Unset CollisionIsCrime       drop one
tools/flow.ps1 test -Shipped                      carry nothing
```

Anything in the settings file can be set, including a member of a table. Named
worlds live in `tools/testworlds.ini` as data.

### How it reaches the game

`tools/testworld.py` writes `HorseCollisionMod_TestWorld.lua` into the
development install beside the settings file. Startup scripts load in name
order, so it runs after `HorseCollisionMod_Settings.lua` and assigns into the
same global; the mod then applies it through `ApplySettings` with the same type
checking and without knowing it exists.

Nothing can ship it, because `build.ps1` packs from `src/`, which never holds
it. The installed settings stay byte-identical to the repository, so the
deploy's own verification is exact.

The world is written to `kcd.log` at load, as the record of what a run was
measured against:

```
[HorseCollisionMod] test world: CollisionIsCrime=false, Retaliation=false
```

## The remote console

CryEngine listens on port 4600 and streams console output back.

```
python tools\dev_console.py --listen          watch the log stream live
python tools\dev_console.py --reload          reload the mod's Lua
python tools\dev_console.py --anim-reload     reload the Mannequin databases
python tools\dev_console.py --commands        dump every command and CVar
python tools\dev_console.py "MemInfo"         run one command
python tools\dev_console.py --lua "CODE"      evaluate Lua in the running game
python tools\dev_console.py --file PATH       evaluate a Lua file as one chunk
python tools\dev_console.py --ride            start the survival loop for a ride
python tools\dev_console.py --wait SECONDS    keep reading after the command
python tools\dev_console.py --diagnose        turn on console output, read it back
python tools\dev_console.py --raw             dump every byte received
```

`--lua` reads and writes the mod's live state:

```
python tools\dev_console.py --quiet --lua "System.LogAlways(tostring(HorseCollisionMod.Config.Knockback))"
```

Backend chatter from `PROS` and `[Steam]` is filtered out; `--noisy` shows it.
Verbosity is raised on connect, since it resets on every game restart;
`--verbose` raises it further for engine-level messages.

Cheat-marked commands, `lua_reload_script` among them, need `-devmode`, which
`flow.ps1 test -Launch` passes.

## The loop

```
.\tools\flow.ps1 test -Launch    once, at the start of a session

                              edit src/, or regenerate the databases
.\tools\flow.ps1 test            push what moved, reload it live
```

Both halves can change in one pass, and Mannequin is reloaded before the Lua, so
the detection loop restarts against databases that are already current. Nothing
here restarts the game.

The Lua reload re-executes the settings file and the mod script, then calls the
mod's entry point:

```
#HorseCollisionMod:uiActionListener('sys_loadingimagescreen', 'OnEnd', nil)
```

That second step is required. The mod starts its detection loop only from that
listener, so a bare re-execution leaves the mod silent until a save is loaded. A
successful reload ends with:

```
[log] [HorseCollisionMod] Load screen ended. v<version> initializing physics timer loop 1
```

## Tests that need game time

`Calendar` is a Lua global and world time is directly settable, so the in-game
wait dialog is not needed:

```
python tools\dev_console.py --file tools\dev_survival.lua
python tools\dev_console.py --file tools\dev_time.lua
```

`dev_time.lua` carries an `HOURS` value at the top; 24 moves a full day in one
call. Setting `RATIO` instead leaves ordinary time running fast rather than
jumping. The shipped ratio is 15.

`dev_survival.lua` holds nourishment and energy at 100, so a multi-day skip in
hardcore needs no food or bed. Neither survives a save load; re-run both after
one.

## Landing a branch

```
.\tools\flow.ps1 land "msg"
```

It checks the documentation style and the testing diary, and runs
`pre_release_check.py`, which regenerates a stale API reference. It then sets
the version from `CHANGELOG.md` with `set_version.py`, builds, commits, merges
into `main`, tags and pushes. Last, it deletes every local branch already
merged into `main` and clears the testing world. `-NoPush` stops before the push.

The version lives in `src/mod.manifest` and the `HorseCollisionMod.Version`
assignment, and `build.ps1` refuses a release if either disagrees.
`set_version.py` writes both and dates the changelog section:

```
python tools\set_version.py            derive the next version and apply it
python tools\set_version.py X.Y.Z      apply one explicitly
python tools\set_version.py --check    report without writing
```

Deriving uses the rule the build enforces: the newest tag older than the build
target, bumped by what the entries under `## [Unreleased]` call for.

### Staleness checks

`build.ps1` checks the repository's own accuracy: version numbers, documented
claims, config keys against their documentation, the layout blocks, and quoted
download sizes against the built zip. `publish_nexus.ps1` also checks the mod
page copy and the Files tab entry, which only publishing puts in front of
anyone.

```
python tools\pre_release_check.py --merge    repository only
python tools\pre_release_check.py            repository and mod page
```

## Testing a packaged build

The loop above runs on loose files. A player runs on paks only, where a pak with
wrong entry names or reference paths overrides nothing and logs nothing.

`flow.ps1 shipping` sets up that state before publishing:

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

## Tools

Every tool resolves paths from the repository root and runs from any directory.

```
tools/
  flow.ps1                the workflow's verbs: status, branch, test, world,
                          shipping, land
  dev_deploy.ps1          flow's internal deploy helper
  game_root.ps1           resolves the game install for the PowerShell tools
  build_adb.py            generates the human animation databases from the
                          game install
  check_tiers.lua         refuses a tier table in the settings file that
                          differs from the one in Tiers.lua
  testworld.py            writes the testing world into the development install
  testworlds.ini          named testing worlds
  dev_console.py          talks to the running game over its remote console
  pre_release_check.py    finds claims the repository makes that are not true
  version_check.py        derives the next version from CHANGELOG.md
  set_version.py          writes the version and dates the changelog section
  audit_code.py           reports unread settings, uncalled functions and
                          unused tables
  verify_additive.py      checks the release's animation layout and file set
  nexus_settings_block.py generates the mod page's settings block and the
                          README settings table from the settings file
  publish_nexus.ps1       uploads a built release to the Nexus Mods page
  bark_chain.py           walks a bark set from metarole to role to topic to
                          sequences, with each line's cooldown
  bark_lines.py           prints the English text of a vanilla bark set, or
                          finds the set holding a remembered line
  bark_alias.py           prints any topic addressable by alias, with its
                          lines, speakers and word counts
  henry_impact_lines.py   every line Henry can be made to say
  npc_pain_sets.py        every NPC bark set whose sequences are all
                          unconditional
  probe_api.lua           lists the methods an object exposes in the running
                          game
  probe_bark.lua          tests whether a vanilla line can be triggered from Lua
  probe_camera.lua        polls the first-person camera through a view shake
  probe_gait_speed.lua    reports the mounted horse's speed plateau per gait
  probe_health.lua        logs one entity's health whenever it changes
  probe_inventory.lua     lists what a named entity carries
  probe_tables.lua        dumps a game table through the Database bind
  dev_peace.lua           stops the world reacting to the player
  dev_survival.lua        holds the player's nourishment and energy at 100
  dev_time.lua            moves game time forward through the Calendar global
  dev_horse.lua           gives the player a rideable horse
  dev_fasthorse.lua       gives the player the fastest horse in the level
  dev_barding.lua         puts a set of barding on the player's horse
  dev_watchfight.lua      samples everyone near the player once a second
```
