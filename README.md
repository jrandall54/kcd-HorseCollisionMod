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
  that edits human animations. Mannequin databases cannot be merged, only replaced.
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

## Build from source

Requires PowerShell and Python 3. LuaJIT is optional and adds a syntax check.

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "2.0.0"
```

Animation data is generated from your own game install. Output goes to `releases\`.
API reference, technical notes and development log are in `docs/`.

## License

MIT. See `LICENSE`.
