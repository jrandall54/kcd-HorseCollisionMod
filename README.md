# Horse Collision Mod

Vanilla horse collisions produce a shout and nothing else. This adds a reaction
scaled to your speed, and a cost so it is not free.

> The reactions are the game's own animations.
> The thresholds were measured, not chosen.
> Every impact costs the horse something.
> Nothing vanilla is replaced that could be referenced instead.

## What happens

| Speed | NPC | Horse stamina |
| --- | --- | --- |
| Walk, 1.8+ m/s | Staggers, stays on their feet, takes no damage | No cost |
| Trot, 4.5+ m/s | Knocked down | -45 |
| Gallop, 8.5+ m/s | Knocked down harder | -75 |

- The stagger is the game's own standing hit reaction, picked from the side you hit them on.
- No crime or bounty. The mod does not fake an attack, so the crime system is never involved.
- If a collision empties your horse's stamina, it rears and throws you off.
- Horses have different stamina pools and it regenerates between impacts, so how many
  people you can put down depends on your horse and how fast you string hits together.
- In combat, stamina costs 2.5x and the walk-speed stagger is disabled. Knockdowns are
  unchanged.

## Requirements

Kingdom Come: Deliverance 1.9.7, the final build. The mod declares that version
and the game refuses to load it against any other.

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

A few detection internals are omitted here and commented in place in the file.

## Compatibility

Works alongside other animation mods. It replaces neither animation database,
referencing them instead, so there is nothing for another mod to overwrite or be
overwritten by. It does not touch AI behavior trees, quests or RPG tables.

`docs/HOW_IT_WORKS.md` explains how, and what the remaining limits are.

Upgrading from before 2.1.0: delete the old version rather than installing over
it, since it replaced files this one does not.

## Planned

Mass and momentum, so armor decides how far someone flies. Blunt damage and
injuries. Horsemanship reducing the chance of being thrown. Morale shock, so a
charge through a line breaks it. And crime, so that riding someone down in a
village is finally something the game notices.

`ROADMAP.md` has the detail.

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
  lint_docs.py            enforces docs/STYLE.md on prose and comments
  publish_nexus.ps1       uploads a built release to the Nexus Mods page
  verify_additive.py      proves the release overrides no vanilla file
docs/
  HOW_IT_WORKS.md         plain-language overview of the mod and its layout
  STYLE.md                documentation rules, enforced by tools/lint_docs.py
  DEV_LOOP.md             the hot-reload development loop
  RELEASING.md            building, publishing to Nexus, regenerating the API docs
  TECHNICAL_DETAILS.md    engine behavior worth knowing before changing things
  TESTING_DIARY.md        every build tested, what was expected, what happened
  api/                    generated Lua API reference (ldoc .)
```

`mod_assets/` and `releases/` are generated and not committed. Every script
resolves paths from the repository root, so they can be run from any directory.

## Build from source

Requires PowerShell and Python 3.

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "2.1.0"
```

Animation data is generated from your own game install rather than committed, so
the first build runs `tools/build_adb.py` for you and resolves the game folder
itself. Output goes to `releases\`.

`docs/HOW_IT_WORKS.md` explains how the mod is put together,
`docs/RELEASING.md` covers publishing, and `docs/DEV_LOOP.md` covers the
hot-reload development loop.

## License

MIT. See `LICENSE`.
