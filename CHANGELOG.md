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

### Fixed

- A man you fought is no longer ruined for good. A victim came out of a brawl
  at a relationship of 0.0, against roughly 0.5 for a healthy villager, and
  below vanilla's 0.2 threshold he decided to run again every time he saw you
  afterwards, across save loads and days of game time. Every provoked fight
  now ends by restoring what he thought of you before you provoked him, so he
  goes back to work and will talk and trade with you again. It restores rather
  than rewards: he is put back to what he thought of you less a standing cost
  for the fight, so beating a man cannot leave him thinking better of you than
  his untouched neighbors do, and he is checked a second time once you have
  finished with him in case he lost more on the way.

### Changed

- The retaliation watcher is simpler and closes an incident when the fight
  actually ends. It used to sort a victim into fighting, running away or
  settled, and treat running as a separate case needing its own rescue, but
  the test for it required you to be 25 m clear before it counted, which never
  happens while you are chasing him: it fired in none of six measured
  incidents. Running is now simply the fight being over, which closes the
  incident within three seconds and hands him to the same repair as any other
  ending. `RetaliationFleeSpeed`, `RetaliationFleeIgnoreRange` and
  `RetaliationFleeSamples` are gone with it. They were added in 4.6.0 and no
  published version has ever carried them, so no existing configuration
  changes; an unrecognized setting is ignored and named in `kcd.log` as
  always.

## [4.7.3] - 2026-09-03

### Fixed

- A provoked victim now actually fights. Since the feature shipped he would
  square up, raise his guard and never throw a punch unless the player swung
  first, because a civilian struck by someone who is not already an enemy
  enters the fight in defense only and one message in the whole combat tree
  turns offense back on. That message is now sent once he reaches the fight,
  naming him as his own attacker so it costs no health, no reputation and no
  crime: a bystander sampled through the change moved 0.000, where naming the
  player moved the victim -0.31 and everyone nearby -0.030.

## [4.7.2] - 2026-09-03

### Fixed

- The detection corridor was 0.70 m wide against a horse that is wider than
  that, so bodies struck against the flank were rejected: the engine still
  damaged them, and the mod never registered the hit to suppress vanilla's
  auto-cure daycycle, which stood the victim in the street replaying
  `PretendingIllness` once their health passed below 40. `HorseHalfWidth` is
  now 0.70, wide enough to catch the whole documented cluster of flank
  contacts and still reject people the horse passes with real clearance.

## [4.7.0] - 2026-09-02

### Added

- Armor is now felt in the collision, not only in the horse's stamina. A man
  in mail is harder for a horse to move than a villager in cloth and lands
  about half as far away: measured six-second throws are 1.92 m against
  4.19 m, where the shipped mod threw armored victims 45% *further* than
  unarmored ones. Two settings control it. `RagdollMass` is what the horse
  collides with in kilograms, replacing the engine's flat 80 for every human,
  and `RagdollMassArmorExponent` divides that by the armor scale raised to a
  power. The exponent sets how far apart the two land and the base sets how
  far everyone travels; `docs/TECHNICAL_DETAILS.md` explains why lowering the
  base is tempting and where it stops working.

## [4.6.3] - 2026-09-02

### Changed

- Research and tooling only. Nothing about a collision looks or behaves
  differently. A survey of a shipped pure-Lua cheat mod, verified against the
  running game, overturned five findings this project had recorded as
  unreachable, and settled why a beaten NPC keeps fleeing: a punch sets a
  hostility flag that only a reputation change carrying
  `can_change_hostility` can clear, which is why surrendering to a victim
  repairs him and paying a fine never does. Two long-blocked roadmap items,
  forcing a brawl to fists and making knockback mean something, are now
  verified as buildable.

## [4.6.2] - 2026-09-02

### Changed

- Development tooling only. Nothing about a collision looks or behaves
  differently.

## [4.6.1] - 2026-09-02

Research only. Nothing about a collision looks or behaves differently.

### Changed

- The consequences of assaulting an NPC are recorded, along with what is
  still unknown about them. Punching someone lowers their own relationship
  with the player and nobody else's, capped so a second punch costs nothing
  further; an unsettled crime depresses the whole town at once and lifts
  afterwards; and 0.2 is the threshold below which an NPC stops dealing with
  the player, which the game's own `payToTalk` remedy exists to lift them
  over. None of it is caused by this mod: the measurements were taken on
  foot, the last of them with every mod file parked.

