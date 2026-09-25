# Technical Details

What the engine allows, and how the mod works within it. The build-by-build
record is in `docs/TESTING_DIARY.md`.

## Making an NPC play an animation

An NPC's body is driven by the animation system, which is driven by the AI. Lua
cannot address a skeleton directly, and none of these produce a reaction:

| Approach | Result |
| --- | --- |
| `human:PlayAnim(fragment, tag)` | Call is accepted, nothing renders |
| `entity:AddImpulse` on a standing NPC | Ignored; actors are animation-driven, not physics-driven |
| `soul:DealDamage` with the player as attacker | Changes stat numbers only |
| `hitReaction` brain message | Delivered, handled by a tree that cannot drive the body. Removing it entirely changes neither damage nor the collision bark |
| `combat:hit` brain message | Reaches the combat subbrain and is acted on, but drives no animation. Sent as a typed table it registers a crime; sent as a string it does nothing at all |
| A `PlayAnimation` node in `sb_switch_hitreactions.xml` | Node runs, animation fails |

Trees named `sb_switch_*` are passive observers running alongside whatever the
NPC is doing. They react to events, send messages and set variables, but they do
not own the body. None of the 31 switch trees in the game contains a
`PlayAnimation` node.

### The call that works

```
actor:StartInteractiveActionByName(name, objectId, updateVisibility, animSpeed)
```

This is what vanilla uses to make someone mime opening a door. It takes over the
body, plays a whole animation, and hands control back cleanly.

`name` is matched against the FragTags of exactly one Mannequin fragment,
`AnimationControlled`. Vanilla ships only object interactions there: `cabinet_o`,
`alarmBell`, `door_l_f_o` and so on. A name outside that set is accepted
silently and aborts after a single frame, which reads in game as a one-frame
twitch.

### Returning the victim to their own control

An interactive action takes the body and does not tell the actor's behavior it
happened. When the animation finishes, the body stands where the reaction left
it while the victim's own idea of where they are continues elsewhere. The two
rejoin only when the engine rebuilds the actor, which in ordinary play happens
when the player looks away and back and the NPC drops to a level of detail the
engine repositions them from. Until that happens the victim is motionless, and
the rebuild then reads as a teleport.

`entity:Hide(1)` followed by `entity:Hide(0)` forces the rebuild. Both calls
are issued together: the teardown happens on the call rather than over elapsed
time, so no interval is needed between them.

The rebuild must land after the animation has finished. An actor still owned by
an interactive action is given back to it, and the freeze happens anyway.

`actor:GetCurrentAnimationState()` reports `AnimationControlled` for as long as
that ownership lasts, and an ordinary locomotion state afterwards, so leaving
that value is the reaction ending. Polling for it is the only workable trigger:
the same action holds the state for different lengths on different victims,
knockdowns spanning 4.3 to 7.2 seconds and staggers around 2.3, so no fixed
delay sits past every animation and inside none.

The poll interval is what a player perceives as a delay before the victim
resumes, since the rebuild fires on the first poll after the animation ends.

An action that resolves to no fragment aborts within a frame and never reports
`AnimationControlled` at all, so the wait is bounded by a ceiling and the
rebuild fires regardless when it expires.

### Messages to an NPC carry a declared payload

`XGenAIModule.SendMessageToEntity(id, name, values)` delivers a message to an
NPC's behavior tree. Most message types declare members in
`Libs/AI/TypeDefinitions.xml`, and a message whose members are unset is
accepted and then discarded, since the receiving node has nothing to match on.
There is no error and no log line: the call returns exactly as it does when it
works.

`daycycle:restartRequest` declares `reason` and `speed`. Sent with an empty
payload it does nothing at all, which is what left victims standing after a
collision with no apparent way to recover them. Sent with both members it
returns them to their day.

Two forms work. Vanilla's trees use text, `values="reason($enum:...),
speed($enum:...)"`, and its Lua uses a table:

```lua
local message = Utils.makeTable('daycycle:restartRequest', {
    reason = enum_daycycleHaltReason.interrupt,
    speed  = enum_daycycleHaltSpeed.instant
})
XGenAIModule.SendMessageToEntityData(target, 'daycycle:restartRequest', message)
```

The table form is preferred here because it is checked against the type
definition rather than parsed out of a string.

**A call that returns without error is not evidence that anything happened.**
That holds for messages, where the payload may be empty, and separately for
binds such as `human:StopAnim`, which is accepted and does nothing whatever is
passed to it. Only observation in game distinguishes the two.

### Files required to add a FragTag

Three kinds of file, all mandatory. Omitting any one leaves the call succeeding
while nothing plays.

1. **Fragment IDs** declare which fragments exist and point each at its tag
   definition file. `kcd_male_fragmentids.xml` already declares
   `AnimationControlled`. `wh_female_fragmentids.xml` does not, and is patched
   to add it.
2. **The tag definition** (`kcd_animationControlledTags.xml`) declares the valid
   FragTags. A FragTags value absent from this file does nothing, even when the
   database entry exists. Both sexes share the file.
3. **The databases** hold the options. The mod's four point at
   `hitreaction_idle_medium_torso_stab_{front,back,left,right}`, standing hit
   reactions already in the game. `kcd_male_database.adb` has an existing
   `AnimationControlled` block to append to. `wh_female_database.adb` has none,
   so the whole block is added.

`tools/build_adb.py` generates all four files from the game's own paks. It
checks that every clip it references exists, because a missing clip resolves to
nothing without an error.

## Pak packaging

Mod paks are zip files. Entry names inside them must use forward slashes:

```
Libs/AI/final/x.xml     works
Libs\AI\final\x.xml     silently does nothing
```

CryEngine looks entries up by exact path. `Compress-Archive` writes Windows
separators, so a pak built with it overrides nothing.

`Scripts/Startup/*.lua` still works either way, because that folder is
enumerated instead of looked up by path. A mod packed with backslashes therefore
loads its Lua normally while every asset override fails. The log shows the pak
opening successfully and reports no error.

`build.ps1` writes the pak entry by entry through `System.IO.Compression`, and
prints each entry name so the separators are visible.

## How the mod's Lua is composed

`Scripts/Startup/HorseCollisionMod.lua` is the entry point. It creates the
table, holds `Config`, the state tables and the timing constants, and applies
the settings file; the behavior lives in thirteen part files under
`Scripts/HorseCollisionMod/`, named at the foot of the entry point in the order
they are wanted:

```lua
Script.ReloadScript("Scripts/HorseCollisionMod/Enums.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Log.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Armor.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Detection.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Health.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Reaction.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Marks.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Sound.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Recovery.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Crime.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Retaliation.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Rider.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Update.lua")
```

| File | What it holds |
|---|---|
| `Enums.lua` | the two engine enums, transcribed from `TypeDefinitions.xml` |
| `Log.lua` | logging, entity names, the engine clock, vector length, speed history and tier |
| `Armor.lua` | what a victim is wearing, and both curves derived from it |
| `Detection.lua` | the horse footprint test and the impact direction |
| `Health.lua` | what an impact cost, and the auto-cure suppression |
| `Reaction.lua` | the brain message, the reaction clip, the physics ragdoll |
| `Marks.lua` | the dirt and blood a knockdown leaves on the victim |
| `Sound.lua` | the layered noise an impact makes, matched to the victim's armor |
| `Recovery.lua` | the waits, the rebuild and the replan that follow |
| `Crime.lua` | the combat hit that makes riding someone down an offence |
| `Retaliation.lua` | a victim losing patience at a walk, and the brawl that follows |
| `Rider.lua` | horse stamina, the combat multiplier and the dismount |
| `Update.lua` | the detection loop, and dispatching one collision |

`Config`, the state tables and the timing constants stay in the entry point,
because they have to exist before any part is loaded and because
`ApplySettings` writes to them.

### The layout is enforced by the build

New behavior goes in the part file that owns the concern, or in a new part
file. `build.ps1` refuses a build that breaks that, because the split would
otherwise be undone a method at a time, each one defensible on its own:

| Rule | What it prevents |
|---|---|
| The entry point defines only `ApplySettings`, `RedirectAnimationDatabases` and `uiActionListener` | behavior accumulating back in the entry point |
| Only the entry point writes `HorseCollisionMod = {}` | a part file discarding every method loaded before it |
| Every part file carries an LDoc `@module` header | a file silently absent from the reference |
| Every part file is named by a `Script.ReloadScript` line | a file that exists, never loads, and logs nothing |
| Every part file is listed in `config.ld` | a file missing from the reference |
| Every path the entry point loads exists in `src` | a load that resolves to nothing |

Adding a name to that first list is meant to feel like a decision, because it
is one.

`Script.ReloadScript` is the base game's own mechanism, not a development
facility. It is the first line of nearly every vanilla entity script and is how
`Scripts/common.lua` assembles its utilities, so it works in a shipping build.
It is synchronous and resolves the path through the merged pak filesystem, so
each part is fully defined before the next line runs.

The parts sit beside `Scripts/Startup/`, never inside it. The engine enumerates
that folder and executes what it finds, which would run a part before the table
exists and then run it again when the entry point named it. Naming them
explicitly removes the ordering question.

Two consequences follow from the section above. The parts are looked up by
path, so they do not inherit the accidental protection that keeps enumerated
Startup Lua working in a backslash pak; a part file that fails to load is the
first thing to suspect there. And a part that does not load raises no error on
its own - the methods it defines stay nil, and the mod silently does less -
which is why `verify_additive.py` checks that every part ships and that the
entry point names it.

