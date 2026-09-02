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
- [ ] NPCs carrying something keep hold of it through the stagger, but the clip is authored
      for empty hands, so the arms swing through a pose the item was never meant to follow.
      A controlled A/B showed the `ColliderMode` layer was never the cause of anything: the
      item stays in hand with and without it. The goal is now the vanilla behavior instead,
      drop the item, react, pick it back up. `sb_combat.xml` has a `dropItems` tree that tags
      the dropped item `panicDrop`, and `so_slot.xml` recovers it. Cost is shipping a 133 KB
      behavior tree, which has no additive path, so it reintroduces the whole-file conflict
      surface 3.0.0 removed in exchange for a cosmetic fix. Parked unless an additive
      approach to behavior trees appears.
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
- [ ] Carried items are dropped when an NPC is knocked down at trot or gallop. That is the
      physics ragdoll path, separate from the walk-tier stagger, and predates 2.0.0.
- [ ] A one-frame animation fires as an NPC stands up from a trot ragdoll. It does not
      interrupt the recovery, which completes normally. Seen on both a female villager and a
      male guard, so it is not the female Mannequin data. A single frame is the documented
      signature of `StartInteractiveActionByName` accepting a name that resolves to no
      fragment. It coincides with the get-up, which is also when delayed health loss appears.
      Cosmetic.
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
      Whether an animated knockdown suits a full gallop is a design question
      rather than a technical one: a rider at speed should arguably throw a body.

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

- [ ] Shorten the wait between a trot victim going limp and standing up.
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
- [ ] Account for health lost between impacts. Five rides, three explanations tried and
      discarded: fall damage at the get-up, a contact the footprint rejects, and a probe that
      read health after the impulse. Reversing that call order changed neither the rate, still
      2 of 11 intervals, nor the per-impact cost, which fell slightly rather than rising. The
      rate holds near one interval in five across every ride. The watch now records the rider's
      distance and speed at the moment health moves, which distinguishes a contact from
      anything that happens while the horse is elsewhere.
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
- [ ] Unarmored targets take proportionally heavier knockback and armored targets are moved
      less, through one multiplier on `Ragdoll`'s `impulseScale`. A naked target reaches 1.50
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

- [ ] Armor knockback, now measurable. The multiplier has always worked and
      the force it multiplies did not: `Knockback` of 50 is
      indistinguishable from applying no impulse at all, because an impulse
      of that size moves a body of 120 to 160 kilograms at about 0.6 meters
      per second. Raising it to 600 threw a villager 27 meters and threw one
      guard upward into the rider hard enough to nearly kill them, so
      `Uplift` has a hard ceiling that is a safety limit rather than an
      aesthetic one: the rider sits directly above the victim. Raise
      `Knockback` alone, moderately, and measure with the slide now removed.
- [ ] Striking a heavy target strips the horse's momentum rather than only
      its stamina, and shows on the horse. `kcd_horse_controllerdefs.xml`
      declares a `Rear` fragment, so a heavy impact can rear or check the
      horse rather than only debiting a number the player cannot see. That is
      the horse's half of what armor should feel like.
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
- [ ] Skip or soften an impact against a target that has not recovered from the last one.
      `HitCooldownMs` is 3000, which is shorter than the time a victim spends on the ground,
      so a second impact lands on someone already prone: no reaction plays, because they are
      not standing, and a third of those impacts cost no health. Controlled rides with twelve
      seconds between impacts produce neither symptom.

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

- [ ] A victim shows they were hurt. `actor:AddBlood(string, number)` and
      `actor:AddDirt(number)` are both available, so someone ridden down at
      trot can stand up bloodied and muddy instead of immaculate. Cosmetic,
      cheap, and it is the feedback that makes an impact read as an injury
      rather than as a stumble.

- [ ] An impact makes a noise and throws up dust. Vanilla ships 39
      procedural clip types and this mod uses four of them, and two of the
      rest are exactly this:

      `PlaySound` takes a `StartTrigger`, a `Radius` and an obstruction
      type, and vanilla drives combat impacts through it with triggers named
      like `c_w_sword_clinch`. A trot collision is currently silent apart
      from the victim's bark.

      `ParticleEffect` takes an `EffectName`, an `AttachmentName` for the
      joint to hang it on, position and rotation offsets, and `KillOnExit`.
      Dust off the ground where a body lands, and it is authored per
      fragment rather than needing anything in Lua.

      Both ride along in animation data already generated, which makes them
      the cheapest immersion on this list. Neither has been tried.
- [ ] Horsemanship level reduces stamina cost and the chance of being thrown.
- [ ] Horse barding increases impact force and reduces momentum loss.
- [ ] A braced polearm hit head-on acts as a wall: heavy stamina cost, near-certain dismount.

## Phase 4: AI reaction

- [ ] Riding through a packed group inflicts a morale shock, so lightly armored enemies
      break and flee using native AI.

- [ ] The collision bark fires while the victim is still falling or lying as
      a ragdoll, which is nobody's idea of speaking. It should land as they
      get up.

      Reachable. The bark is vanilla's, not this mod's: it fires with
      `SendHitReaction` switched off, and `sb_switch_hitreactions.xml` raises
      it as `dialog:monologRequest` carrying the metarole `KOLIZE_S_HRACEM`,
      or `KOLIZE_S_HRACEM_LEHKA` for a light contact and
      `KOLIZE_S_HRACEM_NA_KONI` for a mounted one. A vanilla quest script
      removes and restores those metaroles with
      `soul:RemoveMetaRoleByName` and `soul:AddMetaRoleByName`, so the same
      calls can silence the request at the impact and send one deliberately
      once the victim is upright.
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
