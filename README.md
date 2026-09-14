# Horse Collision Mod

Vanilla horse collisions produce a shout and nothing else. This mod gives them a
reaction scaled to your speed, a sound, damage that follows what the victim is
wearing, marks they carry afterwards, a cost to your horse, and two combat moves
of your own.

## What happens

| Speed | The victim | Your horse |
| --- | --- | --- |
| Walk, 1.8+ m/s | Staggers and stays up. No damage. | No cost |
| Trot, 4.5+ m/s | Knocked down by an animation, hurt. | Stamina cost |
| Gallop, 8.5+ m/s | Thrown by physics. Often fatal without armor. | Higher cost |
| Rear | Struck by the horse coming down. | Higher cost |
| Charge | Everyone in a corridor ahead is knocked down. | Highest cost |

- **Two moves on two keys.** `F` rears the horse on the spot and brings its hooves
  down on anyone in front. The charge is a rearing lunge that knocks down everyone
  ahead of the horse. The horse must be standing still to rear.
- **`Q` and `E` lean you out of the saddle** in first person, so the horse's head
  stops hiding what you are about to ride into.
- **Damage follows what the victim wears.** An unarmored villager rarely survives a
  full gallop. A man in plate mostly walks away.
- **Collision kills are yours or not, as you choose.** Trampling someone to death is
  a crime and guards respond, unless you turn that off, in which case it genuinely
  is not charged to you.
- **Your Horsemanship decides what an impact costs your horse.** Early on a single
  gallop can empty its stamina; the cost falls as the skill rises. Barding adds
  damage and eases the stamina cost.
- **If a collision empties your horse's stamina it rears and throws you off**, and
  may wander off rather than wait to be remounted.
- **Victims speak.** A shove gets a complaint. A knockdown gets a cry of pain and
  then words while they get back up. Henry grunts when the collision goes through
  him, and has something to say when one kills somebody.
- **Shove the same person too often and they fight back.** They drag you out of the
  saddle first, and you can yield instead of killing them. The brawl itself is not a
  crime. Women raise the alarm rather than fighting.
- **They carry the marks.** Dirt and blood on the side the horse struck, which build
  up and wear off once their own routine takes them home.
- **The impact lands on you too.** Camera kick at a gallop, a brief blur in first
  person, and dust off the ground where a body lands.
- **In combat every stamina cost is multiplied**, and the walk stagger is skipped.
  Knockdowns are not.
- Your dog is never affected.

## Requirements

Kingdom Come: Deliverance 1.9, any patch.

## Install