Each part adds to the table and carries no top-level statements beyond its
function definitions, so re-running the entry point cascades a reload through
all of them. The development loop reloads only
`Scripts/Startup/HorseCollisionMod.lua`.

The game's own paks store forward slashes in the central directory and
backslashes in the local file headers. Python's `zipfile` treats that as
corruption and refuses to read them, so `build_adb.py` inflates entries from the
local header directly.

## Engine and Lua limits

- The `io` library is restricted. Scripts cannot write files.
- `os.clock()` returns nil. `System.GetCurrTime()` returns seconds as a float.
- Reading properties on C++ userdata entities outside `pcall` can throw fatal
  errors. Entities stream in and out constantly, so every engine call in this
  mod is wrapped.
- The stat `soul:GetState("exhaust")` returns is the **Energy** stat the game's
  own UI shows, and it runs opposite to its name: 100 is fully rested and 0 is
  spent. An untouched NPC reads 100. Reading it as exhaustion inverts every
  conclusion drawn from it, and a cap written to hold victims below a ceiling
  drains them instead of protecting them.
- `soul:DealDamage(stamina, health, attacker, flag)` takes stamina first.
  Vanilla's debug helper `Quick.lua` names the parameters health-first, which is
  wrong. Use `soul:SetState` when adjusting a specific stat.
- **`soul:DealDamage` ignores the game's immortality flag.** Captain Bernard
  reads `imm=1` and was taken from 100 health to 66 over three collisions. The
  protection vanilla applies to a story character lives in the attack path, not
  in the damage call, so a mod reaching health directly bypasses it and nothing
  downstream objects. Anything that writes to a victim's health has to check for
  itself.
- The protection is readable as derived stats. `soul:GetDerivedStat("apr")` is
  the attack-protection flag granted by the `vip_attackprot` buff, and `"imm"`
  is immortality; `"ppr"` and `"upr"` cover theft and unconsciousness. Measured
  side by side, `rat_bernard` reads `apr=1 imm=1 upr=1 ppr=1` where an ordinary
  guard reads zero for all four. `references/libKCD1/include/rpgmodule/E_DerivedStat.h`
  catalogs the full set of 110 codes.
- Brain messages sent with `XGenAIModule.SendMessageToEntity` are not guaranteed
  to arrive. Handlers declared `Atomic="true"` drop messages while busy, and
  most messages sent under load are lost. There is no return value to check.
- The behavior tree node `LogToConsole` does not write to `kcd.log`. An
  `ExecuteLua` node calling `System.LogAlways` does.
- Actor damage does not reach Lua. `BasicActor.Server:OnHit` and
  `BasicActor.Client:OnHit` can be replaced on a live entity and never fire,
  including on a victim losing health to a collision. Damage is resolved
  natively, so no override of `BasicActor.lua` can gate it.
- The collision damage multipliers on the same file are equally inert.
  `GetSelfCollisionMult`, `GetForeignCollisionMult`, `GetColliderEnergyScale`
  and `GetCollisionDamageThreshold` exist on every actor and are never called.
  Much of `BasicActor.lua` is inherited Crytek code, alongside the vestigial
  `HitDeathReactions` subsystem, and reads as available while doing nothing.
- `SetPhysicParams(PHYSICPARAM_COLLISION_CLASS, ...)` returns success on an
  actor but does not reach the ragdoll the engine creates from it. Filtering
  every actor-like class off a victim leaves collisions against it unchanged.
- Entity script tables are copies. `NPC = CreateAI(NPC_x)` copies fields, so
  patching a shared table such as `BasicActor` changes nothing about entities
  already spawned.

Most of these failures are silent. A call returns without error, a log line
never appears, an animation does not play. Confirm that a signal works before
drawing a conclusion from its absence.

## Timers and save reloads

KCD clears Lua timers when a save is loaded, but not always completely. A script
that starts a new timer loop on every load screen can accumulate several running
at once, which costs performance and can disrupt audio.

The mod increments a counter on each load screen and passes that value into the
timer closure. Any loop whose value no longer matches the current one stops on
its next iteration, so at most one loop is live.

Detection runs at `TickSeconds`, which is 0.033. That figure is the loop rate
and the distance the footprint sweeps forward, so the two cannot disagree; they
were separate numbers until the impact sound made the lag between a contact and
the reaction audible.

Each tick checks that the player is mounted and moving at least at walking pace
before doing anything else, so the cost while on foot is negligible. Thirty
passes a second over every entity near the horse is also why the loop's
diagnostics are built only when something will read them: see `IsInHorseFootprint`,
which formats its measurements only on request.

## Detection

Two stages. `System.GetEntitiesInSphere` around the horse, filtered to living
humans, then an oriented-box test against the horse's footprint. The sphere is a
broad phase only, so `HitRadius` can stay generous without NPCs reacting from an
unnatural distance.

### The broad phase is the whole cost, and it is cached

Measured in the running game, `System.GetEntitiesInSphere` takes 0.10 ms for
one entity inside a one meter sphere and 0.43 ms for eight inside the shipped
2.5. Everything else in a tick, the footprint test included, is below the
resolution of the clock. At thirty ticks a second that single call is the only
part of this mod with a budget worth managing.

It does not have to run every tick. The sphere reaches `HitRadius` and the
footprint can never reach past `HorseFrontReach` plus `MaxSweepExtra`, so
anyone the query did not return is at least the difference between those, 1.1
meters, from being hit. `EntitiesNearHorse` reuses the last result until the
horse has traveled `SphereCacheTravel`, 0.8 of that margin, or the result has
aged past `SphereCacheMaxAgeMs`. The remaining 0.3 meters covers a victim
walking toward a horse that is barely moving.

Keying the refresh on distance traveled rather than on a tick count is what
makes the guarantee independent of speed: a gallop re-queries every second or
third tick and a trot rarely, which is the right way round. Measured against a
stationary horse the call drops from 0.19 ms to 0.0055 ms.

A cached entity may have been unstreamed since it was returned. Every use of
one is wrapped and its position is read fresh each tick, so a stale list costs
a rejected candidate rather than an error.

### Speed tiers

Horse speed occupies three plateaus: 2.05 to 3.74, 6.38 to 7.03, and 9.18 to
10.81 m/s. `SpeedWalk`, `SpeedTrot` and `SpeedGallop` sit in the empty gaps
between them instead of on round numbers, so a threshold is never set at a speed
the horse holds.

The gap between 8.03 and 8.84 m/s is empty, which places the trot-to-gallop
boundary at 8.5 in open space. Reaction strength changes sharply across it, at a
speed the horse passes through often.

### The speed a collision is scored at

A horse loses speed the moment it hits someone, and detection samples velocity
once per tick. The speed read on the tick that notices a victim has therefore
already been reduced by the collision it is meant to describe, which scores a
gallop impact as a walk and plays a stagger where a knockdown belongs.

The tier comes from the peak of the last `ImpactSpeedSamples` ticks instead.
The window is short by design: taken over a longer span it would charge gallop
to a rider who galloped up and then slowed deliberately to nudge someone.

`MaxImpactSpeed` caps the result. The value scales knockback force as well as
selecting the tier, and the physics system reports occasional speeds above
anything a horse holds.

### Footprint

A horse is long and narrow. A sphere alone catches people alongside and behind
it who were never struck, so the second stage tests an oriented box.

`HorseHalfWidth = 0.70` gives a footprint 1.4 m wide, wide enough to catch a
body struck against the flank rather than only a dead-center hit. At 0.35, 22
of 104 pooled rejections across three instrumented rides were contacts the
footprint wrongly rejected, three of them unambiguous flank hits on stationary
guards, and the engine still damaged those victims without the mod ever
registering the hit to suppress vanilla's auto-cure daycycle. At 0.70,
rejections no longer occur inside the 0.70-0.90 m band that would mean a real
near-touch is still being missed, while people the horse passes with genuine
clearance, out to 2.46 m, are still correctly rejected.

### Forward sweep

The footprint is extended forward by the distance the horse covers in one tick,
so victims are not missed between frames.

The sweep is the dominant term in the effective reach and needs a ceiling.
`SweepMultiplier` scales it and `MaxSweepExtra` caps it. Uncapped at gallop the
extension alone can push the effective reach past two meters, which admits NPCs
well ahead of the animal. The sweep only has to cover one tick of travel, not a
stride.

### Per-victim cooldown

The footprint is tested ten times a second. Without a cooldown the same NPC's
reaction restarts every tick and they never finish staggering.

## Reaction defaults

Why the defaults in `HorseCollisionMod.Config` are set where they are. The
config table itself is kept scannable, since it is read to change a setting.

### Every victim weighs what the engine says, and why

`GetMass` answers 80 for every human including the player, so a peasant and a
knight are the same thing for a horse to hit. The mod once wrote over that
figure, dividing a base by the armor scale raised to an exponent, so that a
mailed guard was the heavier body to move. That path is gone.

It was removed for two reasons. The coupling is weak: the throw goes as roughly
`mass ^ -0.185`, measured across a fiftyfold flat comparison, so doubling a
victim's mass shortens the throw by 12% and a visible difference costs a spread
around a hundredfold. Buying that spread meant an exponent of 3.7, which ran
from 43 kg for a villager to 1,208 kg for a mailed guard and 501,187 kg at the
armor scale real guards score. Between scale 0.35 and 0.10 the mass moved by a
factor of a hundred, which is a cliff rather than a scale, and everything
stacked above it stopped meaning anything: an impulse of 58 against 1,208 kg
moves a guard five centimeters per second, so the knockback, the uplift and the
barding force bonus did nothing at all to anyone in armor.

