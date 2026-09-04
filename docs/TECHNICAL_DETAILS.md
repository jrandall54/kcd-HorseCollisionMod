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
the settings file; the behavior lives in twelve part files under
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
Script.ReloadScript("Scripts/HorseCollisionMod/Recovery.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Crime.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Retaliation.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Rider.lua")
Script.ReloadScript("Scripts/HorseCollisionMod/Update.lua")
```

| File | What it holds |
|---|---|
| `Enums.lua` | the two engine enums, transcribed from `TypeDefinitions.xml` |
| `Log.lua` | logging, the engine clock, vector length, speed history and tier |
| `Armor.lua` | what a victim is wearing, and both curves derived from it |
| `Detection.lua` | the horse footprint test and the impact direction |
| `Health.lua` | what an impact cost, and the auto-cure suppression |
| `Reaction.lua` | the brain message, the reaction clip, the physics ragdoll |
| `Marks.lua` | the dirt and blood a knockdown leaves on the victim |
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

Detection runs at 100 ms. Each tick checks that the player is mounted and moving
at least at walking pace before doing anything else, so the cost while on foot
is negligible.

## Detection

Two stages. `System.GetEntitiesInSphere` around the horse, filtered to living
humans, then an oriented-box test against the horse's footprint. The sphere is a
broad phase only, so `HitRadius` can stay generous without NPCs reacting from an
unnatural distance.

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

### Ragdoll mass and the armor exponent

Every human is 80 kg to the physics engine, so without intervention a peasant
and a knight are the same thing for a horse to hit. `RagdollMass` replaces that
figure on the victim, written once the body is a ragdoll and before the horse
reaches it, and `RagdollMassArmorExponent` divides it by the armor scale raised
to a power.

The two numbers do different jobs, and this is the part worth understanding
before changing either:

- **The exponent sets how far apart armored and unarmored victims land.** The
  base cancels out of the ratio between two victims, so it cannot widen the
  gap no matter what it is set to.
- **The base sets how far everyone travels**, armored and unarmored alike.

The throw responds to mass as roughly `mass ^ -0.185`, measured across a
fiftyfold flat comparison. That coupling is weak enough to matter: doubling a
victim's mass shortens the throw by 12%, so a spread around a hundredfold is
what a visible difference costs, and an exponent of 1 is worth nothing at all.

At the shipped figures a villager is about 43 kg and a mailed guard about 4900,
and the measured six-second throws are 4.19 m against 1.92 m.

Lowering the base widens the separation on the ground while shortening nothing
else, which is tempting and has a limit. At a base of 40 light victims reach 17
kg, where the mod's own knockdown impulse stops being negligible and adds up to
4.34 m/s to a body the horse has already launched. Those victims travel twelve
meters and more, which does not read as a person being hit by a horse.

### Stamina

A full horse stamina pool is 210. At the current values a gallop costs roughly
five bodies and a trot roughly seven before the horse is spent and Henry is
thrown. Stamina regenerates quickly between impacts, so the number of people
that can be put down in one run depends on the horse and on how fast the hits
are strung together.

A walking bump is not hard enough to tire a horse, hence `StaminaDrainWalk = 0`.

The cost is then multiplied by what the target wears, between
`MinArmorStamina` and `MaxArmorStamina`. A villager in cloth costs less than
the listed figure and a target in mail costs twice it, so a charge into
armored men is the expensive one. That multiplier compounds with the combat
multiplier below.

### Combat multiplier

Riding through a market at speed is meant to be cheap. Using the horse as crowd
control mid-battle is not: with no penalty, charging a group of four leaves them
ragdolled and the rider free to shoot or swing at no cost.

At `CombatStaminaMultiplier = 2.5` a galloping charge into combat spends the
horse in a single impact, making it a committed move instead of a repeatable
one.

### SuppressStaggerInCombat

The stagger hands the victim's body to an interactive action, which pulls them
out of their combat behavior. On return they have lost track of the player and
bark lines like "Where did he go?" while he stands in front of them.

Suppressing it keeps their perception intact. The knockdown tiers are unaffected
either way.

### WalkStagger

Turning it off compares against vanilla collision handling without uninstalling
the mod. The knockdown tiers are unaffected.

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
horse striking a person. Twenty three single candidates were auditioned and
rejected before layering was tried. A tier therefore names a list of
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
arrives from the same direction and quieter — the way `Lightning.lua` makes
distant thunder quieter. Because a victim is a meter or two away at impact, the
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

The mod contains no damage code. Health lost to a knockdown is the engine's,
and it comes from one parameter:

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