## [4.6.0] - 2026-09-02

### Added

- Victims lose patience. Barging the same man at a walk used to cost nobody
  anything; now each shove is counted, and past the first one every further
  shove rolls against a growing chance that he turns and fights. `Retaliation`,
  `RetaliationFreeBumps`, `RetaliationChanceStep`, `RetaliationMaxChance` and
  `RetaliationMemorySec` control it, and setting `Retaliation` to false
  restores the old behavior.
- A provoked fight is not a crime. No fine is levied and no guard is summoned
  for the provocation, because the message that starts it never reaches the
  reputation system. A charge appears only if you swing, and only if somebody
  sees it. Guards who witness the brawl still wade in, which is the game
  deciding rather than this mod. Faction reputation was measured across a
  full provoked brawl and did not move.
- A guard provoked the same way arrests rather than brawls. That is the
  game's own rule for soldiers, kept deliberately.
- Women do not fight back. The game refuses them the fight branch outright.
- The brawl ends when the victim's own state says it has, never on a timer.
  Usually the game resolves the encounter itself and the mod does nothing;
  only a victim who leaves the fight and keeps running, with the rider well
  clear, is told to stand down and sent back to work.
  `RetaliationFleeSpeed`, `RetaliationFleeIgnoreRange`,
  `RetaliationFleeSamples` and `RetaliationCeilingSec` tune that.

## [4.5.1] - 2026-09-02

Research only. Nothing about a collision looks or behaves differently.

### Changed

- The retaliation research is settled and recorded. Trampled non-guards
  already flee to report the crime; faction angriness turns out to be inert
  as a hostility switch; and the game's context system, which vanilla quests
  drive from Lua, carries an `alwaysFightWhenHit` option that makes a victim
  fight back instead. A `combat:hit` sent with `real = false` drives that
  fight without any reputation or crime consequence, which is what a brawl
  over a shove needs.
- A polearm guard taking no walk stagger is recorded as an open question.

## [4.5.0] - 2026-09-01

### Added

- `RagdollDamping` and `RagdollMinEnergy` control how quickly a thrown body
  sheds speed and comes to rest.
- `ImpulseDelayMs` controls how long the mod waits for a body to become a
  physics object before pushing it. An impulse applied before that is
  ignored by the engine without reporting anything.
- `LateralImpulse` pushes a victim across the horse's line of travel rather
  than along it. Off by default.

### Changed

- A victim thrown by a collision no longer slides for meters after landing.
  They travel a little over a meter after coming down, against nearly three
  before, and where they end up is far more consistent from one impact to
  the next. The sliding had been there since 1.0.

## [4.4.5] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The `TraceRecovery` diagnostic also measures how far a victim turns during a recovery, and names any weapon they are holding.

## [4.4.4] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The `TraceRecovery` diagnostic also reports which system owns a
  victim's body at each step, not only what animation is playing.
  Off by default, as before.

## [4.4.3] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- A woman knocked down at a trot is handed to physics earlier in her fall, which makes the fall itself read better. Men are unchanged.
- A new `TraceRecovery` setting, off by default, times every animation state a recovering victim passes through and writes the sequence to the log.

## [4.4.2] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- A victim knocked down at a trot no longer snaps into a different activity about half a second after standing up. Carried items are no longer dropped and NPCs no longer change direction in a single frame. Beggars and innkeepers, who cannot recover on their own, are still returned to what they were doing, and now immediately rather than after a delay.

## [4.4.1] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The armor weights are read from the game's own item tables at runtime instead of from a 50 KB table generated at build time and shipped with the mod. The weights are unchanged; the download is 27 percent smaller.

## [4.4.0] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently, but the
set of files the mod installs has changed.

### Added

- Ten script files under `Scripts/HorseCollisionMod/`, which the mod now
  installs alongside the two in `Scripts/Startup/`. They are loaded by the
  entry point rather than by the engine, so they must be installed
  together; a pak carrying only the Startup scripts no longer contains a
  working mod.

