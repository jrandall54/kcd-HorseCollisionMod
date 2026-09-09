# Horse Collision Overhaul - Roadmap

Collisions should feel weighty and natural, and should lean on the game's own RPG systems
(Horsemanship, armor weight, native AI) rather than brute-force physics.

## Phase 1: Speed tiers and non-ragdoll reactions

Complete, shipped in 2.0.0.

- [x] Map horse speed to three tiers, with thresholds set between the plateaus the
      horse actually holds.
- [x] Play a native standing hit reaction at walking pace instead of a ragdoll. Delivered
      through `actor:StartInteractiveActionByName` against custom `AnimationControlled`
      FragTags added to the animation database.
- [x] Keep the vanilla collision bark, by posting the native `hitReaction` brain message.
- [x] Drain horse stamina at trot and gallop, and dismount the rider when it is spent.

Known gaps carried into later phases:

- [x] Female NPCs stagger too. `wh_female_fragmentids.xml` had no `AnimationControlled`
      fragment at all, so it is declared and the block added to their database.
- [x] Detection reach narrowed from a sphere to a horse-shaped footprint.
- [x] Reactions carried their victim into walls and buildings, and sometimes left them
      standing inside one. An interactive action is root-motion driven, so the animation
      moves the body and nothing constrains where it ends up.
      `actor:SetMovementControlledByAnimation(false)`, called on the victim a tick after
      the action starts, returns them to entity-driven movement, which is the state
      vanilla's own hit reactions play in. Walk and trot are both clean against a wall.
      The timing is the whole trick: an interactive action applies its fragment's
      movement layer as it starts, so the same call made before it is overwritten and
      changes nothing. Settable as `ReleaseAnimationMovement`.
- [x] A trot knockdown clipped into sloped ground, partly burying a victim falling uphill
      and leaving one falling downhill briefly airborne. Fixed by the same call as the
      item above, which was not expected to touch it: a wall and a slope are the
      horizontal and vertical cases of one fault, an animation moving the body along a
      path authored in a plane with nothing reconciling that path with the world.
      Returning the actor to entity-driven movement puts the engine back in charge of
      where the body goes, and it resolves both. Not perfect, and close enough to
      vanilla to leave alone. Correcting the get-up pairings had already fixed the
      rotation behind most of it; `GroundRotation` and the ragdoll settle layer do
      nothing and are not used.
- [x] The horse and a downed NPC pass through each other, and a rider
      squared up head-on ends up inside the body while the fall plays. Not
      fixable through `ColliderMode`: `Interactive`, `NonPushable`,
      `GroundedOnly` and `Disabled` were each ridden on the knocked-down
      tiers and none is distinguishable from the others, including switching
      collision off outright, which also produced none of the clipping that
      layer exists to prevent.

      The cause is that no impulse fires at trot. With `TrotReaction` set to
      `"fall"` the dispatch plays the reaction and nothing else, so the
      victim collapses where they stood, which against a squared-up rider is
      under the horse. Adding an impulse is not small: an animation-driven
      actor ignores them, which is why this tier is an animation rather than
      a physics knockdown. Closed as understood rather than as fixed.
- [x] **Not an exploit.** An entry here described repeated impacts driving victims to an
      exhaustion ceiling, on readings of `exhaust=100`. The stat named `exhaust` is the
      **Energy** stat the game's own UI shows, and it runs the other way: 100 is fully
      rested and 0 is spent. Every NPC reading 100 was untouched, not exhausted. The guards
      that could not fight were held by vanilla's auto-cure daycycle, which is fixed, and
      the cap written against this was draining its victims rather than protecting them.
      Removed with the other superseded protections.
- [x] An NPC that stops responding after repeated impacts is held by vanilla's auto-cure
      daycycle, which plays `PretendingIllness` under a wait with no timeout while health
      is under 40. Fixed under Start here below. The guard read as exhausted in an earlier
      entry was not: `exhaust=100` is full energy. The `Animation-queue overflow` the
      engine logs alongside it is a symptom of queued reactions, not the cause.
- [x] Reactions firing at the wrong tier. Tracked under Reaction reliability
      below.

## Start here

Two separate defects, found by testing rather than reading, and neither is what
earlier entries in this file assumed. Both are open.

### 1. Collisions damage the victim. Resolved at trot, open at gallop.

There are two sources and only one was ever a defect.

The mod's own `hitReaction` carries a `hitStrength` per tier, and vanilla turns
a player-ridden collision into a real `combat:hit` carrying it. That is Phase 3
blunt damage arriving early, it is wanted, and walk costs nothing only because
it sends a strength that does nothing.

The other is the trample. A ragdoll turns the victim into a physics object under
a moving horse, and the engine charges the velocity delta at
`CollisionVelocityDeltaToDmgR = 0.25`. The horse's speed at contact is the only
predictor: above 10 m/s costs 20 to 25 against an unarmored target, under 5 m/s
costs nothing, and neither the impulse nor armor affects it.

- [x] Throw the victim sideways. No effect. The impulse does not cause the
      damage, so its direction cannot help.
- [x] Delay the ragdoll. Cuts the damage by about a fifth and destroys the
      impact, because a victim who stands upright while the horse is inside them
      does not read as having been hit.
- [x] An animated knockdown at trot, through the `AnimationControlled` path the
      walk stagger uses. No physics body is created, so the trample cannot
      happen. `TrotReaction` selects it and it is the default.
- [ ] Gallop still ragdolls, and still takes the trample. That is where the
      damage is, 20 to 25 an impact against 3 to 5 at trot, and it is untouched.
      The ragdoll at a gallop is settled design and is not up for replacement.

