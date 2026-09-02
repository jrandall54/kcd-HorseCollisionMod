# Horse Collision Mod

Vanilla horse collisions produce a shout and nothing else. This mod adds existing animations 
and physical reactions when Henry collides with NPCs while on horseback. The goal of this mod 
is to increase immersion by adding a feature that would feel right at home being included 
in vanilla. 

## What happens

| Speed | NPC | Horse stamina |
| --- | --- | --- |
| Walk, 1.8+ m/s | Staggers, stays on their feet, takes no damage | No cost |
| Trot, 4.5+ m/s | Knocked down, and hurt | -30 |
| Gallop, 8.5+ m/s | Knocked down harder, and hurt badly | -45 |

- The stagger is the game's own standing hit reaction, picked from the side you hit them on.
- Riding someone down hurts them, and enough of it kills. The damage is the game's
  own, from the speed the horse is carrying when it strikes, so a bump costs nothing
  and a full gallop costs a great deal.
- Because the game treats a rider's collision as the rider's doing, hurting or
  killing someone this way is a crime like any other, and guards respond to it.
- Armor decides how much the impact tires your horse. It does not reduce the damage,
  and it does not currently change how far someone is carried.
- If a collision empties your horse's stamina, it rears and throws you off.
- Horses have different stamina pools and it regenerates between impacts, so how many
  people you can put down depends on your horse and how fast you string hits together.
- In combat, stamina costs 2.5x and the walk-speed stagger is disabled. Knockdowns are
  unchanged.

## Requirements

Kingdom Come: Deliverance 1.9.7. The mod declares that version
and the game refuses to load it against any other.

## Install

