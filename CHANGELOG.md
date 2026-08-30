# Changelog

Notable changes to HorseCollisionMod. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For a mod, the public interface is the settings file, the install procedure and
the reactions a player sees in game. A change that forces a player to redo their
configuration, or that changes how the mod sits alongside other mods, is a major
change even when nothing about it looks like an API.

Entries land under `## [Unreleased]` as the work does, and move under a version
heading at release. An entry that breaks an existing install is marked
**BREAKING**. `tools/version_check.py` derives the next version from these
sections and refuses a release built at any other number.

## [Unreleased]

### Removed

- Three settings that no longer do anything useful: `MinVictimHealth`,
  `ClearCollisionInjuries`, and the `LimitCollisionExhaust` group. Each was an
  attempt at the problem where ridden-down NPCs stopped responding, and each was
  aimed at the wrong cause. That problem is now fixed at its source. A settings file still naming them keeps working; unknown
  settings are ignored and named in `kcd.log`.

### Changed

- A trot collision now knocks the victim down with an animation rather than a
  physics ragdoll. They fall, then get up, as one continuous movement, and the
  horse no longer runs over the body it just made. Set `TrotReaction` to
  `"ragdoll"` to restore the old behaviour. Gallop is unchanged and still
  ragdolls, which is what a horse at full speed should do.

### Fixed

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