Armor is separated by the ragdoll brake instead, which removes a commanded
fraction of a thrown body's speed. That is a lever with a bounded range and it
does not lie about what a person weighs.

### Waiting for the body to become physics

`actor:Fall` requests the fall, it does not perform it. For one frame after the
request the victim is still an animated character, and physics calls aimed at
one are discarded silently, so the brake and the damping wait
`PhysicsReadyMs` before running.

The wait cannot be skipped. Without it the brake fires onto
a body still carrying the peak velocity of the engine's collision and, being
proportional, takes more speed away: gallop throws fell from a mean of 1.81 m to
1.57 m over 18 impacts, and the rider described the victims as bricks.

The figure is one frame because that is what it measured at. The mass rewrite
doubled as the readiness probe, writing a value and reading it back on a six
rung ladder of 0, 16, 33, 50, 80 and 120 ms, because a write is refused on a
living actor and accepted on a ragdoll. Every impact ever logged answered on the
second rung. The probe worked and never varied, so it was machinery around a
constant.

### Ending a throw

A thrown body left to the engine slides until friction stops it, which is much
further than a person struck by a horse should travel and varies wildly with
the ground. `DampVictim` ends the throw instead, through two brakes that answer
different questions, and then gets out of the way.

**The grounded brake** arms when `IsColliding` reads true for
`RagdollDampContactRun` samples in a row, and ramps the damping in over
`RagdollDampRampSamples` more rather than applying it at once. Landed and
stopped are two separate facts: speed alone fires whenever a tumbling body dips
below a threshold, measured anywhere from 736 ms to 2848 ms, and contact alone
fires on a body skidding at 8.6 m/s in front of the rider. Applying the full
figure the instant a body lands reads as braking, so it comes in gradually.

**The air brake** covers the window the grounded brake cannot reach. The first
three or four samples of a long throw are exactly the ones that report no
contact, and that is where the distance is. Above `RagdollSpeedSoftCap` the mod
applies drag proportional to how far over the cap the body is, scaled across
`RagdollSpeedSoftCapSpan` and released again below it. Drag rather than a
velocity clamp, because a hard ceiling applied every frame reads as the body
hitting an invisible wall.

The cap was first set at 9.0 on the theory that the far throws were victims
launched into the air. They were not, and it fired on nothing. Pairing the
contact string against the speed trace, one sample per column, settled it: a
launch holds 8 to 9 m/s across its uncontacted samples while a short throw
never passes 3.9, so 4.0 separates them.

**Both are released when the watch ends.** `damping` and `min_energy` are
persistent fields of `pe_simulation_params`, not a one-shot effect, so a body
damped once carries them for the rest of its existence unless something takes
them back. `min_energy` is the threshold below which physics puts a body to
sleep, and at 1.0 that is anything slower than roughly 1.4 m/s. A corpse still
carrying it that the horse nudges into the air drops under the threshold near
the top of the arc and sleeps holding that position, which is a body floating
in mid-air until something wakes it. The release runs at both exits of the
watch, the settled one and the failsafe ceiling.

### Stamina

An impact's cost is a **share of that horse's own maximum stamina**, read per
impact from the engine's `mst` derived stat. A flat point figure would mean
different things on different mounts: the pool measured 210 on the test horse
and 230 on another.

    cost = maxStamina
         * (tier share + combat + victim armor - barding)
         * Horsemanship

The three situational figures are added to the tier's share rather than
multiplied with it. Multiplied, the chain ran `base x combat x victimArmor x
barding x horsemanship`, all unbounded, and put a gallop anywhere between 14.85
and 1452 points against a pool of about 210, so the tier separation the rider
tunes, a factor of 1.6, was invisible beside a stack spanning nearly a
hundredfold. Added, the worst case is the sum of the named maxima, 0.38 of the
pool before Horsemanship, and each term is readable on its own in the telemetry
line.

Horsemanship remains a multiplier because it is the one factor meant to
dominate. It runs from 5.0 at level 0 to 1.0 at the top of the skill, so a
gallop's 0.20 share empties the horse in one impact for a novice and allows
five back to back for an expert. Stamina regenerates between impacts, so a
player who circles and lines up again gets more than those counts say.

| Tier | Share of pool | Back to back at full Horsemanship |
| --- | --- | --- |
| Walk | 0 | unlimited |
| Trot | 0.13 | about 8 |
| Rear | 0.20 | limited by its cooldown, not by stamina |
| Gallop | 0.20 | 5 |
| Charge | 0.20 | limited by its cooldown, not by stamina |

A walking bump is not hard enough to tire a horse, hence the `Walk` figure of 0
in `StaminaShareByTier`. The rear and the charge are commanded attacks rather
than consequences of riding, so what stops a player spamming them is the
cooldown on the move itself, `RearCooldownMs` for the rear and
`ChargeCooldownMs` for the charge, each on its own clock. Both start on the
move's first contact, so a move that reaches nobody costs no cooldown; their share is a cost
the player feels, not a budget they count. Both match the gallop's 0.20 by the
rider's ruling. The cooldown figures are set by feel on a ride, not derived.

While a cooldown runs, the player carries the mod's `hcm_rear_cooldown` or
`hcm_charge_cooldown` buff, so the game's own buff icons show it. The rows copy
vanilla's `barking_cooldown`, a `Cpp:BasicTimed` buff with no effect. They are
declared with no duration and the mod removes each when its clock passes, so
the icon follows the setting rather than a second copy of the figure in a table.
Buff rows are read at startup only; neither `Database.LoadTable('buff')` nor
`wh_rpg_reload` makes a new one addable in a running game.

Because no cooldown starts until contact, a press is also refused while a move
is in progress: during a charge on `RearCharging`, during a standing rear for
the length of `relaxed_rearing` as the horse reports it. Without it, a second
charge press in the idle moment between the rear and the push doubled the
push.

Every tier is charged through one function, `DrainImpactStamina`. The rear and
the charge went through it late: each used to drain a flat setting at its own
call site, so Horsemanship, barding and the combat surcharge reached every tier
except the two heaviest.

| Surcharge | Share | Effect on a gallop at full Horsemanship |
| --- | --- | --- |
| In a fight | +0.13 | 3 impacts |
| Armored victim | +0.05 at most | 4 impacts |
| Full barding | -0.03 | 6 impacts |

The victim's armor surcharge rises with the weight of what they are wearing and
reaches `MaxArmorStaminaAdd` at `ArmorReferenceWeight`, the weight counted as a
full set. It is the one term that does not reach the rear and the charge, and
that is deliberate rather than an omission. Those two are charged once for the
whole move and the move can land on several people at once, so there is no
single victim whose armor to read. What the horse and rider bring, meaning
barding, Horsemanship and the combat surcharge, applies to them in full.

### Combat surcharge

Riding through a market at speed is meant to be cheap. Using the horse as crowd
control mid-battle is not: with no surcharge, charging a group of four leaves
them ragdolled and the rider free to shoot or swing at no cost.

At `CombatStaminaAdd = 0.13` a gallop in a fight costs 0.33 of the pool instead
of 0.20, so three impacts spend the horse where five would outside a fight.

### SuppressStaggerInCombat

The stagger hands the victim's body to an interactive action, which pulls them
out of their combat behavior. On return they have lost track of the player and
bark lines like "Where did he go?" while he stands in front of them.

Suppressing it keeps their perception intact. The knockdown tiers are unaffected
either way.

### WalkStagger

Turning it off compares against vanilla collision handling without uninstalling
the mod. The knockdown tiers are unaffected.

## What a fall-tier impact actually does to a body

Measured, not inferred. A single trot knockdown was sampled every 100 ms from
the impact until the victim was standing again, untouched throughout. `headUp`
is `actor:GetHeadPos().z` minus `entity:GetWorldPos().z`, and the entity origin
sits on the ground, so it is the head's height above the floor.

| t+ms | animation state | headUp | the body |
| --- | --- | --- | --- |
| 0 | `AnimationControlled` | 1.55 | upright, the impact lands |
| 624 | `AnimationControlled` | 0.94 | falling |
| 1840 | `AnimationControlled` | 0.15 | flat |
| 2448 | `MotionIdle` | 0.15 | flat |
| 3072 | `MotionIdle` | 0.15 | flat |
| 3664 | `BlendRagdoll` | 0.27 | rising |
| 4880 | `BlendRagdoll` | 1.21 | rising |
| 5472 | `BlendRagdoll` | 1.59 | standing |
| 6064+ | `MotionIdle` | 1.59 | standing, finished |

Three things follow, and the mod had all three wrong.

**`BlendRagdoll` is the get-up, not the lie-down.** The head climbs from 0.27 to
1.59 across it. Every piece of code that treated that state as "the victim is
still a settling ragdoll" had the sequence backwards, and anything waiting for
it to end was waiting until after the victim was already on their feet.

**The flat stretch is `AnimationControlled` followed by `MotionIdle`.** The fall
clip ends before Mannequin's Ragdoll ProcLayer takes hold, leaving roughly
600 ms in which a victim lying face down reads `MotionIdle`, the same state as
somebody standing about doing nothing. That hole is why every test built on
animation-state strings eventually let an impact through mid-fall and snapped
the body upright into a second fall clip.

**A victim is flat for about 1.8 seconds and standing again by 5.5.** Not the
eight seconds the old `VictimRebuild` timings suggested; that figure was the
mod noticing late, not the body taking that long.