Vortex, or extract the zip into `Kingdom Come - Deliverance\Mods\`.

## Settings

Settings live in their own file, `HorseCollisionMod_Settings.lua`, inside the
mod's pak. It contains nothing but the values below.

Install the mod, then edit the pak that is inside the mods folder. Opening the downloaded
zip and going into the pak inside it does not work.

1. Open the installed pak with 7-Zip or WinRAR, using **Open archive** rather
   than Extract:
   - installed by hand: `Mods\HorseCollisionMod\Data\HorseCollisionMod.pak`
   - installed by Vortex: right click the mod, **Open in File Manager**, then
     `Data\HorseCollisionMod.pak`. This is the staging copy, which is the one
     to edit; Vortex deploys by hard link, and an archive tool replaces a file
     rather than editing it in place, so editing the deployed copy under
     `Mods\` separates the two.
2. Go to `Scripts\Startup\` and open `HorseCollisionMod_Settings.lua`, not
   `HorseCollisionMod.lua`, which is the mod itself.
3. Change the values you want, keeping the `=` and the comma.
4. Save and close. When 7-Zip asks whether to update the archive, say yes.
5. On Vortex, run **Deploy Mods**.
6. Load a save.

A misspelled or mistyped setting is ignored and named in `kcd.log` rather than
breaking the mod. Deleting a line restores its default.

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
| `StaminaDrainTrot` | 18.0 | Stamina removed per NPC at a trot. Raise to be thrown sooner. |
| `StaminaDrainGallop` | 22.0 | Stamina removed per NPC at a gallop. Raise to be thrown sooner. |
| `StaminaDrainWalk` | 0.0 | Stamina removed per NPC at walking pace. |
| `CombatStaminaMultiplier` | 2.2 | Multiplies the drain values while you are fighting. 1.0 disables the combat penalty. |
| `ThrowRiderOnStaminaEmpty` | true | Whether an emptied horse throws you. False still drains stamina. |
| `TrotReaction` | "fall" | What a trot impact does. `"fall"` plays an animated fall the game recovers from, `"knockdown"` adds an animated get-up, `"ragdoll"` is the physics knockdown. |
| `CollisionIsCrime` | true | Whether riding someone down is a crime. Applies at trot and gallop, never at a walk. |
| `ReleaseAnimationMovement` | true | Keeps a reacting victim out of walls and out of sloped ground. False restores the behavior before 4.0.0. |
| `ReplanAfterReaction` | true | Whether a victim walks back to whatever they were using, which is what puts them straight with it again. |
| `SuppressStaggerInCombat` | true | Whether to skip the stagger during a fight. |
| `WalkStagger` | true | False gives vanilla behavior at walking pace, leaving knockdowns intact. |
| `ProtectMutt` | true | Whether your dog is immune. |
| `LogTelemetry` | true | Whether the mod writes diagnostics to `kcd.log`. |
| `Retaliation` | true | Whether a man shoved repeatedly at walking pace can lose patience and fight back. |
| `RetaliationFreeBumps` | 1 | How many walk impacts a victim tolerates before any chance of a fight begins. The first is always free. |
| `RetaliationChanceStep` | 0.25 | How much each further shove adds to the chance. |
| `RetaliationMaxChance` | 0.85 | The ceiling on that chance. |
| `RetaliationMemorySec` | 45 | How long a victim stays annoyed. Leave them alone for longer and the count resets. |
| `RetaliationFleeSpeed` | 3.5 | Meters per second that counts as running away rather than walking somewhere. |
| `RetaliationFleeIgnoreRange` | 25.0 | How far you must be before a running victim counts as a runaway. Running from someone stood over them is fair. |
| `RetaliationFleeSamples` | 8 | Seconds of sustained running, with you clear, before the mod steps in. |
| `RetaliationCeilingSec` | 120 | Failsafe. Stop watching an incident after this. |

A few detection internals are omitted here and commented in place in the file.

## Compatibility

Works alongside other animation mods. It replaces neither animation database,
referencing them instead, so there is nothing for another mod to overwrite or be
overwritten by. It does not touch AI behavior trees, quests or RPG tables.

`docs/HOW_IT_WORKS.md` explains how, and what the remaining limits are.

Upgrading from 2.x: delete the old version rather than installing over
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
CHANGELOG.md              what changed in each release
ROADMAP.md                what is planned, and what each phase established
config.ld                 LDoc configuration for the API reference
.luarc.json               Lua language server settings, including engine globals
.gitattributes            how files are stored, so line endings do not drift
src/
  HorseCollisionMod.lua            the entry point: the table, the settings it
                                   reads, and the parts it loads
  HorseCollisionMod_Settings.lua   the values a player edits
  HorseCollisionMod/               the rest of the mod, one file per concern,
                                   pulled in by the entry point
  mod.manifest
tools/
  build_adb.py            generates the animation data from a game install
  dev_deploy.ps1          installs into the game without Vortex
  dev_console.py          talks to the running game over its remote console
  typed_message_probe.lua a Lua probe run in the game through dev_console.py
  probe_stuck_actor.lua   reports nearby actors' animation state, to tell a
                          mod-driven animation apart from a vanilla one
  restore_alive.lua       returns nearby actors to the alive physicalization
                          profile, repairing one left in another
  probe_inventory.lua     names what a named entity is carrying, resolving
                          item class GUIDs to readable names
  probe_tables.lua        dumps a game table's columns and rows through
                          the Database bind
  publish_nexus.ps1       uploads a built release to the Nexus Mods page
  verify_additive.py      proves the release overrides no vanilla file
  version_check.py        derives the next version from CHANGELOG.md
  pre_release_check.py    finds claims the repository makes that are no
                          longer true
docs/
  HOW_IT_WORKS.md         plain-language overview of the mod and its layout
  DEV_LOOP.md             the hot-reload development loop
  TECHNICAL_DETAILS.md    engine behavior and the constraints on changing it
  ENGINE_BINDS.md         every Lua function the game exposes on the objects
                          this mod touches, from the engine's own registration
  TESTING_DIARY.md        every build tested, what was expected, what happened
  kcd_api.lua             engine API stubs, so the language server resolves them
  api/                    generated Lua API reference (ldoc .)
```

`mod_assets/` and `releases/` are generated and not committed. Every script
resolves paths from the repository root, so they can be run from any directory.

## Build from source

Requires PowerShell and Python 3.

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "3.0.0"
```

Animation data is generated from your own game install rather than committed, so
the first build runs `tools/build_adb.py` for you and resolves the game folder
itself. Output goes to `releases\`.

`docs/HOW_IT_WORKS.md` explains how the mod is put together, and
`docs/DEV_LOOP.md` covers the hot-reload development loop.

## License

MIT. See `LICENSE`.
