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
rejected contact of explanation 2. A loss with the horse thirty meters away is
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

## The lockup is an injury buff, and it never heals on its own

**User request**: deep research into `references/`, the decompile, and the game's
own data, to find what the animation is and where it comes from.

It is not an animation state, a stat, or anything Mannequin selects on its own.
It is a **buff**, which is what the user guessed before this search began.

### The trail

`Libs/Tables/action/actor_action_standup.xml` names the fragment that stands an
actor up after a ragdoll: `mn_fragment_id="BlendRagdoll"` with
`mn_tags="blendOut+standup"`. That fragment lives in `kcd_male_database.adb` and
`wh_female_database.adb`, both of which this mod reaches through its `SubADB`
chain, and both declared in fragment id files the mod either does not override
or overrides as a strict superset. **The mod removes nothing the recovery needs**,
which clears the animation data as a suspect:

```
kcd_animationControlledTags.xml   vanilla 20 names, ours 25, none missing
wh_female_fragmentids.xml         vanilla 276 names, ours 277, none missing
```

`WHGame_Decompiled.c` then names the real mechanism: `C_InjuredSoulBuffInstance`,
`C_InjuredBuffInitParams`, `C_InjuredTagSoulBuffInstance` and `InjuredTag`.
Injury is a soul buff, not a state.

### The buffs

`Libs/Tables/rpg/buff.xml`, class 5, `Injury`:

| Buff | GUID | Params |
| --- | --- | --- |
| `injured_torso` | `37d59205-3782-446d-b32e-89a9f786725d` | `str*0.75,agi*0.75` |
| `injured_head` | `c48e48e2-ae85-4429-9dd6-4fb94c388001` | `src+1,srg*0.75` |
| `injured_left_arm` | `34f0885b-7287-4881-907f-f19751a5e831` | `defense*0.75` |
| `injured_right_arm` | `ce3737db-b0a3-459d-8d47-d58695d58be3` | `asp*0.75` |
| `injured_left_leg` | `10fc25ca-c095-44c6-b88b-d54ad58ab0a6` | `Run-1,Walk-0.5,LimitSprint` |
| `injured_right_leg` | `738f8a07-c5fd-4687-9408-34ffb0bcd17e` | `Run-1,Walk-0.5,LimitSprint` |
| `injured_tag_persistent` | `83ef27f9-4ce2-4894-bd42-d2cc61a6f758` | `Cpp:InjuredTag` |
| `remove_injuries` | `46683e3b-e261-412f-b402-99ee17dda62a` | `Cpp:BasicTimed`, duration 1 |

Every injury carries `duration="-1"` and `is_persistent="True"`. **They do not
expire.** A human player treats them with bandages, potions or sleep. An NPC has
no such path, so an injury applied to an NPC is permanent for the life of the
save.

`buff_ai_tag_id="7"` on each of them is what the AI reads, which is how a buff
ends up driving both the animation and the unwillingness to fight.

That closes every observation. The guard holding his stomach has
`injured_torso`, `str*0.75,agi*0.75`, forever. He was healthy, rested and
healing because health, stamina and energy are unrelated to it. Repeated
collisions apply more injuries, which is why the effect accumulates, and why an
untouched NPC on a fresh save reaches it after enough impacts.

### What it means for the mod

**This is the mod's own doing.** Vanilla converts a player-ridden collision into
a real `combat:hit`, the engine resolves an injury from it, and nothing ever
removes it. A rider can permanently cripple every NPC in a town, which is the
exploit and the immersion break in one.

`soul:AddInjury` and `soul:RemoveAllBuffsByGuid` are both in the bind list, and
`remove_injuries` exists as a buff of its own, so the mod can act on this
directly rather than by weakening the hit.

Nothing here is tested in game yet. The next step is to confirm that removing
`injured_torso` from the stuck guard returns him to normal.

## Vanilla has no horse collision, so the injuries are the mod's

**User report**: "there is no vanilla horse collision though... I know there is
a recognition that henry is on a horse and collides but I didn't think it had
anything attached to it besides the bark. I just did the test and of course
vanilla doesn't have collisons so I didn't see anything happen."

The mod was parked completely for this: the pak, its manifest, all three loose
Lua files, all four loose animation files, and its entry in `mod_order.txt`. The
log confirms the session ran with no mod line at all.

Riding into NPCs produced nothing. No knockdown, no reaction, no injury.

**An earlier claim in this session that horse collisions are vanilla behaviour
was wrong.** `sb_switch_hitreactions.xml` contains a collision branch, and that
branch is what converts a player-ridden collision into a real `combat:hit`, but
nothing in vanilla ever feeds it a strength that injures. The branch exists for a
bark. The mod is what sends `MinorInjury` at trot and `MajorInjury` at gallop
into it.

So the permanent injuries are caused by this mod, and by the released 3.0.0 as
well, which sends the same two strengths.

### Cleared rather than prevented

The strength that rolls the injury is the same strength that carries the damage
and the crime. Lowering it to stop the injury would take those with it, and the
damage is a Phase 3 feature that already works.

`ClearInjuries` removes the eight injury buffs from a victim at 1500 ms and
5000 ms after an impact, the second pass covering an injury that arrives late
the way the damage sometimes does. Only victims of a collision are touched, and
only in the seconds after one, so an NPC injured by anything else keeps what it
earned.

`ClearCollisionInjuries` defaults to on. Turning it off restores what 3.0.0
shipped.

An existing save repairs itself as the rider rides: any NPC hit again has its
injuries cleared. That is a partial repair rather than a complete one, since an
NPC never hit again keeps what it has, but it needs no separate migration and
no action from the player.

**Untested in game.** The mod was parked when this was written.

## The stuck state is curable, and it is not the injury buff

**User report**: "he snapped out of it!"

Four things were applied to a stuck `villageGuard` at once: the
`remove_injuries` buff, the `miraculous_cure` buff, `health=100` and
`stamina=200`. He returned to normal behavior immediately.

That settles the most important question. **The state is reversible from Lua**,
so whatever it is, the mod can undo it.

### What the same session rules out

The mod applied `remove_injuries` after every one of 16 impacts on that guard,
logging `cure=true` for all 32 calls, and he became stuck anyway. **So the
injury buff is not what holds him**, or at least clearing it is not enough. The
identification in the earlier entry was built on the decompile and the buff
table rather than on a test, and this is the test.

Stamina is unlikely for the same reason: earlier stuck guards read 124 and 138,
which is most of a pool.

That leaves `miraculous_cure` and health, and health is the stronger candidate.
Every stuck NPC measured has been low: 19.6, 26.0, 32.6, 34.1 and 49.4 against
a hundred.

### A caution carried from this round

`cure=true` was logged 32 times while nothing changed, exactly as
`cleared=8/8` had been before it. Both were counting calls that did not throw.
A ScriptBind that accepts a call and reports success proves only that the
function exists, and on this build several of them do nothing observable.
**Nothing in this project should be recorded as working on the strength of a
return value.** The only evidence that has held up all session is a change
someone can see on screen or a number that moves in a later sample.

## It is the wounded state, and health is only the gate out of it

**User report**: a guard set to 25 health without ever being hit "didn't
freeze, he's acting normal". The same guard, stuck after a collision, returned
to normal the moment health was raised.

Two tests, one conclusion. **Low health does not cause the state, and raising
health is what releases it.** A collision puts its victim into a wounded state
whose exit is gated on health, and because nothing ever heals an NPC, a victim
left below that gate never leaves.

That reconciles the question the user raised about combat: an NPC beaten to low
health in a fight does not freeze, because the combat tree owns the situation
and has its own exits. This mod produces something vanilla never produces, a
badly wounded NPC standing in the street with no combat context, and nothing
owns that.

It also means the fix does not need to understand the state at all. Keeping the
victim above the gate is enough.

### The floor

`HoldVictimAboveFloor` reads the victim's health at 1000 ms and 4000 ms after
an impact, after the engine has resolved the hit, and lifts it back to
`MinVictimHealth` if it fell below. Damage still lands and still accumulates
down to the floor, and a victim already dead is left alone.

`MinVictimHealth` defaults to 60, above the highest health at which a victim
has been seen stuck, which is 51.8. The exact gate is not known; 60 is a margin
rather than a measurement, and the setting exists so it can move.

The injury cure stays. A permanent injury is worth undoing on its own account,
and the two are independent: the cure ran on all 16 impacts of the session that
produced the stuck guard, and did not prevent it.

### Where this leaves damage

The user's reading is that this becomes moot once damage and crime are properly
built, since a trampled villager should be hurt and should be a victim the world
reacts to. That is likely right, and the floor is deliberately a setting rather
than a rule so it can be lowered as the state acquires an owner.

## The floor holds

**User report**: "I smashed a guard like 15 times and he didn't seem to get
stuck."

19 impacts on `rat_guard18`, trot and gallop, 15 floor lifts, no lockup.

```
Floor rat_guard18 t+1000ms was=21.2 held=60.0
Floor rat_guard18 t+1000ms was=43.3 held=60.0
Floor rat_guard18 t+1000ms was=53.5 held=60.0
```

Damage lands on every impact, visible in the health carried on each impact
line, between 44 and 57 through the run. Only the stranding is prevented.

That closes the lockup. Four mechanisms were proposed and discarded on the way
to it, and the one that worked was found by a test rather than by reading: low
health does not cause the state, and health is only the gate out.

### The trade-off, which is real

A collision can no longer kill. A victim cannot be trampled below the floor
however many times they are ridden into, so a rider cannot run someone down.
That is a deliberate exchange for the lockup and it is a setting rather than a
rule, but it should be understood before release: it is a change to what the
mod does in play, not only a defect fix.

A future version can separate the two, by letting a hit that would be lethal
resolve as a death rather than being floored, so that trampling can kill while
never stranding. That needs the crime work to be meaningful and is not worth
building before it.

## Combat takes ownership of a stuck NPC, and hands it back

**User report**: "when I was testing a guard who was stuck, i swung the sword at
him and his combat enables and then I surrendered and paid the fine and then he
returned to the stuck state."

This is the clearest confirmation of the mechanism in the whole session, and it
was observed rather than reasoned.

A stuck guard **fights normally** once combat starts. Nothing about him is
broken: the animation, the AI and the willingness to fight are all intact while
the combat tree owns him. When combat ends he falls straight back into the
wounded state, because his health is still below the gate and the combat tree
has released him.

So the wounded state is the fallback an NPC sits in whenever nothing else claims
them, and combat is one of the things that claims them. It confirms that the
state is not damage, not a broken tree and not a stuck animation, and that
health is the only thing deciding whether they can leave it.

### What it means for repairing existing saves

A save carrying stuck NPCs is repaired by riding into them again:
`HoldVictimAboveFloor` runs on every impact and does not care what state the
victim was in beforehand, and a lift was already recorded from as low as 21.2.
No extra check is needed for that, and the check the user proposed, testing on
collision whether the victim is below the threshold, is exactly what the floor
already does.

Hooking the moment a fine is paid would work for that one case but not for the
general one, and a broader sweep that lifts every wounded NPC near the player
carries a real hazard: **an NPC scripted to be wounded for a quest would be
healed by it.** The game has several. Repairing only what the mod collides with
is targeted and cannot touch anyone the rider never touched.

Untested: whether an NPC stuck from before the fix is released by a single
impact under it. The mechanism says yes, and that is not the same as having
seen it.

## The lockup could not be reproduced with both protections off

**User report**: "I've hit this guy like 20 times and he's not getting stuck",
then, after the injury cure was disabled too, "uhh, he died?"

An attempt to manufacture a stuck NPC, so that repairing one could be tested,
failed and produced a more important result than the test it was for.

`rat_guardJanik`, 12 armor pieces at 74 weight, was ridden into 25 times with
`MinVictimHealth` at 0 and, for the last four, `ClearCollisionInjuries` off as
well. That is exactly what 3.0.0 does. Health fell steadily to 15.5, then 13.8,
12.2, and a gallop took him to 0.115, at which point he died.

**He never entered the stuck state**, at any health, across the whole run,
including nine impacts below 32.6, which is lower than most of the values at
which victims were seen stuck earlier in the session.

### What that costs the previous conclusion

The state is **intermittent**, not a deterministic consequence of collisions at
low health. The model recorded two entries ago, that a collision plus low health
puts a victim into a wounded state, is at best incomplete: the same inputs
produced death here and a lockup earlier.

So the health floor cannot be claimed to fix the lockup by mechanism. What can
honestly be said is narrower:

- Raising a stuck victim's health releases them. Seen twice, on demand.
- Keeping victims above 60 keeps them out of the range where every observed
  lockup happened, between 19.6 and 51.8.
- A 19 impact run with the floor on produced no lockup, but so did a 25 impact
  run with it off, so that run proves less than it appeared to.

What still distinguishes a victim who locks up from one who dies is not known.
Archetype, whether combat was entered, and a roll inside the engine are all
candidates and none has been tested.

### A 3.0.0 behavior worth naming

**A trampled NPC can die.** Four impacts took a guard from 13.8 to dead, the
last one a gallop for roughly 12 health. That is what the released version does,
and killing a guard is a murder the crime system will notice.

The floor prevents it as a side effect, which is the trade already recorded, but
until now nothing in this project had established that collisions were lethal at
all.

### The repair test is still unrun

Producing a stuck NPC on demand is the prerequisite, and it could not be done.
Whether one impact under the floor releases an NPC stuck from before remains
untested.

## The damage is the ragdoll, and the walk tier proves it

A methodical run from a clean baseline, one variable at a time, finally found
the cause. It is not downstream of the hit at all. It is the mod's own
`Ragdoll` call.

### The sequence

With `MinVictimHealth` at 0 and `ClearCollisionInjuries` off, a plain
`villageGuard` locked up reliably at 18 impacts. That reproduction is what made
everything after it possible.

| Variable changed | Result |
| --- | --- |
| `remove_injuries` applied to a stuck victim, four times | no release |
| health 52, then 76 | no release |
| health 88, then 100 | releases |
| health pulsed to 100 then back down after 700 ms | drops back in |
| healed, allowed to walk normally, then damage restored | drops back in |
| `remove_unconsciousness` applied, health untouched | no release |
| `SendHitReaction` off | **damage continues** |
| impulse zeroed, `Knockback` and `Uplift` at 0 | **damage continues** |
| `horse_throwdown_protection` on the victim | **damage continues** |

### What that leaves

The walk tier costs nothing. Every walk impact all session, with the hit
reaction on or off, left health unchanged:

```
villageGuard tier=Walk health=63.2079   next impact 63.2079
villageGuard tier=Walk health=49.6894   next impact 49.6894
```

Walk calls `PlayStagger`. Trot and gallop call `Ragdoll`. That is the only
difference between them, and trot damages every time.

**`actor:Fall()` costs the victim health.** Not the impulse, which can be zero
and still damage. Not the hit reaction, which can be off and still damage. The
ragdoll itself.

It also explains the vanilla test cleanly. Vanilla never ragdolls a pedestrian,
so a victim stays animation-driven and a horse cannot touch them. The moment
this mod ragdolls someone they become a physics object in the path of a horse.

### What this retires

Everything built earlier tonight was treating symptoms of a cause that had not
been found: the energy limit, the injury cure, and the health floor. None of
them addresses the ragdoll, and the floor cannot work anyway, since the release
gate sits between 76 and 88 while a floor that high would cancel damage
entirely. They should be removed rather than left in.

### The direction that follows

The walk tier is the existence proof. A staggering victim is animated rather
than physical, takes no damage, and never locks up. Replacing the physics
ragdoll with an animated knockdown, through the same `AnimationControlled`
path the mod already uses for `hcm_stagger_*`, would keep the knockdown while
removing the damage and the lockup together.

That is a design change rather than a patch, and it is where the next branch
should start.

## Root cause: the horse runs over the body the ragdoll created

Ragdolling an NPC 7.3 m away, with no horse anywhere near, costs nothing:

```
rat_activity_vagabund at 7.3m health=100.00 -- ragdolling with NO horse contact
4s after ragdoll: health=100.00 (was 100.00)
```

So `actor:Fall()` is not the damage either. The damage needs the horse.

**The mechanism, in order.** The mod ragdolls the victim, which converts them
from an animation-driven actor into a physics object. The horse is still moving
through that space. The engine resolves horse against body as a collision and
applies damage from the velocity delta, at
`CollisionVelocityDeltaToDmgR = 0.25` in `rpg_param.xml`. The victim is run
over, repeatedly, by the thing that knocked them down.

Every observation fits it:

| Observation | Explained by |
| --- | --- |
| Walk costs zero, always | Stagger does not ragdoll, so no physics body exists |
| Vanilla costs zero | Vanilla never ragdolls a pedestrian |
| `SendHitReaction` off changes nothing | Not combat damage |
| Impulse zeroed changes nothing | The horse still arrives |
| `death_protection`, `tough_guy` bypassed | Not routed through combat damage |
| `fall_damage` with `fdm=0` bypassed | Not fall damage |
| Gallop 17 to 24, trot 3 to 8 | Damage scales with velocity delta |

That last row had been sitting in the logs all session as an unexplained tier
difference. It is the signature of the parameter.

### Why the impulse makes it worse rather than better

`Ragdoll` directs the impulse along the horse's velocity, so the victim is
driven **forward, down the horse's own line of travel**. They are pushed along
the path the horse is about to occupy, which maximises the number of frames the
two overlap. A lateral component would clear them instead.

### The candidate fixes, in the order they are worth trying

1. **Throw the victim sideways.** Add a lateral component to the impulse so a
   clipped pedestrian is knocked aside rather than punted along the horse's
   line. Cheap, physically sensible, and changes nothing else.
2. **Delay the ragdoll** by a couple of hundred milliseconds so the horse has
   passed before the body becomes physical.
3. **Animated knockdown** through the `AnimationControlled` path, as the walk
   stagger already does, which never creates a physics body at all.

Overriding `CollisionVelocityDeltaToDmgR` is possible but rejected: it is a
global table, it would change the player's own collision damage, and shipping
`rpg_param.xml` reintroduces exactly the whole-file conflict surface 3.0.0
removed.

### What this retires

The energy limit, the injury cure and the health floor all treated symptoms of
this and none of them touch it. They come out.

## Two bugs, not one: the damage is collision velocity, the lockup is not

With `CollisionVelocityDeltaToDmgR` set to 0 in a loose `rpg_param.xml`, and
the mod otherwise in its normal configuration:

```
15 impacts, 15 zero deltas, health 96.3775 throughout
```

**The damage is proven.** Every trot and gallop impact cost exactly nothing. The
source is the engine's collision damage, applied when the horse strikes the
physics body the ragdoll creates, which is what the isolated ragdoll test at
7.3 m predicted.

**And the victim still locked up, at 96.4 health**, in a normal standing
animation rather than a wounded one.

That separates the two problems, and it corrects several entries above:

- The lockup is **not caused by the damage**. A victim at full health reaches
  it just as readily.
- The wounded pose was never the state, only how a wounded NPC looks while in
  it. With no damage, the same wedge shows in an ordinary idle.
- The health gate between 76 and 88 is **not a gate**. Raising health released
  victims, repeatedly and on demand, but a healthy victim can be stuck, so
  writing health must jog the AI into re-evaluating rather than clearing a
  threshold.
- `MinVictimHealth` could never have fixed the lockup. It should be removed
  along with the injury cure and the energy limit.

### What the lockup now looks like

An NPC repeatedly ragdolled ends up wedged in whatever idle it holds, alive and
undamaged, and will not resume its schedule. Combat claims it normally and
returns it to the wedge afterwards, which was recorded earlier and fits an AI
state that never resumes rather than anything about health or animation.

The obvious next variable is the interval between impacts.
`KnockdownRecoveryMs` is 6000, and a victim hit again while still recovering is
plausibly what wedges the state machine. That is one setting and one ride.

### On shipping the collision parameter

Proven as a diagnostic, rejected as a fix. It is a single global value read by
everything in the game that resolves a physical collision, so zeroing it
changes falling objects, carts and the player's own collisions, and shipping
`rpg_param.xml` reintroduces the whole-file conflict surface 3.0.0 removed.
The damage fix remains a lateral impulse, so the horse and the body stop
overlapping at all.

## BasicActor's collision damage getters are vestigial

**Hypothesis**: `BasicActor.lua` gates collision damage through four per-entity
getters, `GetSelfCollisionMult`, `GetForeignCollisionMult`,
`GetColliderEnergyScale` and `GetCollisionDamageThreshold`, each returning a
value stored on the entity. If the engine reads them, a victim's collision
damage can be suppressed per entity at runtime, which would fix the trample
damage without shipping `rpg_param.xml` and without the whole-file conflict
surface that override carries.

The properties are authored, not dead defaults. A live read of three NPCs
returned `collisionDamageThreshold=2` on `rat_man95`, `villageGuard` and
`rat_guard23`, matching `collisionDamageThreshold = 2` on
`Scripts/Entities/AI/NPC_x.lua:163`. `Scripts/Entities/actor/BasicActor.lua`
ships in `Scripts.pak` at 47,737 bytes. All four getters are present as
functions on every live NPC entity.

**Method**: each getter was replaced on the entity table with a wrapper that
logs the call and returns a suppressing value, 0 for the three multipliers and
10000 for the threshold. The hook was verified by direct invocation immediately
before the ride:

```
[H3] rat_merchant_shop1 before selfMult=1 fnType=function
[HOOK] GetSelfCollisionMult on rat_merchant_shop1 a=nil b=nil -> 0
[H3] rat_merchant_shop1 after  selfMult=0 thresh=10000
```

**Results**: four impacts on the two verified-hooked entities, one trot and
three gallop.

| Victim | Tier | Delta |
| --- | --- | --- |
| rat_merchant_shop2 | Trot | -4.1089 |
| rat_merchant_shop2 | Gallop | -26.6725 |
| rat_merchant_shop1 | Gallop | +0.0000 |
| rat_merchant_shop1 | Gallop | -21.6846 |

**Not one `[HOOK]` line fired.** Damage landed at its normal magnitude and the
last impact killed the victim. The engine does not call these getters when it
resolves collision damage against an actor. The subsystem is vestigial in the
same way `HitDeathReactions` is, and for the same reason: much of
`BasicActor.lua` is inherited Crytek code, still carrying Nanosuit, Abrams tank
and SmartMine references that KCD never uses.

**Two further findings from the same session:**

- **Patching the shared `BasicActor` table does not reach spawned entities.**
  Global `BasicActor` was patched and a spawned NPC still returned the vanilla
  value. Entity script tables are copies, which is the same mechanism recorded
  under additive deployment, where redirecting `NPC_x` had no effect because
  `NPC = CreateAI(NPC_x)` copies fields.
- **A radius snapshot is not a reliable way to instrument a victim.** A first
  pass hooked every NPC within 25 m and the two eventual victims were not among
  them, which made the first ride worthless. Hook by entity name and verify by
  direct invocation before treating a ride as valid.

**What this retires**: overriding `BasicActor.lua` to gate collision damage, in
any form. The file's damage plumbing is not what the engine runs.

## KCD does not route actor damage through Lua `OnHit`

**Hypothesis**: `BasicActor.Server:OnHit(hit)` receives every physical hit, so a
gatekeeper at the top of it could discard a collision hit before anything
downstream reads it. `BasicActor.lua` supports the reading: line 616 branches on
`hit.type ~= "collision"`, and `SinglePlayer:ProcessActorDamage` is reached from
inside `OnHit`.

**Method**: `Server.OnHit` and `Client.OnHit` were replaced on the entity table
with a wrapper that logs `hit.type`, `hit.damage` and `hit.shooterId` and then
calls the original. A synthetic call confirmed the wrapper was reached. The hook
re-armed on a two second timer against every NPC within 70 m of the player, so
it followed the rider and covered any target rather than a chosen few. Sixty
NPCs were instrumented.

**Results**: four impacts, and the victims were checked for instrumentation
afterwards rather than assumed.

| Victim | Hooked | Tier | Armor weight | Delta |
| --- | --- | --- | --- | --- |
| rat_woman44 | no | Trot | 6 | -2.7146 |
| rat_man19 | yes | Gallop | 8 | -22.7365 |
| rat_guard24 | yes | Gallop | 46 | +0.0000 |
| rat_guard_pazdera | yes | Trot | 55 | +0.0000 |

`rat_man19` was verifiably hooked, lost 22.74 health to a gallop impact, and
produced no wrapper call. The session counter finished at **zero OnHit calls
against sixty hooked entities**.

Actor damage in KCD does not pass through the Lua `OnHit` entry point. Warhorse
resolves it natively. There is no Lua interception point on this path, so a
`BasicActor.lua` override cannot gate collision damage however it is written,
which matches the finding above that the file's collision multiplier getters are
never called either.

**Side observation, not pursued.** Both heavily armored victims took exactly
zero damage while the cloth-clad victim took 22.74 at the same tier. Their
`armorImpulse` values were 0.42 and 0.38 against 1.00 for the unarmored target.
A target the impulse barely moves is a target that is not thrown along the
horse's path, and it takes no trample damage. That is the trample mechanism
predicting its own signature, and it is direct support for the lateral impulse
fix: reduce the overlap and the damage goes with it. It also sits awkwardly
against the earlier Phase 2 reading that armor mitigation "cannot be separated
from zero", which was measured on damage rather than on impulse.

## A lateral impulse does not reduce collision damage

**Hypothesis**: `Ragdoll` aimed its impulse along the horse's heading, driving
the victim down the line the horse was about to occupy and maximising the frames
the two overlap. A sideways component should clear the victim instead, and the
damage should fall with the overlap.

**Change**: a `Lateral` term, default 40, applied along the perpendicular to the
horse's heading, signed by which side of the line the victim already stands on.

**Results**: no reduction. Gallop impacts on light targets cost as much as
before or slightly more, against a pre-change baseline of -22.74 on a cloth-clad
target.

| Victim | Armor weight | armorImpulse | Tier | Delta |
| --- | --- | --- | --- | --- |
| rat_woman34 | 5 | 1.26 | Gallop | -25.8146 |
| rat_woman34 | 5 | 1.26 | Gallop | -24.1469 |
| rat_woman34 | 5 | 1.26 | Gallop | -29.2818 |
| villageGuard | 59 | 0.37 | Trot | +0.0000 |

**The change made the impulse larger, not sideways.** Knockback 50 and Uplift 30
give a magnitude of 58.3. Adding a perpendicular 40 gives 70.7, a 21 per cent
increase. Damage rose with it.

**Damage tracks impulse magnitude across the whole session.** Ordering every
gallop impact by `armorImpulse`, which is the only per-victim multiplier on the
impulse, the correlation is tight: 0.37 to 0.42 costs nothing, 1.00 costs 22.74,
and 1.26 costs 24 to 29. Armor weight is the input to that multiplier, so the
same ordering was previously read as armor mitigating damage. The impulse is the
better explanation, because the engine charges collision damage on a velocity
delta and a larger impulse produces a larger one when the body lands.

**What is still open.** An earlier session recorded "impulse zeroed, `Knockback`
and `Uplift` at 0, damage continues" and concluded `actor:Fall()` alone costs the
victim health. That test recorded whether damage occurred, not how much. If
zeroing the impulse takes a gallop impact from 25 down to 3 rather than to 0, the
ragdoll's own landing accounts for a little of the cost and the impulse accounts
for most of it, and the conclusion drawn from that table needs revising. The
magnitude was never measured, so it is being measured now.

## The impulse contributes nothing to collision damage, and neither does armor

**Method**: `Knockback`, `Uplift` and `Lateral` all set to 0 in the running
game, so victims drop where they stand with no throw at all. Six gallop
impacts.

| Victim | Armor weight | armorImpulse | Speed at contact | Delta |
| --- | --- | --- | --- | --- |
| villageGuard | 50.5 | 0.40 | 10.48 | -25.4294 |
| rat_man97 | 5 | 1.26 | 10.49 | -24.3547 |
| rat_armorers_wife | 6 | 1.15 | 10.65 | -20.7616 |
| rat_armorers_wife | 6 | 1.15 | 10.71 | -23.1778 |
| rat_woman43 | 6 | 1.15 | 2.62 | +0.0000 |
| rat_woman12 | 5 | 1.26 | 4.27 | +0.0000 |

**Damage is unchanged with the impulse switched off**, at 20 to 25 against the
22 to 29 recorded with it on. The impulse accounts for none of it. The earlier
conclusion that `actor:Fall()` alone costs the victim health stands, and the
magnitude measurement this test was run to obtain confirms it rather than
overturning it.

**Armor makes no difference either.** A guard in chain at 50.5 weight took
25.43, the largest cost of the ride, while unarmored villagers took 20 to 24.
The apparent armor mitigation recorded earlier was an artifact: `armorImpulse`
scales the impulse, the impulse moved the victim, and a victim thrown further
was read as a victim damaged more. With the impulse off the ordering vanishes.
Phase 2's note that armor mitigation "cannot be separated from zero" was
correct, and the later reading that armored targets take zero damage was wrong.

**The one predictor is the horse's speed at contact**, and it separates the two
groups perfectly. Every impact above 10 m/s cost 20 to 25. Both impacts under
5 m/s cost exactly nothing, despite scoring as Gallop from the peak of the
speed trail. That is the signature of `CollisionVelocityDeltaToDmgR` and it
confirms the trample mechanism directly: the cost is the horse striking the
body, scaled by how fast the horse is still going when it does.

**What this retires**: the lateral impulse, reverted. Aiming the impulse
differently cannot help when the impulse is not the cause. The remaining
candidate is to keep the physics body from existing while the horse is on top
of it, which is the deferred ragdoll.

## Deferring the ragdoll costs the impact and does not fix the damage

**Hypothesis**: an animation-driven actor cannot be struck by the horse and
costs nothing, so holding the victim upright until the horse has passed, then
ragdolling, removes the trample without changing anything else.
`RagdollDelayMs` set to 300, which at 10.5 m/s puts the horse 3.1 m clear
against a front reach of about 1.3 m.

**Result**: rejected on feel. The user's report: "it doesn't feel or look
natural and the horse basically sticks inside of them before they fall or I
clip them as I ride by and it doesn't feel impactful at all".

**And it does not buy much.** Gallop impacts at the 300 ms delay cost 13.9 to
22.2 where the same impacts cost 20 to 25 undelayed, and only impacts already
slow at contact reached zero. The delay narrows the window the horse and the
body share without closing it, because a horse that has just struck someone is
also decelerating into them. The trade is not feel against damage. It is feel
against a partial reduction.

Three hundred milliseconds is long enough for the horse to be visibly standing
inside a victim who has not reacted yet, and the delay breaks the causal link a
player reads between the strike and the fall. A collision that lands and then
waits does not register as a collision at all. Shortening the delay trades feel
back against damage along the same axis, because the damage window is exactly
the window the horse and the body share.

**What this leaves.** Both cheap fixes are now spent. The impulse does not cause
the damage and its direction cannot help. Delaying the body costs the impact
and only partly reduces the damage. The remaining approaches either stop the body existing at all, which is
the animated knockdown through `AnimationControlled`, or stop the horse and the
body colliding while both exist.

**The second of those is unexplored and is not a last resort.** KCD's Lua
exposes CryEngine collision filtering directly through
`SetPhysicParams(PHYSICPARAM_COLLISION_CLASS, filtering)`, and the vanilla
scripts use three fields on that table: `collisionClass` and
`collisionClassUNSET` in `GeomEntity`, `PickableItem`, `Ladder`, `AnimObject`,
`Bed` and `AlchemyTable`, and `collisionClassIgnore` in `TriggerBase`, which
sets it to -1 to ignore everything. Named class constants exist as Lua globals:
`BasicAnimal` declares `collisionClass = gcc_npc_ignored_type` and `Boar_x` and
`Pig_x` declare `gcc_npc_reported_type`.

If the victim's ragdoll can be told to ignore the horse for the second after it
is created, the ragdoll stays immediate, the impact keeps its impulse and its
timing, and the collision that charges the damage never resolves. That is the
only candidate so far which does not trade feel for damage.

## Filtering horse collisions off the ragdoll, first attempt

**Hypothesis**: the victim's ragdoll can be told to ignore the horse collision
class for a moment after it is created, so the ragdoll stays immediate and the
impulse stays untouched while the collision that charges the damage never
resolves.

**Implementation**: after `actor:Fall`,
`npc:SetPhysicParams(PHYSICPARAM_COLLISION_CLASS, { collisionClassIgnore = gcc_horse })`,
restored with `collisionClassIgnoreUNSET` after `HorseIgnoreMs`, default 1500.
Both field names are confirmed in the decompile, and both calls return cleanly
against a live NPC. `gcc_horse` is 65536; the full set of class globals is
`gcc_ai` 131072, `gcc_horse` 65536, `gcc_interactive` 262144, `gcc_ragdoll`
16384, `gcc_rigid` 32768, `gcc_npc_ignored_type` 2097152,
`gcc_npc_reported_type` 524288, `gcc_player_capsule` 1024, `gcc_player_body`
2048, `gcc_vehicle` 4096.

**Results**: a reduction, not a fix. Five gallop impacts cost 16.39, 16.53,
17.05, 19.15 and 19.42, against a 20 to 25 baseline. Trot fell to 3.7 to 4.9.

The user also reported seeing the horse phase through the victim on the first
gallop only, and not on any impact after it.

**Diagnosis: the filter is written before the body it is meant to apply to
exists.** `actor:Fall` does not physicalize the ragdoll within the same tick,
which the impulse code already accounts for by deferring itself by 50 ms. A
collision class written immediately after `Fall` lands on the living entity's
physics and is discarded when the ragdoll replaces it. That explains the
partial reduction, since the filter takes effect only from whenever it happens
to survive, and it explains the single visible phase-through: the one impact
where the ordering happened to work is the one where the horse passed through.

**Change**: the filter is now written three times, immediately, at 50 ms and at
200 ms, so at least one write lands after physicalization and covers the frames
where the horse is still on top of the victim.

## KCD has a working third-person camera

`g_tpview_enable 1` is accepted by the console and is not cheat-marked, with
`g_tpview_control` and `g_tpview_force_goc` alongside it. First-person at gallop
makes it very hard to see what an impact actually does, which has cost several
rides where the only usable evidence was the telemetry. The camera is a
development CVar, so it needs setting per session like the other console state.

## Re-timing the collision filter changes nothing

**Change tested**: the horse collision filter written three times, immediately
after `actor:Fall`, at 50 ms and at 200 ms, so that at least one write lands
after the ragdoll physicalizes.

**Results**: no improvement. Gallop impacts cost 16.89, 20.23 and 20.97,
against 16.39 to 19.42 with the single write and 20 to 25 with no filter at
all. The spread across all three configurations is the same.

The physicalization theory is wrong, or at least it is not what limits this.
Two possibilities remain and they are distinguishable by one test:

1. **The wrong class is being filtered.** `gcc_horse` is the obvious name, but
   a ridden horse may be classed as `gcc_ai`, as one of the `gcc_npc_` types,
   or the damage may be charged against the rider's own capsule rather than the
   horse. Nothing read so far reports an entity's actual collision class, and no
   getter for it is exposed.
2. **`SetPhysicParams` does not survive on a ragdoll at all**, in which case the
   whole route is closed regardless of which class is named.

**Next test**: filter every actor-like class at once, the union of `gcc_horse`,
`gcc_ai`, `gcc_npc_all`, `gcc_player_all`, `gcc_rigid` and `gcc_vehicle`, which
is 36412416. Engine-side classes below 1024 are deliberately excluded so the
body still collides with terrain instead of falling through the world. If the
damage goes to zero, the mechanism works and only the class was wrong. If it
does not, physics filtering cannot reach this and the remaining candidate is the
animated knockdown, which never creates a body at all.

## Physics collision filtering cannot reach the ragdoll

**Test**: `collisionClassIgnore` set to the union of every actor-like class,
`gcc_horse`, `gcc_ai`, `gcc_npc_all`, `gcc_player_all`, `gcc_rigid` and
`gcc_vehicle`, which is 36412416, applied at 0, 50 and 200 ms after
`actor:Fall` and restored after 1500 ms. Engine classes below 1024 were
excluded so the body still collides with terrain.

**Results**: unchanged. Gallop impacts cost 19.73, 21.23 and 21.44, squarely in
the 20 to 25 band measured with no filter at all.

Filtering every class the horse could possibly belong to changes nothing, so
the failure is not the choice of class. `SetPhysicParams` returns success on a
victim entity, but the collision class written there does not reach the ragdoll
the engine creates, and the trample resolves regardless.

**This closes the physics filtering route.** Taken with the two results above
it, every approach that leaves a physics body in the horse's path is now spent:

| Approach | Result |
| --- | --- |
| Redirect the impulse sideways | No effect. The impulse does not cause the damage |
| Zero the impulse entirely | No effect, 20 to 25 either way |
| Defer the ragdoll 300 ms | 14 to 22, and the impact reads as broken |
| Filter horse collisions off the body | 16 to 21, three timings tried |
| Filter every actor class off the body | 20 to 21 |

**What remains** is the approach that never creates a physics body: an animated
knockdown through the `AnimationControlled` path the walk stagger already uses.
The existence proof has been in every session's telemetry from the beginning.
Walk impacts cost exactly zero health, without exception, because the victim
never leaves the animation system. The work is to author or locate knockdown
fragments for the trot and gallop tiers, in the same way the stagger fragments
were added, so those tiers displace the victim through Mannequin rather than
through physics.

## RPG parameters can be overridden per character, not only globally

`CollisionVelocityDeltaToDmgR` is confirmed in `Libs/Tables/rpg/rpg_param.xml`
inside `Tables.pak`, as
`<row rpg_param_key="CollisionVelocityDeltaToDmgR" rpg_param_value="0.25" />`.

That table was treated as global, and overriding it was rejected on the grounds
that it changes the value for everything in the game including the player's own
collisions. A second table alongside it changes that reading.
`Libs/Tables/rpg/perk_rpg_param_override.xml` maps a perk to an RPG parameter
and a replacement value:

```
<column name="perk_id" type="uuid" />
<column name="rpg_param_key" type="character varying" />
<column name="rpg_param_value" type="real" />
```

So a parameter's effective value is resolved per character, against the perks
that character holds, and Warhorse ships the mechanism for doing it. Vanilla
uses it sparingly: one perk, twenty five keys, and no vanilla perk touches
`CollisionVelocityDeltaToDmgR`.

If a perk can be attached to a soul at runtime, a victim can carry a perk that
zeroes their own collision damage for the second the horse is on top of them,
and the player's collisions are untouched. Two things are unverified: whether
the parameter is resolved against the damaged character rather than the
attacker, and whether perks can be added and removed from Lua at all. No
`AddPerk` or `RemovePerk` appears in the Lua state dump, so the second question
has to be settled by enumerating the live `soul` methods.

Note also that reading vanilla tables needs a manual decompress.
`Tables.pak` stores backslash separators in its local file headers while its
central directory uses forward slashes, and Python's `zipfile` refuses the
mismatch.

## The damage may not be a defect

Worth recording before more work goes into removing it. The trample damage was
first investigated because it was believed to cause the lockup. It does not: a
victim wedges at full health with collision damage zeroed. Meanwhile Phase 3
lists "apply native blunt damage on high-speed impacts" as a wanted feature and
marks it already delivered.

Measured, the damage is 3 to 5 at trot and 16 to 25 at gallop against an
unarmored villager, scaling with the horse's speed at contact and costing
nothing when the horse has already slowed. That is close to what the design
asks for. The open question is therefore whether this needs removing at all, or
only tuning, and the answer decides whether any of the remaining approaches are
worth building.

## The lockup is vanilla's auto-cure daycycle, and the animation is PretendingIllness

Located in the game's own behavior tree data, in
`Libs/AI/final/sb_daycycles_cure.xml` inside `Scripts.pak`. The file declares
five trees: `cureStart`, `cure`, `cureLookHurt`, `cureFastStartCheck` and
`cureApplyPatch`. `cureLookHurt` is the state, and it is short enough to quote
whole:

```xml
<DecoratorBuff BuffId="e3edccf9-fb68-4399-b66d-0a06271a6b81" SoulWUID="this.id">
  <Parallel successMode="All" failureMode="Any">
    <LODGuardian LODTerm="OnBoth" StatProp="PropagateChild">
      <LOD>    <Wait duration="-1" timeType="GameTime" /> </LOD>
      <Detail> <PlayAnimation animation="PretendingIllness" /> </Detail>
    </LODGuardian>
    <Wait duration="-1" timeType="GameTime" />
  </Parallel>
</DecoratorBuff>
```

An NPC in this node plays `PretendingIllness` and waits **forever**. The wait
has no timeout, so nothing inside the subtree ends it. It ends only when the
parent withdraws it.

The buff it decorates itself with is `autoCure`, from `Libs/Tables/rpg/buff.xml`:

```xml
buff_name="autoCure" implementation="Cpp:Constant" duration="-1"
params="health+0.02/s"
```

So the node regenerates health at 0.02 per second, or 1.2 per minute of game
time, while the NPC stands there looking ill.

**The gate is health, and its value is 40.** `Libs/AI/final/sb_daycycles.xml`
declares `<Variable name="t_autoCureLowHealthLimit" type="_float" values="40.0" />`,
and `sb_daycycles_cure.xml` gates the cure on `NPCStateGate State="Health"
Target="this.id" Low="$t_autoCureLowHealthLimit"`.

### Every observation this explains

| Observation | Explanation |
| --- | --- |
| Victim stands in a looping hurt animation | `PlayAnimation "PretendingIllness"` under `Wait duration="-1"` |
| Alive, undamaged further, will not resume its schedule | The daycycle is running this activity instead of the NPC's own |
| Raising health releases it immediately | Health is the gate the parent re-evaluates |
| Setting a healthy NPC to 25 did not freeze it | The gate is read when the daycycle re-evaluates, not on a health write |
| It never recovers on its own | It does, at 1.2 health per game-minute, which reads as never |
| Combat claims the NPC normally and hands it back | The combat tree preempts the daycycle, then returns to it |
| `MinVictimHealth = 60` prevented it across 19 impacts | 60 is above the 40 gate |
| Stuck NPCs measured at 19.6, 26.0, 32.6 and 34.1 | All below 40 |
| Vanilla never shows it | Vanilla rarely leaves a non-combat NPC under 40 health standing in a street |

### What it is not

It is not an AI failing to resolve an attacker. The proposal that KCD's AI reads
damage with no valid `shooterId` and falls into an injured loop for that reason
does not survive the data: nothing in the cure trees examines a shooter, an
attacker or a hit at all. The trigger is one float compared against health.

It is also not a defect. This is designed vanilla behavior for a wounded NPC
with no other context, and the mod meets it only because the mod is the one
thing in the game that leaves ordinary townspeople badly hurt in the open.

### The levers, all of them Warhorse's own

- **Health above 40.** Already proven by `MinVictimHealth`, and the cheapest.
- **`$b_context['suppressAutoCure']`.** Both `sb_daycycles.xml` and
  `sb_daycycles_cure.xml` gate the entire cure on `!$b_context['suppressAutoCure']`,
  and eleven quest files set it, so it is the sanctioned way to exempt a
  character. `XGenAIModule.SetBrainVariable()` exists in the Lua state and is the
  candidate for reaching it.
- **`XGenAIModule.RemoveDaycyclePatch()`.** The cure installs itself through
  `cureApplyPatch`, and `t_daycycleCureInProgress` is marked `isPersistent="1"`,
  so a patch that never completes persists. This is the route to releasing an
  NPC already stuck.
- **A stronger regen.** The vanilla 0.02/s is what makes the state look
  permanent.

### The second state is still unexplained

A victim was recorded wedged at **96.4 health in an ordinary standing idle**,
not in `PretendingIllness`. That is above the 40 gate and in the wrong
animation, so it is not this. Two distinct states have been recorded under one
name, and only the low-health one is now understood.

## Low health alone does not start the cure, and the trigger needs a buff

**Test, from the console with no horse involved.** A healthy `rat_man97` at
100 health was set to 20, well under the 40 gate, and its animation state polled
every five seconds for a minute.

```
[IND] target=rat_man97 health=100.0 anim=MotionMovement
[IND] set health=20 -> now 20.0
[IND] t+5s  health=20.0 anim=MotionMovement
[IND] t+15s health=20.0 anim=MoveToIdle
[IND] t+55s health=20.0 anim=MotionMovement
```

**No `PretendingIllness`, and no regeneration.** Health held at exactly 20.0 for
the whole minute, so the `autoCure` buff was never applied either, which is
independent confirmation that the cure never started. The NPC walked its
schedule normally. This reproduces the earlier report that a guard set to 25
health "didn't freeze, he's acting normal", and it corrects the entry above:
**health below 40 is necessary but not sufficient.**

The full entry condition, read out of `cureStart`, is a gate followed by a
parallel:

```
IfGate    !$t_daycycleCureInProgress & !$b_context['suppressAutoCure']
  BuffTagCheck buffAITagId="4"  then buffAITagId="3"
  or ProcessMessage buffAdded where tagId in (poison, bleed, sleep)
  and NPCStateGate State="Health" Low/High="$t_autoCureLowHealthLimit"   (40.0)
```

So the cure needs **a buff and low health together**. A collision supplies the
buff, which is what earlier entries were pointing at when they called this "the
injury buff", and removing that buff afterwards does not help because by then
the cure activity is already running.

## The context option that suppresses the cure works, and it is vanilla's own

`Scripts/Script/Context.lua` ships a public API over the `b_context` brain
variable the trees read, and vanilla uses it for exactly this purpose.
`sa_event_wanderer.xml` calls:

```lua
Contexts.SetNonpersistentOption(wanderer, 'suppressAutoCure', 'event_wanderer')
```

and `sa_duel.xml` uses the message form, which expires on its own:

```
InstantSendMessageToNPC target="this.id" type="context:timedOptionRequest"
  values="option('suppressAutoCure'),expiration(30),handle('sa_duel')"
```

**Both were exercised live against an NPC and both were accepted**, and the
option was read back rather than trusted to a return value:

```
[CTX] check before ok=true val=false
[CTX] SetNonpersistentOption ok=true err=nil
[CTX] check after  ok=true val=true
[CTX] timedOptionRequest ok=true err=nil
```

`Contexts.CheckOption` reports the option is set, so the state really changed.
Whether it prevents the lockup is a separate question and needs a ride.

The message form is the better fit. It carries its own expiration, so a victim
cannot be left permanently exempt if the mod misses its cleanup, and the mod
already sends brain messages this way for `hitReaction`.

`XGenAIModule.GetBrainVariable(entity.id, 'b_context')` returns nil, so the
brain variable is not readable directly by that name from Lua. `Contexts`
maintains its own table and is the supported route. `SetBrainVariable`,
`GetBrainVariable` and `RemoveDaycyclePatch` are all present on this build.

## The lockup reproduced on demand, and suppressed on demand

A controlled A/B, run entirely from the console with no horse and no collision.
Two guards standing in the street. Both were set to 20 health and given the
`bleeding` buff, `0c903899-fcc9-4cf2-9ee3-1130ac08b0fc`, which carries
`buff_ai_tag_id="4"`, one of the two tags `cureStart` checks. The only
difference between them was one line:

```lua
Contexts.SetNonpersistentOption(B, 'suppressAutoCure', 'hcm')
```

Result, five seconds later:

```
[AB] A=villageGuard suppress=false
[AB] B=rat_guard24   suppress=true
[AB] A health=20.0 addBuff=true
[AB] B health=20.0 addBuff=true
[AB] t+5s  A 20.1 PretendingIllness  |  B 20.0 MotionMovement
```

**A entered `PretendingIllness`. B carried on walking.**

Three things are settled by that line:

- **The lockup is `cureLookHurt`, and it reproduces on demand.** Bleeding plus
  health under 40 is the whole trigger. No horse, no ragdoll, no collision, no
  attacker, and five seconds from a standing start.
- **`suppressAutoCure` prevents it.** Same health, same buff, same second, and
  the only difference was the context option.
- **The `autoCure` buff confirms which subtree is running.** A's health had
  already moved from 20.0 to 20.1 while B's had not, which is the 0.02 per
  second regeneration the `DecoratorBuff` on `cureLookHurt` applies. Nothing
  else in the game was healing A.

That last point matters as evidence, because it is a number moving on a later
sample rather than a function reporting success, which is the standard this
project settled on after several ScriptBinds were found to accept calls and do
nothing.

### What this means for the mod

The mod does not need to avoid ragdolls, avoid damage, or keep victims above a
health floor to avoid the lockup. It needs to tell the game that a trampled
villager is not a candidate for the auto-cure daycycle, using the same call
vanilla uses for a duellist or a scripted wanderer.

The message form is preferable to the direct call because it expires by itself:

```
XGenAIModule.SendMessageToEntity(npc.id, 'context:timedOptionRequest',
    "option('suppressAutoCure'),expiration(30),handle('HorseCollisionMod')")
```

`MinVictimHealth` and `HoldVictimAboveFloor` can then come out. They worked, but
they bought the fix by preventing a collision from ever being able to kill,
which was a real change to what the mod does in play.

## The auto-cure exemption holds in play, and trampling can kill again

**Build**: every impact sends the victim
`context:timedOptionRequest option('suppressAutoCure') expiration(30)`.
`MinVictimHealth` at 0 and `ClearCollisionInjuries` off, so nothing else was
protecting the victim.

**User report**: "I hit her maybe 5 times in total. I didn't see any change in
behavior that wasn't what was expected. No lockup. Just kept getting up and
returning to walking. I did eventually kill her though and now the guards are
pissed and trying to kill me."

Five gallop impacts on `rat_bailiff_wife`, an unarmored villager:

| Impact | Speed at contact | Health before | Delta |
| --- | --- | --- | --- |
| 1 | 5.08 | 78.08 | +0.0000 |
| 2 | 10.76 | 78.08 | -18.1326 |
| 3 | 6.36 | 38.11 | +0.0000 |
| 4 | 10.66 | 38.11 | -30.9845 |
| 5 | 10.72 | 7.12 | -7.1229, dead |

**She was at 38.11 health across two impacts, under the 40 gate, and did not
enter `PretendingIllness`.** That is the condition which produced the lockup on
demand in the controlled A/B, and the exemption held through it. `SuppressAutoCure`
logged on all five impacts.

Two things follow beyond the lockup:

- **A collision can kill again.** The last impact took her from 7.12 to 0. The
  old `MinVictimHealth` floor made that impossible, so removing it restores
  something the mod is meant to be able to do.
- **The crime system engages on its own.** Guards turned hostile after the
  death with no code in the mod for it, which is the Phase 3 behavior arriving
  without being built.

### The gap this ride did not test

The victim died shortly after falling under 40, so the exemption never had to
outlast her. The realistic case is different: a rider knocks someone down twice,
leaves them alive at 30 health, and rides away. Thirty seconds later the
exemption lapses while they are still under the threshold and still bleeding,
which is exactly the entry condition again. Whether the cure starts at that
point is untested and is the next thing to settle.

## The exemption expires cleanly, and the cure has a branch that works

**Test**: `rat_swordsmith_helper` set to 20 health with the `bleeding` buff and
a 30 second `suppressAutoCure` exemption, then polled for 70 seconds, which is
40 seconds past the expiry.

```
[EXP] t+5s  health=20.0 anim=MotionIdle
[EXP] t+30s health=20.0 anim=MotionIdle
[EXP] t+70s health=20.0 anim=MotionIdle
```

Followed by a direct check:

```
[EXPCHK] rat_swordsmith_helper health=43.6 anim=MotionIdle suppressStillSet=false
```

Two results. **The timed option really does expire**, so the message form is
safe to use and cannot strand a victim outside the daycycle. And **no lockup
followed the expiry**: the NPC never entered `PretendingIllness` at any point.

Health then moved from 20.0 to 43.6. That is far too large a step for the
`autoCure` regeneration of 0.02 per second, which would have produced about 0.8
over the same window, so something else restored it. The likely candidate is
the branch of `cureStart` that actually treats the injury rather than the one
that stands still: the file declares `cure` and `cureApplyPatch` alongside
`cureLookHurt`, and `bandage` appears 27 times in it. **This is unconfirmed**,
and the only firm claims are the two above.

If that reading is right, `cureLookHurt` is the fallback for an NPC that cannot
treat itself, and whether a victim locks up depends on the victim. The guard in
the earlier A/B entered `PretendingIllness` within five seconds and stayed there
for the full ninety, while this NPC recovered on its own. That difference is
worth settling, because guards are the most likely thing a rider tramples
repeatedly.

## The message form of the context request can be dropped

An attempt to repeat the expiry test on a guard failed before it started, and
the failure is worth more than the test would have been:

```
[GRD] target=villageGuard health=20.0 anim=<unknown> sup=false
[GRD] t+5s  health=20.0 anim=<unknown> sup=false
[GRD] t+55s health=20.0 anim=<unknown> sup=false
```

`Contexts.CheckOption` read **false immediately after** the
`context:timedOptionRequest` message was sent, so the option was never set. The
guard was hostile at the time, following a kill earlier in the session, and
`GetCurrentAnimationState` returned `<unknown>` throughout, which is consistent
with combat owning the actor.

The direct call does not behave this way. Earlier in the session
`Contexts.SetNonpersistentOption` was applied to this same `villageGuard` and
`CheckOption` read back true immediately.

**A brain message is a request, and a busy brain can drop it.** The direct call
writes the Contexts table itself and does not depend on the brain accepting a
message. This is the same trap recorded earlier in this diary, where a
ScriptBind accepted a call and did nothing: the mod logged
`SuppressAutoCure ... for=30s` on all five impacts of the successful ride, and
that line only proves the message was sent.

The implementation should therefore use `Contexts.SetNonpersistentOption` with
its own scheduled `ClearOption`, and verify with `CheckOption` rather than
trusting either. Non-persistent is the right form for a second reason: it does
not survive a save, so an exemption the mod fails to clear cannot become
permanent in a player's game.

A guard in combat is also an invalid subject for any cure test, since combat
preempts the daycycle. Tests of this kind need a calm area.

## The exemption must be set before the injury, not after

Two runs, same buff, same health, same option, different order.

**Option set after the injury** (`villageGuard`):

```
[G2] target=villageGuard health=86.9 anim=MotionMovement
[G2] armed health=20.0 sup=true
[G2] t+5s health=20.1 anim=PretendingIllness sup=true
```

**Option set before the injury** (`rat_swordsmith_helper`):

```
[G3] target=rat_swordsmith_helper sup=true  (option set FIRST)
[G3] armed  health=20.0 anim=SmithGrab   sup=true
[G3] t+5s   health=20.0 anim=SmithGrab   sup=true
[G3] t+10s  health=20.0 anim=SmithHeating sup=true
```

The second NPC carried on with its job animations and did not regenerate,
so the cure never started. The first entered `PretendingIllness` **while the
option read true**.

**The gate is evaluated when the cure starts, and setting the option afterwards
does not cancel a cure already running.** The `IfGate` in `cureStart` carries
`RunLogic="KeepRunning"`, so a subtree already entered keeps running regardless
of the condition that admitted it. This is the same shape as the earlier finding
that removing the injury buff from a stuck NPC does not release it.

### Why the mod is nonetheless correct

`SuppressAutoCure` is called from `TriggerCollision`, at the moment of impact,
while collision damage resolves around 500 ms later. The exemption is therefore
in place before health can cross the threshold, which is the order that works,
and it is why the ride test passed with a victim held at 38 health.

### What it rules out

The exemption cannot be used to repair an NPC that is already stuck, in a save
or otherwise. That needs a different lever, and the candidates are raising
health above 40, which is already known to work, and
`XGenAIModule.RemoveDaycyclePatch`, which is untested.

## An NPC already in the cure can be released, without healing it

The cure installs itself as a daycycle patch. `cureApplyPatch` sends:

```
SendMessageToNPC target="this.id" type="daycycle:change"
  values="add(true), once(true), handle('curePatch'), name('cure'), priority(34)"
```

so the handle is `curePatch`, and `XGenAIModule.RemoveDaycyclePatch(wuid, handle)`
is documented to remove it and to report whether it did.

**Removing the patch alone is not enough.** A first attempt removed the patch
and also reset `t_daycycleCureInProgress` to false. The patch removal reported
true, and the guard was back in `PretendingIllness` five seconds later: clearing
that flag reopened the gate while the NPC was still bleeding under 40 health, so
the cure simply started again.

**Suppress first, then remove.** Applying the ordering rule established above:

```
[FX2] before health=23.7 anim=PretendingIllness sup=false
[FX2] step1 suppress set=true
[FX2] step2 RemoveDaycyclePatch returned=true
[FX2] t+5s  health=23.7 anim=IdleToMove     sup=true
[FX2] t+10s health=23.7 anim=MotionMovement sup=true
[FX2] t+15s health=23.7 anim=MotionMovement sup=true
```

The guard stood up and walked his patrol again **at 23.7 health**, still
bleeding, without being healed.

The strongest evidence in that block is the health column. It had been climbing
by 0.02 every second for the previous three minutes, and it stops dead at 23.7
and stays there. The `autoCure` buff is attached to `cureLookHurt` by a
`DecoratorBuff`, so regeneration stopping is proof the subtree itself is gone
rather than merely out of view, which is what the earlier `MotionIdle` samples
turned out to be.

### The `LODGuardian` explains an earlier misreading

During the expiry test the same guard left `PretendingIllness` at t+70s and
showed `MotionIdle` while health kept climbing at the same rate. That is not a
recovery. `cureLookHurt` wraps its animation in a `LODGuardian`, which plays the
animation only in the `Detail` branch and substitutes a plain wait in the `LOD`
branch, so a victim the player is not close to stops performing the animation
while remaining in the subtree. **Animation state alone is not a reliable test
for this state; the regeneration is.**

### Both halves are now proven

- **Prevention.** Set the option before health crosses the threshold. The mod
  does this at impact, and collision damage resolves about 500 ms later.
- **Repair.** Set the option, then remove the `curePatch` daycycle patch. This
  releases a victim already stuck, at low health, without healing them, so it
  does not cost the mod its ability to trample someone to death.

## Entry into the cure is not immediate for every NPC

Attempts to manufacture the stuck state on demand succeed on some NPCs and not
others. `villageGuard` entered `PretendingIllness` within five seconds of being
set to 20 health with the `bleeding` buff, twice. `rat_man95` and
`rat_swordsmith_helper`, given the same treatment, were still walking with
health flat at exactly 20.00 half a minute later, and the flat health shows the
`autoCure` buff was never applied, so the cure had not started rather than
having started invisibly.

The buff and the health threshold are necessary but the daycycle also has to
re-evaluate, and when that happens depends on what the NPC is doing.
`sb_daycycles_cure.xml` declares a `cureFastStartCheck` tree and `sb_daycycles.xml`
carries a persistent `t_fastStart` variable, so there is a fast path and a slow
one. Which NPCs take which is not established.

Two practical consequences. A guard is a reliable subject for this state and a
townsperson is not, which is worth knowing before spending a test on one. And
the mod cannot be judged to have fixed the lockup by watching a single victim
fail to enter it, since some victims would not have entered it anyway. The
evidence that matters is the controlled A/B, where two NPCs were treated
identically in the same second and only the exempt one stayed free.

## The wedge at 96.4 health was an artifact of the modified collision parameter

Recorded so it is not chased again. The one observation that did not fit the
auto-cure explanation, a victim wedged at 96.4 health in an ordinary standing
idle rather than in `PretendingIllness`, was made during the session that ran
with `CollisionVelocityDeltaToDmgR` set to 0 in a loose `rpg_param.xml`.

That table override is a diagnostic that was tried once and rejected, and it is
not something the mod ships or that a player would ever have. The observation
therefore describes a game state that no longer exists and cannot recur unless
the parameter is deliberately overridden again.

It also explains the anomaly on its own terms: with collision damage zeroed the
victim could not fall under 40 health, so whatever held them was not the cure,
and there was no reason to expect `PretendingIllness`.

**There is no second lockup state to explain.** The 96.4 reading is retired.

## Which NPCs enter the cure

The entry timing above is worth stating as a practical rule, and it matches an
earlier session the user recalled, where a named NPC took collision damage
repeatedly, never locked up, and was eventually killed.

`villageGuard` entered `PretendingIllness` within five seconds, twice, under
controlled conditions. `rat_man95`, `rat_swordsmith_helper` and
`rat_bailiff_wife` never entered it under equivalent or worse treatment.

So the state is far more readily produced on guards than on ordinary or named
townspeople, which is consistent with every report of it in this project: every
stuck NPC recorded here has been a guard. That is also the worst case for a
player, since guards are what a rider tramples repeatedly, so the fix is aimed
at the right target even though the state is not universal.

## A polearm guard takes no walk stagger and drops the weapon on a ragdoll

**User observation**, recorded for the animation work rather than acted on now:

> "I noticed a guard with a polearm? or whatever type of special weapon that is
> and that the walk stagger did not work on him and when he was rag dolled from
> a trot/gallop, he dropped his weapon and then walked off."

Two separate behaviors on one target, and both are consistent with things
already known about this mod.

The walk stagger plays through `actor:StartInteractiveActionByName` against the
mod's `AnimationControlled` FragTags. Those fragments were authored for the
ordinary human male and female databases, and Mannequin selects a fragment by
tag against what the actor currently holds. A two-handed polearm puts the actor
in a weapon state the mod's four fragments do not cover, so the request resolves
to no fragment and nothing plays, which is the same signature recorded earlier
for a name that does not resolve. It is not a detection failure: the impact was
scored, and the same guard reacted to the knockdown tiers.

The dropped weapon is the physics path rather than the animation path, and it is
already on the roadmap as a known consequence of `actor:Fall`. Recovering a
dropped item is vanilla's own `panicDrop` behavior in `sb_combat.xml`, which the
roadmap parked because that tree is 133 KB with no additive route.

**Why this matters for the trot work.** Converting trot from a ragdoll to an
animated knockdown does not automatically cover this target. Whatever fragments
the trot tier uses will need to resolve for an actor holding a two-handed
weapon, or that guard will take no reaction at trot either, which is worse than
the ragdoll he gets today. A weapon-state axis therefore has to be part of the
fragment work rather than an afterthought, and the polearm guard is the test
case for it.

## The animation palette available for a trot knockdown

Read out of the game's own data rather than guessed, in preparation for
replacing the trot ragdoll with an animated knockdown.

**Where the clips are.** `Animations/Animations.img` inside `Animations-part0.pak`
holds the catalogue, 139,096 clip paths for humans. The reaction animations are
in `animations/humans/male/hitdeath/`, 102 clips, and
`animations/humans/female/hitdeath/`, 60.

**Where the fragments are.** Both the stagger clip the mod already uses and
vanilla's fall-to-ground clips live in the `HitDeath` fragment of
`kcd_male_database.adb`, not in `AnimationControlled`. The
`AnimationControlled` fragment holds 32 fragments and every one of them is an
object interaction: doors, gates, a cabinet, a wardrobe, an alarm bell. That is
why the mod copies a clip into a FragTag of its own rather than invoking a
vanilla one: `actor:StartInteractiveActionByName` reaches
`AnimationControlled`, and the reactions are not in it. The same copy applies
to a knockdown.

### Two candidates, and they are not equivalent

**`collision_stand_{front,back,left,right}_heavy`.** Four directional clips,
named for exactly this case, and **referenced zero times in the vanilla male
database**. The animation was authored and never wired to a fragment. It is
male only; the female set has no equivalent.

**`relaxed_death_walk_{front,back,left,right}_01`.** Four directional clips,
present for **both** male and female, and used by vanilla in `HitDeath` under
`FragTags="so_forward+death"` with `Tags="walk"`, which is a person collapsing
to the ground while walking. That is the shape of a knockdown.

The recovery half exists for both genders as
`getup_ground_{front,back,left,right}` in `behavior/`.

### What that forces

The mod already reaches men and women, and the female database gap has cost
this project once. A reaction that exists for men only cannot be the trot
tier's reaction. **`relaxed_death_walk_*_01` is the candidate that can be**,
with `collision_stand_*_heavy` worth testing separately as a heavier standing
reaction for men.

Two things are unknown and neither can be read from a filename: whether
`collision_stand_*_heavy` puts a target on the ground or only rocks them, and
whether a victim playing a death fall gets up again on their own or stays
prone. Both are one build and one ride.

### The polearm constraint still applies

Mannequin selects a fragment against what the actor holds, and the walk
stagger already fails to resolve for a guard carrying a two-handed polearm.
Whatever the trot tier uses has to resolve for that actor as well, or that
guard gets no reaction at trot where today he gets a ragdoll, which is worse
than the state being replaced.

## An animated knockdown resolves and recovers on its own

`hcm_knockdown_{forward,back,left,right}` added to the mod's
`AnimationControlled` options, mapped to `relaxed_death_walk_*_01`, which both
character sets carry. Played on a standing NPC from the console, with no horse
and no ragdoll:

```
[K] target=rat_man97 before=MotionMovement z=77.35
[K] hcm_knockdown_forward ok=true err=nil
[K] t+1.5s anim=AnimationControlled z=77.35
[K] t+3.0s anim=AnimationControlled z=77.35
[K] t+4.5s anim=MotionMovement      z=77.41
[K] t+10.5s anim=MotionMovement     z=76.86
```

Two results. **The fragment resolves**, which `anim=AnimationControlled` shows
and which is the same signal the walk stagger gives. And **the victim recovers
without help**: the interactive action ends after three to four seconds and the
NPC returns to its own locomotion. A death clip played this way does not leave
anyone prone, so the trot tier does not need a scheduled `getup_ground_*` to
follow it.

Since nothing here creates a physics body, this path cannot incur the trample
damage that the ragdoll does. Whether it reads as a knockdown on screen is a
separate question and needs eyes rather than telemetry.

### The unreferenced collision clips cannot be reached yet

`collision_stand_{front,back,left,right}_heavy` were tried first and rejected
by the builder:

```
clips absent from the male database: ['collision_stand_front_heavy', ...]
```

The assets exist under `animations/humans/male/hitdeath`, but no fragment in
the stock database references them, so they never appear in its animation list,
and `build_adb.py` validates a clip by looking for it there. Reaching them
means validating against the character's animation set instead. They are male
only regardless, so they could not carry a tier by themselves.

### Two tooling faults found on the way

`dev_console.py --lua` sent chunks that did not compile and the game dropped
them without a word, which is indistinguishable from a chunk that ran and found
nothing. It now compiles the chunk locally first and refuses to send one that
fails, naming the error. Several rounds of this session were spent reading
results that were never produced.

`build_adb.py` reported the size of its whole reaction table as the number of
options written, so a character set that received fewer would still have been
reported as complete.

## The animated knockdown reads correctly going down and badly coming up

**User observation**, watching `hcm_knockdown_*` played on a merchant at normal
speed, cycling all four directions:

> "she goes down and thin unnatural snaps back up. the four directions do
> slightly differ some of them are way too slow and more dramatic type of
> reactions that I don't think would make sense."

Three findings, and only the first was in question before the test:

- **The victim does go to the ground.** The animation reads as a fall, which
  the telemetry could not establish: the entity origin does not move during it,
  so `z` holds at its standing value throughout and says nothing about the
  pose.
- **The recovery is wrong.** The interactive action ends and the victim snaps
  upright rather than getting up. Nothing plays a get-up: the fall clip runs to
  its end and control returns. `getup_ground_{front,back,left,right}` exists
  for both character sets and is the obvious next piece.
- **`relaxed_death_walk_*_01` is not four equivalent clips.** Some directions
  are slower and more theatrical than a horse impact warrants, which is
  unsurprising for animations authored as deaths. The direction variants need
  choosing individually rather than taken as a set.

Slow motion was tried first as a way to see it and was the wrong instrument.
A reaction cannot be judged for feel at 35 per cent speed, since the thing being
judged is how it reads at the speed it will be played. Looping it at normal
speed is what produced usable answers.

## Trot on the animated knockdown: reads decently, three faults

**User report** after riding with `TrotReaction = "knockdown"`:

> "I think it looks decent, but not perfect. The effect of the NPC feeling
> sticky and the horse kind of feeling muddy while the animation is firing. The
> snap back needs to be address as it is unnatural."

- **Sticky victim, muddy horse.** The horse and the victim push against each
  other while the animation runs. This is the same complaint recorded against
  the walk stagger, where setting the animation's `ColliderMode` to `Disabled`
  did not resolve it and was reverted for matching vanilla. The knockdown makes
  it worse in one specific way: the victim is on the ground for three to four
  seconds rather than staggering for one, so the window in which a horse can
  snag on them is several times longer.
- **The snap back up**, already recorded above. The fall clip ends and control
  returns with no recovery played.
- The knockdown carries none of the impact's momentum, which is the structural
  difference from a ragdoll and is not fixable by choosing a different clip.

### An armor observation, and what the code actually does

> "it feels like the guards/more armored NPCs were getting impacted more by
> trotting than galloping when we still had it wired for fall/rag doll whichs
> makes me curious if the armor wiring is correct"

Read rather than assumed. `ArmorCurve` is called with `invert=true`, so the
ratio is `reference / weight`: heavier armor gives a smaller multiplier, and
armored targets are moved less, which is what the design intends. The tier
scalars are 0.6 at trot and 1.0 at gallop and they multiply that same figure,
so for any one target **gallop always applies 1.66 times the trot impulse**.
A guard at weight 58 scores 0.371, giving 0.22 at trot against 0.37 at gallop.

The arithmetic therefore cannot produce the reported ordering, so if armored
targets really did move more at trot, the cause is elsewhere: the footprint
behaving differently at speed, the deferred impulse landing after a fast horse
has gone, or the visible damage at gallop being read as impact. **None of this
is measurable today, because the impulse magnitude the mod actually applies is
computed and never logged.** That is the gap to close before drawing any
conclusion.

## The fixed exemption window was wrong, and a guard proved it in play

**User report**, standing beside the NPC: "I hit the same guard a fews times
and he's in the locked up, injured animation loop that I thought we had
addressed before. Do this animations have damage or did some fluke happen
here?"

Neither. Measured live on the nearest NPC:

```
[N] nearest=villageGuard dist=2.7m health=40.59 anim=PretendingIllness suppress=false
[N] t+4s  health=40.67 anim=PretendingIllness
[N] t+16s health=40.91 anim=PretendingIllness
```

Health climbing 0.02 per second is the `autoCure` buff, and
`suppress=false` is the whole explanation: **the exemption had expired.** The
impacts logged him at 62.7, then 52.4, then 42.0, and the damage that followed
the last one took him just under the threshold. Thirty seconds later the
exemption lapsed, the gate opened, and the cure started.

This is exactly the gap recorded when the message form was first tested and
never closed. It was described then as the realistic case and it is: a rider
knocks someone down, leaves them alive under 40, and rides away.

**A fixed window cannot be right at any value.** What it has to outlast is the
victim climbing back over 40 at 0.02 health per second, which from 30 health is
just under nine minutes of game time. The exemption is now held until the
victim is above `AutoCureHealthLimit`, rechecked on the same interval, with one
watcher per victim and a token so a second impact replaces the first rather
than running beside it.

**The animated knockdown is not the cause and does still damage.** It creates
no physics body, so the trample cost is gone, but the mod's `hitReaction`
message is still converted by vanilla into a real player-attributed
`combat:hit` carrying `hitStrength`, and that lands. Trot cost about 10 health
per impact across the three logged here.

The guard was released in place with the mod's own `SuppressAutoCure`, which
now carries the patch removal:

```
SuppressAutoCure villageGuard for=30s set=true
[R] t+4s health=41.39 anim=PretendingIllness
[R] t+8s health=41.39 anim=MotionMovement
```

Health stopped moving at 41.39, which is the regeneration ending with the
subtree rather than the animation merely changing.

## The get-up chains, and clips through uneven ground

**User report**: "the get up animation does chain, but the NPC clips through as
the ground isn't PERFECTLY flat and the transition isn't smooth."

The fall and the get-up are two separate interactive actions with nothing
blending them, and neither is aligned to the ground under the victim. On a
slope the pose at the end of the fall and the pose at the start of the get-up
do not meet, and the body passes through the terrain between them.

## Where the damage comes from, since the animation is not it

A question worth answering plainly, because the reasoning behind it is right:
if trot now uses the same mechanism as the walk stagger, and walk costs
nothing, why does trot cost anything?

**The fragment has never been the source.** Playing an animation on an NPC does
not hurt them at any tier. There have always been two separate sources, and
only one of them is gone:

1. **The hit reaction.** `SendHitReaction` posts vanilla's `hitReaction` brain
   message carrying a `hitStrength`, and vanilla converts a player-ridden
   collision into a real, player-attributed `combat:hit` carrying that
   strength, which the engine then resolves against the target. The strength is
   the whole difference between the tiers: walk sends `Tickle` at 2, trot sends
   `MinorInjury` at 5, gallop sends `MajorInjury` at 6. **Walk costs nothing
   because it sends a strength that does nothing, not because it plays an
   animation.** This is Phase 3's blunt damage, already wired, and it is
   wanted.
2. **The trample.** The horse striking the physics body a ragdoll creates,
   charged by the engine on the velocity delta. **This is the one the animated
   knockdown removes**, because no physics body is ever created.

Measured on the animated knockdown, trot costs 4.6 to 5.7 per impact with
`dz=+0.00` on every sample, against 3.7 to 4.9 under the ragdoll. So the trot
figure barely moved, which is expected: at trot the horse is slow enough that
the trample component was small to begin with. **The gain from this change is
at gallop**, where trample was 20 to 25, and gallop is still on the ragdoll.

An earlier note in this session put trot at about 10 per impact. That was read
from the difference between consecutive impact lines, which spans everything
that happened in between, rather than from the probe delta. The probe figures
above are the right ones.

## Chaining the get-up on a timer does not work

**User report**: "almost every single one looks glitchy as the timing between
the animations is definitely off and the guards clips and even one time got up
in mid air floating... the animation triggers, then it seems to in one frame
snap them back into walking, then again snaps them back on the ground for the
getting up animation."

The description is exact and the cause follows from it. The fall is one
interactive action and the get-up is a second, fired by a Lua timer at a fixed
`KnockdownGetupMs`. The fall clips do not all run for the same time, which the
user had already noticed as some directions being slower, so a single fixed
delay is early for some and late for others. When it is late the victim has
already regained control and started walking, and the get-up then drags them
back to the ground from wherever they had walked to, which is the snap sequence
reported and also how a get-up ends up playing in mid air.

**A fixed delay cannot be tuned into correctness**, for the same reason the
auto-cure exemption window could not: it is standing in for a duration the
system already knows and Lua does not.

The fragment is the place to fix it. A Mannequin `AnimLayer` takes a sequence
of clips, so the fall and the get-up can be one option that Mannequin times and
blends itself, with no Lua timing and no gap for the victim to escape through.
`KnockdownGetupMs` is set to 0 in the meantime, which restores the single fall
and its abrupt recovery.

## The fall and the get-up as one Mannequin sequence

A Mannequin `AnimLayer` plays several clips in order, and vanilla relies on it:
568 options in the stock male database hold two or more, sequencing a jump into
its fall the same way.

```xml
<AnimLayer>
  <Blend ExitTime="0" StartTime="0" Duration="0.2" />
  <Animation name="relaxed_death_walk_front_01" />
  <Blend ExitTime="-1" StartTime="0" Duration="0.2" />
  <Animation name="getup_ground_front" />
</AnimLayer>
```

`ExitTime="0"` on the first clip starts it at once. `ExitTime="-1"` on the
second begins the transition when the first has finished, so **the sequence is
timed by the animations and not by Lua**. That removes the fixed delay
outright, and with it the gap the victim was escaping through.

Measured on a standing guard, the whole action now holds the actor for about
5.5 seconds against 3.5 for the fall alone, and leaves through `IdleToMove`
into ordinary locomotion:

```
[S] t+1.0s anim=AnimationControlled
[S] t+5.0s anim=AnimationControlled
[S] t+6.0s anim=IdleToMove
[S] t+8.0s anim=MotionMovement
```

`PlayGetup`, `KnockdownGetupMs` and their setting are removed rather than left
at zero. The fragment does the work, and a knob whose only remaining function
is to reintroduce the fault is not worth keeping. The standalone `hcm_getup_*`
options stay, since they cost nothing and give the recovery a name that can be
played on its own.

## The knockback varied with how hard the horse braked, not with the target

The user reported twice that armored and unarmored knockback at gallop did not
feel right. The impulse magnitude was added to the telemetry to make it
checkable, and it found a fault the armor arithmetic did not have.

`TriggerCollision` is handed the **live** velocity and the **scored** speed, and
they are deliberately different numbers: the score is the peak of the last few
ticks, so a collision is rated by the speed the horse carried into it rather
than by the speed left after contact slowed it. `Ragdoll` then built its
direction as `velocity.x / speed`, dividing one by the other. That leaves a
direction shorter than unit whenever the horse has slowed, and an impulse
weakened by exactly that ratio.

One target, one tier, one armor value, from a single ride:

| Victim | scale | sampled / scored | Predicted | Logged |
| --- | --- | --- | --- | --- |
| rat_armorers_wife | 1.15 | 10.14 / 10.14 | 67.0 | 67.3 |
| rat_armorers_wife | 1.15 | 2.84 / 10.72 | 37.7 | 37.7 |

`sqrt((50 * 1.15 * 0.265)^2 + (30 * 1.15)^2)` is 37.7, so the model accounts
for the reading exactly. The same woman took 1.8 times the knockback depending
on how hard the horse happened to brake.

The armor scaling itself was never wrong. Across the same ride, unarmored
targets scored 1.15 to 1.26 and took 40.9 to 73.4, while guards scored 0.35 to
0.42 and took 20.3 to 24.3, which is the intended ordering. The noise on top of
it is what made the ordering hard to feel.

The direction is now normalised against the velocity's own length. The scored
speed keeps its two jobs, choosing the tier and scaling the impulse, and no
longer sets the direction's length as well.

## Crime accumulates per collision

**User report** after a gallop kill: "I got arrested and my jail time is REALLY
high. I get it, every one of those collisions is being counting as a crime and
it's pilling up, but that might be something we need to tune when we get to the
crime feature implementation."

Recorded for the crime phase rather than acted on. Vanilla attributes every
player-ridden collision to the rider as a real `combat:hit`, so a ride through a
crowd registers an assault per impact and the sentences compound. The mod sends
one `hitReaction` per impact by design, and the per-impact cooldown governs how
often that can happen, so the tuning levers already exist.

## Vanilla settles a fallen body with a ragdoll, two seconds in

The mod's knockdown fragment was diffed against the vanilla `HitDeath` option
that plays the same clip. Vanilla carries one layer the mod's copy does not:

```xml
<ProcLayer>
  <Blend ExitTime="2" StartTime="0" Duration="0.2" />
  <Procedural type="Ragdoll">
    <ProceduralParams>
      <Sleep value="0" />
      <Stiffness value="100" />
    </ProceduralParams>
  </Procedural>
</ProcLayer>
```

**That is what conforms a fallen body to the ground.** The animation plays for
two seconds and then the body is handed to a stiff ragdoll, which settles it
onto whatever terrain is actually there. Without it the clip plays its authored
pose regardless of the slope underneath, which is exactly the clipping
reported.

`MovementControlMethod` is otherwise identical to the mod's copy, `Horizontal`
at 2 and everything else at zero, so nothing else is missing. Vanilla also
leaves its second clip slot empty, `<Animation name="" />`, because the ragdoll
is what follows the fall in a death. The mod puts the get-up there instead.

### Why this is not a return to the physics knockdown

The ragdoll the mod removed was created at the moment of impact, underneath a
horse still traveling through that space, and the engine charged the trample
that followed. This one is created **two seconds after the animation starts**,
by which time a horse at trot has covered something like fourteen meters and is
nowhere near the body.

It is the deferred ragdoll the roadmap proposed and Lua could not deliver. The
Lua attempt delayed the whole reaction, so the victim stood upright while the
horse stood inside them, and it was rejected on feel. Timed inside the fragment
it defers only the physics settle: the fall plays immediately and reads
correctly, and the body goes physical once, late, purely to find the ground.

**The open question is the get-up.** Vanilla never needs one here because this
is a death. Whether an actor handed to a ragdoll at two seconds can be returned
to an animated recovery is not answered by reading, and is the next test.

## The settle layer works, and a stale target nearly buried it

The ragdoll settle layer was added to the knockdown options and the first test
showed nothing playing at all, on either the knockdown or the walk stagger. The
stagger failing too was read as the whole database having been rejected, and the
layer was reverted.

**That diagnosis was wrong.** The stagger still failed after the revert. The
target was the fault: the test reused an entity captured by an earlier run,
which happened to be the NPC that had taken twenty-four knockdowns during a
loop and had logged `Animation-queue overflow. More then 16 entries`. A fresh
target played the reverted build immediately, and played the settle build
immediately as well.

The project's own rule covers this and was not followed: log what the victim was
doing before blaming the fragment. A stale entity reference is the same class of
error as a victim locked in a scripted job animation, and it produced the same
symptom, which is a valid call that plays nothing.

**With the layer in place**, on a fresh guard:

```
[S] t+1.0s anim=AnimationControlled
[S] t+5.0s anim=AnimationControlled
[S] t+6.0s anim=BlendRagdoll
[S] t+8.0s anim=BlendRagdoll
[S] t+9.0s anim=IdleToMove
```

The animation plays, the body is handed to the ragdoll to settle, and the actor
returns to its own locomotion. **The animated recovery and the ragdoll settle
coexist**, which was the open question and could not be answered by reading.
Whether the settle actually fixes the clipping on sloped ground is visual and
needs a ride.

## The settle layer cannot be ordered correctly inside one option

**User report** riding with the settle layer: "clipping is better but still
definitely there also the rag doll timing isn't quite correct so theres some
unnatural snapping back adn forth between the stages of animation and the
transition and rag doll lasts way too long."

The ordering is the fault, and it is structural. What is wanted is fall, then
settle onto the ground, then get up from a grounded pose. What the fragment
produces is fall, get up, then settle:

```
[S] t+1..5s anim=AnimationControlled   fall and get-up
[S] t+6..8s anim=BlendRagdoll          the settle, after both
[S] t+9s    anim=IdleToMove
```

`ExitTime` on the ragdoll `ProcLayer` does not move it. Vanilla uses 2 with two
anim slots, the second empty, which suggested the value counts clip slots
rather than seconds; setting it to 1 produced an identical trace. **The layer
takes over when the animation layer finishes, whatever the value**, so with a
get-up in that layer the settle can only ever come last. It then holds for
about three seconds, which is the "lasts way too long".

Reverted to the build without it, which is the one the user judged better.

### What a correct version would need

`actor:StandUp` exists, alongside `RagDollize`, `SetPhysicalizationProfile` and
`GetPhysicalizationProfile`, so leaving a ragdoll for an animation is possible.
A correct sequence is therefore available in principle: a fragment holding the
fall and the settle, as vanilla has, then `StandUp`, then the get-up as a
second action.

That is three stages joined by Lua rather than two joined by Mannequin, on a
mod whose last two attempts at Lua-timed animation chaining both failed on
timing. It should be attempted deliberately, with the physicalization profile
polled rather than a delay guessed at, or not at all.

**The trade as it stands**: no settle layer gives a clean fall and a good
recovery with clipping on sloped ground. The settle layer improves the clipping
and costs the recovery. The first is the better build today.

## Comparing every shared fall clip, and keeping the ones already in use

Eighteen fall clips exist for both character sets: the four
`relaxed_death_walk_*_01` the mod uses, and fourteen `relaxed_death_idle_*`
variants that had never been looked at. All were built as named options and
played one at a time on a standing NPC, in four rounds by direction, judged on
whether they read as a trot impact.

| Direction | Verdict |
| --- | --- |
| Front | `walk_front_01` and `idle_front_04` quickest; the rest slower |
| Back | `walk_back_01` and `idle_back_01` acceptable; `idle_back_02` and `_03` too dramatic |
| Left | `walk_left_01` best, `idle_left_01` possible; the rest exaggerated |
| Right | `walk_right_01` and `idle_right_01` good, `idle_right_03` decent |

**The clips already in use won every direction**, and the reason is in what
they are: `relaxed_death_walk_*` are falls from motion and `relaxed_death_idle_*`
are falls from standing, so the walking ones are quicker and less staged. A
trot victim is mid-stride, which is the case the walking clips were authored
for.

So the awkwardness reported at trot is **not fixable by choosing a different
clip**. Nothing quicker exists in the shared palette. What remains is the
transition, which is the ordering problem the settle layer could not solve.

The fourteen candidates are removed again rather than shipped. Twenty-six
options where twelve are used is dead weight in a database every redirected
human resolves through, and restoring them for another comparison is one line.

### A fall for a fatal collision

Worth keeping, from the user, on `relaxed_death_idle_right_02`:

> "3 would be good if it was played on a collision that was also a death hit
> because it reacts fast get to the ground and then has a dramatic ending but
> not good just for normal trot."

A collision that kills is a different event from one that knocks down, and the
clips that read as too theatrical for a knockdown are the ones authored for a
death. The mod already knows a victim's health at the moment of impact and
already sends the hit that may kill them, so choosing a death fall when the
impact is fatal is available and needs no new data. It belongs with the crime
and damage work rather than here.

## The settle layer fires after the victim has already stood up

Measured properly, with the get-up removed from the fragment so the option was
fall plus settle exactly as vanilla builds it, and the physicalization profile
sampled twice a second alongside the animation state:

```
[P] t+0.5s  anim=AnimationControlled  profile=alive
[P] t+2.5s  anim=AnimationControlled  profile=alive
[P] t+3.0s  anim=MotionIdle           profile=alive
[P] t+4.5s  anim=MotionIdle           profile=alive
[P] t+5.0s  anim=BlendRagdoll         profile=alive
[P] t+7.0s  anim=BlendRagdoll         profile=alive
[P] t+7.5s  anim=MotionIdle           profile=alive
```

The order is fall, **stand**, ragdoll, stand. The victim regains control two and
a half seconds before the settle arrives, so the body is upright when the
ragdoll takes it, drops it again, and hands it back. That is exactly the
"snapping back and forth between the stages" reported, and it is why the
clipping only partly improved: the settle is not settling the fall, it is
settling whatever pose the actor had wandered into afterwards.

**`ExitTime` on that layer does not control this.** Values of 1 and 2 produce
identical traces, and the gap between the animation ending and the ragdoll
starting is the same in both.

**And the profile never changes.** It reads `alive` through the entire
sequence, including while the animation state says `BlendRagdoll`. So the plan
for a correct three-stage version, polling `GetPhysicalizationProfile` for the
settle rather than guessing a delay, has nothing to poll. `StandUp`,
`RagDollize` and `SetPhysicalizationProfile` exist, but the profile is not
observably driven by this fragment.

**Both approaches to the clipping are therefore closed for now.** The clips
already in use are the best available, and the settle layer cannot be ordered
to run while the victim is down. The build is back to the fall and get-up
sequence, which is the version judged best in play, and the clipping on sloped
ground stands as a known cosmetic limitation of an animated knockdown.

Anything further would need the ragdoll driven from Lua rather than from the
fragment: `RagDollize` on the victim once the fall has played, then `StandUp`
before the get-up. That is a third attempt at Lua-timed animation chaining on a
mod where two have already failed, and it should only be taken up with a
measurement that says when the fall has actually finished, which the animation
state provides and a fixed delay does not.

## The clipping is a pose mismatch between the fall and the get-up

**User observation**, which relocates the problem: "they fall and it looks good
and then their body usually rotates in a frame and then the get up fires and
somewhere in that action is where most of the clipping seems to start."

A body that rotates in a single frame is not a terrain problem. It is the root
orientation being corrected between two clips that disagree about which way the
body is lying. The fall ends in whatever pose it ends in; the get-up is
authored from one specific lying pose, and if that is not the pose the body is
in, the actor is snapped into it. At ground level a snap of that size puts the
body through the road, which is where the clipping was reported to start.

**The pairing is the suspect.** The mod pairs by name, `relaxed_death_walk_front_01`
with `getup_ground_front`, on the assumption that "front" means the same thing
in both. It probably does not. In a fall clip the direction reads as where the
impact came from; in a get-up it reads as which side the body is lying on.
Those are opposites: someone struck from the front falls onto their back and
has to get up from their back.

This also explains why `GroundRotation` changed nothing. It aligns an actor to
the ground it stands on, and the fault is a root rotation between two clips
rather than a mismatch with the terrain.

## The get-up has to be paired to the pose, and the names do not tell you which

One fall, `relaxed_death_walk_front_01`, was built against all four get-ups so
that the only difference between the options was the recovery clip. Fired at an
NPC the user tagged with a walk stagger, at 3.7 m:

| Get-up | Result |
| --- | --- |
| `getup_ground_front` | rotates, clips |
| `getup_ground_back` | rotates, clips |
| `getup_ground_left` | **does not rotate, clips far less** |
| `getup_ground_right` | rotates most, clips most |

So the forward walking fall leaves the body on its **left** side, and the
correct recovery is `getup_ground_left`. The mod paired it with
`getup_ground_front` on the assumption that a shared direction word meant a
shared pose, and it does not: the fall's direction names where the impact came
from, the get-up's names which side the body is lying on, and the relation
between them is not identity and not opposition either.

**The clipping was a consequence, not the fault.** A get-up authored from the
wrong side rotates the root to reach its own start pose, and at ground level
that rotation drives the body through the road. The worst pairing clipped worst,
which is the ordering a rotation-driven fault predicts and a terrain-driven one
does not.

That also explains why `GroundRotation` changed nothing, and why the ragdoll
settle only partly helped: the settle was correcting some of a bad rotation
after the fact.

The remaining three pairings have to be found the same way, by playing each
fall against all four get-ups. There is no naming rule to infer them from.

## The four correct fall and get-up pairings

Each fall was played against all four get-ups, with the fall held constant so
the recovery clip was the only variable. The subject was teleported three
meters in front of the player once, allowed to settle, and then given the four
options in turn.

| Fall | Get-up | Result |
| --- | --- | --- |
| `relaxed_death_walk_front_01` | `getup_ground_left` | no rotation, least clipping |
| `relaxed_death_walk_back_01` | `getup_ground_front` | no rotation |
| `relaxed_death_walk_left_01` | `getup_ground_left` | slight roll, best available |
| `relaxed_death_walk_right_01` | `getup_ground_right` | acceptable |

**Three of the four the mod shipped were wrong**, and none of the correct pairs
follows from the names. Front pairs with left and back pairs with front, which
is neither identity nor opposition, so there was no rule to infer and the
mapping had to be measured.

The user's vocabulary made the readings usable: a yaw, described as a clock
hand moving from six to twelve, against a roll, described as going from back to
belly. A wrong pairing showed as one or the other, and the worst offenders were
180 degree yaws.

Two directions have no perfect partner. The left and right falls keep a slight
roll whichever get-up follows them, so some residual movement is inherent to
chaining these clips and is not a pairing error.

### On staging a test subject

Reading a single frame of rotation needs the subject in front of the player at
a known distance, and neither picking the nearest NPC nor asking the user to
tag one held up: targets walked off, fell through scenery, despawned, or turned
out to be a namesake two kilometers away, and several rounds were spent on
subjects nobody could see.

Teleporting one NPC three meters in front of the player, once, then letting it
settle before firing, is what worked. Repositioning between clips was tried
first and was worse: it moved the subject mid-animation and left it floating.

The harness now measures where the subject actually landed and refuses to fire
beyond eight meters, so a bad placement fails loudly instead of costing a round.

The subject also floated at times during these rounds. That is the staging and
not the mod: `SetWorldPos` places the entity at the player's own height, which
is not the ground height where it lands, and the body does not always settle
before the clip is fired. The user judged it not to have affected the
animations being compared, and no floating has been reported from an actual
collision, where the victim is standing where it already was. Worth remembering
before a future session reads it as a defect.

## The pairings hold for both character sets, and play still differs

A trot impact in play showed strong rotation on `hcm_knockdown_back`, the
pairing round two had judged clean. Every pairing until then had been read on
one woman, `rat_woman32`, so the character set was the first suspect: the two
databases are separate and their clips are separately authored.

The back fall was rebuilt against all four get-ups and staged on a man,
`rat_man97`:

| Get-up | Male | Female |
| --- | --- | --- |
| `getup_ground_front` | almost none | no rotation |
| `getup_ground_back` | strong | rotates |
| `getup_ground_left` | 180 degrees | rotates |
| `getup_ground_right` | not very much | rotates |

**The same pairing wins for both**, and the ordering of the losers matches too.
Gender is not the variable and the mapping needs no per-set split.

So a staged subject and a collision victim behave differently, and the
difference is not the character set. What a real impact adds is that the victim
is walking rather than standing idle, that their facing when struck is
arbitrary rather than whatever the teleport left, and that the mod chooses the
direction from the impact geometry rather than being told which to play.

Whether the rotation seen in play happens at the start of the fall, which would
point at the victim being turned to suit the clip's authored facing, or between
the fall and the get-up, which is the fault already fixed, is not yet
established and decides which of those to pursue.

## The rotation is in the body's own frame, not the world's

One clip, `relaxed_death_walk_back_01` into `getup_ground_front`, fired four
times on one man with only his facing changed: toward the player, away, and
turned ninety degrees each way.

> "slight 90, slight 90, slight 90, slight 90, they all seemed almost identical
> slightly glitchy almost 90 degree rotation"

**Identical every time.** The get-up resolves against the body rather than a
world direction, so a victim's orientation when struck does not change which
pairing is right. That rules out the explanation for why staged tests and play
disagreed, and it means a fixed mapping can be correct.

It also corrects a reading from the previous round. The same pairing was
recorded as "almost none" earlier and reads as a slight ninety here. The
earlier look was the less careful one, taken before the staging held the
subject still and before the user had settled on a vocabulary for these
rotations. Readings from the staged pass supersede the ones before it.

## The systematic pairing pass, across both character sets

The first pass was run on whatever NPC was to hand and produced a mapping that
did not survive scrutiny. This one staged the subject deliberately: teleported
to a fixed spot four meters in front of the player, placed at terrain height,
turned to face the player, and held for all four options of a round, so nothing
varied within a round but the get-up. Sixteen pairings, then the same sixteen
on the other character set.

| Fall | Get-up | Male | Female |
| --- | --- | --- | --- |
| front | back | very slight | slight |
| back | front | about 90 degrees | very slight |
| left | left | really good | slight |
| right | right | pretty dang good | slight |

**Front and back swap, left and right keep their own.** One mapping serves both
sets, which the earlier partial results had suggested was not the case.

The back fall is the weak entry. It is clean on a woman and holds about ninety
degrees on a man, and no other get-up does better for him, so that rotation is
inherent to chaining those two clips rather than a pairing that can be improved.

### What the first pass got wrong, and why

It had front pairing with left. Both sets point at back. The readings behind it
were taken before the subject was held still, before the user had settled on a
vocabulary separating a yaw from a roll, and in several cases on a subject that
walked away, fell through scenery or was a namesake two kilometers off.

Two hypotheses were raised and killed along the way, both worth the time:
facing, which changed nothing across four orientations of the same clip, and
per-set mappings, which the matched pass shows are unnecessary.

### Women are a different entity class

Scanning for a female subject reported none within two hundred meters while the
user could see four. **Women are class `NPC_Female`, not `NPC`.** Thirteen stood
within sixty meters of a scan that had reported zero.

The mod's own filter accepts a victim on `class == 'NPC'`, `class == 'Player'`,
or the presence of `Properties.esFaction`, so women reach it only through that
last fallback and never by class. That works, but it is the kind of accident
that explains a long history of female-specific faults in this project, and it
is worth naming the class explicitly.

## The human filter was not one, and a dog proved it

A knockdown was logged against `led_guardDog3` at trot, with `gender=0`:

```
ImpactCost led_guardDog3 tier=Trot strength=5 health=95.6250 pieces=0 weight=0.0
Reaction action=hcm_knockdown_back gender=0 ok=true err=nil
```

A guard dog was handed a human knockdown fragment. It resolves against a dog
skeleton, which has its own database, so nothing could have played.

The filter accepted anything carrying `Properties.esFaction`, which was written
to catch quest characters whose class is set to something unexpected. Dogs carry
it too. The same fallback was also the only route by which **women** passed,
since they are class `NPC_Female` and the filter named only `NPC` and `Player`.

So one line was wrong in both directions at once: it admitted animals, and it
admitted half the human population by accident rather than by name. Given the
run of female-specific faults in this project, reaching women through a fallback
meant for quest characters is worth calling out as a cause rather than a
curiosity.

The three human classes are now named: `NPC`, `NPC_Female`, `Player`. Confirmed
against a live scan, which reported `NPC` at 47, `NPC_Female` at 13, `Dog` at 5,
`Horse` at 1 and `Player` at 1 within sixty meters.

`ProtectMutt` is unaffected and still guards Henry's dog by name. It was never
the thing keeping other animals out, because nothing was.

## A teleported subject never settles on a slope

Staging by teleport works on flat ground and does not work on a gradient. A
subject placed with `SetWorldPos` at terrain elevation was polled every 300 ms
for a stable height and never reached one:

```
[T] rat_guard22 settled after 12000ms at z=91.59
```

Twelve seconds is the timeout, not a settle. The body hangs and never comes to
rest, so the floating the user reported on hillside rounds is the staging
rather than the animation, and every slope test run this way has been measuring
that artifact.

**Clipping on slopes can only be judged from natural riding.** The victim is
then standing where the world put them, with no teleport in the picture. The
telemetry names which direction fired, so a report of what was seen can still
be matched to a specific pairing without staging anything.

Teleport staging keeps its place for comparing clips on flat ground, where it
settles immediately and removes every other variable. It is the wrong
instrument for terrain.

## Clipping after the pairing fix tracks the slope, not the direction

Twelve trot impacts on a hillside, ridden naturally with no staging, each
observation matched against the reaction the telemetry recorded.

| Direction | Sex | Observed |
| --- | --- | --- |
| right | M | no clip |
| back | F | no clip |
| back | F | no clip |
| forward | M | no clip |
| left | M | floated, facing downhill |
| forward | M | clipped on the way down, fell toward uphill |
| back | M | clipped on standing up, slightly uphill |
| forward | M | no clip |
| back | M | floated, facing downhill |
| right | M | clipped on the way down |
| back | M | no clip |
| forward | M | slight clip |

**Seven of twelve were clean**, against a state the user had called
unacceptable before the pairings were corrected.

**The failures do not track direction.** `forward` appears four times, twice
clean and twice clipped; `back` five times, three clean and twice not. They
track the gradient instead: every failure is annotated either as facing
downhill, where the body floats, or falling toward uphill, where it clips. Both
female impacts were clean.

So the rotation fault is closed and what remains is terrain conformance: the
animation plays in a plane while the ground rises or falls under it.
`MCM_ZMOVE` was already 1 for this ride, so letting the animation drive the
actor's vertical position is not sufficient on its own. `Vertical` and `XyMove`
remain at 0 and are the next candidates, one rebuild each now that the movement
control parameters are settings.

## The movement control values are modes, and vanilla's are already right

`MovementControlMethod` carries `Horizontal` at 2 with `Vertical`, `XyMove` and
`ZMove` at 0, copied from the vanilla option this mod's fragments are modelled
on. Those three zeroes looked like a lever for the terrain problem, since a
body that cannot move vertically cannot follow a slope.

Measured, by sampling the victim's position five times a second through a
knockdown and reporting the largest single step:

| Vertical, ZMove | Largest step |
| --- | --- |
| 0, 0 | 0.21 to 0.30 m |
| 1, 1 | **0.00 m** |
| 2, 2 | **58.64 m in one frame** |

**They are modes, not switches.** Setting them to 1 pins the actor's origin
completely, which is the opposite of following terrain. Setting them to 2, to
match `Horizontal`, flings the body sixty meters in a single frame.

Vanilla's values are already the correct ones and the mod copied them
correctly. This is not a lever, and the slight improvement reported while
`Vertical` was 1 does not survive measurement: the origin moved less, not more.

The reported "slight teleporting" is also answered. With the values at 1 the
entity origin does not move at all during a knockdown, so nothing about the
actor was jumping; what was visible was the skeleton, and the 58 metre result
above is what an actual teleport measures like.

**Terrain conformance has no remaining knob on this fragment.** The animation
plays in a plane, the origin barely moves, and neither `GroundRotation` nor the
ragdoll settle nor the movement control method changes that. Seven of twelve
impacts clean on a hillside is where an animated knockdown lands.

## Why the mod's reactions pass through geometry and vanilla's do not

The question was put directly: these are vanilla's own clips, so why does a
guard staggering beside a wall stay out of it while a mod victim goes through?

**Because the playback path differs, and the mod cannot use vanilla's.** Lua's
only working entry point is `actor:StartInteractiveActionByName`, which
resolves against the `AnimationControlled` fragment. An interactive action is
root-motion driven: the animation moves the body, and root motion is not
navmesh or collision constrained. Vanilla's hit reactions play through
`HitDeath`, natively, where the actor keeps entity-driven movement. The
`hitReaction` and `combat:hit` messages reach a tree that cannot drive the
body, so that path is closed.

Five approaches were tried against it and measured.

| Approach | Outcome |
| --- | --- |
| `ColliderMode = Interactive` | correct, and kept, but not the cause |
| `Horizontal = 1` | travel drops to 0.00 m and the clipping stops, and the fall loses its direction |
| `Horizontal = 6`, `Vertical = 6` | does not play at all |
| No `MovementControlMethod` layer | dropped impacts, glitching, still clips |
| `GroundRotation`, ragdoll settle | no effect, and cannot be ordered |

Two of those are worth keeping as facts rather than attempts.

**`ColliderMode` was genuinely wrong and is now fixed.** The mod declared none
while 29 of the 32 vanilla options in `AnimationControlled` declare
`Interactive`. The builder's own comment explained the faulty reasoning: it
matched the fragment the clips come from rather than the fragment the options
live in. It does not stop the clipping, and a victim was still put through a
wall having traveled 1.59 m, but it was wrong before.

**`Horizontal = 6` is for synchronised pairs.** Vanilla uses it in
`HorseCombatHitSync` on fragments tagged `throw`, which is a rider throwing
someone from horseback and reads as an exact match for this case. It requires a
partner actor and plays nothing without one.

**Removing the movement layer is not the answer either**, despite 84 of
vanilla's 106 `HitDeath` options declaring none. Without it the animation still
plays and still travels, which disproves the builder's claim that an
interactive action needs one, but in play it produced dropped impacts and
glitching.

The remaining route is the one the roadmap already names: drive the ragdoll
from Lua once the fall has played, so the body is settled by physics rather
than by an animation. That is a third attempt at Lua-timed animation chaining
on a mod where two have failed, and it should be taken up deliberately or not
at all.

## The animation entry points, enumerated rather than assumed

The module header has said since 1.x that `StartInteractiveActionByName` is the
only call that drives an NPC's body. That claim was never tested against a full
enumeration of what the engine exposes, and it is wrong.

**The actor bind carries 98 functions and the human bind 41**, read off a live
NPC rather than from documentation. Several bear directly on this problem and
none had been tried.

### `actor:SetMovementControlledByAnimation(enable)`

A runtime, per-victim switch for whether the animation drives the actor's
movement. This is the same thing `MovementControlMethod` sets inside a fragment,
except it can be set per victim at the moment of impact rather than baked into
every option. Confirmed callable and accepted; the animation still plays and
still travels about a metre afterwards. Whether it prevents a victim passing
through geometry is untested and is the obvious next experiment, because it is
the only lever found that can be applied to one victim at a time.

### A family of native full-body actions

```
CanStealthKill / RequestStealthKill        SAT_KillEnabled = 3
CanStealthKnockout / RequestKnockOut       SAT_KnockoutEnabled = 4
CanHorsePullDown / RequestHorsePullDown    HPS_Enabled = 2
CanHuntAttack / RequestHuntAttack          HAS_Enabled = 2
RequestMercyKill, RequestGrabCorpse, RequestPutCorpse, RequestItemExchange
```

Each takes a victim entity id and is called on the attacker.
`Scripts/Entities/AI/Shared/BasicAIActions.lua` shows vanilla offering them as
interaction prompts, so **a native mounted takedown exists in the game**:
`@ui_hud_horse_pulldown`, wired to a behaviour tag `horsePullDown_horse`.

Every `Can` call returned 0, which is `Undefined` rather than `Disabled`, at
ranges from 4.3 m down to 0.7 m with the player mounted. The `Request` calls
were accepted and did nothing. So the family is gated on conditions not yet
identified, and the gate is not distance.

### The SmartObject animation route

`Libs/AI/final/so_animationOnSpot.xml` contains a tree named `playAnimation`,
registered in `so_behaviour_tag` under that name. Its parameters carry
`animationOnSpot_movementType`, whose values are `noMove`, `exactMove` and
`teleport`. That is an explicit vanilla mechanism for playing an animation on an
NPC with the movement behaviour chosen.

Installing it through a daycycle patch, the mechanism the auto-cure uses, was
tried and had no effect. Vanilla's own `cureApplyPatch` passes
`sourceId($__land)`, so the patch anchors to a source the behaviour reads, and a
patch without one appears to be ignored.

### What is genuinely dead

`human:PlayAnim(fragment, tag)` was retested, since the finding against it
predates this record. It was called with `HitDeath` and the FragTags of options
known to exist there, with `AnimationControlled`, and with an empty tag. Every
call returned cleanly and **none rendered**. The original conclusion stands.

### Unused strength

`enum_HitReactionStrength` runs to `Fatal = 7`. The mod sends `Tickle` at walk,
`MinorInjury` at trot and `MajorInjury` at gallop, and has never sent `Fatal`.
`hitType` is already sent as `Collision`, which `enum_HitReactionType` defines
as 2.

## The pull-down gate is three angle CVars, and none of them is what blocks it

The three CVars exist and are readable live, decoded from the registration
block in `references/WHGame_Decompiled.c` and confirmed against the running
game:

| CVar | Value | Registered description |
| --- | --- | --- |
| `wh_cs_HorsePullDownAngle` | 55 | max XY half-angle from the centre of the horse |
| `wh_cs_HorsePullDownZeroAngle` | 20 | the angle that half-angle is measured about |
| `wh_cs_HorsePullDownZAngle` | 15 | max Z angle |

So the admissible sector is 20 +/- 55 degrees off the horse's facing, which is
a wide arc down one side, with the victim within 15 degrees of level. There is
**no distance CVar for pull-down**, unlike `wh_cs_StealthActionDistance = 2`
for the stealth actions, so its reach comes from the `inr_pullDown`
interaction range rather than from a tunable.

A polling probe was installed over the console, sampling every nearby human
four times a second while riding through Rataje and reporting distance, XY
angle, Z angle, and all four `Can` calls.

```
[HCMProbe] rat_woman25 dist=5.34 ang=+7.6 zang=+3.7 pull=0 knock=0 hunt=0 kill=0
[HCMProbe] rat_woman44 dist=5.41 ang=+6.0 zang=-2.1 pull=0 knock=0 hunt=0 kill=0
[HCMProbe] rat_woman21 dist=5.15 ang=+8.1 zang=-4.0 pull=0 knock=0 hunt=0 kill=0
```

Every reading sits inside the declared angle limits on both axes and still
returns `HPS_Undefined`. The line is logged once per state change, and no
second line ever appeared for any subject, so the value stayed 0 all the way
through contact as the horse rode over them.

**The important part is the other three columns.** `CanStealthKnockout`,
`CanHuntAttack` and `CanStealthKill` return `Undefined` in exactly the same
conditions. Those are ordinary gameplay features that work when the player is
sneaking on foot, so a gate that stops all four at once is not a pull-down gate
at all. The likely reading is that these binds answer against the interactor's
current target, and report `Undefined` for a victim the interaction system has
not selected, which is what `BasicAIActions:GetActions` supplies when vanilla
calls them. If that holds, polling them from Lua can never return anything else
and the whole family is closed to this mod.

The discriminating test is the same probe with the player on foot and crouched
behind a subject, where `CanStealthKill` is known to be available in play. A
non-zero reading there means the gate is being mounted; a zero reading means
the bind needs interactor context and the family is dead.

## The SmartObject playAnimation route needs a smart object, not a patch

Reading `Libs/AI/final/so_animationOnSpot.xml` in full answers why installing
`playAnimation` as a daycycle patch did nothing, and it is not the missing
`sourceId`.

The tree's `PlayAnimation` node is declared
`SmartObject="__object.id" HelperID="helperId"`, and its `teleport` and
`exactMove` branches both target `__object.id`. `__object` is the smart object
the behaviour is running against, so the tree is meaningless without one. Its
parameters are worse: everything it plays comes from
`$t_animationOnSpot_params`, which is **forward-declared** rather than owned,
and is set by an enclosing tree through an `Expression` node. Vanilla's users
are wrappers like `q_dlc_revelation_trial_johanka`, each of which sets
`behaviorName`, `animation`, `animationTags` and `movementType` and then
includes `playAnimation`.

A `daycycle:change` message carries `add`, `once`, `handle`, `name`,
`priority`, `ignoreDuplicit` and `sourceId`. There is no field in it that can
set a tree variable, so there is no way to tell an installed `playAnimation`
which animation to play. Adding `sourceId` to the patch would not have helped.

What the file does establish is that the behaviour-tree `PlayAnimation` node
exists, is entity-driven rather than root-motion driven, and is the node
vanilla uses everywhere. `Libs/AI/final/animationUtils.xml` carries several
self-contained trees built on it that take no `__object` and no external
parameters, `cheer`, `lookingAround`, `prayStand` and `guard` among them. If
one of those can be installed on a victim by name through a daycycle patch and
is seen to play, then the daycycle route reaches native animation playback and
the remaining problem is only authoring a tree that plays this mod's fall
clips. That is the test worth running before the route is abandoned.

## Taking movement control off the animation stops victims entering geometry

The hypothesis was that a victim passes through a wall because an interactive
action is root-motion driven, and that
`actor:SetMovementControlledByAnimation(false)`, applied to the one victim at
the moment of impact, would put them back on entity-driven movement without
touching the fragment every option in the database shares.

Because it was not known which side of `StartInteractiveActionByName` the
engine would honour, the setting names when the call happens rather than
whether: `fragment` leaves it alone, `before` calls it ahead of the action,
`after` calls it a tick later on a timer, and `both` does both. The ride was
run at `both`, so a null result would have ruled out all three at once.

Rides against walls and building corners, with the wall always on the far side
of the victim so the reaction pushes them into it.

| Tier | Impacts | Result |
| --- | --- | --- |
| Walk | 4 to 5 | none entered the wall or any solid geometry |
| Trot | 3 | slight clipping, no penetration, victims returned to where they stood |

The user's report on the trot rides: "Very slight clipping, but the beggar
didn't straight up go through a wall like before and more or less returned to
his original position. the beggar by the church did not end up inside of the
church wall like he did before which is much better."

**This is the first thing tried on this problem that worked.** The list it
follows is long: `ColliderMode = Disabled`, `Horizontal = 1`, `Horizontal = 6`,
removing the movement control layer, `GroundRotation`, the ragdoll settle
layer, and correcting the fall and get-up pairings. The last of those helped
the terrain case and none of them touched geometry.

The church wall is worth naming as a landmark, because the same beggar at the
same wall was put inside it on earlier builds, and is the clearest before and
after this problem has produced.

Two things are still open. The result was taken at `both`, so it is not yet
known whether `before` alone, `after` alone, or only the pair is doing the
work; the answer decides whether the setting can collapse to a boolean. And
walk is clean while trot still shows slight clipping, which is consistent with
the residual travel measured on this fragment rather than with a second cause.

## The pull-down family is reachable from Lua, and the mounted probe had a hole

The reading in the entry above, that `Undefined` across all four `Can` calls
meant they answer only against the interactor's current target, is **wrong**.

On foot and crouched behind a guard at 0.83 m:

```
[HCMProbe] rat_guard26 mounted=false dist=0.83 ang=-9.3 zang=-2.1 pull=0 knock=4 hunt=0 kill=3
```

`knock=4` is `SAT_KnockoutEnabled` and `kill=3` is `SAT_KillEnabled`. Polling
the binds from Lua returns real answers with no interaction prompt on screen
and nothing selected, so the family is not closed and the earlier reading was
a false alarm. `CanHorsePullDown` reporting `Undefined` here is correct
behaviour, since the player is not on a horse.

The mounted samples that produced that reading have a defect. The probe logged
one line per subject per state, and the state never changed, so a subject first
seen at the edge of the six metre sphere with every call reading zero was never
logged again as the horse closed on it. **Nothing closer than 5.15 m was ever
recorded while mounted**, which is well outside any plausible reach for an
action performed by leaning out of the saddle. The declared angle limits were
satisfied in those samples, but distance was not tested at all.

The key now carries a half-metre distance bucket, so a subject logs afresh as
it closes. Re-running it mounted is what actually tests the gate.

## Loading a save locks every previously hit NPC out of reactions

Reported as "it seems none of the animations would fire or I couldn't seem to
impact them", on a ride that was supposed to be comparing `before` against
`both`. The setting was not the cause and the ride produced no comparison.

The telemetry showed the detection loop working perfectly and the cooldown gate
rejecting every impact before it was scored:

```
[HorseCollisionMod] Recovering rat_refugee_ales for=407408ms
[HorseCollisionMod] Recovering rat_refugee_vojcek for=258240ms
[HorseCollisionMod] Recovering rat_refugee_kunes for=251248ms
```

`KnockdownRecoveryMs` is 6000 and `HitCooldownMs` is 3000, so no deadline this
code writes can be more than six seconds ahead. Reading `RecentHits` out of the
running game gave 23 entries whose deadlines spread from 347 seconds behind the
clock to 239 seconds ahead of it.

There is one writer, `self.RecentHits[npcId] = now + recovery`, so the stamps
cannot be wrong. **The clock moved under them.**

`System.GetCurrTime` was measured against a real-time `Script.SetTimer`: it
advanced 5.000 s over a 5.000 s timer, so it does not drift and it is not the
accelerated world clock. It read 142,746,608 ms, about 39.6 hours, which is
accumulated time restored from the save rather than time since the level
loaded. **Loading an earlier save moves it backwards** by however far the save
was rewound, and every victim hit after that point in the abandoned timeline
keeps a deadline that is now hundreds of seconds in the future.

The failure is silent and looks exactly like the mod being broken: detection
runs, the footprint accepts the victim, and nothing happens. It also has a
second cause with the same signature, since entity ids are reused across a
load, so a stamp can lock out a victim that was never hit at all.

Two fixes, both shipped.

- The load screen listener clears `RecentHits`. That handles the ordinary case
  directly, and the listener already fires on every save load because it is
  where the mod starts its detection loop.
- The gate discards any deadline further ahead than the longest cooldown that
  can be written. That covers a discontinuity from anything else, and repairs
  itself on the next impact rather than needing the load to be observed.

Worth holding on to beyond this mod: **any timestamp kept in Lua across a save
load is stamped against a clock the save restores**, and Lua state in the
running game is not restored with it. The two go out of step at every load.

## The movement control call has to come after the action, not before it

Ridden at `before` against the same church wall and the same beggar that gave
the clean result at `both`. One walk impact and five trot impacts landed, all
of them logging `MovementControl when=before ok=true`, so the call was made and
accepted on every one.

The user's report: "Trot saw him first time sort of bounce off the wall of the
church back towards me, he doesn't return to original position is out in the
street, then trot impact throws him back towards the church and clips into the
wall... then the next couple impacts he clips through and is then seemingly
ejected out of the wall but he never returns to his position."

**That is the old behaviour.** Setting movement control before the action is
worth nothing, which is consistent with `StartInteractiveActionByName` applying
the fragment's own `MovementControlMethod` layer as it starts and overwriting
anything set ahead of it. The call has to land on the running action.

Since `both` worked and `before` did not, the deferred call is carrying the
result on its own, and `after` alone should reproduce it. Confirming that is
what collapses the setting from four modes to a switch.

One detail from this ride is not about movement control and should not be read
as one. The beggar resumed his begging animation wherever he came to rest
rather than returning to where he had been standing. At `both` he "more or less
returned to his original position". Whether that tracks the setting or is the
smart object slot reclaiming him from wherever he ends up needs the `after`
ride to separate.

The cooldown fix from the previous entry is confirmed in the same log. The
deadlines read `for=2896ms` and `for=5920ms` against `HitCooldownMs` of 3000
and `KnockdownRecoveryMs` of 6000, where the same lines before the fix ran to
407,408 ms.

## The deferred call alone carries it, and the setting becomes a switch

Ridden at `after` from a freshly loaded save, against the same church wall and
the same beggar as the two rides before it. Four walk impacts and three trot
impacts, every one logging `MovementControl when=after ok=true`.

| Setting | Walk | Trot |
| --- | --- | --- |
| `fragment` | into the wall | through the wall, ends up inside it |
| `before` | into the wall | clips in, ejected, ends up in the street |
| `after` | clean, one head partly in the wall | never clipped, no bounce |
| `both` | clean | slight clipping, no penetration |

`after` alone reproduces `both`, so the deferred call is doing all of the work
and the call made ahead of the action contributes nothing. The four modes
collapse to one boolean, `ReleaseAnimationMovement`, defaulting on.

**Why the order matters.** An interactive action applies its fragment's own
`MovementControlMethod` layer as it starts, which overwrites a value set before
the call and leaves one set after it standing. This is the same reason the
ragdoll impulse is deferred by a tick, and the deferral is 50 ms in both places.

The position question from the previous entry is answered and was not the
setting. At `after` the victim "more or less returned to original position",
matching `both`, so the beggar staying in the street at `before` was a
consequence of being ejected from the wall rather than a separate behaviour.
Facing is not preserved: one victim came back to the right place pointing a
different way. That is cosmetic and is not tracked further.

This closes the geometry problem that has been open since the walk stagger
shipped. Everything tried before it, `ColliderMode`, three `MovementControlMethod`
variations, removing the movement layer, `GroundRotation`, and the ragdoll
settle layer, changed nothing about geometry. The terrain problem on sloped
ground is separate and remains open.

## The same call fixes the sloped ground, which was thought to need a ragdoll

The entry above closed the geometry problem and left terrain open, on the
reasoning that a body buried in a hillside and a body pushed through a wall
were different faults. They were not. Free play on the shipped build, with no
further changes:

> "After testing I'm not noticing any floating/clipping through the ground on
> trot collision animations. Maybe every so slightly, but way better than
> before and it looks close to something that would be found in vanilla so I
> think that issue can be set aside. It's not 100% perfect, but it's basically
> there."

**The hypothesis this overturns was the project's own.** The prior conclusion
was that terrain conformance had no remaining knob on this fragment, that seven
of twelve clean impacts on a hillside was where an animated knockdown lands,
and that revisiting it needed the ragdoll driven from Lua after the fall had
played. That last was named as a third attempt at Lua-timed animation chaining
on a mod where two had already failed, and it is now not needed.

Why one call covers both: a root-motion animation moves the body along a path
authored in a plane, and nothing reconciles that path with the world. A wall is
the horizontal case and a slope is the vertical one. Returning the actor to
entity-driven movement puts the engine back in charge of where the body
actually goes, and the engine already resolves both.

The measurement that read as ruling this out is worth re-reading rather than
deleting. `Vertical` and `ZMove` at 1 pinned the origin completely and at 2
flung the body 58 meters, which was correctly read as proof that they are modes
rather than switches, and correctly concluded that vanilla's values were right.
The error was generalising from the fragment layer to the runtime call. They
set the same property and are not the same lever: one is baked into every
option in the database, the other is applied to one victim on a running action,
and only the second can be timed to land after the action has claimed control.

Both halves of the problem the animated knockdown shipped with are now closed
by one line of Lua, so no ragdoll chaining is needed and the trot knockdown
stays fully animated.

## The bind enumeration was mostly lost, and is now written down

The entry "The animation entry points, enumerated rather than assumed" claimed
an enumeration of 98 actor functions and then named about ten of them. The
list itself was never recorded, so everything not acted on that night was gone.

Re-deriving it live failed and is worth recording as a fact about the
environment: **the script binds cannot be enumerated with `pairs`.** `actor`,
`human`, `soul` and `inventory` are userdata dispatching through a metatable,
and iterating them yields nothing. `ItemManager` and `XGenAIModule` are plain
tables and enumerate normally, at 9 and 28 functions.

The real source is the script-bind registration in
`references/kcd-documentation`, one file per bind, with the class, method and
argument types in the filename. Extracted in full to `docs/ENGINE_BINDS.md`:
419 functions across the ten classes this mod can reach, 113 of them on
`Actor`, against the ten previously written down.

### The leads that were sitting in it

Each of these bears on an open roadmap item, and none had been noticed.

- **`actor:GetCurrentAnimationState()`.** The mod states, in the comment on
  the cooldown gate, that nothing in the engine reports whether an actor is on
  the ground, and times the recovery blind because of it. This is the call
  that would answer it, and it would replace `KnockdownRecoveryMs` with an
  observation.
- **`actor:StandUp()`.** Chaining a get-up was attempted twice from Lua
  timers and abandoned both times.
- **`actor:CameraShake(number, number, number, vector)`.** There is no
  rider-side feedback on impact at all. Riding into someone at a gallop
  currently registers only through what the victim does.
- **`actor:SetSpeedMultiplier(number)`** and
  **`actor:SetMovementRestriction(boolean, boolean)`.** Per-victim movement
  effects, which is the shape the momentum work in Phase 2 wants.
- **`actor:QueueAnimationState(string)`, `ChangeAnimGraph(string, number)`,
  `SetAnimationInput(string, string)`, `SetVariationInput(string, string)`.**
  A second animation path, through the animation graph rather than through
  Mannequin. The module header's claim that the interactive action is the only
  way to play a clip has never been tested against any of these.
- **`actor:RagDollize()`** and **`actor:GoLimp()`**, both distinct from the
  `actor:Fall` the mod uses, and
  **`actor:SetPhysicalizationProfile(string)`**, which is the switch between
  alive and ragdoll physics rather than a request to fall.
- **`actor:AddBlood(string, number)`.** Visible impact feedback on the victim.
- **`actor:CanKnockOut(id)` and `RequestKnockOut(id)`**, which are separate
  binds from `CanStealthKnockout` and `RequestStealthKill` and were not in the
  family previously listed.

### ItemManager carries no weight

Asked directly, because the shipped item table is 50 KB and would be worth
dropping. `ItemManager` exposes `AddOnEquipBuff`, `CreateItem`, `GetItem`,
`GetItemName`, `GetItemOwner`, `GetItemUIName`, `IsItemOversized`,
`RemoveItem` and `SetItemOwner`, and nothing else. An item read back through
`GetItem` carries `health`, `amount`, `id`, `class` and `entity`, and no
weight.

So **there is no live weight lookup**, and the join through the shipped table
is not a shortcut but the only route. What the roadmap describes as unbuilt,
reading an entity's carried items generically, is already implemented in
`ArmorOf`: `inventory:GetInventoryTable()` for the WUIDs and
`ItemManager.GetItem(wuid)` for the class. Only the class-to-weight join needs
the table.

## Regeneration between impacts, not the per-impact cost, sets the real limit

The halved values were ridden and reported as: about 20 trot impacts before
being thrown, gallop about right, trot in combat repeatable "seemingly as much
as I want", and combat gallop acceptable but ideally capped at one or two.

Measured across 30 logged impacts:

| Tier | Mode | Mean drain | Impacts from a full 210 pool |
| --- | --- | --- | --- |
| Gallop | calm | 33.7 | 6.2 |
| Gallop | combat | 67.1 | 3.1 |
| Trot | combat | 49.4 | 4.3 |

The first suspicion, that the repeatable combat staggers were walk-tier impacts
costing nothing, is wrong. Every walk impact in the log carries
`combatScale=1.0`, so `SuppressStaggerInCombat` is working and none of them
happened during a fight. They were real trot impacts.

**The pool recovers between impacts, and that is the term that was missing.**
Consecutive impacts inside a single fight show the horse regaining 14 to 44
stamina in the gap, against a trot impact on a villager costing 12.4. The cost
of an impact on an ordinary target is smaller than what the horse gets back
before the next one, so that case cannot deplete the pool at all and the
reported figure of 20 is a floor rather than a ceiling.

This is why tuning the base drains alone was never going to land. Against
armored targets the drain does outrun regeneration and the pool falls, which is
why gallop read correctly while trot through a village read as free.

The correction raises the combat multiplier from 1.5 to 2.2 and the trot base
from 15 to 18, leaving gallop at 22 because calm gallop was reported as
correct. That puts a combat gallop into a mail guard at 2.0 impacts and a
combat trot at 2.4, which is the cap that was asked for, while a calm trot
through villagers stays cheap at 14.1 and a calm gallop is unchanged at 4.3
against a guard.


## The rebuild call works; a fixed delay is the wrong trigger for it

Tested at 4.0.1-dev.1, the first build to rebuild a victim after a reaction.
The rebuild is `entity:Hide(1)` followed immediately by `entity:Hide(0)`, fired
on a timer measured from the start of the reaction: 5000 ms for a knockdown,
2000 ms for a stagger.

**User report**: "first npc was woman walking and she took about a second to
start moving again after getting up, there was a very slight blinking, second
was woman walking but she is frozen and I'm currently still in game standing
next to her."

### Four reactions, and the distance each victim covered

`travel` is measured from the impact position and sampled at fixed offsets.

| Victim | Action | Gender | t+3s | t+6s | t+10s |
| --- | --- | --- | --- | --- | --- |
| villageGuard | hcm_knockdown_back | male | 0.08 | 6.57 | 10.98 |
| rat_bailiff_wife | hcm_knockdown_right | female | 0.07 | 0.07 | 2.30 |
| rat_swordsmiths_wife | hcm_knockdown_forward | female | 0.06 | 0.06 | 0.06 |
| rat_swordsmiths_wife | hcm_knockdown_forward | female | 0.06 | 0.01 | 0.06 |

Every one of these logged `VictimRebuild ok=true err=nil`. The call being
accepted says nothing about whether the victim resumed.

### The call is not what failed

The frozen victim was probed live, several minutes after her second impact and
while still stationary. A `Hide(1)` and `Hide(0)` pair fired by hand at that
moment moved her **4.17 m in the following five seconds**.

So the same call, on the same victim, in the same session, works when it
arrives later and does nothing when it arrives at 5000 ms. What separates the
two is only when it happened relative to the reaction.

### What that means for the trigger

A delay measured from the start of the reaction has to guess the length of the
fall and the get-up. That length is not constant: it varies by action, and a
victim hit again while still recovering starts a reaction from a state the
first one left behind. The victim who never recovered was hit twice, and was
already frozen from the first impact when the second landed.

Where the delay lands too early the rebuild happens while the animation still
owns the actor, and the animation takes the body back afterwards, which leaves
exactly the freeze the rebuild exists to prevent. Where it lands too late the
victim stands idle for the difference, which is the second-long pause reported
on the victim who did recover.

The recovering victims bracket the problem rather than contradicting it: the
male knockdown had covered 6.57 m by t+6s, so 5000 ms was past the end of his
animation, while the female knockdown had covered 0.07 m at the same offset and
only reached 2.30 m by t+10s.

### The blink is real

`Hide(1)` and `Hide(0)` issued in the same call, with no timer between them,
was recorded during earlier work as invisible on screen. Observation at this
build contradicts that: the recovering victim showed "a very slight blinking".
The teardown is not free, and hiding the visible NPC is being drawn at least
once.

### Open question

Whether the reaction's actual end can be read from the engine, so the rebuild
is triggered by the victim being up rather than by a clock. The alternative is
a rebuild that verifies its own result and repeats, which treats the symptom.


## `AnimationControlled` is the reaction, and reading it replaces the delay

Instrumented ride at 4.0.1-dev.2, sampling `actor:GetCurrentAnimationState()`
and distance covered every 250 ms for 11 seconds after each impact. The rebuild
delays were held at 12000 ms so nothing interfered with the measurement. Six
runs produced samples: five knockdowns and one stagger.

### The states an actor passes through

262 samples returned six values:

| State | Samples |
| --- | --- |
| AnimationControlled | 115 |
| MotionIdle | 89 |
| MotionMovement | 39 |
| IdleToMove | 8 |
| MoveToIdle | 6 |
| MotionIdleVARdefault | 5 |

`AnimationControlled` is present from the first sample at t+256 ms and holds
continuously until the reaction ends. Everything else is ordinary locomotion.
Nothing else in the set distinguishes a victim mid-reaction.

### How long it is held

| Action | Held until | Moved by then | Recovered on their own |
| --- | --- | --- | --- |
| hcm_knockdown_back | 6992 ms | 0.06 m | no |
| hcm_knockdown_forward | 5040 ms | 0.09 m | no |
| hcm_knockdown_right | 6032 ms | 0.00 m | yes |
| hcm_knockdown_back | 4288 ms | 0.07 m | no |
| hcm_knockdown_back | 4272 ms | 0.08 m | no |
| hcm_stagger_right | 2256 ms | 0.06 m | yes |

Knockdowns spread from 4272 to 6992 ms, a range of 2.7 seconds, and the same
action varies within it: `hcm_knockdown_back` was held for 6992 ms on one victim
and 4272 ms on another. The stagger released at 2256 ms.

### Why any fixed delay was going to fail

The 5000 ms the previous build used falls inside the knockdown range. Victims
whose animation ended before it were rebuilt correctly and stood for the
remainder; victims whose animation was still running were rebuilt mid-clip, and
the animation took the body back afterwards, which produced exactly the freeze
the rebuild exists to prevent. Both outcomes came from one number, which is why
the same build looked like it worked on some victims and not others.

The stagger delay of 2000 ms was under 2256 ms, so every stagger was being
rebuilt mid-clip.

### The freeze does not resolve itself

Four of the six victims covered less than a tenth of a meter for the full
eleven seconds, having left `AnimationControlled` and settled into `MotionIdle`
seconds earlier. The animation ending is not the victim resuming. Something has
to reattach them, which is what the rebuild is for.

### What replaced the delay

`WhenReactionEnds` polls the animation state every 250 ms and fires when the
value leaves `AnimationControlled`, bounded at 12000 ms. The state must have
been observed at least once before leaving it counts, so a poll landing in the
gap before the action takes hold cannot report a reaction that has not started
as already finished.

Both per-tier delay constants are removed. The distinction they encoded was an
attempt to approximate clip length, and an observation covers stagger and
knockdown without needing to know which is playing.

Telemetry is now one line per reaction, `VictimRebuild action= on= waited=`,
where `on` is `state`, `ceiling` or `unreadable` and `waited` is how long the
reaction actually ran. Those figures are the evidence for whether the trigger
is firing where this predicts.


## The observed trigger holds, and the freeze is fixed

Tested at 4.0.1-dev.3, five trot knockdowns and two walk staggers, men and
women.

**User report**: "no freezes, pause is very short but still present. The blink
seemed to be noticable a few time maybe."

### Every reaction fired on the observation

| Action | Waited |
| --- | --- |
| hcm_knockdown_back | 7248 ms |
| hcm_knockdown_forward | 5248 ms |
| hcm_knockdown_left | 6752 ms |
| hcm_knockdown_back | 4528 ms |
| hcm_knockdown_left | 6768 ms |
| hcm_stagger_back | 2496 ms |
| hcm_stagger_left | 2000 ms |

All seven reported `on=state`. The ceiling was never reached, so the animation
state was readable and changed on every victim, and no rebuild was fired blind.

The figures land where the sampled ride predicted: knockdowns between 4.5 and
7.2 seconds, staggers at 2.0 and 2.5. `hcm_knockdown_back` again varies by most
of three seconds between two victims, at 7248 and 4528 ms, which is the
variation no fixed delay could have covered.

Against the previous build this is the difference between four of six victims
frozen and none of seven.

### The residual pause is the polling interval

Each `waited` figure sits about 250 ms above the animation's measured end: the
sampled `hcm_knockdown_back` released `AnimationControlled` at 6992 ms and the
trigger reported 7248 ms. That gap is one poll, which is what the player sees as
the short remaining pause.

`ReactionPollMs` drops from 250 to 100, which bounds the pause at a tenth of a
second. The detection loop already runs at that rate, so the cost is known.

### The blink is unresolved and belongs to its own branch

Hiding and showing the entity in a single call was recorded during earlier work
as invisible on screen. Two rides have now contradicted that, first as "a very
slight blinking" and now as noticeable on some victims.

It is a separate defect from the freeze, with a separate cause, and the freeze
fix is complete without it. What has not been tried is firing something other
than `Hide` at this moment. The eleven calls previously found inert were all
tested on victims that had been stuck for minutes; none was tried at the
transition out of `AnimationControlled`, which is a different state and was not
observable when those tests were run.

### One reaction reached the ceiling

A `hcm_stagger_right` reported `on=unreadable waited=12160ms`, meaning
`AnimationControlled` was never observed at all across the full twelve seconds.
The fallback did its job and the rebuild fired anyway.

An action that is accepted and then aborts within a frame produces exactly this,
which is the known behavior of a reaction whose name resolves to no fragment.
The cost is a victim waiting out the ceiling before being rebuilt, and the
telemetry names the case whenever it happens, so its frequency is measurable
rather than assumed.

## The pause closes at a hundred millisecond poll

Tested at 4.0.1-dev.4, four trot knockdowns and two walk staggers.

**User report**: "pause is gone, no freezes."

Halving the polling interval from 250 ms to 100 ms removed the remaining pause
entirely, which confirms the diagnosis that the pause was the interval rather
than anything about the rebuild. No victim froze, so the observed trigger holds
at the faster rate.

This is the freeze fix complete, and the first fix reimplemented on the clean
4.0.0 base. What remains unresolved is the blink, which is its own defect and
its own branch.


## Entity links are not how a smart object holds an NPC

Probed at 4.0.2-dev.1, reading every entity link on a victim before the
reaction, after it, and after the rebuild. Eight reactions across an innkeeper,
a merchant, a beggar and two guards.

### The link list never changed

| Victim | Links, identical at all three samples |
| --- | --- |
| rat_innkeeper1 | rat_home14, rat_pub2, rat_home13 |
| rat_merchant_shop3 | rat_home7, sa_rat_shop3 |
| rat_refugee_vojcek | refugeeCamp, rat_watercarrier_jobs |
| rat_guard8 | sa_rat_garrison, rat_home8 |
| rat_guard4 | sa_rat_garrison, rat_home12 |

`usedSO` resolved to nothing on every victim at every sample, including on
victims observed returning to a smart object animation afterwards.

So the `usedSO` link the behavior trees write is not in the entity link system
that `entity:GetLink` and `entity:GetLinkTarget` read, and nothing in that
system records a smart object being used or lost. The hypothesis that a stale
link is what strands a victim is wrong.

What entity links do hold is persistent assignment: a home, a workplace, a
garrison, a job list. `sa_rat_shop3` and `sa_rat_garrison` are smart activities,
so the link names the role an NPC is assigned to rather than the object they are
touching at any moment.

### The victims do re-acquire their smart object

**User report**: the innkeeper "does return to his lean animation which because
of his distance to the wall showed some slight clipping, like hes attaching from
the wrong angle". The beggar "also doesn't end up facing the direction he
started in but also returns to begging animation".

This is the finding that matters, and it is the opposite of what a stale link
would predict. Nothing is stranded. The smart object takes the victim back, and
takes them back at whatever angle they happen to be standing at, which is why
the innkeeper leans into the wall instead of against it.

### The merchant shows what a correct re-acquisition looks like

**User report**: the merchant "seemed to just stay in place on the first impact,
but the second he got up and went back around to the front of his booth which I
think is what he does normally on a loop when he's attached to his booth".

Both outcomes came from the same code, so the difference is where he was left
standing. A smart object tree reaches its loop through `Move` to the object and
then `ExactMove directionType="AlignWithEntity"`, and the alignment is part of
the approach. A victim left inside the object's tolerance resumes the loop
without approaching, so the alignment never runs and their angle is whatever the
fall gave them. A victim left outside it walks back, and the approach aligns
them correctly on the way in.

That accounts for every observation in one mechanism: the innkeeper and the
beggar were near enough to skip the approach, the merchant on his second impact
was not.

### What this says about the facing work

The rotation chased across three earlier mechanisms was a symptom. The angle was
never the victim's to keep; at a smart object it belongs to the object and is
written by the approach. Correcting it from Lua was fighting for control of a
value the engine sets as a side effect of an NPC walking to their work.

The untested lever is making the victim re-approach rather than resume in place.
`daycycle:restartRequest` is what vanilla sends for this, and
`sb_switch_hitreactions.xml` sends it after the game's own hit reactions, which
is the closest vanilla precedent to this mod.


## The replan fixes the merchant and cannot reach the innkeeper

Tested at 4.1.0-dev.1, two impacts each on the Rattay innkeeper, a beggar and a
merchant. `daycycle:restartRequest` reported `ok=true` on all six.

**User report**: the innkeeper "always returns to his lean in the direction he
is facing after his getting up animation which was 180 degrees on the first
impact and 90 degrees to his right on the second. same idea with the beggar but
it was first impact 45 degrees to his left, second impact ended with him 90
degrees to his left from original direction, merchant seemed to get right up and
walk back into his position, second impact he got up again, and then shortly
after walked back behind his booth to his other normal position."

### The prediction held exactly

The merchant is fixed, on both impacts, including the first. Previously only his
second impact produced a correct return, and the difference then was that the
second had thrown him clear of the booth. With the replan he approaches every
time, and the approach is what puts him straight.

The innkeeper and the beggar are unchanged. Both re-attach to their object at
whatever angle the get-up left them at: 180 and 90 degrees for the innkeeper, 45
and 90 for the beggar. Neither walks anywhere, so neither is aligned.

This is the mechanism working as understood rather than failing. Alignment
happens during the approach, and a victim already inside their object's
tolerance has no approach to make. Restarting the daycycle asks them to re-plan;
re-planning correctly concludes that they are already where they should be.

So the fix is real and it is partial by construction. It covers every victim who
is displaced and no victim who is not, and displacement is a property of the
impact rather than of the victim.

### The angle is inherited from the get-up, not chosen by the object

Worth stating plainly, because it narrows what is left: the object does not pick
a wrong angle. It accepts the one the victim is holding. Every reported figure
is the rotation the fall and get-up chain imparted, which earlier measurement
established belongs to the clip rather than to the victim, the same action
producing the same drift on different people in different places.

### The question that is now open

Raised by the user: whether the rotation is caused by the mechanism that keeps a
reacting victim out of walls.

`ReleaseAnimationMovement` calls `actor:SetMovementControlledByAnimation(false)`
one tick after the action starts. That takes the body off the animation's root
motion and puts it on entity-driven movement, which is the state vanilla's own
hit reactions play in and the reason they respect geometry that an interactive
action passes through. Reverting it was previously observed to bring wall
clipping back, so its effect on translation is established.

Its effect on rotation is not. If suppressing the animation's translation leaves
its rotation still being written, or causes the entity to be turned to follow the
clip it can no longer travel along, then the drift is a cost of the anti-clipping
fix rather than a property of the animation, and the two are the same problem.

That is a single-variable experiment: measure the drift with the setting on and
again with it off. Nothing needs correcting to find out, only recording.


## The rotation is in the animation data, and one pairing already has none

Two rides at 4.1.0-dev.2, identical but for `ReleaseAnimationMovement`, which is
the setting that takes a reacting victim off the animation's root motion so they
stop passing through walls. Sixteen reactions, heading read before the reaction
and again when it ended, nothing written.

### The setting makes no difference to rotation

| Action | Anti-clipping on | Anti-clipping off |
| --- | --- | --- |
| hcm_knockdown_forward | +53, +52 | +53, +53, +53, +53 |
| hcm_knockdown_left | -176, 0, 0 | -176, -176 |
| hcm_knockdown_back | +90 | +91 |
| hcm_knockdown_right | 0 | 0, 0 |

The figures are the same to the degree in both configurations. Taking the body
off root motion changes where a victim ends up, which is why it fixed the wall
clipping, and does not change which way they face. The two problems are
unrelated, and the anti-clipping fix is not paying for itself in rotation.

### Each action has one rotation, and it is a constant

Across sixteen reactions on different people in different places, hit from
different approaches, in two configurations:

| Action | Rotation |
| --- | --- |
| forward | +53 degrees |
| left | -176 degrees |
| back | +90 degrees |
| right | 0 degrees |

`hcm_knockdown_right` imparts no rotation at all, on three reactions across both
rides. That is the finding that matters. The rotation is not something reactions
inevitably do; it is something three of the four fall and get-up pairings do and
the fourth does not.

This is the sixteen-pairing staged pass being visible from the outside. The back
fall on a male was recorded there as holding about ninety degrees with no better
get-up available, and the measurement here returns +90 and +91 for exactly that
action.

### Two anomalous zeros

`hcm_knockdown_left` returned 0 twice in the first ride against -176 everywhere
else. Those two ended at 6784 and 6752 ms where every other left ended at 7008
to 7040, so they finished about 250 ms early. An animation that stopped before
its rotating section would produce both the short duration and the absent
rotation. Not investigated, and recorded only so a later ride showing the same
pair of figures is recognized rather than treated as new.

### What this closes and what it opens

Closed: correcting the heading from Lua, which three mechanisms attempted; the
theory that the drift is caused by the anti-clipping fix; and the theory that a
stale smart object link strands a victim.

Open, and now well specified: three of the four knockdown pairings carry a fixed
rotation and one carries none. The work is in the animation data, in the choice
of get-up paired with each fall, and `hcm_knockdown_right` is a working example
sitting in the same database.


## Handing recovery to the game works, and lands the ragdoll too late

Tested at 4.2.0-dev.1 after a full game restart, which the new fall-only
fragments require. Five trot impacts.

**User report**: "There is a gap between when the animation ends and the the
visible rag doll starts, but everyone gets up much more naturally once it takes
over and looks much better. Also beggars and innkeepers do not return to begging
and lean animations after impact and they just stand in place after, but the
merchants seem to not have a problem getting back into their pacing schedules
around their attached booths."

### The recovery itself is better

Dropping the get-up clip removes the rotation it imparted, and the game's own
recovery reads as more natural than the animated one it replaces. That is the
approach confirmed: the fall is worth keeping and the get-up was not.

### Firing at the end of the clip is the wrong moment

The ragdoll is currently triggered when the animation state leaves
`AnimationControlled`, which is the end of the whole fall clip. A fall clip does
not end when the victim reaches the ground; it ends after they have reached it
and settled into the clip's final pose, and the difference is the visible gap.

The correct moment is ground contact, which is earlier and differs per clip.
Handing a body to physics while it is already prone is invisible; handing it
over after a pause is not.

### A regression on activity NPCs that do not walk

Beggars and innkeepers no longer return to their begging and leaning animations
at all, where under the animated get-up they returned but faced the wrong way.
Merchants are unaffected and resume their rounds.

The split is the same one found earlier: a merchant walks back to his booth and
a beggar does not walk anywhere. The difference now is that the ones who do not
walk fail to re-enter their animation rather than entering it turned. Something
about the state a ragdoll recovery leaves an actor in prevents the smart object
from taking them back, where the animated get-up did not.

This is a cost of the change and it has to be answered before the tier ships as
a default.

### The proposal being taken up

From the user: "the rag doll should fire the moment the NPC finally hits the
ground which would be different for every animation since they have different
lengths and times till NPC hits the ground."

Rather than four hand-tuned constants, ground contact is observable the same way
the end of a reaction turned out to be. The victim's height is sampled while the
fall plays and the ragdoll is handed the body once that height stops falling,
which adapts to the clip, the character set and the ground underneath without
any figure being fixed in advance. A per-action ceiling remains as a fallback for
the case where the height cannot be read at all, and every sample is logged so
that case is recognized rather than guessed at.

## Every direction shared one ragdoll timing, and the table looked full

Tested at 4.2.0-dev.2, eight to ten trot impacts across both character sets and
all four directions.

**User report**: "sometimes it fires too early and it looks like a lifeless
puppet, sometimes it fires right now and looks pretty natural and others its
late and seem like they kick and go limp after already falling."

### The cause is a table lookup that missed

`GetImpactDir` returns the engine's vocabulary, `so_left`. The option name is
built by stripping that prefix, but the per-direction timing table was indexed
with the unstripped value, so every lookup missed and fell through to the
forward default. The log names it plainly: `hcm_fall_left at=1300ms`, where the
table holds 1200 for left.

So all four directions and both character sets ran on one figure, which is
exactly the report: with a single timing against clips that run from 1.75 to 4.2
seconds, some land early, some land right and some land late.

The user's conclusion that every gender and direction needs its own timing
stands. What was not true is that four timings had been tried; one had.

Worth generalizing: a Lua table lookup that misses returns nil silently, and a
fallback written for robustness then hides it. The value used is now logged next
to the action, which is the only reason this was visible at all.

## The rebuild fires, and does not restore an activity NPC

Thirty recoveries reported `VictimRebuild on=resolved`, so the ragdoll was seen
to resolve and the entity rebuild ran on every one. Beggars and innkeepers still
stood inert afterwards while merchants resumed normally.

**User report**: "when I left the area and came back they were back in their
animations. same behavior confirmed for the innkeeper."

So the teardown the engine performs when a player leaves and returns does
restore these NPCs, and `entity:Hide(1)` followed immediately by `entity:Hide(0)`
does not, despite being the call that was found to fix the original freeze.

The difference between the two is time. The engine's own teardown and rebuild
are separated by however long the player was away; the mod's are separated by
nothing at all.

The first thing being tried is ordering rather than duration: the re-plan is now
sent 600 ms after the rebuild instead of in the same frame, on the reasoning
that a brain being torn down and remade is the wrong one to ask to choose an
activity. If that is not enough, a gap between the two `Hide` calls is the next
variable, and it costs the visible blink that the zero-gap version was chosen to
avoid.

## The gallop tier works because it does nothing afterwards

Tested at 4.2.0-dev.3, roughly a dozen trot impacts plus one gallop.

**User report**, and the observation the branch turns on: "I hit one with a
gallop, knocked him way out of position and when he got up he immediately
starting walking towards another (different than original) begging spot in the
market and put himself in the beggin annimation. So, how is there a difference
between how the gallop transitions the NPCs and how we are doing it?"

Also reported: beggars keep barking while stuck standing, though spaced further
apart than normal, so the brain is running rather than halted; and a beggar who
was reset by the player leaving and returning came back into the animation but
at neither the original position nor the original facing.

### Three things the trot tier does that the gallop tier does not

Read from the log, per impact:

| Step | Gallop | Trot fall |
| --- | --- | --- |
| `SetMovementControlledByAnimation(false)` | no | yes, and never restored |
| `entity:Hide(1)` / `Hide(0)` rebuild | no | yes |
| `daycycle:restartRequest` | no | yes |

A gallop impact emits `actor:Fall` and an impulse and nothing else. The game
recovers the victim, and the observation above shows it also returns them to
their day, choosing a replacement begging spot when the original was no longer
suitable. That is a better outcome than anything this mod has produced by
hand.

The user's question about the rebuild is the right one: it exists to hand a body
back after an animated get-up the mod held to the end. Where the game owns the
recovery there is nothing to hand back, and performing a teardown on an actor
the engine is in the middle of recovering is a plausible cause of the recovery
not completing.

**Movement control being released and never restored is the more serious of the
three.** It is the exact condition the original freeze was traced to: the actor
left on entity-driven movement while its behavior runs elsewhere. That fits the
report precisely, since a beggar continuing to bark while standing inert is a
brain that is running and a body that is not following it.

### The change

For the fall tier only: movement control is handed back immediately before
`actor:Fall`, so the actor reaches physics in the state it would have been in
untouched, and neither the rebuild nor the re-plan runs at all. Beyond the
handover the tier now does exactly what the gallop tier does, which is nothing.

Releasing control during the fall is kept, since that is what stops the clip
carrying its victim through a wall, and it is only held for the length of the
fall now rather than forever.

### Clip lengths, measured

Fifty-six reactions, grouped by character set and direction. Within a group the
spread is under fifty milliseconds, so a clip's length belongs to the clip.

| Direction | Male | Female |
| --- | --- | --- |
| back | 1696-1744 | 1856-1936 |
| forward | 2384-2464 | 3312-3376 |
| left | 4064-4160 | 2016 |
| right | 3008-3104 | 2320-2352 |

Left is the pair that differs most between the sets, at 4.1 seconds against 2.0,
which is why a single timing could not serve both.

The ragdoll now fires at a fraction of the measured length rather than at a
figure per direction. That leaves one number to tune instead of eight, on the
reasoning that these clips share an authoring convention and land at about the
same point in their own length. The starting fraction is 0.6.

## The ragdoll always fires; on some victims it never resolves

Tested at 4.2.0-dev.4. Twenty-two reactions across both character sets.

**User report**: "on some of the woman the freeze occured and my gut tells me you
forgot to get rid of the get up animation we had before because on those ones
that freeze, I don't think I see the rag doll even firing at all."

### The ragdoll fires on every one

Every `hcm_fall_*` reaction logged a matching `VictimFall`, at the timing its
character set and direction call for, and every trace reached `BlendRagdoll`.
The only reaction with no ragdoll was a walk stagger, which is correct.

So the freeze is not a reaction falling back to the old two-clip setup. It is
the opposite: the ragdoll arrives and **does not resolve**. Two traces end at
`BlendRagdoll` with the twenty second window run out, meaning the victim was
still a settling body when observation stopped.

Distance covered ten seconds after impact names the victims:

| Victim | Travel per impact |
| --- | --- |
| rat_woman34 | 1.08, 0.80, 0.24, 0.19, 0.24, 0.84 |
| rat_woman35 | 0.32 |
| rat_guard24 | 0.00 |
| rat_refugee_vojcek | 0.43, 4.20 |
| rat_refugee_beranMr | 0.44, 2.83 |

`rat_woman34` is the repeat case and matches the report of one type of woman.

**The cause is the safety net being removed rather than the ragdoll being
wrong.** Copying the gallop tier meant dropping the rebuild, and the rebuild was
also what eventually freed a victim whose recovery stalled. A gallop victim has
no such net either, but a gallop victim is thrown clear, and being thrown clear
turns out to be what makes the difference.

### Displacement is what returns an NPC to their day

Three observations now say the same thing.

- A merchant walks back to his booth and re-acquires it correctly.
- A beggar hit at a trot is not displaced and stays standing indefinitely.
- **User report**: "the beggars on trot seemed stuck at standing, and then I
  galloped into them a few times and they seemed to snap out of it and reorient
  themselves somewhere else."

The user's note that a freed beggar chooses a different spot rather than the
original is the useful part: the NPC is not resuming an interrupted activity, it
is planning a new one, and planning is what a victim still standing on their own
slot never does.

A gallop differs from a trot fall in exactly one relevant way, which is that it
carries an impulse. The trot fall hands the body to physics with none at all, so
the victim settles where they already were.

### The three changes under test

- A bounded safety net returns, firing only when the ragdoll fails to resolve
  within the ceiling. In the ordinary case the tier still does nothing, which is
  what the gallop tier does.
- The ragdoll carries a small impulse, so a victim is moved off the slot they
  were occupying. This is the gallop's difference, at a fraction of its size.
- The fraction moves from 0.6 to 0.68, against "if anything, the rag dolls are
  firing ever so slightly too early".

## The rebuild is what gives a recovered victim a plan, and the replan is not

Tested at 4.2.0-dev.5, then measured directly on three victims left standing in
front of the player.

**User report**: "I only tested the women because I currently have 3 woman stuck
right in front of me."

### They were not stuck in the ragdoll

Every fall reaction logged `VictimRecovered`, so `BlendRagdoll` was entered and
left on all of them, at waits between 4.2 and 6.8 seconds. Probed live, the
three stuck victims read `MotionIdle` and `MotionIdleVAR1`, upright and alive
with the ragdoll long finished. A fourth victim from the same ride,
`rat_karolina`, read `MotionMovement` and was walking normally.

So the failure is not a recovery that stalls. It is a victim who completes the
recovery and then has nothing to do.

### One test each, on two of the three

| Call | Victim | Travel over six seconds | State after |
| --- | --- | --- | --- |
| `daycycle:restartRequest` | rat_woman12 | 0.00 m | MotionIdle |
| `entity:Hide(1)` then `Hide(0)` | rat_woman43 | 4.11 m | MotionMovement |

The third was left untouched as a control and did not move.

The rebuild frees them and the re-plan does nothing at all. That settles a
question that had been answered by inference twice: the rebuild is not part of
the animated get-up's cleanup, it is what gives any recovered victim a plan, and
it is needed whichever way they got up.

Removing it in order to copy the gallop tier was wrong, and the reasoning behind
it was wrong in an instructive way. The gallop tier does need no rebuild, but
that is not because the game recovers the victim; it is because a gallop throws
them far enough that they re-plan on their own. Recovery and re-planning are two
different things and only one of them was being reasoned about.

### The impulse is not doing what a gallop's does

At a quarter scale the impulse measured 14.5 against a gallop's 24.3, and moved
victims 0.21, 0.91 and 0.94 m. That is consistent with an earlier finding that
what throws a body at a gallop is the horse carrying it rather than the impulse,
and the ragdoll here is created seconds after the horse has gone.

So displacement large enough to force a re-plan is not reachable this way at a
plausible impulse, and the rebuild reaches the same outcome directly.

## Five interventions on a stuck beggar, all inert

A beggar left standing after a trot fall was held in that state and tested
directly, one call at a time, measuring travel and animation state afterwards.
Untouched beggars nearby read `Beggar` throughout, so the state was specific to
the victim rather than to the time of day.

| Intervention | Travel | State after |
| --- | --- | --- |
| `entity:Hide(1)` then `Hide(0)`, same call | 0.00 m | MotionIdle |
| The same pair with a 400 ms gap | 0.00 m | MotionIdle |
| `actor:Fall`, no impulse | 0.66 m | MotionIdle |
| `actor:Fall` with an impulse of 70 | 1.71 m | MotionIdle |
| `SetWorldPos` 4.5 m away, then `daycycle:restartRequest` | 4.47 m | MotionIdle |

None returned him to begging.

The last row matters most because it is vanilla's own teleport recovery, the
pairing used in `hasteInstruction_teleportBase.lua`, and because it removes
displacement as the explanation. He was moved four and a half meters clear of
his spot and re-planned, and still did nothing.

The impulse row confirms the earlier finding from another direction: 70 of
impulse moved a free body 1.71 m, so what throws a victim at a gallop is the
horse carrying them and not the impulse. Displacement of the size a gallop
produces is not reachable from a ragdoll created after the horse has gone.

### A stuck beggar and a stuck villager are not the same failure

Both read `MotionIdle`, upright, with the ragdoll long resolved. The difference
is what frees them: hiding and showing a stuck villager moved her 4.11 m into
`MotionMovement`, and the identical call on the beggar moved him nothing at all.

So the rebuild does not restore an activity. It restores an NPC who had no
activity to return to.

### What is left

Two things free a beggar and neither is understood: the player leaving the area
and returning, and a fresh gallop impact.

A gallop may not be curing anything. It hits a beggar who is still in `Beggar`
rather than one already stuck, and it may simply be a path that never creates
the problem. Under that reading the question is not what a gallop does
afterwards but what the trot fall does that a gallop does not.

Three differences were identified between the two paths. The impulse is now
removed, and movement control is handed back before the ragdoll. **One remains
untested: the trot fall releases movement control for the length of the fall
and a gallop never touches it at all.**

## The movement control release is not what breaks an activity NPC

Tested at 4.2.0-dev.7 with `ReleaseAnimationMovement` off, which is the last
structural difference between the trot fall path and the gallop path.

**User report**: "Beggar goes through the wall and stands up and stays there and
doesn't return. nothing else to report."

Going through the wall is the setting being off and is expected. Not returning
is the answer: taking the release away does not restore the beggar, so it was
never the cause. The setting is back on.

That exhausts the differences between the two paths. The impulse was removed,
movement control is handed back before the ragdoll, and the release itself is now
ruled out.

### A correction to the previous entry

A beggar observed back in `Beggar` without intervention had not recovered on his
own; the user had reloaded a save. Nothing about a stuck beggar improves with
time. The recovery trace, extended to two minutes, holds `MotionIdle` and
`MotionIdleVARdefault` past a hundred seconds.

### The context tables, compared

`Contexts.GetDataTable` reads what options an entity carries. Between a stuck
beggar and a healthy one the only difference was:

```
stuck     suppressAutoCure: HorseCollisionMod=false
healthy   suppressAutoCure:
```

`false` means the option is not active, and `Contexts.ClearOption` refused it for
exactly that reason: "doesn't have the 'suppressAutoCure' option active with
handle 'HorseCollisionMod'". So this is a residual key rather than a live option,
and clearing it moved the victim 0.00 m. Not the cause, and recorded so the same
difference is not chased again.

### Everything that does not free a stuck activity NPC

Measured on beggars held in the stuck state, each tried on its own:

`entity:Hide(1)`/`Hide(0)` together, the same pair with a 400 ms gap,
`actor:Fall` with no impulse, `actor:Fall` with an impulse of 70, `SetWorldPos`
4.5 m away followed by `daycycle:restartRequest`, `Contexts.ClearOption`, and
turning off the movement control release for the whole reaction.

Every one left the victim in `MotionIdle` having traveled at most the distance
the call itself moved them. Only a save load restores them.

### Where that leaves the tier

The fall tier is better than the animated get-up for ordinary NPCs and worse for
activity NPCs. Under the animated get-up a beggar and an innkeeper returned to
their animations, facing the wrong way; under the fall tier they do not return at
all. That is a regression against what `main` ships, and the tier cannot take the
default while it stands.

## A stuck beggar is a behavior tree waiting for an animation that was destroyed

This is what makes an activity NPC's `MotionIdle` different from a villager's,
and it was found by reading `so_beggarworkplace.xml` rather than by testing.

### The shape of the beggar's tree

```
FuseBox
  Child: LuaWrapper(SetNonpersistentOption suppressDudeProxBark_greet, 'begging')
    Sequence
      AddLink usedSO -> the workplace
      InstantSendMessageToNPC daycycle:behavior:progress
      IfCondition tag == '' -> RandomGate -> beggarLaying or beggarKneeling
      LODGuardian
        Detail
          Sequence
            PlayAnimation 'Beggar'
            ...
            PlayAnimation 'BeggarOut'
            AnimationEventWait Id='animation' Event='LogicalEnd'
  OnFail
    Sequence
      RemoveLink usedSO
      SuppressFailure
```

Two things follow.

**The link is released only on failure.** `RemoveLink usedSO` sits in the
FuseBox's `OnFail` branch, so it runs when the child fails and at no other time.

**The child cannot fail; it waits.** The sequence ends in `AnimationEventWait`
for a `LogicalEnd` event. An interactive action seizes the body and the animation
that would have raised that event no longer exists, so the node neither succeeds
nor fails. The tree parks there permanently.

That is the whole difference. A villager's `sa_` activity is issuing movement and
re-evaluating; a beggar's `so_` tree is blocked on an event that will never come.
It also matches the independent finding recorded earlier for
`sb_switch_hitreactions`, whose handler stalls the same way on an animation that
never completes.

### Why everything tried so far failed

Nothing that was tried touches a parked tree node. Brain variables are identical
between a stuck and a healthy beggar because the block is in tree execution
rather than in brain state; the context tables match for the same reason;
`daycycle:restartRequest`, `daycycle:interrupt` and `daycycle:change` are
messages the parked node is not listening for; and `entity:Hide` rebuilds the
entity while the tree state survives. A save load works because the tree is
instantiated afresh.

### The LODGuardian is the way out, and it is verified

`LODGuardian` plays the animation in its `Detail` branch and substitutes a plain
wait in the `LOD` branch. Moving an NPC into the LOD branch therefore abandons
the Detail sequence and the parked `AnimationEventWait` with it. That is exactly
what the player leaving the area does.

Tested on a beggar held in the stuck state, by narrowing the AI level of detail
distances so he fell outside `Detail`, then restoring them four seconds later:

```
[L] forced LOD distances low
[L] restored LOD distances
[L] kunes after LOD flip travel=0.00 state=BeggarVAR
```

He returned to begging without moving, having been inert through seven earlier
interventions. The mechanism is confirmed.

### What a fix has to be

`WH_AI_LOD_DistanceMin` and `WH_AI_LOD_DistanceMax` are global, so flipping them
degrades every NPC in the world for the duration and cannot ship. Two directions
follow from the same understanding:

- **Per-entity.** `WH_AI_LOD_Override` exists and its argument form is not yet
  known. If the level of detail can be forced on one actor, the flip becomes
  local and the fix is a few lines.
- **Prevent rather than repair.** The tree parks because the animation it waits
  on is destroyed without failing. Anything that makes that node fail instead
  reaches `OnFail`, which releases the link and lets the tree recover on its own,
  which is what vanilla intends.

## Vanilla's own abort is a tree node, and Lua has no equivalent

Following the parked-node finding, the question became what makes the parked
`AnimationEventWait` fail, since failing is what reaches the `OnFail` branch that
releases the smart object and lets the tree recover.

**Vanilla's answer is `AbortAllAnimations Target="this.id"`.** It appears in
twelve trees, and in `sb_combat.xml` it is gated on exactly the flag the beggars
carry:

```
IfCondition condition="$b_interruptAnimationsInCombat"
  AbortAllAnimations Target="this.id"
Expression "$b_interruptAnimationsInCombat = true"
```

Probed, every beggar reads `b_interruptAnimationsInCombat = true` while a
sitting villager reads `false`. So the game already knows these animations must
be aborted rather than interrupted, and it does so when combat starts.

`AbortAllAnimations` is a behavior tree node. It has no Lua bind, and the bind
list carries nothing else of that shape.

### Two candidates tested and neither works

**`human:StopAnim`** was recorded earlier as inert, but only ever on a victim
stuck for minutes, which left the result open to being an artifact of the moment
it was tried. Repeated properly on a healthy beggar mid-animation, it returns
`ok=true` and the actor is still `Beggar` twelve seconds later. The call is
accepted and does nothing, which is what the bind reference already says of it.

**`daycycle:behavior:progress` with `progress(false)`** is the counterpart of the
message the tree sends on entering, so it was the most plausible way to tell the
daycycle the behavior had ended. Sent to a stuck beggar it is accepted and
changes nothing: `MotionIdle` before, `MotionIdle` ten seconds later.

### Where this leaves the fix

The mechanism is fully understood and the repair is not reachable through any
Lua bind found so far. What has been established is narrow and useful: the fix
must make the animation abort, not stop, not interrupt, and not be seized; and
the game has a node that does exactly that, reserved for combat.

Untried, and each a different shape of the same idea:

- Reaching `AbortAllAnimations` indirectly, by finding what else in the game
  raises it outside combat. Eleven trees other than `sb_combat` use it.
- Making the victim briefly satisfy whatever condition the combat subbrain
  enters on, so vanilla aborts the animation itself.
- The animation event system directly, since the parked node waits on
  `LogicalEnd` for a named `AnimationWUID`; if that event can be raised from
  Lua, the node completes and the tree continues normally rather than failing.

## The parked tree reaches merchants too, and that is a regression against main

Tested at 4.2.0-dev.8, the merge candidate.

**User report**: "no clipping, falls look good, no freezes, but this merchant
next to me was not able to return to his activity and seems stuck when usually
on every test before this he always was able to snap back in to place. I tested
the two woman traders across the street and they were both able to return to
their loops."

`rat_merchant_shop1` and `rat_merchant_shop3` both read `MotionIdle`.
`rat_merchant_shop2` read `MotionMovement` and was fine.

The LOD flip that freed a beggar was applied to the two idle merchants.
`rat_merchant_shop1` moved 3.95 m and entered `ADLG_Agree`, so he had been
parked in the same way. `rat_merchant_shop3` moved 0.48 m and stayed
`MotionIdle`, which is inconclusive since a merchant standing at his stall is
legitimately idle.

So the failure is not specific to beggars and innkeepers. It reaches any NPC
whose smart object tree is parked, and merchants escaped it earlier only because
their activity involves walking, which re-plans them. When one is left close
enough to his stall to skip the approach, he parks like a beggar.

### Why this is a regression rather than a pre-existing fault

Both tiers seize the actor with `StartInteractiveActionByName`, so both should
park the tree equally. They do not, and the difference is what happens next.

Under `knockdown` the interactive action runs to its end and Mannequin releases
the actor when the fragment completes. Measured at 4.1.0-dev.1, a beggar and an
innkeeper both re-entered their animations afterwards, turned the wrong way but
present.

Under `fall` the actor is taken by `actor:Fall` partway through the fragment,
so the interactive action never completes and never releases. That is the
plausible cause of the parking, and it is introduced by this branch.

The tier therefore trades a rotation fault that main has for an activity fault
that main does not.

## Messages have to be typed tables, and ours have all been empty strings

This is the reason a long list of calls has been recorded as accepted and inert,
and it is not that the brain cannot be reached.

### Two ways to send a message, and only one carries a payload

```lua
XGenAIModule.SendMessageToEntity(id, name, "")            -- string values
XGenAIModule.SendMessageToEntityData(id, name, table)     -- typed payload
```

`Libs/AI/TypeDefinitions.xml` declares what each message carries:

| Message | Required members |
| --- | --- |
| `daycycle:restartRequest` | `reason` enum, `speed` enum |
| `daycycle:interrupt` | `behaviorSource` wuid, `behaviorName` string, `includeXml`, `includeTree`, `daycycleHaltSpeed` enum, `immediateActivityBeingSwitchedIntoHandle` |
| `daycycle:progress` | `progress` bool, `behavior` string |
| `haltContext` | `reason` enum, `speed` enum |

Vanilla builds these with `Utils.makeTable`, which is reachable from Lua and used
in the game's own scripts:

```lua
local msg = Utils.makeTable('dog:changeRequest',
        { newMaster = true, master = player.this.id,
          newMode = true, mode = enum_dogCompanionMode.free })
XGenAIModule.SendMessageToEntityData(dog.this.id, "dog:changeRequest", msg)
```

Every message this project has sent used the string form with `""`, so the
members arrived unset and the receiving node had nothing to match on. The message
was delivered and discarded, which is indistinguishable from a call that does
nothing.

### Measured on the same victim

`rat_merchant_shop1`, parked in `MotionIdle` after a trot collision:

| Form | Travel |
| --- | --- |
| `SendMessageToEntity(id, 'daycycle:restartRequest', '')` | 0.00 m |
| `SendMessageToEntityData` with `reason=interrupt, speed=instant` | **3.94 m** |

The typed message re-planned him and he walked back to his stall. The string
form had been tried repeatedly across this branch and never moved anyone.

The enums are globals: `enum_daycycleHaltReason` is
`unknown 0, combat 1, death 2, interrupt 3, situation 4`, and
`enum_daycycleHaltSpeed` is `slow 0, fast 1, instant 2`.

### What this does not explain

`human:StopAnim` takes no payload and is still inert, so it belongs to a
different category. Registration in the decompiled binary is identical to
working calls such as `GetHorse` and `IsMounted`, so the difference is in the
body rather than the binding. The working set is physics, stats and entity
transforms, none of which the animation system re-asserts every frame; the inert
set is animation control on an actor a behavior tree owns, which it does.

### Interfaces present at runtime and absent from the bind reference

Taken from a dump of the live Lua state rather than from the registration list:
`XGenAIModule.MakeTableFromType`, `SendMessageToEntityData`, `SetBrainVariable`,
`_GetDataVariable` and `_SetDataVariable`. `SetBrainVariable` has never been
used by this project and is the one genuine write into an NPC's brain that is
known to exist.

`AbortAllAnimations` is confirmed as `wh::xgenaimodule::BehaviorTree::C_AbortAllAnimations`,
a tree node class with no Lua entry point, so it is reachable only by a tree
that runs it.

## Typed messages, run against a parked merchant

The four messages this project had recorded as inert, resent as typed tables
against `rat_merchant_shop1` parked in `MotionIdle`, one at a time with nine
seconds between them.

| Message | Travel | State after |
| --- | --- | --- |
| `daycycle:restartRequest` | 0.10 m | MotionIdle |
| **`daycycle:haltContext`** | **3.42 m** | **MotionMovement** |
| `daycycle:interrupt` | 0.57 m | MotionIdle |
| **`daycycle:behavior:progress`** | **3.21 m** | **MotionMovement** |

`daycycle:haltContext` moved a victim that `daycycle:restartRequest` had just
failed to move, which is the useful result: halting the context is what a parked
tree needs, and restarting the daycycle is not.

`daycycle:interrupt` is the one that had been predicted to work, on the grounds
that it carries the richest payload and is what vanilla sends to stop a
behavior. It did not.

### The run has a flaw worth naming

The four were sent to the same victim in sequence, so each was applied to
whatever the previous one left behind. The victim was walking when
`daycycle:interrupt` arrived rather than parked, and was walking again after
`behavior:progress`, so neither of those results is clean.

Only the first two rows are trustworthy: a genuinely parked victim was unmoved
by `restartRequest` and freed by `haltContext`. The probe now takes a single
candidate so each can be tried against a freshly parked victim.

### On the earlier merchant result

The same merchant had been moved 3.94 m by a typed `restartRequest` earlier in
the session, and moved 0.10 m by it here. The difference is that the mod now
sends a typed `restartRequest` as part of the reaction, so by the time the probe
ran he had already received one. A message that has already been delivered has
nothing left to do, which is consistent rather than contradictory.

## The typed replan fixes every activity NPC

Tested at 4.2.1-dev.1, whose only change from 4.2.0 is that `ReplanVictim`
sends `daycycle:restartRequest` as a typed table rather than as an empty string.

**User report**: "he just got up and started walking ways towards a new place to
beg... I tried another beggar and she also got up and starting walking away
towards another begging spot... I hit a woman sitting on a bench and she got up
and sat back down. Every merchant I hit was able to reset normally. I even went
and hit the innkeeper and he got up and naturally put himself back into his
proper leaning position."

Eighteen replans this session, all typed, none falling back to the string form.
Live states afterwards:

```
rat_innkeeper1      = Leaning
rat_refugee_vojcek  = Beggar
rat_refugee_beranMr = MotionMovement
rat_merchant_shop1  = MotionIdle
```

So the parked tree, the unreleased `usedSO` link, the beggar that only a save
load recovered and the innkeeper that never returned were all one fault: a
message the game accepted and discarded because its declared members were never
filled in.

### The distance metric is retired

`travel` ten seconds after impact was used throughout this investigation as the
test for whether a victim recovered, and it flagged the innkeeper as stuck at
0.20 m in the same session he was observed leaning correctly. He leans in place
and never travels; a beggar returning to his own spot does not travel either.

The measure was only ever valid while returning to an activity required walking
back to it, which was true of a displaced merchant and of nobody else. Animation
state is the honest test and is what the probes now read.

### A note on how the battery was run

The four typed messages were fired at whatever was parked from an earlier state,
without the preconditions being stated first, so the run measured a victim that
had already received a typed replan from the mod. `daycycle:haltContext` moving a
parked merchant 3.42 m is still a real observation, but it is not evidence that
`haltContext` is needed: the typed `restartRequest` in the reaction covers every
case tested since.

## The attacker resolves when it is sent as a WUID rather than as text

Tested at 4.2.11-dev.1. `hitReaction` declares `attacker` as `common:wuid`, and
the message had been carrying it through `Framework.WUIDToMsg`, which renders a
sixty-four bit identifier into the message text for a tree to parse back. It is
now built with `Utils.makeTable` and sent with `SendMessageToEntityData`.

Twenty-three sends, every one `typed=true attacker=true`, no errors.

### Damage, before and after, from one session's log

The build was hot-reloaded partway through, so both forms appear in the same
log against the same save.

| | Tier | Impacts | No damage | Mean loss |
| --- | --- | --- | --- | --- |
| Before | Gallop | 3 | **3 (100%)** | 0.00 |
| After | Trot | 18 | 1 (5.6%) | 5.94 |
| After | Gallop | 2 | 0 | 26.61 |

### The repetition test is the part that carries weight

A single impact cannot distinguish a mitigated hit from a dropped message, which
is why an earlier session could not settle this. Repeated impacts on one victim
can, and every repeat landed:

```
rat_woman34   -7.00  -11.63  -6.23
rat_man95     -5.34   -5.25  -4.80
rat_woman44   -6.64   -3.63  -5.34  -5.41
rat_ruch      -6.26   -6.66
```

Trot losses cluster between 3.6 and 7.4 with one at 11.6, which is the shape of
a hit resolving every time rather than intermittently.

### What this does not establish

The sample is small and unbalanced. There is no trot baseline in this log,
because the reload happened before any trot impact under the old form, so the
comparison rests on three gallops. Three of three failing and none of two
failing is suggestive and is not a measurement.

One trot impact still did nothing, on `rat_shop_guard_butcher`. Armor does not
reduce damage in this mod, so a guard is not expected to differ, and one case is
not a pattern.

### The open question this reopens

If the attacker now resolves, the branch inside `sb_switch_hitreactions.xml`
that follows the horse's `rider` link to the player, and re-sends the event as
`combat:hit`, is reachable. That branch is what applies damage and attributes
crime, and `combat:hit` feeds the combat sub-brain, which owns the body. The
conclusion that a reaction animation is unreachable from a mod was drawn when
that path was assumed dead.

## A testing hazard: the first sprint after a save load gallops

**User report**: "there is this bug that I don't think is our mods doing and is
just vanilla where after you reload a save, the first time you press the run
button while on the horse it automatically gets to gallop speed even though you
didn't hold forward or double press."

Not caused by this mod, and it does not need fixing here, but it corrupts a ride
that is meant to be at a single tier: the first impact after a load can arrive
at gallop when the rider meant to trot. It cost the opening impact of a
controlled comparison.

Two protections, both cheap:

- **Filter by the tier the log records** rather than by what the ride intended.
  Every impact writes its tier, so an accidental gallop is excluded by the
  analysis instead of by the rider's memory.
- **Write a marker into the log** at the start of a measured phase, and count
  only what follows it. A phase that has to be restarted then costs nothing.

## The attacker encoding makes no difference, and that kills the premise

A controlled comparison at 4.2.11-dev.2. One save, one session, no reload
between phases: the form is switched from the console, so entity ids, cooldowns
and the horse are held constant. Trot only, since the gallop trample adds engine
damage unrelated to the message. Phase B used victims Phase A had not touched.

| Phase | Form | Trot impacts | No damage | Mean loss |
| --- | --- | --- | --- | --- |
| A | string | 11 | 2 (18%) | 4.85 |
| B | typed | 13 | 2 (15%) | 5.26 |

Eighteen per cent against fifteen, on samples of eleven and thirteen, is noise.
The typed form is not better and not worse.

### What that settles

**`Framework.WUIDToMsg` resolves.** Trot damage exists only because vanilla
follows the horse's `rider` link to the player and re-sends the event as
`combat:hit`; that branch cannot run without an attacker it can resolve. Damage
landed on eleven of thirteen impacts under the string form, so the attacker was
resolving all along.

The theory behind this branch was that the WUID was being mangled into text and
failing to resolve, and that this explained victims taking no damage. It is
wrong. It was built on an archived note reading "the vanilla branch did not
resolve riderPlayer", which was one candidate among several in that entry and
was never the finding.

**It also removes the premise for retrying `combat:hit`.** That plan rested on
the same encoding argument. Reopening it now needs a different reason, and there
is not one yet.

### What is still unexplained

Roughly one impact in six does no damage, in both forms. Four cases here:

```
A   rat_refugee_vojcek        beggar, activity anchored
A   rat_merchant_shop1        merchant, activity anchored
B   rat_innkeeper1            innkeeper, activity anchored
B   rat_swordsmiths_wife      second impact on the same victim
```

Three of the four are NPCs whose day is anchored to a smart object, which is
suggestive and is not a result at four cases: other anchored victims in the same
ride, `rat_refugee_Radan` and `rat_refugee_tonda_rumpal`, took damage normally.

Worth stating that the zero rate is not new and was not introduced here. It sits
at the same level under the form that shipped in 4.2.1.

## Neither the encoding nor the attacker changes the zeros

Three phases at 4.2.11-dev.2 and dev.3, one save, no reload between them, the
form and the attacker switched from the console so the horse, the entity ids and
the cooldowns stay constant. Trot only.

| Phase | Form | Attacker | Trot | No damage | Mean |
| --- | --- | --- | --- | --- | --- |
| A | string | horse | 11 | 2 (18%) | 4.85 |
| B | typed | horse | 14 | 2 (14%) | 5.09 |
| C | typed | player | 10 | 2 (20%) | 5.04 |

Thirty-five impacts, six with no damage, and the rate does not move.

**Naming the rider directly makes no difference either.** That was worth
testing: naming the horse leaves the game to follow the horse's `rider` link
before it re-sends the event as `combat:hit`, and an intermittently
unresolvable link would have produced exactly this pattern. It does not.

### The zeros are real, not a sampling window

Impact cost is sampled at four offsets. Every victim reading zero at t+3000
reads zero at t+500, t+6000 and t+10000 as well:

```
rat_refugee_vojcek     +0.00  +0.00  +0.00  +0.00
rat_merchant_shop1     +0.00  +0.00  +0.00  +0.00
rat_innkeeper1         +0.00  +0.00  +0.00  +0.00
rat_swordsmiths_wife   +0.00  +0.00  +0.00  +0.00
rat_man13              +0.00  +0.00  +0.00  +0.00
rat_refugee_maruna     +0.00  +0.00  +0.00  +0.00
```

Nothing arrives late. The hit does not land at all.

### What is left, and it is about ordering rather than content

`TriggerCollision` starts the reaction and then sends the hit:

```lua
self:PlayReaction(npc, velocity, speed, "hcm_fall_")
self:SendHitReaction(npc, horseWuid, strength.MinorInjury, playerEnt)
```

`PlayReaction` seizes the actor through `StartInteractiveActionByName`. The hit
message therefore arrives at a victim whose body has just been taken, and an
earlier entry recorded that handlers declared `Atomic="true"` drop messages
while busy. A handler occupied by the reaction would drop the hit for some
victims and not others, which is the shape of what is measured, and it is
independent of what the message contains, which is why three phases of changing
the contents moved nothing.

## Ordering does not change it either, and the message may not be the source

Phase D at 4.2.11-dev.4, the hit sent before the reaction seizes the body
rather than after it. Same save, same session, no reload.

| Phase | Form | Attacker | Sent | Trot | No damage | Mean |
| --- | --- | --- | --- | --- | --- | --- |
| A | string | horse | after | 11 | 2 (18%) | 4.85 |
| B | typed | horse | after | 14 | 2 (14%) | 5.09 |
| C | typed | player | after | 10 | 2 (20%) | 5.04 |
| D | typed | horse | **before** | 18 | 3 (17%) | 4.85 |

Fifty-three trot impacts across four configurations. The rate does not move,
and neither does the mean.

### The variable that has never been tested is whether the message matters at all

**User recollection**, and it reframes the whole question: "way back in the
v1.00-1.20 or somewhere in the early days of development we were able to produce
a hit on people based on collision, which back then was purely through
fall/ragdoll or just the insphere, that made the guards instantly want to kill
me."

Those builds had no `hitReaction` message. The reaction was a physics ragdoll
and the damage and the crime came from the collision itself, which is the
engine charging a velocity delta against a physics body.

Four phases have varied what the message contains and when it is sent, on the
assumption that the message is what produces the damage. That assumption has
never been checked. If trot damage comes from somewhere else, every one of those
phases was measuring noise around a figure the message does not set, which is
exactly what a flat rate across four configurations looks like.

The test is to switch the message off entirely and see whether damage still
lands at the same rate.

## Switching the hit message off removes the zeros

Phase E at 4.2.11-dev.4, `SendHitReaction` disabled entirely. Same save, same
session, no reload.

| Phase | Configuration | Sends | Trot | No damage | Mean |
| --- | --- | --- | --- | --- | --- |
| A | string, horse, after | 11 | 11 | 2 (18%) | 4.85 |
| B | typed, horse, after | 14 | 14 | 2 (14%) | 5.09 |
| C | typed, player, after | 12 | 10 | 2 (20%) | 5.04 |
| D | typed, horse, before | 19 | 18 | 3 (17%) | 4.85 |
| **E** | **no message at all** | **0** | **13** | **0 (0%)** | **6.30** |

Thirteen impacts, none of them free, and the highest mean loss recorded.

### The message is not the damage, and may be what prevents it

The assumption behind four phases was that `hitReaction` is what produces the
damage, so its contents and its timing were varied to find why it sometimes did
not. Removing it produced more damage, more reliably.

That fits the user's account of the earliest builds, which had no such message:
"we were able to produce a hit on people based on collision, which back then was
purely through fall/ragdoll or just the insphere, that made the guards instantly
want to kill me". The damage and the crime came from the collision, and they did
so before this mod ever sent a message.

### Held to what it proves

Zero of thirteen against eleven of fifty-three. If the underlying rate were the
seventeen per cent the other phases show, a run of thirteen with none has roughly
a one in eleven chance, so this is suggestive rather than settled on its own. The
mean rising from about 4.9 to 6.3 is a second signal in the same direction, and
the four configurations on the other side agree with each other.

A confirming phase with the message back on, under otherwise identical
conditions, is what would settle it.

### The open question this raises

`hitReaction` is in the roadmap as a Phase 1 deliverable, for one reason: to keep
the vanilla collision bark. If the barks continue without it, the message costs
damage and buys nothing. If they stop, there is a real trade to weigh.

## Six phases, and the zero-damage impacts remain unexplained

Phase F put the message back on under Phase B's exact configuration, as an
A/B/A. It did not reproduce.

| Phase | Message | Trot | No damage | Mean |
| --- | --- | --- | --- | --- |
| B | on, typed, horse, after | 14 | 2 (14%) | 5.09 |
| D | on, typed, horse, before | 18 | 3 (17%) | 4.85 |
| E | **off entirely** | 13 | 0 (0%) | 6.30 |
| F | **on again**, as B | 15 | 0 (0%) | 6.21 |

Pooled, the message being on gives five zeros in forty-seven and off gives none
in thirteen, which looks like an effect until F is read: the message was on and
the zeros still did not appear. **Phase E was a false positive and was nearly
written up as a finding.**

The zeros stopped after Phase D and no variable under test explains it.

### Everything ruled out, on eighty-one trot impacts

- **Message contents.** String against typed: 18% against 14%.
- **Attacker identity.** Horse against rider: 14% against 20%. Naming the rider
  skips the `rider` link resolution entirely and changes nothing.
- **Ordering.** Sent before the reaction seizes the body against after: 17%
  against 14%.
- **The message existing at all.** Off against on, within the later phases:
  0% against 0%.
- **Impact speed.** Zeros averaged 6.76 m/s and hits 6.84 m/s, over the same
  range. Not glancing blows.
- **Repeat impacts.** Three of ten zeros were repeats, against thirty-nine of
  seventy-one that dealt damage. Zeros skew towards first hits, not away.
- **Sampling.** Every zero reads zero at t+500, t+3000, t+6000 and t+10000.

### What is actually known

The rate is about one impact in eight overall, it predates this branch, and
nothing here made it better or worse. The vanilla collision bark fires with the
message and without it, which removes the one documented reason for sending it,
but not on evidence strong enough to act on given how this investigation went.

### The lesson, which is the useful part

Four phases were spent varying the contents and timing of a message on the
assumption that it was the damage source, and that assumption was never checked
until the user recalled that the earliest builds produced damage and crime with
no message at all. The check took one ride and overturned four.

Then Phase E's clean run was very nearly recorded as a discovery, on thirteen
impacts, before the confirming phase showed the effect was not there. A run of
thirteen with no zeros has about a one in eleven chance at the observed rate,
which is exactly the kind of number that reads as a result and is not one.

## Riding over the fallen is caught by the gate, and the zeros are not that

Phase G at 4.2.11-dev.5, recording the victim's animation state at the moment of
impact, ridden the way the player normally rides rather than at clean standing
targets.

**User note**, and the reason for the phase: "are you taking into account the
fact that I run over the NPCs while they are on the ground like 90% of the
time?"

Fourteen trot impacts reached the damage telemetry. Two cost nothing, and both
were on victims who were upright:

```
rat_woman10          MotionMovement   +0.00
rat_refugee_beranMr  BeggarVAR        +0.00
```

Against twelve that did cost, on `MotionMovement`, `Beggar`, `IdleToMove` and
`MotionIdle`. Every state that appears in the zero column also appears in the
column that took damage, and `rat_woman10` reads `MotionMovement` for both a
zero and a normal loss in the same ride.

### The gate is doing its job

In the same session the cooldown gate turned away **174** impacts, and only
**two** impacts on a victim mid-reaction reached the telemetry at all. So
riding over the fallen is being filtered before any of this is measured, which
is what it is for.

That is worth knowing on its own: the impacts a player spends most of their time
making are invisible to the damage telemetry by design, so any reading of
"damage per impact" from this log describes clean standing hits and nothing
else.

### Where the zeros stand after seven phases

Roughly one impact in eight on a standing victim costs nothing, and none of
these explains it: the message's contents, its attacker, its ordering, its
existence, the impact speed, whether the victim had been hit before, the
sampling window, or the victim's state at impact.

It predates this branch and nothing here moved it. It is now well bounded, which
is the only progress: it happens to upright victims, at ordinary trot speeds, on
first and repeat impacts alike, with and without the hit message.

## A typed combat hit registers as a crime, where the string form never did

Phase I at 4.2.12-dev.1, `combat:hit` sent as a typed table built with
`Utils.makeTable`, in vanilla's own shape: the player named as attacker, the
collision rewritten as `Melee`, `real` set true.

**User report**: "on the first hit it was a recognized crime with a witness
calling for help. I hit another woman and then I surrendered to the guard. He
said I was brawling, I paid the fine."

Two impacts, both `CombatHit ok=true`, both costing the victim the usual amount:
`-5.80` and `-5.95`. The damage is unchanged. What is new is that the game
recognized the act, produced a witness, and charged the player for it.

### This overturns a documented conclusion

`docs/TECHNICAL_DETAILS.md` lists the `combat:hit` brain message as delivered
and handled by a tree that cannot drive the body, alongside `hitReaction`. That
came from an earlier session which sent it twelve times as a `key(value)`
string and observed no reaction and no hostility, and recorded plainly that
"`ok=true` proves nothing".

The message was correct. The payload was not carried. Sent as a typed table the
same message reaches the combat subbrain and is acted on, which is the third
time this project has found an accepted message doing nothing because its
declared members never arrived.

### What it delivers, and what it does not

It delivers a roadmap item that has been open since Phase 3 was written: riding
someone down in a village is something the game notices.

It does not appear to drive an animation. The user reported no reaction beyond
the mod's own fall, so the hope that reaching the body-owning subbrain would
produce an engine-authored hit reaction is not supported by this test, though
two impacts cannot rule it out.

### Open, and worth a moment's thought before shipping

The charge was **brawling**. `hitType` is sent as `Melee`, because that is what
vanilla's own branch rewrites a player-ridden collision into, so the game is
being told Henry struck them by hand. Whether a collision should be charged as
brawling, as assault, or not at all is a design question rather than a technical
one, and `HitReactionType.Collision` is the obvious alternative to measure.

Making every trot collision a crime is a large change to how the mod plays, and
it is off by default until that is decided.

## What the game charges for a ridden collision, measured

Four runs at 4.2.12-dev.2, one impact each, reloading between them so the charge
could be read by surrendering to a guard. `combat:hit` sent as a typed table
with the player as attacker and `real` true; only `hitType` and `strength` vary.

| Run | hitType | strength | Result |
| --- | --- | --- | --- |
| 1 | Melee | MinorInjury (5) | "beating people right under my nose?" charged, fine |
| 2 | Melee | MajorInjury (6) | "you're brawling!" charged, 80 gold |
| 3 | **Collision** | MinorInjury (5) | **no crime at all, across five impacts** |
| 4 | **Collision** | MajorInjury (6) | **no crime at all** |

### The crime system does not see a collision

`HitReactionType.Collision` produces no crime whatever the strength. Only
`Melee` does. That is why the vanilla branch in `sb_switch_hitreactions.xml`
rewrites a player-ridden collision into `Melee` before re-sending it as
`combat:hit`: the crime system has no concept of being ridden down, so the game
launders it into the one hit type it does prosecute.

So a collision can be made a crime, and only by describing it as something it is
not.

### Severity moves with strength, within one label

Both `Melee` runs produced the same kind of charge and a different fine, 80 gold
at `MajorInjury` against a smaller figure at `MinorInjury`. The crime label
appears to stay assault-shaped while the penalty scales, which is most of what
was wanted from severity scaling and needs no new message.

`Crime.lua` in `Scripts.pak` defines the labels and their reaction profiles:
`assault` has civilians auto-reacting within 2 m and able to react within 8;
`murder` within 3 and 12. Both are named strings, and `crimeReport` carries a
`crime:string` member, so naming a crime directly is a channel that exists and
has not been tried.

### Where that leaves the design

Making a trot collision a crime works today, by sending `Melee`. The cost is
that the game believes Henry struck them by hand, which is why the guard talks
about beating and brawling rather than about riding anyone down. Whether that
trade is worth taking, and whether a fatal collision already produces murder on
its own, are the open questions.

## The crime matrix for a typed combat hit

Nine runs at 4.2.12-dev.2, one impact each, reloading between them and reading
the charge by surrendering to a guard. Every run corroborated against the log,
which records the `hitType` and `strength` actually sent.

| hitType | strength | Charged | Guard's words |
| --- | --- | --- | --- |
| Melee (1) | Tickle (2) | yes | "no one gets away with beating people up around here" |
| Melee (1) | MinorInjury (5) | yes | "beating people right under my nose?" |
| Melee (1) | MajorInjury (6) | yes | "you're brawling!" |
| Melee (1) | Fatal (7) | yes | "I saw you beating folk" |
| Collision (2) | MinorInjury (5) | **no** | nothing, over five impacts |
| Collision (2) | MajorInjury (6) | **no** | nothing |
| Fall (7) | MinorInjury (5) | **no** | nothing |
| Bullet (10) | MinorInjury (5) | yes | "nobody gets away with shooting people here" |
| MeleeStealth (16) | MinorInjury (5) | yes | "forgotten that brawl, have you?" |

### What the message actually controls

**`hitType` decides whether there is a crime, and what it is called.** Melee and
MeleeStealth are prosecuted as a brawl, Bullet as a shooting. Collision and Fall
are invisible to the crime system entirely, at any strength.

**`strength` changes nothing about the crime.** Tickle, documented as costing no
health at all, is charged exactly as Fatal is. So the crime does not come from
harm; it comes from the hit existing.

**`combat:hit` does no damage.** `Fatal` is documented as killing a fully
healthy target and the victim did not die. Damage comes from the collision
itself, which the earlier phases established when removing the mod's hit message
left damage unchanged.

So this message is an attribution channel and nothing else.

### What that means for severity

Severity cannot be scaled through this message. The ladder the game gives is
assault for any hit and murder when the victim actually dies, which the user has
confirmed happens on its own at a gallop.

The fine is scaled by the victim's social class rather than by the hit:
`nobleman` 12.5, `bailiff` 5, `officer`, `soldier` and `watchman` 2.5,
`circator` 2, the craft trades 1.5, and everyone else 1. The eighty gold
recorded earlier against a remembered sixty is therefore not evidence that
strength scales anything, since the two victims were different people.

### Still untried

The second `hit` type, `attacker, kind, real`, where `kind` is a
`combatAttackKind` of `none`, `missile`, `stealthAction`, `unarmed`, `melee` or
`dogBite`. And `crimeReport`, which carries a `crime:string` and is the game's
own channel for naming a crime rather than implying one.

## The undeclared hit types do nothing, and there is no explosion

`HitReactionType` is declared in `TypeDefinitions.xml` with the comment "These
correspond to the C++ enum => weird values", and its five values leave gaps at
3 to 6, 8, 9 and 11 to 15. Those gaps are real C++ values the XML does not
expose, so each was sent as a `combat:hit` against a live victim.

**All eleven produced nothing.** No witness, no crime, no reaction. Combined
with the earlier runs, the complete picture is:

| Value | Declared as | Crime |
| --- | --- | --- |
| 1 | Melee | yes, a brawl |
| 2 | Collision | no |
| 3, 4, 5, 6 | undeclared | no |
| 7 | Fall | no |
| 8, 9 | undeclared | no |
| 10 | Bullet | yes, a shooting |
| 11 to 15 | undeclared | no |
| 16 | MeleeStealth | yes, a brawl |

Only the three the crime system knows about are prosecuted, and there is nothing
hiding in the gaps.

### On explosion

There is no explosion among KCD's hit reaction types. The word does appear in
the game's data, in `Scripts/Entities/Items/HitTypes.xml`, whose own comment
says it "is loaded as a non-native fallback" and which lists `ExplosiveGrenade`,
`Rocket`, `Tank125`, `MGBullet` and `PistolBullet`. Those are CryEngine and
Crysis assets shipped unused, alongside `VTOLExplosion` and `HumanTurret`
elsewhere. A build that sent an explosion damage type was reaching into that
registry rather than into KCD's combat system.

## Naming a crime directly does nothing

`pm:crimeReport` carries `sender`, `criminal`, `crime` as a string, and
`investigationInProgress`, and was the last candidate for charging a collision
as something other than a brawl. Sent as a typed table naming `murder` with the
player as criminal, and accepted by five NPCs, it produced no reaction of any
kind.

That fits what the trees do with it. In `sa_crimeDistrict.xml` the message is
routing: it resolves a destination and decides whether the report goes to a
soldier or a circator. It carries a crime the system already knows about to an
authority; it does not create one.

Worth recording separately: the type is `pm:crimeReport`, not `crimeReport`.
Types in `TypeDefinitions.xml` are namespaced by nesting, so the enclosing
`<Type>` supplies the prefix, and `Utils.makeTable` rejects an unqualified name
outright with "requires name of a existing MBT type". That rejection is the
validation the string form never offered, and it is a reason to prefer the
typed path even where both work.

### The crime question is closed

`combat:hit` with `hitType` of `Melee` is the only way to make a ridden
collision a crime, and the game will call it a brawl. That is the same
compromise vanilla makes in `sb_switch_hitreactions.xml`, which rewrites a
player-ridden collision into `Melee` for exactly this reason.

Severity is not ours to set. The label follows the hit type, the fine follows
the victim's social class, and murder arrives on its own when the victim dies.

## The engine's own hit reactions, and the API that is not there

`Libs/Tables/animation/hit_reaction.xml` holds 287 rows mapping an actor class,
a reaction type and a set of tags to a Mannequin fragment. The vocabulary is the
one this mod already computes:

```
so_forward+minor_hit   so_back+major_hit   death
sitting+so_left+minor_hit   lying+death   horse+so_forward+major_hit
```

Every row resolves to `HitDeath` or `HitDeathTorso`. Reaction types come from
`hit_reaction_type.xml`: `AnimatedMinor` 5 tagged `minor_hit`, `AnimatedMajor` 6
tagged `major_hit`, `AnimatedDeath` 7 tagged `death`, `AnimatedWeak` 8 tagged
`weak_hit`, alongside `Ragdollize` 0 and three physical types.

### The script bind is documented and absent

Warhorse's own `CScriptBindHitDeathReactions` documentation describes exactly
what this mod has always needed, including `StartReactionAnim`, which "pauses
the animation graph while playing it and resumes automatically when the
animation ends", and `OnHit`, which notifies the hit death reactions system.

Probed on a live NPC, none of `OnHit`, `StartReactionAnim`, `ExecuteHitReaction`,
`ExecuteDeathReaction`, `IsValidReaction`, `EndCurrentReaction`,
`EndReactionAnim` or `StartInteractiveAction` exists on the entity, the actor or
the human. The documentation describes a build that is not this one.

### What is reachable is the fragment itself

`HitDeath` sits in the vanilla database with the same structure as
`AnimationControlled`, which this mod already extends:

```xml
<HitDeath>
  <Fragment BlendOutDuration="0.2" Tags="horse" FragTags="so_forward+major_hit">
    <AnimLayer><Animation name="horserider_fall_right" /></AnimLayer>
    <ProcLayer>
      <Blend ExitTime="1.1" StartTime="0" Duration="0.2" />
      <Procedural type="Ragdoll">
        <Sleep value="1" /> <Stiffness value="500" />
```

### A correction to an earlier conclusion

The ragdoll settle layer was tried in the fall fragment and abandoned, on a
measurement showing it arriving two seconds after the victim had already stood
up. That attempt used `Sleep` 0 and `Stiffness` 100, recorded at the time as
"vanilla's own value".

Vanilla's own value, in the fragment that does exactly this handover, is
`Sleep` 1 and `Stiffness` 500, at `ExitTime` 1.1. Those are materially different
parameters, and the layer is doing in Mannequin what this mod now does from Lua
with a timer and `actor:Fall`.

Whether the earlier failure was the parameters or the ordering is untested.

## The fragment performs the ragdoll handover, and the timer goes

Tested at 4.3.1-dev.1. Each `hcm_fall_*` option carries a Ragdoll ProcLayer at
its own ExitTime, with `Sleep` 1 and `Stiffness` 500 taken from the `HitDeath`
option that drops a rider off a horse. Exit times are the measured clip lengths
at 0.68, per character set and direction, which is what the Lua timer used.

Fourteen impacts, every one `by=fragment`, and twelve recoveries all
`on=resolved`. No ceiling, no case where the layer failed to fire.

**User report**: "it's hard to tell the difference between what we had and what
it is now. I can see the ragdolls for sure and maybe on some of the animations
it looks a little weird, but some of them are completely smooth the entire way
through so it might just be a tuning issue."

Which is the expected outcome: the exit times are the same numbers the timer
used, so nothing about the timing changed. What changed is where they live.

### The earlier abandonment was a parameter, not the approach

The settle layer was tried before and dropped after the ragdoll was measured
arriving two seconds after the victim had already stood up. That attempt used
`Sleep` 0 and `Stiffness` 100, recorded at the time as vanilla's own value.
Vanilla's value in the fragment that performs this exact handover is `Sleep` 1
and `Stiffness` 500. `Sleep` decides whether the body settles or stays live.

### What it removes

Ninety lines: the handover branch, the per-gender clip length table, and the
fraction. Also the `actor:Fall` call for this tier, its timer, its generation
guard, and the movement control hand-back that had to happen immediately
before it.

The clip length table was the liability worth removing. It held figures this
project measured out of the running game across fifty-six reactions, correct
for four clips on one build, and silently wrong if a clip were ever swapped.
The fragment cannot drift that way, because the timing sits beside the clip it
belongs to.

What remains is the wait for the ragdoll to resolve, which the rebuild has to
follow: a victim can leave the ragdoll upright and still have no plan.

### After the removal

Five impacts on the trimmed build, with the ninety lines gone: four recoveries
`resolved` and one `neverRagdolled`, where `BlendRagdoll` was not observed inside
the ceiling and the rebuild ran anyway. No errors.

That case is not new and not caused by this. It appeared at two in forty-three
under the Lua handover, and the ceiling exists for it.

`VictimFall` no longer appears in the log, correctly: the mod does not perform
the handover any more, so it has nothing to report about it. `VictimRebuild`
still records how each recovery ended.

## A part file inside the mod's own pak loads

The mod's Lua was one file of 2,558 lines. The first section is out of it:
`HitReactionType` and `HitReactionStrength` now live in
`Scripts/HorseCollisionMod/Enums.lua`, which the entry point pulls in with
`Script.ReloadScript` at the foot of the file.

Thirty lines were moved rather than a whole subsystem, because the question
being answered was whether the mechanism works at all, and a failure here costs
one revert instead of a tangle.

### What the log shows

Two trot impacts on a save loaded from the deployed build:

```
Impact tier=Trot speed=6.95 sampled=6.92 armorImpulse=1.26 armorStamina=0.83
Impact tier=Trot speed=6.95 sampled=6.95 armorImpulse=0.38 armorStamina=2.16
ImpactCost rat_guard_pazdera tier=Trot state=MoveToIdle strength=5 ...
Reaction action=hcm_fall_forward gender=1 ok=true err=nil
CombatHit ok=true strength=5 err=nil
```

`strength=5` is `HitReactionStrength.MinorInjury` and the combat hit carries
`HitReactionType.Melee`. Both values were read out of the part file. No Lua
error appeared, and no field resolved to nil.

The victim reacted normally, which is the outcome that matters: nothing
player-facing changed, so an impact indistinguishable from 4.3.1 is the result.

### The failure this had to be able to catch

A part file that does not load raises no error of its own. The entry point
still loads, the methods it expected are nil, and the mod silently does less.
Eyeballing the game cannot tell that apart from a quiet build.

`verify_additive.py` now checks three things against the packaged pak: that
every Lua file in `src/HorseCollisionMod/` ships, that the entry point names
each one in a `Script.ReloadScript` call, and that no path it loads is missing.
The checks were confirmed by tampering with a copy of the release - stripping
the part out of the pak fails two of them, deleting the `ReloadScript` line
fails the third - because this tool has passed vacuously before.

### Load order, and why the parts sit outside Scripts/Startup

The engine enumerates `Scripts/Startup/` and executes what it finds. A part
file there would run in no guaranteed order, possibly before the table exists,
and then run a second time when the entry point named it. Only the entry point
is enumerated; everything else is named explicitly.

One consequence is worth carrying forward: a part file is looked up by path, so
it does not inherit the accidental protection that keeps enumerated Startup Lua
working in a pak built with backslash entry names.

## The armor part file, measured against horse stamina

`ArmorOf`, `DescribeArmor`, `ArmorCurve`, `ArmorImpulseScale` and
`ArmorStaminaScale` moved to `Scripts/HorseCollisionMod/Armor.lua`, 180 lines
out of the entry point, which is now 2,368 lines.

The block referenced no file-local of the entry point and every caller reaches
it through `self`, so no call site changed. The build needed no change either:
it walks `src/HorseCollisionMod/` rather than naming files.

### Two trot impacts, same horse, same starting stamina

| Victim | Armor read | `armorStamina` | Horse stamina |
|---|---|---|---|
| `rat_pickpocket_woman1` | 5.0 kg, 3 pieces, default cloth | 0.83 | 210.0 -> 195.1 |
| `rat_guard_pazdera` | 55.0 kg, 11 pieces, chain | 2.16 | 210.0 -> 171.1 |

Trot speeds were 6.97 and 6.96, and both started from a full 210.0, so the
stamina drawn is comparable directly: 14.9 against 38.9, a ratio of 2.61. The
multipliers stand in a ratio of 2.60.

The armor weight therefore reaches the horse's stamina cost intact through the
part file. No Lua error followed the reload.

### The stamina signal is the one that works

Throw distance would have measured nothing. `armorImpulse` is computed on every
impact and has one consumer, which at trot is a branch the shipped settings do
not take, so at trot the impulse multiplier is applied to nothing at all. That
is recorded in `ROADMAP.md` under Phase 2 and is unaffected by this slice.

Stamina has no such gap: `ArmorStaminaScale` feeds the drain on every impact at
trot and gallop, and the log carries both the multiplier and the resulting
figures.

### The reload path exercised the cascade

This slice was deployed into an already-running game rather than a fresh
launch. Reloading `Scripts/Startup/HorseCollisionMod.lua` alone re-executed
both part files through the `Script.ReloadScript` calls at the foot of it, and
the mod came back reporting `Load screen ended. v4.3.2 initializing physics
timer loop 4`. The development loop needs no knowledge of how many part files
there are.

## Logging, speed history and the tier, and two locals that had to change shape

`Log`, `LogRejection`, `TrackSpeed`, `RecentPeak`, `SpeedTrail`, `ImpactSpeed`
and `GetSpeedTier` moved to `Scripts/HorseCollisionMod/Log.lua`, 171 lines. The
entry point is 2,198 lines, down from 2,558 before the split began.

### A file-local cannot cross a part file boundary

`GetTimeMs` and `GetVectorLength` were declared `local function` in the entry
point and called from nine places spread across the file. A `local` is visible
only inside the chunk that declares it, and each part file is a separate chunk,
so moving them as locals would have left every later slice calling a global
that resolves to nil.

They are now `HorseCollisionMod:TimeMs` and `HorseCollisionMod:VectorLength`.
Every call site is inside a method and reaches them through `self`, including
three inside nested closures, where `self` is captured as an upvalue.

This is why the slice is placed third rather than later. The constraint applies
to any file-local shared across the seams, and finding it while the rest of the
mod is still in one file made it one edit instead of several.

### One trot impact after the reload

```
Impact tier=Trot speed=6.93 sampled=6.92 armorImpulse=1.26 armorStamina=0.83
ImpactCost rat_pickpocket_woman1 tier=Trot strength=5 weight=5.0
Reaction action=hcm_fall_forward gender=2 ok=true err=nil
Horse stamina 210.0 -> 195.1
VictimRebuild action=hcm_fall_forward on=resolved waited=9184ms
```

That single line exercises the whole moved block: `VectorLength` on the horse's
velocity, `TrackSpeed` and `ImpactSpeed` against the history, `GetSpeedTier` to
choose the tier, and `Log` to report it. The recovery completed and no field
resolved to nil.

### The deployed pak is not what the loose files are

Worth knowing before any shipping test. The engine enumerates
`Scripts/Startup/` from every source it has, so the loose script and the copy
inside `Mods\HorseCollisionMod_dev\Data\HorseCollisionMod.pak` are both
executed, and each registers its own load-screen listener. Three banners
appeared on one load screen, at three different versions, because a hot reload
registers another listener without removing the previous one.

At `sys_PakPriority = 0` the loose files win the path lookup, so the part files
resolve to the current ones and the measurements above are of the current code.
The deployed pak, however, is whatever the last full deploy built - here
v4.3.1, which predates the split and contains no part files at all. A shipping
test run against a stale pak would exercise the monolithic build and report
nothing wrong.

## Footprint detection and impact direction, across eight impacts

`IsInHorseFootprint`, `FootprintDetail` and `GetImpactDir` moved to
`Scripts/HorseCollisionMod/Detection.lua`, 144 lines. The entry point is 2,055
lines, down from 2,558 before the split began. The block used no file-local of
the entry point, so nothing changed shape.

### What the ride covered

Eight impacts after the reload, without a single Lua error:

| Tier | Victims | Directions chosen |
|---|---|---|
| Trot | 7 | `hcm_fall_forward`, `hcm_fall_back`, `hcm_fall_left` |
| Gallop | 1 | ragdoll path, `Impulse scale=1.26 magnitude=73.7` |

Every reaction returned `ok=true err=nil`, every recovery that ran to
completion reported `on=resolved`, and armor was read across the whole range
present in the world: 2.0 kg of cloth on `rat_karolina` through 55.0 kg of
chain on `rat_guard_pazdera`.

### Direction is the signal that matters here

A footprint test that failed outright would produce no impacts at all, which is
easy to see. The failure worth catching is a subtler one: a direction lookup
returning a single constant would still produce reactions, and every victim
would fall the same way.

Three distinct directions appeared across the eight, chosen against the horse's
approach rather than fixed, which is what rules that out. `GetImpactDir`
resolves the cross product through `VectorLength`, now a method in `Log.lua`,
so this also exercises the previous slice's change from a second part file.

### The footprint sweep widens with speed

Visible in the limits printed on each test: `limits=1.40/0.35/2.35` at impact
speed and `1.11/0.35/2.35` through the slower recovery polls. The forward
limit tracks the sweep term while the lateral and vertical limits stay fixed,
which is the intended shape and is unchanged by the move.

## Health probing, with the full sample series intact

`WatchHealth`, `SuppressAutoCure`, `ProbeImpactCost` and `ImpactProbeSamples`
moved to `Scripts/HorseCollisionMod/Health.lua`, 368 lines. The entry point is
1,688 lines, down from 2,558 before the split began.

`SuppressAutoCure` is filed with the probe rather than the reaction because its
purpose is protecting the measurement: vanilla's daycycle would restore health
before the later samples are taken.

### Two trot impacts, four samples each

`villageGuard`, 59.0 kg of chain, `armorStamina=2.22`:

```
ImpactCost t+500ms   from=96.3775 health=93.6406 delta=-2.7369
ImpactCost t+3000ms  from=96.3775 health=93.6406 delta=-2.7369
ImpactCost t+6000ms  from=96.3775 health=93.6406 delta=-2.7369
ImpactCost t+10000ms from=96.3775 health=93.6406 delta=-2.7369
```

`rat_refugee_tonda_rumpal`, 6.0 kg of cloth:

```
ImpactCost t+500ms   delta=-4.3907
ImpactCost t+3000ms  delta=-6.0535
ImpactCost t+6000ms  delta=-6.0535
ImpactCost t+10000ms delta=-6.0535
```

All four scheduled samples fired on both, `SuppressAutoCure` reported
`for=30s set=true` on both, and no field resolved to nil. The second victim
shows the case the 3000 ms sample exists for: a further 1.67 of health left
after the first reading and before the second, which a single sample at 500 ms
would have missed entirely.

### The crime response is back on

The guard got up and attempted an arrest. `CollisionIsCrime` was left `false`
at the console during 4.3.1 animation testing; a save reload has restored the
shipped default, so crime responses are being exercised again alongside this.

### One neverRagdolled, which is not new

`VictimRebuild action=hcm_fall_left on=neverRagdolled waited=15072ms`, meaning
`BlendRagdoll` was not observed inside the ceiling and the rebuild ran anyway.
That case predates the split and the ceiling exists for it. The victim
recovered.

## The three reaction paths, separated by tier

`SendHitReaction`, `PlayReaction`, `Ragdoll` and `ImpulseVictim` moved to
`Scripts/HorseCollisionMod/Reaction.lua`, 235 lines. The entry point is 1,452
lines, down from 2,558 before the split began.

These were two non-contiguous regions in the old file, `SendHitReaction` above
the recovery code and the other three below it. They are one concern, being the
three ways a collision reaches the victim's body, and the file now reads in
ascending force: brain message, animation, physics.

### The two tiers wrote different lines

| Tier | Victim | What the log recorded | Damage |
|---|---|---|---|
| Trot | `rat_pickpocket_woman1`, 5.0 kg cloth | `Reaction action=hcm_fall_forward ok=true`, then `MovementControl released ok=true` | -6.03 |
| Gallop | `rat_guard24`, 46.0 kg chain | no `Reaction` line at all; `Impulse scale=0.42 magnitude=24.3` | -26.63 |

That difference is the result worth recording. A part file that loaded but
resolved to something wrong could still produce a reaction of some kind, and
one tier alone would not distinguish the animation path from the physics path.
Two tiers writing two different signatures does.

The trot recovery reported `on=resolved` and all four impact-cost samples fired
on both victims. No field resolved to nil.

### The gallop impulse carries the armor multiplier

`armorImpulse=0.42` on the guard reached physics as `Impulse scale=0.42`, so
the multiplier is applied on this path. Whether it changes anything a player
can see is the separate question recorded in `ROADMAP.md` under Phase 2, and is
untouched by this slice.

## Victim recovery, watched without the crime response

`ReleaseVictimMovement`, `WhenRagdollResolves`, `FinishRecovery`,
`ReplanVictim`, `WhenReactionEnds` and `RebuildVictim` moved to
`Scripts/HorseCollisionMod/Recovery.lua`, 287 lines. The entry point is 1,166
lines, under half the 2,558 it started at.

`CollisionIsCrime` was set `false` at the console for this test and restored to
`true` afterwards. A guard response makes a recovery impossible to watch: the
victim is reacting to the crime rather than recovering, and the player is being
arrested rather than observing.

### Four trot impacts

Every one resolved:

| Victim | Reaction | Rebuild | Replan |
|---|---|---|---|
| `rat_armorers_wife` | `hcm_fall_forward` | `on=resolved waited=9360ms` | `typed=true` |
| `rat_konyas_wife` | `hcm_fall_back` | `on=resolved waited=7824ms` | `typed=true` |
| `rat_woman44` | `hcm_fall_forward` | `on=resolved waited=8928ms` | `typed=true` |
| `rat_guard_pazdera` | `hcm_fall_back` | `on=resolved waited=5408ms` | `typed=true` |

No `CombatHit` line appears on any of them, which confirms the crime setting
took effect rather than being sent and ignored. No Lua error, and no field
resolved to nil.

### What the replan looks like from the saddle

Observed for the first time, because it has always been hidden until now:

> "they get up normally, start to return, pause for a sec natural looking, and
> then seem to change direction and resume"

That is the two-stage recovery working as designed. `RebuildVictim` puts the
victim on their feet and they move under whatever plan they still hold.
`ReplanAfterRebuildMs` later, 600 ms, `ReplanVictim` sends
`daycycle:restartRequest` with `reason(interrupt), speed(instant)`, which
restarts the schedule at once and sends them where the schedule wants them
rather than where they had started walking.

That is what the code does. It does not explain why it is being seen now.

The mechanism is old: the typed payload landed in 4.2.1 and `VictimReplan
typed=true` appears on every impact recorded since. The player reports having
watched thousands of impacts and never seen a victim pause and change
direction after standing up.

An explanation was offered here and is wrong, so it is recorded as wrong rather
than deleted: that the crime response had always masked it. `CollisionIsCrime`
was added in 4.3.0, one day before this entry. Every version before that ran
with no crime system at all, which is the same condition this test created, so
there was a long stretch in which the behavior would have been just as visible
as it is now.

So the observation stands unexplained. What is established is only that the
replan fires, that it fired on all four impacts, and that the recovery
completes. Why its effect appears newly visible is not answered, and the
candidates worth separating are whether anything about the send changed since
4.2.1, whether the 600 ms gap is being reached differently now that the fall
hands off through the fragment rather than a timer, and whether this is an
observation that has simply not been looked for before.

It is not breaking, and it is not from the split: the recovery code moved
verbatim and the same lines appear in the impacts recorded before it moved.

## The crime hit, from its own part file

`SendCombatHit` moved to `Scripts/HorseCollisionMod/Crime.lua`, 86 lines. The
entry point is 1,081 lines, down from 2,558 before the split began.

One method rather than a subsystem, but its own concern: it is the only place
the mod tells the game to charge the player, and the only consumer of
`CollisionIsCrime`. `IsCombatCollision` stays in the entry point despite the
name, because it decides how hard an impact is rather than whether it is an
offence, and it is read by the rider and stamina code.

One trot impact with a witness present, `CollisionIsCrime` restored to `true`:

```
Impact tier=Trot speed=6.92 armorImpulse=1.26 armorStamina=0.83
Reaction action=hcm_fall_right gender=2 ok=true err=nil
CombatHit ok=true strength=5 err=nil
VictimRebuild action=hcm_fall_right on=resolved waited=8480ms
```

A guard pursued the player. The strength sent is 5, the same
`HitReactionStrength.MinorInjury` the trot tier chose, so the value crossed
two part-file boundaries to get there: read from `Enums.lua`, chosen in the
entry point, sent from `Crime.lua`.

The witness matters to the test. `SendCombatHit` returning `ok=true` only
proves the message was accepted, not that the crime system did anything with
it, and an impact with nobody watching would have logged the same line either
way.

## The stamina budget and the throw, drained to empty

`IsCombatCollision`, `ThrowRider` and `DrainHorseStamina` moved to
`Scripts/HorseCollisionMod/Rider.lua`, 141 lines. The entry point is 941 lines,
under a thousand for the first time, from 2,558 before the split began.

`IsCombatCollision` is filed here rather than with `Crime.lua` despite the
name. It decides how hard an impact counts, not whether it is an offence, and
the stamina multiplier is its only consumer.

### Five gallop impacts without stopping

| # | `armorStamina` | Horse stamina | Cost |
|---|---|---|---|
| 1 | 0.83 | 180.4 -> 162.2 | 18.2 |
| 2 | 0.83 | 153.7 -> 135.5 | 18.2 |
| 3 | 0.83 | 119.0 -> 100.7 | 18.3 |
| 4 | 2.22 | 70.7 -> 21.8 | 48.9 |
| 5 | 1.67 | 0.0 -> 0.0 | already empty |

`ThrowRider via horse.horse ok=true` followed, and the player was dismounted.

The fourth impact is the useful one. An armored victim cost 48.9 against 18.2
for the unarmored, a ratio of 2.69, where the multipliers stand at 2.67. The
armor weight is read in `Armor.lua`, turned into a multiplier there, and spent
in `Rider.lua`, so this measures a value crossing a part file boundary rather
than either file alone.

Stamina also falls between impacts, which is the gallop itself costing the
horse and is vanilla behavior, not the mod's drain.

### What this ride did not cover

`combatScale` read 1.0 on all five, so only the non-combat branch of
`IsCombatCollision` was exercised. The combat multiplier path is untested by
this slice and would need an impact taken during a fight.

## The detection loop, and the split finished

`TriggerCollision`, `SafeUpdate` and `UpdateTimer` moved to
`Scripts/HorseCollisionMod/Update.lua`, 373 lines. The entry point is 569
lines, from 2,558 when the split began.

Moved last on purpose. It calls into every other part, so a fault here would
have been indistinguishable from a fault in whichever part it called, and all
nine of those had already been proven in the running game.

### Fourteen impacts across all three tiers

| Tier | Count | Reaction | `CombatHit` | Horse stamina |
|---|---|---|---|---|
| Walk | 3 | `hcm_stagger_left`, `_right`, `_forward` | none | none |
| Trot | 5 | `hcm_fall_forward`, `_back`, `_right` | `strength=5` | 15 to 88 |
| Gallop | 6 | `Impulse` magnitude 24.3 to 73.8 | `strength=6` | 37 to 80 |

Every reaction returned `ok=true err=nil`. No Lua error and no
`CRITICAL ERROR IN UPDATE TIMER` line appeared.

The walk tier is the result worth having. It had not been ridden once since the
split began, and it is the only tier whose correctness is partly an absence:
no crime is raised and no stamina is drawn, which is the shipped design and
would have been invisible in a test that only counted reactions.

### The combat multiplier, left untested by the previous slice

`combatScale=2.2` appears on nine of the fourteen, so the combat branch of
`IsCombatCollision` ran. The rider slice recorded that gap and this ride closes
it: one trot impact drew 88.1 stamina at 2.2 combat and 2.22 armor, against
14.9 for the same tier unarmored and out of combat.

### The layout as it now stands

| File | Lines | What it holds |
|---|---|---|
| `HorseCollisionMod.lua` | 569 | the table, `Config`, state, timing, `ApplySettings`, the redirect, the bootstrap |
| `Update.lua` | 400 | the detection loop and dispatching one collision |
| `Health.lua` | 383 | what an impact cost, and the auto-cure suppression |
| `Recovery.lua` | 312 | the waits, the rebuild and the replan |
| `Reaction.lua` | 255 | brain message, reaction clip, physics ragdoll |
| `Log.lua` | 199 | logging, clock, vector length, speed history and tier |
| `Armor.lua` | 196 | what a victim wears, and both curves |
| `Rider.lua` | 160 | horse stamina, combat multiplier, dismount |
| `Detection.lua` | 159 | footprint test and impact direction |
| `Crime.lua` | 106 | the combat hit that makes it an offence |
| `Enums.lua` | 41 | the two engine enums |

One `neverRagdolled` appeared at 15008 ms. That case predates the split, the
ceiling exists for it, and the victim recovered.

## 4.4.0 tested as a player installs it

The zip installed through Vortex into a shipping-configured game, launched
without `-devmode`, with `sys_PakPriority = 2`,
`mn_allowEditableDatabasesInPureGame = 0`, and every loose file parked. All
three tiers behaved.

This is the test the whole split was gated on. The development loop runs on
loose files, which the engine finds by enumeration and by a priority that
favors them; a pak resolves the ten part files by exact path instead, and that
lookup is the one thing loose-file testing cannot exercise. A wrong path there
fails silently: the entry point loads, its `Script.ReloadScript` calls find
nothing, every method the parts define stays nil, and the mod does nothing
while logging no error.

`Script.ReloadScript` therefore works in a shipping build, which was the open
risk when the split was planned, and the answer is no longer inferred from
vanilla using the call at load time.

### What the parked set has to include

The shipping test is only valid if nothing loose remains. Two files were nearly
missed.

The ten part files were added to the parking list in the same branch that
created the first one, so they parked correctly. `HorseCollisionMod_ItemData.lua`
was not on the list at all and was found by checking the game folder rather
than by trusting the tool. Left in place it would have overridden the pak's
copy of the armor weight table, and the armor readings in a shipping test would
have come from a loose file.

The general shape: a parking list written by hand goes stale the moment the
shipped file set changes, and the failure is silent in the direction that
matters, because a stale loose file makes the test pass rather than fail.

## The live item table lookup exists, and is reachable only by SHA

Recorded because it was found once, built once, verified once, and then lost.

An earlier entry in this diary concludes that `ItemManager` reports an item's
class and no weight, and that "there is no live weight lookup, and the join
through the shipped table is not a shortcut but the only route". The first half
is correct and the conclusion is not. `ItemManager` is not the route. The
`Database` bind is.

### What it does

`Database` exposes the tables the game ships, read through
`Database.GetTableColumnData(table, column)`:

| Table | Columns used | For |
|---|---|---|
| `pickable_item` | `item_id`, `weight` | every item's weight |
| `armor` | `item_id`, `smash_def`, `armor_type_id` | the subset that is armor |

The class an item reports through `ItemManager.GetItem` joins straight to
`pickable_item.item_id`. Membership of `armor` is what makes a carried item
count as worn, which is the same filter the shipped table provided by
containing only armor classes.

It degrades rather than failing: when `Database` is unavailable the log says so
and every target reads as unarmored.

### What it was measured at

Confirmed against a live inventory, 18 items matched and none missed, and the
index built 796 armor pieces in game. Removing the generator, its build step
and the shipped file took the download from 56,470 to 37,573 bytes.

### Why it is not in the mod

It was committed as `093ae77`, and `main` was later hard reset to 4.0.0. The
commit is not an ancestor of `main` and is on no branch, so it is reachable
only by that SHA and only until the object is pruned.

The file it was written against was the 2,558-line single script, which no
longer exists, so the commit is a specification rather than a patch to apply.

## The shipped armor table is gone, and the weights did not move

`ItemIndex` in `Armor.lua` builds the class-to-weight join from `Database` at
runtime, replacing the 50 KB table that was generated from the game's paks at
build time and shipped with the mod.

Rebuilt onto the part file rather than cherry-picked from `093ae77`, which was
written against the single-file mod that no longer exists. The new code is in
`Armor.lua`, which owns armor; nothing was added to the entry point.

### It builds

```
ItemIndex built ok=true armorPieces=796 err=nil
```

796 is the same count the orphaned implementation measured, so the join reaches
the same set of rows.

### The weights are unchanged, on the same NPCs

Six impacts across walk, trot and gallop. Three of the victims had been ridden
down earlier the same day, with the shipped table still in place:

| Victim | With the shipped table | From `Database` |
|---|---|---|
| `rat_pickpocket_woman1` | `pieces=3 weight=5.0 smashDef=0.30 heaviest=default cloth` | identical |
| `rat_karolina` | `pieces=1 weight=2.0 smashDef=0.10 heaviest=default cloth` | identical |
| `rat_woman12` | `armorImpulse=1.26 armorStamina=0.83` | identical |

`rat_guard23` read `pieces=8 weight=31.0 smashDef=3.22`, giving
`armorStamina=1.72`, so the armored path scales as before. No Lua error and no
`Database is unavailable` line.

Matching a named victim's figures before and after is the measurement worth
having. A count of 796 proves the tables were read; identical output on the
same NPC proves the join is the same one.

### What it costs

The built zip falls from 71,925 to 52,561 bytes, 27 percent. Removed with it:
`build_item_weights.py`, its build step, the shipped Startup script, its entry
in the dev console's reload chain, and its line in the README layout.

### Why the table existed

An earlier entry concluded there was no live weight lookup, on the evidence
that `ItemManager` reports a class and no weight. That evidence is correct and
the conclusion did not follow: `ItemManager` is not the only bind that reads
the game's tables. `Database` is, and it was never asked.

## The replan does not turn the victim

A victim was reported standing up, starting to move, pausing, then setting off
in a different direction. `ReplanVictim` sends `daycycle:restartRequest` with
`reason(interrupt)` 600 ms after the rebuild, which fits that description
exactly, and `Config.ReplanAfterReaction` switches it off. So it was measured
rather than argued.

### Heading, measured either side of the replan window

`WatchHeading` in `Recovery.lua` samples the victim's direction vector as the
rebuild finishes and again 2,000 ms later, and logs the angle between them.
Reporting by eye had produced "I think I saw it before but now it's gone?",
which is not a measurement, and the numbers show why: the effect is
intermittent, so a handful of impacts watched by eye can support either answer.

| Turn | Replan on | Replan off |
| --- | --- | --- |
| | 11 | 9 |
| | 4 | 83 |
| | 78 | 102 |
| | 143 | 0 |
| | 29 | 74 |
| Mean | 53 | 54 |
| Over 70 degrees | 2 of 5 | 3 of 5 |

No `VictimReplan` line appears in the second set, so the switch took effect
rather than being set and ignored.

**The replan is not the cause.** Victims turn just as far without it, and the
turning is the game's own behavior tree choosing a destination for an NPC whose
activity was interrupted.

### Two other explanations ruled out the same way

The same session cleared two more of the mod's own actions, each by switching
it off rather than by reading the source:

- **`SendHitReaction`**, the native brain message, was suspected of causing a
  victim and then several bystanders to flee. The same innkeeper was ridden
  down with the message off and on: `travel=0.00` both times, no flight either
  way.
- **The flight itself** was seen once, on `rat_pickpocket_woman1`, and did not
  reproduce across the seven impacts that followed under identical settings. No
  cause is established and none is proposed.

### The bark does not come from the mod

Observed while `SendHitReaction` was off: the vanilla collision bark fired
anyway. The comment on that function claims the message is what makes the bark,
perception and crime handling fire. The bark half of that claim is wrong, and
the module header's own description of vanilla behavior already said so, since
it records that riding into an NPC in vanilla produces an audio bark and
nothing else.

### One observation worth a second look later

With the replan off, `rat_refugee_tonka` recorded `turned=0deg moved=0.00m`, a
beggar who did not move at all in two seconds. That is the case the replan was
added for in 4.2.1, where a beggar, an innkeeper and a merchant were left
standing. One sample, and not pursued here.

## The replan fires at whoever needs it, and nobody else

A victim was reported standing up, beginning to resume, and then snapping into
something else about half a second later, dropping a carried bucket or changing
direction in a single frame.

### What it was

`ReplanVictim`, sent to every trot victim 600 ms after the rebuild. It restarts
the victim's daycycle, which tears down the activity they are in; a prop held
by that activity goes with it, which is the bucket.

Two earlier answers about it were wrong and are recorded as wrong. The first
blamed the crime response for masking it, which the release dates disprove. The
second cleared the replan outright on a measurement of heading angle, which was
the wrong quantity: an NPC who ragdolls, stands up facing anywhere and walks off
scores a large angle with no snap at all, which is why gallop, a tier that never
replans, produced the largest angles in the set.

### Why it is still needed

Switching it off fixed the snap and stranded two kinds of victim:

| Victim | Without the replan |
| --- | --- |
| Woman carrying a bucket | recovers, keeps the bucket |
| Merchant | recovers |
| Beggar | stands where they got up |
| Innkeeper | stands where they got up |

A beggar and an innkeeper are bound to a smart object they cannot re-approach
on their own. The replan is the only thing that returns them to it. It was
added in 4.2.1 for exactly those cases, and 4.3.1 handing the fall to the
engine did not make it unnecessary, only unnecessary for everyone else.

### The signal that separates them

The victim's animation state, read once the rebuild lands:

```
Stranded rat_refugee_vojcek  was=BeggarVAR      now=MotionIdle      resumed=false
Stranded rat_innkeeper1      was=Leaning        now=MotionIdle      resumed=false
Stranded rat_woman24         was=MotionMovement now=MotionMovement  resumed=true
Stranded rat_merchant_shop3  was=MotionMovement now=MotionMovement  resumed=true
```

A stranded victim sits in `MotionIdle`. A recovered one is already in
`MotionMovement`, `IdleToMove` or a turn. Across sixteen recoveries this held
without exception. A victim whose own activity is standing still is covered by
the state matching what they were hit in.

### The reading is taken immediately

Three intermediate versions each cost time that turned out to be unnecessary,
and the last of them was removed on the player's argument rather than on a
measurement:

| Version | Delay before a stranded victim is helped |
| --- | --- |
| Fire at everyone | 600 ms, and wrong |
| Fixed check after the rebuild | 1,800 ms |
| Poll to a ceiling | up to 1,200 ms |
| Read the state once, immediately | none |

Waiting was only ever the cost of a weaker signal. Distance moved was carried
alongside the state for one version and was redundant the moment the state rule
existed: every case it caught, the state caught first, and it misjudged a
merchant who resumed by turning on the spot.

### Also corrected

The replan sent `daycycleHaltSpeed.instant`. Vanilla uses that value only for
teleports and cutscenes, where a transition with no wind-down is the point. It
is `fast` now. This was not the fault, and changing it alone fixed nothing.

## The long lie-down after a trot fall is the engine's, and women get twice it

The reported symptom: the fall animation plays well, the ragdoll takes the
body, and then the victim lies there too long before standing. Most noticeable
on women; guards look close to seamless.

### Where a recovery spends its time

`TraceRecovery` times every animation state a victim passes through and logs
the sequence, because a single duration covering the whole recovery cannot say
which phase is long. Three phases, measured across ten trot impacts:

| Phase | Male | Female | Controlled by |
|---|---|---|---|
| Limp for the rest of the fall clip | ~550 ms | ~650 ms | `FALL_SETTLE_AT` |
| A gap in `MotionIdle` | ~1000 ms | ~900 ms | unexplained |
| `BlendRagdoll` | 2570 ms | 5100 ms | the engine |

`BlendRagdoll` is not the ragdoll. Physics takes the body at the fragment's
`ExitTime`, inside the `AnimationControlled` window; `BlendRagdoll` is the
engine blending the body back to animation afterwards, which is the get-up.
An earlier reading of this trace had that backwards.

### It is vanilla, proven on a path with none of the mod's data in it

Female `BlendRagdoll` is 5100 ms against male 2570 ms, a ratio of 1.98 with
almost no variance in either group. A clean factor of two is not physics
settling.

The gallop tier hands the body over with `actor:Fall` and touches no fragment
of this mod's, no `ExitTime`, no `Sleep` and no `Stiffness`. Traced there:

| Victim | `BlendRagdoll` |
|---|---|
| `rat_woman43` | 4832 ms |
| `rat_woman34` | 5056 ms |
| `rat_woman12` | 5040 ms |
| `rat_man97` | 2496 ms |
| `rat_refugee_tonda_rumpal` | 2864 ms |

The same split, within noise of the fall path. **Female actors take twice as
long to stand up from a ragdoll in this game, whatever knocked them down.** No
parameter this mod controls changes it, and that rules out `Stiffness` without
testing it, since the gallop path never reads it.

### What was tried and did nothing

| Change | Effect on `BlendRagdoll` |
|---|---|
| Female handover 0.68 to 0.50 of clip | -30 ms |
| `Sleep` 1 to 0 | -29 ms female, -127 ms male |
| `g_ragdollPollTime` 0.5 to 0.05 | none |
| `ca_DeathBlendTime` | already 0 |

`ExitTime` is honored: forced to 0.30 for every direction, victims collapse a
third of a second into the fall. It decides when the body goes limp and not how
long it then stays down.

### What is left, and is ours

The `MotionIdle` gap. Roughly a second between the fall clip ending and the
engine beginning the get-up, in which nothing is happening and nothing has been
asked for. That, and the limp remainder of the clip, are the only parts of the
sequence this mod can shorten.

The one change kept from all of this is the female handover at 0.50, which the
player reports makes the falls themselves look better.

## Stiffness does not move the lie-down either, and the parameters are exhausted

`Stiffness` was the last ragdoll parameter untested against the phase a victim
spends limp on the ground. It does not move it.

| `Stiffness` | Mean gap | Range | n |
|---|---|---|---|
| 500 | 902 ms | 112 to 1408 | 10 |
| 100 | 757 ms | 400 to 1120 | 9 |

The means differ by less than the spread of either set, so this is noise rather
than a saving. `Stiffness` is back at vanilla's 500, since nothing justifies
deviating from it.

It does not govern how fast a victim rises either: `BlendRagdoll` measured
2560, 2688, 2512 and 2528 ms for men at `Stiffness` 100, against 2570 ms at
500.

### What the phases actually are

Corrected from the previous entry, which had `MotionIdle` down as dead air.
Traced on the gallop path, where the body is thrown and visibly tumbles:

```
rat_woman43  MotionIdle=1888ms BlendRagdoll=4832ms
rat_man97    MotionIdle=2272ms BlendRagdoll=2496ms
rat_guard18  MotionIdle=2496ms BlendRagdoll=2672ms
```

`MotionIdle` is the ragdoll being a ragdoll, and it is longer at gallop because
the body travels further before coming to rest. `BlendRagdoll` is only the
stand-up blend at the end.

### Every dial, and what it does

| Dial | The limp phase | The stand-up |
|---|---|---|
| `ExitTime` | moves when it begins | nothing |
| `Sleep` 1 to 0 | nothing | nothing |
| `Stiffness` 500 to 100 | noise | nothing |
| `g_ragdollPollTime` 0.5 to 0.05 | nothing | nothing |
| `ca_DeathBlendTime` | already 0 | already 0 |

`ExitTime` is the only one that does anything, and what it does is decide when
the body goes limp rather than how long it stays down.

The remaining time belongs to the engine. A trot victim is limp for roughly a
second and then takes 2,570 ms to rise if male and 5,100 ms if female, and the
gallop path reaches the same figures without touching any data this mod ships.

## The limp period is fixed, measured from the handover, and is the engine's

Corrects the framing in the two entries above, both of which timed this from
the wrong point.

Measured from when physics takes the body rather than from when the clip ends,
across eighteen trot impacts: **1,457 ms on average, and the same for both
character sets.** Female victims are indistinguishable from male here. What
differs by gender is only `BlendRagdoll`, the stand-up animation itself, which
runs twice as long for women.

Timed from the end of the clip instead it appears as a variable gap of nought
to 1.4 seconds, and that variability is an artifact: it is whatever part of the
fixed period falls after the animation stops.

### The gap in the trace is not the gap a player sees

A victim whose clip was still nominally playing showed no `MotionIdle` between
`AnimationControlled` and `BlendRagdoll`, which was written up here as the clip
covering the limp period, and a per-direction handover table was derived to
reproduce it.

That was wrong, for a reason this diary already recorded. Once the ragdoll
fires the animation no longer drives the body, so a clip still nominally
playing is not visible and covers nothing. The player sees a limp body from the
handover onward in every case. `ExitTime` moves when that begins and never how
long it lasts, which two earlier experiments had already established.

### Everything the profile trace rules out

`GetPhysicalizationProfile` reads `alive` for the whole recovery: during the
fall clip, during the limp period, and during the stand-up. The actor is never
in the `ragdoll` or `sleep` profile, so `SetPhysicalizationProfile("alive")`
and `actor:StandUp` have nothing to act on. The ragdoll here is a Mannequin
ProcLayer effect rather than a physicalization switch.

The other candidate was the interactive action this mod starts and never ends.
No stop bind for one exists on the actor: the surface has
`StartInteractiveActionByName` and nothing to match it, and `OnEndInteractive`
is a callback on `human` rather than a call.

### Where that leaves it

A trot victim is limp for a fixed 1,457 ms from the handover, then takes 2,570
ms to rise if male and 5,100 ms if female. Neither figure responds to
`ExitTime`, `Sleep`, `Stiffness`, `g_ragdollPollTime` or `ca_DeathBlendTime`,
and the gallop tier reaches both through `actor:Fall` without touching any data
this mod ships.

## What drives the wait before a victim stands, and why it cannot be reached

The wait is a terminator on the `BlendRagdoll` fragment's `blendIn` option: an
empty Procedural at an ExitTime, which replaces the Ragdoll procedural and ends
the hold.

```
<Blend ExitTime="2" StartTime="0" Duration="0" />
<Procedural type="" />
```

`kcd_male_database.adb` carries one at 2 seconds across its 10 options.
`wh_female_database.adb`, with 5 options, carries none at all. That is the
whole of the gender difference: a man's hold is told to stop and a woman's is
not, which is why `BlendRagdoll` measures 2,570 ms against 5,100 ms.

### The override was built and is not read

`build_adb.py` was extended to take authority over `BlendRagdoll` the same way
it does over `AnimationControlled`, carrying all 10 male and all 5 female
vanilla options with no clip lost, rewriting the male terminator and adding one
to the female option. The generated file deployed correctly and contained the
new value.

It changes nothing. At a hold of 0.5 seconds the figures were unmoved, and at a
deliberately absurd 8 seconds they were unmoved again, which rules out a clamp
and shows the fragment is never consulted.

`BlendRagdoll` resolves through `ActionController`, and this mod redirects only
`AnimDatabase3P`. That is deliberate and recorded in `TECHNICAL_DETAILS.md`:
redirecting `ActionController` requires copies of the controller def and the
fragment id file, which puts the mod in the resolution path of every human
animation rather than one fragment, and broke unrelated animations when it was
tried. `verify_additive.py` asserts against it.

### Where that leaves the wait

Identified, understood, and gated behind a change the project has already
rejected on stronger grounds than this symptom. Everything reachable was
measured and moves it by nothing: `ExitTime` on the mod's own fall fragment,
`Sleep`, `Stiffness`, `g_ragdollPollTime`, `ca_DeathBlendTime`, and the
physicalization profile, which reads `alive` throughout and so leaves
`actor:StandUp` and `SetPhysicalizationProfile` with nothing to act on.

## `unragdoll` is a real profile, and is not the way out of the wait

Read out of the game binary's string dispatch for
`SetPhysicalizationProfile`, which accepts six values rather than the two this
project knew about:

| String | Profile |
|---|---|
| `alive` | 1 |
| `unragdoll` | 0 |
| `ragdoll` | 2 |
| `sleep` | 3 |
| `frozen` | 4 |
| `spectator` | 6 |

No vanilla script uses `unragdoll` and no modding documentation names it.

### What it does

Called two seconds into a fall reaction, it takes effect on every victim:
`was=alive now=unragdoll ok=true`. What follows differs by gender, and neither
outcome is the one wanted.

| | Result |
|---|---|
| Men | no change. `BlendRagdoll` still runs 2,592 ms and the wait is untouched. |
| Women | the get-up is skipped entirely. No `BlendRagdoll` at all, straight from the fall to `MotionMovement`, which reads in game as shooting upright. |

It cancels the recovery rather than shortening the wait before it.

### It strands the actor

Nothing returns an actor to `alive`. One victim recorded
`MotionIdle/unragdoll=9952ms` and two others alternated `MotionIdle` and
`MotionMovement` while still in the profile, which is an animation state
machine running while the body is not driven by it. In game that is an NPC
walking on the spot.

`tools/restore_alive.lua` repairs it, and four actors were returned to `alive`
with it. That is the reason the tool exists and the reason the experiment is
not kept: a setting that permanently breaks an NPC is not worth shipping
switched off.

### The ragdoll CVars were never candidates

The engine registers its own help text for them, which the decompilation index
now carries:

| CVar | What the engine says it does |
|---|---|
| `g_ragdollMinTime` | minimum time in seconds that a ragdoll will be visible |
| `g_ragdollPollTime` | time in seconds where 'unseen' polling is done |
| `g_ragdollUnseenTime` | time the player has to look away before it disappears |
| `g_ragdollDistance` | distance the player has to be away before it disappears |

All four govern corpses being removed. None of them gates a recovery, and the
rides spent testing two of them were spent on a reading of their names.

`g_hitDeathReactions_disableRagdoll`, "disables switching to ragdoll at the end
of animations", is the only one in that family that touches this behavior at
all, and it has not been tried.

## The polearm get-up is the game's, not the reaction's

A guard carrying a halberd was reported turning roughly a hundred and eighty
degrees near the end of his get-up and then swinging back, where other victims
do not.

### The weapon, named

`ItemManager.GetItem(wuid).class` returns a GUID rather than a readable name,
which is why an attempt to match class names against "halberd" or "spear"
matched nothing. `ItemManager.GetItemUIName(class)` resolves it:
`ui_nm_halberd`. The same GUID joins to `pickable_item.item_id` in the
`Database` tables, which is the route `Armor.lua` already uses.

`human:GetItemInHand(hand)` returns nothing unless the weapon is drawn, so an
NPC carrying a halberd sheathed reports an empty hand.

### The correlation, measured

Facing at the impact against facing after the get-up, in degrees:

| Victim | Weapon | Trot |
|---|---|---|
| `rat_guard2` | halberd, drawn | 156, 177 |
| `rat_guard4` | halberd, drawn | 178, 114 |
| `rat_guard22` | none drawn | 5, 5 |
| `villageGuard` | none drawn | 6, 2 |

Exact: every large turn is a drawn halberd and every small one is not.

### It is not the mod's reaction

The gallop tier hands the body over with `actor:Fall` and plays no clip of this
mod's at all. The same guards, ridden down at gallop:

| Victim | 5,000 ms | 9,000 ms |
|---|---|---|
| `rat_guard4` | 171 | 31 |
| `rat_guard2` | 122 | 53 |
| `rat_guard2` | 154 | 154 |

The same magnitudes as the fall path. The turn belongs to what the game does
when a drawn polearm carrier stands up from a ragdoll, and no animation data
this mod ships is involved in it.

Nothing here is fixable from the fall fragment, and the get-up options carry no
weapon tag to vary: four per direction for an NPC, four more for the player,
and nothing else.

## ColliderMode cannot stop the horse dragging a downed victim

The rider gets stuck on bodies, and the horse carries a victim it stays in
contact with, which is what makes the armor impulse unmeasurable. The obvious
lever looked like the `ColliderMode` layer this mod already writes.

### The engine defines eight modes, not three

Read from the binary's own string table:

```
Undefined  Disabled  GroundedOnly  Pushable
NonPushable  PushesPlayersOnly  Spectator  Interactive
```

Vanilla's male database uses only `Disabled`, `GroundedOnly` and `Interactive`,
so the other five are invisible from the animation data alone.

### Setting it changes nothing, and cannot

The knocked-down tiers were given `NonPushable` while the walk stagger kept
`Interactive`. The generated data was correct and deployed, and the result in
game was indistinguishable: still stuck on bodies, still dragged.

`ColliderMode` is an `AnimatedCharacter` setting and governs collision while
the body is animation driven. The dragging happens after the ragdoll takes the
body, when physics owns it, so the layer has nothing to act on by then. No
value of it can reach this, which also explains the older note that `Disabled`
resolved nothing when it was tried against the same symptom.

### Where the lever actually is

Physics, not animation. The engine parses `collisionClass`,
`collisionClassIgnore`, `collisionClassUNSET` and `collisionClassIgnoreUNSET`
from a physics parameter block, and `entity:SetPhysicParams` is a real Lua
function on an NPC entity, confirmed by type check in the running game.

Reaching it needs the collision class bits the horse and an actor use, which
are not in the animation data and would have to come out of the binary or from
experiment. That is a longer path than the one this entry started down, and it
is recorded rather than taken.

## Riding into a squared-up victim puts the rider inside them, and collision is not why

Three collider modes were tried on the knocked-down tiers, against a baseline
of `Interactive`: `NonPushable`, then `GroundedOnly`, with the walk stagger left
alone in both. The generated data was correct each time and deployed each time,
and neither was distinguishable in game.

The premise was wrong. The player is not blocked by the victim, they are
**inside** them, which is too little collision rather than too much. No collider
mode places a body somewhere else.

### Why the body is there

At trot with `TrotReaction` set to `"fall"`, the dispatch calls `PlayReaction`
and nothing else. **No impulse is applied at that tier at all.** The victim
collapses where they were standing, and against a rider squared up head-on that
is directly under the horse.

Adding an impulse is not a small change either, for the reason the fall tier
exists: an animation-driven actor ignores impulses, which is what sent this mod
to an animated reaction rather than a physics knockdown in the first place. The
fragment does hand the body to physics partway through, so an impulse timed to
that handover would move them, but by then they are already on the ground
underneath the horse and would be slid out rather than thrown clear.

### What is ruled out

Four of the eight collider modes were ridden on the knocked-down tiers, with
the walk stagger left on `Interactive` throughout:

| Mode | Result |
|---|---|
| `Interactive` | baseline: the rider ends up inside the victim |
| `NonPushable` | no observable difference |
| `GroundedOnly` | no observable difference |
| `Disabled` | no observable difference, and nothing clipped into the world |

Nothing distinguishes them, including switching collision off entirely, and
turning it off did not produce the clipping the layer is written to prevent.
Whatever governs a mounted rider passing through a falling body, it is not this
layer, and further values are not worth riding.

The one place the layer demonstrably mattered was the choice between writing it
and omitting it, which is what stopped victims ending up inside wagons. That
comparison was against no layer at all rather than between values.

## Damping the ragdoll stops the sliding, and makes distance mean something

Bodies thrown by a collision slid for meters after landing, which has been true
since 1.0 and reads in game as the ground being ice.

It also made every measurement of throw distance untrustworthy, because what
was being measured was the launch plus the slide, and the slide depends on the
surface rather than on the impact.

### The call

`entity:SetPhysicParams(PHYSICPARAM_SIMULATION, params)` with `damping` and
`min_energy`, which are fields of `pe_simulation_params`. Vanilla uses the same
function for its own entities, with `PHYSICPARAM_COLLISION_CLASS` in
`GeomEntity.lua`, and the constants come out of the binary's own registration
table: `PHYSICPARAM_SIMULATION` is 5, `ARTICULATED` 6, `ROPE` 8, and the
collision class block is 21.

Applied after the impulse rather than with it, so a throw is not damped before
it happens. Accepted on every victim, `ok=true` across twelve impacts.

### What it changes

| | n | mean landing | range |
|---|---|---|---|
| undamped | 9 | 6.19 m | 3.05 to 9.08 |
| damped, 3.0 and 0.5 | 12 | 4.72 m | 2.40 to 6.31 |

The clearer figure is the ground covered after landing, between the samples at
500 ms and 3,000 ms, which is slide and nothing else:

**2.77 m undamped against 1.09 m damped, a reduction of sixty per cent.**

The spread narrows with it, from six meters to under four, so an impact is now
far more repeatable than it was.

### What it does not change

Armor still does not separate: a multiplier of 1.26 averaged 5.05 m against
4.79 m for mail. That is expected rather than disappointing, because the
shipped `Knockback` of 50 was already measured as indistinguishable from
applying no impulse at all. A body of 120 to 160 kilograms takes about 0.6
meters per second from an impulse of that size.

The value of the damping here is that it removes the slide from any future
measurement of that, which was drowning the armor signal in noise.

---

## How the road events actually spawn, and why none of it is reachable

Asked whether the thief a townsman chases could be a model for making a
trampled victim fight back, on the grounds that it looks like a random event in
the way a roadside ambush or the riddler does.

It is not a random event, and there turn out to be three separate systems that
are easy to mistake for each other.

### The random event system is empty

`random_event` carries `ui_caption`, `condition_expression`, `base_run_chance`,
`night_run_chance_modif`, `cooldown`, `map_icon_id` and `map_game_speed`, and
`random_event_option` carries `success_cmd`, `fail_cmd` and a chance
expression. The CVars behind it are `wh_pl_RandomEventsCooldown`,
`wh_pl_RandomEventBaseChanceRunOffset` and `wh_pl_RandomEventAnswer`, all in
the player module.

It is the map travel system, the one that would interrupt a fast travel with a
choice. **Every one of its tables is empty in this build.** Nothing in the
shipped game uses it.

### The situation system is ambient conversation

`situation` holds fifteen rows, joined to `situation_role` for participants and
scoped to a smart area by `sa_smart_area_id`. Only four are enabled:
`talking`, `talkingOnBench`, `beggar` and `testOne`. Shipped disabled are
`preachCrowd`, `dialogWithPasserby`, `talkingByFire`, `reactionToPillory`,
`shoutPillory`, `fortuneTellingPositiv`, `fortuneTellingNegative`,
`tournamentCivilTalk` and two quest situations.

So it is the system that makes two villagers stand and chat, not the system
that puts a thief on the road. It is also not exposed to Lua: `Situations` is
nil in game, and `WH_Situations_StartNew` turns out to be a CVar rather than a
function.

### The thief is EventSystem, and it is Lua

`vanilla_scripts/Scripts/Script/Events_chase.lua` is sixty two lines. C++ calls
`EventSystem.SetupChase()` for a scenario table, `Chase_PickScenario()` to roll
against the weights, and `SpawnChaseEntity()`, which is `System.SpawnEntity`
with `sharedSoulGuid`, `bWH_PerceptibleObject`, `SetLootLegal` and
`MarkAsIgnoredCorpse`. The same family covers `Events_wanderer.lua` and the
ambush behaviors in `Libs/AI/final/sa_event_*.xml`.

The behavior comes from a **patch**: `man_flee` for the thief, `man_chase` for
his pursuer, with the spawned entity set `bIdleUntilFirstPatch` until one
arrives. The chase tree is then driven by blackboard variables,
`event_chase_state`, `event_chase_state_request` and `event_chase_type`.

Patches are behavior tree nodes. The binary defines `AddPatch`,
`CallBehaviorPatch`, `RemovePatch`, `GetPatches` and `FinishPatch` under
`wh::xgenaimodule::BehaviorTree`, there is no Lua bind for any of them, and no
vanilla script applies one. Lua supplies the scenario data and nothing else.

### The finding that matters

Searching the entire shipped script tree for a call that makes an NPC hostile
returns one result, `soul:IsInCombatDanger()`, which is a read. Vanilla Lua
never sets an alignment, never changes a faction relation and never starts a
fight.

Hostility is the crime and faction system's alone, and 4.3.0 already sends a
real player attributed `combat:hit`, which is why a guard comes after the rider
after an impact. Retaliation is therefore probably not a system to build but a
behavior to observe: the open question is only whether a non-guard responds to
the same hit the way a guard does.

`tools/probe_tables.lua` came out of this, and dumps any game table's columns
and first column through the `Database` bind.

---

## KCSE is a native plugin loader with no Lua, and a reverse-engineered map of the game

Evaluated after the road-event research closed the behavior-tree patch route,
on the question of whether the Kingdom Come Script Extender reopens anything
this mod cannot reach from Lua.

The name misleads. It does not extend the game's scripting.

### What it actually is

One file matters, `Bin/Win64/dinput8.dll`, a proxy the operating system loads
in place of the real `dinput8` and which forwards the genuine calls onward.
From inside the process it:

- reads the distribution from `WHGame.dll`, distinguishing Steam, GOG and Epic
  by which of `steam_api64.dll`, `Galaxy64.dll` or `EOSSDK-Win64-Shipping.dll`
  is present, and the build from `wh_sys_version`
- loads a matching `kcd_addresslib_*` file, which maps stable `REL::ID` numbers
  to real addresses for that exact build and distribution
- scans for DLLs exporting `KCSEPlugin_Version` and `KCSEPlugin_Load`
- hands each one an `IKCSEInterface` offering `IMessagingInterface`, for
  plugin-to-plugin traffic with a `kMessage_AllPluginsLoaded` broadcast, and
  `ITaskInterface`, whose `AddTask` runs a `std::function` on the game thread
- supplies a trampoline allocator and `vtable_hook.h`, the machinery for
  hooking game functions

It is the SKSE architecture, ported. The address library is the reason it works
at all and the reason it breaks: the mapping is per build and per store, so a
game patch invalidates it.

### It contains no Lua

Searched for `lua_`, `Lua`, any binding registration and any console command
registration. **None of them appear anywhere in the binary.** It adds no
functions to the scripting environment, no console commands and no script API.
It is a supported way for C++ to be inside the process, and nothing else, so no
Lua mod can call it.

### The archive as distributed does nothing

`KCSE 2244 3 2026-06-29T13-46Z b37E8uyAU.zip` holds four entries: two
directories, `dinput8.dll` at 1.4 MB and `dinput8.pdb` at 32 MB. There is no
address library and there are no plugins. Installed as it stands it reports
`Address library not found` and stops.

### What the symbols are worth

The PDB carries **1,564 reverse-engineered headers of the game's own classes**,
alongside 7,105 game-internal type names:

| module | headers |
|---|---|
| `xgenaimodule` | 590 |
| `databasemodule` | 394 |
| `combatmodule` | 102 |
| `rpgmodule` | 70 |
| CryEngine and offsets | 118 |
| `guimodule` | 34 |
| `entitymodule` | 32 |
| `playermodule` | 13 |

Three of those bear directly on items closed elsewhere in this diary.
`C_AddPatch.h`, `C_CallBehaviorPatch.h` and `C_RemovePatch.h`, under
`include/xgenaimodule/BehaviorTree/bt/`, are the patch nodes that drive
`man_chase` and have no Lua bind. `rpgmodule` carries `C_Faction` and
`S_FactionRelation`, which is the hostility no vanilla Lua call can set.
`combatmodule/C_CombatActor.h` carries the combat action set, including
`C_CombatActorActionHit` and `C_CombatActorActionRiderMovement`.

**The headers themselves are not in the archive**, only their paths and the
type names compiled in. A PDB normally also carries struct layouts and member
offsets, but recovering those requires a real PDB reader such as the DIA SDK or
a Ghidra import, which has not been run. What exists today is a map of how the
game's classes are organized, which the decompilation index does not provide,
and not the definitions themselves.

### Why it stays reference rather than becoming a dependency

Adopting it changes what this project is. The mod is a Vortex-installable pak
of data and Lua that survives game patches. A KCSE plugin is a C++ DLL that
requires a proxy DLL placed in the game's `Bin/Win64`, goes stale whenever the
address library does, and needs an MSVC toolchain and a separate test loop.
Fewer players will install it and more of them will see it break.

If the patch nodes or the faction classes ever justify that cost, the shape is
a separate companion plugin, never a change to this mod.

The build path recorded in the PDB is a `Cheat_Tool_Set/KCD/RE` directory,
consistent with a reverse engineering toolset, and it is a third-party DLL
injected into the game process.

---

## libKCD1 supplies the engine's own script bind catalog, and reopens two closed items

`github.com/JerryYOJ/libKCD1`, GPLv3, is the source the KCSE binary was built
from: the header counts match the shipped PDB exactly, 590 under
`xgenaimodule`, 394 `databasemodule`, 102 `combatmodule`, 70 `rpgmodule`. It is
cloned to `references/libKCD1`.

The entry above judged that archive a map rather than source, on the grounds
that the PDB carried only header paths. **That was wrong about the project as a
whole.** The definitions are public, and 1,990 files of them.

The author's own caveat applies throughout: this is reverse engineered against
game version 1.9.8, offered as a hobby project, and "not every RE'd member is
guaranteed correct." Nothing below is confirmed in game yet.

### The catalog

`include/**/C_ScriptBind*.h` describes **37 script binds carrying roughly 530
Lua methods**, each with its signature and the address it registers from. These
are the engine's own registrations for the scripting layer this mod runs on,
which no shipped documentation covers.

| bind | methods |
|---|---|
| `C_ScriptBindGameRules` | 115 |
| `C_ScriptBindSoul` | 54 |
| `C_ScriptBindPickableItem` | 37 |
| `CScriptBindGame` | 36 |
| `C_ScriptBindXGenAIModule` | 28 |
| `C_ScriptBindQuest` | 27 |
| `C_ScriptBindInventory`, `C_ScriptBindEntityModule` | 17 each |
| `C_ScriptBindActor`, `C_FactionScriptBind` | 10 each |

### A faction API exists in Lua

`include/rpgmodule/C_FactionScriptBind.h` registers `GetId`, `GetName`,
`GetLocationId`, `GetReputation`, `GetBaseReputation`,
`AddReputation(sEnumName)`, `GetAngriness`, **`SetAngriness(float)`** and
**`AddAngriness(float)`**.

The finding recorded against the retaliation item stands as stated: no shipped
script calls anything that makes an NPC hostile, and the only hostility call in
the whole vanilla tree is the read `soul:IsInCombatDanger()`. **The inference
drawn from it does not stand.** That a vanilla script never calls something is
evidence about vanilla's habits, not about what the engine exposes, and
searching scripts was the wrong instrument for the question asked.

### Brain variables are settable from Lua

`C_ScriptBindXGenAIModule` registers `GetBrainVariable` and
**`SetBrainVariable`**, alongside `SendMessageToEntity`,
`SendMessageToEntityData`, `GetEntityByWUID`, `ProduceSound`,
`ProduceSoundWUID`, `SpawnPerceptibleVolume`, `RemoveDaycyclePatch` and
`SetPlayerDogMode`.

The chase behavior tree is driven by blackboard variables, `event_chase_state`,
`event_chase_state_request` and `event_chase_type`. If those are brain
variables in the sense this bind means, the tree is drivable from Lua without
any of the patch nodes that were judged unreachable. That is unverified and is
the first thing to test.

`ProduceSound` bears on the silent-impact item, and `SetPlayerDogMode` on Mutt.

### What this changes about KCSE itself

Nothing. The extender is still a C++ plugin loader with no Lua, still needs an
address library per build, and is still not something to ship against. The
value was never the loader; it is the headers, and those are readable without
installing anything into the game.

---

## Trampled non-guards flee to report the crime, and none of them fights back

Three non-guards ridden down at trot outside a town, at shipped defaults with
`CollisionIsCrime` on, to settle whether choosing fight or flight is this mod's
work or the crime system's. Two women and Miller Peshek.

**Every one of them registered being attacked and ran for a guard to report the
crime. None turned on the rider.**

| victim | gender | speed | reaction | damage | travel at t+10s |
|---|---|---|---|---|---|
| `rat_spaAbbess` | female | 6.99 | `hcm_fall_forward` | -5.74 | 2.37 m |
| `rat_woman11` | female | 6.81 | `hcm_fall_forward` | -5.61 | 6.36 m |
| `rat_pesek` | male | 6.94 | `hcm_fall_back` | -6.59 | 20.46 m |

All three took `CombatHit ok=true strength=5`, all three recovered without
intervention, and `ReplanIfStranded` resumed all three from `MotionIdle` or
`MotionMovement`.

The travel figures separate walking away from running for help. Between
t+6000ms and t+10000ms, Peshek covered 19.78 m, a sustained **4.95 m/s** — a
full run, faster than the 4.5 m/s trot threshold that floored him. The two
women managed 1.40 m/s and 0.42 m/s over the same window, which is a brisk walk
and a limp, and both were still accelerating when sampling stopped.

### What this settles

The flight half of retaliation already exists and costs nothing to keep. It
comes from the crime system, driven by the player-attributed `combat:hit` this
mod has sent since 4.3.0, and it produces a witness walking to a guard rather
than an NPC ignoring the impact.

The fight half does not happen at all. Three victims, three reports, no
aggression. Nothing in the crime response turns a trampled civilian hostile,
so an NPC that comes after the rider has to be made hostile deliberately.

### How angriness is reachable

`C_ScriptBindRPGModule` is the Lua `RPG` table, and it registers
`GetFactions()`, `GetFactionById(id)` and `IsPublicEnemy(wuid)`. The faction
objects those return carry `C_FactionScriptBind`, which registers
`GetAngriness()`, `SetAngriness(float)` and `AddAngriness(float)` alongside
`GetReputation()` and `AddReputation(sEnumName)`. That is a complete path from
Lua to faction hostility, without a behavior patch and without the script
extender.

The binary carries a console command for the same data:

    wh_rpg_angriness [-f FACTION_ID [-a ANGRINESS]] [-p]

which dumps all faction angriness and takes a value, so angriness can be
watched across a collision before any code is written against it. The engine
also names `GetActorAngriness` and `GetFactionAngriness` as XGen functions and
ships an `angriness_enum` table and `C_AngrinessEnumDatabase`, so angriness is
banded rather than a bare float.

### Confirmed in the running game

Probed over the remote console immediately after the ride above, so the
catalog no longer carries the reverse-engineering caveat for this bind.

`RPG` is a real Lua table. `RPG.GetFactions()` returns **98 factions**, each a
table carrying `__FactionId` with the bound methods reached through its
metatable rather than listed by `pairs`. `RPG.GetFactionById(42)` returns
`Faction[#42, name=ui_fac_rataje_out_villagers]`, and on it:

| call | result |
|---|---|
| `f:GetId()` | `42` |
| `f:GetName()` | `ui_fac_rataje_out_villagers` |
| `f:GetAngriness()` | `0` |
| `f:GetReputation()` | `0.5` |

`wh_rpg_angriness -p` dumps 56 rows with per-faction angriness, the faction's
location and position, a last-update stamp and a max distance, plus each
faction's relations to the others as a signed value and a distance.

**Faction angriness did not move.** Every Rataje faction reads `0` after three
trampling crimes committed minutes earlier, with a last-update stamp of
`-6.44e-07` shared across all of them, which is a faction that has never been
updated rather than one updated and decayed. So the crime hit this mod sends
drives the witness-and-report response without touching faction hostility at
all, and hostility would have to be set deliberately.

Whether angriness is the right dial remains open: the engine names
`GetActorAngriness` separately from `GetFactionAngriness`, so a single trampled
villager may carry anger the faction does not. `SetAngriness` and
`AddAngriness` are untested, deliberately — they write to faction state in a
live save and could sour a whole town permanently.

---

## Faction angriness is not hostility, and `hostilePerception` is

`SetAngriness` works, takes a float, and clamps at 1.0: writing 2, 10 and 100
each read back as exactly 1. Written across **all 98 factions at once**, so
that the question could be answered by walking up to whoever was nearest
rather than by working out which faction an NPC belongs to.

**Nothing happened.** Every NPC in Rataje behaved normally with their faction
at maximum angriness: no drawn weapons, no squaring up, no aggression, and a
walk stagger still produced the ordinary reaction rather than a fight.

So angriness is not a hostility switch. It is a number the crime and faction
systems read when they decide something, and setting it directly bypasses
whatever consults it. The engine's dump confirms the write lands —
`wh_rpg_angriness -f 42` reported `0.999919` with a fresh last-update stamp
seconds after the write, so the value is real and decays — but no behavior
hangs off it on its own.

### The message that does decide

`vanilla_scripts/Libs/AI/final/sb_combat.xml` handles
**`combat:stimulus:hostilePerception`**, carrying a `perceptible`, and that
single message is where fight, flee and report are chosen. The branch on
`crimeSystemRole`:

- **circator or monk** — flees if the perceptible is the player, otherwise
  builds a `threat` information and goes to `report`.
- **civilian, renegade or soldier** — reaches the fight branch, which sets
  `t_state = fight`, `t_fightParams.opponent = perceptible`, and sends a
  `combat:bark` with the metarole `SPATRENI_NEPRITELE_-_UTOK`, spotting an
  enemy and attacking.

The fight branch is gated, and the gates are the interesting part:

- `b_context['fightAllHostilePerceptibles']`, a context flag that skips every
  check below and goes straight to fighting.
- otherwise a `LuaGate` running
  `entity.soul:GetDerivedStat('mor') > RPG.MoraleForCombat`. **`RPG.MoraleForCombat`
  reads `0.2` in game.**
- then a `MoraleCheck` at `ThreatLevel` 0.400000 for a soldier or renegade and
  0.550000 for a civilian, or a `CompareMorale` of observer against target.

That is a native courage gate. A brave NPC turns on the rider and a timid one
does not, decided by the game's own morale stat against the rider's, with no
probability constant invented by this mod.

### Why this is reachable

The delivery is the call this mod already makes.
`XGenAIModule.SendMessageToEntityData(target, type, content)` is what `Crime.lua`
uses to send `combat:hit`, and it is the same call vanilla's own `Crime.lua`
uses to send `combat:confrontationFeedback` and `combat:friskFeedback` into the
combat subbrain. `XGenAIModule.SendMessageToEntityData` is confirmed live.

Thirty-seven `combat:` message types appear across the vanilla behavior XML,
`combat:stimulus` at 154 uses being the most common by a wide margin, and the
subbrain reads them from a `combatStimulus` inbox.

### Status

The message has not been sent yet. What is established is that faction
angriness is the wrong dial, that a right one exists, that its gate is morale
rather than a coin flip, and that the transport is already in the mod.

---

## `hostilePerception` works, and morale decides who fights

`combat:stimulus:hostilePerception`, carrying the player as `perceptible`,
sent to eight NPCs at once and sampled for ten seconds afterwards rather than
watched. One attacked and seven fled.

| NPC | morale | dist at send | dist at t+10s | travel | end state |
|---|---|---|---|---|---|
| `rat_guard23` | **0.668** | 11.71 | **2.02** | 13.91 | **`CombatMovement`** |
| `rat_merchant_shop3` | 0.269 | 4.04 | 32.30 | 31.83 | `MotionMovement` |
| `rat_man97` | 0.191 | 4.03 | 25.25 | 28.91 | `MotionMovement` |
| `rat_merchant_shop1` | 0.171 | 13.52 | 31.32 | 29.84 | `MotionMovement` |
| `rat_swordsmiths_wife` | 0.171 | 9.37 | 38.48 | 30.56 | `MotionMovement` |
| `rat_refugee_Radan` | 0.171 | 14.21 | 47.93 | 35.35 | `MotionMovement` |
| `rat_pickpocket_woman1` | 0.171 | 14.41 | 46.51 | 33.14 | `MotionMovement` |
| `rat_woman3` | 0.171 | 14.51 | 49.50 | 39.16 | `IdleToMove` |

The guard closed from 11.71 m to 2.02 m and entered `CombatMovement`, the
combat locomotion state, while every other NPC ran 25 to 50 m in the opposite
direction. Nothing else was sent and nothing in the mod was changed.

### The address is `this.id`, not `id`

An earlier attempt sent the same message to `ent.id` and produced nothing at
all. The two are different objects:

    rat_merchant_shop3   ent.id    = 000000000007C0FA
                         this.id   = 0500000000000763
    player                         = 0500000000000A53

The `05` prefix marks a WUID, and `Crime.lua` already sends `combat:hit` to
`this.id` for exactly this reason. A message sent to the entity id is accepted
and discarded silently, which is the same failure recorded against
`daycycle:restartRequest` and against a `key(value)` payload. **A null result
from a typed message means the address or the shape is wrong before it means
the mechanism is absent.**

### The gate is not the constant alone

`RPG.MoraleForCombat` reads `0.2`, and `sb_combat.xml` gates the fight branch
on `entity.soul:GetDerivedStat('mor') > RPG.MoraleForCombat`. But
`rat_merchant_shop3` reads 0.269, clears that constant, and fled anyway.

The `MoraleCheck` that follows explains it: threat level **0.400000** for a
soldier or renegade against **0.550000** for a civilian. A townsman at 0.269
fails the civilian check; a guard at 0.668 passes the soldier one. So the
split observed is the one the tree describes, and it lands where it should —
**guards fight, civilians run** — without this mod choosing anything.

Civilian morale is strikingly uniform: 0.171 for six of the eight, which
suggests a class default rather than a per-NPC roll.

### `IsInCombatDanger` is not a hostility read

It returned `false` for every NPC at every sample, including the guard at 2 m
in `CombatMovement`. Whatever it reports, it is not "this NPC is fighting the
player", and it should not be used to detect retaliation.

---

## The context system is the real API, and it is a menu of about ninety switches

`Scripts/Script/ContextData.lua` catalogs **89 context options and 14 presets**,
and `Scripts/Script/Context.lua` exposes them to Lua as `Contexts`:

    Contexts.SetPersistentOption(entity, option, handle, params)
    Contexts.SetNonpersistentOption(entity, option, handle, params)
    Contexts.ClearOption(entity, option, handle, params)
    Contexts.CheckOption(entity, option)
    Contexts.SetNonpersistentPreset(entity, preset, handle, params)
    Contexts.ClearPreset(entity, preset, handle, params)

Vanilla quests drive NPC behavior with exactly these calls. `q_ledecko` sets
`fightAllHostilePerceptibles` on four bandits, `q_huntPtacek` on two Cumans,
and `q_hareHunt` applies the `berserk` preset. Every option is carried on a
named **handle**, so several systems can request the same option and clearing
one does not disturb another.

Applied here to 20 NPCs at once: 19 accepted `alwaysFightWhenHit` and
`Contexts.CheckOption` read back `true` for all of them. The one refusal was
`rat_activity_vagabund`, an activity-spawned NPC, which errored inside
`Context.lua` itself.

### The options that bear on this mod

Retaliation:

| option | effect |
|---|---|
| `alwaysFightWhenHit` | answers a hit with a fight rather than the usual response |
| `fightAllHostilePerceptibles` | fights anything perceived hostile, skipping the branch conditions |
| `suppressFightMoraleChecks` | removes the morale gate that makes civilians flee |
| `forceFightUncertainBehavior` | forces the uncertain-behavior branch to fight |
| `disableChangeHostilityOnHit` | a hit does not change hostility |
| `neverAcceptSurrender` | refuses a yield |

A consensual brawl, where onlookers do not fetch a guard:

| option | effect |
|---|---|
| `suppressDudeHostilePerceptionStimuli` | the NPC ignores the player being perceived as hostile |
| `suppressDudeHostilePerceptionStimuliWhileNotInCombat` | the same, only outside combat |
| `suppressReputationHitOnDudeHit` | being hit by the player costs no reputation |
| `suppressReputationPreventForDudeHits` | player hits do not trip the reputation guard |
| `suppressCollisionsBark` | silences the collision bark |
| `suppressHitReactions` | no hit reaction at all |
| `postMercyImmunity` | immunity after mercy is granted |
| `impossiblePayingCrimeFine`, `impossibleCrimeSkillChecks`, `availableCrimeAuthority` | crime-dialog levers |

The presets show how vanilla composes them. `berserk` is
`fightAllHostilePerceptibles` plus `suppressFightMoraleChecks`, and nothing
else. `eventEnemyWithFriendlySuperfaction` — an enemy who fights the player
without the world turning on them — is `suppressDudeProxBark`,
`suppressPickNoticedItems` and `suppressReputationPreventForDudeHits`.
`kunoband` is the full eighteen-option bandit profile.

### The duel system is separate and probably out of reach

`sa_duel.xml` carries a complete sparring implementation: `duel:duelRequest`,
`duel:startDuelWithPlayer`, `duel:stopDuel`, `duel:suspendDuel`,
`duel:duelResult`. `startDuelWithPlayer` takes a `bet`, a `difficulty`, a
`borrowArmor` flag, `myWeapons` and `enemyWeapons` of type
`enum:duelWeaponTypes` — which includes **`Unarmed`** — an `isWooden` flag for
training weapons, and a `customCombat` string.

That is the trainer and tournament fight, and it ends cleanly:
`duel:stopDuel` carries a `winner` wuid "so NPCs can recognize who need to
play winner animation and who will play surrender".

**None of the `duel:` types appear in `MessageTypes.xml`.** Only
`skirmish:duelRequest` is registered there. So they are almost certainly
local to the duel scripted action, and an NPC not running `sa_duel` has
nothing listening. Unverified.

### Custom behaviors suppress stimuli by design

`combat:stimulus:customBehaviorRequest` is registered, is handled by the
combat subbrain starter that every NPC runs, and carries:

    behaviorSource + behaviorName, or includeXml + includeTree
    suppressStimuli        default true
    interruptRunningState  default true
    entity, bool1..4, int1..2

The comment on `suppressStimuli` in `TypeDefinitions.xml` reads "whether all
other combat stimuli are suppressed while in the custom behavior". That is
crime suppression stated in the game's own data, and it is the mechanism
`sa_duel`, `sa_event_ambushplr` and eighteen other scripted actions use.

### Hostility and crime are separate, and the seam shows

Sending `hostilePerception` made guards fight without any crime being
registered: on surrendering, the guards froze and the crime conversation
never started. So the combat that message produces is not a prosecutable
event, and the surrender path that normally resolves a guard fight has
nothing to resolve. Any feature built on hostility alone inherits that dead
end and needs its own ending.

---

## `alwaysFightWhenHit` produces the whole brawl, resolution included

One context option, set on 19 NPCs before the ride, no code in the mod
changed and nothing else sent:

    Contexts.SetNonpersistentOption(ent, "alwaysFightWhenHit", "hcm_brawl_test")

Ridden into at trot, **the merchant fought back** instead of fleeing. Guards
witnessed it and joined in against the rider. The rider surrendered, every
participant dropped hostility, the crossed-swords hostility indicator faded,
and the encounter ended on its own.

**No crime dialog occurred, and none was needed.** `CollisionIsCrime` was on
and the mod sent its usual `combat:hit`, so the difference is not that the
crime path was disabled. The fight simply resolved as a fight.

That is the opposite of the earlier `hostilePerception` result, where guards
made hostile the same way froze on surrender with no way to finish. The
distinction worth keeping: a fight entered through **being hit** carries its
own ending, and a fight entered through **being told someone is hostile**
does not.

### What this settles

Retaliation is one context option. It needs no custom behavior tree, no
faction write, no `hostilePerception` message, and no probability constant
invented by this mod. The victim's own morale still decides how the fight
goes; the option only decides that a fight is the answer.

It also delivers most of what a consensual brawl needs for free: no crime
prosecution, no cutscene, and a surrender that resolves cleanly.

### What it does not yet do

Two gaps against a tavern-style brawl, both untested:

- **Guards joined in.** For a fight the town ignores, bystanders need
  `suppressDudeHostilePerceptionStimuli`, which stops an NPC reacting to the
  player being perceived as hostile.
- **Weapons were not constrained.** Nothing here forces fists.
  `enum:duelWeaponTypes` carries `Unarmed`, but that belongs to the duel
  scripted action rather than to the context system, and no context option in
  the catalog obviously forces an unarmed fight.

---

## How a civilian answers a hit, in full, and the two gates that matter

`sb_combat.xml` lines 8308 to 8365 carry the whole decision for a victim whose
`crimeSystemRole` is `civilian`:

    if b_context['alwaysFightWhenHit'] or b_context['suppressFightMoraleChecks']
        pass
    else
        CompareMorale(this, attacker)          -- must win to continue

    if b_soul.gender == male                   -- women fail here, always
        pass
    else
        fail

    -> t_state = fight, t_fightParams.opponent = realAttacker
       and if the attacker is the player and the player is not already an
       enemy, t_fightParams.startInDefenseOnly = true

    -- when the fight path fails:
    if attacker == player and b_soul.caste <= normal
        CreateInformation 'assault' -> t_state = report
    else
        t_state = flee, with t_fleeParams.fightIfHit = true

### Female civilians cannot retaliate

The `gender == male` test sits **after** the context check and is not
bypassed by it. `alwaysFightWhenHit` removes the morale comparison and nothing
else, so a woman set to always fight when hit still falls through to `report`
or `flee`. Any retaliation feature is male-only among civilians unless some
other path exists.

### `startInDefenseOnly` is why the brawl behaved

When the attacker is the player and the player is not already an enemy, the
fight starts in defense only. The NPC squares up and blocks rather than
opening with an attack, which is what a scuffle over being shoved looks like
and is the reason the observed brawl read as proportionate.

### Vanilla already has the annoyance idea

The flee branch sets `t_fleeParams.fightIfHit = true`. A civilian who runs
will turn and fight if struck again. The concept of wearing someone's patience
down is the game's own, not an invention.

### `real = false` sends a hit that costs no reputation

`sb_switch_hitreactions.xml` line 481 gates the reputation change on
`$hit.real`:

    if hit.attacker == player
       and not b_context['suppressReputationHitOnDudeHit']
       and not isDudeBestFriend
       and not (suppressAssaultReactions and suppressReputationHit)
       and hit.real                              <-- here
    then
       reputationChangeName = hit_melee_weak | _medium | _strong | _brutal
                              by hit.strength, 3 / 4 / 6 thresholds
       if b_context['disableChangeHostilityOnHit']
          reputationChangeName += '_noChangeHostility'
       SetReputationNPC(reputationChange)

So a `combat:hit` carrying `real = false` reaches the combat subbrain and
drives the fight decision, but never reaches `SetReputationNPC`. Vanilla uses
it for near misses and for horse collisions: `sb_switching_horse.xml` sets
`$hit.real = false` for a hit relayed off a horse.

That is the mechanism for a fight the crime system does not prosecute, and it
needs no context option at all. `suppressReputationHitOnDudeHit` reaches the
same place by another road, and `disableChangeHostilityOnHit` softens the
reputation entry rather than removing it.

### Witnessing appears to be modeled

The same condition block reads `isKnockOutByPlayer` against
`isKnockOutByPlayerAndSeen`, and the report path builds its case with
`CreateInformation PerceivedWuid=... label='assault'`. Whether a bystander
reacted to something it actually saw is therefore a distinction the game
already draws. Not investigated further.

---

## Retaliation fires as designed, and a witness still reports the brawl

First run of `Retaliation.lua` in game. Three walk staggers on `rat_man6`:

    Retaliation rat_man6 count=2 chance=0.25 roll=0.34 provoked=false
    Retaliation rat_man6 count=3 chance=0.50 roll=0.26 provoked=true
    ProvocationHit rat_man6 ok=true strength=2 err=nil

The first shove was free, the second rolled 0.34 against 0.25 and passed
without incident, the third rolled 0.26 against 0.50 and he turned and
fought. The count, the curve and the roll all behave as written, and
`math.random` is seeded by the game rather than returning a fixed sequence.

**A woman witnessed it and a crime was reported immediately.** Surrendering
produced a charge of brawling rather than assault.

### Why `real = false` did not prevent it

It prevented what it gates and nothing else.
`sb_switch_hitreactions.xml` runs two separate branches off a hit, and only
the first is gated on `$hit.real`:

- The **reputation** branch, at line 481, computes a `hit_melee_*` change and
  calls `SetReputationNPC`. Gated on `$hit.real`, so `real = false` skips it.
- The **assault broadcast**, at line 615, is gated on something else
  entirely:

        if suppressAssaultReactions and checkAssaultSuppression.suppressExternalReactions
            Success                     -- nothing is broadcast
        else
            SpawnExpiringPerceptibleVolume
                Expiration 6s, Radius 1, Height 1, Label 'assault',
                conspicuousness 1, visibility 1
            IgnorePerception for the attacker and for the victim
            AddLink assaultVolumeData carrying attacker, victim and kind

  So a one-meter perceptible volume labeled `assault` is spawned at the
  victim for six seconds. The attacker and the victim are explicitly made
  blind to it; **everyone else can see it**, and that is what a bystander
  reports. It fires whether or not the hit was real.

### The suppression is a link, and Lua cannot make links

`suppressAssaultReactions` is not a context option. It is computed by the
`checkAssaultSuppression` tree in `sb_combat.xml`, which walks **entity links
tagged `suppressAssaultReactions`** between attacker and victim.
`sa_duel.xml` is where that is used in anger:

    AddLink    From='this.id' To='__player' Tag='suppressAssaultReactions'
    RemoveLink From='this.id' To='__player' Tag='suppressAssaultReactions'

`questUtils.xml` adds an `expiration` to the same link's data. That is the
whole mechanism behind a sparring match the town ignores.

**No script bind exposes links to Lua.** All 37 `C_ScriptBind*` headers
carry only readers: `GetLinkedEntity`, `GetLinkedOwner`, `GetHelperLinks`,
`GetHelperLinkTarget`, `IsLinkedWithShop`. There is no `AddLink`. Vanilla Lua
never creates one either.

The one untried route is `combat:stimulus:customBehaviorRequest`, which takes
an `includeXml` and an `includeTree` and is reachable from Lua, pointed at a
tree inside `sa_duel.xml` that adds the link. Speculative, and it would tie
this mod to the internals of a scripted action.

### Reputation was not cleanly measured

`ui_fac_ratays_citizens` reads 0.357 against a base of 0.5, and
`ui_fac_ratays_traders` 0.538. The same session included three trot
tramplings that were real crimes with `real = true`, so this does not isolate
what the brawl cost. A clean measurement needs a fresh save with no prior
offense.

---

## The runaway was a flee that outlived its cause, and `standDownRequest` ends it

The no-crime fix worked. A beggar provoked at the fourth shove
(`roll=0.36` against `chance=0.75`) turned hostile with **no crime reported**,
where the previous build had charged the rider with brawling before a punch
was thrown. Sending `combat:stimulus:hit` instead of `combat:hit` is what did
it: the assault perceptible volume lives in `sb_switch_hitreactions.xml`, and
the stimulus goes straight to the combat subbrain without passing through it.

He then yielded immediately rather than fighting, was released unconditionally
through the surrender dialog, and ran out of town without stopping.

### The mod was not holding him

Inspected live while he ran. No context option was set on him at all, and the
mod's own telemetry had already reported `RetaliationEnd cleared=true
state=IdleToMove replanned=true`, so the option came off and the daycycle
restart was accepted. He read `MotionMovement`, profile `alive`, health 100,
morale 0.169. The flee was vanilla's, and it had outlived the incident that
started it.

Note the contrast in the log: `cleared=false` on victims the option was never
set on, and `cleared=true` on the one it was. `Contexts.ClearOption` throws
when the handle is absent, so that field distinguishes the two rather than
reporting a failure.

### The one message that reaches someone mid-flight

`combat:stimulus:standDownRequest` sets `t_state = standDown`. It matters
because of the acceptance rule in `sb_combat.xml`: a stimulus arriving while
the receiver is already in `fight` or `flee` is rejected outright, **except**
for `standDownRequest` and `customBehaviorRequest`. Those two are named in the
condition and skip the check. So every other message this mod could send is
discarded by exactly the victim who needs one.

Measured on the runaway, samples taken 1, 3, 6 and 10 seconds apart:

| | before | after |
|---|---|---|
| t+1s | | `MotionIdle`, 1.86 m |
| t+3s | | `MotionIdle`, 0.00 m |
| t+6s | `MotionMovement`, 12.95 m | `MotionIdle`, 0.00 m |
| t+10s | `MotionMovement`, 16.95 m | `MotionIdleVARdefault`, 0.00 m |

He stopped inside a second and was in a daycycle idle variant ten seconds
later, which is a resumed routine rather than a frozen actor.

### The payload is empty, and that is not the same as absent

`TypeDefinitions.xml` declares one member on `standDownRequest`, named `_`.
It is a placeholder, not a field: passing it is rejected outright with
`override table does not match the type 'combat:stimulus:standDownRequest.',
got member '_.'`. Vanilla's own sends carry `values=""`.

`Utils.makeTable` validating against the type definition is worth noting on
its own. It rejected a wrong payload with a precise message, where the same
mistake made by hand would have been delivered and silently discarded.

### A beggar yielding at once is not a fault

`alwaysFightWhenHit` decides that a fight is the answer. It does not decide
how the fight goes, and nothing in it makes a coward brave. A beggar at 0.169
morale surrendering to a mounted man immediately is the game working.

---

## The crime lands on the player's own punch, and `SurrenderIn` broke the watch

Two provoked brawls, `rat_ruch` and `rat_man19`, both civilians, both
provoked on the third shove.

### The crime timing is right, and it is the player's

**No crime is reported when the victim turns hostile.** It is reported when
the rider swings back. In the second encounter the rider threw no punch at
all: the victim fought, guards joined and punched the rider, and still no
crime existed. One punch from the rider, and the charge appeared.

That is the correct division and it comes out of the behavior data rather
than out of this mod. The provocation is a stimulus the victim answers; the
assault is something the player does.

A provoked **guard** is a different matter and is left that way deliberately.
The soldier branch of the hit handler raises assault information whenever the
attacker is the player, with no `real` check and no context option in front of
it, so a provoked guard arrests rather than brawls. An earlier revision gated
soldiers out of the roll. That gate was wrong: a guard exercising authority a
townsman does not have is the distinction the crime-free brawl exists to draw,
not a fault to design around. The gate has been removed.

### `SurrenderIn` defeated the state watch

Both incidents closed as `why=natural cleared=true state=SurrenderIn
stoodDown=false replanned=false`, and both victims were left running
afterwards. `rat_man19` was measured circulating between two points at
**4.79 m/s sustained** for several minutes.

The classifier tested `^Combat` for "the incident is still running" and
treated everything else as settled once it stopped moving. A victim mid-yield
stands in `SurrenderIn`, which carries no `Combat` prefix and is perfectly
still, so three consecutive samples of it read as settled and the watch
closed the incident while the victim was in the middle of surrendering.

`why=natural` was therefore a false positive on both runs, and the question of
whether the game resolves its own fights is **still unanswered**: no true
natural resolution has been observed yet, only a misread one.

The engine's surrender states all share a prefix, and all of them are now
treated as engaged: `SurrenderIn`, `SurrenderDialog`, `SurrenderDialogToIdle`,
`SurrenderDialogToMove`, `SurrenderForcedWait`, `SurrenderToCombat`.

### The stand-down works on a circulating flee, more slowly

Applied by hand to `rat_man19` while he ran. Speed by sample afterwards:
3.94, 2.75, 3.45, then 1.58 m/s, decelerating below the 3.5 m/s flee
threshold to a walking pace. Slower than the beggar, who reached `MotionIdle`
inside a second, but the same outcome.

---

## Every runaway was observed by chasing the runaway

`rat_man19` was still circulating after a hand-applied stand-down slowed him
from 4.79 m/s to 1.58 m/s. Probed for a cause, expecting a temporary hostile
superfaction, since the context catalog carries
`suppressTempSuperfactionClearingInCombatVersusDude` and `combat:fightOptions`
carries `clearTempSuperfactionAgainstPlayer`.

That was not it. `GetSuperfaction` and `GetPerceivedSuperfaction` both read 3,
identical, against the player's 5. He was in no hostile faction at all.

**`distToPlayer=2.53`.** The rider was two and a half meters behind him.

That confound runs through every runaway recorded today. The beggar followed
out of town, and this one: in each case the flee that "would not end" was
being watched by the one person whose presence sustains it. The stand-down
demonstrably worked on both, and both resumed once the rider closed again,
which is a fresh flee rather than an old one persisting.

### Reading an NPC at distance proves nothing

With the rider 116 m away, six samples two seconds apart reported
`mps=0.00` and a position identical to the decimal, while the animation state
stayed `MotionMovement` rather than becoming an idle. That is an actor frozen
outside the simulation radius, not one that settled. The engine carries
`wh::xgenaimodule::BehaviorTree::C_LODCombat`, so AI level of detail exists.

**Any observation of a distant NPC's state is worthless.** A victim has to be
watched from close enough to be simulated and far enough not to be the thing
being fled, which is a narrow band, and every measurement taken today outside
it should be discarded.

### What the mod does about it

A running victim is only a runaway when the rider is more than
`RetaliationFleeIgnoreRange` away, 25 m by default. Running from someone
standing over you is correct behavior and interrupting it would be the fault.
Below that range a running victim is classified as engaged: the incident stays
open, nothing is sent, and the victim is left to do the sensible thing.

---

## Both endings observed cleanly, and the game does resolve its own fights

First run on a reloaded save, with the rider stationary rather than following
the victim. `rat_man19`, a townsman, provoked twice.

    Retaliation    rat_man19 role=townsman count=3 chance=0.50 roll=0.36 provoked=true
    RetaliationEnd rat_man19 why=natural  state=MotionTurn     stoodDown=false replanned=false

    Retaliation    rat_man19 role=townsman count=2 chance=0.25 roll=0.04 provoked=true
    RetaliationEnd rat_man19 why=runaway  state=MotionMovement stoodDown=true  replanned=true

**The first is the answer to a question open all session.** The rider
surrendered to the victim, the encounter resolved on its own, and the mod sent
nothing at all. The game does clean up after its own fights, and the
stand-down is a failsafe for the case where it does not rather than the
mechanism.

The second earned its intervention: after taking payment through the yield
dialog the victim ran, cleared the 25 m range test, and sustained it.

Sampled afterwards, at two-second intervals, with the rider stationary:

| | state | speed | range to rider |
|---|---|---|---|
| t+2s | `MotionMovement` | 0.00 | 16.1 |
| t+4s | `MotionMovement` | 0.97 | 14.2 |
| t+6s | `MotionMovement` | 0.95 | 12.3 |
| t+8s | `MotionMovement` | 0.99 | 10.4 |
| t+10s | `MotionMovement` | 0.97 | 8.5 |

A steady walking pace against the 4.79 m/s of a flee, and the range closing
rather than opening: a victim walking back to his routine rather than running
from anything. The replan did its job.

## Two things the yield dialog raises, both parked

Neither is this feature's, and neither has been investigated.

**The surrender prompt is not shown.** Surrendering to a provoked victim
resolves the encounter cleanly, but the on-screen input hint that normally
appears when guards are attacking does not, so a player has no way of knowing
the option exists. The engine carries
`wh::xgenaimodule::BehaviorTree::C_SurrenderActionHint` and
`S_SurrenderActionHintContext`, plus a `SurrenderActionHint` string, so the
hint is a behavior tree node. Whether it can be raised from Lua is unknown.

**The yield dialog can be used to extract money.** A victim who yields offers
the usual options, including paying the player to be let go. A provoked brawl
is not a crime unless witnessed, so this is a repeatable income with no legal
consequence, which is a plausible early-game exploit. It is vanilla's dialog
reached through a fight this mod arranges, so the mod is at least adjacent to
it.

---

## A provoked brawl costs no reputation

Five Rataje factions read before and after a complete provoked brawl on
`rat_man29`, a townsman: three walk staggers, provoked on the fourth
(`roll=0.01` against `chance=0.75`), a punch from the rider, and a yield.

| faction | before | after |
|---|---|---|
| `ratays_traders` | 0.537924 | 0.537924 |
| `ratays_citizens` | 0.446707 | 0.446707 |
| `rataje_out_villagers` | 0.500000 | 0.500000 |
| `ratays_soldiers` | 0.382400 | 0.382400 |
| `kunes_rattay` | 0.160000 | 0.160000 |

**Identical to six decimal places, every one.** A townsman belongs to
`ratays_citizens`, so the faction that would have moved was measured and did
not move.

That is the `real = false` provocation and the `combat:stimulus:hit` route
working as designed: neither reaches `SetReputationNPC`. The figures below
base for citizens and soldiers are this save's own history and predate the
test.

The claim has one limit. This brawl raised no witnessed crime. A witnessed
one, reported and fined, goes through the crime system's own reputation
machinery, which has not been measured separately.

The encounter also closed `why=natural state=MoveToIdle` with nothing sent,
the second genuine natural resolution recorded.

### The victim holds no grudge in any value that can be read

Asked directly, `rat_man19` reported `relationshipToPlayer = 0.537791`,
slightly **positive**, with `GetSuperfaction` and `GetPerceivedSuperfaction`
both 3 and identical. Nothing persistent marks the rider as an enemy, which
argues against the flee-on-approach being a permanent state. It is not
evidence that it decays, only that no stored value carries it.

---

## The flee-on-approach isolation test is confounded by an active crime

Run with the mod entirely uninvolved: dismounted, a fresh civilian punched by
hand. He was knocked out, a witness fled and reported it, and a crime was
outstanding when he woke. Walking into his field of view made him flee.

So vanilla does produce flee-on-approach after a beating. **But it does not
separate the two candidate causes**, because the crime was still active: an
NPC avoiding the man who beat him and an NPC avoiding a wanted criminal look
identical from the saddle.

The player's crime state could not be read to settle it from outside.
`soul:IsPublicEnemy()` errors on the player, and `RPG.IsPublicEnemy` errors
whether passed the wuid or a string. `XGenAIModule.GetWuidDebugString` does
work and answers `WUID:(Soul)A53{Dude}`, so the player wuid itself is fine and
the fault is in those two calls or in how they are addressed.

### The test that removes the confound

A mod-provoked brawl raises no crime at all as long as the rider throws no
punch. That was established earlier: guards were seen punching the rider while
no charge existed, and the charge appeared on the rider's first swing. So
provoking a victim and never swinging produces a complete brawl with no crime
anywhere in it, and approaching the victim afterwards tests the beating alone.

Not yet run.

### What is known against a permanent state

`relationshipToPlayer` reads 0.537791, slightly positive, and both
`GetSuperfaction` and `GetPerceivedSuperfaction` read 3 and match. No readable
value marks the rider as an enemy. That is an argument against permanence, not
proof of it, since whatever drives the flee is evidently not stored in any of
the three.

---

## Beating a man to a yield zeroes his relationship, and only his

Thirty humans within 40 m had their `soul:GetRelationship(playerWuid)` read
before a provoked brawl and again after it. The rider provoked one man, beat
him until he yielded, and touched nobody else.

| NPC | before | after |
|---|---|---|
| `rat_man19` | 0.5378 | **-0.0000** |
| the other 23 read both times | unchanged | unchanged |

The common baseline is **0.5378**, shared by nearly every townsman, merchant
and shop guard. Soldiers sit at 0.4052 and beggars at about 0.72. An earlier
reading of 0.5378 on a brawl victim was taken as "slightly positive, holds no
grudge"; it was simply the default, and that inference was wrong.

So the cost of beating someone is **individual and local**: their own
relationship with the rider, not the faction reputation, which was separately
measured as unmoved to six decimal places, and not the town at large.

It lives in the save. `rat_ruch` read `-0.0000` after being beaten in an
earlier session and reads 0.5682 after the save was reloaded.

This is what the flee-on-approach follows, and it explains why paying the fine
changed nothing: the crime and the relationship are different records, and
only the first was settled.

**It is also not this mod's doing.** The rider's own fists lower it. The mod
arranges for a man to be willing to fight; what the rider then does to him is
the rider's.

Whether it recovers is the open question, and `soul:ModifyPlayerReputation`
exists as a lever if it turns out not to.

## Side finding: the closeout pair unsticks an NPC the mod never touched

Several NPCs were seen running into the inn area and stopping. Three were in
`MotionMovement` and sampled: two were moving normally at 1.2 to 2.6 m/s and
were not stuck at all. `rat_man12` read **0.00 m/s across every sample while
in `MotionMovement`**, which is the genuine signature: a locomotion state with
no locomotion.

He is not this mod's. The log carries **zero** `HorseCollisionMod` lines
mentioning him across the whole session: no collision, no stagger, no
provocation. He held no context option, had no annoyance entry, and his
relationship read the ordinary 0.461 baseline.

The one thing that had touched him was a read-only morale probe that called
`SetState("mor")` and `SetState("morale")`, which measurably changed nothing;
two other NPCs from that same set were behaving normally at the time. Not a
likely cause, but not excluded either.

`SendStandDown` followed by `ReplanVictim`, the same pair `EndRetaliation`
sends, freed him:

    MotionMovement 0.00 -> StandUp -> MotionIdle -> MotionIdleVARdefault

That is a point in the closeout's favour beyond its own feature: the pair is a
general recovery for an actor wedged in a locomotion state, not something that
only makes sense after a brawl.

### Correction: the inn NPCs were stuck, and a load screen cleared it

The sampling above was taken **after** the player fainted and woke, and a load
screen resets NPC state. The NPCs read as normal because they had already been
fixed, not because they were never stuck. The rider confirms they were frozen
beforehand.

The most likely cause is not the mod's collision system but a repair script
run earlier in the same session, which sent `daycycle:restartRequest` to every
human within 60 m, 50 of them, to free one runaway. It interrupted NPCs who
were mid-activity, a butcher carving and a Konrad Hagen listening to dialogue
among them, and was waved through as harmless at the time. An inn full of
people running scripted activities is precisely where that would surface.

Unproven, and recorded as the leading candidate rather than a conclusion. The
practical rule it argues for: a repair sends its messages to the entity that
needs repairing, never to everyone nearby.

---

## Vanilla control: a fist fight zeroes the relationship, with the mod uninvolved

The decisive test for whether this mod causes victims to flee from the player
permanently. The rider dismounted, so no part of this mod ran: no walk
stagger, no provocation, no `alwaysFightWhenHit`, no `combat:stimulus:hit`.
He punched a merchant, the merchant fled, the rider surrendered to the guards
and resolved the crime, then followed the merchant.

Read afterwards, against three untouched controls:

| NPC | history | relationship | state |
|---|---|---|---|
| `rat_merchant_shop3` | punched on foot, crime resolved | **-0.0508** | `MotionMovement`, 108 m off |
| `rat_merchant_shop2` | untouched | 0.5048 | `ADLG_Gesture27` |
| `rat_bedrich` | untouched | 0.5048 | `Lying` |
| `rat_shop_guard_general` | untouched | 0.5048 | `LeaningBackVAR` |

The whole baseline had drifted from 0.5378 to 0.5048 over the session and all
three controls moved together, so the merchant's -0.0508 is a real
displacement rather than a shifted scale. Superfaction and perceived
superfaction both read 3, unchanged.

The rider reported him seeming normal at first and then recognizing the rider
and fleeing again.

**This is vanilla's consequence for beating someone, not this mod's.** The mod
arranges for a man to be willing to fight; the fists and everything that
follows from them are the player's. Resolving the crime does not restore the
relationship, because the crime and the relationship are separate records.

Whether a zeroed relationship recovers over time is a question about Kingdom
Come rather than about this mod, and remains unmeasured. `rat_refugee_Radan`
read `-0.0000` before a save reload and 0.7222 after it, which confirms only
that the value is save state.

## The relationship penalty does not decay, and the gap is the way to measure it

Tracked across several in-game days after the vanilla fist fight:

| | after 1 day | after several more |
|---|---|---|
| `rat_merchant_shop3` | -0.1608 | -0.1606 |
| `rat_merchant_shop2` control | 0.3948 | 0.3949 |
| `rat_bedrich` control | 0.3948 | 0.3949 |
| **gap** | **0.5556** | **0.5556** |

**The absolute value is not the measurement.** Between two readings minutes
apart, the victim and both controls all moved by exactly 0.11, which is a
global shift in the player's standing rather than anything about the victim.
Read the gap between the victim and an untouched neighbor instead, and it has
not moved at all.

So the personal penalty for beating a man is **fixed at 0.5556 and does not
decay over days**. Whether it decays over longer spans is unmeasured, but a
value that has not moved a thousandth across several days is not on a fast
curve.

The global component does move, which implies the relationship is something
like a town-wide standing plus a fixed personal penalty. If so, raising
standing in the town lifts the victim's absolute value even while the penalty
stands, and could carry him back above whatever threshold makes him flee.
Untested.

`AddReputation` and `soul:ModifyPlayerReputation` both take an enum name
rather than a number. The `reputation_change` table exists with columns
`reputation_change_id, name, change, reputation_change_target_id,
can_change_hostility, reputation_cap, reputation_notification_id`, but its
rows do not come back through the `Database` bind, the same limitation seen
with `angriness_enum`. The names recoverable from behavior data are all
penalties: `hit_melee_weak`, `hit_melee_medium`, `hit_melee_strong`,
`hit_melee_brutal`, `death`, `pickpocket_fail`, `crime_theft_individual` and
`surrender_step`.

### Testing across game time is expensive and should be avoided

Hardcore mode makes passing days costly: the player has to eat and sleep, and
the skip runs at `wh_pl_SkipTimeMaxWorldTimeRatio` 360, one real second per
six game minutes, so a day costs about four real minutes of watching a bar.

Two mitigations, both applied. `soul:SetState` sets the player's `hunger` and
`exhaust` to 100 directly, which removes the survival errand from any test
needing time. Raising `wh_pl_SkipTimeMaxWorldTimeRatio` shortens the skip
proportionally. Both are console values and a save reload wipes them.

Note that `stamina` reads 150 on the player rather than 100, so setting it to
100 lowers it.

---

## Corrections to the assault aftermath, and what a beaten NPC actually does

Several claims made earlier in this session were wrong and are corrected here.

### No state reading beyond about 25 m is trustworthy

Three separate NPCs were called stuck on readings taken at 40 to 80 m, after
the same session had already established, with a beggar at 116 m, that a
distant actor reads as motionless because its AI is not ticking. The engine
carries `wh::xgenaimodule::BehaviorTree::C_LODCombat`, so AI level of detail
is real. The one NPC that genuinely was wedged, `rat_man12`, was read at 23 m.

A useful tell: an unsimulated actor's position is identical to the decimal
place across samples, while a simulated one that happens to be standing still
still jitters.

### `Lying` at full health is a routine activity

The merchant was found in `Lying` and taken for injured or stuck. At the same
moment ten NPCs within 80 m were `Lying`, **every one at 100 health**,
including six guards, a scribe and a villager. It is a scheduled rest, not
damage and not a fault.

### An injured NPC does heal

The claim that an NPC never heals, which the auto-cure suppression exists to
work around, does not hold in general. The merchant's health was measured
recovering on its own from 67.4 to 79.7 with nothing done to him.

### What a beaten NPC actually does

Repeated across two runs, the second on a fresh reload with a baseline of
0.5378 on the victim and both controls:

1. Punched on foot, with none of this mod running, he flees.
2. The rider surrenders and the crime is settled.
3. He **returns to his own stall**. His daycycle is intact and he is not
   displaced permanently.
4. He flees again as soon as the rider approaches, and runs far enough to
   leave the streaming radius entirely.

So the assault does not break the NPC. It leaves him unwilling to be near the
player, which makes his shop unusable while it lasts.

Whether the relationship value is what drives the flee is inference rather
than measurement: two NPCs support it, one at `-0.0000` who fled and one at
0.7192, above baseline after the rider surrendered to him, who did not. The
value itself did not decay across four in-game days.

`soul:ModifyPlayerReputation(repChangeName, propagateToFaction)` is the lever
that would test recovery directly, but every reputation change name
recoverable from behavior data is a penalty, and the `reputation_change`
table's rows do not come back through the `Database` bind.

## The aversion triggers at six meters, and vanilla sells the cure

### The flee is a recognition reaction, not a permanent state

Sampled every two seconds while the rider walked in on a merchant beaten
several in-game days earlier:

| time | range | his speed | state |
|---|---|---|---|
| t+18 to t+24s | ~32 m | 0.00 | `ADLG_Speak`, `ADLG_Emphasis`, hawking his wares |
| t+34 to t+38s | 19 to 12 m | 0.74 to 0.89 | walking normally at his stall |
| t+42 to t+44s | 7.5 to **5.8 m** | **0.00** | `MotionIdle`, standing still |
| t+46s | 7.6 m | 1.95 | starts moving |
| t+48s | 16.9 m | **4.80** | full flight |

He is not avoiding the player across the town. He works his stall untroubled
until the rider is close enough to recognize, barks, and runs. That is why he
keeps returning and why he keeps being lost again.

### 0.2 is the threshold, and the game sells a way over it

`Scripts/Script/Crime.lua` carries the whole mechanism:

    function CrimeUtils.IncreasePayToTalkReputation (entity)
        local soul = assert(entity.soul, ...)
        for _ = 1, 4 do
            soul:ModifyPlayerReputation('payToTalk')
            if soul:GetRelationship(player.this.id, 'Current') >= 0.2 then
                return
            end
        end

with `CrimeUtils.CalcPayToTalkPrice` charging
`700 * persuadeToTalkWithLowReputationPriceMultiplier`, a multiplier defined
per social class in `Scripts/Script/SocialClass.lua` and ranging from 1 to 5.

Measured on a control: one `ModifyPlayerReputation('payToTalk')` moved
`GetRelationship` from 0.3948 to 0.5337, **+0.1389**, and the price for that
merchant read **2100**.

So an NPC beaten below the 0.2 threshold is recoverable by paying him, in two
applications from zero, and the shop is not lost. The rider's judgment that
Warhorse would not ship a permanent loss was correct, and several hours were
spent looking for a decay curve when the intended remedy is a transaction.

The one thing still unresolved is reaching the dialog at all, since the
aversion makes him run at about six meters.

### Note

`rat_merchant_shop2`, a control, was left 0.1389 higher than it started by
the proof above. A save reload restores it.

## The 0.2 threshold is real, and only a beating to submission goes under it

The resolving comparison. Both done on foot with none of this mod running,
both followed by surrendering and paying the fine.

| what the rider did | victim's relationship | against the 0.2 threshold | behavior |
|---|---|---|---|
| one punch on a shop guard | **0.2548** | **above** | back at his post `Leaning`, entirely normal |
| a merchant beaten to a yield | **-0.0000** | **below** | flees at about 6 m, will not deal |

So ordinary play is fine. A punch costs standing and leaves the victim above
the line where he still deals with the player. The failure appears only when
a victim is beaten all the way down.

### At zero, the game's own remedy has nothing to grip

`ModifyPlayerReputation('payToTalk')` behaves like this on a healthy NPC:

| apply | value | delta |
|---|---|---|
| start | 0.5337 | |
| 1 | 0.6726 | **+0.1389** |
| 2, 3, 4 | 0.6726 | +0.0000 |

It raises toward a ceiling near 0.67 and then does nothing, which is the
`reputation_cap` column of the `reputation_change` table.

Applied to the merchant sitting at `-0.0000` it moved him by **exactly
nothing**, not a smaller amount. Sending `combat:stimulus:standDownRequest`
and a daycycle restart first changed his animation state from `MotionTurn` to
`MotionIdle` but did not unblock the raise, so a live combat state is not what
gates it. His superfaction and perceived superfaction both read 3, matching
his own faction, so it is not a temporary hostile faction either. Every
variant of the read agrees: `GetRelationship` with the wuid, with
`this.id`, and with the `Current` and `Base` second arguments all return the
same figure.

What blocks it is unidentified. The `reputation_change` table carries a
`can_change_hostility` column and reputation names pick up a
`_noChangeHostility` suffix elsewhere, so hostility is tracked separately from
the number and is the leading suspect. The table's rows do not come back
through the `Database` bind, so the row for `payToTalk` could not be read.

### None of this is the mod's

Every measurement above was taken on foot with the mod uninvolved. What the
mod contributes is a victim willing to fight; the fists and the consequences
of them are the player's, and a player could reach all of it in vanilla.

### Correction: both merchant runs were a single punch

The entry above attributed the merchant's `-0.0000` to being "beaten to a
yield" and the guard's 0.2548 to "one punch". **That is wrong.** The rider
punched the merchant once, exactly as he punched the guard once. Both were
followed by surrendering and paying the fine, and the merchant run began from
a fresh reload with the victim and both controls at 0.5378.

So the corrected comparison is:

| victim | role | one punch, fine paid | drop |
|---|---|---|---|
| `rat_shop_guard_butcher` | security | 0.5378 to **0.2548** | 0.283 |
| `rat_merchant_shop3` | merchant | 0.5378 to **-0.0000** | 0.538 |

The same action cost the merchant roughly twice what it cost the guard, and
took him under the 0.2 threshold while the guard stayed above it. **Why is not
established.**

Social class does not explain it. `Scripts/Script/SocialClass.lua` carries
`persuadeToTalkWithLowReputationPriceMultiplier` per class, which prices the
remedy, but no multiplier on the penalty itself.

Candidates, none tested:

- the blow landed at a different `hit_melee_*` strength, which
  `sb_switch_hitreactions.xml` selects from `hit.strength` at thresholds of
  3, 4 and 6
- the two took different branches of the hit handler entirely, the guard
  being a soldier who arrests and the merchant a civilian who flees, and the
  civilian branch creating `assault` information the soldier branch does not
- the guard's encounter resolved, through the arrest, while the merchant's
  never did, and something continued to apply while he fled

The practical conclusion drawn in the entry above, that ordinary play is safe
and only a beating goes under the threshold, **does not hold** and is
withdrawn. A single punch put a merchant under it.

### Two effects, and the larger one is town-wide

Reading 34 humans within 50 m at the end of the session: mean relationship
**0.2346**, min -0.2501, max 0.6532, against a 0.5378 baseline measured
earlier the same evening.

**The whole town's standing with the player is sliding**, and it is sliding
for NPCs the rider never touched. `rat_shop_guard_general`, never assaulted,
went from about 0.54 to 0.2488 while the session ran. `rat_merchant_shop2`,
raised deliberately to 0.6726 by the `payToTalk` proof, read -0.1401 later.

So there are two effects and the larger is not the per-victim one:

- a personal penalty on the victim, real but smaller than earlier entries
  claimed
- a town-wide slide driven by the rider's accumulated crime record, which
  drags everyone toward the 0.2 threshold together

Every absolute comparison in the entries above is contaminated by the second.
The victim at the bottom of the distribution is not uniquely branded; he is
the low end of a population that fell. A playthrough that does not include a
night of assault testing would not see this.

### Shop guards are renegades, and renegades keep no grievance

`soul:GetSocialClass().SoulCrimeRoleId` reads **3** for the `security` class,
which the `crimeSystemRole` enum names **renegade**, not soldier. The renegade
branch of the hit handler in `sb_combat.xml` is the shortest of the three:

    if crimeSystemRole == renegade:
        t_state = fight, opponent = realAttacker

with no `CreateInformation label='assault'` anywhere in it. The soldier branch
creates one whenever the attacker is the player, and the civilian branch
creates one on the path where the victim declines to fight.

That is a concrete mechanical reason a shop guard leaves no lasting grievance
where a merchant or a villager, both `civilian` and both `SoulCrimeRoleId` 1,
does.

## Resolution: three effects stacked, and only one of them lasts

Jail was tested on the assumption it cleared something a fine does not. It
does not. Measured before seven days in jail and after, with a further punch
in between:

| | before jail | after jail and another punch |
|---|---|---|
| `rat_merchant_shop3` | **0.2314** | **0.2314** |
| three controls | 0.4259 | 0.4259 |

Identical. Jail moved nothing, and the victim was already above the 0.2
threshold before serving it. He traded normally afterwards, and would have
traded beforehand.

**The second punch cost nothing.** He was already at the floor for that
reputation change, which is the `reputation_cap` column: `hit_melee_*` pushes
a person down only so far, and repeat offenses against the same person do not
compound.

### What was actually happening

Three effects, mistaken for one another repeatedly across the session:

1. **A personal penalty**, about 0.22 below the victim's neighbors. Capped,
   does not compound, and did not decay over the spans measured.
2. **A large transient depression of the whole town's standing while a crime
   is unsettled.** This is what took a 0.54 baseline to a 0.23 mean and
   dragged NPCs the rider never touched down with it, `rat_shop_guard_general`
   from about 0.54 to 0.2488 among them.
3. **Recovery once the crime settles**, after which everyone returned to a
   shared 0.4259.

The victim fled because 1 and 2 together put him under 0.2. When 2 lifted he
cleared the threshold with the personal penalty still in place, and dealt with
the player again.

**Paying a fine does work.** It is not instant, and every observation of a
victim fleeing after a fine was made inside the window where the unsettled
crime was still depressing the town. Jail passed seven days, which guaranteed
the window had closed; a fine and some time reaches the same place. There is
no missing mechanism, and the earlier suspicion of a design oversight is
withdrawn.

### What this cost

Most of a session, because the absolute value was read as if it described the
victim when it mostly described the player's current standing with the town.
The gap against untouched neighbors was the correct instrument throughout and
was only adopted late.

### Correction: the jail comparison was two readings after jail

The entry above concluded that jail does nothing, from a pair of readings
described as before and after seven days served. **Both were taken after.**
The rider had already served when the first was run, so the pair shows only
that nothing changed between two post-jail moments, which is not the
comparison that was claimed.

Everything the entry infers from that pair is withdrawn:

- that jail moves nothing
- that the victim was already above the threshold before serving
- that the recovery to 0.4259 happened without jail
- that a fine and time reach the same place

The one measurement that survives is that a second punch cost the victim
nothing, since both readings bracket it. `hit_melee_*` has a floor per person
and repeat offenses against the same person do not compound.

**Whether jail clears something a fine does not is untested.** It needs the
A/B the rider proposed: punch, pay the fine, observe; then reload, punch,
serve the sentence, observe. Readings must be taken at each stage rather than
at the end, since the town-wide depression while a crime is unsettled moves
faster than the personal penalty and will otherwise be mistaken for it again.

That mistake, reading a pair of samples as a before and after when both fell
on the same side of the event, is the third time in this session that a
conclusion outran the measurement.

## Parked: what is known about assault aftermath, and what is not

The investigation stops here. The remaining question needs in-game time to
pass, and passing it is too expensive to be worth the answer: seven days
served in jail costs about ten real minutes of watching a wheel turn, and the
speed-up that made it bearable is `VF_CHEAT`, so it needs `-devmode`, which a
plain launch does not have.

### Established

- **A punch lowers the victim's own relationship with the player** and nobody
  else's, by an amount capped per person. A second punch on the same victim
  cost nothing.
- **An unsettled crime depresses the whole town at once**, including NPCs the
  player never touched, and this effect is far larger than the personal one.
  It lifts afterwards; the town returned to a shared 0.4259.
- **0.2 is the threshold** at which an NPC stops dealing with the player.
  `CrimeUtils.IncreasePayToTalkReputation` exists to lift someone over it,
  priced by `CalcPayToTalkPrice` at 700 times a per social class multiplier.
- **`payToTalk` raises by 0.1389 toward a ceiling near 0.67** and then does
  nothing, which is the `reputation_cap` column.
- **Shop guards are `renegade`**, `SoulCrimeRoleId` 3, and that branch of the
  hit handler creates no assault information at all, where the soldier and
  civilian branches both do.
- **The aversion is a recognition reaction at about six meters.** The victim
  works his stall untroubled until the player is close, then barks and runs.
- **None of it is this mod's.** Every measurement was taken on foot, and the
  final run was taken with every mod file parked and the `Mods` folder empty.

### Not established

- Whether serving a sentence clears something paying a fine does not. The A/B
  was set up and abandoned before the first reading.
- Whether the personal penalty decays over long spans. It did not move across
  the days measured, but every one of those measurements sat inside the
  town-wide depression and cannot be trusted.
- What blocks `payToTalk` on a victim at zero. Hostility tracked separately
  from the number is the leading suspect, from the `can_change_hostility`
  column and the `_noChangeHostility` suffix, and is unconfirmed.

### The methodological lesson

Three conclusions in this session outran their measurements: NPCs called stuck
from outside simulation range, a decay curve inferred from an absolute value
that was tracking something else, and a before-and-after pair where both
samples fell on the same side of the event. In each case the fix was the same
and was available from the start: **read the victim against untouched
neighbors, never the absolute number, and confirm which side of an event each
sample was taken on.**

---

## A shipped cheat mod contradicts five "unreachable" findings, and settles the assault question

`references/kcd1tools/cheat-106-1-58-*.zip` is spraguep's Cheat mod, Nexus
1.58. Unlike KCSE it is **pure Lua in a pak**, the same shape this project
ships, so every call in it is proof rather than a candidate. Its
`Cheat/Data/data.pak` holds twenty-three `Scripts/cheat_*.lua` files and a
`Docs/` folder.

Every entry point below was then **verified to exist in this build** by
probing the running game: 43 of 43.

### Time is directly settable, and the wait wheel is irrelevant

`Calendar` is a Lua global. Read at the main menu: `GetWorldTime()` returned
3,319,760 seconds, `GetWorldTimeRatio()` returned **15**, `GetWorldHourOfDay()`
10.16, `IsWorldTimePaused()` false.

    Calendar.SetWorldTime(Calendar.GetWorldTime() + hours * 3600)
    XGenAIModule.SendMessageToEntity(player.this.id, "timekeeper:recalculate", "")
    Calendar.SetWorldTimeRatio(1000)

Also `SetWorldTimePaused`, `SetFakeTimeOfDay`, `UnfakeTimeOfDay`,
`IsFakedTimeOfDay`.

This retires the conclusion that passing in-game time is too expensive to test
with. Seven days is one call. The 24-hour cap on the in-game wait dialog, and
the ten real minutes a jail sentence costs, are both bypassed entirely.

Note that `Calendar.GetWorldTimeRatio()` at 15 is the ordinary world time
ratio and is a different quantity from the CVar
`wh_pl_SkipTimeMaxWorldTimeRatio` at 360, which governs the skip dialog.

### The reputation change table reads, and it answers the assault question

Two mistakes had made this table look empty. `Database.LoadTable(name)` must be
called first, and the row count is **`LineCount`**, not `RowCount`. With both
corrected, `Database.GetTableLine(name, row)` returns a row keyed by column
name and `reputation_change` has **71 lines**.

The rows that matter:

| name | change | can_change_hostility |
|---|---|---|
| `hit_melee_weak` | **-0.2** | **true** |
| `hit_melee_medium` | -0.4 | true |
| `hit_melee_strong` | -0.7 | true |
| `hit_melee_brutal` | -1.25 | true |
| `surrender_step` | **+0.25** | **true** |
| `payToTalk` | +0.25 | **false** |
| `best_friend` | +2 | true |
| `sworn_enemy` | -2 | true |
| `crime_assault_individual` | -0.3 | false |
| `crime_assault_reported` | -0.3 | false |
| `death` | -0.6 | true |

The `_noChangeHostility` suffix seen in `sb_switch_hitreactions.xml` is not a
modifier applied at runtime: rows 96 to 99 are separate entries,
`hit_melee_weak_noChangeHostility` through `hit_melee_brutal_noChangeHostility`,
carrying the same numbers with the flag false.

**This explains every observation the assault investigation could not.**

- A punch is `hit_melee_weak`, -0.2, and it **sets a hostility flag**. The
  flag, not the number, is what makes the victim flee on recognition.
- `payToTalk` is +0.25 with `can_change_hostility` **false**. It can raise the
  number and cannot clear the flag. That is why applying it to a healthy
  control moved the value and applying it to the beaten merchant did nothing
  useful: the merchant's problem was the flag.
- `surrender_step` is +0.25 with the flag **true**. Surrendering to the victim
  is the designed repair, and it is the only common positive change that can
  clear hostility.

That is exactly what was observed and could not be explained: surrendering to
a provoked victim resolved the encounter completely and left the beggar at
0.7192, above his neighbors, while paying a guard a fine never repaired
anything. The fine settles the crime; only the victim can lift the hostility,
and surrendering to him is how.

A ruined NPC should therefore be repairable with
`soul:ModifyPlayerReputation('best_friend')`, +2 with the flag true, or more
proportionately with `surrender_step`. Untested.

### `angriness_enum` also reads

Nine lines: `min_angriness` 0, `max_angriness` 1, `death` 0.55,
`unatributedStealthKill` 0.15, `event_roadsideCorpse_unsolvedMurder` 0.2,
`theft_large` 0.125, `theft_medium` 0.025, `theft_small` 0.01. So the
angriness scale is 0 to 1 as measured, and the increments real events apply
are small. Setting a faction to 1.0 was far outside anything the game does.

### Entity links exist in Lua after all

`Entity.CreateLink`, `Entity.GetLink`, `Entity.RemoveLink` and
`Entity.CountLinks` are all present. The earlier finding that "no script bind
exposes links to Lua, all 37 carry only readers" was drawn from the
`C_ScriptBind*` headers and is **wrong**: the entity class table carries them.

Whether these reach the behavior tree's tagged links, which is what
`checkAssaultSuppression` walks for a `suppressAssaultReactions` tag between
attacker and victim, is **not established**. CryEngine entity links take a
name and a target id; the behavior tree's take From, To, Tag and Data. They
may be the same system or two systems sharing a word. Testing it reopens the
brawl a town ignores, which was closed as impossible.

### Mass is readable, which matters for knockback

`ent:GetPhysicalStats()` returns a table with `mass`, `gravity` and `flags`;
the player reads mass 80. The cheat mod applies impulses as
`ent:AddImpulse(-1, pos, dir, ent:GetPhysicalStats().mass * force)`, scaling by
mass so the result is a velocity rather than an arbitrary number.

The armor knockback item has been stuck on exactly this: a shipped `Knockback`
of 50 was measured as indistinguishable from applying nothing to a 120 to
160 kg body. Scaling by the target's own mass makes the figure mean meters per
second, and armor weight can modulate a velocity rather than guess at a force.

### Console commands can be registered from Lua

`System.AddCCommand(name, "table:method(%line)", help)` registers a real
console command backed by Lua, `%line` receiving the arguments. The cheat mod
registers about eighty this way, including a `cheat_eval` that runs
`loadstring` on its argument.

`System.ExecuteCommand("...")` runs a console command from Lua, and
`System.SetCVar` / `System.GetCVar` reach CVars directly. `System.SetCVar` was
observed setting `wh_pl_SkipTimeMaxWorldTimeRatio`, a `VF_CHEAT` variable,
from 360 to 3600. **That test is not conclusive**: the session had `-devmode`,
which would have allowed it anyway. Whether Lua bypasses the flag without
`-devmode` is untested and matters, because it decides whether a development
console command can replace the `-devmode` requirement for probing.

### Everything else confirmed present

`Game.SetWantedLevel`, `Game.SaveGameViaResting`, `Game.RemoveSaveLock`,
`Game.IsLoadingEngineSaveGame`, `Physics.RayWorldIntersection`,
`Framework.IsValidWUID`, `EnvironmentModule.BlendTimeOfDay`,
`EntityModule.GetInventoryOwner`, `Shops.IsLinkedWithShop`,
`System.SpawnEntity`, `System.GetEntitiesByClass`, `Entity.AddImpulse`,
`Entity.SetPhysicParams`, `Entity.AwakePhysics`, and `actor:ReviveToDefaults`.

`Game.SetWantedLevel(0..3)` is the crime state this project could not even
read, and it would have separated the transient town-wide depression from the
personal penalty in one command.

### Why this was missed

The `C_ScriptBind*` headers in `references/libKCD1` describe the **script
binds**. `Calendar`, `Game`, `Database`, `Entity` and `Physics` are reached
another way and are not among them, so a survey of those headers cannot answer
"what can Lua call". It answers "how is this bind declared", and it is not
always right about that either: the header gives
`AddReputation(const char* sEnumName)` while the cheat mod passes a number.

The order to consult is now the cheat mod for what Lua can call, the
decompilation for what the binary contains, and libKCD1 for how a bind is
declared.

## Second pass: the actor surface, and a native horse pull-down

Reading the cheat mod pointed at a broader question, which is what the entity
methods vanilla itself uses actually are. Gathered from `vanilla_scripts/`
rather than from the reverse-engineered headers, because the headers cover
script binds and these are reached another way.

**Eighty-odd `actor:` methods and twenty `human:` ones**, of which this mod
uses six. The ones that bear on open work, none tried here:

- `actor:StandUp()` and `actor:IsUnconscious()`. Both would have replaced
  improvisation: the stuck-NPC repairs reached for a stand-up through a
  stand-down message and a daycycle restart, and `IsDead` was probed and
  failed where `IsUnconscious` exists.
- `actor:SetMovementTarget(...)`, which sends an actor somewhere directly
  rather than asking the daycycle to replan and hoping.
- `actor:RequestKnockOut()`, an ending for a brawl that is neither a death nor
  a yield.
- `actor:HolsterItem` and `actor:UnequipInventoryItem`. Vanilla's `Crime.lua`
  holsters the **player's** weapon during a confrontation with the second of
  these. Taking a victim's weapon out of his hand is a route to an unarmed
  brawl that does not need `combat:order`'s unregistered `restrictWeaponKind`,
  which is what closed that item.
- `actor:CameraShake` and `actor:SetViewShake`. A collision currently costs
  the rider a number they cannot see. Neither has ever been considered.
- `actor:GetArmor()`, which reads armor directly where `Armor.lua` sums it out
  of the item tables.

### Horse pull-down is already in the game

`BasicAIActions.lua` offers it as an interactor action beside knockout and
hunt attack:

    local canPullDown = user.actor:CanHorsePullDown(self.id)
    user.actor:RequestHorsePullDown(self.id)

hinted `@ui_hud_horse_pulldown`, interaction `inr_pullDown`, with
`wh_cs_HorsePullDownAngle`, `wh_cs_HorsePullDownZAngle` and
`wh_cs_HorsePullDownZeroAngle` governing the geometry.

In vanilla the player pulls a mounted NPC down. Whether the roles can be
reversed is untested. If they can, an NPC dragging the rider off the horse is
native, and it is both the braced-polearm item and the strongest form of a
victim fighting back.

### The AI has rider-specific combat behaviour

A combat action type group in the binary carries forty-six names, among them
`freeRiderAttack`, `freeRiderAttackStatic`, `groupRiderAttack`,
`groupRiderMovement`, `riderGuardIdle`, `riderGuardMovement`,
`riderGuardFastStop`, `riderGuardJump`, **`riderGuardRear`**,
`horsePullDownAttackSuccess` and `horsePullDownHitSuccess`.

These are behavior and animation identifiers, not Lua entry points, so they
are not callable as they stand. What they establish is that combat against a
mounted target, and mounted combat including a rear, are things the game
already has written. The roadmap item about a heavy impact rearing the horse
has a named behavior behind it rather than only a fragment.

## `MessageTypes.xml` is not a whitelist, and two closures rested on reading it as one

`Libs/AI/MessageTypes.xml` holds **41 entries**, each carrying an
`ImportanceLevel` or an `IsContextRelated` attribute. Absence from it was
twice treated as evidence that a message cannot be sent from Lua.

That is wrong, and this mod disproves it every time a victim recovers.
**`daycycle:restartRequest` does not appear in that file**, and
`Recovery.lua` sends it through `XGenAIModule.SendMessageToEntityData` with a
payload built by `Utils.makeTable`. It works, and it was measured: an empty
payload moved a parked victim 0.00 m and a filled one moved him 3.94 m back to
his stall.

The file configures properties for the messages that need non-default ones.
Everything else takes defaults. It says nothing about deliverability.

### What that reopens

- **Forcing an unarmed brawl.** `combat:order` carries a `restrictWeaponKind`
  sub-order taking `weaponChange.unarmed`, and was set aside partly because
  the type is not registered. It may well be sendable.
  `human:HolsterWeapon()` is still the simpler route and should be tried
  first, but the reasoning that closed this one was unsound.
- **The duel and sparring system.** `sa_duel.xml` carries
  `duel:startDuelWithPlayer` with a bet, a difficulty, `isWooden`, and
  `enemyWeapons` from an enum that includes `Unarmed`, and it ends cleanly
  through `duel:stopDuel` carrying a winner. That was closed with "none of the
  `duel:` types appear in `MessageTypes.xml`, so they are almost certainly
  local to the scripted action". Only the second half of that sentence is
  still worth testing, and it needs testing rather than asserting: whether an
  NPC not running `sa_duel` has anything listening.
- **Behavior patches.** `daycycle:patch` is a message type used in the
  behavior XML and absent from `MessageTypes.xml`, and
  `XGenAIModule.RemoveDaycyclePatch` is a real Lua bind, so removal is
  reachable. Whether a patch can be added by message is untested, and it is
  the route to `man_chase`, the pursuit behavior closed as unreachable.

### The general lesson

Three separate closures in this project rested on a written artifact being
read as more authoritative than it is: the `C_ScriptBind*` headers taken as
the whole Lua surface, `MessageTypes.xml` taken as a whitelist, and
`GetTableColumnData` returning nothing taken as a table being empty. In each
case the artifact answered a narrower question than the one being asked.

The check that would have caught all three is the same: **try it in the
running game.** A probe costs a minute.

### Confirmed: the unregistered types are all constructible

Tested against the running game. `Utils.makeTable` builds every one of them:

    combat:order                          ok
    daycycle:patch                        ok
    duel:startDuelWithPlayer              ok
    combat:fightOptions                   ok
    combat:stimulus:standDownRequest      ok
    daycycle:restartRequest               ok
    combat:stimulus:hostilePerception     ok

Four of those seven were set aside on the grounds that they are absent from
`MessageTypes.xml`. The type system knows all of them, because
`Utils.makeTable` validates against **`TypeDefinitions.xml`**, which is the
registry that matters. `MessageTypes.xml` was never it.

Constructing a message is not the same as a tree listening for it, and that
half still needs a target in a loaded world. But "it cannot even be built or
addressed" is finished as a reason to close anything.

## Live verification in a loaded world

The game running with `-devmode` and a save loaded, 32 humans nearby, the
rider mounted.

### Weapons: an unarmed brawl is solved

    villageGuard  IsWeaponDrawn  false
    human:DrawWeapon()    -> drawn=true   inHand=020000000000FC2A
    human:HolsterWeapon() -> drawn=false  inHand=0000000000000000

Both calls work on an NPC and the state reads back correctly. Forcing a
provoked brawl to fists needs no `combat:order`, no `restrictWeaponKind` and
no behavior tree node: holster the victim's weapon before provoking, and
`DrawWeapon` restores it afterwards. That item was closed for want of a
mechanism it did not need.

### Entity links are real, creatable, and retrievable by tag

    subject links before = 2      (NPCs already carry links of their own)
    e:CreateLink("suppressAssaultReactions", player.id)  -> ok
    subject links after  = 3
    e:GetLinkTarget("suppressAssaultReactions") -> the player table

The signatures, established by probing: `CountLinks()` takes nothing,
`GetLink(index)` returns the linked entity, `GetLinkTarget(name)` returns the
entity a named link points at, and `GetLinkName(index)` returns nil in this
build. `CreateLink(name, targetId)` is the writer.

So a link carrying exactly the tag `sa_duel.xml` uses, pointing from an NPC at
the player, can be created from Lua and read back by name. **Whether the
behavior tree's `checkAssaultSuppression` reads the same store is the
remaining question**, and it is a question rather than a closed door, which is
where this stood before.

### Mass and armor are not what they looked like

`GetMass()` reads **80 for every human including the player**, so it is the
character controller's mass rather than a body's, and it does not distinguish
an armored target from a villager. `actor:GetArmor()` and `GetMaxArmor()` both
read 0 on NPCs.

That tempers the knockback plan. `SetVelocity` still states an outcome in
meters per second rather than a force, which is the substantive improvement,
but mass cannot be used to scale by build and armor still has to come from the
item tables as `Armor.lua` already does.

### Horse pull-down is not offered to an NPC as things stand

`npc.actor:CanHorsePullDown(playerId)` returned **0** for every human nearby,
against the constants `HPS_Enabled = 2` and `HPS_Disabled = 1`. Vanilla's own
check offers the action only when the answer is one of those two, so 0 means
not applicable at all.

The rider was mounted at the time, which is the scenario that would make it
applicable, so this is not simply a matter of the player being on foot. It may
still depend on range or facing, which `wh_cs_HorsePullDownAngle` and its two
companions govern, and that is untested. `Game.GetWantedLevel` does not exist;
only the setter does.

### The entity link does not suppress the assault, and the test was sound

Every human within 35 m was given a link named `suppressAssaultReactions`
pointing at the player, 33 of them, and the rider then rode a civilian down at
trot in a public place. **A crime was reported.**

The result was checked for the obvious confound. Seventeen further humans had
streamed in since the links were placed and carried none, so the victim might
have been one of those. He was not: the mod's telemetry names `rat_man97`, and
read back afterwards he carried three links with
`GetLinkTarget("suppressAssaultReactions")` returning the player.

So a link created through `Entity.CreateLink` is **not** the object
`checkAssaultSuppression` walks. Two explanations fit and neither is tested:
the behavior tree keeps its own link store, or the tree's links carry `Data`
that this one lacks. `questUtils.xml` sets
`$suppressAssaultReactions.expiration` on the link through a
`LinkDataExpression`, and the behavior tree's `AddLink` has a `Data` attribute
where `CreateLink(name, targetId)` has no equivalent, so a dataless link may
be read as expired or ignored.

The item closes again, but on evidence this time rather than on a
misreading of which headers describe what. All 23 test links were removed.

### `SetVelocity` is the knockback mechanism this mod has wanted

On a living, animation-driven NPC, `SetVelocity({0, 0, 6})` lifted them
**0.86 m** within 700 ms before they came down. That alone is notable: this
mod's own notes record that physics impulses are ignored because actors are
animation-driven, and a velocity is evidently not.

On a ragdolled victim, 6 m/s away from the rider:

| | traveled |
| --- | --- |
| t+900ms | **4.43 m** |
| t+2500ms | 5.57 m |
| t+5000ms | 5.53 m, at rest |

Six meters per second carried a body five and a half meters and the damping
already in the mod brought it to rest. Against `Knockback = 50` being
indistinguishable from applying nothing and `600` throwing a villager 27
meters, that is a number a person can choose deliberately.

The victim was returned to the `alive` profile and replanned.

### `best_friend` repairs a relationship

`soul:ModifyPlayerReputation('best_friend', false)` moved a bystander from
0.5048 to **0.7826**, a delta of +0.2778.

The table row says the change is +2, so the applied figure is normalized
rather than added raw, the same way `payToTalk` reads +0.25 in the table and
applied +0.1389. What matters is the direction, the size relative to a punch's
-0.2, and that this row carries `can_change_hostility` true, which is what a
beaten victim needs and what `payToTalk` cannot give.

That NPC was left 0.278 better disposed than found, which is a benefit rather
than damage and was not reverted.

### Correction: LDoc was broken by the version tool, not by the enum tables

An earlier entry recorded that adding a third and fourth table to
`Enums.lua` made LDoc fail with `'class' cannot have multiple values;
{module,table,module}`, and that the fix was to move `CombatAttackKind` beside
its consumer and delete the unused `CrimeSystemRole`. **That diagnosis was
wrong.**

The cause was `tools/set_version.py`, written in the same session. Its
substitution read

    re.sub(r"^(-- @release\s+)\S+\s*$", ..., flags=re.M)

and `\s` matches newlines, so `\s*$` ran past the end of the line and consumed
the blank line separating the module header from the doc block below it. LDoc
reads the two as a single block, sees a module tag and a table tag and a
module tag, and fails.

The bump to 4.6.3 reproduced it exactly, on a file whose tables had not been
touched since the supposed fix. The regex now matches horizontal whitespace
only.

Two things follow. The move of `CombatAttackKind` into `Crime.lua` was not
necessary; it is kept because sitting beside its only consumer is better
placement regardless, but the reason given for it was false. And the test that
"proved" the tables were at fault, removing them and seeing the failure
persist, was correct evidence that was then read the wrong way round: it
should have ruled the tables out rather than being set aside.

## Setting a victim's mass before the collision

`Reaction:MassVictim` writes `PHYSICPARAM_SIMULATION` with a `mass` of
`RagdollMass / armorScale` on a rung schedule of 0, 16, 33, 50, 80 and 120 ms,
stopping at the first write that reads back. It runs before the impulse and
the damping, because it is the only one of the three that has to beat the
horse's own collision rather than follow it.

### The write beats the collision

Sixteen gallop impacts, every one of them taken:

| rung | impacts | victim had moved |
| --- | --- | --- |
| 0 ms | 1 | 0.00 m |
| 16 ms | 15 | 0.01 - 0.08 m |

No impact needed a third rung. Guards were carried to 192 - 217 kg and
villagers down to 63 - 85 kg from the engine's flat 80 for every human. The
timing question is settled: a victim's mass can be changed while the body is
still within eight centimeters of where it was standing.

### It changes the throw, but not in the direction momentum predicts

Twenty-one gallop impacts carrying a confirmed mass, against seventy on the
shipped impulse path from the same log, measured at the settled distance of
t+6s rather than mid-flight. Mean approach speeds were 7.26 and 7.64, so the
two pools are comparable.

| path | mean throw | armored | plain | ratio |
| --- | --- | --- | --- | --- |
| impulse, mass untouched | 3.76 m | 4.52 m | 3.12 m | 1.45x |
| impulse plus mass | 2.17 m | 2.17 m | 2.18 m | 1.00x |

Correlation of armor scale against settled throw falls from -0.247 to -0.002,
and from -0.297 to -0.039 with approach speed partialed out.

Two things happened, and neither was the intended one. Every victim traveled
less, and the spread between armored and unarmored collapsed to nothing.

The decisive detail is the villagers. They were made **lighter** than the
engine's default, 63 to 85 kg against 80, and they were thrown **shorter**,
3.12 m down to 2.18 m. Momentum transfer predicts the opposite: a lighter body
struck by a 480 kg horse should leave faster and travel further. A uniform
shortening that ignores the sign of the mass change is not a collision
responding to mass. It is more consistent with the write settling the body,
the same family of effect as the damping and `min_energy` this mod already
sets through the same parameter block.

So the mechanism works and the lever moves the outcome. What has not been
shown is that it moves it through the collision.

### A discriminating test

Set a flat mass well below the default, the same figure for every victim
regardless of armor, and ride. Momentum transfer predicts throws longer than
the 3.76 m baseline. A settling artifact predicts the same shortening seen
here, because the direction of the change would not matter. One ride separates
them, and nothing else about the reaction needs to change.

### Armor already governs the throw, opposite to the intent

The seventy shipped-path impacts carry an armor signal that is real and points
the wrong way. **Armored victims travel 45% further**, 4.52 m against 3.12 m,
and the effect survives controlling for approach speed at a partial
correlation of -0.297.

The mod's own armor scaling works against this. `armorImpulse` runs from about
0.37 for a mailed guard to 1.26 for a villager in cloth, so an armored victim
is given roughly a third of the impulse a villager gets, and still outflies
them. That is the clearest statement yet of a conclusion this project reached
by other routes: the impulse is not what carries a body, and the collision
between the horse and the victim is doing work the mod does not control.

What is new is that the collision is not blind to armor. Something about an
armored body already produces a longer throw. The cause is not established
here; the correlation is measured across seventy impacts and is not an
artifact of speed.

## Contact geometry decides more of the throw than speed does

The detection log already carries the geometry of every accepted collision.
`Footprint fwd= lat= dz= sweep=` is written on the tick the victim is found,
`fwd` being distance along the horse's facing and `lat` the perpendicular
offset, so `lat` near zero is a victim square in front of the chest and `lat`
near the limit is one clipped by the shoulder.

117 gallop impacts carry both a footprint reading and a settled throw at t+6s.

### The lateral offset costs half the throw

Restricted to full gallop, where approach speed is effectively constant across
the bands:

| lateral offset | impacts | mean throw | mean speed |
| --- | --- | --- | --- |
| 0.00 - 0.12 | 9 | 4.87 m | 10.43 |
| 0.12 - 0.22 | 20 | 4.84 m | 10.64 |
| 0.22 - 0.36 | 8 | 3.15 m | 10.43 |

Centered against clipped is 4.85 m against 3.15 m, a factor of 1.5 at the same
speed. The partial correlation of lateral offset against throw, with speed
held out, is -0.258.

### Forward distance matters more, and is not only speed

`fwd` correlates with speed at +0.808, because the front reach is extended by
`speed * TickSeconds * SweepMultiplier` and a faster horse therefore finds its
victim further ahead. It survives that: the partial correlation with speed
held out is +0.312, and in the regression below it is the largest term.

A large `fwd` is a victim still out in front when the tick fires, whom the
horse then runs into chest first. A small `fwd` is a victim already beside the
horse, brushed in passing.

### Weighing the terms against each other

Least squares on all 117 impacts, `R^2 = 0.313`, effects given as meters per
standard deviation of each term:

| term | effect |
| --- | --- |
| forward distance | +0.79 m |
| lateral offset | -0.54 m |
| armor scale | -0.34 m |
| mass was set | -0.30 m |
| approach speed | +0.25 m |

Geometry is worth roughly 1.3 m of spread between a square hit and a glancing
one. Speed, once geometry is accounted for, is worth 0.25 m. That ordering is
the opposite of the assumption the tier system is built on.

The model is weak in absolute terms and honestly so. At full gallop `R^2` is
0.174 and the residual spread is 1.96 m against an actual spread of 2.16 m, so
most of the variation is still unexplained. The footprint is read one tick
before contact and is a coarse stand-in for the geometry of the collision
itself, which is never measured.

### Correction to the mass reading

The earlier entry compared 21 mass impacts against 70 and reported a mean
throw of 2.17 m against 3.76 m. Pairing more permissively recovers 47 mass
impacts, and the comparison is then **3.00 m against 3.76 m**. The two pools
have comparable geometry, mean lateral offset 0.154 against 0.136 and edge
contacts 25.5% against 20.0%, so the difference is not a geometry artifact.

With geometry, speed and armor all held out, setting the mass is worth -0.30 m
per standard deviation, the smallest of the five terms. The effect is real,
uniform, and small. It remains true that it did not differentiate by armor,
which was the point of setting it.

### Why a clear contact sometimes produces nothing

The footprint is a box in the horse's frame, not a cone or a radius:

| bound | value |
| --- | --- |
| front reach | 1.05 m, plus up to 0.35 m of sweep with speed |
| rear reach | 0.20 m |
| half width | 0.35 m |
| vertical | 2.35 m |

The corridor is **0.70 m wide and 0.20 m deep behind the origin**. A horse's
body is wider than that before its legs are counted, and a victim has a radius
of its own, so the surfaces meet while the centers are still well over 0.35 m
apart. There is a band of genuine physical contact, roughly 0.35 m to 0.7 m of
lateral offset, in which the engine collides and the mod does nothing. What
the rider sees is a vanilla shove with no stagger, no fall and no ragdoll.

The rear bound has the same shape of problem. Turning tightly puts the victim
beside or behind the horse's origin, past the 0.20 m rear reach, while contact
is still being made along the flank.

Accepted impacts bear this out at the edge: of 117, only 6 fall in the last
0.06 m of the corridor, where a uniform distribution of approaches would put
many more. The corridor is clipping approaches, not merely bounding them.

Rejections are logged only when `DiagnoseMisses` is on, and it has been off,
which is why none of these appear in any log gathered so far. It is now on.

## Correction: mass does reach the collision

The flat-mass ride reverses the earlier reading. Setting `RagdollMass = 40`
with `RagdollMassArmorScaled = false` gives every victim the same 40 kg, half
the engine's figure for a human, which is the only configuration that shows
the direction of the effect.

130 gallop impacts across the three conditions carry footprint geometry and a
settled throw at t+6s. Each is labeled by its own `Mass` log line rather than
by when it was recorded, so a reload in the middle of a session cannot
mislabel it.

Restricted to full gallop, where approach speed and contact geometry are
closest to comparable:

| mass | impacts | mean throw |
| --- | --- | --- |
| flat 40 kg | 20 | **5.26 m** |
| untouched, 80 kg | 37 | 4.48 m |
| armor scaled, 63 - 217 kg | 8 | 3.28 m |

The ordering is monotonic in mass and it is the ordering momentum transfer
predicts. Halving the mass adds 17% to the throw. In the regression across all
130 impacts, mass carries a coefficient of -0.0138 m/kg, which over the 40 to
217 kg range actually used is 2.44 m of swing, standing beside lateral offset
at -0.66 m and armor scale at -0.71 m per standard deviation.

### Why the earlier entry got it backwards

The previous reading compared the armor-scaled condition against the untouched
one and concluded that mass produced a uniform shortening unrelated to the
sign of the change, which would have made it a settling artifact rather than a
collision term.

Two errors produced that. The full-gallop sample for the flat condition was
taken from a single segment of the log and held three impacts; labeling by the
`Mass` line recovers twenty. And the armor-scaled condition is not a test of
direction at all: it made guards much heavier, from 80 to between 192 and 217,
while making villagers only slightly lighter, from 80 to between 63 and 85. The
mean of that is heavier, so the mean throw fell. Reading it as "everyone got
shorter regardless of direction" mistook an asymmetric treatment for a
symmetric one.

The villager half of that condition was the piece of evidence that looked
decisive and was not. Villagers at 63 to 85 kg are barely below 80, and the
throw difference across that narrow band is far smaller than the spread
contributed by contact geometry, which was not controlled at the time.

### What the armor-scaled result actually showed

It did what it was built to do. Armored victims on the shipped path travel 45%
further than unarmored ones, and scaling mass by armor removed that advantage:
the armored-to-plain ratio went from 1.45x to 1.00x. That is the mechanism
working, not failing. It neutralized the gap rather than reversing it because
the scaling was sized to reach parity, not to overshoot it.

Making armor visibly resist a horse is therefore a matter of scaling harder,
and the lever is known to work across at least 40 to 217 kg.

## The detection corridor is narrower than the horse

`DiagnoseMisses` recorded 115 rejections during the ride. Sorting them by
which bound rejected them separates a real defect from two harmless ones.

| rejected by | count | consequence |
| --- | --- | --- |
| width, while in range front to back | 34 | the defect |
| front reach, while inside the width | 13 | harmless, the next tick brings them closer |
| rear reach, while inside the width | 1 | a body already on the ground, `dz` -1.00 |
| both axes | 67 | not a contact |

Eight of the width rejections sit within a plausible contact width, lateral
offset between the 0.35 m limit and 0.80 m:

| victim | forward | lateral |
| --- | --- | --- |
| a village guard | 0.10 | 0.73 |
| a village guard | 0.13 | 0.69 |
| a village guard | 0.21 | 0.67 |
| a guard | 0.26 | 0.65 |
| a refugee | 0.24 | 0.79 |
| a woman | 0.67 | 0.74 |
| a woman | 1.39 | 0.63 |
| a village guard | 1.04 | 0.80 |

A forward distance near zero with a lateral offset of 0.7 m is a body directly
alongside the horse's flank. A horse and a person cannot both occupy that
space without touching, so these are contacts the engine resolved and the mod
declined to see.

The rear reach and the sweep are exonerated. One rejection in the whole ride
was past the rear bound, and it was a corpse a meter below the horse. At 0.1 s
per tick and 10.7 m/s the horse advances 1.07 m between samples against a
window 1.60 m deep, so nothing is tunneling through.

### The lockup this explains

`SuppressAutoCure` is called from `TriggerCollision`, which runs only after
the footprint test passes. A victim the footprint rejects is therefore struck
by the engine, can lose health to that collision, and never receives the
exemption that keeps vanilla's auto-cure daycycle from taking them over.

That daycycle is what stands a victim in the street playing
`PretendingIllness`, and avoiding it is the reason the suppression exists. So
the width defect does not merely lose a reaction; it produces exactly the
lockup the suppression was written to prevent, on the victims the mod never
registered.

This follows from the call order and matches a rider's report of a guard that
produced no reaction and afterwards behaved as though auto-cured. It has not
been reproduced deliberately.

## Base mass cannot move the armored-to-unarmored ratio

Base 40 with armor scaling on was ridden to test whether halving the base
would overshoot parity and leave armored victims visibly harder to move. It
did not, and the reason is arithmetic rather than physics.

Forty gallop impacts were recorded, 23 of them above 8 m/s. Restricted to
those, and with one terrain-launched impact excluded for the reason given
below:

| condition | n | mean throw | median |
| --- | --- | --- | --- |
| armored | 12 | 3.39 m | 3.13 m |
| unarmored | 10 | 3.59 m | 3.70 m |

The armored-to-unarmored ratio is 0.94x by mean and 0.85x by median, against
1.00x measured at base 80. A Mann-Whitney test over the two groups gives
p = 0.64, so this sample cannot distinguish the two conditions from each other
or from parity. A least-squares fit over the same 22 impacts puts armor at
-0.06 m per standard deviation, against +0.25 m for forward contact distance;
armor is the weakest term in the model and `R^2` is 0.052.

### Why the base was never going to change it

The mass written is `base / armorScale`. The ratio between an armored victim's
mass and an unarmored one is therefore `scaleUnarmored / scaleArmored`, and the
base cancels out of it entirely.

| base | guard at scale 0.37 | villager at scale 1.26 | ratio |
| --- | --- | --- | --- |
| 80 | 216 kg | 63 kg | 3.4x |
| 40 | 108 kg | 32 kg | 3.4x |

Both conditions present the horse with the same 3.4x mass ratio and differ only
in absolute mass. Reproducing parity was the expected outcome, not a surprise.

**The base sets how far everyone travels. Only the spread of the armor scale
sets how far armored victims travel relative to unarmored ones.** Scaling
harder means widening that spread, which the current formula has no term for.

### What the base did change

Absolute throws moved in the direction momentum transfer predicts. Against the
shipped path, where armored victims travel 4.52 m and unarmored 3.12 m,
lightening every body to a third of the engine's figure brought armored victims
down to 3.39 m and lifted unarmored ones to 3.59 m. Both halves moved the right
way. The gap between them did not open.

### The impact excluded, and why

One refugee traveled 14.36 m, three times the next largest throw in the set.
It is a real launch rather than a parse error: the footprint recorded `dz`
-0.90, so the horse was most of a meter above the victim, the body moved 5.90 m
in the first 300 ms and rose 1.14 m by the half-second sample. It is terrain
geometry, not mass, and with n around ten per group it carries the comparison
on its own. Including it moves the ratio to 0.74x with p = 0.42, which reads as
an effect and is one impact wide.

## Squaring the armor spread does not separate the victims either

`RagdollMassArmorExponent` was added to widen the gap the base could not, and
ridden at base 40 with an exponent of 2. That squares the armor scale before
the division and takes the spread between an armored victim and an unarmored
one from 3.4x to 11.6x, putting guards at 230 to 327 kg and villagers at 25 to
30. The masses were confirmed live before the ride and every write took, all
but two at 16 ms.

The ratio did not move. Armored victims traveled 0.90x as far as unarmored
ones, against 0.94x at an exponent of 1. Tripling the mass of every guard and
squaring the spread between the two groups changed the measured separation by
0.04x.

### The same-armor comparisons run backwards

Comparing victims wearing the same armor across the two conditions removes the
armor confound entirely, and both comparisons move the wrong way.

| group | condition | mass | n | mean throw |
| --- | --- | --- | --- | --- |
| armored | exponent 1 | 73-114 kg | 12 | 3.39 m |
| armored | exponent 2 | 155-295 kg | 6 | 3.69 m |
| unarmored | exponent 1 | 32-42 kg | 11 | 4.57 m |
| unarmored | exponent 2 | 25-35 kg | 9 | 4.01 m |

Nearly tripling an armored victim's mass lengthened the throw by 0.30 m.
Lightening an unarmored victim shortened it by 0.56 m. Momentum transfer
predicts the opposite of both. The standard deviations are 1.4 to 3.5 m, so
neither difference is distinguishable from zero; that is the point. These are
the fingerprint of noise, not of a lever.

### Pooled across every condition, mass does not predict the throw

Sixty-seven full-gallop impacts with a mass write and near-level contact,
spanning 25 to 295 kg over four conditions, regressed on log mass with contact
geometry and approach speed controlled:

| term | effect | p |
| --- | --- | --- |
| ln(mass) | -0.47 m per sd | 0.260 |
| forward distance | +0.44 m per sd | 0.306 |
| lateral offset | +0.04 m per sd | 0.919 |
| approach speed | +0.45 m per sd | 0.287 |

`R^2` is 0.052. Nothing measured reaches significance and the model explains
five percent of the variance, so 95% of what decides a throw is not being
recorded by any instrument this mod has.

The binned means do fall with mass, from 4.80 m below 35 kg to 2.44 m above
250, and that is the shape the earlier reading rested on. It does not survive
controlling for geometry, and it is carried by the unarmored band, which is
also the band with the most samples.

### What this does and does not establish

It does not re-open whether the mass write reaches the collision. It does, at
16 ms, with the victim still centimeters from where they stood.

What it establishes is narrower and more useful: **no setting of the base or
the exponent produces a visible difference between an armored victim and an
unarmored one.** The test was not powered to resolve a small effect, but it did
not need to be. An armor difference worth shipping would be obvious at an 11.6x
mass spread, and at that spread the ratio is 0.90x.

### A methodological check that came back clean

Before drawing any of this, `travel` was checked for measuring locomotion
rather than the throw, since recovery runs about 5.9 s and a victim who stands
up keeps accumulating distance. Across 136 gallop impacts the body is at rest
by three seconds and stays there: the median change from t+3000 to t+6000 is
-0.08 m, and 15% of victims move more than half a meter.

The t+10000 sample is a different matter. It gains 2.08 m on average and 61% of
victims move more than half a meter, because by ten seconds they are up and
walking. **t+6000 is the correct sample and t+10000 must not be used for
throw distance.**

## Correction: mass is a working lever, and it is very weakly coupled

A flat 2000 kg for every victim, armor scaling off, ridden against the existing
flat 40 kg control. This is a 50x change in mass with no armor confound on
either side, and it moved the throw.

| condition | n | mean | median | sd | range |
| --- | --- | --- | --- | --- | --- |
| flat 40 kg | 23 | 5.01 m | 3.75 m | 4.54 | 1.03-22.89 |
| flat 2000 kg | 13 | 2.43 m | 1.93 m | 1.41 | 0.59-5.36 |

The ratio is 0.48x by mean and 0.51x by median, at p = 0.012 on a rank test,
which is robust to the one 22.89 m outlier in the control. The two groups are
matched on everything else that matters: mean forward contact distance 1.17
against 1.10, mean lateral offset 0.14 against 0.13, mean approach speed 10.49
against 10.50 m/s. The difference is mass.

**The conclusion recorded in the previous entry was wrong.** Mass is not inert
and the lever is not dead. The earlier rides did not fail because mass does
nothing; they failed because they were run across a range far too narrow to
show anything.

### The coupling is a weak power law

Two flat conditions 50x apart, with the throw halving between them, give:

    throw is proportional to mass ^ -0.185

That is an extremely compressed response. Doubling a victim's mass shortens the
throw by 12%. Every earlier ride worked inside a 3.4x or 11.6x spread, which
this predicts is worth 21% and 35% respectively, against a between-victim
standard deviation of 1.4 to 3.5 m. Those rides were measuring an effect a
quarter the size of their own noise, which is why they read as null.

It also explains the results retrospectively. An 11.6x spread predicts a 0.65x
mass effect, and armor's own unexplained +45% advantage puts the net at 0.94x
against the 0.90x measured.

### What spread the goal actually requires

Taking the power law and armor's +45% advantage together, the spread needed to
make armored victims visibly harder to move:

| target ratio | mass spread | exponent |
| --- | --- | --- |
| 0.8x | 25x | 2.50 |
| 0.7x | 51x | 3.07 |
| 0.6x | 117x | 3.71 |
| 0.5x | 312x | 4.48 |

An exponent of 3.7 on a base of 40 puts villagers near 17 kg and guards near
1940, predicting roughly 5.9 m against 2.5 m. Both ends sit inside a range now
directly measured: 2000 kg was just ridden and behaves.

### The methodological lesson

Four rides concluded that a lever did nothing while testing it across a range
the lever's own coupling could never have made visible. The mistake was not
the measurement, which was careful, but never asking what spread the effect
size actually required before spending a ride on it. A null result across an
untested range is not a null result about the lever.

## An exponent of 3.7 makes armor visibly resist, and launches villagers too far

Ridden at base 40 with the exponent at 3.7, putting guards between 490 and 1945
kg and villagers between 17 and 50, a spread of 114x. The prediction from the
measured power law was a 0.6x throw ratio; the ride came in at 0.40x.

| set | n | armored | unarmored | ratio | p |
| --- | --- | --- | --- | --- | --- |
| all gallop impacts | 26 | 2.08 m | 5.24 m | 0.40x | 0.013 |
| full gallop only | 12 | 3.09 m | 6.86 m | 0.45x | 0.109 |

The full-gallop subset is six impacts a side and cannot carry a result on its
own; the significant figure is the 26-impact set. Contact geometry and approach
speed are matched across the two groups at full gallop, 1.14 m forward and
10.68 m/s against 1.20 m and 10.67, so the separation is not a sampling
artifact of where the horse hit.

The whole series now reads:

| spread | armored | unarmored | ratio |
| --- | --- | --- | --- |
| 3.4x | 3.39 m | 4.57 m | 0.74x |
| 11.6x | 3.69 m | 4.01 m | 0.92x |
| 114x | 3.09 m | 6.86 m | 0.45x |

The rider's unprompted description before seeing any of this was that some
unarmored victims went flying and no guard was thrown far. That is what the
table says.

### The light end is now the problem

Two villagers at 17 kg traveled 12.23 and 13.84 m. Neither is terrain: the
footprint `dz` is -0.13 and +0.09, so the ground was level, and both were
already 6 m out at the half-second sample. They are genuine launches, and a
person hit by a horse and thrown fourteen meters does not look like a person
being hit by a horse.

This is an aesthetic ceiling rather than a statistical one, and it is separable
from the effect. The exponent sets the ratio between armored and unarmored; the
base sets how far everyone travels. The ratio is now where it should be, so the
remaining move is to raise the base until the light end returns to a plausible
distance, which slides the heavy end further up without touching the ratio.

At base 100 with the same exponent, villagers land near 42 kg and guards near
4350. The power law predicts roughly 5.0 m against 2.1 m: a villager thrown
about as far as the shipped mod throws them today, and a guard thrown less than
half that.

## Raising the base holds the ratio and halves what the rider can see

Base 100 at an exponent of 3.7, putting guards between 2543 and 4863 kg and
villagers between 42 and 124. Nothing broke at five tonnes: every mass write
took, all but a handful at 16 ms, and no victim stuck to the horse, jittered or
sank.

| set | n | armored | unarmored | ratio | p |
| --- | --- | --- | --- | --- | --- |
| full gallop | 16 | 1.92 m | 4.19 m | 0.46x | 0.011 |
| all gallop tiers | 40 | 1.96 m | 2.66 m | 0.74x | 0.116 |

The light end is fixed. The longest unarmored throw fell from 13.84 m to 6.15,
so the launches are gone.

### The ratio is not what the rider sees

Against the previous ride, at the same exponent:

| base | armored | unarmored | ratio | **gap** | unarmored max |
| --- | --- | --- | --- | --- | --- |
| 40 | 3.09 m | 6.86 m | 0.45x | **3.77 m** | 13.84 m |
| 100 | 1.92 m | 4.19 m | 0.46x | **2.27 m** | 6.15 m |

The ratio is identical to two decimal places and the separation on the ground
fell by 40%. The rider described the effect as subtle without having seen these
numbers, and that is what a gap shrinking from 3.8 m to 2.3 m looks like.

**The visible quantity is the gap in meters, not the ratio.** Every earlier
entry in this branch reported the ratio, which is the right measure of whether
armor is doing something and the wrong measure of whether anyone can tell.

### Lowering the mass reactivates the impulse

The impulse the mod applies was measured as inert and set aside. That
measurement was made at the engine's default 80 kg, and it does not survive a
change of mass, because an impulse divided by a small mass is a large velocity.

| condition | victim | mass | impulse | delta-v |
| --- | --- | --- | --- | --- |
| base 40 | unarmored | 17-50 kg | 66 | 2.97 m/s, up to 4.34 |
| base 40 | armored | 490-1945 kg | 23 | 0.020 m/s |
| base 100 | unarmored | 42-124 kg | 64 | 1.00 m/s |
| base 100 | armored | 2543-4863 kg | 22 | 0.007 m/s |

Against a horse imparting something near 10 m/s, 4.34 is a third again on top
and 0.007 is nothing. So at a low base the impulse stops being noise and starts
being a second armor-differentiating mechanism, because `armorImpulse` already
runs 1.26 for cloth against 0.35 for mail and the mass divides it further the
same way.

This does not contradict the finding that the impulse is inert; it bounds it.
The impulse is inert **at the engine's default mass**, which is the only mass it
was ever measured at.

It also means the two mechanisms compound at a low base, and that the long
throws at base 40 were not purely a mass effect. Roughly a third of that
launch velocity came from the mod's own impulse.

## What the engine does with the values this mod writes

A survey of `references/libKCD1`, the decompilation index and `vanilla_scripts`
for anything that reads, writes or bounds the parameters this mod sets. Three
findings change what is reachable; the rest bound how much the current approach
can ever achieve.

### The living-entity mass is a different parameter, and it is writable

`pe_simulation_params` carries `mass` for rigid bodies and ragdolls.
**A living entity does not use that struct at all.** Its mass lives in
`pe_player_dynamics`, a separate structure, and the Lua binding exposes both:
`PHYSICPARAM_SIMULATION` and `PHYSICPARAM_PLAYERDYN` are each in the string
table of the shipped binary.

This overturns a finding recorded here and repeated in the `MassVictim`
docstring, that mass cannot be set on a living actor. It cannot be set through
`PHYSICPARAM_SIMULATION`, which is the only thing that was ever tried. Through
`PHYSICPARAM_PLAYERDYN` it takes immediately:

| target | state | parameter | before | after |
| --- | --- | --- | --- | --- |
| a guard | standing, alive | `PHYSICPARAM_PLAYERDYN` | 80 | 900 |
| the player's horse | ridden | `PHYSICPARAM_PLAYERDYN` | 480 | 2000 |

Both were restored afterwards. The consequence is large: the mass could be
written **before the collision** on a standing victim, rather than raced onto a
ragdoll sixteen milliseconds after contact, which removes the retry ladder and
the timing question with it.

### The horse's own mass is reachable

480 kg, and writable by the same call. Every measurement on this branch varied
one side of a two-body collision. The other side is a single parameter away,
and no ride has ever changed it.

### What bounds the effect

Live CVar values from the running game:

| CVar | value | meaning |
| --- | --- | --- |
| `p_max_bone_velocity` | **10** | clamps character bone velocities estimated from animations |
| `p_max_unproj_vel` | **2.5** | limits the velocity used to push overlapping bodies apart |
| `p_max_MC_mass_ratio` | 100 | mass ratio above which the microcontact solver is not considered safe |
| `p_max_velocity` | 100 | clamp on physicalized object velocity |
| `p_max_player_velocity` | 150 | clamp on living entity velocity |
| `p_penalty_scale` | 0.3 | scales the penalty impulse for the simple solver |
| `wh_rd_StillSpeedThreshold` | 0.3 | speed below which a ragdoll counts as still |
| `wh_rd_StillDuration` | 1 | seconds of stillness before standing up |
| `wh_horse_CollisionAvoidance` | 0 | the player's horse does not steer around people |

`p_max_bone_velocity = 10` is the one worth attention. A galloping horse travels
at 10.7 m/s, so the bone velocities that carry its collision into a victim are
clamped at very nearly the speed it is moving. `p_max_unproj_vel = 2.5` bounds
the separation velocity when two bodies interpenetrate.

Taken together these bound the collision from above regardless of either mass,
which is a plausible mechanical account of why the throw responds to mass as
weakly as `mass ^ -0.185` rather than the way momentum transfer predicts.

The mass ratio matters as well. At base 40 and an exponent of 3.7 a guard is
1945 kg and a villager 17, a ratio of 114 against a solver whose documented
safe limit is 100. The shipped base of 100 keeps every pair inside it.

### What is not a confound

- **`damping` and `minEnergy` are both mass independent.** `damping` is defined
  as a fraction of velocity per unit time, and `minEnergy` is documented in
  `physinterface.h` as energy *divided by mass*, so both act on velocity alone.
  `RagdollDamping` and `RagdollMinEnergy` do not interact with the mass write.
- **Ragdoll standup is velocity gated**, at 0.3 m/s held for one second, so a
  heavy victim is not put to rest sooner for being heavy.
- **Horse collision avoidance is off**, so the horse is not steering away from
  victims and biasing the contact geometry.

### Vanilla never does this

Across 495 vanilla scripts, `PHYSICPARAM_SIMULATION` is set on rope entities,
breakable objects, rigid bodies and tactical entities, and on no actor
anywhere. The rider's instinct that the game rarely touches its own physics
engine is right about the script layer: vanilla's mounted collision produces an
audio bark and nothing else, and every physical reaction in this mod is
something the shipped game never asks for.

## Writing the mass before contact removes the race, and the corridor lockup is real

`PrimeMassBeforeContact` writes a victim's mass through `PHYSICPARAM_PLAYERDYN`
while they are still standing, from the detection sweep, rather than onto the
ragdoll afterward. Twenty-two gallop impacts were recorded with it live.

### The race is gone, measured

The `Mass` line already reported which rung of the retry ladder the write took
on and how far the victim had moved by then. Before and after, from the same
session:

| condition | atMs | movedBy |
| --- | --- | --- |
| ragdoll write | 16, occasionally 33 | 0.01 to 0.04 m |
| primed before contact | **0 on every impact** | **0.00 m on every impact** |

Every write now lands on the first attempt with the victim exactly where they
stood. The mass is correct at the moment the ragdoll forms rather than sixteen
milliseconds into its flight, and the retry ladder no longer fires at all.

### A refusal is a body already on the ground

Fifty-three of eighty-seven priming attempts were refused, and the pattern is
uniform: the same victim, refused on consecutive ticks, wanting a scaled figure
and reading back 80. `PHYSICPARAM_PLAYERDYN` addresses the living entity, and a
victim already knocked down is not one, so the write is correctly rejected.

This is expected rather than a fault, since `MassVictim` still handles a body
that is already a ragdoll. It was costing a write, a read and a log line ten
times a second per downed victim beside the horse, so a refusal now backs off
for twenty ticks and logs once.

### The detection corridor lockup, reproduced

The rider reported a guard beside them in `PretendingIllness`. Probed:

    villageGuard  dist=2.5  anim=PretendingIllness  hcm=no  health=35.3

`hcm=no` means the mod holds no record of ever having hit him, and his health
is 35.3 against a full pool. He was struck hard enough to lose two thirds of
his health by a collision the mod never registered, so `SuppressAutoCure` was
never called on him, and vanilla's daycycle for the wounded took him over.

This is the lockup predicted from the call order and never before reproduced:
`SuppressAutoCure` runs from `TriggerCollision`, which runs only after the
footprint test passes, so a victim the corridor rejects is hurt by the engine
and left unprotected. Every impact the mod *did* register in the same session
was suppressed, twenty-two of twenty-two, which is what makes the missing one
diagnostic rather than ambiguous.

He was repaired in place with `SuppressAutoCure` followed by the same
hide-and-unhide rebuild and replan the mod runs on its own victims, and he
stood up and walked off.

**What this does not establish** is the cause of the missed contact. The ride
ran with `DiagnoseMisses` off, so no rejection was recorded and the width
hypothesis is unconfirmed for this specific guard. It is also not yet ruled out
that priming bystanders to several tonnes changes how the engine resolves a
contact the mod declines to see, which would make the lockup easier to provoke
rather than merely visible. `DiagnoseMisses` is back on for the next ride.

## Writing the mass before contact changes nothing the rider can see

Two paired-sample rides, 49 full-gallop impacts, with each victim assigned to
the primed or unprimed half by alternating **within armor band** so the two
groups hold the same mix of guards and villagers. The condition labels itself
in the log: a primed victim's mass is correct when the ragdoll forms and
`MassVictim` reports `atMs=0`, an unprimed one reports 16 or 33.

The second ride's groups matched on everything that matters: mean armor scale
0.77 against 0.75, mean mass 1630 kg against 1669, forward contact distance
1.13 m against 1.19, approach speed 10.51 m/s against 10.61.

### The result is nothing

Centering each impact on its own armor band's mean, which removes armor
entirely and uses all 49 impacts:

| condition | n | mean deviation from band |
| --- | --- | --- |
| primed | 24 | +0.06 m |
| unprimed | 25 | -0.05 m |

A difference of 0.11 m at p = 0.70.

Split by band the two halves point in opposite directions and cancel:

| band | primed | unprimed | difference | p |
| --- | --- | --- | --- | --- |
| armored | 5.55 m (n=15) | 2.59 m (n=9) | +2.97 m | 0.049 |
| unarmored | 3.98 m (n=9) | 6.64 m (n=16) | -2.66 m | 0.141 |

The armored figure is not evidence. Two subgroups were tested and one landed
just under 0.05, which is what testing two subgroups produces by chance, and it
is contradicted by the other band moving the same distance the other way. The
band-centered test over the whole sample is the honest one.

### What this settles

`PrimeMassBeforeContact` does what it claims mechanically. The write lands at
`atMs=0` with the victim not yet moved, against 16 or 33 ms and one to eight
centimeters for the ragdoll write, and it removes the variance of a retry
ladder that landed on different rungs for different victims.

**None of that reaches the throw.** The one-frame-late write was not costing
anything measurable, so correcting it buys nothing a player could see. This is
consistent with `p_max_bone_velocity` at 10 against a horse traveling at 10.7:
if the launch speed is imposed by the animation rather than computed from the
colliding masses, then when the mass is written cannot matter, and the mass
affects only the deceleration afterward.

The armor effect shipped in 4.7.0 therefore stands as measured. It was taken
through the late write, and the late write is not the reason it works.

### A design note worth keeping

The first paired ride was wasted by randomizing per entity. Armor decides the
throw, one ride reaches roughly twenty distinct victims, and one of them was
hit seven times, so a per-entity coin flip put guards on one side and villagers
on the other: mean armor scale 0.69 against 0.99. Randomize on the unit that
carries the variance, or stratify by it.

## Widening the corridor to 0.70 confirmed against the ride

`HorseHalfWidth` raised from 0.35 to 0.70. One ride, `CollisionIsCrime = false`
and `DiagnoseMisses = true`, mixing squarely ridden hits with deliberate close
passes at arm's length.

45 rejections total. Nine were width-only while inside the front/rear range,
and every one is at a lateral offset of 0.70 or beyond, up to 2.46 m — people
the horse passed with real clearance. None fall in the 0.70-0.90 m band that
would mean a genuine near-touch is still being missed, and none reproduce the
0.46-0.63 m cluster that was the documented defect.

25 real collisions, every one followed by `SuppressAutoCure`. Zero
`PretendingIllness` this ride.

The rider's own read of it, which the log cannot supply: every visible hit at
trot and gallop produced the mod's own reaction, and the vanilla fall
animation the corridor bug used to let through never appeared. That vanilla
handoff was the visible symptom of a victim the footprint test rejected, so
its absence over a full ride is the strongest evidence available short of
forcing the exact original failure again, which needs a victim sitting in the
0.46-0.63 m band, a health drop past 40, and enough in-game time for the
auto-cure daycycle to reach them — conditions this fix already removes the
cause of, so deliberately reproducing them again would not test anything new.

## A stale pak ran alongside the current build, not just instead of it

While testing an unarmed-brawl feature (`human:HolsterWeapon()` in the
retaliation path), the log showed two `Load screen ended` lines on every load,
one naming v4.7.1 and the other v4.7.2. That is not the previously documented
failure mode, where an old pak's copy loads *instead of* the current one. Both
were live at once: the stale dev pak's old `HorseCollisionMod` table kept its
own registered listener on the loading-screen event alongside the current
loose-file table's listener, so two independent copies of the mod's detection
and retaliation logic ran against the same NPCs for the length of the session.
`Setting 'RetaliationUnarmed' is not a setting, ignored` was the tell: the old
instance's `Config` had no such key, so its own `ApplySettings` rejected the
setting the new instance was reading correctly.

A full `dev_deploy.ps1 -Version dev` rebuild, game fully closed rather than
reloaded, and a fresh launch replaced the stale pak's contents and cleared the
duplicate. `-ScriptOnly -Reload` alone does not fix this, because it only
touches the loose files the current instance reads; the old instance's copy
lives inside the pak and is untouched by a script-only reload.

## Provoked civilian brawls stall in a defensive standoff, and the mod's own ceiling closes them

Testing the unarmed-brawl feature above surfaced a second, unrelated, and
larger problem: a provoked brawl does not develop into an exchange of blows on
its own.

A huntsman-area civilian (`rat_berthold`, role `merchant`) was provoked while
mounted, then approached on foot. He raised his guard and did not throw a
punch. The rider threw one; the victim threw one back; then nothing. The
encounter sat in `state=CombatIdle` until `WatchRetaliation`'s 120-second
failsafe closed it: `RetaliationEnd rat_berthold why=ceiling ... state=CombatIdle
rearmed=false`. What read in the moment as the fight "ending randomly" was
that failsafe, not a natural resolution.

`rearmed=false` also means `IsWeaponDrawn()` was false at the moment the
victim was provoked, in this case and in every other provocation logged this
session (`turnaj_benes`, the earlier `rat_berthold`). The holster feature never
had anything to holster. Whether that is because civilian defense-only brawls
never draw a weapon at all, or because the check runs before an AI-driven draw
would happen, is not yet known — but across every sample so far, the weapon
was already down.

`docs/TESTING_DIARY.md`'s own record of `startInDefenseOnly` explains the
guard stance: the fight starts in defense only because the player is not
already flagged an enemy, so the victim blocks rather than opens. It does not
explain why the fight stays inert after the rider's own punch is answered.
An earlier entry recorded a victim who *did* keep fighting unprompted and
guards who joined in swinging, so a standoff is not universal — what decides
which happens is still open.

This is a defect in the retaliation feature as shipped in 4.6.0, not in
anything on the branch that surfaced it. `feat/retaliation-unarmed` is parked,
committed and unmerged, pending a scenario that actually exercises the
holster path. The stalled brawl is the next thing to investigate.

## Why a provoked victim never swings: `$offense` is never set

`tools/dev_watchfight.lua` samples every human within 10 m once a second,
along with the player, so a swing and whatever answers it sit in one timeline.
A provoked merchant was watched through a stall and out the far side of it.

### The stall, measured

Twenty-two consecutive samples with both parties in `CombatIdle` at a distance
of exactly 2.0 m. The victim's relationship to the player held at 0.57, his
weapon stayed undrawn, and he neither closed nor struck. He is in the fight
state the whole time: this is not a victim who failed to enter combat, it is
one who entered it and will not act.

The rider then attacked. The victim answered with a single counter, and from
the sample where the rider's own hits began landing the relationship dropped
to -0.00 and stayed there. Every sample afterwards is a real fight:
`CombatAttack`, `CombatDodge`, `CombatBlockNW`, `CombatBlockBroken`,
`CombatHit`.

### The relationship is a side effect, not the cause

The obvious reading is that hostility gates the fight and 0.57 is too friendly
a number to attack over. That reading is wrong, and building on it would have
produced the wrong fix.

`sb_combat_fight.xml:514` initializes the flag that decides whether a fighter
attacks at all:

    $offense = !$t_fightOptions.startInDefenseOnly

A civilian struck by the player, who is not already an enemy, is given
`startInDefenseOnly = true` by `sb_combat.xml:8340`, so `$offense` begins
false. There is exactly one place in the whole subtree that sets it true, at
`sb_combat_fight.xml:574`:

    ReadMessage inbox = hitReaction
    if hitReaction.hitStrength > HitReactionStrength.Zero
       and (hitReaction.hitType == Melee or hitReaction.hitType == Bullet)
        $offense = true
        AddOpponent(hitReaction.attacker)
        InstantSendMessageToNPC(this, encounter:addOpponent)

So a defense-only fighter leaves defense only when a hit reaction of non-zero
strength reaches him, and never otherwise. The relationship falling to zero is
what the rider's real hits do to reputation on their way past; it is
correlated with the fight starting because the same punch causes both.

### Why the mod's provocation cannot start a fight

`SendProvocationHit` sends `combat:stimulus:hit` carrying `attacker`, `kind`
and `real = false`. That reaches the civilian hit handler and wins the
argument about whether to fight, which is why the victim stands up and guards.
It does not put a `hitReaction` of non-zero strength in the victim's inbox, so
`$offense` is never set, and a fighter with `$offense` false has nothing to do
but hold his guard until something closes the incident. The mod's own
`RetaliationCeilingSec` failsafe is usually what does.

The feature's central design decision is what defeats it. `real = false` is
carried precisely so the provocation raises no crime and no reputation change,
and that same flag is why no hit reaction of consequence is ever produced.

### The horse's own collision cannot set it either

`HitReactionType` is `Melee` 1, `Collision` 2, `Fall` 7, `Bullet` 10,
`MeleeStealth` 16. The `$offense` condition accepts `Melee` and `Bullet` and
nothing else, so a hit reaction arising from a horse collision is the wrong
type to release a defense-only fighter however hard it lands.

### The route out, confirmed constructible

`hitReaction` is a declared type in `TypeDefinitions.xml`, carrying `attacker`,
`hitStrength`, `hitType` and `targetOrigMat`, and it is registered in
`MessageTypes.xml`. `HitReactionStrength.Tickle`, value 2, is documented there
as costing the target no health and only minor stamina, and it clears the
`> Zero` test.

Built against the running game:

    Utils.makeTable('hitReaction',
        { attacker = playerWuid, hitStrength = 2, hitType = 1 })   ok

Sending that to a provoked victim should set `$offense` and register the
player as an opponent without a health cost and without touching reputation,
since the block that reads it does neither. That it constructs is not proof
that the fight tree answers it, and the send is untested.

## Reputation does not drive the flee, measured mid-flight

The permanent flee after a beating was attributed to the hostility flag a
punch sets, on the strength of the `reputation_change` table: `hit_melee_weak`
carries `can_change_hostility` true, `surrender_step` carries it true and
raises the number, and a paid fine carries it false. The reading was that
surrendering repairs a victim and a fine cannot.

That explains the reputation and not the behavior.

`tools/dev_fleerepair.lua` was armed before a full cycle: provoke, fight, pay
the fine, release through the yield menu. It watches every human within 60 m,
and when one whose relationship is under 0.35 moves away at more than 2.5 m/s
for two consecutive samples it applies `surrender_step` eight times on the
spot, inside the game, then keeps sampling. Doing it from the console is too
slow, because a fleeing victim covers five meters a second and unloads.

The victim, a townsman, was repaired in mid-flight:

| relationship | distance | speed away |
| --- | --- | --- |
| 0.260 | 4.2 m | 3.5 |
| 0.260 | 8.8 m | 4.7 |
| **0.816** | 13.6 m | 4.7 |
| 0.816 | 23.2 m | 4.9 |
| 0.816 | 32.8 m | 4.8 |
| 0.816 | 47.3 m | 4.6 |

The repair landed and took him to 0.816, above a healthy villager. He did not
slow for a single sample.

The same log rules it out a second way, from bystanders sampled at the same
moment:

| entity | relationship | behavior |
| --- | --- | --- |
| a soldier | 0.209 | `MotionIdle`, 1.5 m from the player |
| a beggar | 0.253 | `Beggar`, standing still |
| the victim | 0.260 | running at 4.7 m/s |

Three NPCs within five hundredths of each other, two of them entirely
unbothered. **The relationship value neither causes the flee nor predicts it**,
and `surrender_step` moves the number without touching the behavior.

### What this closes and what it leaves

`can_change_hostility` remains a correct reading of the reputation table. It is
not an explanation of the flee, and repairing reputation is not a cure. Any
further work on this belongs to the behavior side.

`XGenAIModule.GetBrainVariable` and `SetBrainVariable` exist and accept both an
entity and a WUID without error. Queried on a peaceful NPC for `t_state`,
`t_fightParams`, `t_fleeParams` and `offense` they all answer nil, which is
consistent with subbrain-local variables that exist only while that subbrain
runs. Reading them off a victim **while he is fleeing** is untried, and is the
next thing worth doing.

### What the flee is not, after four probes

Each of these was run against a victim mid-flight, in game, and none changed
his speed away from the player or told us what drives it.

| probe | result |
| --- | --- |
| `surrender_step` to 0.816 | kept running, 4.7 m/s unchanged |
| `XGenAIModule.TryEndCombat` | not bound at runtime, despite the header list |
| `Contexts.ResetEntity` | accepted, kept running at 5.1 m/s |
| `GetBrainVariable` for combat state | nil for every name |

The context option diff between a freshly broken NPC and a healthy one found
three differences, `availableToSelfTalk`, `availableToUseLight` and
`availableToSing`, none of which bear on fleeing. Twenty-six soul getters
compared across the same pair differ only in gender and name string.

`GetBrainVariable` does work: it returns the option table under
`Contexts.__brainVarName__`. It answers nil for `currentState`, `t_state`,
`t_state_current`, `t_state_next`, `t_fleeParams`, `isPlayerHostile`,
`isHostile`, `threat` and `t_stateSwitchQueued`, all of which are declared in
`sb_combat.xml`. The reading is that the bind reaches the context brain only
and not subbrain-local variables, so the combat state is not readable from Lua
by this route.

**The cause remains unknown.** It is not reputation, not a context option, not
a daycycle patch, and not anything exposed on the soul. Whether the state is
even permanent has not been measured under controlled conditions; the seven-day
report was from ordinary play. Skipping days with `tools/dev_time.lua` against
a deliberately broken victim would settle that, and it is the cheapest
remaining question.

## The permanent flee was the chase

A victim who runs after a provoked fight was recorded across this project as
fleeing indefinitely, and a stand-down was built to stop him. He does stop on
his own. What kept him running was being followed.

One beggar, one build, the only difference being what the rider did:

| rider | outcome |
| --- | --- |
| stood still | `halted ran=14000ms speed=0.0` |
| chased him | `stopped ran=40000ms speed=4.9` |

Chased, he ran the whole forty second budget at full flee speed with no sign
of slowing. Left alone, the same man stopped dead at fourteen seconds. A
second victim stopped at 11.5 seconds under the same conditions.

`fleeFromNPCParams` explains it: `distance` defaults to **150.0**, and
`t_fleeParams.entityToFleeFrom` is set to `$realAttacker`, which is the
player. The flee ends when he is that far from the man he is fleeing. Follow
him and he never gets there.

Every earlier observation of an endless flee was made while following the
victim, which is also how the mod's own detector was blinded: it measured
distance from the player, so a sprinting victim read as stationary while the
rider kept pace, and one run logged `done=no-flee` about a man crossing a
village.

### What that costs

`AftermathStandDown` exists to stop a flee that ends by itself, and the
stand-down is what hands a victim to `state_standDown` and its wind-down,
measured at about twenty five seconds of standing still. The pause was the
price of solving a problem that was not there.

The repair is the part that matters and is unaffected: below vanilla's 0.2
threshold a victim decides to run again on every sighting, so without it the
flee restarts forever whether or not any single one ends.

### The yield menu is a message, and it carries an enum

Choosing "continue combat" on a yielded victim made a beggar who would not
throw a punch draw an axe and fight properly. That menu sends
`combat:mercy:dialogResult` with an `enum:combatMercyOutcome`:

    none, exitCombat, takeWeaponAndLeave, leaveWeaponAndLeave,
    leaveValuablesAndLeave, fight

`fight` is what produces the committed armed fight, and it overrides the
timidity that `alwaysFightWhenHit` only partly removes. `exitCombat` is a
sanctioned way out of combat, which is what a long search for one failed to
find; it is not needed for the pause any more, and it is worth knowing.

## A victim now carries the marks of being ridden down

`actor:AddBlood` takes a body zone name, not a material or an effect. The
question had been open since the bind was catalogued, and it was answered from
vanilla's own quest scripts rather than from the game: `q_ledecko.xml`,
`q_counterfeiters.xml` and `q_horse_on_the_run.xml` between them pass around
two dozen names of the form `head_front`, `body_left`,
`arm_left_forearm_back`, `leg_right_upper_back`, `foot_right`, and `all` for
every zone at once. The second argument is a delta between -1 and 1, so marks
accumulate and a negative figure washes them off. `deadBody.xml` bloods every
corpse on spawn this way. The engine resolves the name against a database that
is not exposed to Lua and drops an unrecognized one without an error, so
`Marks.lua` passes only names vanilla itself uses.

No probe ride was needed, and the engine call needed no machinery around it.

### Both tiers verified in one session

`Marks.lua` keys its zone set off the impact direction `Detection.lua` already
computes for the reaction clips. Two impacts confirmed it end to end:

    VictimMarks tier=Gallop dir=so_forward dirt=0.60 blood=0.45 zones=6 applied=true
    VictimMarks tier=Trot   dir=so_back    dirt=0.35 blood=0.15 zones=6 applied=true

The gallop victim was struck from the front and the rider reported "a lot of
blood on him". The trot victim was run down from behind, and the rider found
blood on his leg without being told where to look; `so_back` carries
`leg_right_upper_back` and `leg_right_lower_back`, so the direction keying is
visible on the body rather than only in the log.

The walk tier is deliberately unmarked. A stagger puts nobody on the ground.

## The marks clear after a night, and standing there waiting does not do it

The concern was whether marking a victim leaves them permanently altered in a
way vanilla would not. The script evidence said dirt clears and blood does not:
NPCs call `actor:CleanDirt(1)` in `so_water_tube.xml`, `sa_home.xml` and
`so_hostel.xml`, and the daycycle cleans them in rain, but `CleanDirt` is
documented as leaving blood alone and the only bind that removes blood,
`WashDirtAndBlood`, is called on the player and nowhere else.

The game disagrees, and what was done is worth recording exactly, because the
result depended on it.

A merchant was ridden down twice at a gallop. He was visibly covered in dirt
with blood on both arms. Waiting twenty four hours **standing at his booth**
left him bloody and filthy. Waiting another twenty four the same way changed
nothing either. Waiting until late night, when he was away at home, and then
waiting again until the afternoon when he was back at his booth, produced a
completely clean man.

**Why** is not established. The plausible reading is that an NPC waited at is
held where they are and reloaded in place, so the daycycle behaviors that
would have changed them never run, and only a night spent with the target
somewhere else puts them through their routine. That is a hypothesis fitted to
three observations, not a measurement: nothing here read the NPC's schedule or
watched a wash behavior fire.

What is established is the procedure. Any future test of a routine-driven
effect should wait through a night with the target elsewhere, because that is
the only form of waiting that has produced a change.

### What that means for the feature

Nothing the mod applies is permanent. A victim was seen marked, and seen clean
again a night later, without the mod doing anything to clean him. That is
enough to close the question the feature raised, and no cleanup code is needed
on the mod's side. What in the game removed the blood is unidentified, and it
is not the two binds the scripts pointed at.

### A direct time jump is not a substitute and breaks the session

`Calendar.SetWorldTime` moved the clock a day forward correctly, log confirmed,
and the rider reported that "everything broke" and had to reload. The in-game
wait is the only safe way to pass time here.
`wh_pl_SkipTimeMaxWorldTimeRatio` defaults to 360 and takes 7200 without
complaint, which turns a full day's wait into about twelve seconds and changes
nothing about how the world simulates it.

## Barks cannot be re-pointed from Lua, and the reason is where vanilla sends them

The idea was to replace the collision bark, vanilla's "can't you ride a horse",
with one of the lines an NPC uses when the player swings a fist near them.
Those exist and are addressable by name: `sb_switch_hitreactions.xml` sends
`ZASAH_ZBRANI_IGNOROVANY` on `$dotPlayerAttackNearMiss > -0.25` and again when
the player is neither hostile nor in combat, and `RANENY_NA_ZEMI` for a melee
victim who is on the ground.

### How the vanilla collision bark actually fires

Inside the victim's own hit reaction tree, not from anywhere a mod can call.
When a `hitReaction` message lands and the victim is not in combat and does not
carry the `suppressCollisionsBark` context option, the tree runs a `GraphSearch`
over the attacker's entity links for a `rider`. If that rider is the player, the
player is male and `hitStrength > Healing`, the tree sends **itself**
`dialog:monologRequest` with `metarole('KOLIZE_S_HRACEM_NA_KONI')`. Two lesser
branches send `KOLIZE_S_HRACEM` and `KOLIZE_S_HRACEM_LEHKA` when the player is
the attacker directly.

This mod already drives that path, because `SendHitReaction` posts the message
the tree is waiting on.

### Sending the request from Lua is accepted and produces no line

`dialog:monologRequest` is a declared type carrying `metarole`, `alias`,
`priority`, `lookAtId`, `forceSubtitles` and `overrideContextSuppress`, and
vanilla's own `DialogUtils.RequestPlayerMonologByMetarole` sends it with
`SendMessageToEntityData` and `Utils.makeTable`. Sent that way to a nearby NPC
it is accepted every time, with no error, and no voice line ever plays. Tried
with the near-miss role and with `KOLIZE_S_HRACEM_NA_KONI`, the role the target
demonstrably speaks when ridden into; with and without `lookAtId`, priority and
`overrideContextSuppress`; on a merchant and on a village guard.

One attempt was not inert. The rider saw the target "go into slow motion around
the 8 second mark for about the length of what would be the bark and then pop
back into his normal walk". So the monolog machinery does run and does take the
actor for the duration of a line, and the line itself never resolves. The
receiving tree, `monologRequestRead` in `sb_dialog.xml`, reads from a dedicated
`DialogMailbox` and captures a `common:senderInfo` that a Lua send does not
supply, which is the most likely place the resolution fails.

Calling this closed rather than firing more variants of the same call.

### What that leaves

Silencing the bark is free and already available: `suppressCollisionsBark` is a
context option, set the same way the mod already sets `suppressAutoCure`.
Substituting a different line is not, because the only send that works is the
one inside `sb_switch_hitreactions.xml`. That file was overridden by this mod
once and the override was removed in 2.0.0-rc1 to make the mod Lua-only and
conflict-free; it is still preserved in `mod_xmls.disabled/`. Changing the bark
means reopening that decision for a one-line change.
