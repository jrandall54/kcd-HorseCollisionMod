# Horse Collision Overhaul: roadmap

What is still wrong, what is still wanted, and nothing else. Completed work is in
`CHANGELOG.md`, and the evidence behind every ruling below is in
`docs/TESTING_DIARY.md`.

## The goal

A collision should feel weighty and natural, and should lean on the game's own
RPG systems, Horsemanship, armor weight and the native AI, instead of
brute-force physics.

Four standing constraints shape every item below.

- The mod owns the effects it causes, so each one has a switch and a shipped
  default, and the engine is not left to resolve anything the mod could resolve
  itself.
- Each feature is a separate pillar. No pillar borrows another's tier, reaction
  or subsystem.
- No vanilla file is replaced or renamed. New table data ships as an additive
  `__horsecollisionmod.xml` patch.
- No invented constants. A number that survives is a named setting with its
  derivation recorded.

## Open defects

### Henry's kill line survives him being pulled off the horse

The line is correct when it starts and absurd a second later, once a provoked
victim drags the rider out of the saddle. A monolog already playing can be
stopped from Lua, and the diary carries the call and its timing, but no code in
`src/` uses it.

Unsettled: whether the same interrupt reaches a line vanilla raised, rather than
only one the mod sent.

### Vanilla's own witness barks play from absurd positions

The mod defers its own lines to the moment a victim starts standing up, so
nothing the mod sends is spoken in mid-air. Lines vanilla raises off the crime
volume are not on the mod's schedule, and a bystander can still announce a body
while lying on the ground.

The route is a context option rather than the mod's sending path.
`suppressMonologs` and the `suppressDudeProxBark*` family are the first place to
look.

### The engine charges its own collision against a body under the horse

A victim knocked down at trot read 68.7 health, then 17.7 when the next impact
landed. Fifty-one health went with no damage the mod attributed, on a body lying
in the mod's own fall fragment while the horse stood over it. The rider was
charged with a crime the mod never sent.

The collision shield does not reach this. The shield intercepts a killing blow,
and the crime here is raised by the hit event.

Nothing has been attempted. The first question is whether a downed victim can be
moved, unphysicalized or made non-collidable for as long as the horse stands on
them, and whether any of that is reachable from Lua without wrecking the pose.

### The provocation line may still be truncated

The line a victim speaks as they commit to the fight is the payoff of the whole
retaliation sequence, and it has been heard cut short. Moving the provocation
out of impact time in 5.22.0 should have given it room, and no ride has settled
whether it did. One ride settles it.

## Accepted as they stand

Known, ruled on, and not scheduled.

- **The crime reported is brawling rather than a weapon swing.** `unarmed` is the
  only sendable attack kind that suits a horse walking into somebody, and
  `sb_combat.xml:3556` picks the report bark from the kind, which resolves to the
  brawl set `VOLANI_STRAZE_BITKA`. Open only to a genuinely new idea, not to
  another identifier swap.
- **The engine's trample at a gallop is an armor-blind floor** of roughly 15 to
  20 damage that the mod cannot lower. `rpg_param.xml` stays off limits, being
  one global value read by everything that resolves a physical collision,
  including the player's own. `perk_rpg_param_override.xml` resolves parameters
  per character against the perks they hold and is the unexplored route.
- **A heavy impact does not strip the horse's momentum.** The camera shake and
  the first-person blur carry the horse's side of an impact, and impacts read as
  having weight without a dedicated reaction on the horse.
- **Not every NPC can be pulled from the saddle.** `RetaliationPullsRiderDown`
  ships and works where the action is available.

## Planned work

### 1. The balance pass

The largest item, deferred deliberately. Three numbers govern how hard a
collision lands, and none of them is where it should be.

- **Armor separation through the brake.** Two chosen numbers, the brake's
  ceiling and its drag, measured at 1.70x on means and 1.87x on medians over 143
  throws.
- **Armor defense scaling.** What armor takes off the damage. A charge worth 110
  becomes 12 against chainmail, a factor of nine across a range the player
  experiences as wearing armor or not.
- **Base damage per tier.** The figures the other two scale. A rear at a base of
  60 kills an unarmored civilian in two. A gallop deals 96.9 against 100 health,
  so seven in ten survive one.

The three are not separable, because moving any one of them changes what the
other two compensate for. That makes this a single project rather than three
adjustments, and it cannot proceed incrementally alongside feature work.

Folded in here:

- **The charge's throw distance**, reported as too far. The charge is its own
  tier with its own force settings and has never been tuned by eye against the
  others.
- **Victim mass.** The rider's position is that unarmored NPCs sit at their
  normal mass and the curve scales up from there, instead of writing light
  victims down below it. Over 40 logged throws, an unarmored victim travels
  about three times the armored distance, and every 42 kg victim ranges from
  0.07 m to 7.71 m on the same tier with the same impulse. The contact angle is
  what varies, and a light body converts more of that variation into
  distance.

Nothing in this section is a defect. The mod is playable at these values and
they are deliberate placeholders.

**It comes after every pillar ships**, because each new pillar adds a tier that
has to be balanced against the rest.

### 2. Fear and morale around a rear

A rear either hits someone or does nothing to them. The feature is three bands
instead of one.

- The hooves land, as now, inside `RearReach` and `RearArc`.
- A wider and longer band where nobody is touched and the horse is frightening:
  they break and flee.
- Some of those stand and turn on the rider instead, decided by a morale check,
  feeding the retaliation system that already exists.

A charge breaking a line, and a braced polearm stopping a charge, are the same
feature and belong here. This goes after the balance pass, which changes what
the lunge does to the people around it.

### 3. Widen who can be pulled from the saddle

Availability of the pull-down action is editable in table data. The additive
patch route the perk tables already use is how to reach it without overriding
anything vanilla.

## Parked ideas

Neither is scheduled. Both are kept because the rider asked for them.

- **A protected story character unhorses the rider** instead of absorbing a
  collision. `IsProtectedFromHarm` identifies them at the impact, and the
  retaliation sequence already has a path that pulls Henry down, so it would read
  as the man being too solid to ride down.
- **Riding and walking at the same time.** `StartInteractiveActionByName` with a
  horse tag, called on the mounted player, leaves them in two states at once:
  still the horse's rider, and running the on-foot locomotion state machine on
  top of it. Not a feature and not a defect. The mechanism is in the diary.

## Before the next publish

`HANDOFF.md` carries the publish checklist, which is documentation work and a
shipping test rather than code. None of the open items above blocks a release.
