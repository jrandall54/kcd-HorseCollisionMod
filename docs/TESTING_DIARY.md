        # Horse Collision Mod - Testing & Experimentation Diary

This document serves as a historical record of all logical hypotheses, test builds, and their in-game results. **Consult this diary before implementing new collision logic** to avoid repeating past failures.

## The Goal
* **High Speeds (Gallop):** Trigger a proportionate physics ragdoll and apply heavy stamina drain to the horse.
* **Low Speeds (Walk/Trot):** Trigger a non-ragdoll "stagger," "dodge," or "flinch" animation, avoiding the native ragdoll bounce.

---

### Build: 1.4.0-rc1
**Hypothesis**: Using 
pc.soul:DealDamage(0, 10, nil, false) (10 stamina damage, no attacker) will force the engine to play a native HitReaction/stagger animation without triggering the cavalry ragdoll.
**Results**:
- **Walk/Trot**: No visible hit reaction or stagger. NPCs just barked (vanilla behavior). The engine still randomly produced a ragdoll ~15% of the time at walk, and 100% at trot.
**Thoughts & Conclusions**:
- Stamina damage alone does not trigger a physical hit animation. 
- The 15% / 100% knockdowns were determined to be the **physical collider of the horse** ramming into the NPC natively in CryEngine.

---

### Build: 1.4.0-rc2
**Hypothesis**: Because the horse's native rigid body is hitting the NPC, we must physically push the NPC out of the way *before* the horse hits them. We removed DealDamage and used 
pc:AddImpulse() with a small sideways force to make them physically slide/stumble out of the way. 
**Results**:
- **Walk/Trot**: Zero physical movement. AddImpulse failed silently. All behavior returned to vanilla (NPC just barks, NO ragdolling occurred).
**Thoughts & Conclusions**:
- **CRITICAL CRYENGINE LIMITATION**: AddImpulse does not work on purely kinematic, living actors standing upright. It is completely ignored unless the actor is already in a physics ragdoll state.
- **Revelation**: Because 
c2 successfully stopped the random low-speed ragdolls by simply removing DealDamage, it proves DealDamage was actually *causing* the 15%/100% ragdolls in 
c1.

---

### Build: 1.4.0-rc3
**Hypothesis**: Since stamina damage doesn't cause a flinch, we used DealDamage(1, 0, nil, false) to deal exactly 1 Health Damage. Taking physical health damage natively forces an animation flinch in most game engines.
**Results**:
- **Walk**: Ragdolled ~50% of the time (seemingly random).
- **Trot/Gallop**: Ragdolled/Blew them away 100% of the time.
**Thoughts & Conclusions**:
- **THE TRAP**: Attempting to force an animation on an NPC via DealDamage while they are actively in the HitRadius of a moving horse causes the engine to natively panic and interpolate the damage as a massive physical trauma (trample), resulting in a ragdoll instead of a standing flinch. 

## Status Snapshot (End of Session 8/24 - superseded by build 2.0.0-dev1 below)
- **Do not use DealDamage to trigger a stumble.** It always cascades into a ragdoll when the player is on a horse.
- **Do not use AddImpulse to trigger a stumble.** It fails silently on standing actors.
- **Next Steps:** We need a completely different method to trigger animations (e.g., UI Action signals, MBT brain signals, or sending a specific Lua action graph request).
---

### Build: 2.0.0-dev1
**Hypothesis**: The three previous failures (`DealDamage`, `AddImpulse`, stamina damage) all
failed because they attack the problem from the *physics/damage* side. KCD does not derive
standing hit animations from damage - it plays a named **Mannequin fragment**. The correct
lever is therefore the Mannequin system, reached from Lua via `human:PlayAnim(fragment, tag)`.

**Research performed (sources, so this does not have to be redone):**

1. **`human:PlayAnim(fragment, tag)` exists and is the animation entry point.**
   Found in `references/WHGame_Decompiled.c` at line 3237733, where the script-bind
   registrar stores `local_88 = "PlayAnim"; local_80 = "fragment, tag";`. The two-argument
   signature `(fragment, tag)` mirrors the MBT `<PlayAnimation animation="" tags="" />` node
   exactly.
   The registration call sits at decompiled line 3242650, bracketed by `GetItemInHand`
   (3242648), `StopAnim` (3242662), `GetHorse` (3242676) and `IsMounted` (3242688) - all
   confirmed members of the **`human`** bind. So the call is `npc.human:PlayAnim(...)`.

2. **`PushBack(distance)` is a red herring - it is player-only.**
   Registered at decompiled line 3242923, inside the *player* bind cluster
   (`GetPlayerHorse` 3242887, `ClearPlayerHorse` 3242899, `SetPlayerHorse` 3242901,
   `EnableFastTravel` 3242906, `TryDrawTorch` 3242921, `SetWhistling` 3242925). It pushes
   *Henry*, not an NPC. Do not spend a build testing it on NPCs.

3. **Fragment names come from the game's own Mannequin databases.**
   `Data/Animations-part1.pak` is a plain zip. The authoritative fragment lists are
   `Animations/Mannequin/ADB/kcd_male_fragmentids.xml` (615 fragments) and
   `Animations/Mannequin/ADB/wh_female_fragmentids.xml`.
   Relevant fragments:
   - Male only: `CombatHit`, `CombatHitMovement`, `CombatHitTorso`, `CombatHitCombo`,
     `CombatDodge`.
   - **Male and female**: `Juke90Left`, `Juke90Right`, `Juke180Left`, `Juke180Right`,
     `WalkThrough`, `Cower`, `GetUp`.
   Because the female database has **no `CombatHit`**, any reaction that must work on all
   NPCs has to fall back to the Juke fragments.

4. **Tag vocabulary.** `Animations/Mannequin/ADB/kcd_combat_tags.xml` defines a `HitType`
   group with exactly the tiering this mod needs: **`hitTypeLow`, `hitTypeNormal`,
   `hitTypeHeavy`**. Tag strings are a comma-separated list (vanilla examples:
   `'CarveDoe1A,butcherDoe'`, `'lieSideLeft,liePlaceBench,isSitting'`).

5. **The native `hitReaction` brain message is reachable from Lua.**
   `Libs/AI/TypeDefinitions.xml` defines the message type:
   `hitReaction { attacker: common:wuid, hitStrength: enum:HitReactionStrength,
   hitType: enum:HitReactionType, targetOrigMat: int }`.
   Enum ordinals (TypeDefinitions.xml lines 3097-3125):
   - `HitReactionType`: Melee=1, **Collision=2**, Fall=7, Bullet=10, MeleeStealth=16.
   - `HitReactionStrength`: Zero=0, Healing=1, Tickle=2, Unpleasant=3, Exhausting=4,
     MinorInjury=5, MajorInjury=6, Fatal=7.
   It is sent with
   `XGenAIModule.SendMessageToEntity(id, "hitReaction", "attacker(<wuidMsg>), hitStrength(n), hitType(2)")`,
   matching the MBT form `<InstantSendMessageToNPC type="hitReaction" values="hitStrength(6), hitType(10)" />`
   found in vanilla.
   **Vanilla already generates `HitReactionType.Collision` for horse impacts.**
   `Libs/AI/final/sb_switch_hitreactions.xml` catches it, resolves the horse's `rider` link,
   and if the rider is the player re-sends it as `combat:hit` for crime attribution. That is
   why NPCs bark but never animate: the collision path drives *AI reaction only*, never a
   Mannequin fragment. There is no `PlayAnimation` node anywhere in that tree.

