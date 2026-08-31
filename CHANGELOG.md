# Changelog

Notable changes to HorseCollisionMod. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For a mod, the public interface is the settings file, the install procedure and
the reactions a player sees in game. A change that forces a player to redo their
configuration, or that changes how the mod sits alongside other mods, is a major
change even when nothing about it looks like an API.

Entries land under `## [Unreleased]` as the work does, and move under a version
heading when the branch merges. An entry that breaks an existing install is
marked **BREAKING**. `tools/version_check.py` derives the next version from
these sections and refuses a build made at any other number.

Every merge to `main` takes a version and a tag, whether or not that build is
published, because `main` is always releasable and a merged version is
therefore stable. A prerelease suffix belongs to a build still being tested on
a branch, never to one that has landed. Publishing is a separate decision, made
against whatever version is current at the time, and it does not change the
number.

## [Unreleased]

## [4.1.0] - 2026-08-31

### Fixed

- Victims go back to what they were doing properly, instead of resuming it from
  wherever they fell. Anyone whose day is anchored to something, a merchant at a
  stall or a drinker leaning on a wall, would otherwise carry on at whatever
  angle the fall left them at, which showed as an innkeeper leaning into his
  wall from the wrong side. They now walk back to it, which is what sets their
  position and their facing.

### Added

- `ReplanAfterReaction` controls that, and is on by default.


## [4.0.1] - 2026-08-31

### Fixed

- NPCs no longer freeze where they fell and then jump somewhere else. An
  animated reaction hands a victim's body to the animation and their own
  behavior is never told, so the reaction ended with the body standing still
  while their thoughts carried on somewhere across the street. The two only
  rejoined when something forced the game to rebuild them, which in practice
  meant looking away and back. Affects 4.0.0, and is why victims sometimes
  appeared to teleport.

## [4.0.0] - 2026-08-30

Major because a trot collision no longer does what it did in 3.0.1, and what a
given speed does is part of this project's public interface. An existing
settings file still loads, which is a different test.

### Changed

- **BREAKING** A trot collision now knocks the victim down with an animation
  rather than a physics ragdoll. They fall, then get up, as one continuous
  movement, and the horse no longer runs over the body it just made. Set
  `TrotReaction` to `"ragdoll"` to restore the 3.0.1 behaviour. Gallop is
  unchanged and still ragdolls, which is what a horse at full speed should do.

- `MinVictimHealth`, `ClearCollisionInjuries` and the `LimitCollisionExhaust` group
  no longer exist. Each was an attempt at the problem where ridden-down NPCs
  stopped responding, and each was aimed at the wrong cause; that problem is
  now fixed at its source. None of them appeared in a released version, so no
  settings file in use names them; one that does keeps working, since an
  unrecognised setting is ignored and named in `kcd.log`.

- Collisions cost the horse far less stamina. Riding through ordinary foot
  traffic no longer threatens to throw you: a trot into a villager costs about
  six per cent of the pool where it cost twelve, and a gallop into an armored
  target during a fight no longer empties the pool in one impact. Charging
  armored targets is still expensive, and still much more so than charging
  peasants. `StaminaDrainTrot`, `StaminaDrainGallop` and
  `CombatStaminaMultiplier` carry the new defaults; a settings file that names
  them keeps whatever it sets.

### Fixed

- Staggering and falling victims stay out of walls and out of the ground. A
  reaction played beside a building could carry its victim into the wall,
  through it, or leave them standing inside it, and one played on a hillside
  buried them falling uphill and left them airborne falling downhill. Movement
  control is now taken off the animation once the reaction has started, so the
  victim is moved by the entity rather than by the animation's own root motion.
  Set `ReleaseAnimationMovement` to `false` to restore the old behaviour.

- Collisions no longer stop working after loading a save. Each victim is held
  briefly after an impact so a single pass through a crowd cannot restart the
  same reaction every frame. That wait was timed against a clock the save
  restores, so loading an earlier save left victims waiting for the length of
  the rewind, silently: nothing played, however many times they were ridden
  into. Waits are now discarded on load and any that outlast their own limit
  are ignored.