### What does not work as a signal

All of these were sampled through the same sequence and none of them separates
any phase from any other:

  * `actor:GetPhysicalizationProfile()` reads `alive` from the impact to
    standing, without exception.
  * `entity:GetAngles()` returns pitch and roll of 0.00 throughout. The entity
    does not rotate with the body.
  * `entity:GetWorldPos().z` does not descend when the victim does. The entity
    is not what moved.
  * `entity:GetVelocity()` never exceeds 0.39 across the whole knockdown.
  * `actor:IsUnconscious()` stays false.

`actor:GetHeadPos()` is the one reading that tracks the rendered body, and
`GetHeadPos().z` minus the entity origin is a continuous measure of posture
with no ambiguity anywhere in the sequence.

### How the mod uses it

`RecordStandingHeight` stores a victim's upright `headUp` at the first impact
that reaches them, since a victim the speed tiers scored is by definition
someone the horse rode into while they were standing. `IsVictimFlat` then reads
the current value against half of that. The halfway point is a bisection rather
than a tuned figure: flat reads 0.15 against a standing 1.55, so the two are an
order of magnitude apart and any split between them answers identically.

An animated reaction is refused only while the victim is flat. One that has
begun to get up takes the reaction, because a victim shrugging off a hoof reads
as vanilla's non-reaction. The impact itself always lands: a second hit on a
downed victim registers and costs them health, so declining it would lose
damage the engine charges anyway.

## Marks left on a victim

Two actor binds, both taking a delta between -1 and 1 and both accumulating:

```lua
actor:AddDirt(0.6)
actor:AddBlood("head_front", 0.45)
```

`AddDirt` covers everything the victim is wearing and takes no zone.
`AddBlood` takes a named body zone and marks the body and whatever covers it.
The engine resolves the zone name against a database that is not exposed to
Lua, and it discards a name it does not recognize without an error, so the
names the mod passes are drawn only from the set vanilla's own quest scripts
use. `q_ledecko.xml` and `q_counterfeiters.xml` between them list most of it.

`Marks.lua` keys its zones off the impact direction `Detection.lua` already
computes for the reaction clips, so a man run down from behind is bloodied
across his back rather than his face. The four sets are not mirror images,
because vanilla's names are not symmetrical and inventing one to balance a
list would produce a call the engine silently drops.

Each application is jittered by a quarter either way, so a victim ridden down
twice does not carry two identical marks.

Nothing is applied at the walk tier: a stagger puts nobody on the ground, and
dirt on a victim who never fell reads as a bug.

The mod does not clean up after itself, because something in the game already
does. A merchant ridden down twice was seen covered in dirt with blood on both
arms, and seen clean again after a night had passed with him away from his
booth. That contradicts the script evidence, which had `CleanDirt` documented
as leaving blood alone and `WashDirtAndBlood` called on the player and nowhere
else. Whatever removes it has not been identified.

The form of the waiting mattered. Forty eight in-game hours spent standing at
the merchant's booth changed nothing about him at all; the night that cleaned
him was one he spent elsewhere. Why that is so is untested, so a routine-driven
effect should be checked the way this one was rather than by waiting in place.

## Spoken reactions

`Bark.lua` asks a character to say a vanilla line. Nothing is recorded and no
audio ships.

### How a line is addressed

    XGenAIModule.SendMessageToEntityData(target, "dialog:monologRequest",
            Utils.makeTable("dialog:monologRequest", {
                metarole = name, forceOnMuted = true }))

`monologRequest` accepts four ways of naming what to say and only one is usable,
each measured in game rather than assumed:

| Field | Result |
| --- | --- |
| `metarole` | Works, and reaches the generic reaction sets. What the mod uses |
| `alias` | Works, but every label vanilla exposes is quest scoped |
| `topicId` | Does nothing from Lua |
| `StartMonolog` | Does nothing, proven by A/B against `alias` on one speaker |

The target is `entity.this.id` rather than `entity.id`, for NPCs and for the
player alike.

### The set is chosen, not the line

A metarole names a *set*, and the dialog system decides which member plays. So a
set is only usable when every one of its lines is acceptable at the moment it
fires, which is a stronger condition than it looks and has caused three wrong
choices:

- **Length.** `JINDRICH_NARAZIL_NA_MRTVOLY` fits Henry finding a body, and the
  bodies it was recorded for are the Skalitz massacre. Its longest line runs 139
  characters and names his parents.
- **Content.** `KOLIZE_S_HRACEM_LEHKA` is vanilla's lightest bump set and 23 of
  its 36 entries carry no word at all, being the wordless marker `<...>` or a
  Hungarian interjection recorded for Cuman speakers.
- **Coupling.** `UVIDI_MRTVOLU` is the audible part of a scripted reaction where
  the NPC panics, flees and fetches a guard. `monologRequest` reaches only the
  audio, so firing it produces somebody who announces a corpse and strolls on.

`tools/bark_lines.py` reads any set's English text offline, which is how the
shipped sets were chosen. It walks `metarole.xml` to `topictorole.xml` to
`text_ui_dialog.xml`, whose localization keys carry the topic id in their first
field (`t<topic>_s<sentence>_<n>_<speaker>_<hash>`), so no sequence table is
needed. `--grep` runs it backwards, from remembered words to the set that holds
them.

### What decides whether a request is heard

Nothing is reported back. A request that produces no sound is indistinguishable
from one that does, because the log line is written straight after the `pcall`.
Three separate conditions have been observed to matter:

1. **Recording.** A speaker whose voice never recorded the set is silent, with
   no error. This is per character and is vanilla's own casting.
2. **Role membership.** A soul holds *roles*, not metaroles:
   `role.xml` maps `role_id` to `(metarole_id, role_name)`, `soul2role.xml` says
   who holds each, and `soul:GetRoles()` enumerates them. Henry returns 32.
   `AddMetaRoleByName` returns true and changes nothing, and there is no
   `AddRole`, so a speaker's palette is fixed.
3. **State.** A metarole describing a state appears to be silent outside it;
   `COMBAT_` sets do not speak out of combat even on a soul holding their roles.

The second and third are **hypotheses supported by a handful of observations and
not proven**, and the third has never been tested by inducing a state. Neither
should be quoted as fact. `docs/TESTING_DIARY.md` carries the evidence and the
open questions.

### Crime takes the victim's voice

With `CollisionIsCrime` on, a trot or gallop impact reports a crime, and the
victim's crime and combat reaction fires immediately in place of the mod's
line, which is the call for the guards. `HushVanillaBark` does not prevent it and was
never meant to: it sets the `suppressCollisionsBark` context option, which gates
vanilla's *collision* bark branch in `sb_switch_hitreactions.xml:293`, and the
crime callout is a different branch. Suppressing that would require finding the
option it is gated on.

The walk tier is unaffected because a stagger is not a crime, so the spoken
reactions reduce to walking pace in the default configuration and work at every
tier with `CollisionIsCrime` off.

### Sequencing the two lines of a knockdown

A knockdown speaks twice: a wordless cry at impact, then words during the
get-up. The second fires when the body begins to rise, which `WhenVictimRises`
reads from head height.

Three earlier attempts missed the moment. The readiness watcher could not
report until two seconds after the victim was upright. Waiting for the
animation state to leave `BlendRagdoll` fires once the get-up has already
finished, because that state *is* the get-up. And a delay tuned from the impact
is one figure for a rise that is not one length: measured, a body lies flat
from about 1.8 seconds and starts rising anywhere from there to past seven,
depending on the fall and the character set, so 3200 ms landed mid-ragdoll for
some victims and after others had walked away.

The target is a moment inside the get-up rather than at either end, and no
animation state marks it. The body does: the head climbs from about 0.15 of its
standing height to 1.59 across the rise, so leaving flat is the instant wanted.

`BarkGapMs` keeps the two apart: a victim who recovers quickly would otherwise
speak over their own cry, and the second request cuts the first off mid-word.

`BarkCooldownMs` must stay at or below `HitCooldownMs`. At 6000 against a hit
cooldown of 3000 it silenced exactly every second impact the mod acted on, which
reads as barks randomly failing rather than as a cooldown.

### Never request a generic metarole

`NPC` and `PLAYER` are conversation roles. Requesting one does not speak a line;
it opens a dialogue scene with its own camera, headed by an unlocalised topic
id. The exit is a save reload. See the diary for what that implies as a
capability.

## The sound a collision makes

`Sound.lua` plays it, from Lua, at the moment of impact. Vanilla's own helper
in `Scripts/Utils/SoundUtils.lua` reaches the audio system directly:

```lua
PlayAudioTrigger(entity, name)   -- ExecuteAudioTrigger on the entity's proxy
Sound.GetAudioTriggerID(name)    -- a handle, or nil if the name is not real
```

The second is a validator: any trigger name can be checked from the console
without playing it or rebuilding anything.

### There is no sound for this, so it is built from layers

Vanilla horse collisions are silent, so nothing in the game's library is a
horse striking a person. No single trigger works: twenty three of them were
auditioned and every one reads as a weapon, a footstep or a dropped object. A
tier therefore names a list of
`{ trigger, delay, distance, chance }`, played a few milliseconds apart so the
ear takes them as one event.

Two trigger names are tokens resolved per victim from the armor data
`Armor.lua` already computes: `body` is the blunt impact against that material
and `foley` the movement rustle it makes. Cloth, leather, mail and plate each
have both.

