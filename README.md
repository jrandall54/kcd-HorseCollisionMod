# Horse Collision Mod

Vanilla horse collisions produce a shout and nothing else. This adds a reaction scaled to
your speed, and a cost so it is not free.

## What happens

| Speed | NPC | Horse stamina |
| --- | --- | --- |
| Walk, 1.8+ m/s | Staggers, stays on their feet, takes no damage | No cost |
| Trot, 4.5+ m/s | Knocked down | -45 |
| Gallop, 8.5+ m/s | Knocked down harder | -75 |

- The stagger is the game's own standing hit reaction, picked from the side you hit them on.
- No crime or bounty. The mod does not fake an attack, so the crime system is never involved.
- If a collision empties your horse's stamina, it rears and throws you off.
- Horses have different stamina pools and it regenerates between impacts, so how many people
  you can put down before that happens depends on your horse and how fast you string hits
  together.

## In combat

- Stamina cost is multiplied by 2.5.
- The walk speed stagger is disabled.
- Knockdowns are unchanged.

## Design

The first version was a physics hack: every impact applied a raw impulse and threw a ragdoll,
at any speed. This version tries to make collisions behave like part of the game.

- Reactions are the game's own animations. The stagger, the knockdown and the rear-and-throw
  all already exist in vanilla.
- Speed thresholds come from measured in-game gaits rather than round numbers.
- The detection area is shaped like a horse, and was narrowed after logging where impacts
  were actually landing.
- Stamina limits how much you can do in one run, and costs more in combat, so charging into a
  fight is a decision rather than a default.
- Nothing is hardcoded. Every threshold, force and cost is a value at the top of one file.

## Requirements

**Kingdom Come: Deliverance 1.9.7.** The mod declares that version in its
manifest, and the game disables any mod whose declared version does not match
`wh_sys_version` in `system.cfg`. That is deliberate: the mod ships whole
animation databases generated from 1.9.7, so a mismatch failing to load is
safer than it loading and overwriting a different version's animation data.

1.9.7 is the final build, so in practice this means any up-to-date copy.

## Install

Vortex, or extract the zip into `Kingdom Come - Deliverance\Mods\`.

## Settings

1. Go to `Mods\HorseCollisionMod\Data\`
2. Right click `HorseCollisionMod.pak`, open with 7-Zip or WinRAR (open, do not extract)
3. Edit `Scripts\Startup\HorseCollisionMod.lua` inside the archive
4. Save, and let the archive update when prompted

| Setting | Default | Effect |
| --- | --- | --- |
| `SpeedWalk` | 1.8 | Meters per second. Below this nothing happens at all. |
| `SpeedTrot` | 4.5 | Meters per second. At or above, NPCs are knocked down instead of staggered. |
| `SpeedGallop` | 8.5 | Meters per second. At or above, the knockdown uses full force. |
| `HorseFrontReach` | 1.05 | Meters ahead of the horse that count as contact. Lower to require a closer hit. |
| `HorseHalfWidth` | 0.35 | Meters to either side that count as contact. Lower if NPCs react when you ride past. |
| `HorseRearReach` | 0.20 | Meters behind the horse that count as contact. |
| `HitCooldownMs` | 3000 | Milliseconds before the same NPC can react again. Stops one person reacting repeatedly. |
| `Knockback` | 50.0 | Horizontal knockdown force, trot and gallop only. Higher throws them further. |
| `Uplift` | 30.0 | Vertical knockdown force, trot and gallop only. Higher throws them upward rather than along the ground. |
| `StaminaDrainTrot` | 45.0 | Stamina removed per NPC at a trot. Raise to be thrown sooner. |
| `StaminaDrainGallop` | 75.0 | Stamina removed per NPC at a gallop. Raise to be thrown sooner. |
| `StaminaDrainWalk` | 0.0 | Stamina removed per NPC at walking pace. |
| `CombatStaminaMultiplier` | 2.5 | Multiplies the drain values while you are fighting. 1.0 disables the combat penalty. |
| `ThrowRiderOnStaminaEmpty` | true | Whether an emptied horse throws you. False still drains stamina. |
| `SuppressStaggerInCombat` | true | Whether to skip the stagger during a fight. |
| `WalkStagger` | true | False gives vanilla behavior at walking pace, leaving knockdowns intact. |
| `ProtectMutt` | true | Whether your dog is immune. |
| `LogTelemetry` | true | Whether the mod writes diagnostics to `kcd.log`. |

A few more values sit in the file that are not listed here (`HitRadius`, `TickSeconds`,
`SweepMultiplier`, `MaxSweepExtra`, `HorseMaxVerticalDiff`, `SendHitReaction`). They are
internals for the detection and the collision bark, commented in place if you want them.

## Compatibility

- **Replaces `kcd_male_database.adb` and `wh_female_database.adb`.** Conflicts with any mod
  that edits human animations. Mannequin databases cannot be merged, only replaced, so
  whichever mod loads last wins outright and the other's changes vanish with no error.
- Also replaces `kcd_animationControlledTags.xml` and `wh_female_fragmentids.xml`.
- The replaced files are the game's own, with roughly 3 KB of added fragments. Everything
  else in them is byte-identical to vanilla 1.9.7.
- Does not touch AI behavior trees, quests, or RPG tables.

## Planned

Not promises, just what is being worked on next.

**Mass and momentum**

- Knockback scaled to what the target is wearing, so an unarmored peasant flies and a man in
  plate barely moves.
- Hitting a heavy target costs the horse its momentum, not just stamina.
- Stamina cost scaled to armor weight. Riding down a knight should be far more expensive than
  riding down a farmhand.

**RPG systems**

- Blunt damage and injuries from high-speed impacts.
- Horsemanship reducing stamina cost and the chance of being thrown.
- Horse barding increasing impact force.
- Bracing against a drawn polearm stopping a charge outright.

**AI reactions**

- Morale shock, so lightly armored enemies break and run after a charge through their line.

**Crime**

Right now nothing you do on a horse is ever a crime, which is convenient but wrong. Vanilla
already has most of the parts, including separate dialog lines for a light collision and a
heavy one, and its own handling for being ridden down by the player. The plan is to use them
rather than invent a parallel system.

- Severity scaled to speed. A bump at walking pace is a nuisance, trampling someone at a
  gallop is assault.
- Witnesses and location deciding whether anything comes of it, through the vanilla crime
  system rather than an instant bounty.
- Reputation damage for minor incidents, so being careless in a village costs you standing
  before it costs you money.
- Guards reacting differently from civilians, and reacting more strongly if you do it twice.

**Other**

- Reactions for dogs and other animals.
- A way to patch the animation data at install time instead of replacing it, so the mod stops
  conflicting with other animation mods.

## Repository layout

```
build.ps1                 the one build entry point
config.ld                 LDoc configuration for the API reference
src/
  HorseCollisionMod.lua   the mod
  mod.manifest