6. **Relevant CVars** (all default ON, so they are not the blocker, but they are tuning
   knobs): `wh_am_HitReaction_Enabled`=1, `wh_am_HitReaction_CollisionsEnabled`=1,
   `wh_am_HitReaction_PhysicalHitCoef`=10.0,
   `wh_am_HitReaction_CollisionCacheEvictionInterval`=1.0,
   `wh_am_HitReaction_EnvironmentCollisionScale`=1.0, plus `wh_am_HitReaction_Debug`=0.
   There is also a console command **`wh_am_DebugPlayAnimation`** ("Play animation on given
   entity") which can test fragment names in-game without a rebuild.

**What this build does:**
- Replaces the two-way speed split with four tiers: Walk (>=1.6 m/s), Trot (>=4.0),
  Canter (>=6.0), Gallop (>=8.0).
- Walk/Trot: no ragdoll, no damage. Calls `npc.human:PlayAnim(fragment, tags)` with a
  gender-aware candidate ladder, plus the native `hitReaction` message at low strength
  (Tickle / Unpleasant) so vanilla barks still fire.
- Canter/Gallop: the proven 1.2.0 ragdoll, at 0.6x and 1.0x impulse respectively, plus
  `hitReaction` at MinorInjury / MajorInjury and the horse stamina drain.
- Logs a one-shot API probe of the victim's extension surface, and logs every `PlayAnim`
  call with its fragment, tags and pcall result.
- `Config.ProbeFragments` (default off) walks one candidate per impact so the whole ladder
  can be swept in a single play session.

**Results**: PENDING - awaiting first in-game test.

**Open questions for the test:**
- Does `human.PlayAnim` actually exist on a live NPC (the API probe line answers this)?
- Does `CombatHit` render on a non-combat NPC, or does it require combat context/scope?
- Does the `hitReaction` message at Tickle strength cause unwanted hostility at walk speed?

---

### Build: 2.0.0-dev1 (RESULTS)
**Results**:
- **API probe (the key win)**: `human.PlayAnim=function`, `human.StopAnim=function`,
  `human.PushBack=nil`, `actor.PlayAnimation=nil`,
  `actor.StartInteractiveActionByName=function`. The `human:PlayAnim` binding is real and
  the `PushBack` player-only finding was confirmed against the live engine.
- **Walk**: `PlayAnim("CombatHit","hitTypeLow")` returned `ok=true err=nil` on every single
  impact, yet produced **no visible animation** - vanilla bark only.
- **Trot** (logged as tier=Canter, 6.38-7.03 m/s): worked well. NPCs knocked away, horse
  stamina drained over repeated hits, rider eventually thrown.
- **Gallop** (9.18-10.81 m/s): NPC flew correctly, but Henry was thrown on *every* contact
  and the horse then bolted.
- **Speed telemetry**: 36 logged impacts cluster into exactly **three** plateaus  - 
  walk 2.05-3.74, trot 6.38-7.03, gallop 9.18-10.81. The dev1 4.0-6.0 "Trot" band caught
  nothing but gait transitions. The four-tier model was wrong; KCD has three gaits.

**Thoughts & Conclusions**:
- **`pcall ok=true` does NOT mean the animation played.** A Mannequin fragment request that
  matches no option is dropped *silently*. This is the single most important lesson of the
  session: never treat a successful `PlayAnim` call as evidence of a working animation.
- **Root cause found by reading the animation database.**
  `Data/Animations-part1.pak` -> `Animations/Mannequin/ADB/kcd_male_database.adb` is plain
  **XML**. Inside `<FragmentList>`, every fragment lists its options as
  `<Fragment Tags="a+b+c">` (note: `+` separated, not comma separated).
  **All 241 `CombatHit` options require drawn-weapon and combat-guard tags**
  (`l_longsword+r_longsword`, `sZ0`, `rightGuard`, `eZ0`, `kick`, `dZ5`, `hitTypeNormal`...).
  An unarmed villager holds none of them, so nothing resolves. `CombatHitMovement` (43
  options) and `CombatDodge` (129 options) are gated the same way.
  **CombatHit is structurally unreachable outside an armed duel. Do not retry it.**
- **What actually resolves for a peaceful NPC** (from auditing every option's tags):
  - `WalkThrough` - 1 option, `Tags=""`, always resolves, but the clip is
    `relaxed_walk_medium`, i.e. a plain walk cycle, not a reaction.
  - `Juke90Left/Right`, `Juke180Left/Right` - 2 options each, gated on `walk` or `run`,
    which `PlayAnim`'s tag argument can supply explicitly. Clips are
    `relaxed_walk_juke_90_left` etc. Present in **both** male and female databases.
  - `MotionLandHeavy` - male only, has an untagged option, plays `relaxed_fall_down_land`.
- **There is no civilian stagger animation in the game.** Searching every
  `<Animation name>` in the male database for stagger/stumble/push/bump/trip/recoil/shove
  returns only combat weapon-impact additives. The only non-combat evasive clips in KCD are
  the **eight juke animations**. Any walk-speed reaction has to be built from those.

---

### Build: 2.0.0-dev2
**Hypothesis**: The walk reaction should be a **juke** (sidestep out of the horse's path),
not a stagger, because that is the only non-combat evasive animation KCD ships. Passing the
required `walk` tag explicitly to `PlayAnim` should let the option resolve even on a
standing NPC.

**Changes**:
- Gait model corrected to three tiers from the dev1 telemetry: Walk >=1.8, Trot >=4.5,
  Gallop >=8.5 m/s.
- Walk ladder is now `Juke90{side}`/`walk` -> `Juke180{side}`/`walk` ->
  `MotionLandHeavy` (male) -> `WalkThrough`.
- Juke side is computed in the **victim's own frame** (`npc:GetDirectionVector(1)` crossed
  with the horse->victim escape vector). The juke clips are authored relative to the NPC's
  facing, so using the horse's frame as dev1 did would have made them step *into* the horse.
- Trot keeps the 0.6x ragdoll that tested well; Gallop keeps the 1.0x ragdoll.
- `ThrowRiderOnStaminaEmpty` added and defaulted **false**. Throwing Henry belongs to
  roadmap phase 2/3 where mass/barding/Horsemanship decide it.
- Stamina before/after values are now logged on every drain, as calibration data for
  phase 2.
- New `LogAnimationState` samples `actor:GetCurrentAnimationState()` 250 ms after each
  request, so the log can finally distinguish "call accepted" from "fragment active".

**Results**: PENDING.

---

### Build: 2.0.0-dev2 (RESULTS)
**Results**:
- **Walk**: still no visible reaction, vanilla bark only.
- **Trot**: acceptable.
- **Gallop**: much better. Henry no longer thrown on first contact, only after a couple of
  impacts.
- **Log rotation**: `kcd.log` is NOT lost on restart. The game copies it to
  `logbackups/KCD Build(0) <date> (<time>).log` before truncating, so every past session is
  still on disk.

**Two findings that change the picture:**

1. **The walk test was invalid because of the test location.** The new `AnimState` telemetry
   returned `TournamentCrowdLoop` (5x) and `TournamentCrowdVAR` (3x) for every walk-tier
   victim. Those NPCs are tournament spectators locked in a scripted job animation whose MBT
   action owns the FullBody Mannequin scope, so the juke request was queued behind a looping
   behavior and never surfaced. **The juke has still not been tested on an ordinary NPC.**
   Lesson: always log what the victim was already doing before blaming the fragment.

2. **The horse stamina drain has never worked, and the rider throw was always vanilla.**
   Telemetry: `Horse stamina before=210 drain=25 after=210` on every single impact -
   `soul:DealDamage(0, n, nil, true)` is a **no-op** on horse stamina. Values ranged
   140-210, so stamina is an absolute pool of roughly 0-250, not a 0-1 normalized value.
   Because `ThrowRiderOnStaminaEmpty` was **false** in dev2 and Henry was still thrown at
   gallop, the dismount is **native engine behavior** from the high-speed collision, not
   this mod. The dev1 diary entry crediting the mod's stamina logic for the throw was wrong.

**Dead end ruled out**: the stock CryEngine `HitDeathReactions` bind (documented methods
`StartReactionAnim`, `ExecuteHitReaction`, `OnHit`) looked ideal because `StartReactionAnim`
"pauses the animation graph while playing". But `Libs/HitDeathReactionsData/*.xml` - the data
files every KCD actor's `fileHitDeathReactionsParamsDataFile` property points at - ship in
**zero** paks. The subsystem is vestigial in KCD; Warhorse replaced it with Mannequin.
Do not pursue it.

**New reference acquired**: `references/kcd-documentation/` is Warhorse's official ScriptBind
HTML documentation, cloned from github.com/Nexus-Mods/kcd-documentation (the same content the
warhorse.nexusmods.com site serves, which 403s to scrapers). Contains per-class method lists
including `C_ScriptBindHuman`, `C_ScriptBindActor`, `C_ScriptBindSoul`.

---

### Build: 2.0.0-dev3
**Hypothesis**: Two independent fixes.
(a) The juke never surfaced because the brain's action owned the FullBody scope, so call
`human:StopAnim()` to release it immediately before `human:PlayAnim()`.
(b) Horse stamina must be written with `soul:SetState("stamina", value)` - signature
confirmed as `"state,value"` in the decompile at line 3423683 - rather than via
`soul:DealDamage`, which does nothing.

**Changes**:
- `human:StopAnim()` is called before every `PlayAnim` request.
- New `wasPlaying=<state>` field on the Stagger log line records what the victim was doing
  *before* the request, so an invalid test location is obvious immediately.
- Horse stamina drain rewritten to `soul:SetState("stamina", before - drain)`, clamped at 0.

**Results**: PENDING. Must be tested on **ordinary NPCs** (Rattay/Skalitz villagers), not the
tournament crowd.

---

### Build: 2.0.0-dev3 (RESULTS)
**Results**:
- **Walk on ordinary villagers: still vanilla, no animation.** This is the decisive test.
  `wasPlaying` came back as `MotionMovement` (9), `MoveToIdle` (3), `MotionIdle` (2) - i.e.
  ordinary locomotion with a free FullBody scope, not a scripted job loop. `AnimState after`
  was unchanged: `MoveToIdle` (6), `MotionMovement` (6), `MotionIdle` (2). The juke never
  became the active animation even with `human:StopAnim()` called first.
- **Horse stamina drain now works**: 210 -> 185 -> 160 -> 129.8 -> 104.6 -> 71.2 -> 43.1
  -> 22.4. `soul:SetState("stamina", value)` is the correct writer. Full pool is 210.
- Rider never thrown, because `ThrowRiderOnStaminaEmpty` was still false.

**Conclusion - `human:PlayAnim` is dead for NPCs. Stop trying to drive NPC animation from
Lua directly.** The call is accepted, the fragment name and tags are valid, the scope is
free, `StopAnim` is called first, and the animation still never surfaces. The NPC's brain
(MBT) continuously re-drives `MotionMovement`/`MotionIdle` through the AnimatedHuman
locomotion system and immediately reasserts control over anything pushed in from outside.

**Cumulative list of ruled-out approaches (do not retry any of these):**
1. `soul:DealDamage` for a flinch - cascades into a ragdoll (1.4.0-rc1/rc3).
2. `npc:AddImpulse` on a standing actor - silently ignored (1.4.0-rc2).
3. `soul:DealDamage(0, n, nil, true)` for horse stamina - no-op (dev2). Use `SetState`.
4. `human:PlayAnim` with `CombatHit` - tag-gated behind drawn weapons (dev1).
5. `human:PlayAnim` with any fragment at all - never renders on an NPC (dev3).
6. `human:PushBack` - player-only bind, `nil` on NPCs (dev1 probe).
7. CryEngine `HitDeathReactions` / `StartReactionAnim` - `Libs/HitDeathReactionsData/*.xml`
   ships in zero paks; subsystem is vestigial in KCD (dev2 research).
8. `animationOnSpot_params` - a smart-object subtree parameter, not a mailbox message, so
   it cannot be triggered on an arbitrary NPC from Lua (dev3 research).

**The one remaining path**: make the **brain** play the animation. The MBT `PlayAnimation`
node is used 1278 times across the vanilla behavior trees and is the only thing that
demonstrably animates an NPC. Since `XGenAIModule.SendMessageToEntity(id, "hitReaction", ...)`
is already delivered successfully to every victim, the plan is to ship a modified
`Libs/AI/final/sb_switch_hitreactions.xml` whose `hitReaction` handler adds a
`PlayAnimation` branch for `hitType == Collision` at low strength.
**Tradeoff to weigh: this replaces a core vanilla AI file, so it will conflict with any
other mod that touches the same tree.**

---

### Build: 2.0.0-dev4
**Hypothesis**: Balance only. Now that stamina actually drains, restore the anti-bulldozing
mechanic the mod is supposed to have.

**Changes**:
- Stamina cost split per gait: walk 0, trot 20, gallop 40, against the measured pool of 210.
  That is roughly five bodies at gallop or ten at trot before the horse is spent.
- `ThrowRiderOnStaminaEmpty` restored to **true**; it had nothing to act on before because
  the drain was a no-op.
- `TryPlayAnim` config flag added, defaulted **false**, since the call is proven inert.

**Results**: PENDING.

---

### Build: 2.0.0-dev4 (RESULTS)
**Results**: Walk unchanged (expected - `TryPlayAnim` was off and `PlayAnim` is inert
anyway). Stamina/throw mechanic works; user judged the threshold too generous and wants to
be thrown sooner at both trot and gallop, but deferred the numbers to the phase 2
mass/velocity work rather than tuning them twice.

---

### Build: 2.0.0-dev5 - FIRST MBT OVERRIDE
**Hypothesis**: Since Lua cannot drive NPC animation and the brain always wins, the brain
itself must play the fragment. `Libs/AI/final/sb_switch_hitreactions.xml` already receives
our `hitReaction` message, so a `PlayAnimation` node is added directly inside that handler.

**The change** - a 10-line diff against the vanilla file, no vanilla logic removed:
- Inserted as the **first child** of the `hitReaction` `ProcessMessage` handler's
  `<Sequence>` (vanilla line 234), so all existing behavior still runs afterwards:
  ```xml
  <IfCondition failOnCondition="false"
      condition="$hitReaction.hitType == $enum:HitReactionType.Collision &
                 $hitReaction.hitStrength == $enum:HitReactionStrength.Tickle">
    <PlayAnimation animation="Juke90Left" tags="walk" ... />
  </IfCondition>
  ```
- A matching `EditorData` mirror was inserted at vanilla line 789 to keep the editor
  metadata 1:1 with the logic tree.
- **Tickle strength is the private signal.** The mod only ever sends Tickle at walk speed,
  so the branch cannot fire on a vanilla engine collision.

**Authoring notes for future MBT edits (these cost time to work out):**
- Attribute values are double-wrapped: the XML attribute contains an expression-language
  string delimited by `&quot;`. A literal is `animation="&quot;Juke90Left&quot;"`, and a
  logical AND inside a condition is `&amp;`.
- The file is **CRLF** and declares `encoding="us-ascii"`. Patch it as bytes and rejoin with
  `\r\n`, or Python's universal newlines silently rewrites the whole file to LF and the diff
  becomes unreviewable.
- Verify with `xml.etree.ElementTree.parse` and a `diff` against the vanilla copy before
  building. The patch script anchors on node content, not line numbers.

**Compatibility cost**: this ships a full replacement of a core vanilla AI file, so the mod
now conflicts with any other mod that edits `sb_switch_hitreactions.xml`.

**Results**: PENDING. If NPC AI misbehaves generally, this file is the first suspect -
removing the mod fully reverts it.

---

### Build: 2.0.0-dev5 (RESULTS)
**Results**: NPC does not sidestep. Reaction is vanilla.

**Verification done before drawing any conclusion** (the mod pak IS loading correctly):
- `[Mod] 'HorseCollisionMod_v200dev5' supports game version '1.9.7' by wildcard '1.*', it will be enabled`
- `Pak 'mods\horsecollisionmod_v200dev5\data\horsecollisionmod.pak' is opened, root: 'data\'`
- The pak contains both `Libs\AI\final\sb_switch_hitreactions.xml` (134 KB) and
  `Scripts\Startup\HorseCollisionMod.lua`.
- **No XML parse or behavior-tree load errors anywhere in kcd.log.**

So the failure is one of two things, and they have very different consequences:
- **(a)** the modded XML is not overriding the vanilla tree (or that subtree is not running), or
- **(b)** it is overriding, the branch fires, and `PlayAnimation` is still overridden by the
  locomotion system - which would mean the animation is unreachable by any route.

**Housekeeping note**: a stale `Mods/HorseCollisionMod_v120` directory is still installed. It
is absent from `mod_order.txt` and its pak never appears in the log, so it is inert, but it
should be removed to avoid confusion.

---

### Build: 2.0.0-dev6
**Hypothesis**: None - this build is purely diagnostic, to separate (a) from (b) above.

**Changes**: Two `LogToConsole` nodes added to the modded behavior tree at `LogLevel="Error"`
so they cannot be filtered out:
- **Unconditional**, as the first child of the `hitReaction` handler:
  `HCM_MBT recv type=$hitReaction.hitType strength=$hitReaction.hitStrength`
- **Inside the Collision+Tickle branch**, immediately before `PlayAnimation`:
  `HCM_MBT branch fired - playing Juke90Left`
(The `IfCondition` now wraps a `<Sequence>` so it can hold both the log and the animation.)

**How to read the result:**
- **No `HCM_MBT recv` line at all** -> the modded tree is not active, or the message is not
  reaching `switch_hitReactions_detail`. Note that subtree sits behind a `LODGuardian`/`Detail`
  branch, so it only runs at high LOD. Fixing the override is then the task, not the animation.
- **`recv` appears but `branch fired` does not** -> the enum comparison is wrong; the logged
  type/strength values say exactly what arrived.
- **Both appear and the NPC still does not move** -> the MBT `PlayAnimation` node itself is
  overridden by locomotion. That is the end of the line for this approach, and a walk-speed
  reaction would need a custom animation asset.

**Results**: PENDING.

---

### Build: 2.0.0-dev6 (RESULTS)
**Results**: No visible change at walk - but the visual result is irrelevant here, the log is.

**`HCM_MBT` line count: 0**, against 8 walk impacts and 8 `hitReaction sent ok=true` lines in
the same session.

This rules out possibility (b) from dev5: the branch never executed, so nothing was
overridden by locomotion. The MBT `PlayAnimation` approach is **not** disproven. The failure
is upstream, and there are now two candidate causes that must be separated:
- **(a1)** the modded XML is not actually overriding the vanilla behavior tree, or the
  `switch_hitReactions_detail` subtree is not running (it sits behind a `LODGuardian`/`Detail`
  branch and only executes at high LOD);
- **(a2)** `XGenAIModule.SendMessageToEntity(id, "hitReaction", values)` is not delivering.
  **`pcall ok=true` proves only that no Lua error was raised, not that the message landed** -
  exactly the same trap as `human:PlayAnim`. The Lua-facing message name may not be the bare
  `hitReaction`; every vanilla Lua example uses a `module:message` form such as
  `player:request` or `interactionModule:onInteraction`.

---

### Build: 2.0.0-dev7
**Hypothesis**: None - diagnostic, to separate (a1) from (a2).

**Changes**: The `Detail` branch's `IncludeTree` is wrapped in a `<Sequence>` with a
`LogToConsole` in front of it:
```xml
<Detail canSkip="1">
  <Sequence>
    <LogToConsole Message="HCM_MBT detail subtree entered" LogLevel="Error" />
    <IncludeTree File="final/sb_switch_hitReactions.xml" Name="switch_hitReactions_detail" />
  </Sequence>
</Detail>
```
The dev6 handler telemetry is retained unchanged. This log fires whenever any NPC enters high
LOD, so it is deliberately noisy - it is a one-build diagnostic.

**How to read the result:**
- **No `detail subtree entered` line anywhere** -> the override is not live at all. The XML in
  the mod pak is not replacing the vanilla tree. Investigate pak path casing
  (`sb_switch_hitreactions.xml` on disk vs `final/sb_switch_hitReactions.xml` in the
  `IncludeTree` reference), pak path separators, and mod load order.
- **`detail subtree entered` appears but no `recv` on a walk impact** -> the override IS live
  and the subtree IS running, so the Lua message is not being delivered. The fix moves to
  `SendMessageToEntity` - message name form, values string syntax, or entity id.
- **`recv` also appears** -> compare the logged `type=`/`strength=` values against
  Collision(2)/Tickle(2).

**A second, independent test is included in this round**: hit an NPC with a drawn weapon.
That generates a hitReaction from the engine itself. If `recv` appears for a sword hit but
never for a horse collision, the tree and override are proven good and the problem is
isolated to our Lua message.

**Results**: PENDING.

---

### Build: 2.0.0-dev7 (RESULTS) - ROOT CAUSE FOUND
**Results**: `detail subtree entered: 0`, `recv: 0`, `branch fired: 0`, against **93 impacts**
(81 walk, 11 trot, 1 gallop) and 93 `hitReaction sent ok=true` lines, plus direct weapon hits
on NPCs.

The "detail subtree entered" log fires whenever *any* NPC enters high LOD, so zero occurrences
proves the modded behavior tree was never running.

**ROOT CAUSE: the mod pak used Windows path separators in its zip entry names.**

```
vanilla Scripts.pak :  Libs/AI/final/sb_switch_hitreactions.xml   <- forward slashes
our mod pak         :  Libs\AI\final\sb_switch_hitreactions.xml   <- BACKSLASHES
```

`Compress-Archive` writes `\` into zip entry names on Windows. CryEngine resolves pak entries
by **exact path string with forward slashes**, so the modded XML was invisible to the engine
and the vanilla tree was used every time.

**Why this went unnoticed for so long**: `Scripts/Startup/*.lua` is *enumerated* by the mod
loader rather than looked up by exact path, so the Lua half of the mod loaded and ran
perfectly with backslash entries. Only exact-path asset overrides silently failed. Every log
line said the pak opened successfully, and there were no errors anywhere.

**Consequence**: any asset/XML override this mod has ever shipped was inert. This was never a
behavior-tree problem, an animation problem, or a message problem - it was a packaging bug.

**Fix (build.ps1)**: `Compress-Archive` replaced with explicit
`System.IO.Compression.ZipFile` entry creation, normalizing each entry name with
`.Replace("\", "/")`. The build now prints each entry as it is added so the separators are
visible at build time:
```
  + Libs/AI/final/sb_switch_hitreactions.xml
  + Scripts/Startup/HorseCollisionMod.lua
```

**Lesson**: when a data override appears to do nothing, verify the pak's entry names before
suspecting the data. `unzip -l` on the built pak, compared against the vanilla pak, would
have caught this on day one.

---

### Build: 2.0.0-dev8
**Changes**: Rebuilt with the corrected pak writer. No Lua or XML logic changed from dev7 -
the same MBT telemetry and the same Collision+Tickle juke branch. This is the first build in
which the behavior-tree override can actually take effect.

**Expected**: `HCM_MBT detail subtree entered` should now appear (frequently). Then the dev7
decision table applies to whether `recv` and `branch fired` follow.

**Results**: PENDING.

---

### Reference acquired: Nexus Mods KCD wiki mirror
`references/Nexus_KCD_Wiki/` - **35 of 38 pages, 340 KB**, with an `INDEX.md`. The remaining
3 are redirects/stubs with no content.

wiki.nexusmods.com is behind a Cloudflare JS challenge and returns 403 to every direct
request (curl, urllib, WebFetch, `api.php`, `Special:Export`). It is mirrored through the
Wayback Machine instead. Regenerate with `python dl_nexus_wiki.py`; the script skips pages it
already has, so re-runs resume rather than restart.

Two Wayback quirks worth remembering: the CDX index endpoint rate-limits hard (HTTP 429), so
the index is cached to `.cdx_cache.txt`; and the `web/2id_/` shorthand 403s on many pages, so
the script falls back to the availability API to resolve a concrete snapshot timestamp and
fetches `web/<timestamp>id_/` instead. That fallback is what recovered the two most valuable
pages, `RPG_params_in_KCD` (21 KB) and `Modding_guide_for_KCD` (9 KB).

**Relevance**: nothing in the wiki covers Mannequin, behavior trees or animation, so it does
not help the current walk-reaction problem. It is however a strong source for roadmap
phases 2-3 - `RPG_params_in_KCD`, `KCD_RPG_Params`, `RPG_stats_in_KCD`, `Buffs_in_KCD` and
`Table_Data_Types_in_KCD` cover the stat, buff and table-format territory that armor weight
and Horsemanship scaling will need.

---

### Build: 2.0.0-dev8 (RESULTS)
**Results**: `detail subtree entered: 0`, `recv: 0`, `branch fired: 0` against 81 impacts
(52 walk, 14 trot, 15 gallop).

**The pak separator fix was real but was not the (only) cause.** Verified:
- The installed pak now lists `Libs/AI/final/sb_switch_hitreactions.xml` with forward slashes.
- The Lua reports `v2.0.0-dev9`-era versioning correctly (`v2.0.0-dev8` this run), which
  proves the game is reading the **new** pak, not a stale one.

So the pak is correct and being read, and the behavior tree override still appears inert.
Two possibilities remain:
- **(i)** `LogToConsole` does not reach `kcd.log`. The node name says *console*, and it may be
  gated behind an AI debug cvar. If so, the override may have been working since dev8 and we
  simply cannot see it.
- **(ii)** Mod paks genuinely cannot override `Libs/AI/*`, e.g. the AI system loads behavior
  trees before mod paks mount, or from a preprocessed cache. Note kcd.log contains **no**
  behavior-tree or AI load messages at all, so load ordering cannot be read from the log.

---

### Build: 2.0.0-dev9
**Hypothesis**: None - diagnostic, to separate (i) from (ii).

**Changes**: `ExecuteLua` probes added alongside every `LogToConsole` probe. `ExecuteLua` is
used 1709 times in the vanilla trees and can call `System.LogAlways`, which is the one logging
path this project has *proven* reaches `kcd.log`. Prefix `HCM_MBT_LUA` distinguishes them from
the `HCM_MBT` LogToConsole lines.
- Detail branch: `System.LogAlways('HCM_MBT_LUA detail subtree entered')`
- hitReaction handler: logs `data.hitReaction.hitType` / `.hitStrength`, nil-guarded
- Inside the juke branch: `System.LogAlways('HCM_MBT_LUA branch fired')`

**How to read the result:**
- **`HCM_MBT_LUA` lines appear but `HCM_MBT` lines do not** -> `LogToConsole` is gated and the
  override has been live all along. Read the `_LUA` lines for the real state.
- **Neither appears** -> the override is genuinely not loading. Mod paks cannot replace
  `Libs/AI/*` by this route, and the MBT approach needs a different delivery mechanism.

**Note on ExecuteLua authoring**: the `code` attribute is double-wrapped like every other MBT
attribute (`code="&quot;...&quot;"`), uses `&apos;` for Lua string quotes and `&#10;` for
newlines. Tree variables are reached through `data.<varName>`, and the NPC through `entity`.

**Results**: PENDING.

---

### Build: 2.0.0-dev9 (RESULTS) - BREAKTHROUGH, THE OVERRIDE WORKS
**Results** (19 walk, 1 trot, 2 gallop impacts):
```
HCM_MBT_LUA detail subtree entered : 90
HCM_MBT_LUA recv                   : 15
HCM_MBT_LUA branch fired           : 3
HCM_MBT (LogToConsole)             : 0
```

**Three things established at once:**
1. **The behavior-tree override IS live.** 90 detail-subtree entries. The dev8 pak separator
   fix was necessary and correct.
2. **`LogToConsole` does NOT write to kcd.log.** Zero lines despite the tree demonstrably
   running. Every conclusion drawn from its silence in dev6/dev7/dev8 was invalid.
   **Never use `LogToConsole` for MBT telemetry in this project - use `ExecuteLua` with
   `System.LogAlways`.**
3. **`PlayAnimation` was reached** - the juke branch fired 3 times.

**Message delivery data - the important discovery:**
```
sent by our Lua : 19x strength 2 (Tickle), 1x strength 5, 2x strength 6
received by tree: 3x  type=2 str=2   <- ours
                  12x type=2 str=3   <- the ENGINE's own Collision hitReactions
```
- **Our Lua messages are mostly dropped**: only 3 of 19 Tickle arrived, and **none** of the
  strength 5/6 messages arrived at all. The handler is `ProcessMessage Atomic="true"`, so it
  very likely processes one message at a time and discards the rest.
- **The engine reliably emits its own Collision hitReaction at strength 3 (Unpleasant)** on
  horse contact - 12 events. That is a far better trigger than anything we send.

**Recurring failure pattern to remember**: three separate times this project has trusted a
signal whose delivery was never established - `PlayAnim` returning `ok=true`,
`SendMessageToEntity` returning `ok=true`, and `LogToConsole` producing no output. Before
concluding anything from a signal, prove the signal itself works.

---

### Build: 2.0.0-dev10
**Hypothesis**: `PlayAnimation` in the MBT will visibly animate the NPC. This is the last
untested link in the chain and the whole point of the exercise.

**Changes**:
- Juke branch condition widened from `Collision & Tickle` to **`Collision`** alone, so it
  catches the engine's own 12-per-session collision events instead of our unreliable 3.
  Speed-based gating returns once `PlayAnimation` is proven to render.
- All `LogToConsole` nodes removed (proven silent).
- Added `HCM_MBT_LUA PlayAnimation returned` immediately after the node, so the log shows
  whether the node completed or blocked.

**Results**: PENDING.

**If the juke renders**, the remaining work is gating it to walk speed only. The clean way is
an entity flag: Lua writes `entity.hcm_...` on a walk-tier impact (vanilla does exactly this,
e.g. `fleeingNPCEntity.event_chase_area = ...` in sa_event_chase.xml), and an `ExecuteLua`
node in the handler reads `entity` and writes a declared tree variable that the `IfCondition`
tests. That avoids depending on our unreliable message delivery entirely.

---

### Build: 2.0.0-dev10 (RESULTS) - PlayAnimation BLOCKS FOREVER
**User report**: walk produced **no reaction at all - not even the vanilla bark**, which is a
regression from every previous build. Trot and gallop ragdolled as normal.

**Telemetry**:
```
detail entered         : 134
recv                   : 28
branch fired           : 28
PlayAnimation returned : 0     <- the whole story
```

**Diagnosis**: the MBT `PlayAnimation` node is a **blocking action** - it runs until the
animation completes. It never completes here, so the handler's `<Sequence>` stalls at that
node forever. Because the juke branch had been inserted as the **first** child of that
Sequence, every piece of vanilla logic below it - including the bark - never ran. That is
exactly why the bark disappeared, and it is positive proof the node is executing.

Note this also leaves each affected NPC permanently parked in its hitReaction handler, so it
will not process further hit reactions until the save is reloaded.

This most likely also explains dev9's dropped messages: the handler is
`ProcessMessage Atomic="true"`, and a handler stuck inside an unfinished action cannot accept
the next message.

---

### Build: 2.0.0-dev11
**Hypothesis**: `PlayAnimation` hangs because the fragment never acquires the body. Three
independent corrections, and one deliberate simplification:
1. **Placement** - the juke block moved to the **last** child of the handler Sequence, so all
   vanilla logic (bark, crime attribution, perception) completes first.
2. **Timeout** - the node is wrapped in `<Parallel successMode="Any">` alongside a
   `<Wait duration="2.0">`, so the branch can no longer hang the handler regardless of what
   the animation does. The whole block is inside `<SuppressFailure>`.
3. **Context** - `context="NPC_IS_BUSY"` is now set, which is what vanilla uses on full-body
   animations to make the AI yield the body. Previously empty.
4. **Fragment** - switched from `Juke90Left` to **`WalkThrough`** for this test. Per the ADB
   audit, `WalkThrough` has a single option with `Tags=""`, so it is the one fragment
   guaranteed to resolve in any tag state. If even that will not play, the problem is the
   mechanism, not the fragment choice.

Probes now bracket the block: `juke block start` and `juke block end`.

**How to read the result:**
- **`block start` and `block end` both appear** -> the node no longer hangs. Whether the NPC
  visibly moves then tells us if `WalkThrough` rendered.
- **`start` but no `end`** -> even the Wait/Parallel cannot break it out, which would point at
  the action system rather than the fragment.
- **Vanilla bark returns at walk** -> confirms the stall diagnosis was right.

**Results**: PENDING.

---

### Build: 2.0.0-dev11 (RESULTS)
**User report**: **the vanilla bark is back** at walk speed, confirming the dev10 stall
diagnosis exactly. Still no visible animation.

**Telemetry**: `detail entered 122`, `recv 22`, `juke block start 22`, `juke block end 22`.

**Diagnosis**: the node no longer hangs - moving the block to the end of the Sequence and
capping it with `Parallel`+`Wait` fixed the stall, and the returning bark proves it. But
`start` and `end` are logged **back to back with no 2-second gap**, so the `Wait` never
elapsed. `PlayAnimation` is now returning (or failing) *immediately* rather than playing.

Adding `context="NPC_IS_BUSY"` therefore changed the node's behavior from *hang forever* to
*return instantly*, without ever rendering. The bracketing probes cannot distinguish success
from failure, which is the gap dev12 closes.

Also of note: `recv type=2 str=5` appeared, i.e. one of our own trot-tier messages
(MinorInjury) did get through this time.

---

### Build: 2.0.0-dev12
**Hypothesis**: The node's attributes are wrong, not the mechanism. Rather than guessing
further, copy the attribute set from a vanilla `PlayAnimation` that is **known to work on a
standing NPC** - the `ADLG_Listen` dialog gesture:
```
context=""   InterruptSafeStart="OFF"
```
dev11 used `context="NPC_IS_BUSY"` with `InterruptSafeStart="AUTO"`. `AUTO` is plausibly the
culprit on its own: it defers the start until the engine considers it safe, which for an NPC
under continuous locomotion control may be never. Vanilla uses `OFF` in 49 places precisely
where an animation must start immediately.

**Changes**:
- `context=""` and `InterruptSafeStart="OFF"`, matching ADLG_Listen exactly.
- `PlayAnimation` moved inside a `<Sequence>` with a **`PlayAnimation SUCCEEDED`** probe
  directly after it. A `Sequence` aborts on child failure, so the presence or absence of that
  line finally separates success from failure.
- `Wait` raised to 5.0s so a genuine animation has room to play and would show as a visible
  gap in the log timestamps.
- Fragment still `WalkThrough` (the only `Tags=""` fragment, guaranteed to resolve).

**How to read the result:**
- **`SUCCEEDED` appears** -> the node ran and reported success. If nothing renders after that,
  the fragment is being played into a scope the locomotion system immediately overwrites.
- **`SUCCEEDED` missing** -> `PlayAnimation` is failing. The fragment or its arguments are
  rejected, and `WalkThrough` failing would mean the arguments, not the fragment.

**Results**: PENDING.

---

### Build: 2.0.0-dev12 (RESULTS) - DEFINITIVE: THE ANIMATION IS UNREACHABLE
**Telemetry**: `recv 14`, `juke block start 14`, **`PlayAnimation SUCCEEDED 0`**, `end 14`.

`PlayAnimation` is **failing**, not succeeding-invisibly - and it failed with `WalkThrough`,
the one fragment with `Tags=""` that is guaranteed to resolve in any tag state, using the
exact attribute set copied from vanilla's known-good `ADLG_Listen` node
(`context=""`, `InterruptSafeStart="OFF"`).

**ROOT CAUSE - a structural rule of the AI architecture:**
```
PlayAnimation nodes across all 31 sb_switch_*.xml trees : 0
```
Zero. Not one, in any switch tree, out of 369 behavior trees in the game.

Every tree that plays animations is an `sa_*` (smart activity), `so_*` (smart object) or
`npc_*` tree - trees that **own the NPC's body**. The `sb_switch_*` trees are passive parallel
observers: they react to events, send messages, set variables and change AI state, but they do
not drive the body. `sb_switch_hitreactions` is one of those observers.

So `PlayAnimation` failing here is not a bug in our arguments. It is the engine correctly
refusing an animation request from a tree that does not own the body. **Warhorse never does
this anywhere in the game**, which is why there was no working example to copy.

Playing an animation on an arbitrary NPC would require interrupting whatever activity tree
currently owns that NPC - a different tree for every NPC at every moment - which means editing
the core activity and daycycle trees rather than one switch tree. That is out of scope for
this mod and would break compatibility with almost everything.

**FINAL CONCLUSION: a walk-speed reaction animation is not reachable from a KCD mod.** It is
reachable only through the C++ combat hit-reaction path, which is exactly why `CombatHit` is
tag-gated behind a drawn weapon and combat guard state. This is a documented engine
limitation, not an unfinished task. **Do not reopen this without new information.**

Note this is not an asset problem - authoring a custom animation would not help, because the
blocker is playback authority, not the absence of a clip.

---

### Build: 2.0.0-rc1 - CLEAN RELEASE CANDIDATE
The MBT override is **removed** (`mod_xmls/` renamed to `mod_xmls.disabled/`, preserved for
reference). The mod is Lua-only again and therefore conflicts with nothing.

**What ships:**
- Three gait tiers matching the measured plateaus: Walk >=1.8, Trot >=4.5, Gallop >=8.5 m/s.
- **Walk**: native `hitReaction` message only - vanilla bark, perception and crime handling,
  no ragdoll, no damage. This is the honest ceiling for walk speed.
- **Trot**: ragdoll at 0.6x impulse, `MinorInjury`, 20 stamina.
- **Gallop**: ragdoll at 1.0x impulse, `MajorInjury`, 40 stamina.
- Horse stamina drains correctly via `soul:SetState`, and empties the rider onto the ground -
  the anti-bulldozing mechanic. Tune `StaminaDrainTrot` / `StaminaDrainGallop` down to be
  thrown sooner.
- Mutt protection retained.
- All dead animation code removed (fragment ladders, juke side selection, API probes).

**Roadmap status**: Phase 1 velocity tiering is **done**. Phase 1 non-ragdoll walk reactions
are **closed as engine-limited**. Phase 2 (mass, armor, momentum) is unblocked and is the
natural next target - and the dev8 pak fix is a prerequisite for any of its data overrides.

---

### Correction to the dev1 finding about CombatHit
The dev1 entry claimed all 241 `CombatHit` options require a drawn weapon. That was based on
the first 25 options, which are all longsword. A full audit of the block shows **48 of the 241
options carry `noweapon` tags** (`r_noweapon`, `l_noweapon`, `ol_noweapon`, `or_noweapon`).
`CombatHit` is therefore reachable for an unarmed NPC. The "structurally unreachable outside an
armed duel" wording was too strong and is withdrawn.

This does not change the dev12 conclusion, which rests on different evidence: `PlayAnimation`
failed from `sb_switch_hitreactions` even with `WalkThrough` (`Tags=""`, always resolvable), so
the blocker there is body ownership, not fragment gating. But it does matter for the question
below.

### Build: 2.1.0-dev1 - two new levers
**Observation that prompted this** (from the user): swinging a weapon at a peaceful NPC walking
down the street makes them recoil with exactly the wanted animation. So the animation *is*
playable on a non-combat NPC. The question is what event produces it.

**The distinction previously conflated**: this project has only ever sent `hitReaction`, which
is a *physical* event consumed by `sb_switch_hitreactions` - a passive observer tree proven
unable to drive the body. A real weapon strike instead drives **`combat:hit`**, which feeds the
**combat sub-brain**, and that owns the body. Vanilla sends this message to itself inside
sb_switch_hitreactions.xml when the player's horse tramples an NPC:
```xml
<InstantSendMessageToNPC target="this.id" type="combat:hit"
    values="attacker($__player), strength($hitReaction.hitStrength),
            hitType($enum:HitReactionType.Melee), real(true)" />
```
`combat:hit` has never been sent from this mod. Message delivery from Lua is already proven to
work (dev9), so this is a genuinely untried lever, not a repeat.

**Change 1 - `SendCombatHit`**: at walk speed, sends
`combat:hit` with `attacker(<player wuid>), strength(3), hitType(Melee), real(true)`.
Player WUID resolved once via `XGenAIModule.GetMyWUID(player)` + `Framework.WUIDToMsg`.
Config: `WalkCombatHit`, `WalkCombatHitStrength`.

**Change 2 - `CheckHorse`** (the requested horse-side prototype): on a walking contact the
**horse** takes a braking impulse opposite its velocity. This deliberately depends on nothing
the engine denies mods - impulses are ignored on standing NPCs, but the horse is a moving
physicalised entity. Horse speed is re-sampled 400 ms later and logged, so the telemetry shows
whether the impulse took. Config: `WalkHorseCheck`, `HorseCheckImpulse` (900).

**Expected log lines**: `Player WUID msg = ...`, `combat:hit sent ... ok=true`,
`Horse check applied at N m/s`, `Horse speed after check: N`.

**Results**: PENDING.

**Caveat to watch for**: `combat:hit` may make the NPC hostile, since it is the event that
normally means "the player attacked me". If the recoil appears but everyone draws weapons,
the lever works and the tuning question becomes strength and crime suppression.

---

### Build: 2.1.0-dev1 (RESULTS)
- **`combat:hit`**: 12 sent, `ok=true`, no visible reaction. As always, `ok=true` proves
  nothing about delivery, and the `combatHit` inbox is consumed by
  `sb_switch_hitreactions` - the same passive observer tree - so even on delivery it is an
  AI notification rather than an animation driver.
- **Horse braking impulse: effectively useless.** 3.19 -> 3.02, 2.89 -> 2.81, and one case
  went *up* 2.85 -> 2.89. **The horse is animation-driven too**, exactly like the NPCs, so
  `AddImpulse` does not meaningfully move it. Physics is not a lever on any KCD actor.

**A real bug uncovered while checking signatures**: `soul:DealDamage` registers its
parameters in the decompiled binding as **`"stamina,health"`** (line 3423557), but vanilla's
own debug helper `Scripts/Script/Quick.lua` calls it as
`DealDamage(hitToHealth, hitToStamina, __null, true)`. Both cannot be correct.
Builds 1.4.0-rc1/rc3 and 2.0.0-dev1/dev2 all called it without knowing which, and dev1/dev2
called `horseEnt.soul:DealDamage(0, staminaDrain, nil, true)` on the **horse**. If the
registered order is right, that was 25 points of **health** damage to the horse per impact,
not stamina - which fits the dev1 report that the horse bolted and struggled to return. The
earlier diary claim that this call was "a no-op" is therefore **withdrawn**; it may simply
have been hitting the wrong stat. Current builds use `soul:SetState` and are unaffected.

Also note every previous `DealDamage` attempt passed a **nil attacker**. Vanilla passes
`__null` and, for a real strike, a genuine attacker. An anonymous hit is plausibly read as a
trample rather than as "the player struck me", which is precisely the distinction that
decides whether the combat recoil plays.

**Useful discovery**: vanilla's collision barks are dialog monolog metaroles -
`KOLIZE_S_HRACEM` (collision with player), `KOLIZE_S_HRACEM_LEHKA` (light), and
`KOLIZE_S_HRACEM_NA_KONI` (on horseback). Vanilla already distinguishes light from normal
collisions for barks, which is a ready-made hook if bark variation is ever wanted.

---

### Build: 2.1.0-dev2
**Change 1 - `DealWalkHit`**: deals a minimal hit with the **player as the named attacker**,
and logs the victim's health and stamina either side of the call. This tests the user's
counter-example directly (a weapon strike makes a peaceful NPC recoil) and, as a side effect,
**resolves the argument-order ambiguity empirically** - whichever stat moves is the second
argument's slot. Config: `WalkDealDamage`, `WalkDamageArgA`, `WalkDamageArgB`.

**Change 2 - `CheckHorse` rewritten**: the useless braking impulse is replaced with vanilla's
own way of making a horse react, from `so_camp_horseWork.xml`:
`hitReaction` at `Exhausting` strength sent to the horse entity.

**Expected log**: `DealDamage(0,1,player,true) ok=... | hp X->Y | sp A->B` and
`Horse hitReaction(Exhausting) ok=...`.

**Results**: PENDING.

---

### Build: 2.1.0-dev2 (RESULTS) - ARGUMENT ORDER SETTLED, AND A SHIPPED BUG CONFIRMED
```
DealDamage(0,1,player,true) ok=true | hp 100->99 | sp 115->115
DealDamage(0,1,player,true) ok=true | hp  99->98 | sp  81.15->81.15
```
14 calls, health fell by exactly 1 each time, stamina never moved.

**`soul:DealDamage(stamina, health, attacker, ?)` - the decompiled binding was right and
`Quick.lua`'s parameter names are misleading.** Argument A is stamina, argument B is health.

**Therefore the horse bug is confirmed.** Builds 2.0.0-dev1 and dev2 called
`horseEnt.soul:DealDamage(0, 25, nil, true)` on the horse, which was **25 points of health
damage per impact**, not stamina. That explains the dev1 report of the horse bolting and
struggling to return. Not present in any current build (they use `soul:SetState`), but any
future use of `DealDamage` must respect this order.

**And the substantive result: a real hit, with the player as named attacker, produces no
recoil, no hostility, nothing.** `soul:DealDamage` is an **RPG-layer stat operation**. It
does not generate a combat hit event, so it cannot produce the reaction a weapon swing does.
The named-attacker hypothesis is disproven.

`hitReaction` at Exhausting strength to the horse also produced no visible horse reaction.

**Cumulative: every message-based and stat-based lever is now exhausted.**

| Lever | Layer reached | Result |
|---|---|---|
| `hitReaction` message | AI observer tree | delivered, no animation |
| `combat:hit` message | AI observer tree | no effect |
| `soul:DealDamage` | RPG stats | health changes, no reaction |
| `human:PlayAnim` | - | accepted, never renders |
| MBT `PlayAnimation` from switch tree | - | fails, no body ownership |
| `AddImpulse` on NPC | physics | ignored (animation-driven) |
| `AddImpulse` on horse | physics | 3.19 -> 3.02 m/s, negligible |

The recoil on a weapon swing is produced by the **C++ combat system's own weapon-collision
path**, which owns the body. No Lua binding injects into it.

---

### Build: 2.1.0-dev3
**Change**: `DealWalkHit` disabled (its question is answered, and it was costing NPCs health
for nothing). Added `TryInteractiveAction` - the last body-owning API reachable from Lua.

`actor:StartInteractiveActionByName(ActionName, ObjectId, UpdateVisibility, AnimSpeed)` is
how vanilla takes over an actor to play door and cabinet animations
(`player.actor:StartInteractiveActionByName(npcAnim, self.id, true, 1)`, AnimDoor.lua:773),
and the dev1 API probe confirmed it exists on NPCs.

The valid action-name vocabulary is smart-object data not present in the SDK libs, so the
build walks a ladder of five name/target combinations, one per impact, and logs each.

**Caveat recorded in advance**: a `pcall` result of `true` proves nothing here. This project
has been caught by that three times (`PlayAnim`, `SendMessageToEntity`, `LogToConsole`).
Only what is seen in game counts.

**Results**: PENDING.

---

### Build: 2.1.0-dev3 (RESULTS) - THE BODY MOVED
**User report**: "a very quick glitchy movement that was almost instant then the NPC snapped
back into normal behavior and gave the bark."

**This is the first time any approach has visibly moved an NPC's body.**
`actor:StartInteractiveActionByName` **does** acquire body ownership from Lua. The motion was
instantaneous because all five probe names were invalid, so the action aborted the moment it
started and locomotion reclaimed the body. All five logged `ok=true`, which as always proves
nothing.

**THE KEY DISCOVERY - what ActionName actually is.** Vanilla calls
`StartInteractiveActionByName("cabinet_c", ...)`. `cabinet_c` is **not** a fragment ID; it does
not appear in kcd_male_fragmentids.xml at all. It is a **`FragTags`** value inside the
animation database:
```xml
<Fragment BlendOutDuration="0.2" Tags="" FragTags="cabinet_c">
  <Animation name="library_cabinet_close" />
```
So `ActionName` resolves against **FragTags**, a completely different namespace from the
fragment IDs and Tags this project has been using for twelve builds. Dumping every FragTags in
`kcd_male_database.adb` gives 3662 values across 208 fragments - the real vocabulary.

**The two that matter:**
```
HitDeathTorso (16) : so_{back,forward,left,right}[+head]+{weak_hit,minor_hit}
HitDeath      (23) : so_{back,forward,left,right}+{minor_hit,major_hit,death,collision+major_hit}
                     plus bare: fall, minor_hit, major_hit
CombatHitTorso (6) : dZ0..dZ5+hitTypeLow
```
- **`HitDeathTorso` is torso-only** - an upper-body flinch that does not ragdoll, in `weak_hit`
  and `minor_hit` strengths, and **directional**. This is the walk-speed reaction the project
  has been looking for since build 1.4.0.
- **`HitDeath` carries `so_<dir>+collision+major_hit`** - the engine's own horse-trample
  reaction, by name.

The user's instinct was right and my "unreachable" conclusion was wrong for a second reason:
I had been searching the wrong namespace the entire time.

---

### Build: 2.1.0-dev4
**Changes**:
- Probe ladder replaced with **real FragTags names**: `so_<dir>+weak_hit`,
  `so_<dir>+minor_hit`, bare `minor_hit`, and `so_<dir>+collision+major_hit`.
- New `GetImpactDir` computes the impact direction in the **victim's own frame** from
  `GetDirectionVector(1)` and the horse position, and substitutes the correct `so_forward` /
  `so_back` / `so_left` / `so_right` prefix per hit.
- `horsePos` threaded through `TriggerCollision` so the direction can be computed.

**Results**: PENDING. Watch for a reaction that *holds* rather than snapping back.

---

### Build: 2.1.0-dev4 (RESULTS) + THE SECOND HALF OF THE DISCOVERY
**User report**: same one-frame glitchy movement, then snap back. All 7 ladder entries fired,
all `ok=true`, direction substitution working (`so_forward` / `so_back` both appearing).

**Video evidence** (`test_footage/`, frames before / of / after): in the "of" frame the guard
has visibly **dropped and compressed** - the reaction pose genuinely begins - and then reverts.
So the animation is starting and being canceled within roughly one frame, rather than never
starting. Screenshots are readable directly with the Read tool and were decisive here; ask for
them whenever "it looked glitchy" is the only description available.

**THE MISSING HALF: Tags and FragTags are two different namespaces, and this project has been
using the wrong one since build 1.4.0.**

A Mannequin fragment option can be selected by `Tags` **or** by `FragTags`:
```xml
<Fragment Tags="walk" />                          <- selected by Tags
<Fragment Tags="" FragTags="so_forward+weak_hit" />  <- selected by FragTags
```
`HitDeathTorso`, `HitDeath` and `CombatHitTorso` all carry **`Tags=""`** and are keyed
**entirely by FragTags**. Every `PlayAnim` call this project ever made passed a *Tags* value -
`"hitTypeLow"`, `"walk"` - so for those fragments nothing could ever resolve. That is the real
reason `PlayAnim` was silently inert, not a lack of body ownership.

**The calling convention is proven by vanilla's own MBT tag strings**, all verified against the
database as FragmentID(FragTags) pairs:
```
'CartTow(cartTowFail_A)'   -> CartTow   has FragTags cartTowFail_A   : True
'LeaningIn(leaningBack)'   -> LeaningIn has FragTags leaningBack     : True
'WashFace(washFaceTub)'    -> WashFace  has FragTags washFaceTub     : True
```

---

### Build: 2.1.0-dev5
**Changes**: probe ladder rebuilt to test the **correct vocabulary through both delivery
methods**, one candidate per impact:
1. `PlayAnim("HitDeathTorso", "so_<dir>+weak_hit")`
2. `PlayAnim("HitDeathTorso", "HitDeathTorso(so_<dir>+weak_hit)")`  - the vanilla bracket form
3. `PlayAnim("HitDeathTorso", "so_<dir>+minor_hit")`
4. `PlayAnim("CombatHitTorso", "dZ0+hitTypeLow")`
5. `PlayAnim("HitDeath", "so_<dir>+minor_hit")`
6. `StartInteractiveActionByName("so_<dir>+weak_hit", ...)`

`PlayAnim` is back in play because the reason it failed is now understood and corrected.

**Results**: PENDING. The thing to watch for is a reaction that **holds** for its full duration
rather than lasting a single frame.

---

### Build: 2.1.0-dev5 (RESULTS)
**User report**: underwater/bogged audio, otherwise vanilla - no glitch, no animation, default
barks. All 8 ladder entries fired, all `ok=true`.

**Audio: not this mod.** The log carries a repeating pair of errors every 0.5 s -
`ERROR: operation 'Do connect' takes too much time` and
`PROS: disconnected on server side. Trying to reconnect.` That is Warhorse's PROS online
service failing to connect and retrying on the main thread, which is what stalls the audio.
It appears in logbackups going back to **15 Aug**, 11-14 occurrences per session, long
predating any of this work. The mod's own log output is 478 lines / 26 KB with no repetition,
so it is not flooding anything. If it becomes annoying, disabling the online/telemetry
connection is the fix, not touching the mod.

**The mechanism is now pinned down precisely.**

`StartInteractiveActionByName` resolves its `ActionName` against the FragTags of **one
fragment only: `AnimationControlled`**. That fragment has exactly **30 options**, and every one
is an object interaction:
```
cabinet_o -> library_cabinet_open      wardrobe_o  -> wardrobe_open
cabinet_c -> library_cabinet_close     alarmBell   -> ringing_alarm_bell
door_{l,r}_{f,b}_{o,c}[+gate{Big,Small}] -> door/gate clips
```
`so_forward+weak_hit` is not among them. **That is why dev3/dev4 acquired the body and aborted
within one frame**: a valid call with no matching option. The one-frame pose drop in the video
was the action starting and instantly finding nothing to play.

`human:PlayAnim` has still never visibly moved an NPC under any vocabulary (Tags, FragTags, or
the bracket form), so it is dropped.

**The target clips are identified.** `HitDeathTorso` maps to:
```
combat_hit_small_back_add / _left_add / _right_add
freeblock_hit_small_front_add / _back_add
```
The **`_add` suffix means additive** - these layer a torso flinch over whatever the body is
already doing rather than replacing it, which is precisely the right shape for a walking bump.

---

### Build: 2.1.0-dev6
**Hypothesis**: the interactive action will **hold** if given a name that actually exists.

**Change**: ladder reduced to four **known-valid `AnimationControlled` FragTags** -
`cabinet_o`, `wardrobe_o`, `alarmBell`, `door_l_f_o`. Each has a real clip behind it, so a
villager should visibly mime opening a cabinet or ringing a bell in the middle of the street.
Deliberately absurd, because the question is only whether the action holds.

**How to read the result:**
- **A villager plays an obvious object animation that holds** -> mechanism proven. The sole
  remaining constraint is vocabulary, and the animation database is plain XML we can extend.
- **Still a one-frame glitch** -> the API cannot hold on an NPC regardless of name, and the
  interactive-action route is finished.

**If it holds, the plan** is to ship a modified `kcd_male_database.adb` adding a new option to
`AnimationControlled` with a custom FragTags (e.g. `hcm_stagger_back`) pointing at
`combat_hit_small_back_add`, then call it by name from Lua. The dev8 pak-separator fix is a
prerequisite for that override loading at all.

**Results**: PENDING.

---

### Build: 2.1.0-dev6 (RESULTS) - MECHANISM PROVEN
**User report**: "all of the animations worked! Kind of funny watching them ring an imaginary
bell or open a ghost cabinet. They ran through the animations and then seemingly returned to
their normal behavior."

**`actor:StartInteractiveActionByName` plays a full animation on an ordinary NPC, holds for
its whole duration, and hands the body back cleanly afterwards.** This is the working vehicle
the project has been looking for since build 1.4.0.

The one-frame glitch in dev3/dev4 was never a body-ownership problem. It was a valid call with
no matching option: the API resolves its name against the FragTags of a **single** fragment,
`AnimationControlled`, and vanilla only ships object interactions there.

Also observed: a dog did not react. Dogs use `kcd_dog_database.adb`, a separate database, so
this is expected.

---

### Build: 2.1.0-dev7 - AUTHORING OUR OWN VOCABULARY
Since the mechanism works and the constraint is only vocabulary, and the animation database is
plain XML, the mod now **adds its own options** to `AnimationControlled` (32 -> 40), pointing
at standing hit-reaction clips the game already ships:
```
hcm_stagger_{front,back,left,right} -> hitreaction_idle_medium_torso_stab_{dir}
hcm_shove_{front,back,left,right}   -> hitreaction_idle_heavy_{dir}
```
`hitreaction_idle_*` clips are **non-additive full-body** reactions, so they read as a stagger
on their own. The `combat_hit_small_*_add` clips are additive and expect a base pose
underneath, which is why they were the wrong choice.

**New tooling**:
- `build_adb.py` regenerates the modded database from the vanilla pak. It verifies every
  referenced clip exists first, since a missing clip resolves to nothing silently - the exact
  failure mode that cost this project a dozen builds. It also contains a tolerant pak reader:
  KCD paks store forward slashes in the central directory but backslashes in local headers,
  which Python's `zipfile` rejects as corruption, so entries are inflated from the local header
  directly.
- `build.ps1` now copies anything under `mod_assets/` into the pak, replacing the old
  single-file `mod_xmls` special case.
- Lua `PlayStagger(npc, horsePos, prefix)` picks the direction in the victim's own frame and
  calls the matching action.

**Scope limits, by design:**
- **Male NPCs only.** `wh_female_fragmentids.xml` declares no `AnimationControlled` fragment at
  all, so females fall through to the vanilla bark. Adding it means editing the female
  fragmentids as well as the database.
- **Compatibility cost**: this ships a full replacement of `kcd_male_database.adb` (5.5 MB), so
  it will conflict with any mod that edits male animations.

**Results**: PENDING.

---

### Build: 2.1.0-dev7 (RESULTS) - MY NAMING BUG
**User report**: single-frame glitch, then vanilla.

**Telemetry**: the action names actually sent were
```
5 x hcm_stagger_forward     <- does not exist in the database
1 x hcm_stagger_back        1 x hcm_stagger_right    2 x hcm_stagger_left
```
`GetImpactDir` returns `so_forward` (matching vanilla's HitDeathTorso FragTags naming) and the
Lua strips `so_` to get `forward`, but `build_adb.py` authored the option as
**`hcm_stagger_front`** (matching the clip naming). The majority of impacts therefore asked for
a name that does not exist - a valid call with no matching option, i.e. exactly the one-frame
abort signature again. Fixed by authoring `hcm_stagger_forward`.

Four impacts did use names that exist (`back`, `left`, `right`) and were still reported as
glitchy, so a second possibility has to be excluded: **the modded database may not be loading
at all.** Overriding `Animations/...` from a mod pak has never been verified in this project;
only `Libs/` and `Scripts/` have.

---

### Build: 2.1.0-dev8
**Changes**:
1. **Naming fixed** - `hcm_stagger_forward` / `hcm_shove_forward`, matching what the Lua sends.
2. **Canary added** to settle whether the modded database loads. `build_adb.py` now repoints
   the **vanilla** `cabinet_o` option away from `library_cabinet_open` to
   `hitreaction_idle_heavy_back`, and the Lua alternates each walk impact between our own
   `hcm_stagger_<dir>` and plain `cabinet_o`.

**How to read the result** - `cabinet_o` is the discriminator, because dev6 proved it works
against the vanilla database:
- **cabinet_o makes an NPC stagger** (not mime a cabinet) -> our database IS loaded. Then
  whether `hcm_stagger_*` works tells us if our authored options are well formed.
- **cabinet_o still mimes a cabinet** -> our database is NOT loading. Animation pak overrides
  do not work the way Libs/Scripts overrides do, and the next question is load order or
  animation preloading (`wh_am_ReloadDB` and `wh_am_PreprocessingAnimations` exist as CVars).
- **cabinet_o does nothing at all** -> the modded database loaded but is broken, and the
  vanilla option was destroyed along with it.

This single build distinguishes all three outcomes, which no amount of staring at
`hcm_stagger_*` alone could do.

**Results**: PENDING.

---

### Build: 2.1.0-dev8 (RESULTS) - THE CANARY ANSWERED IT
**User report**: "I noticed the stagger (I think on the very first one)! It seemed to happen
about every 4-5 times or so. It seems to cut off way too early... snaps back after what seems
like less than a second. I saw no other animations fire except no animation/vanilla and one
frame glitch movement."

**Log sequence** - clean alternation, 7 canary calls and 7 of ours:
```
cabinet_o -> hcm_stagger_forward -> cabinet_o -> hcm_stagger_forward -> ...
```

**The canary fired and our options did not**, which settles both open questions at once:
1. **The modded animation database IS loaded from a mod pak.** `cabinet_o` produced a stagger
   instead of miming a cabinet, which can only happen if our repointed database is in use.
   Animation overrides work exactly like Libs/Scripts overrides.
2. **Our authored options were still inert** - the one-frame glitch, on every `hcm_*` call.

**ROOT CAUSE OF THE REMAINING FAILURE: FragTags must be declared.**
`kcd_male_fragmentids.xml` line 131:
```xml
<Tag name="AnimationControlled"
     subTagDef="Animations/Mannequin/ADB/kcd_animationControlledTags.xml" />
```
Each fragment's FragTags vocabulary is declared in a **separate subTagDef file**. Adding an
option to the database is not enough; if its FragTags are not declared there, the lookup finds
nothing and the action aborts after a frame. `cabinet_o` worked precisely because it is
already declared in that file.

So there are **three** files in the chain, and this project has now been bitten once by each:
fragment IDs, the database options, and the subTagDef declarations.

---

### Build: 2.1.0-dev9
**Changes**:
- `build_adb.py` now emits **both** files: the modded `kcd_male_database.adb` and a modded
  `kcd_animationControlledTags.xml` declaring our eight tags in a new `HcmReaction` group.
- Canary removed from both the database and the Lua; it has served its purpose.
- Every walk impact now calls `hcm_stagger_<dir>` directly.

**Known issue carried forward**: the canary stagger "cut off way too early ... less than a
second", the NPC beginning to lose balance and then snapping back. Our own options use a
minimal template rather than the vanilla cabinet_o option's layers (which include
`PositionAdjustAlignBone` and an `AnimateCamera` layer with `ExitTime="2.8"` tuned for a
different clip), so duration may behave differently. If our stagger also truncates, the next
lever is `BlendOutDuration` and the ProcLayer set, not the fragment choice.

**Results**: PENDING.

---

### Build: 2.1.0-dev9 (RESULTS) - **WORKING**
**User report**: "it seems to work fundamentally as it should. Every collision with the horse
at walking speed has the NPC play a full stagger animation that feels pretty realistic."

**The walk-speed non-ragdoll reaction is solved**, after being open since build 1.4.0.

**The complete working chain**, for anyone reading this later:
1. Lua calls `npc.actor:StartInteractiveActionByName("hcm_stagger_<dir>", npc.id, true, 1)`.
2. That name is looked up in the **FragTags of the `AnimationControlled` fragment only**.
3. The option is added to `Animations/Mannequin/ADB/kcd_male_database.adb`, pointing at
   `hitreaction_idle_medium_torso_stab_<dir>` - a non-additive standing hit reaction the game
   already ships.
4. The FragTags value is declared in the fragment's subTagDef,
   `Animations/Mannequin/ADB/kcd_animationControlledTags.xml`. **Steps 3 and 4 are both
   mandatory**; either alone produces a one-frame abort.
5. Both files ship in the mod pak with **forward-slash entry names** (see the dev8 packaging
   fix under 2.0.0), or the engine never sees them.

**Open tuning issues reported, deferred to the next phase:**
- Stagger direction does not correlate well with the actual impact direction.
- The player gets "stuck" in NPCs - they do not move aside, and the collider feels oversized.
- `HitRadius` (2.5) is too large; NPCs react from an unnatural distance.

---

### Milestone: 2.1.0-rc1
Buttoned up for a commit before tuning begins, since the next phase can regress this.

**Tooling hardened in the same pass:**
- `build.ps1` now **runs `build_adb.py` automatically** when `mod_assets/` is missing. That
  directory is derived from the game's own paks, so it is gitignored rather than committed,
  and a fresh clone would otherwise silently build a Lua-only mod with no stagger - a trap
  worth closing.
- `build.ps1` now **fails the build** if either animation file is missing from the staged pak,
  because the failure mode in game is a silent no-op that costs a full test cycle to diagnose.
- Verified end to end: deleting `mod_assets/` and building reproduces both files and packs
  all three entries.

---

## Archived dev sessions (removed)

`archived_dev_session_1/` (72 MB) and `archived_dev_session_5/` (6.8 GB) were deleted
during the 2.1.0-rc1 cleanup. Both were snapshots of earlier attempts at the same
walk-speed animation problem, and session 5 additionally contained a nested copy of
session 1 and of the whole `references/` tree, which is where its size came from.

Everything of value is recorded below so the directories did not need keeping.

**Duplicates, nothing lost**: the five Warhorse scripting-tutorial transcripts in
session 1 are byte-identical to `references/vid_1.txt` through `vid_5.txt`, and
`references/` additionally holds videos 6 to 8. The source URLs for all eight are now at
`references/vid_transcript_sources.md`.

**Worth carrying forward** - from session 1's `KCD_Scripting_Truth.md`, a summary of
Martin Cerny's thesis on the AI architecture, which matches what this project observed
independently:

> NPCs are essentially empty vessels operated by Behavior Objects. An NPC does not own
> its routine; its brain subscribes to a Behavior Object. When a physics event such as a
> horse bump occurs, the C++ engine passes an AI hitReaction message to the NPC's inbox,
> and the active Behavior Object processes it.

That is consistent with the finding that `sb_switch_*` trees are passive observers with
no `PlayAnimation` node anywhere among them, and it explains why the native horse-collision
path terminates in a `KOLIZE_S_HRACEM_NA_KONI` dialog bark and nothing else.

**Corrections to that document**, since it was written before this session's testing and
its central claim is wrong:

- It states that sending `combat:hit` "successfully forces a stagger" by shunting the NPC
  into the combat behavior object. **This was tested directly in build 2.1.0-dev1 and is
  false.** Twelve `combat:hit` messages produced no animation, no hostility and no
  visible change. The `combatHit` inbox is consumed by `sb_switch_hitreactions`, the same
  passive observer tree, so it cannot drive the body.
- Its proposed Path A, editing `sb_switch_hitreactions.xml` to add a `PlayAnimation` node,
  was implemented across builds 2.0.0-dev5 through dev12 and **does not work**. The node
  fails because a switch tree does not own the NPC's body.
- Its Path B, an invisible smart area with a custom behavior tree, was never tried and
  remains untested. It is moot now that the interactive-action route works.

The approach that actually succeeded is not among that document's suggestions:
`actor:StartInteractiveActionByName` with FragTags added to the `AnimationControlled`
fragment. See the 2.1.0-dev6 through dev9 entries above.

---

### Build: 2.0.0-rc.1 (RESULTS)
**User report**: stagger animation works well. Three problems remain.
1. NPCs still react when ridden past without contact, so detection reach is still too wide.
2. The horse still gets stuck on a staggering NPC. Walking head-on into someone results in
   both pushing against each other with neither able to clear.
3. Stagger directions look better, but are hard to judge while the stuck problem dominates.

**Analyzis of the reach.** The footprint borrowed the horse_impact_ragdoll values
(front 1.48, rear 0.58, half-width 0.90). A 0.90 half-width is a **1.8 m corridor** and a
horse body is roughly 0.7 m across, so someone standing half a meter clear of the flank was
still inside the box. Rear reach also allowed reactions from behind the horse's origin.

---

### Build: 2.0.0-rc.2
**Changes**:
- Footprint tightened: front 1.48 -> **1.15**, rear 0.58 -> **0.20**, half-width
  0.90 -> **0.55**.
- **Every accepted impact now logs its own geometry**: `Footprint fwd=.. lat=.. dz=..
  sweep=..`. The next tuning pass reads real distances instead of guessing at dimensions.
- New `Config.WalkStagger` toggle. Setting it false disables only the walk stagger and
  leaves the knockdown tiers alone, which allows a direct A/B against vanilla collision
  handling without uninstalling.

**On the stuck problem.** Setting the animation's `ColliderMode` to `Disabled` in rc.1 did
not fix it, and there is no evidence that layer takes effect at all. Two possibilities need
separating before more work goes into it:
- **It is vanilla.** NPCs are solid to a horse in unmodded KCD, and mutual pushing is the
  normal result of riding into someone who is walking at you.
- **The mod makes it worse.** The stagger takes over the body for about a second, during
  which the NPC cannot sidestep, so a collision that vanilla would resolve by the NPC
  stepping around instead becomes a standoff.

`WalkStagger = false` distinguishes the two. If the standoff still happens with it off, the
behavior is vanilla and the fix belongs in Phase 2 momentum work rather than here.

---

### Build: 2.0.0-rc.2 (RESULTS)
**User report**: reach still too wide, still able to stagger someone not visibly touched.
Stamina drain too forgiving at both trot and gallop. Stickiness written off as vanilla
tangling and dropped from scope.

**103 logged impacts, analyzed rather than guessed at:**
```
lateral  min=0.00  p50=0.30  p75=0.44  p90=0.51  max=0.55
forward  min=0.06  p50=1.08  p75=1.37  p90=1.56  max=2.05
sweep    min=0.23  p50=0.74  p75=0.95  p90=0.95  max=0.95
```
Two distinct causes, neither of which was obvious without the numbers:

1. **Lateral distances were pressed against the cap.** Median 0.30 but the 90th percentile
   sat at 0.51 against a 0.55 limit, so the limit itself was admitting people half a meter
   clear of the flank.
2. **The forward sweep was the bigger culprit.** **45 of 103 impacts landed beyond the
   1.15 m front reach and were admitted by the sweep alone**, which sat pinned at its 0.95
   cap for over a quarter of samples. Effective reach was therefore past **two meters**
   ahead of the horse for much of the time.

---

### Build: 2.0.0-rc.3
**Changes, all derived from the data above:**
- Half-width 0.55 -> **0.35**, roughly a horse chest.
- Front reach 1.15 -> **1.05**.
- Sweep multiplier 1.30 -> **0.50**, cap 0.95 -> **0.35**. The sweep only needs to cover one
  tick of travel, not the better part of a stride.
- Stamina drain trot 20 -> **45**, gallop 40 -> **75**. Against the measured 210 pool that
  is roughly five bodies at a trot and three at a gallop, down from ten and five.

**Predicted effect**, by replaying the 103 logged impacts through the new footprint:
```
accepted under old footprint: 103/103
accepted under new footprint:  40/103   (39% of before)
effective forward reach at gallop: 2.10 m -> 1.40 m
corridor width:                    1.10 m -> 0.70 m
```
So roughly three in five previously-registered impacts will no longer trigger. If that
overshoots and genuine contacts start being missed, the telemetry is still in place and
half-width is the first value to relax.

**Dropped from scope**: the horse and NPC tangling during a stagger. Nothing attempted
changed it, and it matches vanilla behavior when riding head-on into a walking NPC.
Revisit alongside Phase 2 momentum work, if at all.

---

### Build: 2.0.0-rc.3 (RESULTS)
**User report**: reach now feels right. Two concerns remain: horse collisions are still
exploitable in combat (ride through four enemies, then shoot or swing at them freely while
they are ragdolled), and the rider-throw animation looks wrong.

---

### Build: 2.0.0-rc.4
Two targeted changes rather than the full combat-rules system, which belongs with the
Phase 2 mass and Horsemanship work.

**1. Combat-aware stamina cost.** `player.soul:IsInCombatDanger()` is the same check vanilla
scripts use in a dozen places, and it covers being threatened as well as actively fighting.
While it is true, stamina cost is multiplied by `Config.CombatStaminaMultiplier` (2.5).

```
Trot    out of combat  cost= 45.0  -> 4.7 NPCs before thrown
Trot    in combat      cost=112.5  -> 1.9 NPCs
Gallop  out of combat  cost= 75.0  -> 2.8 NPCs
Gallop  in combat      cost=187.5  -> 1.1 NPCs
```
Riding through a market stays cheap and fun. Charging a group mid-battle spends the horse in
roughly one impact, making it a committed move rather than a repeatable one.

This is deliberately a **multiplier on the existing cost**, not a parallel rule set. Phase 2
will multiply the same value by target mass and armor, so the two compose instead of one
replacing the other.

**2. Rider throw uses the horse's own animation.** `RearAndThrowDown` is registered in the
decompiled binary at line 3242421, next to `HasRider` (3242397) and `IsMountable` (3242409).
The extension carrying it is undocumented, so `ThrowRider` tries the horse entity, then
`horse.human`, then `horse.actor`, logging which one takes, and falls back to the previous
`player.actor:Fall` if none do. The old fallback reads as the player collapsing rather than
being thrown, which is what looked wrong.

**Deferred deliberately**: a full combat rule set (different tiers in combat, no ragdoll for
braced or armored enemies, morale and aggro). It is entangled with mass, armor weight,
Horsemanship and polearm bracing, all of which are Phase 2 and 3. Building it now would mean
building it twice.

---

### Build: 2.0.0-rc.4 (RESULTS)
**User report**: combat multiplier hard to judge; guards bark "Where did he go?" after being
bumped even though the player is standing in front of them; the rider throw is unchanged;
the walk stagger often does not play even though the bark fires.

**Telemetry**:
```
Impact tier=Walk 21    Trot 10    Gallop 2
Stagger calls    21     (every walk impact called it, all ok=true)
ThrowRider       3      all "falling back to player ragdoll"
combatScale      1.0 x32,  2.5 x1
```

**1. The throw never used the horse animation.** `RearAndThrowDown` is on none of the three
candidates tried (horse entity, `horse.human`, `horse.actor`), so every throw fell back to
ragdolling the player. Its registration sits at decompiled line 3242421 next to `HasRider`
and `IsMountable`, which is **before** the `human` cluster starting at 3242472, so it belongs
to some other extension. rc.5 enumerates the horse's actual extensions to find it.

**2. The stagger was requested on all 21 walk impacts and still often did not render.** As
always, `ok=true` proves nothing. The likeliest cause is **victim gender**: the female
animation set has no `AnimationControlled` fragment, so female NPCs accept the call and play
nothing. rc.5 logs gender on every stagger to confirm or rule this out.

**3. The perception bug is caused by this mod.** The stagger hands the victim's body to an
interactive action, which pulls them out of their combat behavior; on return they have lost
the player as a target and bark the "lost him" lines. This is a real regression in combat,
not cosmetic.

**4. The combat multiplier only fired once in 33 impacts**, so it is genuinely untested
rather than ineffective.

---

### Build: 2.0.0-rc.5
- **`Config.SuppressStaggerInCombat`** (default true) skips the stagger animation while the
  player is in a fight, which fixes the perception regression. It also lines up with the
  intended design: knockdowns still apply in combat, but the horse is not a free crowd
  control tool and NPCs do not lose track of the player.
- **Gender logged on every stagger**, to settle whether the misses are the known female
  limitation or something else.
- **Horse extensions enumerated once**, listing any that carry `RearAndThrowDown`, plus
  `player.human` added as a fourth candidate.

**Results**: PENDING.

---

### Build: 2.0.0-rc.5 (RESULTS)
Testing was combat-heavy and hard to control, so the log carried the result rather than
observation.

**The probe found the throw API**: `horse.horse HAS RearAndThrowDown`. A horse entity carries
its own **`horse`** extension, which was not among the candidates tried, so all three throws
still fell back to ragdolling the player. Full extension list on a live horse:
```
inventory actorStats Properties onClient AI this otherClients server
grabParams actor allClients scriptSave soul PropertiesInstance horse
```

**Everything else is working as designed**, confirmed numerically:
- `combatScale=2.5` on **11 of 13** impacts, so combat detection is reliable.
- 5 walk impacts produced only **2** stagger calls; the other 3 were suppressed in combat, so
  `SuppressStaggerInCombat` works.
- Stamina drains match the multiplier exactly: `166.4 -> 53.9` is 112.5, which is trot 45 x
  2.5; `201.4 -> 13.9` is 187.5, which is gallop 75 x 2.5.
- 3 recorded throws, matching the user's report of being thrown after a gallop impact.

The user's observation of surviving 3+ trot impacts before being thrown is also explained:
stamina regenerates between hits, so the naive pool-divided-by-cost figure understates it.
That is realistic and needs no change.

**Still unconfirmed**: whether the missing staggers are the female-NPC limitation. Only two
staggers were logged and both were `gender=1` (male), because combat suppression removed the
rest. Needs an out-of-combat test against a mixed crowd.

---

### Build: 2.0.0-rc.6
- `ThrowRider` now targets **`horseEnt.horse`** first. The one-shot enumeration probe is
  removed now that it has served its purpose.
- `docs/kcd_api.lua` gains a `HorseExtension` class documenting `RearAndThrowDown`,
  `HasRider` and `IsMountable`, with a note that they live on `entity.horse`.

**Results**: PENDING.

---

### Build: 2.0.0-rc.6 (RESULTS)
**User report**: the throw now reads as the horse bucking, which looks natural. Women still
do the one-frame twitch on walk impacts. No more "where did he go" barks.

**Telemetry confirms all three:**
- `ThrowRider via horse.horse ok=true` twice. The rear-and-buck is now the mod's, not the
  guards unhorsing him.
- Staggers by gender: **6 male, 10 female**. The women were the majority of walk impacts and
  every one of them produced the twitch, which **confirms the female limitation** rather than
  leaving it as a theory.
- `combatScale=1.0` across all 35 impacts, so this session was entirely out of combat and
  says nothing about combat balance either way.

---

### Build: 2.0.0-rc.7 - FEMALE NPCs SUPPORTED
The female limitation is fixed rather than documented around.

`wh_female_database.adb` already contains the same
`hitreaction_idle_medium_torso_stab_{front,back,left,right}` clips. The only thing missing was
the fragment itself, so `build_adb.py` now patches two more files:

- **`wh_female_fragmentids.xml`** - declares `AnimationControlled`, pointing at the same
  `kcd_animationControlledTags.xml` subTagDef the men use. Tag definitions are shareable.
- **`wh_female_database.adb`** - adds a whole new `<AnimationControlled>` fragment block
  containing the four `hcm_stagger_*` options.

The build now ships four data files and fails if any of them is missing from the staged pak.

**Compatibility cost increases**: the mod now replaces both human animation databases, so it
conflicts with any mod editing male *or* female animations. Documented in the README and the
module header.

**Results**: PENDING. The test is simply whether women stagger properly instead of twitching.

---

### Correction to the 2.0.0-rc.6 write-up
That entry claimed the rc.6 session was "entirely out of combat" on the basis of
`combatScale=1.0` across all 35 impacts. **That was an over-claim.** `combatScale=1.0` proves
only that `IsInCombatDanger()` returned false, not that the player was out of combat, and the
user reports they were definitely fighting guards at the time. This is the same
unverified-signal mistake this project has made repeatedly.

The check is not broken outright: it returned true for 1 impact in one earlier session and 11
in another. So it works, and read false throughout a session the player describes as combat.
The likely explanation is that `IsInCombatDanger` reflects *immediate danger* rather than
"a fight is in progress", and a mounted player moving at speed may not be in danger at the
instant of each impact. KCD's own log carries no independent combat marker, so this cannot be
settled from the log alone.

---

### Build: 2.0.0-rc.8
- **Second combat signal added.** A collision now counts as combat if
  `player.soul:IsInCombatDanger()` is true **or** the victim has a weapon drawn
  (`human:IsWeaponDrawn()`). Townsfolk do not walk around armed, so the second signal catches
  exactly the case the first misses: charging someone who is actively fighting.
- **Both raw values are logged**, along with whether each call succeeded:
  `combatScale=2.5 danger=false/true armed=true/true`. A disagreement between the two signals
  is now visible instead of being hidden behind one boolean, and a failed call is
  distinguishable from a false result.

**Results**: PENDING.

---

### Build: 2.0.0-rc.8 (RESULTS) - ALL CHECKS PASS
**User report**: staggers fire correctly on both women and men. Galloping into four people
resulted in being thrown, with the horse bucking. In combat, no staggers and no "where is he"
barks. Ragdolled one guard while being chased by three, then was thrown by the mod's own
logic rather than being unhorsed. Judged natural and not exploitable without practice.

**Telemetry agrees with every part of that:**
```
impacts            Walk 14   Trot 12   Gallop 5
combat detection   1.0 x21   2.5 x10   (danger=true on all 10, armed=true on 8)
staggers           male 8    female 4
throws             6, all "ThrowRider via horse.horse ok=true"
errors             0         all 18 pcalls ok=true
```

**Internal consistency checks:**
- 14 walk impacts, 2 of them in combat, **12 staggers played**. Suppression is exact.
- **Female staggers now play** (4 logged, no twitching reported), so the rc.7 female data fix
  works.
- **Every throw used `horse.horse`**, no fallbacks to the player ragdoll.
- Combat detection fired on 10 of 31 impacts with both calls succeeding. `IsInCombatDanger`
  read true for all 10, so it does work; the rc.6 session where it read false throughout
  remains unexplained but is not reproducible here. The weapon-drawn signal corroborated 8 of
  the 10 rather than rescuing any, which is the healthy outcome.

---

## Release: v2.0.0

Phase 1 complete. The walk-speed non-ragdoll reaction, open since build 1.4.0, is solved.

**What ships:**
- Three gait tiers matched to measured speed plateaus.
- Walk: native standing stagger, directional, on male and female NPCs, suppressed in combat.
- Trot and gallop: physics knockdown at scaled impulse.
- Horse stamina drain with a 2.5x multiplier in combat, and the horse's own rear-and-buck
  animation when the rider is spent.
- Footprint detection tuned from 103 logged impacts rather than guessed dimensions.

**Known untested territory**, stated plainly rather than implied: quest scripts, scripted
encounters, and cutscene-adjacent NPCs have not been exercised at all. The mod does not touch
AI behavior trees or quest logic, which limits the blast radius, but replacing both human
animation databases is not a small footprint.

**Deferred to Phase 2 and beyond**: mass and armor scaling, Horsemanship, polearm bracing,
morale, and the horse-NPC tangling when walking head-on into someone.

---

## Build 2.0.1-dev.1: carried items dropped during the stagger

**Reported after 2.0.0 shipped**: a woman carrying a basket staggered, left the basket on
the ground, and walked off without it.

### The UseHand hypothesis was wrong

The note written when this was first observed guessed that the cause was the `UseHand`
procedural layer, which the stagger template dropped when it was modeled on vanilla's
`cabinet_o` option. Reading the data says otherwise.

`UseHand` appears in seven fragments in `kcd_male_database.adb` and nowhere else:
`LedgeGrab`, `Door`, `Door_Locked`, `Door_LockUnlock`, `Door_CloseLock`, `Door_UnlockOpen`
and `AnimationControlled`. Every one is an animation where the character needs their hands
for something. No hit reaction declares it. So the layer means "this animation requires the
hands", which is a reason for the engine to empty them, not to preserve what they hold.
Adding it back would have been more likely to cause the drop than to fix it.

### Two other candidates ruled out

**The `hitReaction` message is not responsible.** `sb_switch_hitreactions.xml` does contain
a path that matches the symptom exactly: on entering the `Hit` state it runs the `dropItems`
tree from `sb_combat.xml`, which places every non-weapon held item on the ground, links it
to the NPC with the tag `panicDrop` so a later activity can retrieve it, and then posts
`daycycle:restartRequest` so the NPC abandons what they were doing. That whole block is
gated behind the `Hit` state machine state. The `HitReactionType.Collision` branch this mod
posts into only fires barks and an awareness impulse and never touches the state machine.

Worth recording for later anyway: the gate is `!$b_context['suppressDaycycleRestartAfterHit']`,
so there is a sanctioned context flag for turning that behavior off if a future build ever
does put an NPC into the `Hit` state.

**Scope displacement is not responsible.** Carrying is expressed as an override on
`MotionMovement`, for example `tags="walk+r_basket"` with
`scopes="FullBody+HoldItemLeft+HoldItemRight+HoldItem+Looking"`. The hold itself lives in
the `HoldItemLeft` and `HoldItemRight` scopes, which are separate `AutoReinstall` fragments.
`AnimationControlled` claims `FullBody+HoldItem+Looking` and never touches either.

### What the template should have been modeled on

`hitreaction_idle_medium_torso_stab_front` is not an orphan clip. It is an option on the
vanilla `HitDeath` fragment under FragTags `so_forward+minor_hit`, which is where
`GetImpactDir`'s `so_` prefix came from in the first place. That option is the correct model
for ours, and it is much barer than `cabinet_o`:

| Layer | vanilla `HitDeath` | 2.0.0 `AnimationControlled` |
| --- | --- | --- |
| AnimLayer | the clip | the clip |
| `AnimateCamera` | yes | no |
| `MovementControlMethod` | no | yes |
| `ColliderMode` | no | `Disabled` |

`ColliderMode="Disabled"` is the change under suspicion. Vanilla never disables an actor's
colliders during a hit reaction, and a carried basket is a physicalized entity attached to
the hand. It was added in the first place to stop the horse snagging on a victim who is
mid-stagger, and this diary already records that it did not achieve that, so reverting it
costs nothing that was working.

`MovementControlMethod` is kept. An interactive action needs the animation to drive the body
in a way a natively triggered hit reaction does not. The camera layer stays out because it
aims the player's camera and the victim here is never the player.

### The change

`COLLIDER_MODE` in `build_adb.py` now accepts `None`, meaning declare no `ColliderMode`
layer at all, and that is the new default. Setting it to `"Disabled"` or `"Interactive"`
still works and should now require an in-game result to justify.

**Hypothesis**: with no `ColliderMode` layer the victim stays physically as they are for the
duration of the stagger, and whatever they are carrying stays in their hands.

**To test**: find a woman carrying a basket, walk a horse into her, and watch the basket.
Also worth confirming the stagger still plays and reads the same otherwise, since this
touches the fragment every stagger uses.

**If the basket still drops**, the remaining suspect is `StartInteractiveActionByName`
itself interrupting the smart object activity that owns the item, in which case the place to
look is the `panicDrop` recovery paths in `so_slot.xml` and `so_tool.xml` and whether the
action can be started without cancelling the activity.

### Result

**Tested in game.** The basket stays in her hands through the stagger. Removing the
`ColliderMode` layer was the fix, and the `UseHand` hypothesis recorded earlier would have
been the wrong change.

Two qualifications, both from the same test:

**It looks slightly glitchy.** The clip is a hit reaction authored for someone with empty
hands, so the arms swing through a pose the basket was never meant to follow. The item is
kept rather than lost, which is the behavior that matters, but it does not read as natural.
Fixing that properly means either a carried-item variant of the reaction or declaring the
carry tag on the fragment, and neither is worth doing before the tooling makes iteration
cheap.

**The drop still happens at trot and gallop.** Those tiers use the physics ragdoll, not this
fragment, so they were never covered by this change and the behavior predates 2.0.0. That is
a separate issue against the ragdoll path and should not be folded into this one.

---

## Session: development loop tooling

No build under test. The whole session went into the loop used to test builds,
which had become the slowest part of the project: close the game, remove the
old mod in Vortex, install the new archive, deploy, launch, clear a prompt,
wait for the main menu, load a save. Every iteration.

Two tools came out of it, `dev_deploy.ps1` and `dev_console.py`, and both
halves of the mod now reload into a running game. `docs/DEV_LOOP.md` is the
reference; this entry records what had to be discovered to get there.

### The remote console

CryEngine embeds a console server on port 4600, enabled with
`log_EnableRemoteConsole = 1`. Three things about it cost time:

- The event type is written as an **ASCII digit**, `'0' + type`, not a raw
  byte. The server's opening `b"1\x00"` is type 1, not 49.
- The exchange is **server-driven and strictly alternating**. The server sends
  one packet and waits. A client that answers only explicit requests gets one
  packet and then silence. Answer every packet.
- `log_Verbosity` resets with the game, so a session started after a restart is
  silent until it is raised again. That reads exactly like commands vanishing.

### Dev mode is a command line switch

`sys_DevMode` is **not a CVar in this build**; querying it answers "Unknown
command", so the `sys_DevMode = 1` line that used to sit in `system.cfg` never
did anything. Dev mode comes from `-devmode` on the command line. Without it
the console refuses everything marked `VF_CHEAT`, which includes
`lua_reload_script`.

### Loose files go under Data

`sys_game_folder` is `Data`, so the engine's file system is rooted at
`<game>\Data`. A loose script belongs at `Data\Scripts\Startup\`. One level
higher is never found, and **the failure is silent**: "Loading and executing
script file" is logged *before* the read is attempted, and a miss logs nothing
at all. That reads exactly like a script that loaded and did nothing.

Loose files also require `sys_PakPriority = 0`. It ships as 2, pak-only, under
which loose files are ignored entirely and a reload re-reads the same packed
bytes. It is flagged `REQUIRE_APP_RESTART`.

### Animation data reloads too - **WORKING**

`mn_reload` had appeared to be a no-op for as long as it had been tried. It
needed two fixes together, which is why it looked like an engine limitation:

1. The ADB files existed only inside the pak, so the reload re-read the same
   packed bytes. They now deploy loose to `Data\Animations\Mannequin\ADB`.
2. **`mn_allowEditableDatabasesInPureGame` ships at 0.** A shipping build
   treats its Mannequin databases as read only, so the reload ran and was never
   permitted to replace anything. It is now set in `system.cfg` and sent again
   before every `mn_reload`.

Either alone does nothing. Confirmed in game by pointing the male stagger
fragments at `ringing_alarm_bell` and watching NPCs ring an invisible bell,
then reverting, without the game ever restarting. A combined test changing the
Lua (`Knockback` 50 to 2000) and the animation data in one pass also worked.

Note for future tests: `ringing_alarm_bell` and `library_cabinet_open` exist
only in the male database, which is why the stagger work used hit reactions.
A female-visible test needs a clip present in `wh_female_database.adb`.

### Reloading has to restart the detection loop

Re-executing the script is not enough. The loop is started only by the UI
listener when a loading screen ends, because a Startup script has no "game
loaded" hook. A reload rebuilds the table with `TimerTick` unset, the running
loop sees its generation no longer match and stops, and nothing starts a new
one. The mod goes silent and the game looks completely vanilla until a save is
loaded. `--reload` therefore calls the entry point directly afterwards.

That exposed a second bug. The generation counter lived on the table that
`lua_reload_script` rebuilds, so it restarted at 1 on every reload while the
loop still running was also generation 1: its guard matched and it kept going.
The counter now lives in a global that a reload does not rebuild. The
generation in the log line is now a real signal that a reload took.

### The gallop "regression" that was not one

**User report**: after turning `ProtectMutt` off, gallop appeared to stop
ragdolling.

**Not reproducible as described, and the telemetry explains it.** Across the
session: Gallop 17 impacts at 8.84-10.75 m/s, Trot 27 at 4.51-8.03, Walk 14 at
2.38-3.96. Gallop fired throughout, including nine times after the reload.

The stretch that prompted the report is eleven consecutive non-gallop impacts
where the horse never exceeded **8.03 m/s** against a `SpeedGallop` threshold
of **8.5**. The horse was trotting. Stamina was not the limiter either: it read
210.0, 190.7, 190.5 and 182.5 during that run, at or near a full pool.

`ProtectMutt` is one isolated line and cannot affect the gallop path.

**Worth revisiting as tuning**: trot impacts cluster at 6.5-7.0 and top out at
8.03; gallop starts at 8.84. Almost nothing lands between, so the boundary is a
visible cliff in reaction strength right where the horse spends much of its
time.

### Measurement errors worth not repeating

Three conclusions in this session were drawn from signals that had never been
verified, and all three were wrong:

- **"194 ticks in 10 s proves two loops running."** It assumed
  `Script.SetTimer(100, ...)` yields 10 ticks a second. It fires roughly every
  54 ms in this build. Tracing the generation directly showed one loop. The
  duplicate-loop race is real in the code but was not occurring.
- **"26 FPS, the game is starved."** `System.GetFrameTime()` was sampled while
  the game sat unfocused and windowed, where it is throttled. The user's own
  counter reads 50+ in Rattay. The reading was meaningless as a proxy for play.
- **Three separate causes proposed for the audio bug**, all wrong, when the
  answer was already written in this file (see below).

The pattern: prove the signal itself works before drawing a conclusion from it.

### Audio: already answered, in this file

**Re-diagnosed from scratch and got it wrong three times** before finding the
existing entry from build 2.1.0-dev5. The cause is Warhorse's PROS online
service failing to reach its backend and retrying on the main thread every half
second, which stalls the audio buffer. `kcd.log` shows the pair every 0.5 s
with no gap:

```
ERROR: operation 'Do connect' takes too much time. Duration 0.500069 sec
PROS: disconnected on server side. Trying to reconnect.
```

It is **intermittent**, which is what made it look new each time: whether the
retry loop engages depends on what the backend does on that launch. Some
launches are clean with nothing changed. That is a reason to search the record
harder, not a reason to assume the symptom is new.

Nothing in the mod is involved. Blocking the game outbound in the firewall
stops it.

### Environment findings

- **`Bin\Win64\user.cfg` was never being read.** It held performance tuning
  that therefore never applied, plus a dead `hcm_*` CVar block left over from
  1.x: the mod reads none of those and the build registers no `hcm_` CVars at
  all. Consolidated into the single `user.cfg` beside `system.cfg`.
- `r_TexturesStreamPoolSize` reads 4096 regardless of either file, so **KCD's
  own graphics profile overrides `user.cfg`** for it.
- The manifest declared `1.*`. The game matches `<kcd_version>` against
  `wh_sys_version` and **disables the mod when nothing matches**, so that
  claimed compatibility the mod cannot honor: it ships whole animation
  databases generated from 1.9.7. Now pinned to `1.9.7`, which fails safe.
- Carried items are still dropped at trot and gallop, on the physics ragdoll
  path. Separate from the walk-tier stagger fix and predates 2.0.0.
- During this session a woman **kept her bucket** while running the *un-fixed*
  animation data, which does not fit the `ColliderMode="Disabled"` explanation
  recorded for the carried-item drop. Worth re-testing before that fix merges.
- `sys_PakPriority = 0` and `mn_allowEditableDatabasesInPureGame = 1` are
  development settings now live in `system.cfg`. Set `sys_PakPriority` back to
  2 for normal play.

### Repository layout

Not a build test. Recorded because it changes where everything lives and how
the scripts find each other.

Eleven tracked files sat at the repository root, of which four were scripts and
two were the mod itself. Nothing distinguished the mod from the tooling that
builds it. The layout is now:

```
build.ps1                 the one build entry point
src/    HorseCollisionMod.lua, mod.manifest
tools/  build_adb.py, dev_deploy.ps1, dev_console.py
docs/
```

**Every script now resolves paths from the repository root rather than the
working directory.** That was the real work; moving the files was the easy
part. `build.ps1` derives its root from `$PSCommandPath`, `dev_deploy.ps1`
takes one level up from its own location since it lives in `tools/`, and
`build_adb.py` uses `os.path.dirname` twice on `__file__`.

Before this, `build_adb.py` wrote `mod_assets/` relative to whatever directory
it was invoked from. Running it from `C:\` created `C:\mod_assets` and reported
success, which is the kind of quiet wrong behavior that is hard to notice.
Verified afterwards by running both `build.ps1` and `tools/build_adb.py` from
`C:\`: output lands in the repository, and no stray directory is created.

Two traps found while rewiring:

- **LuaJIT's syntax check needs forward slashes.** `build.ps1` hands the script
  path to `loadfile` inside a single-quoted Lua string, and Lua treats a
  backslash there as an escape. The path is converted with
  `.Replace([char]92, [char]47)`.
- **`git status --porcelain` prints a rename as `old -> new`.** Anything
  matching paths against that output has to reduce it to the destination first
  or the match silently fails while a rename is staged.

The build artifact is unchanged: same three files in the zip, same five entries
in the pak, same sizes.

### Config readability, and the LDoc situation

**User report**: the tuning table is hard to read. "I couldn't find the
ProtectMutt setting for almost a minute because it was hard to read."

Fair, and worse than it sounds. The table was **71 lines holding 24 settings**,
with multi-paragraph rationale interleaved between fields. `ProtectMutt = true`
sat alone between a six-line comment and a five-line comment, with nothing
grouping it.

The rationale was also triple-documented: once in the `@field` block above the
table, once inline, and once in the README settings table. One of those three
copies was actively obstructing the thing people open the file to edit.

The table is now 37 lines, grouped by what each setting affects, one aligned
line per setting, with a short header per group. All 24 settings and every
value verified unchanged by diffing the parsed assignments against the previous
commit. The reasoning moved to `TECHNICAL_DETAILS.md` under "Tuning rationale",
where the telemetry that produced the numbers can be read as prose.

The principle worth keeping: a config table is a control surface, not a
document. Explain elsewhere.

### The LDoc comments are correct

Checked rather than assumed, by parsing the file and comparing documentation
against code:

- 13 documented functions, **every `@tparam` name and count matching the actual
  signature**, in order.
- 4 documented tables, every `@field` present in the table and every table field
  documented. No phantom fields, no undocumented ones.
- Tags in use are all standard: `@module`, `@author`, `@release`, `@table`,
  `@field`, `@tparam`, `@treturn`.

An earlier version of that check reported six functions "returning a value with
no `@treturn`". False positives: the pattern used `\s+` where it needed
`[ \t]+`, so it matched across a newline and flagged bare `return` guards. All
six confirmed to have no value-returning statement.

### docs/api is not generated by LDoc

Worth stating plainly because it looked like it was. `docs/generate_api_docs.py`
is a 295-line custom Python renderer that reads LDoc tags and emits its own
HTML. Its docstring claimed `ldoc HorseCollisionMod.lua` "produces the same
content", which overstates it: the script implements only the tags this project
uses and its markup is its own.

**Real LDoc cannot currently be installed on this machine.** It depends on
penlight, which depends on luafilesystem, which is a C module. `luarocks
install ldoc` gets as far as compiling `lfs.c` and fails, because there is no C
compiler on the box at all. The route is `choco install mingw` first.

What was done instead: `config.ld` added at the repository root so the project
is properly configured for LDoc and `ldoc .` works for anyone who has it; the
Python script's docstring rewritten to say what it actually is; and the README
given an "API documentation" section stating which is canonical.

Also fixed there: the repository reorganization had broken the generator, which
still pointed at `HorseCollisionMod.lua` at the root. It now resolves from the
repository root like the other scripts, and was verified from an unrelated
working directory.

### Real LDoc, installed

`docs/api/` is now generated by LDoc itself rather than by a bespoke renderer.

The blocker was that LDoc depends on penlight, which depends on luafilesystem,
which is a C module, and this machine had no C compiler at all: no gcc, no
clang, no MSVC build tools. Chocolatey was present but the shell was not
elevated, and `choco install mingw` writes under `C:\ProgramData`.

`winget` turned out to be the way, since WinLibs installs a full mingw-w64
toolchain into the user profile with no elevation:

```
winget install BrechtSanders.WinLibs.POSIX.UCRT --scope user
luarocks install ldoc
```

The compiler is only needed to build luafilesystem during that install. `ldoc`
lands in the luarocks bin directory, which is already on PATH, and `ldoc .`
runs afterwards in a clean shell with no mingw on PATH. Verified.

`config.ld` at the repository root configures the project. The output is
30,920 bytes plus `ldoc.css`, against 22,207 for the Python renderer, and
carries every documented function and table.

`docs/generate_api_docs.py` is removed. It was 295 lines reimplementing a
standard tool, its output was not what LDoc produces despite a docstring
claiming otherwise, and its existence was the reason the documentation setup
was unclear in the first place.

## Session: publishing to Nexus Mods from the IDE

Not a build test. Recorded because it settles how releases get published and
rules out an approach that looks obviously correct from the outside.

### The GitHub Action cannot work for this mod

Nexus Mods ship `Nexus-Mods/upload-action` and a sample repository,
`Nexus-Mods/API-Example`, whose workflow checks out the repository, zips
`src/`, and uploads the result. That shape is a good fit for a source-only mod
and a bad fit for this one.

`build.ps1` calls `tools/build_adb.py`, which reads
`Data/Animations-part1.pak` out of a local game install to generate
`mod_assets/`. `mod_assets/` is gitignored, so a fresh clone has nothing to
package. A GitHub-hosted runner has no game install, and shipping Warhorse's
paks to CI is both a licensing problem and a gigabyte-scale one.

The workaround would be to build locally, attach the zip to a GitHub release,
and have a workflow feed that artifact to the action. That still builds by
hand, and adds a round trip through GitHub in order to run six HTTP calls. The
only thing it buys is keeping the API key in GitHub secrets rather than in a
shell variable.

So: publish locally, from `tools/publish_nexus.ps1`. Revisit the action only if
the additive/patch ADB deployment on the roadmap ever lands, since a repository
that commits a small delta instead of regenerating whole databases would be
buildable anywhere.

Worth noting the action itself adds nothing over the API. Its inputs map
one-for-one onto the v3 request bodies, `display_name` to `name`,
`category` to `file_category`, `archive_existing_version` to
`archive_existing_file`, and it runs the same six calls the script does.

### The site's file_id is not the API's file id

The number in `?tab=files&file_id=10219` names a mod file **version**, but an
upload is claimed by the mod **file** that owns the version. The spec draws
this distinction explicitly: a `ModFile` is "the persistent, updatable file on
a mod page", and its `ModFileVersion`s are the individual uploads.

Both site identifiers resolve in one call each:

```
GET /games/kingdomcomedeliverance/mods/2338              -> data.id
GET /games/kingdomcomedeliverance/mod-file-versions/10219 -> data.file.id
```

The script resolves them at runtime rather than caching them, then calls
`GET /mods/{id}/files` to confirm the mod file actually belongs to that mod. A
wrong identifier would otherwise publish onto someone else's page quietly.

### Python and .NET disagree about the release zip's entry names

Found while writing the zip validation, and worth recording because it produced
a confident wrong answer in both directions.

`Compress-Archive` stores Windows path separators, so the release zip really
contains `Data\HorseCollisionMod.pak` with a backslash. Confirmed by reading
the raw central directory bytes.

**Python's `zipfile` normalizes those to forward slashes on read. .NET's
`ZipArchiveEntry.FullName` reports them as stored.** So the same file listed
through Python and through PowerShell gives different names, and a check
written against one library fails against the other. The validation normalizes
separators before comparing.

This is the same `Compress-Archive` behavior that `build.ps1` already documents
for the pak, where it matters much more: CryEngine looks pak entries up by
exact path with forward slashes, so a backslash pak silently overrides nothing.
The pak is therefore built entry by entry. The outer release zip is unpacked by
Vortex or by hand rather than looked up by path, so backslashes there are
harmless and no change was made to how it is built.

### Guards on the publish path

Everything below runs before any network call, because a wrong release reaching
a live mod page is slower to undo than to prevent:

- The version string is checked against the API's own `^[a-zA-Z0-9.-]+$` and
  50 character limit, so a typo fails immediately rather than after the upload.
- The zip must contain `mod.manifest` and `Data/HorseCollisionMod.pak`.
- **The `<version>` inside the zip's `mod.manifest` must match the version
  being published.** `build.ps1` copies `src/mod.manifest` verbatim, so its
  version is maintained by hand and can drift from the `-Version` the zip was
  built with. The manifest is what the game reads.
- A version string containing `dev`, `alpha`, `beta` or `rc` is refused.
- `GET /mod-files/{id}/versions` is checked for the version already existing.
- The run prints what it is about to do and requires the version typed back.

`-Force` skips these. `-DryRun` stops after validation and resolution.

Two operational details from the spec that are easy to get wrong: the presigned
`PUT` must carry `Content-Disposition: attachment; filename="..."` matching the
filename sent to `POST /uploads`, because the filename is part of the URL's
signature; and the upload is processed asynchronously, so `GET /uploads/{id}`
has to report `available` before the version can be created. If a run fails
after the upload succeeded it prints the upload id, and `-ResumeUploadId` picks
up from there without sending the file again.

### Not covered by the API

There is no endpoint to create a mod page, and none to edit a mod's
description. `PATCH` exists for collections, not for mods. The Nexus page copy
is still pasted in by hand on each release, which is what the local description
file is for.

`createModFile` and `createModFileVersion` are both marked **Experimental** in
the spec, meaning they can change or be removed without the 90-day deprecation
window the stable endpoints get. Worth re-reading the spec if a release ever
fails for no apparent reason.

### Acceptable use policy, and what it changed

Checked against
https://help.nexusmods.com/article/114-api-acceptable-use-policy after the
first working dry run. Two things were wrong and one was worth writing down.

**Missing required headers.** The policy requires every request to carry
`Application-Name` and `Application-Version`, and explicitly forbids "sending
request metadata which is either blank or impersonates another application".
The script sent neither. Now sends `HorseCollisionMod-publish` and a version
that moves independently of the mod's, since the policy asks that the name stay
constant across releases of the tool.

Worth noting the v3 spec is misleading here: `Application-Name` appears in it
exactly once, as an *optional* header on `downloadRepackedModFileVersion`. The
policy governs, not the spec.

**The poll loop was the one place this script could be a bad citizen.** It sat
at a fixed two second interval for up to sixty attempts. Now backs off from one
second to five, reaching about three minutes of waiting in 40 requests rather
than 90. Nexus do not publish a specific quota in the policy, only that
excessive consumption may be rate limited, so the fix is to not need a number.

**Personal key use is within policy, and would stop being so if this were
generalized.** Nexus permit personal API keys for testing and personal use.
This qualifies: one author publishing to one mod page, the key read from the
environment at the moment of use, stored by nothing, never used without the
author starting the run. The policy's prohibition on "storing user API keys on
your own server and/or using them without the action being initiated by the
user" is the one to stay on the right side of, and a local script that reads an
environment variable does.

If this ever became a tool other modders point at their own pages, that is a
public-facing application, and the policy requires registering with Nexus Mods
at support@nexusmods.com with a testing build before release rather than
shipping on personal keys. Relevant because generalizing the dev tooling for
other modders has come up before.

### Error output

A first working dry run ended on the duplicate-version check, which was correct,
but PowerShell rendered the `throw` as a full error record: source extent,
squiggly underline, `CategoryInfo`, `FullyQualifiedErrorId`, with the actual
sentence split across the noise. Unreadable for something a person runs by hand.

A script-scope `trap` now prints the message and exits, so every guard reports
as one line. The already-published case is not really a failure and got its own
yellow message and exit code 2, so a wrapper can tell "already there" from
"went wrong".

### Confirmed working

First live run against the real mod page, dry run only, no writes:

```
mod:      Horse Collision Mod [9869834848546]
mod file: HorseCollisionMod [7863762]
versions: 1 (0 archived)
Version 2.0.0 is already on the page, uploaded 2026-08-26T05:08:54.000+00:00.
```

All four lookups resolve, including the mod-file-version to mod-file hop, and
the duplicate check reads live data. The upload, finalise and publish calls
remain untested until a real release.

### Storing the API key

`$env:NEXUS_API_KEY` per session worked but meant retyping the key, and the
obvious alternatives are all worse than they look. `setx` writes it to the
registry as plaintext. A gitignored dotfile is plaintext on disk and one
`git add -f` from leaking. Passing `-ApiKey` puts it in shell history.

`Export-Clixml` on a `SecureString` encrypts with DPAPI under the current
Windows account, needs no dependencies, and produces a file that other users on
the machine cannot read and that is useless if copied elsewhere. It is stored
at `%LOCALAPPDATA%\HorseCollisionMod\nexus.cred`, outside the repository, so no
amount of carelessness with `git add` can commit it.

Set with `-SaveApiKey`, removed with `-ForgetApiKey`. Resolution order is the
`-ApiKey` parameter, then the environment variable, then the stored file, so a
single session can override without disturbing what is saved.

The honest limit: DPAPI does not defend against code already running as this
user, which decrypts it exactly as the script does. It defends against the ways
a key actually leaks in practice, which are a synced folder, a backup, a shared
machine and an accidental commit.

Verified by round-tripping a dummy value: stored, decrypted, sent, and rejected
by the API with a 401, which proves the key reached the request rather than the
call failing earlier for some other reason. Removing the file falls back to the
message telling you how to store one.

### When this runs

Release step only, run by hand on a tagged version. Not wired to a push, a
merge, or a schedule, which is also what keeps a personal API key inside the
acceptable use policy: the action is initiated by the author every time.

---

## Build 2.0.1-dev.14: the branch, rebased onto the new layout

`fix/carried-item-drop` was cut before the repository reorganization, so it
edited `HorseCollisionMod.lua`, `build_adb.py` and `mod.manifest` at the old
root paths. Merging main in resolved all three by rename detection with no
manual intervention; only the diary conflicted, both sides having appended.

Rebuilt from scratch with `mod_assets/` deleted first, and the generated data
verified rather than assumed: all four `hcm_stagger_*` options carry
`MovementControlMethod` and no `ColliderMode` layer, and the 32 vanilla
`AnimationControlled` options are untouched.

### The stated rationale for the fix is partly wrong

Worth correcting before testing, because the reasoning is what the next
decision rests on.

The commit removing the layer justified it this way: "the clips these options
play live on the HitDeath fragment in the stock database, and neither of the
two options there declares a ColliderMode layer."

Checked against the vanilla male database. **`HitDeath` has 105 options, not
two**, and `so_forward+minor_hit` appears four separate times with
*different* collider handling: some declare `ColliderMode`, some do not.

The narrow claim survives. The specific fragment that owns
`hitreaction_idle_medium_torso_stab_front`, the clip actually used, declares no
`ColliderMode`. So removing the layer does match the option the clip comes
from.

The broad claim does not. "Matching vanilla" is not one thing here, because
vanilla ships both variants of the same FragTags. Removing the layer is a
defensible choice, not an obviously correct restoration.

**This matters for the open question.** The recorded cause, that
`ColliderMode="Disabled"` makes NPCs drop carried items, was already
contradicted once: a woman kept her bucket during a session running the
un-fixed data. Now it is also clear vanilla itself is inconsistent about the
layer. Two possibilities the test has to separate:

- Removing the layer fixes the drop, and the woman who kept her bucket was
  something else, most likely a different item or a different reaction option.
- The layer was never the cause, the fix is cosmetic, and the drop has another
  source. In that case the change is still worth keeping for matching the
  source option, but it does not close the issue.

The A/B is cheap now that animation data hot-reloads: build both variants by
flipping `COLLIDER_MODE` in `tools/build_adb.py`, deploy with `-AnimOnly`, and
reload without leaving the game. That was not possible when the original
conclusion was recorded, which is probably why it was drawn from one
observation.

### Not yet tested in game

Everything above is static verification of the generated data. No build test
has run.

### The deploy tool could not build, and nothing caught it

Reported on trying to start a test session:

```
-File : The term '-File' is not recognized as the name of a cmdlet
```

`dev_deploy.ps1` invoked the build across two lines, and the first ended with
**two** backticks instead of one. PowerShell reads the first as escaping the
second, so the line yielded a literal backtick and no continuation, and
`-File ...` on the next line was parsed as its own command.

Two things are worth keeping from this.

**The untested path was the one everyone uses.** `-NoBuild`, `-ScriptOnly` and
`-AnimOnly` all skip that block. Those were the only three exercised after the
repository reorganization, so the default path and `-Launch`, which is how a
test session actually starts, were both broken for the whole interval. A parse
check does not catch it either: the result is syntactically valid, just wrong.
The only thing that would have caught it is running the tool the way it is
normally run.

**The cause was a scripted edit mangling an escape.** The same class of damage
put a literal backspace character into the README, where `.\build.ps1` had
rendered as `.uild.ps1`, because a `\b` in a generated string was interpreted
as an escape rather than a path separator. Both came from writing file content
through a shell heredoc.

A sweep of every tracked text file for control characters in the
`\x00-\x08\x0B\x0C\x0E-\x1F` range found no others. Worth repeating that sweep
after any bulk scripted edit, since the corruption is invisible in an editor
and survives review.

---

## Build 2.0.1-dev.14: the ColliderMode A/B, and a wrong conclusion corrected

First controlled test of the carried-item question, using the animation
hot-reload to run both variants against the same NPCs in one session.

**Hypothesis under test**: removing the `ColliderMode` layer is what stops NPCs
dropping carried items during the walk-tier stagger.

**User reported**: "During the initial and after the hotswap the bucket
remained in their hand for women and the animation played normally for men."

**Result: the hypothesis is wrong, and so was the conclusion recorded for
2.0.1-dev.1.** The bucket stays in hand *both* with `COLLIDER_MODE = None` and
with `COLLIDER_MODE = "Disabled"`. The layer makes no difference to whether the
item is held.

### Why the earlier conclusion was wrong

The 2.0.1-dev.1 entry states plainly: "The basket stays in her hands through
the stagger. Removing the `ColliderMode` layer was the fix." That was drawn
from a single observation with no control. The un-fixed variant was never run
against the same NPC, so there was nothing to attribute the result to.

The contradiction was already on the record. A later session noted a woman
keeping her bucket while running the *un-fixed* data, which the recorded cause
could not account for. That should have been treated as falsifying evidence at
the time rather than as an anomaly to re-test later.

The general lesson, and it has now cost two sessions: **a change plus a good
outcome is not a cause.** Where an A/B is possible, run it. It is possible
here, and cheap, precisely because of the hot-reload work.

### What this means for the branch

`COLLIDER_MODE = None` stays, but on much narrower grounds than the commit
claimed. It is not a bug fix. It matches the vanilla `HitDeath` option that
owns the clip, which is a reasonable default, and it is not observably worse.
It does not fix anything, because on current evidence nothing was broken.

The carried-item drop at trot and gallop is untouched by any of this. That is
the physics ragdoll path and predates 2.0.0.

### The real remaining issue is that the stagger ignores the item

**User reported**: "it looks a little unnatural because the animation that we
are forcing doesn't take into account the bucket in their hand."

Which is correct and was already recorded in dev-1: the clip is authored for
empty hands, so the arms swing through a pose the item was never meant to
follow. Keeping the item is not the same as the item looking right.

### The goal now stated

Rather than the item staying glued through a pose that does not fit it, the
target behavior is: the stagger plays, the item is dropped naturally, the NPC
does their reaction and bark, and then picks the item back up and resumes the
behavior loop it was in.

**There is vanilla precedent, and this diary already found it.** From the
dev-1 entry: `sb_switch_hitreactions.xml`, on entering the `Hit` state, runs
the `dropItems` tree from `sb_combat.xml`, which places every non-weapon held
item on the ground, **links it to the NPC with the tag `panicDrop` so a later
activity can retrieve it**, and posts `daycycle:restartRequest`.

That is precisely drop, then retrieve. It was ruled out as the *cause* of the
old symptom, correctly, because the branch is gated behind the `Hit` state and
the `HitReactionType.Collision` path this mod posts into never touches the
state machine. Being ruled out as a cause is not the same as being unavailable
as a mechanism.

Also already noted there: the restart is gated on
`!$b_context['suppressDaycycleRestartAfterHit']`, so there is a sanctioned flag
for suppressing the abandon-what-you-were-doing half while keeping the drop.
That matters, because the goal is to resume the behavior loop, not restart the
day cycle.

Open questions, in order:

1. Can the `dropItems` tree be invoked without putting the NPC into the full
   `Hit` state, which would bring combat behavior with it?
2. Does the `panicDrop` retrieval actually run for a non-combat NPC, and what
   drives it? The places to look are the `panicDrop` recovery paths in
   `so_slot.xml` and `so_tool.xml`.
3. Does the pickup return them to their previous activity or restart it?

### Vanilla does have drop-and-pick-back-up, and it is complete

Read out of `Scripts.pak` rather than inferred. The answer to "is there
precedent for a woman dropping her bucket and picking it back up" is yes, and
the whole loop already exists.

**The drop.** `Libs/AI/final/sb_combat.xml` declares
`<BehaviorTree name="dropItems">` with variables `hand` (0 right, 1 left),
`item` and `itemCategory`, plus a forward-declared `t_dropItems_dropWeapons`
bool. It places held items on the ground, and for anything whose
`itemCategory` is neither `melee_weapon` nor `missile_weapon` it runs:

```
AddLink From="this.id" To="item" Tag="panicDrop"
```

so the dropped item stays linked to the NPC that dropped it.

**The retrieval.** `Libs/AI/final/so_slot.xml` holds 24 item-handling trees,
among them `pickItem`, `pickFromGround`, `findPickedItem`, `safePickItem` and
`slotRecoveryCheck`. The `panicDrop` recovery lives in the `placeItem` tree and
does exactly the expected three steps:

```
GraphSearch ... SubGraph="panicDrop"
RemoveLink From="this.id" To="handCheck" Tag="panicDrop"
SmartObjSetBehaviorState behaviors="pickItem" state="Enabled"
```

`so_tool.xml` has a parallel path that filters the graph with
`LinkTagFilter tag="panicDrop"`.

So: drop, tag, later find by tag, untag, enable the pick-up behavior. That is
the behavior described as the goal, and it ships with the game.

**`dropItems` is not welded to the `Hit` state.** It is a named tree, invoked
by `<IncludeTree File="final/sb_combat.xml" Name="dropItems" />`. The `Hit`
state is one caller, not the definition. An earlier entry ruled the `Hit` path
out as the *cause* of the old symptom, which was correct, but that is not the
same as the tree being unavailable as a mechanism.

**Where the mod's message lands.** `sb_switch_hitreactions.xml` line 260 is the
branch guarded by `$hitReaction.hitType == $enum:HitReactionType.Collision`.
That branch currently does a dead check, some barks gated on
`!$b_inCombat & !$b_context['suppressCollisionsBark']`, and an awareness
impulse. Adding an `IncludeTree` of `dropItems` there is the shape of the
change.

### The cost, which is the real decision

`sb_switch_hitreactions.xml` is 132,889 bytes, and **the mod deliberately
stopped shipping it.** The current pak contains only the four animation files
and `Scripts/Startup/HorseCollisionMod.lua`. Re-adding it means:

- A hard conflict with any other mod that edits hit reactions. Behavior trees
  cannot be merged, only replaced, exactly like the Mannequin databases.
- A second whole-file replacement pinned to 1.9.7, doubling the surface that
  a game patch would invalidate.
- This diary already records a failed attempt to drive animation from this
  file: "A `PlayAnimation` node added to `sb_switch_hitreactions.xml`: node
  runs, animation fails." That was a different goal, but it is a reminder that
  editing the tree is not automatically effective.

Against that, the payoff is real: the current stagger clip is authored for
empty hands, so an NPC keeping a bucket through it looks wrong. Dropping the
item, reacting, and picking it up is both more natural and vanilla-sanctioned.

Not yet established, and worth knowing before committing to this:

1. Whether `dropItems` runs correctly outside a combat subbrain, given it lives
   in `sb_combat.xml` and forward-declares a combat variable.
2. What drives the `pickItem` behavior once enabled, and whether it returns the
   NPC to their previous activity or restarts it. The day-cycle restart in the
   `Hit` path is gated on `!$b_context['suppressDaycycleRestartAfterHit']`, so
   there is a sanctioned flag for keeping the drop without the restart.
3. Whether the same path exists for the female smart objects, since the bucket
   carriers are women and the female animation data has needed separate work
   throughout this project.

---

## Mod compatibility, researched rather than assumed

Prompted by a fair challenge: mod collections stack dozens of mods that must
overlap constantly, so is this mod actually unusual or is the conflict worry
overstated? Answered from the installed mods, the game's own data, and the
game binary.

### The three open questions on the drop-and-pickup path

**Q1. Does `dropItems` depend on combat?** No. The tree is 7,356 characters and
references exactly four variables: `hand`, `item`, `itemCategory`, `__null`.
Not one combat variable, and the node types are all generic (`AddLink`,
`GetItemType`, `HandCheck`, `InstantDoPlace`, `IfCondition`, `Switch`, `While`,
`Expression`). It lives in `sb_combat.xml` by filing, not by dependency, and
should run anywhere.

**Q2. Does the pickup restart the NPC's day?** Not on its own.
`daycycle:restartRequest` appears **zero** times in `so_slot.xml`. The restart
lives in the `Hit` branch of `sb_switch_hitreactions.xml`, not in the retrieval
path, so invoking the drop and letting the smart object recover the item does
not inherently abandon the activity. The four relevant trees are substantial
and real: `pickItem` (9,327 chars), `findPickedItem` (7,590),
`slotRecoveryCheck` (5,551), `pickFromGround` (4,784).

**Q3. Do the female smart objects use the same path?** Yes. `so_slot.xml`
contains no gender branching whatsoever, so item handling is shared. The
gendered split in this project has only ever been in the animation databases.

All three answers are favourable. Nothing in the AI data blocks the goal.

### What this mod actually conflicts with

Every mod installed on this machine, by the files it overrides:

| Mod | Overrides | Subsystem |
| --- | --- | --- |
| Perkaholic | 6 `Libs/Tables/rpg/*__perkaholic.xml` + localization | RPG tables |
| RealisticFootprints | `Libs/MaterialEffects/FXLibs/*`, decal materials and textures | material effects |
| HighFPSFX | 8 `Libs/Particles/*.xml` | particles |
| CutsceneFPSFix | one `.ent` and two Lua files, all its own | new entity |
| EasyToSeeHerbs | one `.dds` | texture |
| XboxToPS3controller | `Libs/UI/Textures/*.dds` | UI textures |
| **HorseCollisionMod** | **`kcd_male_database.adb` (5.5 MB), `wh_female_database.adb`, 2 tag/fragment XMLs** | **animation databases** |

**Overlap between all six other mods: zero.** Not one shared file, excluding
Vortex's own bookkeeping. They stack cleanly because each lives in a different
subsystem, and several add new files rather than replacing existing ones.

So mods do stack by the dozen, and the reason is not that the engine merges
them. It is that most mods touch small leaf assets, and the chance of two mods
picking the same texture or particle file is low.

### This mod is genuinely different, and here is the specific reason

There are two categories, and they are not the same:

**Data with a merge path.** Perkaholic does not replace `perk.xml`. It ships
`perk__perkaholic.xml` alongside it. Those files are row tables
(`<database name="hammerheart"><table name="perk">` with typed columns), and
the loader combines rows from every matching file. Vanilla ships **zero**
`__suffixed` table files, confirming the suffix is a mod convention the loader
supports rather than something copied from the game. Two perk mods can coexist.
The community has built merge tools on top of this for the cases that do clash:
KCDMerge, Letum's Mod Merger, Mod Merger, all of which work by matching row IDs
and combining values.

**Data with no merge path.** Mannequin animation databases are one XML document
per character type. There is no row identity to match, no `__suffix`
convention, and none of the merge tools handle `.adb`. Two mods that both add a
fragment to `kcd_male_database.adb` cannot both win. The later one in
`mod_order.txt` replaces the file outright and the other's changes vanish
silently.

That is the honest asymmetry. The mod is not unusually greedy, it is in the one
data format the ecosystem has no answer for. Behavior trees, which the
carried-item work would need, are in the same category.

### SubADB: the engine supports splitting a database, and vanilla never uses it

This is the finding that changes the options.

Scanned all 28 vanilla `.adb` files: **zero** use `<SubADB>`. Easy to conclude
from that alone that the fork dropped the feature. It did not. The strings are
present in `WHGame.dll`:

```
SubADBs
Loading subADB %s
[CAnimationDatabaseManager::LoadDatabase] Unknown tags %s for subADB %s
```

Those are live code paths in `CAnimationDatabaseManager::LoadDatabase`,
including a tag-validation error specific to sub-databases. The loader is
implemented; the game simply never exercises it.

**And the database is bound from Lua, not hardcoded.**
`Scripts/Entities/actor/player.lua` sets:

```lua
ActionController = "Animations/Mannequin/ADB/kcd_male_controllerdefs.xml",
AnimDatabase3P   = "Animations/Mannequin/ADB/kcd_male_database.adb",
```

Which raises a genuinely additive shape worth testing: a small parent `.adb`
that declares the vanilla database and a mod fragment file as two SubADBs,
with entities pointed at the parent. No vanilla animation file modified at all.

Untested, and there are real unknowns: whether a SubADB can carry a whole
database rather than a fragment subset, whether tag validation accepts it, and
whether the entity property can be redirected without replacing `player.lua`
and `BasicAI.lua`, which would only move the conflict rather than remove it.

The cost of finding out is low, because animation data hot-reloads. This is
exactly the kind of question that was expensive before that tooling existed.

Recorded now so the option is not lost: **the current whole-database
replacement is a choice, not a constraint.**

---

## Build 2.0.1-dev.15: SubADB loads

**Hypothesis**: the Mannequin loader in this build supports sub-databases, so
the mod's fragments can live in their own `.adb` and the vanilla database only
needs a reference to it.

Background is in the compatibility entry above: no vanilla `.adb` uses
`<SubADB>`, but `WHGame.dll` carries `SubADBs`, `Loading subADB %s` and a
subADB-specific tag error, and `SubADB` exists as a standalone string
alongside `File` and `Tags`.

### The build

`build_adb.py --subadb` writes two files instead of one:

- `hcm_male_stagger.adb`, 3,406 bytes, a complete `AnimDB` with the same
  `FragDef` and `TagDef` as the parent and an `AnimationControlled`
  `FragmentList` holding the four stagger options.
- `kcd_male_database.adb`, vanilla plus **96 bytes**:

```xml
  <SubADBs>
    <SubADB File="Animations/Mannequin/ADB/hcm_male_stagger.adb" />
  </SubADBs>
```

Emitted without a `Tags` filter on purpose. The loader validates `Tags` against
the tag definition, so an unfiltered reference is the case least likely to fail
for a reason unrelated to the question.

Compare that 96-byte diff with the roughly 3,200 bytes the inline splice adds.

### Result: the engine loads it

Reloaded into the running game with `--anim-reload --verbose`. Verbosity
mattered: at the default the line does not appear at all, which made the first
attempt read as a silent failure when it was a logging level.

```
[log] Loading subADB Animations/Mannequin/ADB/hcm_male_stagger.adb
```

No `Unknown tags ... for subADB` error accompanied it. The `Unknown tags`
lines that do appear are the pre-existing vanilla noise for
`CombatStealthAttackSuccess` and `CombatStealthHitSuccess` with `stealthLying*`
tags, and their format is "for fragmentID", not "for subADB".

**So the feature is live in this build despite no vanilla file using it.** Worth
noting how close this came to a wrong negative: 28 vanilla databases using zero
SubADBs is exactly the kind of complete-looking sample that justifies "the fork
removed it".

### The in-game control is built in

The female database is still built with the options spliced inline, and only
the male one uses the SubADB. So a single test separates the two cleanly:

- Women stagger, men do not: SubADB parsed but its fragments did not resolve.
- Both stagger: SubADB works end to end.
- Neither: something unrelated broke.

### Still to establish

Loading is not the whole prize. The reference still lives inside a replaced
`kcd_male_database.adb`, so this does not yet remove the conflict, it shrinks
it from 5.5 MB of spliced XML to three lines another author could reapply by
hand.

Removing the conflict entirely needs the second half: a small parent `.adb`
that declares *both* the vanilla database and the mod's file as SubADBs, with
entities pointed at the parent. The database path is a Lua entity property,
`AnimDatabase3P` in `Scripts/Entities/actor/player.lua`, so redirecting it does
not require touching any animation file, though it would require touching
`player.lua` and `BasicAI.lua` unless it can be set at runtime.

Unknown, and the next thing to test: whether a SubADB can carry a whole
database rather than a fragment subset.

### Result: confirmed in game

**User reported**: "both staggered."

Men staggered from a fragment defined only in `hcm_male_stagger.adb`, reached
through the `<SubADBs>` reference. Women staggered from the female database,
which is still built with the options spliced inline and served as the control.

**SubADB works end to end in KCD 1.9.7.** The fragments resolve, not merely the
file being read, and they resolve through a mechanism no vanilla file uses.

That settles the mechanism. What it changes:

| | inline splice | SubADB |
| --- | --- | --- |
| diff against vanilla `kcd_male_database.adb` | ~3,200 bytes spliced into `FragmentList` | 96 bytes appended before `</AnimDB>` |
| another animation mod's copy | mod's fragments vanish silently | three lines a person can reapply |
| where the mod's content lives | inside a 5.5 MB vanilla file | its own 3.4 KB file |

This does not yet remove the conflict. `kcd_male_database.adb` is still
replaced, so load order still decides. It converts an unresolvable conflict
into a trivially resolvable one, which is worth having on its own.

### The remaining step, and its one unknown

Full additivity needs the vanilla database left untouched entirely. The shape:

```
hcm_male_database.adb        tiny parent, two SubADB references
  -> kcd_male_database.adb   vanilla, untouched, still in its pak
  -> hcm_male_stagger.adb    the mod's fragments
```

with entities pointed at the parent instead of the vanilla file.

Two things have to hold, and only the first is a genuine unknown:

1. **Can a SubADB carry a whole database rather than a fragment subset?**
   Nothing observed so far says no, but nothing tested says yes either.
2. **Can `AnimDatabase3P` be redirected without replacing a vanilla file?**
   It is a Lua entity-class property, set in
   `Scripts/Entities/actor/player.lua` for the player and in the AI equivalents
   for NPCs. Replacing those files would only move the conflict from an
   animation database to a Lua script, which is better but not free. Setting it
   from this mod's own Startup Lua before entities spawn would be free, and
   this mod already runs Startup Lua. Untested.

If both hold, the mod replaces **no vanilla file at all** and the animation
conflict disappears rather than shrinking.

---

## Build 2.0.1-dev.16: a SubADB can carry a whole database

**Hypothesis**: the loader will accept an entire animation database through a
`<SubADB>` reference, not just a small fragment subset.

**Setup.** The loose `kcd_male_database.adb` was replaced with a **341 byte**
parent holding nothing but two references:

```xml
<AnimDB FragDef="..." TagDef="...">
  <SubADBs>
    <SubADB File="Animations/Mannequin/ADB/hcm_male_vanilla.adb" />
    <SubADB File="Animations/Mannequin/ADB/hcm_male_stagger.adb" />
  </SubADBs>
</AnimDB>
```

`hcm_male_vanilla.adb` is a byte-for-byte copy of the vanilla 5.5 MB database.
Shipping that copy is obviously not the end state; the point was to isolate one
variable and leave the Lua redirect out of it.

**User reported**: "men staggered and everyone is animating normally."

**Result: confirmed.** The entire male animation set reached the game through
two SubADB references, from a parent document containing no fragments of its
own. Both loads were logged and no subADB error appeared.

The second half of that report is the load-bearing one. Had the vanilla SubADB
failed to merge, every male in the world would have lost their whole fragment
set, which is not a subtle failure.

### The warnings were a false alarm, and were checked rather than assumed

The reload logs a batch of `Warning missing fragmentID` lines
(`DiceGameStart`, `CorpseGrab`, `PickingHerbs`, and others), which read like
the probe having broken something.

Fingerprinted the full warning set under both the probe and the previous
working build and diffed them:

```
missing fragmentID       total=14    unique=12
unknown tags fragID      total=16    unique=2
skipping unknown frag    total=103   unique=103
invalid tag              total=16    unique=2
```

**Identical**, the extra `Loading subADB` line aside. All of it is vanilla's own
noise. Worth the two minutes: the alternative was reporting a regression that
was always there, which this project has done before.

### Where this leaves the additive question

Both unknowns from the previous entry are now settled in favour:

1. SubADB works, and fragments defined only in a sub-database resolve.
2. A SubADB can carry a whole database.

One piece remains: pointing entities at a parent that references the
**untouched** vanilla file inside its pak, rather than replacing
`kcd_male_database.adb` with the parent. That is the difference between
shrinking the conflict and removing it, and it is a Lua question rather than an
animation one, since `AnimDatabase3P` is an entity-class property.

---

## Build 2.0.1-dev.17: fully additive animation deployment works

**Hypothesis**: entities can be pointed at a small parent database that
references the untouched vanilla file inside its own pak, so the mod overrides
no vanilla animation file at all.

**Setup.** Every loose `kcd_male_database.adb` override removed, so vanilla is
served from `Animations-part1.pak`. In its place a new file:

```
hcm_male_database.adb   342 bytes
  <SubADB File="Animations/Mannequin/ADB/kcd_male_database.adb" />   vanilla, from the pak
  <SubADB File="Animations/Mannequin/ADB/hcm_male_stagger.adb" />    the mod's four options
```

Five male entity classes redirected at runtime through the remote console,
confirmed by reading the property back:

```
NPC_x, NPC_NAI_x, NullAI_x, DummyTarget_x, Player
  AnimDatabase3P = Animations/Mannequin/ADB/hcm_male_database.adb
```

Then a save load, because the property is read when an actor spawns and
existing NPCs had already been built against the old value.

**User reported**: "men staggered and everyone animating normally."

**Result: confirmed.** The mod's fragments resolve, ordinary male animation is
intact, and **not one vanilla animation file is overridden on the male path.**

Worth stating what that changes. The compatibility entry above concluded that
Mannequin databases have no merge path and that two mods touching human
animations cannot coexist. That conclusion was correct about *replacement* and
wrong as a limit. There is a supported way to add fragments without replacing
anything, and it has now been demonstrated end to end.

The chain of three results that got here, each of which could have been
mistaken for a dead end:

1. No vanilla `.adb` uses SubADB, but the loader is in `WHGame.dll`.
2. SubADB resolves fragments, not just loads files.
3. A SubADB can carry an entire database, and the database path is a Lua
   entity-class property rather than something compiled in.

### What is still replaced

The male *database* path is clean. Three files are not yet:

| File | Status |
| --- | --- |
| `kcd_male_database.adb` | **no longer overridden** |
| `hcm_male_database.adb`, `hcm_male_stagger.adb` | new files, conflict with nothing |
| `kcd_animationControlledTags.xml` | still a replacement, declares the four FragTags |
| `wh_female_database.adb` | still a replacement, female side not yet converted |
| `wh_female_fragmentids.xml` | still a replacement, declares the female fragment |

The female side is unconverted on purpose: it was the control for this test.
Converting it should be mechanical now.

The two XML declaration files are the open question. Whether a sub-database can
carry its own tag and fragment definitions, or whether those must be merged
into the vanilla ones, has not been tested.

### Deferred observations from this session

Recorded now so they survive, not investigated yet at the user's direction.

**Female staggers fire intermittently.** "Some of the woman stagger animations
didn't fire and some did. It almost seemed random or maybe related to which
side I hit them from."

Not caused by the additive work: the female path was untouched in this test and
still uses the inline splice. A side dependency would point at `GetImpactDir`
and the four directional FragTags, where a direction that resolves to no
matching option is dropped silently, which this diary records as the single
most important failure mode in the project.

**Speed tier misreported at gallop.** "Sometimes I'll be galloping full speed
against someone and the animation/ragdoll don't fire and in the console it says
it impacted them at walking speed but there's no way that's accurate."

This is the same phenomenon as the earlier "gallop regression" entry, which was
closed as not-a-bug on the grounds that the horse never exceeded 8.03 m/s
against `SpeedGallop = 8.5`. That closure now looks premature. If the speed
sampled at impact can read as walking pace during a full gallop, the telemetry
that justified the tier boundaries is itself suspect, and so is the tuning
derived from it. The likely suspect is when and how velocity is sampled
relative to the impact rather than the thresholds themselves.

Both belong to a tuning pass, after the deployment work.

---

## Build 2.0.1-dev.19: the declaration files go additive too

**Hypothesis**: a SubADB entry's own `FragDef` is honoured rather than inherited
from the parent, so the mod can bring its own fragment id and tag definitions
under its own filenames and stop claiming vanilla ones.

**Setup.** Three files, none of them a vanilla name:

```
hcm_male_stagger.adb        FragDef -> hcm_male_fragmentids.xml
hcm_male_fragmentids.xml    AnimationControlled subTagDef -> hcm_animationControlledTags.xml
hcm_animationControlledTags.xml   vanilla tags plus the four hcm_stagger_* tags
```

The `kcd_animationControlledTags.xml` override was deleted.

**User reported**: "men staggered and everyone animating normally."

**Result: confirmed.** The sub-database's own `FragDef` is used, the chain
resolves through it, and the male path now overrides **no vanilla file at all**:

```
hcm_male_database.adb              342 bytes
hcm_male_stagger.adb              3319 bytes
hcm_male_fragmentids.xml         35505 bytes
hcm_animationControlledTags.xml   1005 bytes
```

Against the shipped 2.0.0 layout, which replaced `kcd_male_database.adb`
(5.5 MB) and `kcd_animationControlledTags.xml`.

### The weakness, stated plainly

`hcm_male_fragmentids.xml` and `hcm_animationControlledTags.xml` are **copies**
of vanilla with additions, not references to it. The database got something
strictly better: a genuine reference to the untouched file inside its pak.

A copy never collides, which is the property being bought. A copy also cannot
pick up another mod's additions, so it buys non-collision without buying
composability. Two mods each shipping their own copy would each see their own
additions and neither would see the other's.

For this mod that is acceptable, because the only thing read out of those files
is the `AnimationControlled` fragment and its FragTags, which nothing else is
likely to extend. It would not be acceptable for a mod that needed to compose
with others in the same tag group. Worth writing down so the limitation is not
rediscovered as a surprise.

Copies also go stale against a game patch. At 1.9.7 being the final build, that
risk is close to zero here.

### Still not converted

The female side: `wh_female_database.adb` and `wh_female_fragmentids.xml` are
still replacements. Kept deliberately as the control through all four probes,
and mechanical to convert now that the male pattern is proven.

### Third report of reactions not firing

**User reported**: "Again noticing some of the reactions from all three speed
categories are getting eaten or something."

Escalating, and worth flagging as a real defect rather than tuning. Earlier in
this session it was reported as intermittent female staggers, possibly
direction-dependent. Now it is **all three speed tiers**, so it is not specific
to the walk-tier interactive action, and not specific to women.

The three tiers use two different mechanisms, the stagger being an interactive
action and the knockdowns being a physics impulse, so a fault common to both
points upstream of either: detection, the impact-direction resolution, or the
per-victim cooldown.

Related and probably the same root: a gallop impact reporting walking speed,
recorded earlier this session. If the speed sampled at impact can be wrong,
tier selection is wrong, and `HitCooldownMs = 3000` would then silently
suppress the correct reaction that follows.

Deferred at the user's direction, but this now looks like the most valuable
thing to fix next, ahead of any tuning. The tuning numbers were derived from
telemetry this defect would have corrupted.

---

## Build 2.1.0-dev.1: the additive layout as a real build

First test of the additive deployment through the actual build pipeline rather
than hand-assembled probe files, and the first with the female side converted.

**User reported**: "both worked."

Men and women both stagger, with the redirect performed by the mod itself
rather than by console commands.

### What ships now

```
hcm_animationControlledTags.xml   1005 B   FragTags, under a mod name
hcm_female_database.adb            347 B   parent, two references
hcm_female_fragmentids.xml       14082 B   declares AnimationControlled
hcm_female_stagger.adb            3409 B   the four options
hcm_male_database.adb              342 B   parent, two references
hcm_male_fragmentids.xml         35505 B   AnimationControlled repointed
hcm_male_stagger.adb              3406 B   the four options
```

Against 2.0.0, which shipped `kcd_male_database.adb` (5,555,221 B),
`wh_female_database.adb` (962,471 B), `kcd_animationControlledTags.xml` and
`wh_female_fragmentids.xml`.

| | 2.0.0 | 2.1.0 |
| --- | --- | --- |
| download | 195,284 B | **24,366 B** |
| content in the pak | 6.5 MB | 92 KB |
| vanilla filenames claimed | 4 | **0** |

Eight times smaller, and it stops redistributing 6.4 MB of Warhorse's own data.

### The redirect

`HorseCollisionMod.AnimationDatabases` maps seven entity classes to the two
parent databases. `RedirectAnimationDatabases` runs at **file scope**, not from
the load screen, because `AnimDatabase3P` is read when an actor spawns and the
load screen ends after the world is already populated. It retries from the load
screen for any class table that loaded late; the log reports `0 pending`, so all
seven exist by the time a Startup script runs.

Verified by reading the property back out of the running game:

```
NPC_x, NPC_NAI_x, NullAI_x, DummyTarget_x, Player -> hcm_male_database.adb
NPC_Female_x, PlayerFemale                        -> hcm_female_database.adb
```

### Build guard

`build.ps1` now fails if any file under a name not beginning `hcm_` would ship.
A leftover from a `--replace` build would silently defeat the entire layout
without changing a single line the build prints, and that class of silent
override has cost this project several sessions already.

### Not yet verified: the pak path

**Everything above was tested with loose files.** `system.cfg` on the
development machine carries `sys_PakPriority = 0`, so the file system is
searched before the paks. A player has the shipped default of `2`, pak only,
where loose files are ignored entirely.

This is not a theoretical gap. This diary records a build where the mod pak
stored Windows path separators, so CryEngine looked entries up by a path that
did not match and the pak silently overrode nothing, while the same files
deployed loose worked correctly. Startup Lua still ran, because that folder is
enumerated rather than looked up by path, which is what made it so slow to
find.

The additive layout is more exposed to that class of failure than the old one,
not less, because it depends on paths resolving in three places rather than
one: the `SubADB File` attributes, the `FragDef` and `subTagDef` references, and
the `AnimDatabase3P` property. Every one of those is a path the engine has to
resolve out of a pak.

Not merging until a packaged build is tested at `sys_PakPriority = 2`.

---

## Build 2.1.0: the additive layout FAILS in a player configuration

**Hypothesis**: the additive layout, verified across five builds with loose
files, also works from inside a pak in a shipping configuration.

**Setup.** As close to a player as the machine gets:

```
sys_PakPriority = 2                        shipping default, paks only
mn_allowEditableDatabasesInPureGame = 0    shipping default
no loose files at all                      the pak is the only source
launched KingdomCome.exe directly          no -devmode
```

**User reported**: "both women and men had the single frame glitched animation
snap back behavior."

**Result: it does not work.** That signature is precisely documented in this
diary as *a valid call with no matching option*: the action is accepted, the
pose visibly begins, and it reverts within one frame because
`StartInteractiveActionByName` found no option matching the FragTags. The
mod's fragments are not being seen.

Everything in this session up to here was verified with loose files at
`sys_PakPriority = 0` and `mn_allowEditableDatabasesInPureGame = 1`. Not one of
those results transferred.

### My testing was badly designed and that cost the answer

Four variables changed at once between the last passing test and this failing
one: pak priority, the Mannequin CVar, loose versus packed, and dev mode. A
failure with four simultaneous changes says only that something in the set is
responsible.

The correct approach was one variable at a time, and it was available: the
whole session had already established that the hot-reload loop makes single
changes cheap. Recording this because the same mistake would otherwise be made
again, and because the earlier `ColliderMode` conclusion in this project failed
for the same reason - a change plus an outcome, with no control.

### The suspects, in order

1. **`mn_allowEditableDatabasesInPureGame = 0`.** The strongest candidate. This
   CVar already has form: it is why `mn_reload` appeared to be a no-op for a
   whole session. If the "pure game" path assembles databases differently, for
   instance from a precompiled or cached form that never processes `<SubADBs>`,
   then SubADB works only in a development configuration and is useless for
   shipping. Every additive test in this session ran with it at 1.

2. **Pak path resolution.** The additive layout resolves paths in three places
   the old one did not: `SubADB File`, `FragDef` and `subTagDef` references, and
   `AnimDatabase3P`. Pak entry names were verified to use forward slashes, which
   rules out the specific bug this project hit before, but not the general class.

3. **Dev mode.** Least likely. It gates `VF_CHEAT` console commands, and nothing
   in the load path obviously depends on it.

### What this means for shipping

**2.1.0 must not be published, and must not merge to main as the default
layout.** Whatever the cause, in the only configuration that matters the mod
currently does nothing at all.

`build_adb.py --replace` still builds the 2.0.0 layout, which is known to work
in a player configuration because it is what shipped. That is the fallback if
the cause turns out to be unfixable.

Next: isolate. `mn_allowEditableDatabasesInPureGame` back to 1, changing
nothing else, still packed and still without dev mode.

---

## Build 2.1.0-dev.5: the canary, and how SubADB merging actually works

Three cold-start failures in a row, each with every file demonstrably loading,
so the question became whether the mod's options ever reach the fragment at
all. The diary records the technique that settles it: build 2.0.0-dev8 used a
canary that repointed a vanilla tag at a stagger clip.

**Setup.** One extra option was added to the mod's sub-database carrying the
**vanilla** FragTag `cabinet_o`, pointing at a stagger clip instead of the
cabinet animation. Because that tag is declared in vanilla's tag file and in the
mod's, tag declaration stops being a variable. The mod was temporarily made to
ask for `cabinet_o`. Sub-database order at the time: the mod's file first,
vanilla's second.

**User reported**: "so women remain with single frame glitched but the cupboard
animation fires on men."

Two separate results, both valuable.

### Men: the later sub-database replaces the fragment, it does not merge

The men played vanilla's cabinet animation, not the mod's clip. So vanilla's
`cabinet_o` option won while vanilla's sub-database was listed **second**.

That is the answer to the whole failure. **When two sub-databases define the
same fragment id, the later one replaces it outright. Options are not merged.**

Every earlier symptom follows from it. With vanilla listed last, its 32-option
`AnimationControlled` fragment replaced the mod's entirely, so the four
`hcm_stagger_*` options were simply absent, and every call against them
resolved to nothing. That is the one-frame snap back, and it produces no error
because `StartInteractiveActionByName` returns success either way.

It also explains why the loader has to be given the mod's file last **and** that
file has to carry vanilla's own options, or redirected NPCs lose every door,
cabinet and wardrobe interaction in the game. The cost of carrying them is
modest: the `AnimationControlled` fragment is 68,966 bytes, **1.24% of the
5.5 MB database**.

### Women: the female parent database is never loaded at all

The log lists exactly two sub-database loads, both male:

```
Loading subADB Animations/Mannequin/ADB/hcm_male_stagger.adb
Loading subADB Animations/Mannequin/ADB/kcd_male_database.adb
```

No `hcm_female_stagger.adb`, no `wh_female_database.adb`. The female parent was
never opened, even though `NPC_Female_x.lua` loads and the redirect reports all
seven classes claimed with none pending.

So the female failure is a different bug from the male one and was masked by it.
Unresolved: whether female NPCs are actually instances of `NPC_Female_x`, or
whether some other class serves them and is not in the redirect table.

### What was wrong with the earlier attempts, in order

Worth listing, because each looked like a complete explanation at the time:

1. **Parent `FragDef` pointed at vanilla's fragment ids.** Real, and fixed. The
   parent's FragDef is what the loader validates FragTags against, and vanilla's
   chain does not declare `hcm_stagger_*`. Fixing it removed the `Unknown tags`
   errors and changed nothing visible, because the next fault was still ahead.
2. **`ActionController` still pointed at vanilla's controller def.** Also real,
   also fixed. The controller def owns the fragment and tag definitions an
   entity resolves names through at runtime; a database's FragDef governs
   load-time validation only. Fixing it changed nothing visible either.
3. **Sub-database ordering.** Tested both ways before understanding the
   semantics, which is why neither order worked: one loses the mod's options,
   the other loses vanilla's.

All three were genuine defects. None was sufficient alone, which is why each
fix produced no visible change and looked like a dead end.

---

## Build 2.1.0: additive deployment WORKS, and the real root cause

**User reported**: "both men and women staggered! Seemed to work great."

Packed, `sys_PakPriority = 2`, cold start, no dev mode, no loose files. The mod
overrides **no vanilla file at all**.

### The root cause, after five failed cold starts

Entity classes are built from templates, and the template is not what spawns:

```lua
-- Scripts/Entities/AI/NPC.lua
NPC = CreateAI(NPC_x);

-- Scripts/Entities/AI/Shared/BasicAI.lua
function CreateAI(child)
    local newt = {}
    mergef(newt, child, 1);   -- copies the fields
```

`NPC_x` is a template. `CreateAI` builds a fresh table and **copies** fields
into it, so the live class holds a snapshot of `AnimDatabase3P` and
`ActionController` taken when its script loaded. A Startup script mutating
`NPC_x` afterwards changes nothing about what spawns.

Every NPC was on the stock animation chain for five test cycles.

**Why it hid so effectively.** `Player` is declared directly as a table rather
than through `CreateAI`, so redirecting it genuinely worked. That made the
mod's own controller def and sub-databases load and appear in the log, which
read as proof the redirect worked. It only ever proved the *player's* redirect
worked. It also explains why `hcm_female_database.adb` never loaded at all:
`PlayerFemale` does not spawn in normal play and `NPC_Female` was never
redirected.

**The mistake.** `Redirected 7 animation databases, 0 pending` was treated as
evidence the redirect had taken effect. It is only evidence the property was
written. Those are different claims and the second was never checked. The cheap
test skipped was querying a *spawned NPC's* database rather than the class
table just written to. This project has a standing rule about proving a signal
works before drawing conclusions from it, and this is the third time in one
session it was broken.

### The three earlier fixes were all real, and all invisible

Each was a genuine defect in code that was never being reached, which is why
none changed the symptom:

1. The parent's `FragDef` pointed at vanilla's fragment ids, so `hcm_stagger_*`
   was undeclared at load-time validation.
2. `ActionController` was not redirected, so runtime name resolution used
   vanilla's tag chain. A database's `FragDef` governs validation only.
3. Sub-databases do not merge options into a fragment another one defines. The
   mod's `AnimationControlled` has to be authoritative and carry vanilla's own
   options, or redirected NPCs lose every door, cabinet and wardrobe
   interaction.

Fixing plumbing downstream of a closed valve produces identical symptoms every
time, which is exactly what a chain of dependent defects looks like from the
outside.

### What ships

```
hcm_animationControlledTags.xml    1005 B   16 vanilla tags + 4 of ours
hcm_female_controllerdefs.xml     22798 B
hcm_female_database.adb            3507 B   4 options + SubADB to vanilla
hcm_female_fragmentids.xml        14082 B   declares AnimationControlled
hcm_male_controllerdefs.xml       87818 B
hcm_male_database.adb             72468 B   30 vanilla + 4 options, SubADB to vanilla
hcm_male_fragmentids.xml          35505 B
Scripts/Startup/HorseCollisionMod.lua
```

Verified against vanilla: all 16 `AnimationControlled` tags present plus the
mod's 4, and all 30 vanilla options present plus the mod's 4. Nothing dropped.

| | 2.0.0 | 2.1.0 |
| --- | --- | --- |
| vanilla files replaced | 4 | **0** |
| `kcd_male_database.adb` | 5,555,221 B shipped | untouched in its pak |
| `wh_female_database.adb` | 962,471 B shipped | untouched in its pak |

### Open, not investigated

**A beggar in Rattay stood instead of kneeling.** Reported as "may or may not be
a thing." Checked and not explained by the fragment replacement: nothing
beggar-related lives in `AnimationControlled`, and no vanilla tag or option is
missing from the mod's copy. Candidates are the controller def copy, the
fragment id copy, or the NPC's schedule being unrelated to the mod entirely.
Needs a controlled comparison against a run with the mod disabled before
anything is concluded.

### A Vortex install test that used the wrong build

Reported: installing `v2.1.0-dev.1.zip` through Vortex produced no staggers,
only the one-frame glitch.

That build is from 12:00 and the working one is from 17:10. It predates every
fix: no `ActionController` redirect, no exposed-class redirect, and it still
used the separate `hcm_<set>_stagger.adb` files whose options a parent
overrides. Any one of those alone produces exactly that symptom, and all three
were missing. The result says nothing about the current build.

The cause is a release directory holding **49 zips**, thirteen of them named
`2.0.1-dev.*` or `2.1.0-dev.1`, with no indication which was current. Everything
superseded is now under `releases/archive/`, leaving only 2.0.0 and 2.1.0 where
they can be picked up by hand.

Worth generalising: intermediate builds from a debugging session are a hazard
once the session ends, because the only thing distinguishing a working build
from a broken one is a timestamp nobody checks.

### The beggar, and a confound in the control

Reported earlier: a beggar in Rattay stood instead of kneeling with the mod
installed. A control run with the mod removed entirely, same save, had him
kneeling.

Structurally the mod does not explain it. `Beggar`, `BeggarOut` and `BeggarVAR`
are fragment ids preserved verbatim in the mod's fragment id copy, their
fragments live in the vanilla database and are reached through the SubADB
reference like every other working animation, and the mod's controller def
differs from vanilla by exactly one line, the `Fragments` filename.

**The control has a confound.** In the mod-on run the player had been riding
around for some time; in the control the save was loaded and the beggar observed
straight away. Beggars follow a daily schedule, so elapsed in-game time was not
held constant between the two runs.

A protocol that would settle it: load the save, observe immediately, quit. Then
change exactly one variable and repeat with the same elapsed time. Until that is
done this is an open question rather than a known regression, and it should not
be recorded as either.

---

## Build 2.1.0 (second design): the beggar, and why the copies had to go

**User reported**, after a proper Vortex install of the working build: staggers
and ragdolls all fine, but Rattay's beggar stands instead of kneeling. He still
plays the barks that belong to the begging animation. Waiting in game did not
restore it. Same save on pure vanilla, he begs.

Barks playing without the animation is the same signature as the stagger
failure: the behaviour runs, requests a fragment, and Mannequin resolves it to
nothing.

### Why the mod was in that path at all

The beggar animation has nothing to do with this mod. It resolves through the
fragment ids `BeggarIn`, `BeggarGive` and `BeggarTake`, whose subTagDef is
`kcd_beggar_tags.xml`. Vanilla's `AnimationControlled` fragment, the only one
this mod touches, contains nothing beggar-related: its 30 options are doors,
cabinets, wardrobes and one alarm bell.

But the first 2.1.0 design shipped **copies** of two large vanilla files:

```
hcm_male_fragmentids.xml     35 KB
hcm_male_controllerdefs.xml  88 KB
```

They existed for one reason: to make a tag file named `hcm_*` reachable. The
controller def had to point at the ids copy, and the ids copy at the tag file.
And because `ActionController` was redirected to that copy, **every fragment a
human uses resolved through files this mod restated**, not just its own.

123 KB of vanilla data restated under mod names, sitting in the resolution path
of animations the mod has no interest in. The beggar is what noticed.

### The design that replaces it

Ship the tag additions under **vanilla's own name** instead:

```
hcm_male_database.adb            72 KB   parent, 30 vanilla options + 4 added
hcm_female_database.adb           3 KB   parent, 4 added
kcd_animationControlledTags.xml   1 KB   16 vanilla tags + 4 added
wh_female_fragmentids.xml        14 KB   declares AnimationControlled
```

`ActionController` is no longer redirected at all. Entities stay on vanilla's
controller def, which reaches vanilla's fragment ids, which reach
`kcd_animationControlledTags.xml` - the one small file this mod extends. Every
other fragment resolves through vanilla's own path, untouched.

The trade, stated plainly: this claims two vanilla filenames totalling 15,087
bytes, where the previous design claimed none. Against that, it stops
restating 123 KB of vanilla definitions and stops interposing itself in
unrelated animations. Fifteen kilobytes of declarations is a far smaller thing
to own, and small enough that another author can merge it by hand in a minute.
The property that actually mattered is intact: **the 6.4 MB of animation
databases are still referenced, never replaced.**

### The general lesson

"Replaces no vanilla file" turned out to be the wrong thing to optimise for.
Avoiding a filename by restating the file under another name does not reduce
what the mod owns, it just moves it, and it can widen the blast radius: the
copies were in the path of every human animation rather than one fragment.

What matters is **how much of the game's behaviour travels through code the mod
restated**. By that measure the second design is strictly better despite
claiming two names, and the first design was worse than 2.0.0 in one respect
that nobody would have predicted from its file list.

### Also fixed

A Vortex install test earlier in the day used `v2.1.0-dev.1.zip`, five hours
older than the working build and missing every fix, because `releases/` held 49
zips with nothing marking which was current. Everything superseded is now under
`releases/archive/`.

### Result: the second design works

**User reported**, installed through Vortex: "the beggar animation is back and
staggers and ragdolls firing as they should."

The additive deployment is confirmed working from a real user install: staggers
and knockdowns for both character sets, and no regression in unrelated
animations. The design is settled.

### Three observations about the beggar, which are not deployment issues

Reported alongside: the stagger did not fire on the beggar while he was in his
begging pose; a gallop knockdown left him standing and walking away rather than
returning to begging; and after a reload neither reaction fired on him at all.

None of these is about the animation layout. Taken in turn.

**Reactions not firing while he is in the begging pose.** The detection log
shows the mod does see him. `IsInHorseFootprint` only logs when its test
passes, and this run logged 53 accepted candidates against 14 impacts. The
candidates immediately before the beggar tests carry `dz=-0.48`, `-0.76` and
`-0.72`, against a typical `-0.04` to `-0.14` for a standing NPC, which is what
a kneeling one looks like: his origin sits much lower.

`HorseMaxVerticalDiff` is 2.35 so the height is not what rejects him. The
narrow gate is `HorseHalfWidth = 0.35`, a footprint 0.7 m wide in total, and
`HitCooldownMs = 3000` accounts for most of the 53-to-14 gap because an NPC
stays inside the footprint for many ticks after being hit.

This looks like the same defect already recorded twice this session: reactions
being eaten across all three speed tiers, and a gallop impact once reporting
walking speed. It belongs to that investigation, not to this one.

**Knocked down, then walking away instead of resuming.** Almost certainly
correct behaviour rather than a bug. The vanilla `Hit` state posts
`daycycle:restartRequest`, which is precisely "abandon what you were doing".
An NPC ridden down at a gallop giving up on begging is what the game does to
its own NPCs.

**The stagger specifically not firing while he is mid-pose.** An NPC already
running an interactive action very likely cannot be given a second one.
`StartInteractiveActionByName` returns success either way, so this would look
identical to every other silent failure in this project. Untested, and worth
knowing before any attempt to "fix" it: refusing to interrupt a scripted
activity may well be the right behaviour.

All three are deferred to the reaction-reliability work, which is now the
largest open item in the project.

### Settings move to their own file

**User report**, after editing settings as a player would: "the actual settings
are really hard to find without ctrl-f."

Correct. The config table sat at line 119 of a 1,051 line file, behind 111 lines
of module documentation, inside a pak that has to be opened with 7-Zip first.

**A game-root .cfg is not available.** The engine ignores unregistered CVar
names in `user.cfg`, and this mod registers none. A `hcm_*` block left over from
1.x was found in `user.cfg` earlier and removed for exactly that reason: nothing
read it. Registering CVars from Lua was not attempted, and would still leave the
values in a file shared with graphics tuning.

Mod folders are mounted by their `.pak`, so a loose settings file beside it is
not read either. Whatever a user edits has to be inside the archive.

So: `Scripts/Startup/HorseCollisionMod_Settings.lua`, containing one table and
nothing else. Startup scripts load in name order and `.` sorts before `_`, so it
runs after the mod. `ApplySettings` merges it from the load screen, by which
point everything in that folder has executed.

The merge validates rather than copying. A key absent from `Config` is a typo,
since `Config` is the list of settings that exist, and a wrong type is a mistake
for the same reason. Both are rejected and named in `kcd.log`. A setting that
quietly does nothing is worse than one that visibly fails, and this project has
lost time to enough silent failures already.

Tested against LuaJIT with the engine globals stubbed: a changed value applies, a
one-letter typo is rejected without being added to Config, a string where a
number belongs is rejected, the real setting nearby is untouched, and an absent
settings file leaves the defaults alone.

### Settings cannot live outside the pak

**User report**: editing the deployed pak through 7-Zip gives a read-only error.

The cause is worse than the symptom. **Vortex deploys by hard link**, not by
copying:

```
\Users\...\AppData\Roaming\Vortex\...\mods\HorseCollisionMod_v2.1.0\Data\HorseCollisionMod.pak
\Games\Kingdom Come - Deliverance\Mods\HorseCollisionMod_v210\Data\HorseCollisionMod.pak
```

Reproduced with a hard link outside the game folder. 7-Zip rewrites an archive
by writing a temporary file and renaming over the original, which severs the
link:

```
7-Zip:  Everything is Ok      reports success
staging size : 22499          unchanged
deployed size: 22635          updated
linked names : 1              link destroyed
```

Vortex's staging copy keeps the original, so the next deploy or purge reverts
the change with no warning. The read-only error was the better outcome of the
two.

### user.cfg was a dead end, and the earlier note did not establish that

An earlier entry concluded the engine ignores unknown CVar names, based on a
`hcm_*` block that did nothing. **That block was in `Bin\Win64\user.cfg`, which
the same entry records as never being read at all.** A conclusion drawn from a
file the game does not load establishes nothing, and the question was still open.

Tested properly, from the `user.cfg` beside `system.cfg` that the game does
read:

```
CVar probe: hcm_speedgallop  ok=true value=nil   type=nil
CVar probe: hcm_test         ok=true value=nil   type=nil
CVar probe: sys_PakPriority  ok=true value=2     type=number
```

`System.GetCVar` works. The engine discards names it does not know. Settled.

### mod.cfg does not help either

The log carries `Config file mods/HorseCollisionMod_v210/mod.cfg not found!`,
which looked promising: a per-mod file in the mod folder, outside the pak.

The official modding guide is explicit about what it is for:

> Another optional file in the mod's root is "mod.cfg". When present, it will be
> loaded after "system.cfg", but before "user.cfg" [...] You can use the
> "mod.cfg" in simple mods when all you want to do is set some CVars.

It sets CVars, and it loads before any Lua runs, so a mod cannot register its
own names first. Combined with the probe above, it cannot carry mod settings.

There is also no file API: `io` appears nowhere in the game's own Lua, and
nothing in `System.*` reads a file.

### Conclusion

Settings have to be inside a pak, which makes editing them a mod-manager
problem rather than something this mod can design around. Every KCD mod with
in-pak configuration has it. What remains is documenting the workflow that
actually works instead of the one that silently loses changes.

### Correction: the read-only error was a nested archive, not the hard link

The previous entry blamed Vortex's hard-link deployment. That was wrong, and the
user's objection was the right one: editing mod settings is a basic thing that
works for other mods, so an explanation that made it impossible was suspect.

Tested rather than assumed this time.

**The deployed pak is writable.** Attributes are `Archive`, not `ReadOnly`, and
it opens `ReadWrite` with no error while Vortex is running.

**7-Zip cannot update an archive nested inside another archive.**

```
A: update Data/HorseCollisionMod.pak INSIDE the release zip
     Error: cannot open file / The system cannot find the path specified

B: extract that pak, then update it standalone
     Everything is Ok
```

That is the read-only error. Opening the downloaded zip and going into the pak
inside it is the obvious thing to try, and it cannot work. Nothing to do with
Vortex, hard links, or the settings living in a pak.

**What the hard link actually costs.** It is real but secondary: an archive tool
replaces the pak rather than editing it in place, so the deployed and staging
copies come apart. Editing the staging copy and redeploying keeps them together.
The earlier claim that the next deploy "silently reverts the change with no
warning" was asserted without testing what Vortex does on external changes, and
should not have been stated as fact.

**What was right.** `user.cfg` and `mod.cfg` genuinely cannot carry mod settings,
both established by probe and by the official modding guide. Settings do have to
live in a pak. That part stands; the conclusion drawn from it did not.

The general failure: an explanation was built on the first plausible mechanism
found, and the far simpler one was never tested. A counter-example from ordinary
use, in this case that people edit mod settings all the time, outranks an
analysis that says they cannot.

### Settings cannot leave the pak, and here is every route that was tried

The question was whether a player could change settings from a plain text file
rather than an archive. Six routes, all tested rather than reasoned about.

| Route | Result |
| --- | --- |
| Unregistered CVar names in `user.cfg` | discarded by the engine |
| `System.SetCVar` creating a name | not available |
| `mod.cfg` | CVars only, and loads before any Lua |
| `exec` called from Lua | **works**, not cheat gated, reaches the mod folder |
| The console expression prefix inside a cfg | not honoured |
| A file API in Lua | `io` does not exist |

**`SetCVar` cannot create a name.** Reading back a name it had just set returns
nil, while the same call against `log_Verbosity` reads back 4. So the call
works and creation is what is unavailable.

**`exec` was the surprise, and it works.**

```
[CONSOLE] Executing console command 'exec Mods/HorseCollisionMod_v210/settings.cfg'
Executing console batch file (try game,config,root): "settings.cfg" found in game/ ...
[Warning] Unknown command: hcm_probe_value
```

`System.ExecuteCommand` runs it, it is not cheat gated, and it finds a file in
the mod folder outside any pak. It just has nothing useful to carry: a cfg run
this way is a batch of CVar assignments, and the mod cannot have CVars.

**The expression prefix does not work in a cfg.** `wh_con_expr_prefix` reads
`!`, and neither `!` nor `#` reached Lua from the file. The log warns about the
unknown CVar name on the first line and says nothing at all about the two
prefixed lines, so the batch parser handles `name = value` and ignores the rest.
The prefix works on the interactive and remote console, not here.

### Where that leaves settings

Inside the pak, in `Scripts/Startup/HorseCollisionMod_Settings.lua`, edited with
an archive tool after the mod is installed. That works and is what the README
documents.

The original complaint had two halves and both are addressed: the settings were
hard to find, which the separate file fixes, and editing them appeared to fail,
which was an archive nested inside the downloaded zip rather than anything about
the design.

### A correction in dev_console.py

Its comment credited `sys_DevMode = 1` for making the console evaluate a leading
`#` as Lua. `sys_DevMode` is not a CVar in this build. The remote console
accepts `#` regardless, separately from `wh_con_expr_prefix`, which reads `!`
and governs the in-game console. The behaviour was right and the explanation was
invented.

---

## Reaction reliability: the accepted impacts are censored at the footprint edge

The diagnostic build was not the one installed for this session, so there are no
`Miss` lines. The build that ran still logs accepted footprints and impacts, and
those alone carry a signal.

**Session totals**: 143 footprint accepts, 60 impacts, 25 staggers.

The gap from 143 to 60 is the per-victim cooldown. An NPC stays inside the
footprint for several ticks at 20 Hz, so one impact accounts for several
accepts. Staggers equal Walk impacts exactly, 25 and 25, so the stagger path
fires on every walk-tier impact it is given.

### Both footprint dimensions are clipped at their limits

```
lateral   median 0.16   90th 0.30   max 0.35     limit HorseHalfWidth   0.35
forward   min  -0.17    median 0.93  max 1.39    limit 1.05 + sweep <= 1.40
```

Neither distribution tails off. Both stop dead at the configured limit, which is
what a censored sample looks like: contacts beyond the boundary exist and are
being rejected, so the recorded maximum is the boundary itself rather than the
largest real value.

Ten percent of accepted impacts sat within 0.05 m of the lateral edge. A
distribution pressed that hard against a limit usually has mass on the other
side of it.

This matches the prediction made when the footprint was narrowed for 2.0.0-rc.2:
replaying 103 impacts through the new shape accepted 40, and the note recorded
at the time was that if genuine contacts started being missed, half-width was
the first value to relax.

### Gallop is under-represented

```
Walk    25 impacts   1.90 to 3.98
Trot    28 impacts   4.62 to 8.42
Gallop   7 impacts   8.89 to 10.75
```

The session was described as making every kind of impact on every kind of NPC,
which does not fit 7 gallops against 53 at lower tiers. Two candidates, and the
diagnostic build separates them: gallop contacts are being rejected by the
footprint more often, since a faster approach crosses the corridor in fewer
ticks, or they are landing but being recorded at a lower tier because the speed
sampled after the collision is lower than the speed that caused it.

The 8.42 to 8.89 hole around `SpeedGallop = 8.5` is the dead zone already
recorded under tuning, not a new finding.

### Not yet evidence

Every number here comes from impacts that were accepted. The rejected ones are
what the question is about, and they are exactly what this log cannot show. The
diagnostic build names them.

### The diagnostic build errored on every tick

**User report**: the game hung on the first run, and on the second nothing
worked and the console filled with errors.

`kcd.log` carried the mod's own handler 125 times:

```
[HorseCollisionMod] CRITICAL ERROR IN UPDATE TIMER:
    scripts/startup/horsecollisionmod.lua:0: [Error] Lua error.
```

`LogRejection` was inserted at line 262 and calls `GetTimeMs()`, which is
declared `local function` at line 284. A `local function` is visible only from
its declaration onward, so the call resolved the name as a global, found nil,
and threw. Every tick, for every rejected candidate.

Two things made it expensive to notice. It is valid syntax, so the LuaJIT parse
in `build.ps1` accepted it. And the failure surfaced through the mod's own error
handler as a generic Lua error with no line number, because the engine needs
`-lua_storedebug 1` for that.

The functions now sit below the helpers they use.

`build.ps1` gained a check for it: for every `local function`, any call to that
name above its declaration fails the build. Verified by reintroducing the bug
and watching it fail:

```
[LINT] HorseCollisionMod.lua line 221: GetTimeMs used before its declaration on line 224
```

This is the same class as `NPC = CreateAI(NPC_x)` copying fields: a language
rule about when a name refers to what, invisible at the call site.

## Reaction reliability: the tier is chosen from a speed the impact already destroyed

**Hypothesis going in**: reactions fail to fire because a candidate is dropped
silently somewhere between `GetEntitiesInSphere` and `TriggerCollision`. Eight
drop points were instrumented with `LogRejection`, plus a ten-sample speed
history so the speed at impact could be compared against the speed just before
it.

**User report**: reinstalled after the crash, rode around the city making every
kind of impact on every type of NPC.

`kcd.log` from that session, 2000 mod lines:

| Outcome | Count |
| --- | --- |
| Miss not-human | 1783 |
| Footprint pass | 83 |
| Miss outside-footprint | 65 |
| Impact | 25 |
| Miss cooldown | 4 |
| Miss no-actor | 2 |
| Miss dead | 1 |
| Miss below-walk-speed | 0 |

The hypothesis was wrong. Nothing is being dropped silently.

The 1783 not-human rejections are all `AudioAreaRandom`, `BasicEntity`,
`TagPoint`, `AudioAreaAmbience` and similar. No NPC appears among them, so the
human filter is not the fault. The names that look like NPCs in that list, such
as `rat_city_horseParkingSpot1` and `tp_rat_cityWalk16`, are Rattay location
markers.

The gap between 83 footprint passes and 25 impacts is an artifact of the
diagnostic, not a defect. `LogRejection` throttles to one line per NPC per
second, and `HitCooldownMs` is 3000, so one NPC struck once and then walked
alongside the horse passes the footprint repeatedly while logging at most one
cooldown line per second.

**The actual defect is in tier selection.** Comparing the speed each impact was
classified on against the peak of the previous ten samples:

| tier assigned | speed | peak | tier the peak implies |
| --- | --- | --- | --- |
| Walk | 3.67 | 6.92 | Trot |
| Walk | 3.76 | 10.58 | Gallop |
| Walk | 4.12 | 10.70 | Gallop |
| Trot | 5.57 | 10.64 | Gallop |
| Trot | 6.62 | 10.70 | Gallop |
| Trot | 7.13 | 12.73 | Gallop |
| Trot | 7.97 | 10.38 | Gallop |
| Trot | 8.13 | 12.73 | Gallop |

Eight of 25 impacts, 32%, were classified below the speed the horse was
carrying. Counting by true tier: 11 impacts happened at gallop speed and 6 of
them, 55%, did not produce a gallop reaction.

Two of those read `Walk` while the horse had been at 10.58 and 10.70 m/s. That
is the exact report that opened this investigation, reproduced with figures: a
gallop impact reporting walking speed.

**Cause**: the horse decelerates on contact. Detection samples velocity once
per 100 ms tick, and by the time the tick that notices the victim reads
`GetVectorLength(velocity)`, the collision has already bled speed off the horse.
The instantaneous speed at detection is a measurement taken after the event it
is supposed to describe.

**Why this reads as "the reaction did not fire".** Every one of the 6 walk-tier
staggers returned `ok=true err=nil`, so the animation path is not failing. A
gallop impact misclassified as Walk plays a small stagger instead of a
knockdown. From the saddle that is indistinguishable from nothing happening,
which is why the defect was reported as reactions not firing rather than as
reactions firing at the wrong strength.

**Two cautions for the fix.** `peak` is not simply the right value to
substitute. One impact logged `speed=15.63`, and two logged `peak=12.73`, all
above the 10.81 m/s ceiling of the gallop plateau, so the peak carries physics
spikes that instantaneous sampling does not. And the history window is ten
samples, a full second, long enough that a rider who gallops up and deliberately
slows to nudge someone would still be charged gallop.

A shorter window is the direction: the speed that matters is the one on the tick
before contact, not the highest of the last second.

**Not the fault, ruled out this session**: the human filter, the dead check, the
below-walk-speed gate (zero rejections), and the footprint on its lateral axis.
The footprint still rejects NPCs standing directly ahead at `fwd` 1.7 to 2.4
with `lat` under 0.35, which is a separate question about front reach and is not
what causes a reaction to be missed, since the horse closes that distance within
one or two ticks.

## Reaction reliability: the correction holds, and the deceleration is one tick wide

**Hypothesis**: scoring a collision on the peak of the last three ticks instead
of the speed sampled when the victim is noticed removes the tier
misclassification. The impact line now prints the scored speed, the sampled
speed and the full ten-sample trail, so the width of the deceleration can be
read directly rather than guessed at.

**User report**: installed and rode around.

31 impacts, against 25 in the previous session.

**No impact was misclassified.** The correction changed the tier on three of
them:

| trail, last three samples | sampled | scored | tier without the fix | tier with it |
| --- | --- | --- | --- | --- |
| 10.57 10.67 5.91 | 5.91 | 10.67 | Trot | Gallop |
| 10.08 10.55 4.71 | 4.71 | 10.55 | Trot | Gallop |
| 4.04 4.50 4.07 | 4.07 | 4.50 | Walk | Trot |

The two gallop cases are the defect that opened this investigation, caught in
the act. Both would have delivered a trot knockdown for a 10.6 m/s impact.

**The deceleration is one tick wide, sometimes two.** Every trail shows the same
shape: speed flat, then a single sample collapsing.

```
[10.68 10.63 10.68 10.74 10.73 10.68 10.58 10.57 10.67 5.91]
[10.71 10.74 10.75 10.76 10.76 10.74 10.10 10.08 10.55 4.71]
[ 2.77  2.82  2.94  3.00  3.59  4.49  5.47  6.32  6.16 4.75]
```

The largest single-tick loss was 5.84 m/s, from 10.55 to 4.71 in 100 ms. Only
the third trail above spreads the loss across two samples. Nothing observed
needs more than two, so `ImpactSpeedSamples = 3` covers the deceleration with a
tick of margin, and there is no case for widening it.

The short window also proved necessary rather than merely cautious. One trail
runs `[4.53 3.76 3.07 2.82 2.78 2.88 3.10 3.93 4.94 5.46]`: a rider who slowed
from 4.53, then accelerated back into the victim. Scored on three samples this
is 5.46, which is correct. Scored on the full second it would still have been
5.46 here, but the 4.53 sits close enough to the front of the window to show how
a genuine deliberate slowdown would be charged the earlier, higher gait.

`MaxImpactSpeed` never bound. The highest speed recorded was 10.78, inside the
gallop plateau, and the 15.63 and 12.73 spikes from the previous session did not
recur. The cap stays as insurance, since it costs nothing and a spike scales
knockback force.

**The footprint is not a source of missed reactions.** Of 99 rejections:

- 64 were beside the horse, past the 0.35 lateral half-width. Correct.
- 34 were dead ahead past the front reach, median 2.23 m. **30 of those 34 were
  followed by an impact within a few ticks**, so they are early detections
  inside the 2.5 m sphere that convert once the horse closes. The remaining 4
  are consistent with an NPC stepping aside. Front reach needs no change.
- 1 was behind the horse.

**Everything downstream is clean.** Five walk-tier impacts produced five
staggers, all returning `ok=true err=nil`. The one `below-walk-speed` rejection
scored 0.75 m/s on a nearly stationary horse, which is correct. The gap between
91 footprint passes and 31 impacts is the per-victim cooldown absorbing about
two follow-up ticks per impact while the horse rides past, and those are
invisible in the log because `LogRejection` throttles to one line per NPC per
second.

**Still open**: kneeling NPCs detected without producing a reaction. Nothing in
this session identifies a kneeling victim, so it needs a test aimed at it.

## Kneeling NPCs react

**Hypothesis**: a kneeling NPC sits low enough, or is offset far enough from the
horse origin, that the 0.7 m wide footprint rejects them, so they are detected
without producing a reaction.

**User report**: tested against the beggar in the same session as the
impact-speed verification. He staggered at walking pace and ragdolled at the
higher tiers.

The footprint accepts a kneeling target as it stands, and `HorseHalfWidth` needs
no change. The earlier report of kneeling NPCs producing no reaction is
explained by the tier misclassification rather than by detection: an impact
scored a tier too low plays a smaller reaction, and on a target already close to
the ground a stagger is easy to miss entirely.

That makes every symptom filed under reaction reliability the same defect. The
walk tier, the gallop-reporting-walk case and the kneeling case all resolve to
scoring a collision on the speed left after the collision.

## 3.0.0 verified in game

**Hypothesis**: with collisions scored on the peak of the last few ticks, every
tier plays the reaction its speed calls for, and the missed reactions reported
across three sessions are gone.

**User report**: all animations firing, no dropped collisions, no mismatched
reactions.

That closes the reaction reliability defect. All three reported symptoms, the
missing reactions across every tier, the gallop impact reporting walking speed,
and the kneeling NPC producing nothing, were one cause: a collision scored on
the speed left after the collision had already slowed the horse.

The build carries `DiagnoseMisses` off, so this was the first session tested
with the shipping log volume rather than the diagnostic one.

## Publishing 3.0.0: the mod file id resolves, the upload path is still untested

**Hypothesis**: addressing the mod file by its own id, `-ModFileId 7863762`,
resolves without the mod-file-version hop, and 3.0.0 has not reached the page.

Dry run against the live mod page, no writes:

```
mod:      Horse Collision Mod [9869834848546]
mod file: HorseCollisionMod [7863762]
versions: 1 (0 archived)
```

The id resolves and still passes the ownership check against `/mods/{id}/files`,
so the direct id costs nothing that the `?file_id=` lookup provided. No
duplicate-version message means 3.0.0 is not published; the single listed
version is 2.0.0 from 2026-08-26, unchanged since the first dry run.

`archive_existing_file` is a field on the create-version request rather than a
call of its own, so archiving 2.0.0 happens in the same request that publishes
3.0.0. There is no window in which the page lists nothing, which is the failure
that would matter on a first use of `-ArchiveExisting`.

**Still untested**: `POST /uploads`, the presigned `PUT`, `finalise`, the
availability poll and `POST /mod-files/{id}/versions`. Every one of them runs
for the first time on the 3.0.0 release, and the flow prints an upload id on a
post-upload failure so `-ResumeUploadId` can retry without re-sending the zip.

## 3.0.0 published: the upload path works, and three things it got wrong

First real use of `tools/publish_nexus.ps1`. Every call that had never run
before ran: `POST /uploads`, the presigned `PUT`, `finalise`, the availability
poll, `POST /mod-files/{id}/versions` with `archive_existing_file`, and the
changelog append. The version is live and a later dry run reports `versions: 2
(1 archived)`, so archiving 2.0.0 in the same request as publishing 3.0.0 did
what the spec says it does.

Three defects, none of which a dry run could have found, because all three sit
past the point a dry run stops.

**The upload stopped on a prompt.** `Invoke-WebRequest` on Windows PowerShell
5.1 parses the response through the Internet Explorer engine, and asks the
operator to confirm before doing so when IE has no first-run configuration:

```
Security Warning: Script Execution Risk
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help
(default is "N"):
```

Answering `N`, which is the default, would have failed the upload after the
session was already created. `-UseBasicParsing` skips the parse and the prompt.
The call is a `PUT` to S3 whose response body is not read at all, so nothing is
lost by never parsing it.

**The published version id printed empty.** The create-version response is
`CreateModFileVersionSuccess`, which is `{ file, version }`, and the id is on
`data.version.id`. The script read `data.id`, which does not exist. Cosmetic in
that the publish had already succeeded, but the printed id is what a failed run
would be diagnosed from.

**The Files tab entry published blank.** `description` on the create-version
request is the text shown under the file on the mod page's Files tab, and is
separate from the mod's front-page description that `nexus_description.txt`
holds. The parameter existed and nothing passed it.

### The Files tab description cannot be added after the fact

`/mod-file-versions/{id}` is GET only. There is no `PATCH` or `PUT` on a mod
file version anywhere in the v3 spec, and `/mod-files/{id}/versions` only
creates. So a description missing at publish time can be added only through the
browser, which is the only route left for 3.0.0's.

The spec declares no `maxLength` on the field, so the API accepts more than the
page keeps. The 255 character limit is the site's, and the overflow is lost
without an error.

Now `releases\file-description-<version>.txt`, read by convention without a
flag, mirroring `notes-<version>.md` for the changelog. The report prints the
length before the upload, and `pre_release_check.py` fails a release whose
description file is missing, empty or over 255, because a blank entry is
invisible in the report of a run that otherwise succeeded.

## Next: Phase 2, starting with armor weight

Everything in Phase 2 depends on knowing what the victim is wearing, so that is
the first piece. Groundwork already established, carried forward so it is not
re-derived. All four code references below were re-checked against the 3.0.0
source.

**Where it plugs in.** `TriggerCollision` already computes a `combatScale`
multiplier and passes a per-tier stamina cost into `DrainHorseStamina`. Armor
scaling is a second multiplier applied at the same point, and `Ragdoll` already
takes an `impulseScale` argument for the knockback side. Neither needs
restructuring.

**Reading the armor.** Entities carry an `inventory` extension, confirmed when
enumerating a live horse's fields. Vanilla scripts use
`inventory:GetCurrentItem`, `GetItemByClass`, `FindItem` and `GetCountOfClass`.
What is not established is how to get from an equipped item to its weight, and
whether a per-actor aggregate exists rather than having to sum pieces.

**Where the data lives.** `Data/Tables.pak` carries
`Libs/Tables/item/armor.xml` at 479 KB, plus `armor_archetype.xml`,
`armor_type.xml` and `armor_subtype.xml`. Those are readable with the
`read_pak_entry` helper in `build_adb.py`, which handles the backslash local
headers that break Python's `zipfile`.

**Reference material**: `references/Nexus_KCD_Wiki/RPG_params_in_KCD.md` and
`RPG_stats_in_KCD.md`, plus `references/kcd-documentation/` for the Soul and
Inventory ScriptBind pages.

**The trap to avoid**, given this project's history: a call that returns a value
is not proof the value is right. Log the weights read off real NPCs and check
them against the tables before building any scaling on top.

## Phase 2: where armor weight and body mass actually live

**Hypothesis**: `Libs/Tables/item/armor.xml` carries the weight of each armor
piece, so scaling knockback by what a victim wears means reading that table.

Wrong on the first half. `armor.xml` has 28 columns and none of them is weight.
What it carries is `slash_def`, `stab_def`, `smash_def`, `noise`, `max_status`
and `str_req`, keyed by `item_id`.

**Weight is on `Libs/Tables/item/pickable_item.xml`**, which every item joins
to by `item_id`, alongside `price`, `model` and `material`. All 796 rows in
`armor.xml` join to it and all 796 have a weight, so the join is total and
needs no fallback. `item.xml` is only a name and category lookup, three columns
wide.

Per-piece weight by armor type, from that join:

```
horse_saddle     n=20    20.00 - 35.00   mean 27.75
chain            n=31     1.00 - 21.00   mean 11.83
horse_bridle     n=12     2.00 - 20.00   mean  7.50
heavy leather    n=35     4.00 -  9.00   mean  6.97
plate            n=127    0.00 - 12.00   mean  6.30
light leather    n=24     0.00 - 10.00   mean  4.46
horse_shoe       n=4      4.00 -  4.00   mean  4.00
cloth            n=329    0.50 - 14.00   mean  3.48
default cloth    n=159    0.00 - 17.90   mean  3.46
shoe             n=32     2.00 -  4.80   mean  2.62
spur             n=5      1.00 -  1.00   mean  1.00
decorated        n=18     0.00 -  0.50   mean  0.08
```

Two things in that table matter for scaling. **Chain outweighs plate per
piece**, mean 11.83 against 6.30, so a rule that treats plate as the heavy end
of the scale would be backwards. And **horse tack is filed as armor**, so any
sum over a target's armor must exclude saddle, bridle, shoe and spur or a
mounted victim reads as heavier than a knight.

`str_req` on `armor.xml` is a designer-set strength requirement and tracks
heaviness independently of the weight column. It is a candidate proxy worth
comparing against summed weight before either is chosen.

### Body mass comes from the soul archetype, not the inventory

`Libs/Tables/rpg/soul_archetype.xml` carries `normal_body_weight` across 16
archetypes:

```
NPC 160    NPC_Female 120    NPC_Child 80    Hero 160    Hero_female 120
Horse 1000    Cow 400    Boar 300    Pig 250    RedDeer 185    DeerDoe 165
Sheep 140    Dog 50    RoeBuck 27    Hare 6    Hen 2
```

This is the mass term Phase 2 needs for the target, and it requires no
inventory enumeration at all. It also supplies the ratio the momentum work
depends on: a horse at 1000 against an adult NPC at 160 is 6.25 to 1, and
against a child at 80 is 12.5 to 1. The same table carries `base_stamina`,
`body_base_armor` and `unarmed_attack_base`, which Phase 3 will want.

`normal_body_weight` also appears in the decompiled binary as
`NormalBodyWeight`, so the engine reads it rather than it being unused data.

**Not this**: `equippable_item.xml` has an `rpg_buff_weight` column. That is a
weighting factor on buff selection, not a mass, and the name invites exactly
the wrong join.

**Still open**: nothing above is reachable from Lua yet. The tables are build
time data, and `build_adb.py` already reads paks, so an item-name to weight
table can be generated into the mod. What that does not answer is which pieces
a given NPC has equipped at the moment of impact, which is the inventory
question the previous entry left open. The CryEngine `inventory` ScriptBind has
15 methods and none of them returns a weight, so the equipped set has to come
from `GetCurrentItem`, `GetItemByClass` or an equivalent KCD-specific bind, and
that is the next thing to establish.

## Roadmap ordering: the native path already carries damage and crime

**Question**: does the roadmap order corner the project, specifically by
building armor scaling in Phase 2 before the damage and crime work in Phases 3
and 4.

It does, and the reason is in vanilla's own behavior tree rather than in
anything the mod does.

### What vanilla does with the collision hit

`Libs/AI/final/sb_switch_hitreactions.xml`, inside `Scripts.pak`, branches on
`$hitReaction.hitType == $enum:HitReactionType.Collision`. Inside that branch it
resolves the horse's `rider` link into `riderPlayer`, and when that is the
player it sends:

```
<InstantSendMessageToNPC target="this.id" type="combat:hit"
  values="attacker($__player), strength($hitReaction.hitStrength),
          hitType($enum:HitReactionType.Melee), real(true)" />
```

`real(true)`, attributed to the player, carrying the strength the collision
arrived with. `SendHitReaction` already sends
`hitType(HitReactionType.Collision)` with the horse as attacker and a per-tier
`HitReactionStrength`, so the mod is already feeding that path: MinorInjury at
trot, MajorInjury at gallop.

Two roadmap items therefore describe wiring that already exists rather than
work to be built. Phase 3's native blunt damage and Phase 4's trampling crime
both hang off a real, player-attributed `combat:hit` that the mod already
causes.

`CollisionVelocityDeltaToDmgR = 0.25` in `Libs/Tables/rpg/rpg_param.xml`
confirms collision velocity to damage is a parameterized vanilla concept, not
something the mod would be introducing. `HorseMoraleToThrowOffRider = 0.2` and
`HorseMountMaxRelativeEncumberance = 1.5` sit in the same table for the Phase 3
Horsemanship and barding work.

### The double-counting trap

KCD resolves a real hit against the target's armor itself, through `smash_def`
on `armor.xml` and `body_base_armor` on `soul_archetype.xml`. Since the mod
already causes a real hit, **armor mitigation is already being applied
downstream of the mod, on every trot and gallop impact.**

Phase 2 as written says "unarmored targets take proportionally heavier
knockback" and "heavily armored targets are moved less". Built as a general
"armor scales the outcome" rule, that stacks a second armor model on top of the
one the engine is already applying, and the error would only show up as
mistuned damage long after the scaling was written.

The boundary that avoids it:

- **The engine owns armor against damage.** Nothing in the mod should reduce
  damage by armor, and `hitStrength` should stay chosen by speed alone, because
  the engine resolves that strength against armor after receiving it.
- **The mod owns the physical response.** The `impulseScale` passed to
  `Ragdoll`, and the horse's side of the impact, its stamina cost and its
  momentum loss. The engine derives none of those from armor, so scaling them
  by the victim's mass and armor weight adds something rather than duplicating
  it.

### What this changes about the order

The cheapest step with the largest effect on the rest of the roadmap is not
building armor scaling. It is establishing, in game, what the existing build
already does: whether damage lands, whether injuries and bleeding follow,
whether a bounty is registered, and whether armored targets already take less.
That test needs no new code, and its result decides whether Phases 3 and 4 are
mostly verification or mostly construction.

**Unverified until that test runs**: everything above is read out of the
behavior tree and the tables. That the tree sends `real(true)` is not proof the
damage lands, that the crime system accepts it, or that armor mitigates it.

### A note on the carried-item gap

Phase 1's remaining carried-item work needs `sb_combat.xml` shipped for its
`dropItems` tree. `sb_switch_hitreactions.xml` is 132,889 bytes and
`sb_combat.xml` is the same order, with no additive path for either. Shipping
one reintroduces exactly the whole-file conflict surface that 3.0.0 removed, in
exchange for a cosmetic fix. It should stay parked unless an additive approach
to behavior trees appears.

## The settings file was never reaching the running game

**Hypothesis**: the inner development loop can be one command instead of two,
because `dev_deploy.ps1` can determine which half of the mod an edit belongs to
by comparing the files it would copy.

The consolidation itself was routine. What it exposed was not.

`Copy-LooseFiles` pushed `src/HorseCollisionMod.lua` and the four Mannequin
databases, and nothing else. `HorseCollisionMod_Settings.lua` was never among
them, and it is a Startup script in its own right rather than something the mod
script pulls in. The first `-Reload` run reported:

```
[DEPLOY] updated HorseCollisionMod_Settings.lua
```

That was the first time the file had ever been placed loose. Every settings edit
made during a live session up to this point changed a file the running game was
not reading: at `sys_PakPriority = 0` the loose mod script was picked up on
reload while the settings came from the pak, so the packed value stayed live
while the edited file sat on disk looking applied.

Two consequences worth carrying:

- **`lua_reload_script` reloads one file.** Reloading the mod script alone
  leaves `HorseCollisionModSettings` holding whatever the last executed copy of
  the settings file defined. The reload sequence now re-executes the settings
  file first, since `ApplySettings` reads that global.
- **Any tuning conclusion drawn from a settings change made mid-session, without
  a game restart, is suspect.** The change did not take effect. Conclusions from
  values that shipped inside a build are unaffected, since those were packed.

`--reload` and `--anim-reload` in `dev_console.py` were also mutually exclusive
in the argument chain, so a change touching both halves silently reloaded only
the Lua. They now compose, Mannequin first.

**Verified in game**: console reload against a running save returned

```
[log] [HorseCollisionMod] Load screen ended. v3.1.0-dev.2 initializing physics timer loop 2
```

and a Lua query confirmed the loose settings are the ones in effect:
`telemetry=true knockback=50 gallop=8.5 settingsGlobal=true`.

## Phase 2 verification: damage lands, nothing bleeds, and one impact cost nothing

**Hypothesis**: vanilla re-sends a player-ridden collision as a real,
player-attributed `combat:hit` carrying this mod's `hitStrength`, so the current
build already causes damage, injury and a crime without any new code. The
impact telemetry added in 3.1.0-dev.2 shows what each impact actually costs.

**User report**: "they all got knocked down, no bounty."

Four impacts. `speed` is the peak-window value that selects the tier and scales
knockback; `sampled` is the instantaneous reading on the detecting tick.

| Victim | Tier | strength | speed | health | t+500ms | t+3000ms |
| --- | --- | --- | --- | --- | --- | --- |
| `rat_woman34` | Gallop | 6 | 10.75 | 96.6113 | +0.0000 | +0.0000 |
| `rat_man95` | Gallop | 6 | 10.75 | 100.0000 | -19.3485 | -19.3485 |
| `rat_guard18` | Trot | 5 | 6.96 | 100.0000 | -3.2593 | -3.2593 |
| `rat_guard18` | Gallop | 6 | 10.73 | 96.7407 | -16.9866 | -16.9866 |

Horse stamina drained 45 at trot and 75 at gallop on every impact, matching the
configured values.

### Damage lands

Three of the four impacts cost health, with no damage code in the mod. Phase 3's
"apply native blunt damage on high-speed impacts" is verification rather than
construction, as the behavior tree reading predicted.

The step from `MinorInjury` to `MajorInjury` is not proportional to speed: the
same guard lost 3.26 at trot and 16.99 at gallop, a fivefold difference across a
tier boundary the horse crosses often.

### Nothing continues after the hit

Every t+3000ms sample equals its t+500ms sample exactly. Damage resolves inside
half a second and then stops. At these magnitudes the collision does not start
bleeding or any other continuing effect, so the injury consequences Phase 3
assumes do not follow from the hit on their own.

### The armor reading is not yet usable

The armored guard lost 16.99 at gallop against 19.35 for the unarmored man at
the same strength and within 0.02 m/s of the same speed. That is mitigation of
about 12 percent, which is far less than a full plate harness against a horse
should absorb, and it rests on one sample each.

It also cannot be separated from the fourth impact, which is the real finding:

### One gallop impact cost nothing at all

`rat_woman34` was struck at `strength=6` and `speed=10.75`, the same as
`rat_man95`, and lost no health whatsoever. Not a small amount. Zero, at both
samples.

An impact that silently costs nothing is indistinguishable from armor working
very well, so this has to be explained before any number above is trusted. The
candidates, in order of how well they fit what is already known:

- **The `combat:hit` was never delivered.** Brain messages sent with
  `XGenAIModule.SendMessageToEntity` are documented in this project as
  unreliable, and handlers declared `Atomic="true"` drop messages while busy.
  There is no return value to check, so a dropped message looks exactly like
  this.
- **The vanilla branch did not resolve `riderPlayer`.** The conversion to a real
  hit happens only inside the branch that resolves the horse's `rider` link to
  the player. A failure there produces a reaction with no damage, which is what
  the log shows.
- **A female-specific path.** `wh_female_fragmentids.xml` needed patching for
  the animation work, so the female side of the data is known to be less
  complete than the male side. `normal_body_weight` is 120 against 160, which
  would change damage but could not zero it.

The first two would apply to any target and would appear at random, which makes
the reliability question prior to the armor question. Sampling one impact per
target cannot tell a mitigated hit from a dropped one; repeated impacts on the
same target can.

### The knockdown separates the mod's half from the engine's

All four victims were knocked down, `rat_woman34` among them, and she lost no
health at all. The impulse comes from the mod's own `Ragdoll` call and does not
depend on the `combat:hit` reaching anything. The damage is resolved by the
engine after that message is handled. On the same impact one landed and the
other did not, which places the failure in the message path rather than in
detection, tier selection, the footprint or the impulse.

It follows that **a knockdown is not evidence the hit was delivered.** A
reliability test has to read health; the reaction on screen looks identical
either way.

### No crime is registered

No bounty followed any of the four impacts, including the one that knocked down
`rat_guard18` at gallop.

Phase 4's trampling crime is therefore construction rather than verification,
which is the opposite of what the behavior tree suggested. A `combat:hit` marked
`real(true)` and attributed to the player is not on its own enough for the crime
system to register anything.

Two conditions were not controlled for and are worth eliminating before that is
settled: a crime generally needs a witness who reports it, and a non-lethal
outcome may not be a crime under the vanilla rules at all. Neither was varied
here.

### What is still unanswered

- Whether the zero-damage impact is a dropped message or something specific to
  the target. Repeated impacts on one target answer this; one impact per target
  cannot.
- Whether a crime registers when a collision is witnessed by a third party, or
  when it is fatal.

## A one-frame animation on the female get-up

**User report**: "after the woman get thrown ragdoll from trot, when shes
getting up I think there a single frame glitch animiation trying to fire. It
doesn't prevent her from finishing her natually getting up, but I think when the
impulse is finished and the NPC is snapping back it may be trying to load
something."

Noticed while running the damage reliability ride, and recorded without
interrupting it.

A single frame is the exact signature already documented for
`StartInteractiveActionByName`: a name that matches no `AnimationControlled`
fragment is accepted silently and aborts after one frame. That does not by
itself explain this one, because the trot tier calls `Ragdoll` rather than the
interactive action, so whatever fires here is either the engine's own recovery
or a reaction message arriving while the ragdoll is still resolving.

The female data is the side that had to be created rather than extended:
`wh_female_fragmentids.xml` declared no `AnimationControlled` fragment at all,
and the whole database block is the mod's. That makes it the first place to
look.

**Not yet connected to anything else.** The same session produced a female NPC
who took zero damage from a gallop impact. Two anomalies on the female path in
one session is worth noting and is not evidence they share a cause: the damage
path runs through a brain message and the animation path through Mannequin, and
they have no step in common.

Cosmetic, and it does not interrupt the recovery. Parked as a known issue.

## The damage half is reliable, and something else is also causing damage

**Hypothesis**: the zero-damage gallop impact means the `combat:hit` carrying
the damage is being dropped, which would make every armor reading untrustworthy.
Repeated impacts on a single target separate a dropped hit from a mitigated one,
because a knockdown looks identical either way.

**User report**: "I picked two NPCs and hit them at least 10 times or more."

Twenty-three trot impacts, twelve on `rat_woman35` and eleven on
`rat_refugee_Radan`, both unarmored.

| Target | Impacts | Landed | Zero | Mean | Min | Max |
| --- | --- | --- | --- | --- | --- | --- |
| `rat_woman35` | 12 | 12 | 0 | -4.7119 | -2.0293 | -9.9917 |
| `rat_refugee_Radan` | 11 | 11 | 0 | -4.2544 | -1.9449 | -6.5577 |

### The message is not being dropped

Every impact cost health. Twelve of them landed on a female target, so the
female path is not implicated either, and the animation twitch recorded in the
previous entry has no counterpart in the damage path.

The single zero on `rat_woman34` stands as an outlier. One event in twenty-seven
is not a mechanism, and chasing it further would cost more than it is worth
until it recurs.

### The variance is what actually blocks the armor question

At a fixed `strength=5` against unarmored targets the cost of an impact ranges
from 1.94 to 9.99, a fivefold spread. The armored guard's single trot impact
cost 3.26, which sits comfortably inside that range.

So the armor reading is still not usable, but for a different reason than
before. It is not that hits are being lost; it is that one sample cannot be
distinguished from the noise. Ten impacts on an armored target settle it.

### Health is lost between impacts, and the mod does not cause it

In 6 of 21 intervals the victim's health at the next impact was lower than where
the previous impact left it: 2.54, 4.58, 4.66, 4.75, 4.82 on
`rat_refugee_Radan`, and 4.47 on `rat_woman35`.

These are discrete steps roughly the size of a trot impact, not a continuous
trickle, and they appear in some intervals and not others. That rules out
bleeding, which is consistent with every 3-second sample matching its 500 ms
sample exactly across all 27 impacts recorded so far.

The first candidate is the mod's own `HitCooldownMs`. It gates the mod's
reaction to a contact, not the engine's handling of the collision, and vanilla
parameterizes collision damage on its own through `CollisionVelocityDeltaToDmgR`
in `rpg_param.xml`. A contact arriving inside the 3-second window would then
damage the target while producing no log line.

If that holds, **the mod is not the only thing damaging a trampled NPC**, and
every per-impact figure recorded so far understates what being ridden into
actually costs. It also means the cooldown does not do what its name suggests
from the victim's point of view.

## Armor barely matters, and the impulse is probably causing its own damage

**Hypothesis**: with the damage half shown to be reliable, ten or more trot
impacts on an armored target give a mean that can be compared against the
unarmored mean, and the comparison decides whether Phase 2 needs an armor
multiplier at all.

**User report**: "First I notice the same single frame glitch on the guard that
I did on the woman when the NPC is getting up after being ragdolled. On one of
the trots impacts, the guard did fall off stairs and the very last one he also
did as well... During the last few tros the guard was displaying a hurt
animation and will no longer move. In fact I've waiting a few minutes and hes
still doing the hurt animation in the same place he got up the last time I hit
him."

Eighteen trot impacts on `villageGuard`, against the twenty-three unarmored
impacts from the previous entry.

| Target | Impacts | Zero | Mean | SD | Min | Max |
| --- | --- | --- | --- | --- | --- | --- |
| Unarmored | 23 | 0 | -4.4931 | 1.64 | -1.9449 | -9.9917 |
| Armored guard | 18 | 1 | -3.8997 | 0.96 | -1.8464 | -6.0649 |

### The engine's armor mitigation is not measurable here

The armored guard takes 87 per cent of what an unarmored villager takes. The
difference is 0.59 against a standard error of 0.41, a ratio of 1.43, so it
cannot be separated from zero at this sample size.

That is not what a full harness against a horse should do. Whatever the engine
resolves through `smash_def` and `body_base_armor` for a collision-derived hit,
it is small enough that Phase 2 cannot rely on it as the reason not to model
armor. The scope boundary at the top of Phase 2 says the engine owns armor
against damage. That remains true in the sense that the engine does the
resolving, but it is doing very little with it.

### A second zero-damage impact, on a male target

Impact 8 in the sequence cost the guard nothing at both samples, at
`sampled=5.32` against the tier boundary at 4.5.

That makes two zeros in forty-five impacts, and the previous entry's conclusion
that the first was an outlier is wrong. It is a low-rate failure of roughly four
per cent, and it is not specific to the female path, since this one landed on a
male guard. Four per cent is small enough not to block the armor work and large
enough to matter to a player, so it stays open rather than closed.

### Fall damage is the better explanation for the delayed loss

The delayed loss recorded in the previous entry appeared again: 3.88, 2.43 and
4.26 across the guard's seventeen intervals, alongside 4.47, 2.54, 4.58, 4.66,
4.75 and 4.82 on the two unarmored targets.

Fall damage from the mod's own impulse fits better than the cooldown explanation
offered previously:

- The guard was seen falling down stairs on two impacts, which is direct
  evidence that the impulse produces falls with real height behind them.
- The magnitudes cluster tightly rather than tracking the wide spread of impact
  damage, which is what a fall from a roughly constant impulse would give.
- The loss lands after the 3000 ms sample. A ragdoll takes longer than that to
  resolve, and the engine plausibly applies accumulated fall damage when the
  actor is restored at the get-up rather than at the moment of landing.
- The one-frame animation happens at the get-up as well. Two effects appearing
  at the same point in the recovery is worth noting, though nothing beyond
  timing connects them yet.

NPC fall damage is otherwise close to unexercised in vanilla, since NPCs are
rarely thrown anywhere. That the mod is the thing exercising it would explain
why this has not been visible before.

**This changes the Phase 2 scope boundary.** If throwing a target damages it,
then scaling `impulseScale` by armor weight and body mass also scales damage,
and the clean split of the engine owning armor against damage while the mod owns
the physical response does not hold. The physical response feeds back into
damage.

Two small health regenerations were also recorded between impacts, +0.04 and
+0.05, so NPCs recover slowly on their own. Too small to affect any figure here.

## The get-up costs nothing, and the delayed loss is not a fall

**Hypothesis**: health lost between impacts is fall damage from the mod's own
impulse, applied when the ragdoll resolves and the actor is restored. Sampling
to 10 seconds should catch it, and the victim's height should show the fall.

**User report**: "I've done the first test with the flat ground but to be
compeltely honest I have no idea where I could test this. There aren't really
any stairs with engough space to hold my horse and not run into other people."

Twelve trot impacts on `rat_woman12` on flat ground, sampled at 500, 3000, 6000
and 10000 ms.

### Nothing happens after 500 ms

No impact changed the victim's health after the first sample. Not one of twelve,
out to ten seconds. Every figure at 3000, 6000 and 10000 ms equals the figure at
500 ms exactly.

The height readings also settle. `dz` at 500 ms runs -0.19 to -1.10, the victim
on the ground, and returns to within about 0.5 of the starting height by 3000 ms.
**The get-up is finished by three seconds**, which removes the reason for
believing the earlier samples were closing too early.

So the get-up applies no damage, and the delayed loss is not fall damage applied
at the end of a ragdoll. The hypothesis in the previous entry is wrong.

### The delayed loss is still there, and it is later than ten seconds

Two of eleven intervals lost health with no impact logged: 5.41 after the sixth
impact and 5.67 after the tenth. Both are larger than any of the twelve impacts
that were logged, and both land after the 10000 ms sample.

Across four rides the pattern holds at roughly one interval in five, with a
magnitude in the range of a trot impact or a little above.

### The next candidate is a contact the mod rejects

The footprint is 0.7 m wide and the mod discards anything outside it, but the
engine resolves its own collisions regardless, and vanilla parameterizes
collision damage through `CollisionVelocityDeltaToDmgR` in `rpg_param.xml`.
A graze while riding away or turning around would then damage the target with no
`Impact` line written.

That fits the timing, which is arbitrary rather than tied to the recovery, and
the magnitude, which is in the range of a real collision. It also predicts
something specific: **health should drop on a pass that produces no log line at
all.** That needs no stairs and no elevation.

### Moving an actor from the console does work, and fall damage is real

An earlier reading of this test was wrong and is corrected here.

`SetWorldPos` raised the player's horse 12 m. The height read back afterwards
was identical to the starting height, which was taken as the engine reverting
the move, in line with the limitation already recorded for `AddImpulse`. It was
not. The horse had already fallen and landed on the same ground, so the sample
was taken after the fall rather than instead of it.

What settles it is that the player was mounted at the time and was killed on
landing, with the game reporting fall height as the cause.

So:

- **Actors can be repositioned from the console**, and a repositioned actor
  falls. The animation-driven limitation recorded for standing NPCs does not
  extend to this.
- **Fall damage is applied**, and 12 m is lethal to the player.
- **The horse took none of it.** Its health read 100 before the drop and 100
  after, while its rider died. Fall damage is therefore not uniform across
  entities, and the horse either resists it or is exempt.

The NPC variant, ragdolling with `actor:Fall` first and raising on a timer,
never produced its log line, and the level was unloaded partway through the
measurement. NPC fall damage remains untested rather than disproven, and there
is no longer any reason to believe the approach cannot work.

## A watch on one target, because the graze test cannot be ridden

**User report**: "I loaded a save because I was checking in on you and when I
came back I was on the death screen saying I died from fall height lol ths test
is damn near impossible to actually play out. NPCs don't really just stand there
for very long espeicaly not enough for me to trot past without hitting them or
anyone."

The graze test as designed asks for something the game does not allow. NPCs walk
their schedules, the streets are busy, and a controlled near miss on a chosen
target cannot be held still long enough to repeat.

The answer is to instrument rather than choreograph.
`HorseCollisionMod:WatchHealth(name, seconds)` samples one entity twice a
second and writes a line only when its health changes, so a quiet watch costs two lines and any loss is
timestamped. Riding normally near the target is then enough: a health drop with
no `Impact` line beside it is the graze the previous entry predicted, and one
with an `Impact` line is an ordinary hit.

It takes the same generation guard as the detection loop, so a watch does not
survive a load screen holding a stale entity.

## The delayed loss was the probe reading health too late

**User report**: "ok I just guessed which one it's not like rat_woman43 has a
nametag or something lol"

The guess was right. The watch recorded four changes on `rat_woman43` during a
two-minute ride:

| Event | Health | Change |
| --- | --- | --- |
| Watch started | 100.0000 | |
| Walk impact, `strength=2` | 100.0000 | none |
| Trot impact | 97.6762 | -2.3238 |
| Trot impact | 89.7660 | -7.9101 |
| No impact logged | 69.4161 | **-20.3499** |
| Gallop impact, starting health already 69.4161 | | |

The 20.35 is larger than any logged impact recorded in this project, and no
`Impact` line accounts for it. What identifies it is where it sits: the gallop
impact that follows reads the victim's starting health as 69.4161, so the loss
had already happened by the time that impact was measured.

### The cause is in the mod, not the engine

`HandleImpact` called `Ragdoll` before `ProbeImpactCost` on both the trot and
the gallop paths. The probe therefore read the victim's health **after** the
impulse had been applied.

If the impulse costs the victim health, that cost is invisible to the impact
that caused it and instead shows up as an unexplained loss in the interval
before the *next* impact, since it is baked into that impact's starting figure.

That accounts for every property of the mystery:

- The magnitude matches an impact, because it is caused by one.
- It never appeared between the 500 ms and 10000 ms samples, because it happens
  at the moment of the next impact rather than during the recovery.
- It appeared in roughly one interval in five, which is how often the impulse
  costs the victim anything worth recording.
- Extending the sampling window could not catch it, which is why the previous
  two entries could not find it.

The order is now reversed on both paths, so the probe reads before the impulse.

### What this means for the figures already recorded

**Every per-impact cost measured so far understates the impact**, by whatever
the impulse took. The armor comparison used the same instrument on both sides,
so its ratio is not invalidated, but the absolute figures in all four rides are
low.

It also revises the Phase 2 boundary question again. The impulse costing the
victim health is now the leading reading of the data, which is the same
conclusion the fall damage hypothesis reached by a route that turned out to be
wrong: scaling `impulseScale` by armor and mass would scale damage with it.

### The instrument also needs a way to name its target

Watching one entity by name asks the rider to identify an NPC that carries no
visible name. The watch happened to land on a target that was ridden at anyway.
Watching every living human near the horse would remove the guess, and is the
shape to build if a watch is needed again.

## The ordering fix was not the cause either

**Hypothesis**: `ProbeImpactCost` running after `Ragdoll` folded the impulse's
own damage into the next impact's starting figure. Reversing the order should
remove the between-impact gaps and raise the per-impact cost by the amount that
used to go missing.

**User report**: the ride was run as asked, twelve trot impacts on
`led_wanderer09`.

Both predictions failed.

| | Impacts | Mean | SD | Min | Max | Gaps |
| --- | --- | --- | --- | --- | --- | --- |
| Before the fix, `rat_woman12` | 12 | -4.2604 | 1.17 | -1.8493 | -5.8415 | 2 of 11 |
| After the fix, `led_wanderer09` | 12 | -3.8781 | 0.50 | -2.5422 | -4.5920 | 2 of 11 |

The gaps did not disappear. The rate is identical, and the two losses were 2.13
and 4.82. The per-impact cost did not rise; it fell slightly.

**So the impulse does not cost the victim health**, and the account given in the
previous entry is wrong. Sampling before the impulse is still the correct order
for a measurement, and it stays, but it explains nothing about the gaps.

The one real change is the spread: the standard deviation fell from 1.17 to
0.50. Two different targets were used, so archetype rather than the reordering
could account for that, and nothing should be read into it yet.

### Where this leaves the question

Five rides, three explanations offered and all three discarded:

1. Fall damage applied at the get-up. Disproved by sampling to 10 seconds and
   seeing no change after 500 ms on any impact.
2. A contact the footprint rejects while the engine still resolves it. Not
   disproved, but not demonstrated, and the ride designed to test it could not
   be performed.
3. The probe reading health after the impulse. Disproved here.

What survives every ride is the rate: close to one interval in five, at a
magnitude in the range of a trot impact, on every target and both sexes.

Guessing at mechanisms has now cost three rides. The watch is the instrument
that can answer it directly, because it timestamps the loss instead of
inferring it from the interval, and it now records the rider's distance and the
horse's recent peak speed at that moment. A loss with the horse alongside is the
rejected contact of explanation 2. A loss with the horse thirty metres away is
none of the three.

## Reading what an NPC is wearing

**Question**: how to get an entity's equipped items and their weights, which
every remaining Phase 2 item depends on.

### The API

`inventory:GetInventoryTable()` returns an array of item WUIDs.
`ItemManager.GetItem(wuid)` returns a table of `amount`, `class`, `entity`,
`health` and `id`, where `class` is the item class GUID that joins to
`Libs/Tables/item/`. `ItemManager.GetItemUIName(class)` gives a readable name.

The ScriptBind tables are C++ userdata with metatable indexing, so `pairs()`
lists nothing on them. Probing candidate names with `type(tbl[name])` works, and
`references/kcd-documentation/` holds the full generated bind documentation,
which is the faster source of the two.

### There is no equipped-items accessor, and it does not matter

Neither the live game nor the bind documentation has one. `Actor` and `Human`
have `EquipInventoryItem`, `EquipItemInSlot` and their unequip counterparts,
all setters. `Soul` has `GetDerivedStat`, whose valid names are not in
`statistic.xml` and have not been located.

What removes the problem is what an NPC actually carries. `led_woman6` carries
eight items: an apple, a quarter loaf, money, two keys, a head wreath, shoes and
a cotte. Everything except the food, keys and money is what she is wearing. The
player carries 179 items and is the exception, not the rule.

So for a collision target, **filtering the whole inventory to armor and clothing
classes is equivalent to reading the equipped set**, and needs no bind that does
not exist. The player would need the real equipped set, but the player is never
the victim here.

The traps already recorded still apply: weight is on `pickable_item.xml` joined
by `item_id` rather than on `armor.xml`, chain outweighs plate per piece, and
horse tack is filed as armor so saddle, bridle, shoe and spur must be excluded.

### An incidental finding on the stuck guard

While a guard was being ridden at repeatedly the engine logged
`Animation-queue overflow. More then 16 entries` against
`objects/characters/humans/skeleton/male.chr` continuously. The guard that
stopped responding earlier in the session is more likely queued reactions
accumulating faster than they play than vanilla's injured state.

## The stuck NPC is exhausted, and armor now scales the impulse

**User report**: "currently in game I'm standing right next to one of the NPCs
in the permo hurt animation where they seem to be stuck in it."

Queried live while the user stood beside it. `villageGuard`, 1.7 m away:

```
health=26.0386 stamina=121.581 exhaust=100
weaponDrawn=false  pieces=9 weight=47.0 smashDef=3.93 heaviest=chain
```

`exhaust=100` is the ceiling. Stamina had already recovered to 121, so the
guard is not out of stamina; it is exhausted, which is a vanilla state that
recovers on its own. Repeated impacts drive exhaustion up until the NPC stops
acting, and the `Animation-queue overflow` the engine logs alongside it is
queued reactions piling up rather than the cause. Not a defect, and not
something the mod needs to handle.

The same query corroborates the armor comparison from earlier. That guard
carries 9 pieces at 47 weight and 3.93 smash_def against a villager's 3 pieces
at 5 and 0.30. A thirteenfold difference in the game's own blunt defense still
produced only 13 per cent less damage, which is the clearest statement yet that
the engine does very little with armor on a collision hit.

### Spurs are the rider's

The first generated table filed spurs as horse tack, following the note in an
earlier entry. They are worn by a rider, so their weight belongs in a person's
total. Tack is now saddle, horseshoe and bridle only.

### The scaling

One curve serves both halves, on the ratio between a target's armor weight and
`ArmorReferenceWeight`. The impulse takes its reciprocal, the horse's stamina
cost takes it directly, and both are clamped.

| Armor weight | Impulse | Stamina |
| --- | --- | --- |
| 0 | 1.50 | 0.75 |
| 5, a villager | 1.26 | 0.79 |
| 8, the reference | 1.00 | 1.00 |
| 20 | 0.63 | 1.58 |
| 47, a guard in mail | 0.41 | 2.00 |
| 69 | 0.35 | 2.00 |

The stamina multiplier reaches its ceiling around weight 32, so everything from
a mail guard upward costs the horse the same. That is a tuning decision rather
than a limit, and the ceiling exists because the curve has none of its own.

Untested in play. The figures come from the curve, not from riding.

## Ten minutes of free riding, and what repeated impacts do

**User report**: "It's hard to say one way or the other. I did notice a lot of
dropped animations, especially from the women at one point I tried to walk
stagger like 5 times in a row and it wouldn't do anything. I did test galloping
into heavy armored in combat and it did throw me immediately like you had said
which for now is probably okay and would tune later."

Sixty-two impacts: 9 at walk, 35 at trot, 18 at gallop.

### The armor scaling works, and the stamina half is too strong

The multipliers land where the curve says they should. An armored guard reads
`armorImpulse=0.37 armorStamina=2.00` at 58 weight, a villager
`armorImpulse=1.26 armorStamina=0.79` at 5.

The cost is the problem. A single trot into a guard drained the horse from
207.1 to 117.1, and the largest recorded drain took the whole 210 pool. The
rider was thrown **nine times in ten minutes**. The stamina multiplier composes
with the combat multiplier already there, so a gallop into an armored target in
combat asks for 75 x 2.5 x 2.0, which is more than the pool holds.

### The dropped animations and the missing damage are the same thing

Every one of the nine walk impacts called the stagger and every call returned
`ok=true`, so the mod attempted all of them and the engine accepted all of them.
Nothing was dropped by the mod.

What separates this session from the controlled rides is how quickly the same
NPC is hit again. `HitCooldownMs` is 3000 ms, and a victim spends longer than
that on the ground: the height samples show them prone at 500 ms and standing by
3000 ms, which is the earliest they could be upright and is measured from the
impact rather than from when the ragdoll settles.

An impact that lands on someone still down cannot play a standing stagger,
because they are not standing, and the numbers agree:

| | Zero damage |
| --- | --- |
| Trot | 10 of 35 (29%) |
| Gallop | 8 of 18 (44%) |
| Controlled rides, 12 s apart | 2 of 45 (4%) |

Walk was 9 of 9, which is by design rather than a failure: the walk tier sends
`Tickle`, which is not meant to cost anything.

The rider being thrown is not the cause. Zero-damage impacts sit near a throw at
much the same rate as damaging ones, 16 of 27 against 21 of 35.

So the earlier four per cent failure rate is a floor measured under ideal
spacing, and free play is far worse. Whether the fix is a longer cooldown or a
check that the target is upright is a design question, but the mod currently
delivers a reaction to people who cannot perform one.

### The console noise

Neither warning the user asked about belongs to the mod.

`Agent '_Sheep21' ... failed to turn towards ... within 8.000000 seconds` is
vanilla AI pathing, and every instance in the log names a sheep.

`PROS:` is Warhorse's own online backend failing to reach its service and
retrying about twice a second. It accounted for 965 of 1940 lines in the play
window, half of everything written. There is no CVar that switches the service
off, but `log_SpamDelay` collapses repeats of an identical line and takes it to
roughly one line per thirty seconds. It is now part of the environment
`dev_deploy.ps1` writes, in both the development and shipping sets, since it
costs nothing in play. The mod's own telemetry carries changing numbers on
every line, so none of it is suppressed.

## Why five guards could not kill the player

**User report**: "I've been letting 5 guards kick the shit out of me for the
last few minutes but they haven't been ablet to kill me, whats going on here."

Every NPC within 15 m read `exhaust=100`:

```
rat_upper_guard12  health=18.9  stamina=90.7   exhaust=100  drawn=true
villageGuard       health=51.8  stamina=132.6  exhaust=100  drawn=false
villageGuard       health=80.0  stamina=53.4   exhaust=100  drawn=true
villageGuard       health=87.5  stamina=12.4   exhaust=100  drawn=true
rat_woman44        health=0     stamina=0      exhaust=100
rat_bailiff_wife   health=0     stamina=67.9   exhaust=100
```

Exhaustion is at its ceiling on every one of them, and it is the same state
that left a guard frozen in a hurt animation earlier. Being ridden into
repeatedly drives it there and it does not recover quickly, so a guard can draw
a weapon and swing without threatening anyone. The player sat at `health=47.5
exhaust=91.9`, most of the way to the same condition from taking the hits.

This is a consequence of the testing rather than of the mod: a session that
knocks the same guards down twenty times leaves the town's guards incapable.

### No engine call reports whether an actor is on the ground

Establishing this ruled out the direct approach to the recovery problem:

- `actor` exposes `Fall` and `StandUp` and nothing that reads the state back.
- `human` exposes `GetItemInHand` and `IsWeaponDrawn` only.
- `entity:GetAngles()` stays upright through a ragdoll. Two NPCs at `health=0`
  read pitch and roll of exactly 0.00, identical to a standing guard, so the
  entity transform says nothing about the body.

The mod applies the impulse itself, so it can time the recovery from that
instead. `RecentHits` now holds the time a victim becomes eligible again rather
than the time it was last hit, and the wait is `HitCooldownMs` after a stagger
against `KnockdownRecoveryMs` after a knockdown. A rejected impact logs
`recovering` with the time remaining rather than `cooldown`.

The 6000 ms default is above the measured recovery rather than derived from it.
Height samples put a trot victim prone at 500 ms and standing by 3000 ms, which
bounds the recovery at 3 seconds for that tier and says nothing about gallop,
which throws them further.

## Exhaustion is writable, so the exploit is fixable at the stat

**User report**: "The exhaustion side effect from being hit is a huge problem
because like we've observed it builds up an then potentially locks up the NPCs
which breaks immersion and also if I hit enough guards I can literally put the
controll down for minutes and they can't actually kill me."

**Question**: whether exhaustion can be controlled directly, rather than by
weakening the hit that causes it.

It can. On a live NPC:

```
[exh] rat_castlemaid2 before=100
[exh] SetState ok=true err=nil
[exh] rat_castlemaid2 after=20
```

`soul:SetState("exhaust", value)` is accepted and the new value reads back, and
it persists: the same NPC still read 20 several minutes later.

That matters beyond this fix. Exhaustion is the first stat found that the mod
can set directly rather than influence through `hitStrength`, so the limit is
applied to the stat itself and the damage, the reaction and the crime the hit
causes are untouched. Anything built later that scales those is independent of
this.

### The limit

`LimitExhaustion` records the victim's exhaustion at the impact and clamps it
twice afterwards, at 500 ms and 2000 ms, since the engine applies the hit after
the message is handled and the exact frame is not observable from Lua.

Only the rise caused by that impact is removed. The baseline is read at the
moment of the impact and the value is only ever clamped down to it, so
exhaustion earned in a fight is never given back, and a victim already past the
ceiling is left alone rather than lowered.

Three settings: `LimitCollisionExhaust`, `MaxExhaustPerImpact` at 8 of 100, and
`MaxExhaustFromCollisions` at 70. The ceiling is the important one: it means
collisions alone can never render a guard harmless, whatever the rider does.

The caps are chosen rather than measured. How much the engine actually adds per
collision is not yet known, so the impact line now carries the victim's
exhaustion and a clamp writes a line naming what it held back.

Applied on every tier including walk, because a stagger needs no run-up and is
the cheapest way to accumulate exhaustion on a chosen victim.

### The test area was reset

Every NPC near the testing area read `exhaust=100` from earlier sessions, which
would have hidden any change. 88 NPCs within 120 m were set to 0 so the next
ride starts from a fair state.

## The exhaustion rise is gradual, not part of the hit

**User report**: "I was able to hit a guard and get him into full exhaustion. I
tested for for last 10 minutes or so hitting a lot of people."

53 impacts, **zero clamps**, and victims still reached the ceiling.

The exhaustion figures now carried on the impact line explain why. Every reading
is one of two values:

```
33  exhaust=0.0
20  exhaust=100.0
```

Nothing between, across 53 impacts. A victim is either untouched or at the
ceiling by the time the next impact reads them, and neither sample at 500 ms nor
at 2000 ms ever caught a value above what the cap allowed.

So the rise is not the hit landing. Exhaustion accumulates over the seconds
after an impact, while the victim gets up and runs, and it is finished long
before the rider comes round for another pass. Two one-shot timers were never
going to see it.

### Watching instead of sampling

`LimitExhaustion` now registers the victim in `ExhaustWatch` with the value its
impact allowed, and `EnforceExhaustLimits` holds it there on every tick of the
update loop until `ExhaustWatchMs` expires, 20 seconds by default.

It runs ahead of the mounted and moving test in `UpdateTimer`. A victim keeps
accumulating after the rider has stopped, and stopping is exactly what a rider
does once they are finished with a guard.

The clamp logs once per victim rather than once per tick, naming how long after
the impact the rise appeared. That measurement is what the caps should be set
from, and it does not exist yet.

**Whether the two readings mean the stat is effectively binary is not
established.** Sampling only at impacts would show 0 and 100 either way, since
those are the states a victim spends time in. The watch samples ten times a
second and will settle it.

## The limit works, and the test population was the problem

**User report**: tested, and the guard still reached full exhaustion.

24 impacts, no clamps, and every impact read `exhaust=100.0` **before** the hit.
The victims were already at the ceiling from earlier sessions, and the code
declined to lower anyone already past it, so the limit could never engage. The
whole test population was spent before it began.

### The mechanism was never the problem

Forced directly, with the watch armed by hand:

```
[test] rat_woman21 forced to 100 with a watch armed at 8
Exhaust rat_woman21 after=128ms was=0.0 rose=100.0 held=8.0
[test] after 600ms exhaust=8
[test] after 3000ms exhaust=8
```

Caught in 128 ms and held. The watch loop does what it should.

That test is worth keeping as a pattern: forcing the state the mod is meant to
react to, from the console, verifies the reaction without a ride. It answered in
seconds what a ride could not answer at all, because the ride could not produce
a victim below the ceiling to begin with.

### The ceiling now applies to victims already above it

The rule that spared them was wrong. A victim the mod pinned at 100 in an
earlier session could never come back, so the exploit would survive the fix in
every save it had already reached. The clamp now pulls such a victim down to
`MaxExhaustFromCollisions` on the next collision:

```
Exhaust rat_woman21 after=112ms was=100.0 rose=100.0 held=70.0
```

Nothing goes below the ceiling, so a victim exhausted by a fight still ends up
tired and a collision is never a favor. What it guarantees is that a guard the
rider knocks down is always left able to fight, whatever state the save was in.

## The stat is Energy, and higher is better

**User report**: "I'm falling asleep in game, so I'm assuming exhaustion and
energy are the same thing because I don't see an exhaustion stat I see an energy
state."

Setting the player's `exhaust` to 0 made the player start falling asleep. The
stat named `exhaust` in `soul:GetState` is the **Energy** stat the game shows in
its own UI, and the scale runs the other way from the name: **100 is fully
rested and 0 is spent.**

Every conclusion drawn from it in the previous four entries is inverted.

- NPCs reading `exhaust=100` were **fully rested**, not exhausted. The reading
  that looked like a smoking gun was the default state of an untouched NPC.
- The guards that could not fight were not exhausted at all. Whatever disables
  them, this was never it, which is what the user suspected before this test.
- `LimitExhaustion` was **draining** its victims. Holding a victim at 70 took 30
  points of energy from someone who had none taken by the collision, and the
  ceiling that was supposed to protect them was making them worse. The clamp
  logged as `held=70.0` were reductions from full.

The limit is switched off in both the defaults and the settings file. The code
stays, because the mechanism is sound and the stat is genuinely writable; only
the premise was wrong.

The player was restored to the 95.5783 recorded before the test, and 55 NPCs
whose energy the mod had lowered were returned to 100.

### What this cost, and the check that would have caught it

Four entries of reasoning rested on a stat whose direction was never verified.
The name `exhaust` was taken to mean exhaustion, and every observation was fitted
to it: a town of NPCs reading 100 looked like accumulated damage rather than
untouched defaults, and NPCs reading 0 and 100 with nothing between looked like a
binary stat rather than a rested population and a handful the mod had drained.

The check that settles a stat's direction is to move it on the player and look at
the screen, which took one command. It should come before any reasoning is built
on a stat this project has not used before.

### The lockup is still unexplained

The guard remains stuck in a hurt animation, and it is not energy, not the
animation queue, which logged no overflow at all on a clean save, and not
anything the mod sets. `health=34.1 stamina=124.1` with no weapon drawn.

## What the stuck guard is not

**User report**: "It kind of reminds me like he's holding his stomach, is he
hungry (nourishment) or maybe is he's poisoned? or is there some buff attached
to him?"

Interrogated live, standing next to him. None of those, and the elimination is
worth more than it looks.

- **Not hunger, poison or bleeding.** `soul:GetState` answers for exactly three
  names on this build: `health`, `stamina` and `exhaust`. Every other name
  tried, including `nourishment`, `poison`, `bleeding`, `injury`, `morale` and
  `consciousness`, returns nil. Those states are not queryable and most likely
  do not exist here.
- **Not a buff.** `HasBuffDebug` is absent from `Soul` on this build, and the
  documented bind list has no getter for buffs at all.
- **Not injury or low condition.** `health=49.4 stamina=138.6 exhaust=100`, and
  health was rising between samples, so he is healing normally. Energy is full,
  which after the correction in the previous entry means rested.
- **Not the animation queue.** Zero `Animation-queue overflow` lines on the
  clean save.
- **Not anything the mod writes.** He entered the state on a save that predates
  the mod's installation, with the energy limit already disabled.

`actor:StandUp()` is accepted and changes nothing.

### The animation cannot be read from the entity

`entity:GetCurAnimation(slot)` returns nil for every slot while
`IsAnimationRunning` is true, so the animation is not playing through an entity
animation slot. It is Mannequin or AI driven, which is consistent with
everything else this project has found about actor animation, and it means the
clip cannot be named from Lua.

`ai_DebugAgent`, `ai_DebugDraw` and `ai_DebugBehaviorSelection` were set and
drew nothing on screen.

### The route that is left

`XGenAIModule.GetBrainVariable(entity, name)` reads a behavior tree's variable
store, and vanilla uses it from `LuaGate` nodes. Twelve persistent `b_` variable
names taken from the `sb_switch_*` trees all returned nil against the guard's
entity id, so either the addressing is wrong, vanilla passing a WUID in one call
site and an entity id in another, or those variables are not set on him.

Settling that addressing is the next step and it is cheap. What it would give is
the tree's own view of the NPC, which is the only place left that can name the
state.

### Runtime archetype data, found incidentally

`soul:GetArchetype()` returns a live table:

```
NormalBodyWeight=160  BodyBaseArmor=1.3  BaseStamina=110
UnarmedAttackBase=2.6  InventoryCapacityMultiplier=3  GenderId=1
```

This is the `soul_archetype.xml` data the roadmap listed as needing extraction,
available at runtime with no generated table. Phase 2's mass scaling can read
`NormalBodyWeight` directly, and `BodyBaseArmor` is the engine's own base armor
for the body underneath whatever is worn.