### Volume, of which there is none

The audio translation layer in `Libs/GameAudio/*.xml` declares no gain, and the
parser at line 3610277 of the decompilation reads only `fmod_name`,
`sustained`, `sustained_cutscene_audio` and `distance_culling`. None of the 66
parameters is a volume; the only ones that exist are the player's own master
sliders. Material effects declare `<Audio trigger="..."/>` and nothing else.

Distance is the substitute. A layer with a distance is played through an aux
audio proxy offset along the line from the listener to the victim, so it
arrives from the same direction and quieter, which is how `Lightning.lua`
places distant thunder. Because a victim is a meter or two away at impact, the
figure behaves as a level rather than as a position.

It reaches only events authored in 3D. Measured through speakers spawned at
verified distances of 2 and 25 meters, `blunt_unarmed_body_fabric` was
inaudible at the far one while `a_o_jump_landing` was identical at both:
`hoofsteps_player` events ignore position, and obstruction does not touch them
either. Neither that landing nor `c_special_bone_crack1`, which shares the
behavior, is used.

The curve is also short and steep. For the blunt impacts the usable range is
about a meter, and past roughly 1.5 the sound is gone, so adjustments are
fractional and are applied to one copy of a layer rather than to all of them.
Upward there is only repetition: naming a sample twice lifts it.

### The rider's own grunt, which is not a bark

`PlayRiderVocal` fires one FMOD event on the player per impact, from the same
`{ trigger, delay, distance, chance }` layer format as above. The triggers are
vanilla's, declared in `Libs/GameAudio/voices.xml`:

```
v_henry_hit_soft     Walk
v_henry_hit_medium   Trot, Rear
v_henry_hit_heavy    Gallop, Charge
```

This is deliberately not routed through the dialog system, and the distinction
matters because every earlier attempt at giving Henry something to say went that
way and produced full monologs. A `dialog:monologRequest` names a bark *set* and
the dialog system chooses which member plays, so the mod cannot ask for a grunt
and be certain of getting one. An audio trigger names the event outright: there
is no selection, no priority auction and no cooldown of the system's own, so a
crime reaction cannot take it the way it takes a collision bark.

The cost is that the vocabulary is non-verbal. All fourteen human-voice events
in `Libs/GameAudio` are grunts, sighs and cries; none is a line of dialogue, so
words remain the dialog system's alone. Two further Henry events were found and
confirmed audible and may be worth adding, `v_henry_hyje` and
`v_henry_nostamina_sigh`; the cinematic ones recorded by his actor resolve to a
valid trigger id and make no sound, their FMOD events being tied to a cutscene's
own mix.

This division is also the engine's. Henry holds the
`COMBAT_VICTIM_SCREAM_RECEIVED_HIT` and `COMBAT_ACTOR_SCREAM_ATTACK` metaroles,
but not one of their sequences carries audio recorded by his actor -- only NPCs'
-- so vanilla does not use dialogue for the player's own impact vocals either.
That is why the mod's ordinary impacts are wordless and its spoken lines fire
only on a kill.

`RiderVocalCooldownMs` holds off repeats, with severity allowed to break it:
Walk ranks 1, Trot and Rear 2, Gallop and Charge 3, and an impact whose rank
exceeds the one that set the cooldown speaks anyway. The stamp is taken when the
grunt is scheduled rather than when it plays, so collisions arriving inside the
tier's own delay are still caught, and a stamp in the future is discarded
because `System.GetCurrTime` is persisted in the save and loading an earlier one
moves the clock backwards.

### An audio trigger plays on a corpse, which dialogue does not

Worth recording next to the above, because it removes a constraint the project
had accepted. A dead entity's subbrain is torn down, so a `dialog:monologRequest`
sent to it has no recipient and is silently dropped; that is why the mod's kills
were silent where vanilla's are not. `ExecuteAudioTrigger` is not a message. It
is a direct call on the entity's audio proxy, which is a rendering attachment
rather than a brain, and a body two seconds dead plays
`v_stealth_stealthkill_man` normally.

So death sounds do not require letting the engine resolve the killing hit, which
was the only route the diary had left and would have cost the attribution
ordering in `ApplyImpactDamage`. Not yet implemented; the mechanism is proven.

### The spoken line has to be predicted, not observed

`BarkRiderOnImpact` chooses between the impact pool and the kill pool at the
moment of contact, from `PredictImpactFatal` rather than from the victim's actual
state. It has to. `ApplyImpactDamage` defers its damage until the thrown body
comes to rest so that the mod's blow lands last and owns the kill, which is up to
a second and a half after contact; a line chosen from the settled death arrives
detached from the collision it is about, and a walk stagger never reaches the
decision at all because its tier is worth no damage and the damage path returns
before dealing any.

The prediction is `ApplyImpactDamage`'s own arithmetic minus the variance roll:
`base * armorScale * bardingDamage` against the victim's current health. The roll
is symmetric about that figure, so an impact landing within one roll's spread of
the remaining health can go either way; in practice nothing is near the margin,
measured at 96.9 intended against 83.0 health on kills and 11.6 against 58.4 on
survivals. The engine's own trample is not added in, because the mod reclaims it
and restores the health the victim had at impact.

`RiderVoiceRanks` orders the three sounds -- grunt 3, impact line 4, death line
5 -- and a request outranking the hold that is running passes it. Before that the
gate was rank-blind and four fatal gallops in one ride produced one death line,
the grunt at each contact having already claimed it. Equal rank still loses, so
two death lines never overlap.

### Levels can only be judged from the saddle

Every sample is clearly audible standing still, and most disappear under the
horse's own hoofbeats at speed. A mix tuned while parked will not survive
being ridden, which cost several rounds of tuning before it was understood.

### Why not the animation data

The generated databases can carry a `PlaySound` procedural layer, and it works:
the stock male database ships twenty four of them, all `c_w_sword_clinch`. It
was built, tested and abandoned, because a fragment cannot make a sound before
it starts. Even at `ExitTime="0.0"` the noise follows the contact that caused
it.

## Collision damage

Two things damage a victim, and only one of them is the mod's.

The engine's share is described below and cannot be seen, stopped or attributed
from Lua. The mod's own share is `ApplyImpactDamage`, dealt from
`ImpactDamageByTier`, and it exists so that the mod rather than the engine owns
the killing blow. Which of the two lands last decides who the game blames, so
that ordering is a feature and not an implementation detail; it is described
under **Owning the killing blow** below.

Health lost to a knockdown by the engine comes from one parameter:

```
Libs/Tables/rpg/rpg_param.xml
  CollisionVelocityDeltaToDmgR = 0.25
```

`actor:Fall` turns a victim from an animation-driven actor into a physics body.
The horse is still moving through that space, so the engine resolves horse
against body as a collision and charges damage from the velocity delta.

What follows from that, and what does not:

- **The horse's speed at contact is the only predictor.** Impacts above 10 m/s
  cost 20 to 25 against an unarmored target; impacts under 5 m/s cost nothing,
  even when the tier scored as a gallop from the peak of the speed trail.
- **The impulse contributes nothing.** `Knockback`, `Uplift` and any lateral
  component can all be zero and the cost is unchanged. Aiming the impulse
  differently therefore cannot reduce it.
- **Armor contributes nothing either.** A guard in chain takes the same as a
  villager in cloth. Armor scales the impulse, and a target thrown further
  reads as a target hurt worse, which is not the same thing.
- **The walk tier costs nothing at all**, because a stagger never leaves the
  animation system and no physics body exists to strike.

Overriding the parameter is rejected. It is a single global value read by
everything that resolves a physical collision, including the player's own, and
shipping `rpg_param.xml` reintroduces the whole-file conflict surface additive
deployment removed.

### Owning the killing blow

A kill the engine resolves is attributed to the rider, and `CollisionIsCrime`
has no reach over it: the switch gates `SendCombatHit`, so with it off the mod
reports no collision, but the engine's trample is not the mod's to withhold.
Suppression therefore follows the killing blow rather than the setting. An
armored victim finished by repeated trampling, where the mod's contribution is
not what ends them, still raises a flag with the switch off.

`ShieldFromEngineDamage` removes the engine's ability to land that blow rather
than trying to beat it to one. A victim the horse strikes is given the game's
`immortality_nonpersistent` buff, GUID
`730503bf-735a-4f47-baae-c2d84ee77524`, at the moment of contact.

Three properties of that buff decide the design:

- **It clamps death, it does not block damage.** Measured over the console: a
  shielded soul dealt 999 damage goes from 100 health to 1, never to 0. So
  telemetry showing a shielded victim losing health is the mechanism working,
  not failing.
- **It takes effect in the call that applies it.** Measured directly, which
  removed an earlier look-ahead that shielded anyone the horse was about to
  strike a tick before contact and caught bystanders it then missed.
- **`AddBuff` returns an instance handle**, and `RemoveBuff(instance)` removes
  only that instance. `RemoveAllBuffsByGuid` would strip every instance,
  including immortality a quest granted a story character, so the handle is
  kept in a record and handed back.

The record is closed over by the backstop timer rather than looked up in
`ShieldedVictims`, because a script reload replaces the whole
`HorseCollisionMod` table and with it that map. The timer is deliberately not
generation guarded for the same reason: every other timer in the mod stops on a
reload, and this one removing immortality must not.

`LiftCollisionShield` is called synchronously at the top of the damage path, so
the shield ends exactly where the mod's own damage begins. A timed lift cannot
do this: it has to outlast the trample and end before the damage, and missing
on either side is silent. At a 700 ms shield against a 1100 ms delay victims
came out clamped at 1 health, because the removal had not taken effect.

