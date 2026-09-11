# Changelog

Notable changes to HorseCollisionMod. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For a mod, the public interface is the settings file, the install procedure and
the reactions a player sees in game. A change that forces a player to redo their
configuration, or that changes how the mod sits alongside other mods, is a major
change even when nothing about it looks like an API.

Entries land under `## [Unreleased]

### Added

- **Leaning out to see past the horse's head.** In first person the horse's head
  and neck sit between the rider and whatever is in front, so lining up on
  someone and watching what happens to them are both guesswork. Hold `Q` or `E`
  and the camera slides out to that side and stays there until the key comes up,
  looking along the neck rather than into it.

  It only works mounted, and only while looking roughly along the horse: past 45
  degrees to either side, or 55 up or down, the lean is refused, and one already
  running ends if the rider turns past it. Beyond those angles the camera would
  travel through the rider and the horse rather than out beside them.

  An impact's camera shake is held back while a lean is held, since seeing who
  is about to be hit is the point of leaning in the first place.

  Configured by `Lean`, `LeanLeftKey`, `LeanRightKey`, `LeanDistance`,
  `LeanForwardShare`, `LeanMaxAngleDeg`, `LeanMaxPitchDeg`, `LeanSuppressShake`
  and `LeanTurnLeadMs`. `LeanTravelAmplitude`, `LeanHoldAmplitude`,
  `LeanShakePeriod`, `LeanShakeSec`, `LeanReleaseSec`, `LeanPollMs`,
  `LeanDeadband`, `LeanMinFlipMs`, `LeanHomeMs` and `LeanRunawayFactor` tune the
  mechanism itself and are better left alone.

### Changed

- The rear on the spot moves from `Q` to `F`, since the lean takes `Q` and `E`.
  The charge stays on `R`. Neither `F` nor `E` does anything in vanilla while
  mounted.

### Fixed

- Engine warnings and errors never reached `kcd.log`. The file and the console
  carry separate verbosities and the file's ships at 0, so everything the engine
  complained about was visible in game and absent from the only record that can
  be read afterwards. A development install now raises it, along with the
  animation warnings, which are off entirely at their shipped value.


## [5.3.1] - 2026-09-11

### Fixed
- A thrown body is woken before the mod releases the physics parameters it set.
  `DampVictim` writes `damping` and `min_energy` on a victim and clears them
  once the throw settles, but a sleeping physics body discards parameter writes
  and reports no error, so a body that reached its sleep threshold before the
  watch closed kept both values for the rest of its existence.

  This closes a state leak and nothing more is claimed for it. It is **not**
  known to change the floating-corpse behavior: that was attributed to this
  mechanism and fixed in 5.0.0, the rider's account of later testing is that
  floating was seen again and attributed to the engine, and the diary carries
  no record of the second investigation. See `docs/TESTING_DIARY.md`.


## [5.3.0] - 2026-09-11

### Added
- `RagdollSpeedCapArmorScaled`, `RagdollSpeedCapArmored` and
  `RagdollSpeedCapUnarmored`. The speed ceiling a traveling body is held under
  is set by what the victim is wearing, 2.5 m/s in full mail against 6.0
  unarmored.
- `RagdollAirDampingArmorScaled`, `RagdollAirDampingArmored` and
  `RagdollAirDampingUnarmored`. The drag is scaled by armor as well, 20.0
  against 4.0. The ceiling alone only decides when drag starts, and past the
  ceiling plus the span it saturates, so without this every victim received the
  same drag on exactly the fast throws where armor should tell them apart.
- `HorseAirborneVz`, the upward speed at which the mod reports the horse has
  left the ground. It writes nothing at rest and samples nothing the detection
  loop was not already reading.

### Changed
- **NOT BREAKING** Armor separates throw distance through the brake rather than
  through a rewritten ragdoll mass. `RagdollMass` is the engine's own 80 kg and
  `RagdollMassArmorScaled` is off, so a knight and a peasant weigh what the
  engine says they weigh. No setting is removed and every key an existing
  install carries still works, so nothing has to be reconfigured.
- The old mass scaling had no bound. At base 100 and exponent 3.7 it ran from
  43 kg for a villager to 1,208 kg for a mailed guard and 501,187 kg at an
  armor scale real guards score, which left every force the mod applies divided
  by a figure swinging across four orders of magnitude: knockback, uplift and
  the whole barding force bonus moved an armored victim five centimeters per
  second. Measured over 143 throws the brake reaches 1.70x separation on means
  and 1.87x on medians, matching what the mass rewrite produced, with every
  figure in it one that was set.

### Fixed
- `RagdollMass = 0`, documented as leaving the engine's figure alone, silently
  removed every throw: victims ragdolled and nothing else ran, because the
  early return skipped the callback that fires the impulse, the brake and the
  damping. It now waits for the body to physicalize and hands on without
  writing a mass.


## [5.2.2] - 2026-09-11

### Fixed
- Walking a horse into someone repeatedly could score the next shove as a trot,
  knocking them down for 16 damage at walking pace. Each shove kicks the horse
  off the victim's body, and the 900 ms speed hold that rates a collision by the
  speed the horse carried into it could not tell that kick from real travel. A
  speed now has to be held across two samples before it counts, so a one-tick
  kick cannot set it while a genuine gallop is scored exactly as before.

## [5.2.1] - 2026-09-11

### Fixed
- A save load in the sixty milliseconds between a collision and the ragdoll
  brake no longer fires that brake into the reloaded world.
- A rear that struck a victim who was removed before the dust spawned no longer
  aborts the rest of that impact's handling.
- `ImpactDustScaleGallop`, `ImpactDustScaleTrot`, `ImpactDustScaleCharge`,
  `ImpactDustScaleRear`, `ImpactDustEffectRear` and `RearReach` now default to
  the values that ship, so deleting one of those lines restores the tuned
  figure rather than the pre-5.2.0 one.

### Changed
- The ragdoll telemetry reports how far the body actually traveled and its
  vertical speed again, so one throw can be read without a sample of a hundred.

### Removed
- **NOT BREAKING** Ten internal settings left unread by the 5.1.0 pipeline
  rewrite: `RagdollThrowSculpt`, `RagdollThrowDistanceArmored`,
  `RagdollThrowDistanceUnarmored`, `RagdollThrowArmorScaleArmored`,
  `RagdollThrowArmorScaleUnarmored`, `RagdollThrowOnsetMs`, `RagdollBrakeMs`,
  `RagdollBrakeDampingArmored`, `RagdollBrakeDampingUnarmored` and
  `RagdollLyingContacts`. None was ever exposed in the settings file, so no
  existing install carries any of them.

## [5.2.0] - 2026-09-10

### Added
- `ImpactDustEffectRear` setting to choose a separate particle for rear impacts.

### Changed
- Rear impact dust now uses `collisions.destructibles.arrow_soil` for a short, punchy effect instead of the lingering `explosion_dust`.
- Rear impact dust spawns instantly at chest height on contact rather than waiting for the victim to hit the ground.
- Scaled down gallop dust from 0.15 to 0.09 and charge dust from 0.17 to 0.10.
- Disabled trot dust (scale 0) as it was not visually effective.
- Increased `RearReach` from 2.0 to 2.5 meters to reliably hit NPCs at standard interaction distance.
- Fixed a bug where `ImpactDustScaleCharge` was overwritten by the gallop scale.

## [5.1.0] - 2026-09-09

### Added
- Three-stage collision physics pipeline perfectly scrubs tumbling inertia off unarmored pedestrians to eliminate the sliding-wall glitch while stopping armored guards instantly.

### Fixed
- Stale Lua documentation references that broke the previous api build.


## [5.0.0] - 2026-09-09

### Added

- `RagdollSpeedSoftCap`, `RagdollSpeedSoftCapSpan` and `RagdollAirDamping`. A
  thrown body traveling faster than the cap is dragged in proportion to how
  far over it is, whether or not it is touching the ground.

- `RearChargeLungePeakMin` and `RearChargeLungeSpentAt`. The charge window now
  closes when the lunge itself is spent, judged as the horse's speed decaying
  to a fraction of the peak it reached, rather than on a fixed timer.

- `RearChargeStaminaCost`. The charge pays its own stamina rather than
  receiving a gallop's as a side effect of being counted as one.

- `RearChargeVictimLockMs`. How long a victim of a charge is held out of
  further impacts.

- `ImpactDamageEngineCeiling` and `ImpactDamageOverkill`. The ceiling is the
  most damage the engine's own trample has been seen to deal at each tier,
  measured over 136 impacts rather than chosen, and the overkill is how far
  past zero the mod aims when it finishes a victim.

### Changed

- **BREAKING** The charge is its own tier rather than a relabelled gallop. The
  detection loop stays out of a lunge entirely and `ChargeStrike` owns it end
  to end, so the charge's throw, stamina and victim lockout are its own
  figures and no longer inherit the gallop's.

### Fixed

- Unarmored victims were sometimes thrown far too far. The existing damping
  cannot arm until the engine reports the body in contact for three samples,
  and the first three or four samples of a long throw are exactly the ones
  that report no contact, so most of the distance was spent before anything
  acted on it. Drag now applies in that window as well. Judged over fourteen
  throws: no long throws, and no body stopping dead on contact.

- Bodies stayed floating in the air after death, and fell only when struck.
  The damping sets `damping` and `min_energy` on the victim, which are
  persistent physics parameters rather than a one-shot effect, and nothing
  removed them once the slide had ended. `min_energy` puts a body to sleep
  below the threshold, so a corpse nudged into the air by the horse slept
  holding that position. Both are now released once the body has stopped.

- A charge kept striking after its lunge was over. The window was governed by
  three numbers that had to agree with each other, one of them a floor of
  1200 ms, so the horse went on hitting people while it was already slowing.
  It now closes when the lunge is spent.

- A charge hit each victim twice. `ChargeStrike` honored no existing contact
  but recorded one, so the detection loop and the corridor sweep both scored
  the same impact.

- An ordinary rear locked its victim out of every impact for 2.6 seconds. The
  lockout was written for the charge and sat unconditionally in a function
  both features call.

- The rider was charged with murder for collision kills while
  `CollisionIsCrime` was off. A kill the engine resolves always belongs to the
  rider, so the mod now decides before the hit lands whether the impact is
  going to be lethal by anyone's hand, and finishes a victim the engine's
  trample could otherwise finish. Reproduced and then verified fixed in game
  on all three paths that let it through.

- Damage variance could turn a fatal blow non-fatal, which handed the kill
  back to the engine. A charge on an unarmored villager left her alive on 0.57
  health. The roll is now overruled when the intended damage would have killed.

### Removed

- `ImpactDamageRushBelow`. It asked how hurt the victim already was, which is
  the wrong question for deciding who lands the killing blow, and its value
  was never measured.

## [4.23.1] - 2026-09-08

### Fixed

- Rearing and charging stopped working. `kcd_animationControlledTags.xml` is the
  only place `hcm_rear` and `hcm_rear_charge` are declared, and
  `tools/build_adb.py` rebuilds that file from its own list, which did not
  include them. Regenerating the animation data to add an unrelated fragment
  deleted the horse's tag group, after which the fragments still existed but the
  names they resolve against did not:
  `StartInteractiveActionByName` returned true and left the horse in
  `MotionIdle`. The generator now emits that group itself.


## [4.23.0] - 2026-09-08

### Added

- `RagdollDampContactRun` and `RagdollDampRampSamples`. A thrown body is damped
  once the engine reports it in contact with something for three samples in a
  row, and the damping then comes in over eight more rather than all at once.

### Fixed

- Thrown bodies slid too far and traveled inconsistent distances. Damping
  decided a throw was over when the body's speed dropped below a threshold,
  which for a tumbling body in the air is arbitrary: it fired anywhere between
  736 ms and 2848 ms, and the throw ended wherever it caught the body. It now
  waits for the body to actually be on the ground, which the engine answers
  directly, and bleeds the motion off instead of arresting it. Measured over
  seventeen impacts afterwards, every one damped on contact and none reached
  the failsafe.

### Removed

- `RagdollDampGroundedSpeed` and `RagdollDampMinTravel`. Both were attempts to
  tell a body still being thrown from one sliding, using vertical motion and
  distance as stand-ins for a fact the engine reports directly.
  **NOT BREAKING**: neither reached a published release.


## [4.22.0] - 2026-09-08

### Added

- `HitReadyByTier`, so only the tiers that play an animation wait for a victim
  to be ready. A gallop and a charge ragdoll, which has no pose to blend from,
  and they can now land at any stage of a victim's recovery.
- `HitMinIntervalMs`, the least time between two scored impacts on one victim.
  Detection runs every 33 ms and a galloping horse clears a person in about
  150 ms, so a single pass was four or five separate impacts.
- `ImpactDamageRushBelow`, which lands the mod's damage immediately instead of
  waiting when the victim is too weak to survive what the engine takes. The
  wait exists so the mod delivers the killing blow and the death is its own to
  attribute; below about 35 health the engine got there first and the rider was
  charged with murder.
- `hcm_settle`, a fragment holding only an empty terminal clip and a `Ragdoll`
  layer, for knocking down a victim who is already down.

### Changed

- An impact on a victim already on the ground now produces a real reaction.
  Previously the mod declined it, the engine's own collision happened anyway,
  and what the rider got was the vanilla result: the horse wedged in the victim,
  no feedback, and a bark.
- Retaliation is a walk-tier answer again. A victim reared on or charged no
  longer decides to fight back; it was wired in when the rear was first built,
  before the rear was a tier of its own.
- `RearMaxSpeed` measures horizontal speed rather than the length of the whole
  velocity vector. A stationary horse reports 1 to 2 m/s because the reading
  carries its settling fall, so the gate was comparing against noise.

### Removed

- `RagdollDampGroundedSpeed`. It damped a body as soon as its vertical motion
  fell below a threshold, on the reasoning that a body still moving without
  rising must be sliding. That is a guess about state rather than state, and it
  was wrong for the case it was worst in: a victim hit while already lying down
  has no vertical component from the first frame, so the throw was arrested
  before it happened. **NOT BREAKING**: the setting is replaced by the test
  below it, which needs no threshold to agree with another threshold.


## [4.21.0] - 2026-09-08

### Added

- `ImpactDamageByTier`, so what each kind of collision is worth is a setting
  rather than a figure compiled into the mod.
- `ImpactDamageOwnsTheHit` and `ImpactDamageReclaimCeiling`. The engine charges
  a collision itself, at a rate this mod cannot read or override, so the tier
  figures were an addition to an unknown quantity. Whatever the engine took is
  now handed back before the mod applies its own, bounded so that an unrelated
  injury is not healed by a passing horse.
- `ImpactDamageArmorCurve` and `ImpactDamageArmorFloor`. The falloff had no
  bottom, so heavy armor drove an impact arbitrarily close to nothing: a charge
  landed about ten damage on an ordinary town guard. The floor is the least
  armor is allowed to refuse, on the grounds that no plate makes a man weigh
  less than the horse standing on him. Both default to the previous behavior
  exactly.

### Changed

- Retaliation is a walk-tier answer again. A victim reared on or charged no
  longer decides to fight back, which is what happened when a guard was reared
  on four times. It was wired in when the rear was first built, before the rear
  was a tier of its own, and it started fights through a path that deliberately
  bypasses the crime system and so could not be turned off with
  `CollisionIsCrime` either. Rears and charges will get answers of their own.
- A rear leads with the horse's own landing, so it sounds like hooves coming
  down rather than a body impact. The layers that resolve by armor sit further
  back, because their chainmail variants were masking the hoof entirely on an
  armored victim while the balance was right on an unarmored one.


## [4.20.1] - 2026-09-08

### Removed

- `DogIgnoresHorses`, and the code behind it. **NOT BREAKING**: the setting
  landed after the last published release, so no player's settings file
  carries it.

  It never worked. Measured with a horse actually standing on the dog,
  re-applying the ignore moved the horse 1.8 cm, and widening the mask to
  `gcc_all`, with nothing left to overwrite it, moved it not at all. A dog
  ignoring every collision class in the game still carried a horse, and the
  horse climbed back on afterwards.

  The reason is that it is not a collision. A horse is a living entity and
  stands wherever a downward ground query finds a surface, with no rigid body
  balance to lose, so it does not need a surface broad enough to hold it: of
  81 rays cast over a 1.35 m grid, the dog's collider answers one. The horse
  balances on a column about fifteen centimeters across, and collision class
  masks do not reach the code path that put it there.

  A correction that moved the horse back to the ground was built and rejected.
  Dropping it straight down lands it on the dog again, and moving it clear
  first reads as teleporting the player. The bug stays.


## [4.20.0] - 2026-09-08

### Added

- `RearIdleOnly`, which requires the horse's own locomotion state to be idle
  before a rear fires.

### Changed

- The rear no longer holds the horse for the third of a second after the
  animation is visually over. The fragment now ends where the horse's feet come
  down rather than where the clip runs out, cutting it from 2032 ms to about
  1400 ms.
- The charge reaches its lunge sooner for the same reason, 1408 ms down to
  about 1050 ms.
- `RearMaxSpeed` measures horizontal speed rather than the length of the whole
  velocity vector, and is 0.15 rather than 1.0. A horse standing still reports
  1 to 2 m/s because the reading carries its settling fall, so the old gate was
  comparing against noise: it refused rears from a dead stop and admitted ones
  that slid.

### Fixed

- A rear taken while the horse was still moving slid it about 0.12 m before the
  animation took hold. A rear is a standing attack, and it now behaves like one.
- Hitting someone no longer costs frames for the following ten seconds. The
  wait that lets a downed victim recover was writing a log line on every pass
  of the detection loop, several hundred per victim, and now writes one.

## [4.19.5] - 2026-09-07

### Fixed

- The mod now loads on any 1.9 patch. It declared support for 1.9.7 exactly,
  and the game's mod loader disables a mod outright when the version does not
  match, so anyone who had patched to 1.9.8 had a mod that never ran at all,
  with nothing in game to explain why.

  If you are on an older release and cannot update, deleting the `<supports>`
  block from `mod.manifest` has the same effect: the loader treats a mod with
  no version restriction as compatible with anything.

## [4.19.4] - 2026-09-07

### Fixed

- The surrender prompt no longer lingers after a fight is over. It used to stay
  up for five or six seconds after the last person willing to fight you had
  died or walked away, offering a surrender to nobody.

- Provoking a guard in sight of another guard no longer shows two surrender
  prompts. That is an arrest, and the game raises its own prompt for it, so the
  mod now leaves guards to it. Villagers still get the mod's prompt.

## [4.19.3] - 2026-09-07

### Changed

- A rear on the spot is its own kind of blow rather than being scored as a
  trot. It hurts considerably more, sounds like hooves coming down rather than
  a body being shoved, and raises its own dust and camera shake. All of it is
  tuned separately from riding someone down.

### Fixed

- Someone killed while still falling from a collision no longer stands up dead.
  The game marked them dead, so bystanders treated them as a corpse, while
  their body stayed locked in the animation with no collision and could be
  walked through walls. Their body now drops properly.

- Victims are no longer occasionally carried through walls by the fall they are
  knocked into.

- A victim of a rear gets back up facing the right way and returns to what they
  were doing, instead of standing wherever they landed with nothing to do.

- Rearing on someone already on the ground no longer twists their body into a
  broken pose. The blow still lands; they simply stay down.

## [4.19.2] - 2026-09-07

### Changed

- The rear and charge is a special move rather than a fast collision. The horse
  rears on the spot and is then driven forward physically, so it collides with
  the world like any moving horse: walls and fences stop it instead of being
  ridden through, and you can steer it slightly on the way in.

- The charge knocks down everyone in a corridor in front of the horse, with no
  limit, so a crowd cannot shield each other by standing close.

- **NOT BREAKING** The settings that steered the old animation-driven charge
  are gone, replaced by the ones that drive the physical version:
  `RearChargeStopDistance`, `RearChargeSideDistance`, `RearChargeCheckZ`,
  `RearChargeWallNormal`, `RearChargeWatchWhileMoving`, `RearChargePollMs`,
  `RearChargeWatchMs` and `RearChargeSpeed`. They existed to stop an animation
  riding through walls, which a physically driven horse does not do.

  Not breaking because no published version ever carried them. The last release
  on Nexus is 4.9.3, which predates the rear entirely, so no player has any of
  these in a settings file.

- A charge is now its own kind of impact rather than being scored as a gallop.
  It hits harder, raises more dust, shakes the camera more, and has its own
  sound, built from hoofsteps rather than the layers an ordinary collision
  uses. All of it is tuned separately from riding someone down.

### Fixed

- A charge could hit nobody at all. The detection the mod uses for ordinary
  collisions needs the horse to be moving, and a charge starts from a
  standstill, so it declined to look for anyone. The charge now finds its own
  victims.

- Your dog can no longer carry your horse around on his back.

## [4.19.1] - 2026-09-07

### Fixed

- The rear and charge no longer rides through walls, fences and carts. The
  charge is an animation, and an animation does not collide, so the horse now
  watches ahead and pulls up short of anything solid instead of passing into
  it. Rising ground is not treated as an obstacle: the horse still charges up
  a hill.

  This also removes the launches that came with it, where a charge that ended
  inside geometry threw horse and rider backwards, sometimes further than the
  lunge had traveled.

## [4.19.0] - 2026-09-06

### Added

- Rear your horse on command. Two moves on two keys: one rears on the spot and
  brings the hooves down on anyone right in front, and one rears and drives
  forward, riding down whoever is in the way. Both are the horse's own
  animations and you stay in the saddle. Only from a standstill.
  `RearChargeKey` and `RearOnlyKey` choose the keys, defaulting to R and Q.
  **NOT BREAKING**, no released version carried them.

## [4.18.0] - 2026-09-06

### Added

- The surrender prompt now appears during a brawl you provoked. Surrendering
  always worked and resolved the fight cleanly; nothing on screen told you so.
  `RetaliationSurrenderHint`. **NOT BREAKING**, no released version carried it.

- `RetaliationPullsRiderDown`, `PullDownPollMs`, `PullDownRepeatMs` and
  `PullDownCeilingMs`, which control a provoked victim dragging you off the
  horse. **NOT BREAKING**, no released version carried them.

### Changed

- A villager who has had enough of being ridden into now drags you out of the
  saddle first and fights you on the ground, instead of throwing punches at
  your horse. The game already had the move; the mod was telling him to attack
  before asking for it, so he hit whatever was in front of him.
  `RetaliationPullsRiderDown`. **NOT BREAKING**, no released version carried
  it.

### Fixed

- The mod no longer provokes new victims once you are already in a fight.
  Someone running into your stationary horse mid-brawl counted as you riding
  them down, so anyone who closed on you was provoked into a second brawl of
  their own. Guards still respond to a fight they witness, as they always did;
  this only stops the mod from adding to it. `ProvokeDuringCombat`.
  **NOT BREAKING**, no released version carried it.

## [4.17.2] - 2026-09-06

### Fixed

- Riding down a guard who happens to have his weapon drawn is no longer
  treated as fighting. Anyone carrying a weapon counted as combat, so a
  patrolling guard cost the horse more than five times the stamina he should
  have, and guards with polearms were never staggered at walking pace because
  the walk stagger is disabled in combat. Whether you are in a fight now
  decides it.

## [4.17.1] - 2026-09-06

### Fixed

- Armor decides how far someone is carried by making them heavier, and only
  that. It was also being used to weaken the knockback, so armor counted
  twice and a man in mail became too heavy for any impact to move at all.
- Riding someone down throws them consistently. The mod settled a knocked-down
  body 150 milliseconds after the impact, before a thrown victim had even
  reached top speed, which arrested them wherever it happened to catch them: at
  an identical impact some victims traveled 3 meters and others 50. It now
  waits until the body has actually slowed before settling it, so the throw
  finishes first and bodies still come to rest rather than sliding.
- Someone already lying on the ground is thrown by a gallop like anyone else.
  They were being settled immediately, because a body on the ground is already
  slow at the moment the old fixed timer fired.

## [4.17.0] - 2026-09-06

### Added

- Your Horsemanship now decides what riding someone down costs. Early in the
  game a single gallop impact empties the horse and puts you on the ground; at
  skill 20 you can ride through four or five armored guards and will usually
  keep your seat when the horse finally stops. This is what the skill already
  governs in vanilla, so it compounds with the game's own reduction.
  `Horsemanship`. **NOT BREAKING**, no released version carried it.
- Barding on your horse now changes what a collision does. It is read off the
  horse's armor rather than its tack, and scales with how much of it the
  horse is wearing rather than with your Horsemanship. A full set costs the
  horse a quarter less stamina per impact, hits fifteen per cent harder and
  throws someone about ten per cent further. `Barding`, `BardingFullSmashDef`,
  `BardingStaminaRelief`, `BardingDamageBonus` and `BardingForceSteps`.
  **NOT BREAKING**, no released version carried them.

### Fixed

- Riding someone down throws them properly. The mod applied its knockback and
  the victim's ragdoll weight the instant it asked them to fall, before the
  body had actually become a ragdoll, and the game discarded both. Victims are
  thrown about forty per cent further as a result, far more consistently, and
  armor finally makes a difference to how far someone is carried: a man in
  mail now weighs three times what a villager does instead of both weighing
  the same.

- The head and neck armor a horse wears is counted as barding. The game files
  it under an `armor_type_id` named `horse_bridle`, which the mod was
  discarding as tack, so the only substantial protection a horse can wear was
  being ignored and barding was scored on cloth trappings alone.

### Changed

- A trot impact costs the horse less stamina than it did, so a trot goes
  meaningfully further than a gallop rather than marginally.

## [4.16.0] - 2026-09-06

### Fixed

- Riding someone down is now consistently a crime, or consistently not one,
  according to `CollisionIsCrime`. Previously it was neither: the game applies
  trample damage of its own for a horse collision and attributes it to the
  rider, and because the mod charged the victim first, its own damage fell a
  little short about two times in three and the game's trample delivered the
  killing blow. Guards blame whoever lands that blow, so the same collision was
  ignored on one villager and an instant hanging offence on the next. The mod
  now waits for the trample to resolve before charging the victim, so it lands
  the killing blow itself. A gallop is slightly more lethal to an unarmored
  villager as a result.

### Added

- `ImpactDamageDelayMs`, how long the mod waits before charging a victim, so
  the game's own trample damage lands first. **NOT BREAKING**, no released
  version carried it.

## [4.15.0] - 2026-09-05

### Added

- A horse that throws a spent rider now sometimes leaves rather than waiting to
  be remounted. Ride it into enough people that its stamina runs out and there
  is a fair chance it wants nothing more to do with you, and you walk.
  `HorseBoltsWhenSpent` and `HorseBoltChance`. **NOT BREAKING**, no released
  version carried them.

## [4.14.0] - 2026-09-05

### Added

- `HitCooldownStateDriven`, `HitReadySettleMs`, `HitReadyPollMs` and
  `HitReadyCeilingMs`, which control how long a knocked-down victim is left
  alone. **NOT BREAKING**, no released version carried them.

### Changed

- A victim who has been knocked down is left alone until they are actually back
  on their feet, rather than for a fixed six seconds. An NPC standing up cannot
  be knocked down again by anything the engine offers, so an impact landing
  there took their health with no reaction at all, and a trot restarted the
  fall animation from a standing pose they were not in. `HitCooldownStateDriven`
  turns it off. **NOT BREAKING**, no released version carried the setting.

## [4.13.0] - 2026-09-05

### Added

- A gallop impact now kicks the rider's camera. Riding someone down costs
  stamina and costs them health, and in hardcore mode neither is visible from
  the saddle; this is the part of it the player feels. A trot gets a smaller
  version of the same kick. `CameraShake` and `CameraShakeTrotScale`.
- An impact throws dust off the ground where the victim lands, rather than
  where they were struck, so it appears with the body however far it was
  thrown. `ImpactDust`.
- In first person the rider's view blurs briefly on an impact. The collision
  happens below the field of view at a gallop, so a first-person rider sees
  almost none of the dust; this is their share of it. Off in third person,
  which can already see the whole thing. `RiderBlur`.

### Changed

- Impact sounds are louder again, tuned in first person alongside the camera
  effects rather than on their own. A gallop is noticeably heavier than a trot
  now, and the dull thud under a gallop impact is back after being dropped for
  being inaudible where it sat.

## [4.12.0] - 2026-09-05

### Added

- `ImpactSoundDistance`, a single control over how loud trot and gallop
  impacts are, in meters. Higher is quieter. The game's audio has no volume
  anywhere, so distance is the substitute, and this is added to every layer of
  a tier so the mix comes down as a whole and the balance between the layers is
  left alone. A third-person camera mod hears every impact from further away
  and will want it lower. **NOT BREAKING**, no released version carried it.

### Changed

- Impact sounds are quieter, and are now tuned in first person. The previous
  balance was judged through a third-person camera, which puts the listener
  several meters further from the victim and made the whole mix sound quieter
  than a normal player hears it.
- A gallop impact no longer plays a hoofstep. It could not be quietened, sat at
  a fixed full level under everything else, and the horse is already making
  that noise.
- The layers of a trot or gallop impact now land together instead of a few
  milliseconds apart, which removes a phasing sound on headphones.

## [4.11.0] - 2026-09-04

### Added

- What a collision costs now depends on what the victim is wearing. Ride an
  unarmored villager down at a gallop and they will usually not get up; do the
  same to a knight in plate and he loses about a quarter of his health and
  keeps coming. A trot knockdown costs a villager roughly a quarter either way,
  so it takes four. Nothing decides this by a dice roll: the damage is scaled
  by the blunt resistance of what they wear and the outcome follows from it.

### Fixed

- Turning `CollisionIsCrime` off now actually stops a trampling death being
  charged to you. It never did before, because the mod had no damage of its own
  and the engine's trample was the only thing that could kill anyone, and a
  kill the engine resolves always belongs to the rider.

## [4.10.0] - 2026-09-04

### Added

- Shove a woman at walking pace once too often and she now answers it. Where a
  man turns and fights, she breaks off, goes to find a guard and reports you.
  She raises no alarm at the moment of the shove: the report is something she
  carries and has to deliver, so getting clear of her before she reaches anyone
  is the difference between a fine and nothing at all. A guard who sees it
  himself still needs no telling.

  Both answers run off the same count and the same roll, so `Retaliation`,
  `RetaliationFreeBumps`, `RetaliationChanceStep` and `RetaliationMaxChance`
  govern the two alike. `WomenRaiseAlarm` turns the new half off on its own.

## [4.9.3] - 2026-09-04

### Changed

- The mod does noticeably less work while you ride. Finding the people near
  the horse was the only expensive thing it did, and it now happens when the
  horse has actually moved rather than thirty times a second regardless.
  Nothing about what counts as a collision changed.

### Fixed

- A diagnostic that could not read a victim's name no longer risks stopping
  that victim being watched.
- `kcd.log` is quieter during ordinary play. A per-tick line about anyone
  standing near the horse was being written with normal telemetry on; it
  belongs with the rest of the diagnostics behind `DiagnoseMisses`.

## [4.9.2] - 2026-09-04

### Fixed

- Guards carrying a polearm can be staggered at walking pace. They never
  could: the stagger is skipped during combat, and the combat test counted a
  victim holding a weapon as combat, so a guard who carries his polearm on
  patrol read as fighting all day. Only an actual fight skips the stagger now.
  Being staggerable also means they can now lose patience and fight back,
  which they never had the chance to do.

## [4.9.1] - 2026-09-04

### Changed

- A gallop hits harder. It stacks four different blunt impacts rather than
  repeats of one, so it reads as a collision rather than as the same sample
  flammed against itself, and the heavy thud underneath sits closer. All four
  follow what the victim is wearing, so a mailed guard and a peasant in cloth
  are told apart on every layer.

## [4.9.0] - 2026-09-04

### Added

- A collision makes a noise. There is no sound in the game for a horse
  striking a person, so each speed tier builds one from layered audio
  triggers a few milliseconds apart: cloth and a body settling at walking
  pace, a blunt impact at a trot, and that impact four times over a dull
  heavy thud at a gallop, with an occasional injury. What the impact sounds
  like follows what the victim is wearing, read from the armor the mod
  already weighs. Seven settings control it, and any of the game's own
  trigger names may be used.

### Changed

- The detection loop now runs from `TickSeconds` rather than a hardcoded
  100 ms timer, at 33 ms. The two figures had agreed only by accident, and
  the gap between a contact and the mod noticing it was the largest part of
  the delay before a reaction. `ImpactSpeedSamples` moved from 3 to 9 to keep
  the window a collision is scored over unchanged.

## [4.8.0] - 2026-09-04

### Added

- A victim knocked to the ground now shows it. Dirt goes on everything they
  are wearing and, at a gallop, blood goes on whichever side of the body the
  horse struck. Both accumulate across impacts and both wash off the way any
  other dirt and blood does. Five settings control it: `VictimMarks`,
  `VictimDirtTrot`, `VictimDirtGallop`, `VictimBloodTrot` and
  `VictimBloodGallop`. Nothing is applied at walking pace, where nobody goes
  down.

## [4.7.5] - 2026-09-03

### Changed

- A victim who runs after a brawl is left to run. The mod used to stop him
  with a stand-down, on the understanding that the flee never ended; it ends
  on its own after ten to fifteen seconds, and what made it look endless was
  following him. Measured on one man, one build: left alone he stopped after
  fourteen seconds, and chased he was still at full speed forty seconds
  later. The engine's own flee ends at a set distance from whoever is being
  fled from, so a rider in pursuit is why it never arrived. Stopping him was
  also expensive, because it parked him standing still for around twenty five
  seconds afterwards, and that is gone with it.

## [4.7.4] - 2026-09-03

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
  `RetaliationFleeSamples` are gone with it. **NOT BREAKING**: they were added
  in 4.6.0 and the newest published version is 4.2.2, so no player has ever
  had them in a settings file and no existing configuration changes. An
  unrecognized setting is ignored and named in `kcd.log` as always.

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
