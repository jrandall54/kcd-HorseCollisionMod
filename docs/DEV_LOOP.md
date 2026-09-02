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

Verifying a release requires the shipping values, so an install used for a
release is left configured for play. `dev_deploy.ps1` switches between the two
and refuses to deploy into an install configured for play, because at
`sys_PakPriority = 2` a deploy, a reload and a console command all report
success while the game keeps running the packed build.

```
.\tools\dev_deploy.ps1 -SetDevEnvironment     development values
.\tools\dev_deploy.ps1 -SetPlayEnvironment    shipping values
```

Restart the game after either. `-Force` deploys into an install that will
ignore what it is given.

### The pre-push hook

Enable it once per clone:

```
git config core.hooksPath .githooks
```

Git does not carry hook configuration through a clone, so a fresh checkout has
no hooks until this is set.

Pushing `main` then runs the version and changelog check, the documentation
style check, and the staleness sweep, and refuses the push if any of them
reports a problem. Pushing a topic branch runs nothing, because a branch in
progress is allowed to be inconsistent.

The staleness sweep has two scopes, chosen by what is happening rather than by
what the version looks like.

`build.ps1` and the pre-push hook check the repository's own accuracy: version
numbers, documented claims, config keys against their documentation, and quoted
download sizes against the built zip.

`publish_nexus.ps1` also checks the mod page copy and the Files tab entry.
Those are written once per release, and publishing is the only act that puts
them in front of anyone. Every merge to `main` takes a plain version and builds
at it while almost none are published, so gating a build on the page copy would
stop ordinary work on a document nobody is about to read.

Both scopes can be run by hand:

```
python tools\pre_release_check.py --merge    repository only
python tools\pre_release_check.py            repository and mod page
```

## Deploying

```
.\tools\dev_deploy.ps1 -Reload             push what changed and reload it
.\tools\dev_deploy.ps1 -Launch             build, install, start the game
.\tools\dev_deploy.ps1 -NoBuild -Launch    install what was built last
.\tools\dev_deploy.ps1 -ScriptOnly         push the Lua whether or not it changed
.\tools\dev_deploy.ps1 -AnimOnly           push the animation data, same
.\tools\dev_deploy.ps1 -ParkVortexMod      move the Vortex-installed copy to mods_old\
.\tools\dev_deploy.ps1 -GameRoot "D:\..."  use an install somewhere else
```

It installs to `Mods\HorseCollisionMod_dev`, overwriting the last build, and
launches with `-devmode`. It refuses to run while the game holds its paks open.
`-Reload`, `-ScriptOnly` and `-AnimOnly` skip that guard, because loose files
are not locked and can be replaced under a running game.

`-Reload` compares every loose file against its source, copies the ones whose
contents differ, and runs the console reload for whichever halves moved. It
reports `nothing changed since the last deploy` when they all match, and says so
rather than reloading when the game is not running. The comparison is on
contents rather than timestamps, because `build.ps1` rewrites all four animation
databases on every run and a Mannequin reload is a visible hitch in the running
game.

`-ScriptOnly` and `-AnimOnly` name one half and skip the comparison. Use them
for a file that has been reverted to a state matching the installed copy, or
when only one subsystem should be disturbed.

Loose files go under `<game>\Data`, mirroring the pak layout:

```
Data\Scripts\Startup\HorseCollisionMod.lua
Data\Scripts\Startup\HorseCollisionMod_Settings.lua
Data\Scripts\HorseCollisionMod\*.lua
Data\Animations\Mannequin\ADB\*.adb
```

The settings file is a Startup script in its own right. Left out, the running
game reads the packed values while the edited file sits on disk looking
applied.

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
.\tools\dev_deploy.ps1 -Launch      once, at the start of a session

                              edit src/, or regenerate the databases
.\tools\dev_deploy.ps1 -Reload      push what moved, reload it live
```

Both halves can change in one pass, and Mannequin is reloaded before the Lua, so
the detection loop restarts against databases that are already current. Nothing
here restarts the game.

`--reload` re-executes the settings file and the mod script, then calls the
mod's entry point:

```
#HorseCollisionMod:uiActionListener('sys_loadingimagescreen', 'OnEnd', nil)
```

That second step is required. The mod starts its detection loop only from that
listener, so a bare re-execution leaves the mod silent until a save is loaded. A
successful reload ends with:

```
[log] [HorseCollisionMod] Load screen ended. v3.0.0 initializing physics timer loop 1
```

## Landing a branch

The version lives in fourteen places: `src/mod.manifest`, the
`HorseCollisionMod.Version` assignment, and an `@release` tag in the entry
point and each of the eleven part files. `build.ps1` refuses a release if any
of them disagrees.

One command writes all of them, and dates the changelog section at the same
time:

    python tools/set_version.py            derive the next version and apply it
    python tools/set_version.py 4.7.0      apply one explicitly
    python tools/set_version.py --check    report without writing

Deriving uses the same rule the build enforces: the newest tag, bumped by what
the entries under `## [Unreleased]` call for. Applying it also moves those
entries under a dated heading for the new version, which is the step the
workflow requires when a branch merges.

So a branch lands like this:

    python tools/set_version.py
    ldoc .
    .uild.ps1 -Version <the version it printed>
    git add -A && git commit
    git checkout main && git merge --no-ff <branch>
    git tag -a v<version> -m "..."
    git push origin main --follow-tags

`ldoc .` belongs in that order because the staleness check compares **commit**
times rather than file times, so the regenerated pages have to be committed
alongside the sources they describe. Regenerating after the commit leaves the
check failing on the next build.

### Two things that used to bite

Rebuilding a version that is already tagged works. The version check compares
against the newest tag *older than* the build target, so `dev_deploy.ps1` runs
normally after a merge; it used to fail against the tag it had just created
and needed `-NoBuild` to get past.

A version mismatch reports every file at once. It used to fail on the first,
which turned a bump into a build-fix-build cycle repeated once per file.

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