The shield ends when the victim's body comes to rest, and the mod's damage
lands at that same moment: `ApplyImpactDamage` shields the victim, waits on
`WhenBodyStops`, lifts the shield and charges them, in that order.

That single event is what makes the whole thing simple. The engine charges a
body for as long as it is being thrown, so the shield has to span exactly that
and no more, and the mod's damage has to land the instant it ends. Two
mechanisms watching two different signals is what produced every defect below.

**Rest is read from position, not velocity, and shares one definition.**
`RestStillMeters` (0.05) and `RestPollMs` (200) are used by both `ImpactThrow`
and `WhenBodyStops`, so the mod cannot hold two disagreeing opinions about
whether a body has stopped. Measured after unifying them, the two readings
agree to the millisecond: 1424/1424, 1440/1440, 1408/1408, 1472/1472.

Four other signals are wrong for this, each for a reason worth keeping:

- **A fixed delay.** 600 ms, against a real settle time of 1200 to 2000 ms at a
  gallop. The victim was charged while still in the air, and the engine had the
  rest of the throw to kill them in.
- **A velocity threshold.** A thrown ragdoll passes through near-zero speed at
  the top of its arc and again on first ground contact, so a couple of slow
  samples is a bounce, not rest. Worse, a victim who survived and walked away
  reads as moving: two were held unkillable for a fifteen second cap at 0.96
  and 2.90 m/s, which is walking and running pace.
- **Exact position equality.** Stricter than rest and therefore later. A body
  returns identical coordinates only once the physics has fully slept, and a
  settled body micro-jitters well past the point it has visibly stopped, so
  this fired 400 ms to 1150 ms after the throw's own reading.
- **`WhenRagdollResolves`.** Reports the character blended back and standing,
  which is later still: the damage arrived as the victim stood up and dropped
  them again.

`BlendRagdoll` is unusable as the signal for this, for a reason that is easy to
miss: it never appears on a victim the impact killed, so a state test reports
`neverRagdolled` on exactly the impacts that threw someone hardest.

**A walk stagger is never shielded.** It is an animation and never makes the
victim a physical object, so there is no engine damage to protect against, and
`ApplyImpactDamage` returns early on a tier worth no damage, which left the
shield on with nothing to take it off.

**The shield must be granted past every early return.** Applied in the
detection loop it reached victims still inside their per-victim cooldown, whose
impact was then dropped, so nothing lifted it and they stood unkillable until
the backstop. It is granted inside `TriggerCollision` instead.

**The prediction this replaced.** `ApplyImpactDamage` used to decide who would
land the killing blow before the wait started, by asking whether the engine's
trample could finish whatever the mod's damage left behind:

```
if damage >= atImpact then          -- already fatal, do not wait
elseif (atImpact - damage) <= ceiling[tier] then
    damage = atImpact + overkill    -- the engine could finish it, so finish it
end
```

`ImpactDamageEngineCeiling` carried the largest trample seen per tier over 136
logged impacts. Damage variance was overruled in the same spirit: a roll that
turned a fatal blow non-fatal handed the kill back to the engine, so it did not
stand.

All of it is gone. It had to be right about a number the mod does not control,
and when it was wrong the rider was charged with murder at random. The shield
removes the race rather than trying to win it.

It also had a second effect nobody intended. A gallop on an unarmored villager
deals `95 * 1.00 * 1.02 = 96.9` against 100 health, so it was never lethal on
its own; what killed them was the finishing rule upgrading any remainder under
36. Removing it made unarmored victims survive a single gallop about seven
times in ten. That is the damage figure being honest rather than a regression
in the shield, and it is left for damage tuning rather than corrected by
rounding outcomes up.

An earlier setting, `ImpactDamageRushBelow`, asked instead how hurt the victim
already was. What matters instead is the size of the remainder against what
the engine can take, and its threshold was never measured. It was removed in
5.0.0.

## The auto-cure daycycle

Vanilla takes over any NPC that is hurt and has no other context, and the mod
is the one thing in the game that leaves ordinary townspeople badly hurt in the
open.

```
Libs/AI/final/sb_daycycles_cure.xml   cureStart, cure, cureLookHurt,
                                      cureFastStartCheck, cureApplyPatch
Libs/AI/final/sb_daycycles.xml        t_autoCureLowHealthLimit = 40.0
```

Entry needs two things together: a buff carrying AI tag 3 or 4, which is
poison or `bleeding`, and health under 40. Either alone does nothing. The
gate also requires that no cure is already running and that the context
option `suppressAutoCure` is not set.

`cureLookHurt` is the state that reads as a broken NPC. It plays the
`PretendingIllness` animation under a wait with no timeout, decorated with the
`autoCure` buff, which restores health at 0.02 per second. Nothing inside the
subtree ends it; the parent withdraws it when health rises back over the
threshold, which takes a quarter of an hour of game time.

Three properties matter for anything built against it:

- **The gate is read on entry only.** The subtree keeps running once admitted,
  so setting the option afterwards does not release a victim already in it.
- **Animation state is not a reliable test.** A `LODGuardian` substitutes a
  plain wait for the animation when the player is not close, so a victim can
  be held while showing an ordinary idle. The 0.02 per second regeneration is
  the reliable signal.
- **Guards reach it far more readily than other NPCs.** Entry also waits on the
  daycycle re-evaluating, and townspeople given identical treatment often never
  enter it.

The mod exempts its victims through the same context option vanilla uses for
duellists and scripted wanderers, set at the moment of impact so that it is in
place before collision damage resolves, and cleared on a timer. It also removes
the `curePatch` daycycle patch, which releases a victim already held, at low
health and without healing them. Removing that patch without setting the option
first lets the cure restart within seconds.

## Additive animation deployment

Since 3.0.0 the mod adds Mannequin fragments without replacing a vanilla file.
`docs/HOW_IT_WORKS.md` covers the purpose and the trade-offs. What follows is
the reference for changing it.

### Engine facts it relies on

None of the three is exercised by the base game.

**Mannequin supports sub-databases.** A database may reference others:

```xml
<AnimDB FragDef="..." TagDef="...">
  <SubADBs>
    <SubADB File="Animations/Mannequin/ADB/kcd_male_database.adb" />
  </SubADBs>
</AnimDB>
```

No vanilla `.adb` uses it; all 28 splice everything into one document. The
loader is present regardless, and `WHGame.dll` carries its strings: `SubADBs`,
`Loading subADB %s`, and
`[CAnimationDatabaseManager::LoadDatabase] Unknown tags %s for subADB %s`.

**A sub-database can carry an entire database**, not only a fragment subset, so
the vanilla file is referenced where it sits inside `Animations-part1.pak`.

**The database an entity uses is a Lua property**, not compiled in.
`Scripts/Entities/AI/NPC_x.lua` declares `AnimDatabase3P`, so a Startup script
can point it elsewhere.

### The layout

Seven files, all named `hcm_*`, so none collides with anything:

```
hcm_<set>_database.adb          the parent
  AnimationControlled           vanilla's 30 options + this mod's 4
  SubADB -> kcd_male_database.adb   untouched, in its own pak
hcm_<set>_fragmentids.xml       vanilla's ids, AnimationControlled repointed
hcm_<set>_controllerdefs.xml    vanilla's controller def, Fragments repointed
hcm_animationControlledTags.xml vanilla's 16 FragTags + this mod's 4
```

`HorseCollisionMod.lua` then points the human entity classes at the parent.

### The four requirements

All four must hold. Each produces the same symptom on its own: a one-frame
twitch, with `StartInteractiveActionByName` returning success.

**1. The parent must define `AnimationControlled` itself.** Sub-databases do not
merge options into a fragment another database already defines; the definition
comes from one place. Options placed in a sub-database are unreachable no matter
which order the subs are listed in.

**2. The parent must carry vanilla's options too.** It takes authority over the
fragment, so anything it omits is gone. Without vanilla's 30 options a
redirected NPC loses every door, cabinet and wardrobe interaction in the game.
The fragment is 69 KB, 1.24% of the database.

**3. The parent's `FragDef` must be the mod's fragment ids.** That is what the
loader validates FragTags against. Pointing it at vanilla's gives:

```
[CAnimationDatabaseManager::LoadDatabase] Unknown tags for fragmentID
    AnimationControlled tag  fragTags hcm_stagger_forward
```

**4. `ActionController` must be redirected as well as `AnimDatabase3P`.** The
controller def owns the fragment and tag definitions an entity resolves names
through at runtime. A database's `FragDef` governs load-time validation only.
Redirect the database alone and the options load and validate cleanly, then
every call against them resolves to nothing.

### Redirect the exposed class, not the template

This requirement has no symptom of its own.

```lua
-- Scripts/Entities/AI/NPC.lua
NPC = CreateAI(NPC_x);

-- Scripts/Entities/AI/Shared/BasicAI.lua
function CreateAI(child)
    local newt = {}
    mergef(newt, child, 1);   -- copies the fields
```

`NPC_x` is a template. `CreateAI` builds a fresh table and copies fields into
it, so the live class holds a snapshot taken when its script loaded. A Startup
script that mutates `NPC_x` changes nothing about what spawns.

The classes to redirect are `NPC`, `NPC_Female`, `NPC_NAI`, `NullAI`,
`DummyTarget`, plus `Player` and `PlayerFemale`, which are declared directly
instead of through `CreateAI`. The `_x` templates are redirected as well, so
anything calling `CreateAI` later inherits correctly.

