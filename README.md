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

- **Replaces no vanilla file.** Every file the mod ships is named `hcm_*`, so there is
  nothing for another mod to collide with. It adds its animations by pointing the game
  at a small database of its own that references the untouched vanilla one.
- This is why it works alongside other animation mods. A mod that replaced
  `kcd_male_database.adb` would win or lose outright depending on load order, and the
  loser's changes would vanish with no error, because Mannequin databases cannot be
  merged.
- The one thing it does claim is the `AnimDatabase3P` property on seven human entity
  classes. Another mod redirecting the same property would still conflict, though that
  is a single value rather than a 5 MB file, and a cooperative mod can chain by
  referencing whatever is already there.
- Does not touch AI behavior trees, quests, or RPG tables.

Before 2.1.0 this mod did replace `kcd_male_database.adb` and `wh_female_database.adb`.
If you are upgrading, delete the old version rather than installing over it.
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
  publish_nexus.ps1       uploads a built release to the Nexus Mods page
  verify_additive.py      proves the release overrides no vanilla file
docs/
  HOW_IT_WORKS.md         plain-language overview of the mod and its layout
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