- [x] Damage the mod applies itself, on top of whatever the physical collision already
      costs, chosen by what the target is wearing. Shipped in 4.11.0.

      The target the rider set, in their words: "a villager with no armor should have about
      a 90% chance of dying on impact where as someone in plate probably would only take a
      little bit of damage and have a very very small chance of dying on impacts."

      `ApplyImpactDamage` charges the victim through vanilla's own
      `soul:DealDamage(stamina, health, attacker, false)`, scaled by the summed `smash_def`
      of what they wear:
      `1 / (1 + max(0, smashDef - ImpactDamageIgnoredArmor) / ImpactDamageArmorScale)`.
      The subtraction is what makes it work, because a villager's shoes and shirt are in the
      game's own `armor` table and would otherwise count as protection. There is no kill
      roll: lethality falls out of damage against health and `ImpactDamageVariance` is what
      makes it a chance.

      Measured across two rides at the shipped figures:

          unarmored gallop   12 of 14 fatal, 86 per cent
          plate gallop       mod 8.5 to 9.4, engine ~15, total -23 to -24
          mail gallop        mod 8 to 12, engine 15 to 19, total -25 to -28
          unarmored trot     -19.5 to -24.4, about a fifth to a quarter

      One limit carried forward: the engine's trample is an armor-blind floor of roughly 15
      to 20 at a gallop that the mod cannot lower. `rpg_param.xml` stays off limits, one
      global value read by everything that resolves a physical collision including the
      player's own. `perk_rpg_param_override.xml` resolves parameters per character against
      the perks they hold and remains the unexplored route.

Overriding `rpg_param.xml` is rejected: one global value read by everything that
resolves a physical collision, including the player's own, and shipping a
vanilla table reintroduces the conflict surface 3.0.0 removed. Per-character
overrides exist through `perk_rpg_param_override.xml`, which resolves RPG
parameters against the perks a character holds, and are unexplored.

### 2. Repeatedly ragdolled NPCs wedge. Fixed.

The state is vanilla's auto-cure daycycle. An NPC carrying a bleeding or poison
buff whose health falls under 40 enters `cureLookHurt`, in
`Libs/AI/final/sb_daycycles_cure.xml`, which plays the `PretendingIllness`
animation under a wait with no timeout and regenerates health at 0.02 per
second. Nothing inside that subtree ends, so a victim left under the threshold
stands in the street until health climbs back over it.

It is designed behavior rather than a defect. The mod meets it because it is the
one thing in the game that leaves ordinary townspeople badly hurt in the open.

- [x] Exempt a collision victim from the daycycle, using the same context option
      vanilla uses for duellists and scripted wanderers. Set at impact, which is
      before collision damage resolves; the gate is only read on entry, so an
      option set afterwards does not release a running cure.
- [x] Release a victim already held, by removing the `curePatch` daycycle patch
      after setting the option. This works at low health and without healing, so
      a save carrying stuck NPCs repairs itself as the rider rides.
- [x] Retire `MinVictimHealth`. It prevented the lockup only by making a
      collision unable to kill.

Produced far more readily on guards than on other NPCs, which is also where
every report of it in this project has come from.

### Three superseded protections. Removed.

Each treated a symptom of a cause since disproven, and the lockup is fixed at
its source.

- [x] `MinVictimHealth` and `HoldVictimAboveFloor`. Prevented the lockup only by
      making a collision unable to kill.
- [x] `ClearInjuries` and the injury buff constant. Injuries were never what
      held a victim.
- [x] `LimitExhaustion`, `EnforceExhaustLimits` and `ExhaustWatch`. Built on an
      inverted reading of the Energy stat, and already disabled by default.

313 lines, four methods, two module tables, six settings and a per-tick timer
hook. A settings file still naming the removed keys keeps working, since an
unknown setting is ignored and named in `kcd.log`.

## Parked curiosity: riding and walking at the same time

Not a feature and not a defect to fix, kept because the rider wants to come back
to it.

    player.actor:StartInteractiveActionByName("hcm_rear", horseId, false, 1.0)

Called on the player while mounted, this leaves them in two states at once. The
tag resolves, because `kcd_animationControlledTags.xml` is shared with the human
databases, but no human option carries it, so the engine acquires the player's
body and camera scope and abandons the action within a frame with nothing
handing either back.

They remain the horse's rider and can steer it, while their character runs the
on-foot locomotion state machine, so they walk and run on top of the horse. The
object id aligns them to the saddle. The camera stays pinned looking up. Drawing
a weapon drops them into the horse, dismounting pops them back on top and leaves
them unable to ride or remount, guards cannot reach them, and surrendering
resolves it by forcing a proper dismount.

`actor:Fall` on the player in that state ragdolls them while they stay standing
on the horse. On foot the call does nothing at all: the acquisition needs the
contradiction with being mounted.

The mechanism is written up in `docs/TESTING_DIARY.md`.

## Development tooling

Complete, merged after 2.0.0. Not a gameplay phase, but it changes how every phase below
gets tested.

