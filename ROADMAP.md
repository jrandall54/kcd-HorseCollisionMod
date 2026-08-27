# Horse Collision Overhaul - Roadmap

Collisions should feel weighty and natural, and should lean on the game's own RPG systems
(Horsemanship, armor weight, native AI) rather than brute-force physics.

## Phase 1: Speed tiers and non-ragdoll reactions

Complete, shipped in 2.0.0.

- [x] Map horse speed to tiers. Three, not four: measured plateaus at roughly 3.0, 7.0 and
      10.8 m/s.
- [x] Play a native standing hit reaction at walking pace instead of a ragdoll. Delivered
      through `actor:StartInteractiveActionByName` against custom `AnimationControlled`
      FragTags added to the animation database.
- [x] Keep the vanilla collision bark, by posting the native `hitReaction` brain message.
- [x] Drain horse stamina at trot and gallop, and dismount the rider when it is spent.

Known gaps carried into later phases:

- [x] Female NPCs stagger too. `wh_female_fragmentids.xml` had no `AnimationControlled`
      fragment at all, so it is declared and the block added to their database.
- [x] Detection reach narrowed to a horse-shaped footprint, tuned from 103 logged impacts.
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
- [ ] Reactions are sometimes not firing, across all three speed tiers, and a gallop impact
      has been seen reporting walking speed. The two reaction mechanisms are different, so a
      fault common to both is upstream of either: detection, impact direction, or the
      per-victim cooldown. This matters more than tuning, because the tuning numbers were
      derived from telemetry this defect would have corrupted.

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

See `docs/DEV_LOOP.md`, and `docs/RELEASING.md` for publishing.

## Additive deployment

Stop replacing vanilla animation files, so the mod cannot be silently overwritten by
another animation mod and cannot silently overwrite one.

Proven in game rather than assumed. CryEngine's Mannequin loader supports sub-databases,
no vanilla KCD file uses one, and the loader is present in `WHGame.dll` regardless. A
342 byte parent that references the untouched vanilla database in its own pak, plus the
mod's own fragment file, works end to end. The database path is a Lua entity-class
property, so entities can be redirected without touching a vanilla script.

- [x] Confirm the engine loads a SubADB at all.
- [x] Confirm fragments defined only in a sub-database resolve.
- [x] Confirm a SubADB can carry a whole database, not just a fragment subset.
- [x] Confirm entities can be redirected to a parent, replacing no vanilla file.
- [x] Move the redirect from a console command into the mod's Startup Lua.
- [x] Convert the female side, which was kept as the control during testing.
- [x] Carry the tag and fragment id declarations under mod filenames too. A sub-database
      does use its own `FragDef`, so nothing vanilla is claimed. These are copies rather
      than references, so they never collide but also cannot compose with another mod
      adding to the same tag group.
- [ ] Verify a packaged build at `sys_PakPriority = 2`. Everything so far was tested
      with loose files, and this project has already lost time to a pak that silently
      overrode nothing while the same files worked loose.
- [ ] Ship it, which changes the install from a database replacement to an addition.

Honest limit: this moves the contested resource from a 5.5 MB database no one can merge
to a single Lua string. Two mods redirecting the same property still collide, but a
cooperative mod can chain by referencing the current value. Small and fixable rather
than total and silent.

See `docs/TESTING_DIARY.md`, builds 2.0.1-dev.15 through 2.1.0-dev.1.

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
