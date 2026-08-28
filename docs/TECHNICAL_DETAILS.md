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
| `hitReaction` brain message | Delivered, handled by a tree that cannot drive the body |
| `combat:hit` brain message | Same |
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
- `soul:DealDamage(stamina, health, attacker, flag)` takes stamina first.
  Vanilla's debug helper `Quick.lua` names the parameters health-first, which is
  wrong. Use `soul:SetState` when adjusting a specific stat.
- Brain messages sent with `XGenAIModule.SendMessageToEntity` are not guaranteed
  to arrive. Handlers declared `Atomic="true"` drop messages while busy, and
  most messages sent under load are lost. There is no return value to check.
- The behavior tree node `LogToConsole` does not write to `kcd.log`. An
  `ExecuteLua` node calling `System.LogAlways` does.

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

`HorseHalfWidth = 0.35` is about a horse chest's half-width, giving a footprint
0.7 m wide. Anything wider admits NPCs standing clear of the flank.

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

### Stamina

A full horse stamina pool is 210. At the current values a gallop costs roughly
three bodies and a trot roughly five before the horse is spent and Henry is
thrown. Stamina regenerates quickly between impacts, so the number of people
that can be put down in one run depends on the horse and on how fast the hits
are strung together.

A walking bump is not hard enough to tire a horse, hence `StaminaDrainWalk = 0`.

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
