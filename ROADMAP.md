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
      behavior tree, which has no additive path.
- [ ] The horse and a staggering NPC can still push against each other instead of clearing
      past. Setting the animation's collider mode to `Disabled` did not resolve it, and it
      matches vanilla behavior when riding head-on into someone. Revisit with Phase 2
      momentum, if at all.
- [ ] Carried items are dropped when an NPC is knocked down at trot or gallop. That is the
      physics ragdoll path, separate from the walk-tier stagger, and predates 2.0.0.
- [x] Reactions firing at the wrong tier. Tracked under Reaction reliability
      below.

## Development tooling

Complete, merged after 2.0.0. Not a gameplay phase, but it changes how every phase below
gets tested.

- [x] Deploy straight into `Mods\` without Vortex, with the game path resolved rather than
      hardcoded so a clone builds on any machine.
- [x] Hot reload the mod's Lua into a running game, no restart and no save reload.
- [x] Hot reload the Mannequin animation databases the same way. Needed the ADB files
      written loose *and* `mn_allowEditableDatabasesInPureGame`, which ships at 0.
- [x] Live telemetry over CryEngine's remote console, with backend chatter filtered out.
- [x] Read the mod's live state out of the running game, which settles questions that
      guessing does not.
- [x] Publish a release to Nexus Mods without the browser, through their v3 API.
      Not a GitHub Action: the build reads the game's own paks, so it cannot run on a
      hosted runner. Revisit if additive ADB deployment below ever lands.

See `docs/DEV_LOOP.md`.

## Additive deployment

Shipped in 2.1.0. The mod no longer replaces the animation databases.

It ships its own small database carrying vanilla's `AnimationControlled` options
alongside its four, and references the untouched 5.5 MB vanilla file where it sits
inside its own pak. The human entity classes are pointed at it from Startup Lua.
Download drops from 195,284 to 21,953 bytes.

- [x] Reference the vanilla databases instead of replacing them.
- [x] Redirect the classes the engine spawns, not the templates they are built
      from. `NPC = CreateAI(NPC_x)` copies fields, so redirecting `NPC_x` has no
      effect on what spawns.
- [x] Verify a packaged build at shipping pak priority, from a Vortex install.
- [ ] Publish 2.1.0, and rewrite the mod page, which still describes the old
      database-replacement install.

Two small declaration files keep vanilla names, 15 KB in total, and two mods
redirecting the same class still collide. See `docs/HOW_IT_WORKS.md`.

See `docs/HOW_IT_WORKS.md` and `docs/TECHNICAL_DETAILS.md`.

## Reaction reliability

- [x] Reactions firing at the wrong tier, which reads from the saddle as not
      firing at all. A gallop impact scored as a walk plays a stagger instead of
      a knockdown. Impacts are now scored on the peak of the last few ticks
      rather than on the speed sampled after the collision has slowed the horse.
- [x] A gallop impact reporting walking speed. Same cause, same fix.
- [ ] Kneeling NPCs are detected but produce no reaction. `HorseHalfWidth` is
      0.35, a footprint 0.7 m wide, which may be too narrow. Needs a test aimed
      at it; no logged session has identified a kneeling victim.

Detection itself is sound: the human filter, the dead check, the below-walk gate
and both axes of the footprint were each cleared against logged sessions.

## Phase 2: Mass, armor and momentum

Scale the high-speed reaction to what the target is actually made of.

- [ ] Read the target's equipped armor weight.
- [ ] Unarmored targets take proportionally heavier knockback.
- [ ] Heavily armored targets are moved less.
- [ ] Striking a heavy target strips the horse's momentum rather than only its stamina.
- [ ] Stamina cost scales against armor weight, so a knight costs far more than a peasant.

Prerequisite met: pak asset overrides now work, which Phase 2 needs for any table data.

## Phase 3: RPG integration

- [ ] Apply native blunt damage on high-speed impacts, with the injury system handling the
      consequences.
- [ ] Horsemanship level reduces stamina cost and the chance of being thrown.
- [ ] Horse barding increases impact force and reduces momentum loss.
- [ ] A braced polearm hit head-on acts as a wall: heavy stamina cost, near-certain dismount.

## Phase 4: AI reaction

- [ ] Riding through a packed group inflicts a morale shock, so lightly armored enemies
      break and flee using native AI.
- [ ] Bumping someone at walking pace annoys them; trampling triggers the crime system.

The `hitReaction` message the mod already sends is the hook for both, and vanilla
distinguishes light from normal collisions through the `KOLIZE_S_HRACEM` and
`KOLIZE_S_HRACEM_LEHKA` dialog metaroles.