- [x] Deploy straight into `Mods\` without Vortex, with the game path resolved rather than
      hardcoded so a clone builds on any machine.
- [x] Hot reload the mod's Lua into a running game, no restart and no save reload.
- [x] Hot reload the Mannequin animation databases the same way. Needed the ADB files
      written loose *and* `mn_allowEditableDatabasesInPureGame`, which ships at 0.
- [x] Live telemetry over CryEngine's remote console, with backend chatter filtered out.
- [x] Read the mod's live state out of the running game.
- [x] Publish a release to Nexus Mods without the browser, through their v3 API.
      Not a GitHub Action: the build reads the game's own paks, so it cannot run on a
      hosted runner. Revisit if additive ADB deployment below ever lands.

See `docs/DEV_LOOP.md`.

## Additive deployment

Shipped in 3.0.0. The mod no longer replaces the animation databases.

It ships its own small database carrying vanilla's `AnimationControlled` options
alongside its four, and references the untouched 5.5 MB vanilla file where it sits
inside its own pak. The human entity classes are pointed at it from Startup Lua.
Download dropped from 195,284 to 24,847 bytes in 3.0.0.

- [x] Reference the vanilla databases instead of replacing them.
- [x] Redirect the classes the engine spawns, not the templates they are built
      from. `NPC = CreateAI(NPC_x)` copies fields, so redirecting `NPC_x` has no
      effect on what spawns.
- [x] Verify a packaged build at shipping pak priority, from a Vortex install.
- [x] Publish 3.0.0, and rewrite the mod page, which described the old
      database-replacement install.

Two small declaration files keep vanilla names, 15 KB in total, and two mods
redirecting the same class still collide. `docs/HOW_IT_WORKS.md` and
`docs/TECHNICAL_DETAILS.md` cover both.

## Reaction reliability

- [x] Reactions firing at the wrong tier, which reads from the saddle as not
      firing at all. A gallop impact scored as a walk plays a stagger instead of
      a knockdown. Impacts are now scored on the peak of the last few ticks
      rather than on the speed sampled after the collision has slowed the horse.
- [x] A gallop impact reporting walking speed. Same cause, same fix.
- [x] Kneeling NPCs producing no reaction. The footprint accepts them as it
      stands; the cause was the same misscoring, and a reaction one tier too
      small is easy to miss on a target already close to the ground.

Detection itself is sound: the human filter, the dead check, the below-walk gate
and both axes of the footprint were each cleared against logged sessions.

### Parked

- [x] The shipped armor weight table is gone. `Armor.lua` reads the game's
      own tables through the `Database` bind: `pickable_item` carries
      `item_id` and `weight`, `armor` carries `item_id`, `smash_def` and
      `armor_type_id`, and the class an item reports joins straight to
      `pickable_item.item_id`. Membership of `armor` decides worn rather
      than carried. The index builds 796 armor pieces in game, three victims
      ridden down before and after the change reported identical weights,
      and the download fell by rather more than a quarter. The figures are
      in the testing diary, which records them as a measurement of that
      build rather than as a claim about the current one.
      `build_item_weights.py`, its build step and the shipped Startup script
      are removed.

- [ ] Not being pursued. Shorten the wait between a trot victim going limp and standing up.
      Nothing settable reaches it. Measured from the handover rather than
      from the end of the clip it is a consistent 1,457 ms, the same for
      both character sets, and unmoved by `ExitTime`, `Sleep`, `Stiffness`,
      `p_group_damping`, `g_ragdollPollTime` and `ca_DeathBlendTime`. The
      stand-up that follows runs 2,570 ms for men and 5,100 ms for women,
      and the gallop tier reaches both through `actor:Fall` without touching
      any data this mod ships. What governs the stand-up is a terminator on
      vanilla's `BlendRagdoll` option, which resolves through
      `ActionController`; this mod redirects only `AnimDatabase3P`,
      deliberately, so an override of it is never read.

      The best lead is an accident: Mutt walked onto a downed guard and the
      wait grew. A fixed duration cannot do that, so the wait is a condition
      being tested rather than a timer running out, and something about the
      body or the space above it is what fails the test. That reframes the
      problem and is worth more than another parameter sweep.
      `g_hitDeathReactions_disableRagdoll`, which disables switching to
      ragdoll at the end of animations, is the one setting in reach untried.
- [x] A polearm guard's get-up plays wrong: he turns roughly a hundred and
      eighty degrees near the end of it and then swings back. Measured, and it
      is not this mod's. The turn tracks a drawn halberd exactly, at 114 to 178
      degrees against 2 to 6 for anyone else, and the gallop tier reproduces it
      at the same magnitudes through `actor:Fall`, which plays no clip this mod
      ships. The get-up carries no weapon tag to vary, four options per
      direction and nothing else, so there is nothing here to change.
- [x] Fixed. A polearm guard took no walk stagger at all, where every other
      NPC staggers reliably at that tier. The reaction was suppressed, and
      `SuppressStaggerInCombat` was doing it.

      `IsCombatCollision` returns true if the player is in danger **or the
      victim has a weapon drawn**, and the walk branch suppressed the stagger
      whenever that combined signal was true. The drawn weapon half was written
      believing townsfolk never walk around armed. A guard carrying a polearm
      holds it on patrol all day, so he read as armed permanently and could
      never be staggered.

      Instrumented with `DiagnoseMisses` on: impacts on the polearm guard
      logged `armed=true/true combatScale=2.2` and produced no stagger, against
      `armed=false/true combatScale=1.0` and a stagger for a sword guard beside
      him. The check now returns the danger signal separately and the walk tier
      suppresses on that alone, so only a real fight skips the stagger.

      The pattern that prompted the look was real but coincidental: the
      get-up turn was vanilla's, and this one is the mod's own suppression.
      What polearm carriers share is only that they hold their weapon.

## Phase 2: Mass, armor and momentum

Scale the physical response to what the target is made of.

**Scope boundary.** Vanilla converts a collision hit whose rider is the player into a real,
player-attributed `combat:hit`, carrying the `hitStrength` this mod sends. The engine then
resolves that hit against the target's armor itself. Armor therefore already mitigates
damage downstream of the mod, and a second armor model here would double-count. The engine
owns armor against damage, and `hitStrength` stays chosen by speed alone. This phase owns
the impulse and the horse's side of the impact, neither of which the engine derives from
armor.

- [x] Establish in game what the current build already causes. Damage lands with no damage
      code in the mod. Nothing continues after the hit, so no bleeding follows. No bounty is
      registered. Armor mitigation cannot be read yet, because one gallop impact cost the
      victim nothing at all while still knocking her down.
- [x] Establish how often the damage half fails. It does not: 23 of 23 repeated trot impacts
      across two unarmored targets cost health, 12 of them on a female target. The single
      zero-damage impact recorded earlier is an outlier rather than a systematic drop, and
      the female path is not implicated.
- [x] Compare armored against unarmored damage at the same tier. An armored guard takes 3.90
      per trot impact over 17 landed impacts against 4.49 over 23 unarmored, which is 87 per
      cent. The difference is 0.59 against a standard error of 0.41, so at this sample size it
      cannot be separated from zero. Whatever the engine applies for armor against a collision
      hit, it is small.
- [ ] Decide where fall damage sits in the Phase 2 scope boundary. If the impulse causes damage
      by throwing the target, then scaling `impulseScale` by armor and mass also scales damage,
      and the split between what the engine owns and what the mod owns does not hold as written
      at the top of this phase.
- [x] Read an entity's carried items and their weights, generic over the
      entity so Phase 3 barding uses the same call on the horse.
      `inventory:GetInventoryTable()` returns the item WUIDs and
      `ItemManager.GetItem(wuid)` returns `class`, a GUID that joins to
      `pickable_item.item_id`. `ItemManager.GetItemUIName(class)` turns that
      into a readable name. No bind reports which items are equipped, but an
      NPC carries only what it wears plus a few trinkets, so filtering the
      inventory to the classes in the `armor` table is equivalent for a
      target. `human:GetItemInHand(hand)` reports a held weapon, and only
      while it is drawn.
- [x] Closed, not achievable. Unarmored targets taking proportionally heavier knockback
      than armored ones cannot be delivered by scaling this mod's impulse, because that
      impulse does not decide how far a body travels. Three gallop rides, one applying
      velocity and two the shipped impulse, produced the same spread of travel, and within
      one ride the weakest applied figure moved a mailed guard furthest. What throws a body
      is the engine's own collision between a ten-meter-per-second horse and a person.
      `armorImpulse` still scales a contribution that does not move anybody.

      Retained below for the reasoning only.

      Original item: unarmored targets take proportionally heavier knockback and armored
      targets are moved less, through one multiplier on `Ragdoll`'s `impulseScale`. A naked target reaches 1.50
      and a target in mail 0.41, against 1.00 at `ArmorReferenceWeight`. Reopened: the
      multiplier is computed and logged on every impact but no longer governs what a player
      sees. `TrotReaction` has defaulted to `"fall"` since 4.2.0, and the trot branch reaches
      `Ragdoll` only under the `"ragdoll"` setting, so at trot the figure is applied to
      nothing. Gallop still passes it, and armored and unarmored targets are reported moving
      alike there too, which points at the horse carrying a victim it stays in contact with
      rather than at the impulse being wrong. Measure the two separately before changing
      either: an armor multiplier tuned against a distance the horse is dictating will be
      tuned to the wrong thing.

- [x] Prerequisite for the armor item above, and it was not the horse. A
      thrown body slid for meters after landing, so distance measured the
      surface as much as the impact. Damping the ragdoll through
      `SetPhysicParams(PHYSICPARAM_SIMULATION, ...)` cuts the ground covered
      after landing from 2.77 m to 1.09 m and narrows the spread from six
      meters to under four. Braking the horse hard on contact changed travel
      not at all, which rules the horse out as the thing carrying them.

- [x] Closed with the item above, on the same measurement. Armor knockback is not
      reachable by scaling the mod's impulse whatever the figure, because the horse's
      collision decides the throw. Raising `Knockback` far enough to matter throws victims
      distances that do not read as a person being hit by a horse.

      Original item: armor knockback, now measurable. The multiplier has always worked and
      the force it multiplies did not: `Knockback` of 50 is
      indistinguishable from applying no impulse at all, because an impulse
      of that size moves a body of 120 to 160 kilograms at about 0.6 meters
      per second. Raising it to 600 threw a villager 27 meters and threw one
      guard upward into the rider hard enough to nearly kill them, so
      `Uplift` has a hard ceiling that is a safety limit rather than an
      aesthetic one: the rider sits directly above the victim.

      **Stop using an impulse.** `Entity.SetVelocity` and `SetVelocityEx`
      exist, enumerated from the running game, and they state the outcome in
      meters per second instead of a force that has to be divided by a mass
      the code never knew. That is the whole reason 50 does nothing and 600
      throws a villager 27 meters: the same figure means different things
      against different bodies.

      With velocity set directly, `Knockback` becomes a speed a person can
      picture, armor modulates that speed, and the ceiling on `Uplift` is
      expressible as one too. `Entity.GetMass` is there for the cases where an
      impulse is genuinely wanted, and vanilla's own code applies impulses as
      `mass * force` for exactly this reason.
- [ ] Not being pursued. Striking a heavy target shows on the horse. The momentum half is not reachable
      for the same reason the knockback items above are closed, so what is left here is
      the visible half: rearing or checking the horse on a heavy impact.

      Original item: striking a heavy target strips the horse's momentum rather than only
      its stamina, and shows on the horse. `kcd_horse_controllerdefs.xml`
      declares a `Rear` fragment, so a heavy impact can rear or check the
      horse rather than only debiting a number the player cannot see. That is
      the horse's half of what armor should feel like.

      The engine names a `riderGuardRear` combat behavior alongside
      `riderGuardMovement`, `riderGuardJump` and the rest, so a rear while
      mounted is something the game already does rather than something to
      invent.
- [x] Shake the rider's camera on a gallop impact. Shipped in 4.13.0 through
      `actor:SetViewShake`, with a trot taking a fraction of it. Its frequency
      argument is a period rather than a rate: vanilla passes 1/20 and a first
      build passing 14 produced nothing at any amplitude. `actor:CameraShake`
      is not used, having no positional component.

      The rider also gets a blur pulse in first person, where the collision
      happens below the field of view and none of the ground effects are
      visible. `System.SetScreenFx` is the only Lua route to the post effects
      and `FilterBlurring_Amount` is clamped near 1.0, so the weight comes from
      the hold and a chroma shift rather than the number.

      Scoped to gallop by the rider. The rear above is stood down, so this
      carries the whole of the horse's side of an impact on its own, and it
      should read as the horse being checked rather than as a screen effect.
- [x] Stamina cost scales against armor weight, so a knight costs far more than a peasant.
      A multiplier on the existing per-tier cost, 0.79 for a villager against 2.00 for a
      target in mail, multiplying with the combat multiplier already applied and with the
      Phase 3 Horsemanship multiplier when it arrives.
- [x] Tune the two curves in play. The stamina half was too strong: ten minutes of free
      riding threw the rider nine times, and a gallop into an armored target in combat cost
      108 per cent of a 210 pool, emptying it outright. The base drains are halved, to 15 at
      trot and 22 at gallop, and the combat multiplier drops from 2.5 to 1.5. A rider can
      now cross a village on foot traffic all day, 17 trot impacts on villagers to an empty
      pool, while charging armored targets stays expensive, 7 on a mail guard and 3 on a
      knight in plate at a gallop in combat.

      The claim that the multiplier saturated around weight 32, so mail and plate cost the
      same, does not hold: with an exponent of 0.4 against a reference weight of 8 the 3.0
      ceiling is not reached until weight 125, and mail reads 2.01 against plate at 2.51.
      No clamp needed changing.
- [x] Decide a victim is hittable again by reading their state, not by waiting out a
      timer. `HitCooldownStateDriven` does it, on `actor:GetCurrentAnimationState`.

      The justification in this item was wrong and the measurement is worth keeping. It
      said an impact inside the recovery plays no reaction and often costs no health. In
      fact a second gallop impact on a victim face down in `BlendRagdoll` registers and
      costs a full 26 health; the gallop tier calls `Ragdoll` directly and has no
      animation in it, so "no reaction plays" was never true of it.

      What is true is that the victim does not move, because **an NPC standing up cannot
      be ragdolled by anything reachable from Lua**. Eight calls across the actor and
      entity binds all fail to reach the body, and two separate runs landed at 2532 ms,
      the same figure to the millisecond, which means the request is held until the
      get-up animation completes rather than processed late. Vanilla does the same thing to itself:
      `DEADANIM_TIMER` waits for the death animation before ragdolling.

      So the wait exists to prevent damage with no visible reaction, and to stop a trot
      restarting the fall clip from a pose the victim is not in.

      Why it matters, unchanged: the timer is shorter than the time a victim spends on the
      ground, so a second impact lands on someone already prone, no reaction plays because
      every reaction is a standing animation, and a third of those impacts cost no health.
      Controlled rides with twelve seconds between impacts produce neither symptom.

Data located. Armor weight is on `Libs/Tables/item/pickable_item.xml`, joined by `item_id`,
not on `armor.xml`. Target body mass is `normal_body_weight` on `soul_archetype.xml`: 160
for an adult NPC, 120 female, 80 child, against 1000 for a horse. Two traps in that data:
chain outweighs plate per piece, and horse tack is filed as armor, so any sum over a
target's armor must exclude saddle, bridle, shoe and spur.

Prerequisite met: pak asset overrides now work, which Phase 2 needs for any table data.

## Phase 3: RPG integration

Scope depends on the Phase 2 verification step. The first item below may already be wired
rather than missing.

- [x] Apply native blunt damage on high-speed impacts. Already wired: vanilla re-sends a
      player-ridden collision as a real `combat:hit` carrying this mod's `hitStrength`, and
      health drops on impact with no damage code in the mod. The step across the tier
      boundary is steep, roughly fivefold from trot to gallop on the same target.
- [ ] The injury system does not handle the consequences. Damage resolves within half a
      second and then stops: across 27 impacts no health reading at 3 seconds differed from
      the one at 500 ms. Reaching the injury system is separate work from causing the damage.
      This is a statement about the window after an impact and not about the total cost of
      being trampled, which the item above covers.

- [x] A victim shows they were hurt. `actor:AddBlood(zone, delta)` and
      `actor:AddDirt(delta)` mark a knocked-down victim with dirt on their
      clothes and blood on the side the horse struck, keyed off the impact
      direction. Shipped in 4.8.0. The marks are not permanent: a victim
      seen filthy came back clean after a night away.

- [x] An impact makes a noise. Not through the animation data, which cannot
      make a sound before its fragment starts, and not with any single
      trigger: the game has no sound for a horse striking a person because
      vanilla never makes one. It is layered from Lua instead, the horse's
      own `a_o_jump_landing` under a blunt body impact matched to the
      victim's armor, with an occasional bone crack at a gallop. The full
      1803-name vocabulary and how to validate a name are in the diary.

- [ ] Correlate the collision's severity with what the player sees and hears.
      The damage system is not fully mapped: what an impact actually costs a
      victim, and how that varies with speed and armor, is known only in
      outline. Once it is, the blood applied and the sound layers chosen can
      both follow from it, so a glancing shove and a killing gallop are told
      apart by the feedback rather than only by the tier they fell into.
      Raised by the rider while tuning the impact sound.

- [x] An impact throws up dust. Shipped in 4.13.0, from Lua through
      `Particle.SpawnEffect` rather than as a procedural layer in the animation
      data: a gallop impact plays no fragment at all, so authoring it per
      fragment would have reached only the trot tier.

      Two things were needed beyond the call. The spawn waits for the victim's
      vertical velocity to cross back up, which is the ground contact, because
      how far a body travels first depends on the angle it was struck at. And
      the position comes from a downward raycast rather than the body's own
      origin, which sits 0.65 to 0.77 m below the surface it rests on and
      buried the emitter on every collision.
- [x] The horse pays for a trampling spree. Not with health, which was built and
      removed: it worked and it was legible in the log, but from the saddle it was a
      second invisible stat racing stamina to the same outcome, and what it contributed
      was not legible from the saddle.

      What was wanted from it was one moment, so that moment is the feature.
      `HorseBoltsWhenSpent` gives a spent horse a `HorseBoltChance` of wanting nothing
      more to do with the rider: it empties the horse's health, which throws the rider
      and sends the horse off, and hands the health back three seconds later once it has
      gone. Emptying the health is used because it is the behavior observed in game,
      including accidentally in 2.0.0-dev1. `combat:stimulus:hostilePerception` does not
      reach a player horse, whose combat brain is a bare wait with no subtree to receive
      it.

- [ ] A victim shows the injury afterwards. A collision can take ninety per cent of
      someone's health and they stand up and walk off with dirt and blood on their
      clothes and nothing in how they move. Vanilla has states for this, and the mod
      already knows the victim's health at the moment of impact and already exempts them
      from the auto-cure daycycle. The route to find is which of the game's own injured
      or exhausted movement states can be set on an NPC and held, rather than authoring
      any animation.

- [x] Horsemanship level reduces stamina cost and the chance of being thrown. The skill
      is `horse_riding`, read with `soul:GetSkillLevel`, and it runs 0 to 20.

      Vanilla's own Horsemanship already governs how quickly a horse tires, so the mod's
      multiplier is faithful to the skill rather than inventing a use for it, and it
      compounds with vanilla's reduction.

      Linear across the scale, from ten times the stamina cost at 0 to 1.2 at 20. Two
      curved shapes do not work in game: one spends the benefit in the first few levels
      and leaves 13 riding like 20, and one withholding it to the last quarter makes
      every level under 16 identical. The brief it has to meet is that a novice cannot
      stay on the horse through an impact and a master can use the horse offensively.

          level   gallops  trots  guards
              0       1.2    1.8     0.6
             10       2.1    3.3     1.0
             20       9.7   15.2     4.8

      `HorsemanshipSeatChance` is the second half: up to a 60 per cent chance of keeping
      the saddle when the horse is finally spent, rolled only on the impact that empties
      it. Rolled on every impact it lets a rider stay on a horse already at zero and go
      on hitting people, which the log caught.
- [x] Horse barding increases impact force. Barding sits in the horse's inventory as
      ordinary equipment, so `ArmorOf` reads it unchanged: an unbarded mount reports one
      piece and about 8 weight, which is its tack, and that is the reference, so a player
      who never armors their horse sees no change.

      **Built and wired but not confirmed in game**, because no barded horse was
      available while it was being tested. The multiplier reads 1.00 on an unbarded
      horse, which is the only half that has been observed.

      Momentum loss is not implemented separately: the stamina cost already carries it.

## Phase 4: AI reaction

- [x] A brawl the town ignores: closed again, on evidence this time.
      `Entity.CreateLink` does create a link named `suppressAssaultReactions`
      from an NPC to the player, retrievable with `GetLinkTarget`, but it does
      not suppress anything. Thirty-three humans were linked, a civilian was
      ridden down in public, and a crime was reported; the victim was
      confirmed afterwards to have carried the link, so the test was sound.

      The behavior tree either keeps its own link store or needs the `Data`
      its own `AddLink` carries, which `questUtils.xml` sets an expiration
      into and which `CreateLink(name, targetId)` has no way to supply.
- [ ] Superseded: a brawl the town ignores. `Entity.CreateLink`, `GetLink`,
      `RemoveLink` and `CountLinks` all exist in Lua, which was checked and
      denied on the strength of the `C_ScriptBind*` headers alone. Those
      headers describe script binds, and the entity class table is not one.

      The mechanism to reach is the link `sa_duel.xml` adds between the
      duelist and the player, tagged `suppressAssaultReactions`, which
      `checkAssaultSuppression` in `sb_combat.xml` walks and which gates the
      assault perceptible volume that tells every bystander an assault
      happened. If a Lua-created entity link is the same object the behavior
      tree reads, a fight nobody reports is one call away. If it is a
      different system sharing a word, the item closes for a better reason
      than last time.

      One probe answers it: create the link between a victim and the player,
      punch the victim in front of a witness, and see whether a crime is
      raised.
- [x] Repair a victim the player has beaten. Shipped in 4.7.4. Every provoked
      fight now ends by restoring what the victim thought of the rider before
      he was provoked, less a standing cost, floored clear of the 0.2
      threshold that makes him flee on sight. He is checked a second time once
      the rider has finished with him, because a victim beaten while standing
      up loses more afterwards. Measured: a victim at 0.000 restored to 0.418
      and walking his routine, talking and trading.

      The mechanism below was the right table and the wrong conclusion about
      the flee. Reputation decides whether he runs *again*; it does nothing to
      a run already under way, and a run ends on its own.
      `soul:ModifyPlayerReputation('best_friend')` is +2 with
      `can_change_hostility` true, and `surrender_step` is +0.25 with the same
      flag. A punch is `hit_melee_weak`, -0.2, and it sets that flag; only a
      change carrying the flag can clear it. This is why paying a fine never
      repairs a victim and surrendering to him does.

      Whether the mod should offer any of this is a design question, but it
      is no longer an open mechanical one, and it means a victim ruined by
      testing can be restored rather than left.
- [ ] A provoked victim pulls the rider off the horse before fighting. Retaliation
      currently has them throwing punches at the horse, which is brave but reads as
      confusion. Pulling the rider down first and then fighting is what the vanilla
      action is for: `CanHorsePullDown` and `RequestHorsePullDown` are an interactor
      action offered beside knockout and hunt attack, with `wh_cs_HorsePullDownAngle`
      and two companions governing the geometry.

      Scoped to retaliation rather than to impacts. Nothing about the action works
      against a horse at speed; it belongs at the walk tier, where a victim who has run
      out of patience is standing next to a rider who is barely moving.

- [ ] Show the surrender prompt during a provoked brawl. Surrendering to a
      victim resolves the encounter cleanly, but the on-screen input hint
      that appears when guards attack does not, so nothing tells a player
      the option exists. The engine carries
      `wh::xgenaimodule::BehaviorTree::C_SurrenderActionHint`,
      `S_SurrenderActionHintContext` and a `SurrenderActionHint` string, so
      the hint is a behavior tree node. Whether Lua can raise it is unknown.
- [x] Women run and fetch a guard rather than fighting. Shipped in 4.10.0.
      `sb_combat.xml` tests `b_soul.gender == male` after the context option is read, so a
      woman falls through to the report and flee branches; that fall-through is the
      feature. `CanRetaliate` returns "fight", "alarm" or "none", and a woman gets neither
      the `alwaysFightWhenHit` option nor the offense release, both of which act on a
      fight subtree she cannot enter. Morale does not separate the sexes, measured across
      twenty one NPCs, so the sex check is honest rather than a shortcut.

      The mechanism is likely already there and needs confirming rather than building. The
      `combat:stimulus:hostilePerception` split is the behavior tree's own and is decided
      by morale, not by anything this mod picks: a civilian must clear a `MoraleCheck` at
      0.550000 against a soldier's 0.400000, and in the one probe run seven of eight NPCs
      fled while a guard at morale 0.668 closed and attacked. If female civilians sit below
      that threshold as a population, sending the same message to everyone already produces
      "men may fight, women run" without a sex check anywhere in the mod, which is the
      better implementation by some distance.

      So the first step is a reading, not a change: sample `GetDerivedStat('mor')` across a
      market's worth of NPCs and see whether the female distribution actually sits under
      the civilian check. Only if it does not does an explicit branch on the `NPC_Female`
      class become the fallback.

      The "call for the guards" half may need nothing at all. Three non-guards ridden down
      at trot each registered the attack and ran for a guard to report it, so reporting is
      the crime system's and is already working; what is unverified is whether a victim who
      is fleeing under `hostilePerception` still reports, or whether the flee replaces the
      report.
- [ ] Not being pursued. The collision bark fires while the victim is
      still falling or lying as a ragdoll, which is nobody's idea of speaking,
      and it cannot be moved: see the evidence under the item below.

      Reachable. The bark is vanilla's, not this mod's: it fires with
      `SendHitReaction` switched off, and `sb_switch_hitreactions.xml` raises
      it as `dialog:monologRequest` carrying the metarole `KOLIZE_S_HRACEM`,
      or `KOLIZE_S_HRACEM_LEHKA` for a light contact and
      `KOLIZE_S_HRACEM_NA_KONI` for a mounted one. A vanilla quest script
      removes and restores those metaroles with
      `soul:RemoveMetaRoleByName` and `soul:AddMetaRoleByName`, so the same
      calls can silence the request at the impact and send one deliberately
      once the victim is upright.

- [ ] Not being pursued. Give each tier its own voice. `dialog:monologRequest` is how the game
      raises spoken reactions and vanilla sends it 958 times across its AI,
      selecting a line by metarole. Eighty metaroles are in use and several
      suit a trampled victim better than the collision bark does:
      `RANENY_NA_ZEMI`, wounded and on the ground; `VZDAVANI_BARK`,
      surrendering; `PRANYR_KRIK`, a scream; `ZASAH_ZBRANI_IGNOROVANY`, a hit
      shrugged off. A grumble at walk, something hurt at trot and a scream at
      gallop costs one message per impact and no new audio.

      Composes with the item above: silence vanilla's bark at the impact and
      send the chosen line once the victim is upright.

      **Both are parked. A spoken line cannot be raised from Lua, but the
      data route is unbuilt rather than impossible.** Five approaches were
      tried, all accepted without error and all silent.

      Sending `dialog:monologRequest` the way vanilla's own
      `DialogUtils.RequestPlayerMonologByMetarole` sends it, with
      `SendMessageToEntityData` and `Utils.makeTable`. Tried with and without
      `lookAtId`, `priority` and `overrideContextSuppress`; on a merchant, a
      village guard and a refugee; with the near-miss role
      `ZASAH_ZBRANI_IGNOROVANY` and with `KOLIZE_S_HRACEM_NA_KONI`, the role a
      target demonstrably speaks when ridden into.

      Assigning the role to the soul first with `soul:AddMetaRoleByName`, which
      is a live function and returns cleanly, then sending. Silent on a beggar
      and on a guard.

      The payload is not the problem: `Utils.makeTable` builds every declared
      field with correct defaults. Nor is victim state: `actor:CanTalk()`
      returns false for every NPC nearby, including ones that plainly converse.

      What settles it is that vanilla's own helper fails the same way.
      `DialogUtils.RequestPlayerMonologByMetarole`, called unmodified on the
      player with a valid metarole, produces nothing, and that helper is
      **defined in the shipped scripts and never called by any of them**.
      Warhorse wrote a Lua entry point for this and never used it. Every bark
      in the game is raised inside a behavior tree, sent by the speaker to
      itself.

      `DialogModule.StartMonolog(entity.id, topicId)` is the real API and it
      does drive the dialog system: `IsSoulInDialog` goes false, true, then
      false again, a complete cycle, with no audio at any point. It behaves
      the same with a topic the target's own voice has 63 recorded lines for,
      with the victim ragdolled through `actor:Fall`, and through vanilla's own
      `DialogModule.ForceDialog` and `RequestPlayerMonologByMetarole`. Note it
      leaves souls flagged in dialog until a save reload.

      **The voice and topic mapping is fully derivable from shipped data**, and
      is worth keeping: `soul.xml` gives `soul_id` from a soul name,
      `v_soul_character_data.xml` maps that to `voice_id`,
      `v_voice_abbreviation.xml` gives the four letter code, and the dialog ogg
      filenames in `Localization/English.pak` encode
      `<voice>_t<topic>_s<sequence>_`. So the exact topics any character can
      speak are computable offline. Collision barks turn out not to be authored
      for refugee voices at all, which explains much of the silence: `kmic` and
      `pdea` carry about four hundred topics each and not one collision topic.

      Two routes remain, neither closed:

      Override `sb_switch_hitreactions.xml`, where the send works because the
      tree sends to itself. Preserved in `mod_xmls.disabled/`. That reopens the
      Lua-only decision made in 2.0.0-rc1 and is a compatibility trade rather
      than a technical problem.

      Or ship the audio, which is the same move already made for animation.
      Vanilla would not play this mod's fall clips either until it shipped
      `hcm_male_database.adb` and pointed the game at it. The dialog lines are
      75,000 loose oggs streamed by the dialog system with no trigger name, so
      the equivalent is an FMOD bank containing the wanted lines plus a
      `Libs/GameAudio/*.xml` declaring triggers into it: the parser resolves
      events by `fmod_name` and never reads `fmod_id`, the config loader
      wildcard scans its folder, and `<FmodBank>` exists in the schema because
      vanilla uses it for `cin_test.bank`. Then a bark is an
      `ExecuteAudioTrigger` call like any other sound. It needs FMOD Studio and
      a decision about redistributing Warhorse voice assets.
- [x] **A trampling death can now be suppressed**, which every earlier entry
      here treated as out of reach. `CollisionIsCrime` gates `SendCombatHit`,
      so it always stopped the mod reporting a collision, but a victim
      trampled to death still brought the guards down because the engine
      resolves the trample and a kill the engine resolves belongs to the
      rider. `ApplyImpactDamage` passes no attacker when the switch is off and
      now kills an unarmored victim outright at a gallop, so the trample never
      gets to be the cause. Measured, one variable changed: damage off, four
      passes, trample kills, crime flag; damage on, one pass, no flag.
      Suppression follows the killing blow rather than the setting, so an
      armored victim finished by repeated trampling still flags.
- [x] Trampling triggers the crime system. A fatal outcome is what turns it on: knocking
      a guard down registers no bounty, but trampling a villager to death brought the
      guards down on the rider and carried a jail sentence, with no crime code in the mod.
      The threshold was the outcome rather than the hit, and non-lethal
      trampling being free is closed: 4.3.0 sends a real, player-attributed
      `combat:hit`, so riding someone down at trot or gallop is charged as
      a brawl whether or not they die. `CollisionIsCrime` turns it off.

The `hitReaction` message the mod already sends is the hook for both, and vanilla
distinguishes light from normal collisions through the `KOLIZE_S_HRACEM` and
`KOLIZE_S_HRACEM_LEHKA` dialog metaroles.

## Phase 5: Tuning the rear

Five items raised after 4.19.0 shipped the feature. Where a note below says
something is established, it was checked against the code or a measurement; the
rest are open questions.

### 1. The lunge passes through buildings. Fixed in 4.19.1.

The rear-and-charge drives the horse into geometry it should be stopped by, and
the rider can aim it straight at a wall.

The obvious lever is probably not the answer, so it is worth saying why before
anyone spends a ride on it. Victims stopped being carried into walls because
`SetMovementControlledByAnimation(false)` hands them back to entity-driven
movement a tick into the reaction. The lunge's second half already runs that
way: at `ExitTime` 0.8 the fragment's MovementControlMethod drops `Horizontal`,
`XyMove`, `ZMove` and `Rotate` to 0 and sets `Inertia` to 1, so the horse is
traveling under its own momentum, not being carried by the clip, and it clips
anyway.

Neither guess above was right. `Horizontal` in the fragment is CryEngine's
`EMovementControlMethod`, and it shipped as `2`, `eMCM_Animation`: the
animation moves the horse and collision is off. The `Jump` procedural was not
involved. Since the 5.4 m of root motion cannot be shortened, and neither of
the other movement control methods works, the horse is stopped short of
anything solid instead. See the diary and TECHNICAL_DETAILS.

### 2. The lunge threads between people

Riders can pass between two NPCs standing close together without touching
either, which a charging horse should not manage. The lunge is scored by the
ordinary detection loop, so this is the horse footprint, `HorseFrontReach`
1.05, `HorseHalfWidth` 0.70 and `HorseRearReach` 0.20, and not any of the
`Rear*` settings.

Worth doing after item 1, not before: if the fix for the clipping changes how
far or how fast the lunge travels, the footprint would have to be tuned twice.

### 3. Rearing has no sound of its own

Both moves borrow an existing tier's sound. The rear on the spot plays
`ImpactSoundTrot`, and the lunge is forced to gallop for its duration so it
plays `ImpactSoundGallop`. Neither reads as hooves coming down.

Wanted: a sound built for the rear, with hoof layers, and for the lunge
specifically the `n_lu_log_ground` layer dropped from what it plays now.

Two things constrain this. The log layer belongs to `ImpactSoundGallop`, which
every ordinary gallop collision uses, so it cannot simply be deleted: the rear
needs its own layer set rather than an edit to a shared one. And the hoofstep
event has been rejected here once already, on the gallop tier, for a reason
that would apply again: `hs_hp_soil` is `hoofsteps_player`, which ignores
position, played at fixed full level under every other layer, and could not be
brought down. `ImpactSoundWalk` still uses it, so it is not unusable, but any
hoof layer needs its level checked from the saddle before it is kept.

Also unresolved: the report is that the rear has no impact sound at all. The
code does call `PlayImpactSound` on the rear strike path. Whether that means it
plays and does not read as a rear, or does not play, is one log line away and
should be settled before any samples are chosen.

### 4. Fear and morale around a rear

Today a rear either hits someone or does nothing to them. The idea is three
bands rather than one.

- The hooves land, as now, inside `RearReach` and `RearArc`.
- A wider and longer band where nobody is touched but the horse is frightening:
  they break and flee.
- Some of those instead stand and turn on the rider, decided by a morale check,
  feeding the existing retaliation system rather than a second one beside it.

The largest item of the five and the only one that is a feature rather than a
defect. It should go last, because the first two change what the lunge does to
the people around it and this is built on top of that.

## Phase 6: The balance pass

Deferred deliberately, and it is the largest item on this document. Three
numbers govern how hard a collision lands and none of them is where it should
be:

- **Armor mass scaling.** What a victim's ragdoll weighs, which is the mod's
  only real lever on how far the horse's collision throws them. An unarmored
  villager is written down to about 42 kg and flies; a mailed guard goes to
  several thousand and barely moves. The heavy end is already saturated, so the
  curve is doing most of its work in a narrow band.
- **Armor defense scaling.** What armor takes off the damage. A charge worth
  110 becomes 12 against chainmail, which is a factor of nine across a range
  the player experiences as "wearing armor or not".
- **Base damage per tier.** The figures the other two scale.

The three are not separable. Changing any one of them moves what the other two
are compensating for, which is why this is a single project rather than three
adjustments and why it cannot be done incrementally alongside feature work.

**It comes after every pillar is implemented, not before.** Each pillar adds
another tier that has to be balanced against the rest, and tuning against a set
that is still growing means tuning the same numbers repeatedly. The charge is
the current example: it arrived with a base of 110 and an armor curve inherited
from the gallop, and neither figure was chosen for it.

### The rider's starting position on mass

Unarmored NPCs should sit at their normal mass, and the curve should scale
**up** from there rather than writing light victims down below it. Today the
curve runs in both directions off a `RagdollMass` of 100, so an unarmored
villager is written down to about 42 kg and a mailed guard up to several
thousand.

The evidence that prompted it: over 40 logged throws, unarmored victims average
roughly three times the armored distance, and the spread within a single mass is
the striking part. Every 42 kg victim ranges from 0.07 m to 7.71 m on the same
tier with the same impulse. Nothing in the mod varies between those; the contact
angle does, and a very light body converts more of that variation into distance.
Raising the unarmored floor compresses the whole distribution rather than
capping the outliers.

Ruled out as the cause while investigating this, so it does not need testing
again: the occasional 26 to 28 m/s reading in the horse's derived speed is a
sampling artifact, not a real discharge. Those samples produced throws of 0.48,
0.21 and 0.06, while the largest launch seen had an ordinary 13.50.

Nothing here is a defect. The mod is playable at these values and they are
deliberate placeholders.


## Phase 7: The crime the mod cannot see

The damage ownership work in 5.0.0 closed every path where the mod's own
collision handling let the engine land the killing blow. One hole remains and it
is different in kind, because the mod is not involved in it at all.

A victim knocked down by a trot read 68.7 health, and 17.7 when the next impact
landed: fifty-one health gone with no damage line of the mod's between them, on
a body lying inside the mod's own fall fragment while the horse stood over it.
The rider was charged with a crime and the mod had attributed nothing.

It is not bleeding. A trace sampling a victim every 250 ms for ten seconds is
flat after the impact resolves, in every case:

    HealthTrace rat_woman3 tier=Trot from=100 every=250ms [94,94,83,83, ...83]

Two steps, the engine's collision and then the mod's damage, and then nothing
moves for ten seconds. It was not a save reload either, which would have
restored the victim to the save's figure.

So it is the engine charging its own collision repeatedly against a body that
cannot get out from under the horse. **None of the damage ownership work reaches
this**, because the mod never sends that hit and so has nothing to attribute or
withhold. Reclaiming the health afterwards would not help either: the crime is
raised by the hit event, not by the death.

Nothing has been tried. The obvious first question is whether the victim can be
moved, unphysicalized, or made non-collidable for as long as the horse is
standing on them, and whether any of that is reachable from Lua without
wrecking the body the way `RagDollize` wrecks a pose.

The instrument that produced the evidence above, `TraceHealthLoss`, was removed
before 5.0.0 shipped. It is in the history if it is wanted again.
