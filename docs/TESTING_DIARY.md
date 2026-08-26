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