### Changed

- The detection loop moved out of the entry point into
  `Scripts/HorseCollisionMod/Update.lua`, completing the split begun in
  4.3.2. The entry point is 569 lines, from 2,558, and holds the settings
  table, the state it keeps between ticks and the startup sequence; the
  behavior lives in the ten part files.

## [4.3.10] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The horse stamina cost and the dismount when the horse is spent moved out of the entry point into `Scripts/HorseCollisionMod/Rider.lua`.

## [4.3.9] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The combat hit that makes riding someone down a crime moved out of the entry point into `Scripts/HorseCollisionMod/Crime.lua`.

## [4.3.8] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- Victim recovery, the ragdoll and reaction waits and the replan moved out of the entry point into `Scripts/HorseCollisionMod/Recovery.lua`.

## [4.3.7] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The brain message, the reaction animation and the physics ragdoll moved out of the entry point into `Scripts/HorseCollisionMod/Reaction.lua`.

## [4.3.6] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- Health probing, the impact-cost samples and the auto-cure suppression moved out of the entry point into `Scripts/HorseCollisionMod/Health.lua`.

## [4.3.5] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The footprint test and the impact direction lookup moved out of the entry point into `Scripts/HorseCollisionMod/Detection.lua`.

## [4.3.4] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- Logging, the speed history and the speed tier moved out of the entry
  point into `Scripts/HorseCollisionMod/Log.lua`. The engine clock and
  vector length became methods on the mod's table, since the file-locals
  they replaced could not be reached from another file.

## [4.3.3] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The armor lookup and the curves that turn armor weight into an impulse
  and a stamina multiplier moved out of the entry point into
  `Scripts/HorseCollisionMod/Armor.lua`.

## [4.3.2] - 2026-09-01

Internal. Nothing about a collision looks or behaves differently.

### Changed

- The mod's Lua is no longer one file. The entry point in
  `Scripts/Startup/` creates the table and names the parts it wants; the
  parts live in `Scripts/HorseCollisionMod/` and are pulled in with
  `Script.ReloadScript`, the same mechanism the base game uses to compose
  its own scripts. The engine enums are the first section moved.

## [4.3.1] - 2026-08-31

Internal. Nothing about a collision looks or behaves differently.

### Changed

- A trot victim is handed to physics by the animation itself rather than by a
  timer in the mod. The timing now sits beside the clip it belongs to, so the
  mod no longer has to know how long any of the game's animations run for.

## [4.3.0] - 2026-08-31

### Added

- Riding someone down is a crime. A witness calls for help, guards respond, and
  surrendering gets you fined; killing someone is charged as murder, which the
  game already did on its own. It applies at trot and gallop, where the impact
  hurts, and never at a walk. `CollisionIsCrime` turns it off.

  The game charges it as a brawl. Its crime system has no concept of being
  ridden down, and vanilla makes the same substitution for a player-ridden
  collision, so this is the game's own compromise rather than a choice made
  here.

## [4.2.11] - 2026-08-31

Diagnostics. The mod behaves exactly as 4.2.10 does.

### Changed

- Impact telemetry records what the victim was doing when the horse reached
  them. Every reaction is a standing animation, so an impact on someone
  already down plays nothing and usually costs no health; without this, an
  impact that cost nothing by design was indistinguishable in the log from one
  that failed.

## [4.2.10] - 2026-08-31

Documentation. The mod is unchanged from 4.2.1.

### Changed

- The rebuild blink is no longer a parked issue. It belonged to the animated
  get-up, where the rebuild landed on a standing victim; the trot tier hands
  the body to physics during the fall and the blink went with it.


## [4.2.9] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- The note about the public pages lagging is beside the call it describes.
  4.2.8 recorded it in this file only, which is not where anyone reading the
  publish path would look for it.


## [4.2.8] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- Records that a posted changelog reaches the author's own management view
  immediately and the public pages later. Its absence from the mod page is not
  evidence the call failed, which is what an investigation concluded twice.


## [4.2.7] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- 4.2.6 recorded that the changelog endpoint refuses this tool's requests. It
  does not. The 413 and 502 behind that claim came from a hand-written probe
  sending different headers and a hand-rolled body, not from the publish path,
  which posts successfully. The claim is retracted from the changelog and from
  the tool's own comments.