`RedirectAnimationDatabases` runs at file scope, not from the load screen,
because `AnimDatabase3P` is read when an actor spawns and the load screen ends
after the world is populated.

### Constraints on any change here

- `kcd_animationControlledTags.xml` and `wh_female_fragmentids.xml` are copies
  of vanilla with additions, not references. A copy cannot pick up another mod's
  additions to the same file. This is acceptable while nothing else extends
  `AnimationControlled`, and would not be for a mod that had to share a tag
  group.
- Two mods redirecting `AnimDatabase3P` on the same class conflict. The
  contested resource is a Lua string, not a binary, so a cooperative mod can
  chain by referencing whatever is already set.
- `ActionController` must be left on vanilla. Redirecting it requires copies of
  the controller def and the fragment id file, which puts this mod in the
  resolution path of every human animation instead of one fragment, and breaks
  unrelated ones.

### Verifying it

`tools/verify_additive.py` checks the packaged release against the game's own
paks: which vanilla names are claimed, that nothing is dropped from the
fragment the mod takes over, that every reference resolves, that pak entry
names use forward slashes, and that the Lua redirects the classes the engine
spawns. It reads those class names out of `Scripts.pak`.

## Retaliation

Walk impacts are counted per victim in `Annoyance`, keyed by entity id and
holding a count and a timestamp. A count older than `RetaliationMemorySec` is
discarded rather than aged down. Past `RetaliationFreeBumps` each further
shove rolls `math.random()` against `count - free` steps of
`RetaliationChanceStep`, capped at `RetaliationMaxChance`.

### Starting the fight

Two steps, both the game's own machinery.

`Contexts.SetNonpersistentOption(npc, "alwaysFightWhenHit", handle)` sets a
context option from the shipped catalog in `Scripts/Script/ContextData.lua`,
which lists 89 options and 14 presets. Vanilla quests set options the same
way: `q_ledecko` gives four bandits `fightAllHostilePerceptibles` and
`q_hareHunt` applies the `berserk` preset. In `sb_combat.xml` the option sits
in front of the morale comparison that otherwise decides whether a civilian
fights or flees, and skipping that comparison is all it does. Options are
carried on a named handle, so clearing this mod's cannot disturb a quest that
wanted the same option.

Then `combat:stimulus:hit` with `attacker`, `kind` of `Unarmed` and
`real = false`.

**Not `combat:hit`.** That message is handled by
`sb_switch_hitreactions.xml`, which runs two independent branches and gates
only one on `real`:

- the reputation branch computes a `hit_melee_*` change by strength and calls
  `SetReputationNPC`. Gated on `real`, so `real = false` skips it.
- the assault broadcast is not gated on `real` at all. It spawns a
  `SpawnExpiringPerceptibleVolume` one meter across at the victim, labeled
  `assault`, for six seconds at full conspicuousness, blinds the attacker and
  the victim to it, and leaves every bystander able to see it. That volume is
  how a witness learns an assault happened, and sending `combat:hit` charged
  the rider with brawling before a punch had been thrown.

`combat:stimulus:hit` is what that switch forwards to the combat subbrain
anyway. The subbrain starter listens for it by name on
`combatStimulus_combatSubbrainStarter` and converts it to a stimulus impulse
of kind `hit`, reaching the same handler without the broadcast.

### What the game decides

The civilian branch of that handler, `sb_combat.xml` lines 8308 to 8365:

    if alwaysFightWhenHit or suppressFightMoraleChecks: pass
    else: CompareMorale(this, attacker)
    if gender == male: pass else: fail
    -> t_state = fight, opponent = realAttacker
       and startInDefenseOnly when the player is not already an enemy

The `gender == male` test sits behind the context option and is not bypassed
by it, so women fall through to the report or flee branches.
`startInDefenseOnly` is why a provoked victim squares up and blocks rather
than opening with an attack.

The soldier branch instead calls `CreateInformation label='assault'` whenever
the attacker is the player, unconditionally, which is why a provoked guard
arrests. Read the distinction with
`soul:GetSocialClass().SoulCrimeRoleId`: 1 for a civilian, 2 for a soldier.

### Ending it

`WatchRetaliation` polls `actor:GetCurrentAnimationState()` once a second
alongside distance covered, and classifies the victim:

- `engaged` for a `Combat` or `Surrender` prefix. Surrender matters: a victim
  mid-yield stands in `SurrenderIn`, perfectly still, and reading that as
  settled closed incidents during the surrender.
- `fleeing` for speed at or above `RetaliationFleeSpeed` **and** the rider
  more than `RetaliationFleeIgnoreRange` away. Running from someone stood over
  you is not a fault.
- `settled` otherwise.

Three endings, named in the telemetry. `natural` after three settled samples,
where nothing is sent because the game resolved its own fight. `runaway`
after `RetaliationFleeSamples` consecutive fleeing samples, which sends
`combat:stimulus:standDownRequest` followed by the reaction recovery's
`daycycle:restartRequest`. `ceiling` at `RetaliationCeilingSec`, a failsafe.

`standDownRequest` is the only message that reaches someone mid-flight:
`sb_combat.xml` rejects every stimulus arriving during `fight` or `flee`
except it and `customBehaviorRequest`, which are named exemptions. Its payload
is empty; the declared member `_` is a placeholder and passing it is rejected
by the type check.

### The surrender prompt

It is raised per provoked victim and reference counted, so several fights share
one prompt and the last to end takes it down.

What decides "the last to end" is the set of victims it was raised for, not the
combat reading. Each is dropped on death and when `EndRetaliation` fires for
their fight, and an empty set hides the prompt at once. Hanging on that ending
is safe because the watcher requires having seen the victim fight before
counting settled samples, so being pulled off the horse no longer reads as the
fight finishing. `SurrenderHintCalmPasses` remains as a fallback against the
danger reading blinking out mid-fight, which is all it was ever for.

Exactly one re-assert loop runs, enforced by a token. The loop ends by noticing
the count has reached zero, which it can only do on its next pass, so a fight
ending and another starting inside that second would otherwise leave two loops
asserting the same hint on independent timers.

**Guards get no prompt from the mod.** A provoked guard in front of a witness
is an arrest, and the game raises its own surrender prompt for that. A second one
beside it is the doubled prompt, reproducible every time with two guards and
never with a villager. The victim's social class decides it, read from the same
source the retaliation answer uses so the two cannot disagree.

### Measured costs

A provoked brawl moves no faction reputation. Five Rataje factions read
identical to six decimal places before and after one, punch and yield
included.

Beating a man does lower `soul:GetRelationship(playerWuid)` for that man
alone, by a fixed 0.5556 that did not decay across several in-game days. That
is vanilla's: a fist fight started on foot with none of this mod running
produces the same, measured against untouched controls. Read the gap against
a neighbor rather than the absolute value, which tracks a town-wide standing
and shifts for everyone at once.

## Rearing on command

### Reaching the fragment at all

The horse has a `Rear` fragment in `kcd_horse_database.adb`, and a fragment is
not something Lua can ask for. `StartInteractiveActionByName` resolves its
argument against the FragTags of one fragment, `AnimationControlled`, which the
horse does not have. So the mod ships four files: a parent database defining
that fragment with an option carrying vanilla's `Rear` contents, the horse
fragment ids with `AnimationControlled` declared, the tag itself, and the horse
controller definition giving the fragment a `FullBody` scope. A fragment with
no scope can never play, whatever the database says. Humans needed no
equivalent only because vanilla already declares the fragment for them.

The call itself takes `ActionName, ObjectId, UpdateVisibility, AnimSpeed`, and
the horse must be passed as its own object. With the name alone it does nothing
and still returns true, which is why correct data looked like broken data for
some time.

### The charge is one fragment, not two

`relaxed_rearing` is cut at 0.8 s by a second Blend in the same AnimLayer and
hands straight to `relaxed_gallop_jump`, with the MovementControlMethod
switching at the same moment: the rear needs the animation to own position, or
momentum drags the horse sideways, and the jump needs it free with inertia on,
or it cannot travel.

Chaining two fragments from Lua instead shows a gap at 700, 1400 and 1900 ms
alike. `relaxed_rearing` spends its last third back on all fours
doing nothing while still holding the horse, releasing at 2064 ms when the rear
is visually over at around 1400.

The charge covers about 5.4 m in a second, which the detection loop would score
as a trot, so `RearCharging` forces it to a gallop for the duration.

### The charge is physics, not animation

An interactive action moves the actor by root motion with collision off, and
`Horizontal` in the fragment is CryEngine's `EMovementControlMethod`: `1` is
`eMCM_Entity`, `2` is `eMCM_Animation`, `6` is `eMCM_AnimationHCollision`. The
charge shipped at `2` and blended into `relaxed_gallop_jump`, whose root motion
carried the horse 5.4 m. That is where every fault came from: riding through
walls, wedging in fences, bouncing, and a divergence discharged at over 20 m/s
when the action ended.

None of the three values fixes it. `2` travels without colliding. `6` collides
while the animation keeps demanding a position collision refuses, so the gap
accumulates and discharges. `1` admits no divergence but hands the horse to its
movement controller, whose desired velocity at a standstill is zero: an impulse
of 10000 gave 20.54 m/s, the horse moved 0.67 m, and the controller zeroed it
on the next frame.