tools/
  build_adb.py            generates the animation data from a game install
  dev_deploy.ps1          installs into the game without Vortex
  dev_console.py          talks to the running game over its remote console
  publish_nexus.ps1       uploads a built release to the Nexus Mods page
docs/
  DEV_LOOP.md             the hot-reload development loop
  TECHNICAL_DETAILS.md    engine behavior worth knowing before changing things
  TESTING_DIARY.md        every build tested, what was expected, what happened
  api/                    generated Lua API reference (ldoc .)
```

`mod_assets/` and `releases/` are generated and not committed. Every script
resolves paths from the repository root, so they can be run from any directory.

## Build from source

Requires PowerShell and Python 3. LuaJIT is optional and adds a syntax check.

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "2.0.0"
```

Animation data is generated from your own game install rather than committed, so the first
build runs `tools/build_adb.py` for you. It finds the game automatically: `--game-root`, then the
`KCD_PATH` environment variable, then the usual Steam and GOG locations, then every Steam
library listed in `libraryfolders.vdf`. If none of those find it, it says so and lists
everywhere it looked.

Output goes to `releases\`. API reference, technical notes and the development log are in
`docs/`, and `docs/DEV_LOOP.md` covers the hot-reload tooling.

## Publishing a release

`tools/publish_nexus.ps1` uploads a built zip to the mod page through the Nexus Mods
v3 API, so a release does not have to go through the browser.

Once, to store your API key:

```
.\tools\publish_nexus.ps1 -SaveApiKey
```

Then per release:

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "2.1.0"
.\tools\publish_nexus.ps1 -Version 2.1.0 -DryRun
.\tools\publish_nexus.ps1 -Version 2.1.0 -ChangelogFile releases\notes-2.1.0.md
```

This is a release step, run by hand on a tagged version. It is not wired into
anything that runs on a push.

### The API key

`-SaveApiKey` prompts for the key and writes it to
`%LOCALAPPDATA%\HorseCollisionMod\nexus.cred`, encrypted with DPAPI under your
Windows account. That file is unreadable to other users on the machine and useless
if copied to another one, which covers how a key realistically leaks: a synced
folder, a backup, a shared machine, a stray `git add`. It lives outside the
repository so it cannot be committed at all.

What DPAPI does not defend against is code already running as you, which decrypts
it exactly as the script does. That is a reasonable trade for a mod upload key,
but it is a trade rather than the key being safe from everything.

`-ForgetApiKey` deletes it. Key resolution is `-ApiKey`, then `$env:NEXUS_API_KEY`,
then the stored file, so a single session can still override without touching what
is saved. Prefer the stored key to `setx`, which puts it in the registry as
plaintext, and to passing `-ApiKey`, which puts it in shell history.

`-DryRun` resolves and validates everything, then stops before uploading. Without it
the script prints what it is about to publish and asks you to type the version back
before anything reaches the live page.

Before uploading it checks that the version string is one the API accepts, that the
zip really is a mod release, that the version in the zip's `mod.manifest` matches the
one being published, and that the version is not already on the page. `-Force` skips
those and the confirmation prompt.

Two things the API cannot do, so they stay manual: creating a mod page, and editing
the mod description. Only files and changelogs are covered.

Deliberately not a GitHub Action. The build reads the game's own `Animations-part1.pak`
to generate `mod_assets/`, so it cannot run on a hosted runner that has no game
install. See `docs/TESTING_DIARY.md` for the full reasoning.

This uses a personal API key for personal use, which is what Nexus Mods permit them
for: one author publishing to one mod page, the key read from the environment at the
moment of use and stored by nothing. Every request identifies itself with
`Application-Name` and `Application-Version`, as their
[acceptable use policy](https://help.nexusmods.com/article/114-api-acceptable-use-policy)
requires. Turning this into a tool other people point at their own mod pages would make
it a public-facing application, which has to be registered with Nexus Mods first.

## API documentation

The doc comments in `src/HorseCollisionMod.lua` are standard LDoc, and `config.ld`
configures the project. Regenerate `docs/api/` with:

```
ldoc .
```

LDoc needs a C compiler to install, because it depends on penlight which depends
on luafilesystem. On Windows without one:

```
winget install BrechtSanders.WinLibs.POSIX.UCRT --scope user
luarocks install ldoc
```

The compiler is only needed for that install; `ldoc .` runs on its own afterwards.

## License

MIT. See `LICENSE`.