- Animals are no longer knocked down. A guard dog could be given a human
  knockdown animation, which cannot play on a dog. The check for whether a
  collision victim is a person accepted anything belonging to a faction, which
  dogs do; it now names the three human classes. Women reached the mod through
  that same fallback rather than by name, so this makes their handling
  deliberate rather than accidental.

- Getting up after a knockdown no longer twists the victim, which was also
  driving them through sloped ground. The recovery animation has to match the
  pose the fall ends in, and three of the four were paired wrongly; a get-up
  authored from the wrong side snapped the body round to reach its own starting
  pose.

- Knockback no longer varies with how hard the horse braked on contact. The
  same target could be thrown almost twice as far depending on how much speed
  the impact happened to scrub, which made the difference between armored and
  unarmored targets impossible to feel. Armor now decides it, as intended.

- NPCs no longer stand in the street playing a hurt animation after being ridden
  down. A victim knocked under 40 health while bleeding was being taken over by
  the game's own auto-cure behaviour, which holds them in place indefinitely
  while healing them at a rate too slow to notice. Victims are now exempted from
  it, using the same mechanism the game uses for its own characters, and an NPC
  already stuck is released the next time a rider collides with them, so an
  existing save repairs itself. The exemption is held until the victim's health
  has recovered past the point where the game would take them over, rather than
  for a fixed time, because a fixed window lapsed while victims were still
  below it.

### Added

- Impact telemetry. Each collision logs the victim's health at the moment of
  impact and again shortly after, so a reaction that looks wrong in game can be
  checked against what the hit actually cost. Written to `kcd.log` under the
  existing `LogTelemetry` setting.

## [3.0.1] - 2026-08-29

### Fixed

- The release archive stored its entries with Windows path separators, so the
  pak arrived as a single file named `Data\HorseCollisionMod.pak` in the mod
  root rather than a `Data` folder containing the pak, and the mod did not
  load. File Explorer treats the backslash as a separator and extracts the
  archive correctly, but the ZIP format requires forward slashes, and
  conforming tools including 7-Zip and Vortex extract one oddly named file. Affects 2.0.0 and 3.0.0. Reinstalling with this archive is
  the whole fix; nothing in the mod itself changed. The build now reads its own
  archive back and refuses to ship one whose entries contain a backslash.

## [3.0.0] - 2026-08-28

### Changed

- **BREAKING** Settings live in `HorseCollisionMod_Settings.lua`. Values edited
  in `HorseCollisionMod.lua` under 2.x are no longer read. Reapply any
  customization in the new file after upgrading.
- **BREAKING** The mod deploys additively and claims no vanilla filename. It carries a small
  database referencing the untouched vanilla one where it sits inside its own
  pak, instead of shipping a replacement copy. Download size drops from 195,284
  to 24,847 bytes, and mods that touch unrelated human animations no longer
  conflict.
- Collisions are scored on the peak speed of the last few detection ticks
  rather than on the speed sampled when a victim is noticed. A horse loses
  speed on contact, so the earlier reading was taken after the event it
  described.

### Fixed

- Reactions firing one tier too low, which reads in game as no reaction at all.
  A gallop impact scored as a walk played a stagger where a knockdown belonged.
- Gallop impacts reporting walking speed.
- Kneeling NPCs appearing to produce no reaction, which had the same cause.
- A horse that decelerates below walking pace on contact no longer loses the
  whole detection tick.

### Added

- `MaxImpactSpeed` caps the speed a collision is scored at, so a physics spike
  cannot inflate knockback force.
- `build.ps1` refuses a release build whose manifest, script constant and
  requested version disagree, or that ships with `DiagnoseMisses` enabled.

## [2.0.0] - Released

### Added

- Native stagger animations on walk-speed collisions, played through
  `StartInteractiveActionByName` against custom `AnimationControlled` FragTags.
- Horse stamina cost per impact, and the rider thrown when the horse is spent.
- `ProtectMutt`, which exempts Henry's dog from collisions.

## [1.2.0] - Released

### Added

- Speed-tiered collision reactions.

## [1.0.0] - Released

Initial release.
