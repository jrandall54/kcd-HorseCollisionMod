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
- [ ] The horse and a staggering NPC can still push against each other instead of clearing
      past. Setting the animation's collider mode to `Disabled` did not resolve it, and it
      matches vanilla behavior when riding head-on into someone. Revisit with Phase 2
      momentum, if at all.
- [ ] Carried items are dropped when an NPC is knocked down at trot or gallop. That is the
      physics ragdoll path, separate from the walk-tier stagger, and predates 2.0.0.
- [ ] A one-frame animation fires as an NPC stands up from a trot ragdoll. It does not
      interrupt the recovery, which completes normally. Seen on both a female villager and a
      male guard, so it is not the female Mannequin data. A single frame is the documented
      signature of `StartInteractiveActionByName` accepting a name that resolves to no
      fragment. It coincides with the get-up, which is also when delayed health loss appears.
      Cosmetic.
- [ ] **Exploit.** Repeated impacts drive a victim's exhaustion to its ceiling and it does not
      recover quickly. Every NPC near a tested area read `exhaust=100`, including five guards
      who could swing at the player indefinitely without landing a meaningful hit. A rider who
      knocks down enough guards can put the controller down and take no real damage, and an
      NPC pinned at the ceiling can freeze in a hurt animation. Vanilla applies the exhaustion
      from the real `combat:hit` the mod causes, so the mod is the source even though it never
      touches the stat. Needs a limit on what one rider can accumulate on one victim rather
      than a change to the reaction itself.
- [x] An NPC that stops responding after repeated impacts is exhausted, not broken. A guard
      held in a hurt animation for several minutes read `exhaust=100` against a recovered
      `stamina=121`, so the state is vanilla's and it resolves on its own. Repeated impacts
      drive exhaustion to its ceiling, which is a consequence of testing rather than a defect.
      The `Animation-queue overflow` the engine logs alongside it is a symptom of queued
      reactions, not the cause.
- [x] Reactions firing at the wrong tier. Tracked under Reaction reliability
      below.

## Start here

Two separate defects, found by testing rather than reading, and neither is what
earlier entries in this file assumed. Both are open.

### 1. Collisions damage the victim, and the mod causes it

The mod ragdolls its victim, which turns them from an animation-driven actor
into a physics object. The moving horse then collides with that body and the
engine charges damage from the velocity delta, at
`CollisionVelocityDeltaToDmgR = 0.25` in `Libs/Tables/rpg/rpg_param.xml`.

Proven twice. Ragdolling an NPC 7.3 m away with no horse nearby costs nothing.
Setting that parameter to 0 in a loose table gives 15 impacts at exactly zero
damage.

- [ ] Throw the victim sideways. `Ragdoll` currently aims its impulse along the
      horse's velocity, driving the victim down the horse's own line of travel
      and maximising the overlap. A lateral component clears them instead.
      Cheapest fix, changes nothing else, and the impact telemetry makes a
      before-and-after unambiguous.
- [ ] If that is not enough, delay the ragdoll a few hundred milliseconds so the
      horse has passed before the body becomes physical.
- [ ] Last resort, an animated knockdown through the `AnimationControlled` path
      the walk stagger already uses, which never creates a physics body. Walk
      impacts have cost zero health all session, which is the existence proof.

Overriding `rpg_param.xml` is rejected: one global value read by everything that
resolves a physical collision, including the player's own, and shipping a
vanilla table reintroduces the conflict surface 3.0.0 removed.

### 2. Repeatedly ragdolled NPCs wedge, and it is not the damage

An NPC hit enough times stops responding: alive, undamaged, holding whatever
idle it was in, refusing to resume its schedule. Combat claims it normally and
hands it back to the wedge afterwards.

With collision damage zeroed, a victim still wedged **at 96.4 health**, in an
ordinary standing idle rather than a wounded pose. So this is independent of
damage, of health, and of the wounded animation.

Ruled out by test, not by reading: injury buffs, the Energy stat, the animation
queue, the mod's Mannequin data, unconsciousness buffs, damage, and health.

- [ ] Raise `KnockdownRecoveryMs` well above 6000 and see whether the wedge
      stops. A victim hit again while still recovering is the most plausible way
      to wedge the state machine, and it is one setting and one ride.
- [ ] If that is not it, instrument what the victim's behavior tree is doing.
      `XGenAIModule.GetBrainVariable(entity, name)` reads a tree's variables and
      is the only unexplored route; twelve `b_` names returned nil against an
      entity id, so the addressing needs settling first, WUID against entity id.

### Three things to remove before either fix lands

All three treat symptoms of causes since disproven, and all three are committed
on `fix/collision-exhaustion`:

- [ ] `MinVictimHealth` and `HoldVictimAboveFloor`. Cannot fix the lockup, which
      happens at full health.
- [ ] `ClearInjuries` and the injury buff table. Injuries are not the cause and
      the cure never released a victim.
- [ ] `LimitExhaustion`, `EnforceExhaustLimits` and `ExhaustWatch`. Built on an
      inverted reading of the Energy stat, already disabled by default.

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
Download drops from 195,284 to 24,847 bytes.

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
- [ ] Read an entity's carried items and their weights, generic over the entity so Phase 3
      barding uses the same call on the horse. `inventory:GetInventoryTable()` returns the
      item WUIDs and `ItemManager.GetItem(wuid)` returns `class`, which joins to the item
      tables for weight. No bind reports which items are equipped, but an NPC carries only
      what it wears plus a few trinkets, so filtering the whole inventory to armor classes
      is equivalent for a target.
- [x] Unarmored targets take proportionally heavier knockback and armored targets are moved
      less, through one multiplier on `Ragdoll`'s `impulseScale`. A naked target reaches 1.50
      and a target in mail 0.41, against 1.00 at `ArmorReferenceWeight`.
- [ ] Striking a heavy target strips the horse's momentum rather than only its stamina.
- [x] Stamina cost scales against armor weight, so a knight costs far more than a peasant.
      A multiplier on the existing per-tier cost, 0.79 for a villager against 2.00 for a
      target in mail, multiplying with the combat multiplier already applied and with the
      Phase 3 Horsemanship multiplier when it arrives.
- [ ] Tune the two curves in play. The stamina half is too strong at its defaults: ten
      minutes of free riding threw the rider nine times, a single trot into a guard drains 90
      of a 210 pool, and a gallop into an armored target in combat empties it outright. The
      multiplier also reaches its ceiling at around weight 32, so a guard in mail and a knight
      in full plate cost the same.
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
- [ ] Horsemanship level reduces stamina cost and the chance of being thrown.
- [ ] Horse barding increases impact force and reduces momentum loss.
- [ ] A braced polearm hit head-on acts as a wall: heavy stamina cost, near-certain dismount.

## Phase 4: AI reaction

- [ ] Riding through a packed group inflicts a morale shock, so lightly armored enemies
      break and flee using native AI.
- [ ] Bumping someone at walking pace annoys them; trampling triggers the crime system.
      Construction rather than verification: a gallop impact that knocks a guard down
      registers no bounty, so a player-attributed `real(true)` hit is not on its own enough
      for the crime system. Whether a witness or a fatal outcome changes that is untested.

The `hitReaction` message the mod already sends is the hook for both, and vanilla
distinguishes light from normal collisions through the `KOLIZE_S_HRACEM` and
`KOLIZE_S_HRACEM_LEHKA` dialog metaroles.