- The warning that a repeated call appends is stated where it matters. Calling
  the changelog path twice for one version leaves two entries on the tab and
  there is no API to remove either.


## [4.2.6] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- `-ChangelogOnly` works. The switch was referenced but never declared, so it
  was rejected as an unknown parameter, and the path it guards looked for the
  notes file at a path containing a newline. Both passed a syntax check: an
  undeclared variable and a multi-line string are valid PowerShell.

- A refused changelog no longer looks like a success. The call is reported
  rather than thrown, since the file is published by then and losing that to a
  changelog would be the wrong trade.

## [4.2.5] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- A release can no longer publish with an empty changelog. The upload field is
  optional and nothing looked for it, so 4.2.2 went out with none. Publishing
  now reads `releases/notes-<version>.md` without being asked, the way it
  already found the Files tab entry, and the pre-release check refuses a
  release that has no notes written.

### Added

- `publish_nexus.ps1 -ChangelogOnly` posts the changelog for a version already
  on the page. The call is additive and independent of the upload, so a release
  published without one is repaired rather than re-uploaded.


## [4.2.4] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- Publishing checks the version being published rather than the one the
  manifest happens to sit on. A release that has been played from its own pak
  is the one that goes out, and `main` may have moved on to tooling since, so
  the check reported the mod page as stale for a version nobody was publishing
  and refused to publish one that was correctly described.


## [4.2.3] - 2026-08-31

Tooling. The mod is unchanged from 4.2.1.

### Fixed

- The check that proves a release overrides no vanilla file could not run. It
  read a table renamed when the mod grew past the walk tier, so it raised an
  error instead of checking anything, and had done since. It now verifies every
  reaction option and every clip both character sets reference.


## [4.2.2] - 2026-08-31

Tooling and the mod page. The mod is unchanged from 4.2.1 and there is no
reason to reinstall for this on its own.

### Fixed

- A release can no longer be published without having been played from its own
  pak. The development loop reads loose files at a pak priority a player does
  not use, where a pak with wrong entry names overrides nothing and logs
  nothing, so a broken release is indistinguishable from a working one. The
  guard existed and was lost; it is restored.

- The mod page check read section headings as settings and none of the settings
  themselves, so it reported the page as missing all twenty-nine keys it
  documents while missing the one key it genuinely lacked.


## [4.2.1] - 2026-08-31

### Fixed

- Anyone whose day is anchored to something goes back to it after a trot
  collision. A beggar returns to begging or walks to another spot, a drinker
  goes back to leaning on his wall, a merchant returns to his stall and
  someone knocked off a bench sits back down. Affects 4.2.0, where they stood
  where they got up until something reloaded them.

  The request that sends a victim back to their day was being sent with an
  empty payload, so the game accepted it and discarded it.


## [4.2.0] - 2026-08-31

### Fixed

- A trot victim is recovered by the game rather than by an animated get-up.
  The get-up clips turn the body as they play, by a fixed amount per direction,
  and that rotation is what left an innkeeper leaning into his wall from the
  wrong side. The fall is unchanged; what follows it is now the same recovery
  a gallop victim gets. `TrotReaction` gains a third value, `"fall"`, which is
  the new default; `"knockdown"` restores the animated get-up.

### Added

- `TrotReaction` accepts `"fall"`, which is the new default. `"knockdown"`
  restores the animated get-up and `"ragdoll"` the physics knockdown.

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
  `TrotReaction` to `"ragdoll"` to restore the 3.0.1 behavior. Gallop is
  unchanged and still ragdolls, which is what a horse at full speed should do.

- `MinVictimHealth`, `ClearCollisionInjuries` and the `LimitCollisionExhaust` group
  no longer exist. Each was an attempt at the problem where ridden-down NPCs
  stopped responding, and each was aimed at the wrong cause; that problem is
  now fixed at its source. None of them appeared in a released version, so no
  settings file in use names them; one that does keeps working, since an
  unrecognized setting is ignored and named in `kcd.log`.

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
  Set `ReleaseAnimationMovement` to `false` to restore the old behavior.

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
  the game's own auto-cure behavior, which holds them in place indefinitely
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