So the charge covers no distance in animation at all. The fragment rears in
place, and the travel is an impulse applied once the action has ended, where a
push does survive. The horse is then an ordinary moving horse: it collides with
the world by default, and no raycast brake or synthetic speed is needed.

**Timing is the animation's length, not its speed.** The impulse cannot fire
while the action holds the horse, so the delay before the horse moves is the
fragment's duration. `relaxed_rearing` runs 2.06 s and spends its last third
back on all fours doing nothing, so it is cut at 1.0 s and finished with
`relaxed_idle_jump_land`. That landing is entered at `StartTime` 0.45 rather
than played whole, since the front of a jump landing is the airborne part a
rear has already done. Measured, the action ended at 1856 ms played whole and
1408 ms with the front skipped.

Raising `RearAnimSpeed` is not an alternative. It compresses the useful part
and the dead part alike, so the move looks wrong and the delay barely moves.

### The rear is a tier, not a trot

The rear on the spot has its own damage, sound, dust, camera shake, view blur
and reaction, keyed on `"Rear"`. It borrowed the trot's until 4.19.2, which hid
three faults.

`ImpactDamageByTier` carried a `Rear` entry that nothing read, so the move did
a trot's 18 rather than the 60 the table said. Connecting it made the rear able
to kill, which exposed the other two.

**A death during an animated reaction leaves a broken corpse.** The game marks
the victim dead while the interactive action still owns the body: it holds an
idle pose, has no collision, and passes through walls. The gallop tier never
showed this because it ragdolls, and a death on a body physics already owns
resolves normally. `ApplyImpactDamage` reads health back after dealing it, so
the death is already detected there, and a victim who died while still in
`AnimationControlled` is handed to `RagDollize`. Deaths outside an action are
left alone, since the game's own handling works and forcing a ragdoll would
override it.

**The recovery is attached to the fall prefix.** `WatchTurn`, `RebuildVictim`
and `ReplanIfStranded` run only for `hcm_fall_`, so a victim of a knockdown or
a stagger stands up facing wherever the clip left them with no activity to
return to. Both tiers that can knock someone down therefore default to
`"fall"`. Extending the recovery to the other prefixes needs a different
completion signal, because it waits on a ragdoll resolving and only the fall
fragments carry a `Ragdoll` ProcLayer.

**Reactions do not stack.** A victim already in `AnimationControlled` or
`BlendRagdoll` is not given a second interactive action, because the two
blending produce a face-down pose that rotates. The hit still lands in full:
refusing it would be wrong, since a second impact on a downed victim
demonstrably registers and costs health.

**The movement release repeats.** A fragment can re-apply its movement layer as
it blends, undoing a single `SetMovementControlledByAnimation(false)`, so the
call is made `ReleaseMovementAttempts` times `ReleaseMovementGapMs` apart. It
is idempotent, and victims were otherwise still carried through walls
occasionally with the call reporting success.

### The charge has its own detection and its own tier

The charge does not use the mod's collision loop. That loop is driven by the
horse's speed and exits below walking pace, so a charge from a standstill
detected nobody at all: measured across whole charges, every tick reported the
loop declining to run. Making it work would have meant the move connecting only
when the physics happened to behave.

Instead the charge sweeps its own corridor, measured from the horse every
`RearChargeStrikePollMs` so it follows the lunge wherever it goes:
`RearChargeStrikeReach` ahead, `RearChargeStrikeWidth` either side,
`RearChargeStrikeBehind` behind. There is no cap and no per-victim cooldown, so
a crowd cannot shield each other by standing close, and each person is hit once
per charge.

`Charge` is a tier in its own right rather than a gallop wearing another name.
It has its own damage in `ImpactDamageByTier`, its own sound in
`ImpactSoundByTier`, its own stamina share in `StaminaShareByTier`, its own victim
lockout in `RearChargeVictimLockMs`, and its own dust, camera shake, view blur
and throw scalar. Nothing about it can be tuned by changing what an ordinary
collision does, or the reverse.

Keeping that separation took removing an explicit alias. The detection loop used
to set `tierName = "Gallop"` whenever a charge was in progress; it now returns
instead, so the loop stays out of a lunge entirely and `ChargeStrike` owns it
end to end. Two things had been resting on the alias. The charge received a
gallop's stamina as a side effect of being counted as one, which is why it now
pays its own. And the corridor sweep honored no existing contact while
recording one, so with the loop also running each victim was scored twice; the
sweep now consults `ImpactIsNewContact` like every other path.

The victim lockout is gated on the tier for the same reason. It was written for
the charge but sat unconditionally in a function both the rear and the charge
call, so an ordinary rear held its victim out of every impact for 2.6 seconds.

### When the lunge is over

A stopwatch cannot say when a lunge is over. Three numbers governed the window
before this and had to agree with each other: a `SpeedWalk` threshold, a floor
of 1200 ms and a ceiling of 2600. None of them described the lunge, so the horse
went on striking people after it was already slowing.

`WatchLunge` closes the window when the lunge itself is spent. It starts at the
push rather than at the key press, tracks the horse's peak speed, and closes
when speed decays to `RearChargeLungeSpentAt` of that peak.
`RearChargeLungePeakMin` is the speed a lunge has to reach before it can be
judged spent at all. The 2600 ms remains as a ceiling and nothing else.

The peak is taken as the larger of each neighbouring pair rather than any single
sample. Derived horse speed throws occasional 21 to 28 m/s readings, and half of
a spike is reached by the next ordinary sample, so the first version of this
closed every window inside 200 ms. A healthy lunge reads as
`peak=13.4 spike=13.5 moved=2.1 after=256ms`: about two meters in a quarter
second off a 13 m/s peak.

Its sound drops `n_lu_log_ground`, which an ordinary gallop uses, and adds
hoofsteps. `hs_hp_soil` ignores position and plays at a fixed level, which is
why the gallop tier has none, so the charge places it back from the ear rather
than at zero distance.

### Input

`Player:OnAction` is an ordinary Lua method on the `Player` entity class table
and the engine calls it for actions delivered to the player. That is what makes
input reachable: the UI action listener the mod uses for the load screen never
sees a key, only interface events. The method is wrapped rather than replaced
and the original is always called, so every other action behaves as it did.

A vanilla key cannot be borrowed. Consuming a press does not stop the game
acting on it: bound to `jump`, this reared the horse and then jumped anyway.
Nor is there a hold to distinguish one use from another, since a two second
hold and a tap both deliver a single `press` and no `release`. So the mod
brings its own action map, `Libs/Config/hcm_actionmaps.xml`, declaring each
move once per candidate key. An action nobody listens for costs nothing.

The file is read once per session. Reading it again once the map is registered
registers the actions a second and third time and one press then arrives three
times over. The listener is re-pointed on every load screen, because the
listener is the player and the world reload replaces that entity.

`HookRearKey` reinstalls itself rather than refusing once hooked. Refusing left
a wrapper from an older copy of the file in place after a hot reload, closed
over an older original, with the hook still reporting itself installed.

### The cooldown must not survive a load

`RearNextAt` is stamped from `System.GetCurrTime`, which is level time. Loading
a save winds that clock backwards, and the deadline lives on the mod table,
which the load does not touch. The mod therefore came back holding a time that
had not happened yet and refused every press until the clock climbed past it.

This presented as the rear keys being dead for an unpredictable stretch after a
load, from instantly to never, and it cost seven attempts aimed at the action
map, the listener and the hook, none of which were ever involved. Logging every
press settled it in one ride: presses reached `Player.OnAction` at +112 ms with
the map reporting itself listening and enabled, 56 consecutive presses were
refused at the cooldown gate, and the 57th was accepted at +14256 ms. The range
of the symptom is just the arithmetic: the wait is how far the clock moved, and
a player who had not reared before loading had no deadline and saw no problem.

The load screen handler drops it with `RecentHits`, `RecentRejections` and
`VictimActivity`, which were already dropped there for exactly this reason.

The general lesson is in `RearRequested`: every gate that refuses a press says
which one it was. A press that arrives and is dropped silently looks, from
outside the game, exactly like a press that never arrived, and those two have
opposite answers.

## Patching a game table without replacing it

A table under `Libs/Tables/` can be changed by shipping a second file beside it
named `<table>__<suffix>.xml`, carrying the same `<header>` and only the rows
that differ. The loader globs `data/libs/tables/<table>__<suffix>.*`, merges what
it finds and logs the outcome:

    Table 'topic2sequence' is patched by 'topic2sequence__horsecollisionmod',
        lines added: 0, modified: 1, equal: 0

The suffix needs no registration. Four properties matter in practice:

- `added` against `modified` says whether a row extended vanilla or replaced one.
  A patch meant to add can report `modified` instead, because rows are keyed on
  their natural columns rather than on a visible id, and a match rewrites the
  row. Replacing a vanilla row removes whatever depended on it.
- Tables are read once at startup, so a patch needs a full relaunch. A script
  reload leaves the game running on the old values with correct files on disk.
- A harmless warning follows each patch, that `Localization\text__<suffix>.xml`
  cannot be opened; the loader looks for a matching localization patch.
- One row costs a few hundred bytes where replacing the file would cost
  megabytes, and two mods patching the same table do not conflict unless they
  touch the same row.

This is the same mechanism third-party perk mods use. It does not make dialogue
gated on `var(...)` reachable: those conditions read variables that live on the
engine's own request rather than on the character, and the `COMBAT_*` metaroles
listed in `Libs/Tables/rpg/combat_shout_type.xml` are dispatched by the combat
shout system rather than by `dialog:monologRequest`, so no column changes that.