Vortex, or extract the zip into `Kingdom Come - Deliverance\Mods\`.

Upgrading: delete the old version rather than installing over it. Settings you
changed carry over, and anything this version no longer recognizes is ignored
rather than breaking.

Upgrading from 4.x: the charge is its own kind of impact now, with its own damage,
stamina cost and reach, so numbers you tuned through the gallop settings no longer
describe it. The rear on the spot moved to `F`, because leaning took `Q` and `E`.

## Settings

Settings live in their own file, `HorseCollisionMod_Settings.lua`, inside the
mod's pak. The ones worth changing are listed below. The file holds more than
this, grouped at the bottom under a warning on each group: internals, and timings
measured against an animation, where the shipped value is the only sensible one.

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
| `HorseHalfWidth` | 0.70 | Meters to either side that count as contact. Lower if NPCs react when you ride past. |
| `HorseRearReach` | 0.20 | Meters behind the horse that count as contact. |
| `HitCooldownMs` | 3000 | Milliseconds before the same NPC can react again. Stops one person reacting repeatedly. |
| `Knockback` | 50.0 | Horizontal knockdown force, trot and gallop only. Higher throws them further. |
| `Uplift` | 30.0 | Vertical knockdown force, trot and gallop only. Higher throws them upward rather than along the ground. |
| `RagdollDampSettleSpeed` | 0.5 | The speed a thrown body must drop under, in meters per second, before the mod settles it so it stops sliding. Settling it while it is still traveling cuts the throw short. |
| `RagdollDampFloorMs` | 200 | The earliest a body may be settled, in milliseconds, so it cannot happen mid-launch. |
| `RagdollDampCeilingMs` | 6000 | The latest, applied whatever the body is doing. |
| `RagdollDampPollMs` | 100 | How often a thrown body is looked at. |
| `StaminaDrainByTier` | Walk 0, Trot 14, Gallop 22, Rear 12, Charge 22 | What each kind of impact costs the horse. Raise a figure to be thrown sooner. A rear and a charge are charged once for the move rather than once per person. |
| `CombatStaminaMultiplier` | 2.2 | Multiplies the drain values while you are fighting. 1.0 disables the combat penalty. |
| `ThrowRiderOnStaminaEmpty` | true | Whether an emptied horse throws you. False still drains stamina. |
| `ReactionByTier` | Walk stagger, Trot fall, Gallop ragdoll, Rear fall, Charge ragdoll | What each impact does to the victim's body. `"stagger"` and `"knockdown"` play an animation, `"fall"` plays one that hands the body to physics partway through and is the only one that gives a victim their activity back, `"ragdoll"` drops them on contact. |
| `ThrowByTier` | Gallop 1.0, Charge 0.7 | How hard each ragdoll tier throws. Only tiers set to `"ragdoll"` above use it. |
| `CollisionIsCrime` | true | Whether riding someone down is a crime. Applies at trot and gallop, never at a walk. |
| `ReleaseAnimationMovement` | true | Keeps a reacting victim out of walls and out of sloped ground. False restores the behavior before 4.0.0. |
| `ReplanAfterReaction` | true | Whether a victim walks back to whatever they were using, which is what puts them straight with it again. |
| `SuppressStaggerInCombat` | true | Whether to skip the stagger during a fight. |
| `WalkStagger` | true | False gives vanilla behavior at walking pace, leaving knockdowns intact. |
| `ProtectMutt` | true | Whether your dog is immune. |
| `HitCooldownStateDriven` | true | Whether the wait after a knockdown reads the victim's own animation state instead of counting. A victim standing up cannot be knocked down again by anything, so hitting them costs health with no visible reaction. |
| `HitReadySettleMs` | 250 | How long a victim must be neither animation-driven nor ragdolling before another impact counts. |
| `HitReadyCeilingMs` | 6000 | Failsafe, for a victim never seen busy at all. |
| `Horsemanship` | true | Whether the rider's `horse_riding` skill changes what a collision costs. A novice is thrown by a single gallop impact; a master rides through four or five guards. |
| `HorsemanshipStaminaWorst` | 10.0 | The horse's stamina cost multiplier at skill 0. |
| `HorsemanshipStaminaBest` | 1.2 | And at skill 20. |
| `HorsemanshipSeatChance` | 0.6 | Chance of keeping the saddle when the horse is spent, at skill 20. |
| `Barding` | true | Whether the horse's own barding changes what a collision does. Barding is the horse's armor, not its tack: a saddle, bridle and shoes count for nothing. |
| `BardingFullSmashDef` | 1.45 | The total `smash_def` treated as a full set of barding. Everything below scales from nothing on a bare horse to its figure here. |
| `BardingStaminaRelief` | 0.25 | How much less stamina an impact costs a fully barded horse. The half of barding you actually feel: one more guard ridden down before the horse is spent. |
| `BardingDamageBonus` | 0.15 | How much harder a fully barded horse hits. |
| `BardingForceSteps` | five steps | What barding adds to the knockdown force, as a list of `{ coverage, added to Knockback, added to Uplift }`. No barding adds nothing, a fifth of a full set adds a fifth of the bonus, and a full set adds all of it. At the top that is 5.0 on a `Knockback` of 50 and 3.0 on an `Uplift` of 30. |
| `HorseBoltsWhenSpent` | true | Whether a horse that has thrown a spent rider may leave rather than wait. |
| `HorseBoltChance` | 0.4 | How often it does. |
| `CameraShake` | true | Whether an impact kicks the rider's camera. |
| `CameraShakeAngle` | 4.0 | Degrees of shake at a gallop. |
| `CameraShakeShift` | 0.08 | Meters of shake at a gallop. |
| `CameraShakeDurationSec` | 0.5 | How long it lasts at a gallop. |
| `CameraShakeFrequency` | 0.05 | Shake period. Vanilla's own shakes use 1/20 to 0.5; large values do nothing. |
| `CameraShakeByTier` | Trot 0.6, Gallop 1.0, Rear 0.8, Charge 1.2 | The fraction of the shake each impact gets. A tier left out does not shake the camera at all. |
| `RiderBlur` | true | Whether an impact blurs the rider's view. First person only, because third person can already see the collision. |
| `RiderBlurAmount` | 1.0 | How heavy the blur is. Values above about 1.0 are discarded by the engine. |
| `RiderBlurHoldMs` | 260 | How long it holds before decaying. |
| `RiderBlurChroma` | 0.2 | A chromatic shift on the same envelope. Past about 0.5 it tints the screen red. |
| `RiderBlurMs` | 480 | How long the decay takes. |
| `RiderBlurByTier` | Trot 0.7, Gallop 1.0, Rear 0.6, Charge 1.1 | The fraction of the blur strength each impact gets. |
| `RiderBlurLengthByTier` | Trot 0.3, Gallop 1.0, Rear 0.4, Charge 1.1 | The fraction of the blur timing each impact gets. |
| `ImpactDamageDelayMs` | 600 | How long the mod waits, in milliseconds, before charging the victim for the impact. The engine applies trample damage of its own for a collision and attributes it to you; waiting lets that land first so the mod delivers the killing blow. That decides whether guards treat a death as murder or as a corpse nobody is blamed for, and so it is what makes `CollisionIsCrime` mean anything. Set to 0 to charge immediately. |
| `ImpactDust` | true | Whether a collision throws dust off the ground where the victim lands. |
| `ImpactDustEffect` | "WH_Particels.other.explosion_dust" | The particle library node to spawn. |
| `ImpactDustEffectRear` | "collisions.destructibles.arrow_soil" | The node a rear spawns instead. A rear is a standing blow, so it gets a short, punchy effect rather than the lingering cloud a gallop throws up. |
| `ImpactDustScaleByTier` | Trot 0, Gallop 0.09, Rear 0.6, Charge 0.10 | Size of the dust each impact raises. Zero switches that tier's dust off. The rear figure is larger because the effect it scales is a different one. |
| `ImpactSound` | true | Whether a collision makes a noise. |
| `ImpactSoundDistance` | 2.0 | Master level for trot and gallop, in meters. Higher is quieter. The listener follows the camera, so a third-person camera mod hears the mix from further away and will want this lower. |
| `ImpactSoundByTier` | layered | The sound each impact makes, one list per tier, each layer `{ trigger, delay ms, distance, chance }`. Distance is the volume control: higher is quieter. |
| `ImpactSoundCrack` | layered | An occasional injury layer, gallop only. |
| `ImpactSoundCrackChance` | 0.12 | How often a gallop adds it. |
| `VictimMarks` | true | Whether a knockdown leaves dirt and blood on the victim. Nothing is applied at walking pace. |
| `VictimDirtByTier` | Trot 0.35, Gallop 0.60, Rear 0.35, Charge 0.60 | Dirt added to everything the victim is wearing, 0 to 1. 0 switches it off. |
| `VictimBloodByTier` | Trot 0.15, Gallop 0.45, Rear 0.15, Charge 0.45 | Blood added to the side of the body the impact struck, 0 to 1. 0 switches it off. |
| `LogTelemetry` | true | Whether the mod writes diagnostics to `kcd.log`. |
| `Rear` | true | Whether your horse can be reared on command. Only from a standstill. |
| `RearChargeKey` | "r" | Which key rears the horse and drives it forward, riding down whoever is in the way. One of r, q, e, f, y, u, o, h. |
| `RearOnlyKey` | "f" | Which key rears on the spot, bringing the hooves down on anyone right in front. Same list. |
| `RearMaxSpeed` | 0.15 | Horizontal speed above which a rear is refused. A rear is a standing attack: a horse still moving when it starts slides about 0.12 m before the animation takes hold. |
| `RearIdleOnly` | true | Also require the horse's own locomotion state to be idle, which catches slow drift a speed reading misses. |
| `RearCooldownMs` | 2500 | How long before another rear is accepted. |
| `Lean` | true | Whether Q and E lean the camera out to either side, so you can see past the horse's head in first person. |
| `LeanLeftKey` | "q" | Which key leans left. One of r, q, e, g, y, u, o, h. |
| `LeanRightKey` | "e" | Which key leans right. Same list. |
| `LeanDistance` | 0.65 | How far out the camera goes and holds, in meters. |
| `LeanForwardShare` | 0.35 | How much the lean also carries the camera forward, as a fraction of the sideways travel. 0 leans straight out. |
| `RearReach` | 2.5 | How far in front the hooves reach, for the rear on the spot. |
| `RearArc` | 70 | The arc in front that counts, in degrees. |
| `Retaliation` | true | Whether a man shoved repeatedly at walking pace can lose patience and fight back. |
| `RetaliationFreeBumps` | 1 | How many walk impacts a victim tolerates before any chance of a fight begins. The first is always free. |
| `RetaliationChanceStep` | 0.25 | How much each further shove adds to the chance. |
| `RetaliationMaxChance` | 0.85 | The ceiling on that chance. |
| `RetaliationMemorySec` | 45 | How long a victim stays annoyed. Leave them alone for longer and the count resets. |
| `RetaliationCeilingSec` | 120 | Failsafe. Stop watching an incident after this. |
| `RetaliationPullsRiderDown` | true | Whether a victim who has run out of patience drags you out of the saddle before fighting, rather than swinging at the horse. |
| `PullDownPollMs` | 250 | How often he looks for the chance to do it. |
| `PullDownRepeatMs` | 1500 | How often he asks again once he has, until you are down. |
| `PullDownCeilingMs` | 8000 | How long he tries before giving up and simply fighting. |
| `PullDownForce` | false | Ask for the pull-down even when the game says the victim cannot do it. Some NPCs are simply not eligible and this does not change that; it exists for future investigation. |
| `RetaliationSurrenderHint` | true | Whether the on-screen surrender prompt is shown while a provoked victim is fighting you. Surrendering already worked; nothing told you so. |
| `SurrenderHintHoldMs` | 1000 | How often the prompt is put back, since the HUD drops it when you are pulled off the horse. |
| `SurrenderHintCalmPasses` | 3 | Quiet passes before the prompt gives up, a fallback against the combat reading blinking mid-fight. It normally goes when the last provoked fight ends. |
| `SurrenderHintYieldsToGame` | true | Guards get the game's own surrender prompt for an arrest, so the mod raises none for them. |
| `ProvokeDuringCombat` | false | Whether someone can be newly provoked while you are already in a fight. Off, because a person running into your stationary horse mid-brawl otherwise becomes another attacker. |

A few detection internals are omitted here and commented in place in the file.

## Compatibility

Works alongside other animation mods. No vanilla file is replaced or renamed. AI
behavior trees, quests and RPG tables are untouched.

The one conflict left is another mod pointing the same NPC classes at a different
animation database, which is uncommon.

## Planned

Injuries that outlast the impact. Making how bad a collision was easier to read.
Morale, so a charge through a line breaks it. A braced polearm stopping a charge.

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
  flow.ps1                the session's states: test, branch, land, shipping
  dev_deploy.ps1          installs into the game without Vortex
  bark_chain.py           walks a bark set from metarole to role to topic to
                          sequences, showing each line with its cooldown, so
                          what a speaker will say and when they run dry is
                          readable without the game
  bark_lines.py           prints the English text of any vanilla bark set, and
                          searches by remembered words for the set holding a
                          line, without starting the game
  bark_alias.py           prints any topic addressable by alias with its lines,
                          speakers and word counts, the alias namespace being
                          the label column of topic.xml
  henry_impact_lines.py   every line Henry can actually be made to say, with the
                          full text of every member of each set, filtered to
                          those whose sequence is always-true, repeatable, and
                          recorded by his actor alone
  npc_pain_sets.py        every NPC bark set whose sequences are all
                          unconditional, with its wordless count and longest
                          line, for choosing the register of a reaction
  dev_console.py          talks to the running game over its remote console
  dev_subject.lua         spawns a test subject in front of the horse
  restore_alive.lua       returns nearby actors to the alive physicalization
                          profile, repairing one left in another
  probe_inventory.lua     names what a named entity is carrying, resolving
                          item class GUIDs to readable names
  probe_tables.lua        dumps a game table's columns and rows through
                          the Database bind
  probe_health.lua        logs one entity's health whenever it changes, for
                          the case where health moves with no impact to
                          account for it
  probe_recovery_states.lua  samples everything an actor exposes, from an
                          impact until they stand again, so a trigger can be
                          tied to a measured posture rather than a timer
  dev_peace.lua           stops the world reacting to the player, so a test
                          that kills someone is not also a test of a fight
  dev_target.lua          puts a pinned test victim four meters in front of
                          the rider, so a ride is not also a search for
                          someone standing usefully
  dev_survival.lua        holds the player's nourishment and energy at 100,
                          so a test needing game time is not also a test of
                          finding food in hardcore
  dev_time.lua            moves game time forward without the wait dialog,
                          through the Calendar global
  dev_horse.lua           hands the player a rideable horse, taken from the
                          horse traders' stable data
  dev_barding.lua         puts a set of barding on the player's horse, so the
                          barding impulse multiplier can be judged
  dev_watchfight.lua      samples everyone near the player once a second, with
                          the player alongside them, so a fight reads as one
                          timeline rather than an impression
  probe_api.lua           lists the methods an object actually exposes in the
                          running game, which the written references do not
  probe_bark.lua          asks whether a vanilla spoken line can be triggered
                          from Lua, using metaroles the speaker provably holds
  probe_camera.lua        polls the first-person camera through a view shake,
                          which is the only way to see what that call does
                          rather than what its arguments suggest
  probe_horse_mass.lua    reports the mass and physics identity of the horse,
                          the player and the nearest NPC, which are the two
                          sides of every collision the mod scores
  nexus_settings_block.py builds the mod page's settings block out of the
                          settings file, so the page cannot fall behind what
                          ships; --check reports what it is missing
  publish_nexus.ps1       uploads a built release to the Nexus Mods page
  verify_additive.py      proves the release overrides no vanilla file
  audit_code.py           reports settings nothing reads, settings missing from
                          the player's file, and functions and tables nothing
                          uses, so clutter is a fact rather than an impression
  legacy/                 tools from investigations that are closed, kept rather
                          than deleted because a probe already written costs
                          nothing to keep and rebuilding one costs a whole
                          working session. Nothing in here is maintained and
                          none of it is checked: a moved Python tool may need
                          the tools directory on sys.path before it can import
                          bark_lines, and a probe may name an engine call since
                          ruled out. Read the header first, which says what the
                          probe was for and what it found
  set_version.py          writes the version into all fourteen places that
                          carry it, and dates the changelog section
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
