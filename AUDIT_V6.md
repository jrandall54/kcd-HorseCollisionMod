# v6 audit ledger

Working document for the `audit/v6` branch. Deleted before the branch lands.

Phase 1 records findings only. Phase 2 applies them in small batches, each
checked off here with its commit.

## Resuming

Read this section first in a new session. It is updated and committed at the
end of every pass, so it always says where the audit stands.

**Phase:** 1, recording findings. No source file has been edited.

**Current status:** Lean.lua findings recorded and committed.

**Method for one pass:** read the whole file; check every factual claim in a
comment against the code it describes; record each problem under the file's
heading in **Findings** as `:line` — problem — planned edit; anything that
changes behavior or needs a decision goes in **Rulings needed** instead;
update this section; commit as `docs(audit): record findings for <file>`.

**Decisions are deferred.** Nothing in phase 1 waits on a ruling. Anything
needing one is recorded under **Rulings needed** with a proposal, and the
passes continue. Rulings are made together once phase 1 is complete.

**Next pass:** `Update.lua`.

**Pass order** (dependencies first, then largest):

- [x] `src/HorseCollisionMod.lua` (entry point)
- [x] `src/HorseCollisionMod_Settings.lua`
- [x] `src/HorseCollisionMod/Tiers.lua`
- [x] `Armor.lua`
- [x] `Reaction.lua`
- [x] `Rear.lua`
- [x] `Retaliation.lua`
- [x] `Bark.lua`
- [x] `Recovery.lua`
- [x] `Health.lua`
- [x] `Rider.lua`
- [x] `Sound.lua`
- [x] `Lean.lua`
- [ ] `Update.lua`
- [ ] `Marks.lua`
- [ ] `Fear.lua`
- [ ] `Crime.lua`
- [ ] `Impact.lua`
- [ ] `Log.lua`
- [ ] `Tutorial.lua`
- [ ] `Detection.lua`
- [ ] `Enums.lua`
- [ ] Documentation: `README`, `docs/*.md` except the diary
- [ ] Tooling: `build.ps1`, `tools/`, `.claude/` hooks and linter

**Carried forward:** findings in one file that point into a file not yet
audited are listed here, so its pass picks them up.

- `Marks.lua` — check the dust comments against the vertical-speed test.
- `Update.lua:85-90` — says `RearCharging` is cleared by `ChargeForward`
  "the moment the horse stops accelerating"; `WatchLunge` clears it when
  speed decays to a fraction of the peak. "the old double hit" is history.
- `Update.lua` — receives `ImpactIsNewContact` from `Recovery.lua`.
- `Rear.lua`, `Retaliation.lua`, `Update.lua` — adopt the shared horse
  lookup from the Lean findings.
- `Impact.lua:218-223` — the comment on deferring `SendCombatHit` ("it
  perfectly overrides the casual recovery dialogue") is in another register;
  its `WhenVictimRises` depends on the early-return ruling.
- `Impact.lua:51`, `:124-127` — `IsCombatCollision` returns the same value
  twice; the comment contrasts `playerInDanger` with "the combined signal",
  which no longer exists. Follows the Rider finding.
- `Impact.lua:251` — ignores `ApplyImpactDamage`'s return value, which the
  Health findings remove.

## Standard

Measured against `.claude/STYLE.md`, plus these rules from the research pass:

- **Timeless.** No `now`, `currently`, `new`, `no longer`, `used to`, `was`,
  `before this`, `at the moment`. Documentation describes the product as it is.
  ([Google: timeless documentation](https://developers.google.com/style/timeless-documentation))
- **No history in code.** Change history belongs in version control, the
  changelog and the testing diary. A comment states the constraint or the
  derivation, never how it was found.
  ([Google Python style: comments](https://google.github.io/styleguide/pyguide.html#38-comments-and-docstrings),
  [Comments are not version control](https://coding.abel.nu/2012/07/comments-are-not-version-control/))
- **Comments explain why, never what.** Do not restate the code.
- **Brief.** Give the reader enough to act and stop.
  ([Microsoft style: top 10 tips](https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice))
- **No people.** No "the rider", no player anecdotes, no quoted rides.
- Narrative of any kind belongs only in `docs/TESTING_DIARY.md`.

## Rulings needed

Items that change behavior or delete a feature. Not applied without a decision.

- [ ] **DynamicRecovery.** `Recovery.lua:1097-1185` computes a per-tier get-up
  duration that nothing applies (the get-up is the global
  `wh_rd_StillDuration`). The duration only times the ground groans and a log
  line. Proposal: keep the groans, stop them when the victim is observed
  standing, delete `DynamicRecovery`, `RecoveryDelayByTier`,
  `RecoveryArmorScale*`, `RecoveryMinSec`, `RecoveryMaxSec`.

- [x] **RearChargeThrow ships at 0.6.** Ruled correct; revisit only if the
  publish test runs call for it. The comment keeps "1.0 throws like a gallop"
  as the scale, with no claim about which tier throws further.

- [ ] **The charge's bark set.** `Tiers.lua:422` says `VictimBarkByTier.Charge`
  is `"rear"`; the settings file (`:381`, changed later in `cbe54cb`) ships
  `"collision"`, and because it carries the whole table, `"collision"` is what
  runs. The same risk applies to every tier table: the settings file ships a
  full literal copy of all nine, so `Tiers.lua` is unreachable unless a player
  deletes one. Proposal: make `Tiers.lua` match what ships (`"collision"`),
  and have `build.ps1` refuse a settings tier table that differs from
  `Tiers.lua`.

- [ ] **The one-time physics-proxy rescue.** `Rear.lua:856-865` calls
  `SetAnimationDrivenMotion(0, 1)` on the horse once per session, to repair
  saves left broken by development tests (`597e613`). Players' saves never
  reached that state, and the comment beside it (`:876`) says the call is
  left alone. Proposal: delete the rescue and `HasRescuedPhysicsProxy`.

- [ ] **`RearAnimSpeed` and the standing rear.** `RearAnimMs` divides the
  rear's length by `RearAnimSpeed`, but the standing rear plays through
  `StartAnimation`, which is not given the speed; only the charge is. Harmless
  at the shipped 1.0. Proposal: document `RearAnimSpeed` as the charge's
  speed and stop dividing the standing rear's length by it.

- [ ] **The cooldown icon after a save load.** A load winds the clock back
  with the deadline in place. `RearRequested` treats a gap larger than the
  cooldown as a wind-back and lets the press through, but
  `UpdateMoveCooldowns` only asks `now < nextAt`, so the icon can stay up
  while the move is available. Proposal: apply the same wind-back test in
  `UpdateMoveCooldowns`, or clear both clocks on load.

- [ ] **`CatchYieldImmediately`.** A module constant fixed at `false`
  (`HorseCollisionMod.lua:1547`) with no setting, so the yield branch in
  `WatchRetaliation` (`Retaliation.lua:414-425`), `sawYield`, `caught` and
  `SendStandDown`, whose only caller is that branch, never run. Proposal:
  delete them.

- [ ] **The pull-down target probe.** `PullRiderDown` asks
  `CanHorsePullDown` for both the player and the horse "until one of them is
  shown to be the right one" (`Retaliation.lua:1190-1192`), and computes
  horse-to-victim angles every poll for the log line alone, whether or not
  telemetry is on (`:1203-1242`). Proposal: settle the target from the
  diary's pull-down rides, keep that one, and delete the second query and
  the angle tracking.

- [ ] **The dead Henry set path.** `RiderBarkSets` is empty, so
  `BarkDeath`'s `Bark(player, "Killed", true)` (`Bark.lua:1049`) always
  returns false and, with telemetry on, logs "no rider set wired" on every
  death. The `RiderBarks` setting gates only that call; the kill line is
  gated by `RiderBarkKill`. Proposal: delete `BarkDeath` and its call
  (`Health.lua:837`), `RiderBarkSets`, `RiderBarks`, and `Bark`'s `rider`
  parameter. Resolves the settings file's `RiderBark`/`RiderBarks` finding.

- [ ] **The empty impact pool.** `RiderBarkAliases` is empty and `RiderBark`
  ships false, so `BarkRiderImpact` never sends. Its doc (`Bark.lua:211-297`)
  says it is kept so a line can be put back. Proposal: keep the mechanism;
  reduce the doc to what an entry must satisfy (the four filters) and move the
  survey and audition history to the diary if absent there.

- [ ] **The charge's impact cry is silent.** `VictimBarkByTier.Charge` ships
  `"collision"`, so the charge reaches `BarkForTier`, and `PainByTier.Charge`
  is `HurtHard` (`ZASAH_ZBRANI_SILNY`), which the comment directly above
  (`Bark.lua:596-609`) says is a combat-shout set that a bark request cannot
  reach. Proposal: `HurtDown`, as trot and gallop use; decide together with
  the charge's bark set ruling.

- [ ] **`HushVanillaBark` clears its own refresh.** Each call arms a timer
  that clears the option after `BarkSuppressMs`, and a refresh comes at half
  that window, so the first timer clears an option the second call set and
  expects to hold. The option can be down while the victim is still in front
  of the horse. This is the two-writers failure the comment in `Bark`
  (`:788-790`) warns against. Proposal: the timer clears only when
  `RecentHushes[id]` still holds its own stamp.

- [ ] **`WhenVictimRises` fires at once on a ragdoll tier.** `8809c66` added
  an early return on any ragdoll state (`Recovery.lua:332-338`, "the most
  reliable indicator that they have started rising"). `IsVictimFlat`
  (`:262-270`) records that a gallop or charge victim sits in `BlendRagdoll`
  for the whole time they are down, so on those tiers the recovery line
  fires on the first poll, while the victim is still on the ground. The
  doc above the function describes the height test that the early return
  bypasses. Proposal: take the shortcut only on a tier whose reaction is
  `fall`, or remove it and rely on the height test.

- [ ] **`VictimFlatFraction` ships at 0.45 against a derivation for about
  0.13.** The comment (`Recovery.lua:275-287`) says flat reads 0.04 to 0.10
  of standing, a rising body 0.17 or more, and that a halfway split refused
  victims who were visibly getting up. `2910119` raised the value from 0.15
  to 0.45 without touching the comment. Proposal: find the reason for 0.45
  in the diary; restore 0.15 or rewrite the derivation for 0.45.

- [ ] **`WhenBodyStops` reads `GetWorldPos`.** `Reaction.lua:421-428` says
  the entity does not follow a ragdoll and reads `GetCenterOfMassPos`;
  `WhenBodyStops` (`Recovery.lua:604`) times the damage from the entity. The
  current log's four `BodyStopped` rows all report `stopped` (1008 to
  2608 ms), so the entity moves on these victims. Proposal: use the same
  body reading as `Reaction.lua`, so the two do not disagree.

- [ ] **The investigation diagnostics.** `WatchTurn` (a polearm victim
  reported facing the wrong way) and `TraceFallLanding` (how often a
  requested fall is held) were built to answer one question each.
  `TraceFallLanding` runs on every impact whenever `LogTelemetry` is on.
  Proposal: delete `WatchTurn`; keep `TraceFallLanding` only if its question
  is still open, and gate it on `TraceRecovery` with the others.

- [ ] **The impact-throw probe.** `ProbeImpactCost` measures throw distance
  from `GetWorldPos` (`Health.lua:213-220`, `:262-272`) and runs a rest
  watcher to log `ImpactThrow` (`:296-348`). Throw distance was closed as
  not measurable from Lua, and the entity does not follow a ragdoll.
  Proposal: delete the rest watcher and the `travel=` field; keep the health
  and state samples, which answer what an impact cost.

- [ ] **Unused sound tokens.** `Sound.lua` resolves six tokens; no shipped
  tier names `foley` or `face`. `foley` carries its own table
  (`BodyFoleySounds`) and resolver (`BodyFoleySound`, `:97-120`); the walk
  names its foley triggers literally. Proposal: delete `foley`, its table and
  resolver, and `face`; document the tokens that remain.

- [ ] **The lean's correction throttle is never applied.** `FlipLean`
  skips a flip inside `LeanMinFlipMs` unless `force` is set, and every call
  site passes `force = true` (`Lean.lua:368`, `:487`, `:496`, `:526`,
  `:566`), including the hold corrections the throttle exists for. The
  queue-overflow protection that `:238-257` and the entry point's
  `LeanMinFlipMs` doc describe is therefore off. Proposal: leave `:526`
  unforced for a `turning` correction and forced only for the expiry
  refresh; or, if the hold is judged fine as it ships, delete
  `LeanMinFlipMs`, the `force` parameter and the throttle.

## Findings

Format: `file:line` — problem — planned edit.

### Tooling and enforcement

- [ ] `.claude/lint_docs.py` — passes with 0 errors while
  `src/HorseCollisionMod.lua` alone carries about 41 narrative lines. The
  rules match a few exact phrases. — Add rules for timeless words, `the rider`,
  `It was <number>`, `used to <verb>`, `before this`, `no longer`, and
  `shipped before`. Promote to errors where false positives are rare.
- [ ] `.claude/hooks/pre-commit`, `.claude/hooks/style-check.sh` — the hook
  comments are themselves narrative ("was broken repeatedly anyway"). —
  Rewrite in the standard.
- [ ] `tools/audit_code.py` — reports `RearCooldownBuff` and
  `ChargeCooldownBuff` as unread; `Rear.lua:431` reads them by string. —
  Recognize string references, or record the exemption.

### src/HorseCollisionMod.lua

- [ ] `:1-66` module header — says three tiers (there are five); lists
  `hcm_<set>_fragmentids.xml` and `hcm_<set>_controllerdefs.xml`, which do
  not ship; names `hcm_animationControlledTags.xml` (ships as
  `kcd_animationControlledTags.xml`); says seven data files (six); option
  counts stale. — Rewrite against `build.ps1:474-479`.
- [ ] `@field` list — truncated or merged entries: `RagdollMinEnergy`,
  `RagdollDampCeilingMs` carries a fragment of the former. `RiderBlur` and
  `CameraShake` say "a gallop" but apply per tier. `ThrowProfileByTier`
  describes a "brake" or "launch" entry mode; verify against `Tiers.lua`. —
  Correct each against the code.
- [ ] Config comments — orphans whose settings moved or were removed:
  "What a trot impact does" (describes `ReactionByTier`), the recovery-line
  delay paragraph above `BarkGapMs`, the retaliation paragraph now above the
  rear settings, "What a collision is worth" above `ImpactSoundByTier`. —
  Delete or move beside the setting they describe.
- [ ] Config comments — contradict the code: "keep at or below
  `HitCooldownMs`" (setting is `HitMinIntervalMs`); "Gallop only: a trot
  knockdown should stay a shove" (trot shake is 0.6); `ShieldWindowMs` has two
  spliced half-sentences. — Correct.
- [ ] Config comments — narrative throughout (`TickSeconds`, `MaxImpactSpeed`,
  `BarkCooldownMs`, `ShieldVictimFromEngineDamage`, blur/blood notes). —
  Reduce each to the constraint or derivation.

- [ ] `:895-898` `CameraShake` and `:911` `RiderBlur` — "a gallop impact" and
  "Gallop only: a trot knockdown should stay a shove" contradict the per-tier
  tables. (The shake half is also listed above; fix once.) — Describe per
  tier.
- [ ] `:980-1077` impact sound block — the layer format
  `{ trigger, delay, distance, chance }`, the distance-is-volume paragraph and
  the token paragraph each appear three times, from successive rewrites
  spliced together. Four orphan per-tier paragraphs (walk, trot, gallop, "no
  hoofstep") follow `ImpactSoundDistance` with no setting under them. — One
  copy of each above the per-tier table; tier notes beside
  `ImpactSoundByTier`.
- [ ] `:1058-1061` `ImpactSoundCrack` — "came out at cartoon volume whatever was
  done to it". — State that the 2D event cannot be attenuated.
- [ ] `:1063-1068` `RiderVocal` — "which is what made every earlier attempt at
  Henry's half unusable". — Cut.
- [ ] `:1102-1108` `RiderBarkPriority` — "confirmed audible in testing … makes
  the tested configuration the default". — State the constraint (a request
  below the top is discarded) and the value.
- [ ] `:1110-1136` hit-readiness block — orphan with no setting under it; names
  `HitCooldownStateDriven`, `HitCooldownMs`, `KnockdownRecoveryMs`,
  `HitReadySettleMs` and `HitReadyCeilingMs`, none of which exist anywhere in
  `src/`. A second paragraph ("Which tiers wait…") is spliced on. — Delete.
- [ ] `:1138-1147` `ImpactDust` — says `arrow_soil` is the chosen effect; the
  default is `explosion_dust` and `arrow_soil` is the rear's. "The
  alternatives worth trying" is a note to self. — Correct; cut.
- [ ] `:1157-1162` `VictimMarks` — "applied at trot and gallop only";
  `VictimBloodByTier` carries rear and charge. — Correct.
- [ ] `:1173` orphan: "How long after the action ends before the displacement
  is read back." — Delete.
- [ ] `:1184-1191` `ImpulseDelayMs` — "has been measured throwing one victim
  four meters and another none". — State the constraint.
- [ ] `:1213-1244` ragdoll block — the damping paragraph runs into the brake
  paragraph with no break, so `RagdollDamping` and `RagdollMinEnergy` sit
  under the brake's text. Eight `RagdollDamp*`, `RagdollSpeedSoftCapSpan` and
  `SettleFragTag` keys have no comment. — Split; document or point to the
  `@field` list.
- [ ] `:1232` "-- Dynamic Ragdoll Recovery" and `:1255` "-- Native Engine
  Ragdoll Stillness" — title-case labels unlike every other comment. The first
  goes with the DynamicRecovery ruling. — Replace with a sentence.
- [ ] `:1246-1252` `RisePollMs` — "Both were read from `Config` and declared
  nowhere, so `ApplySettings` refused them…". — Keep the first sentence.
- [ ] Victims are "he" throughout the retaliation and repair docs (`Baseline`,
  `RepairFloor`, `RepairFightCost`, `CatchYieldImmediately`,
  `RetaliationReleaseMs`); women are victims too. — "they".
- [ ] `:1344` a stray `--- Last time each entity was reported as a miss` heads
  the `SphereCache` doc; it belongs to `RecentRejections` (`:1374`), which has
  none. `SphereCache` states its budget as "Measured in game it takes…". —
  Move the line; keep the figures as a derivation.
- [ ] `:1398-1408` `SpeedHistory` — "That would explain a gallop being recorded
  as a walk" is a hypothesis. — State the purpose.
- [ ] `:1413-1422` orphan: "How long after a reaction begins the victim is
  rebuilt, per tier … Not settings" spliced onto the `ReactionAnimationState`
  doc. — Delete.
- [ ] **`ReactionAnimationState` is assigned twice**, `:1438` and `:1776`, with
  different docs. — Keep one.
- [ ] `:1442-1444` orphan: "How long after the rebuild the victim is asked to
  re-plan". — Delete.
- [ ] `:1458-1467` `PhysicsReadyMs` — "the readiness probe this replaced …
  Before this, the brake and the damping waited on a probe". — One frame; the
  handover is observed at 16 ms.
- [ ] `:1469-1477` `RetaliationPollMs` — "The per-tier tables live in Tiers.lua"
  is spliced into its doc. — Delete the sentence.
- [ ] `:1519-1527` `RepairStepValue` — sweep narrative. — One step is 0.1389,
  the argument is ignored, the ceiling is 0.8430.
- [ ] `:1535-1546` `CatchYieldImmediately` — "measured as `YieldCaught…`",
  "Turn it on only if a victim is ever seen running". — Constraint only.
- [ ] `:1576-1582` orphan "How the ragdoll handover is watched…" heads the
  `AudioProxyLifetimeMs` doc, which also carries "measured at four
  microseconds". — Move the orphan to `RagdollAnimationState`; trim.
- [ ] `:1591-1618` the `FallPending` doc is spliced into the middle of the
  `RagdollAnimationStates` doc, so each table sits under the other's text.
  Both are history ("the mod only ever knew the first. Counted over a
  session's log…"; "The readiness cooldown used to prevent this… the diary
  said so"). — Separate; constraint only.
- [ ] `:1636-1648` `RagdollLandCeilingMs` — "On the fifteen second ceiling that
  victim waited out…". — Keep the 1.9 to 2.9 s derivation.
- [ ] `:1707-1716` `ApplySettings` — stillness cvars under a title-case comment,
  with a needless `local threshold`. They overwrite the player's own
  `wh_rd_Still*` cvars on every load. — Tidy; say so in the settings file.
- [ ] **`GrantPerks` runs twice on every load**: in `ApplySettings` (`:1703`)
  and again in `uiActionListener` (`:1938`). — Remove one.
- [ ] `:1720-1758` `AnimationDatabases` doc — "the reason given on
  ImpactProbeSamples above" (it lives in `Health.lua`), "what 2.0.0 shipped",
  "the last point where the mod touched Theresa", a trailing empty `--`. —
  Fix the pointer; cut the history.
- [ ] `:1784-1790` `AnimationSets` — "it resolves correctly, but … and stops"
  reads as a finding. — State the constraint.
- [ ] `:1860-1897` load-screen reset — "was missed, which is the whole of
  why…", "Measured: presses reached the hook at +112 ms…", "the other
  deadline missed when the rear's was fixed". — One sentence: level time
  rewinds on load, so every deadline stamped against it is cleared.
- [ ] `:543` — "Knockdown impulse. Trot and gallop only"; `ThrowByTier` trims
  `Knockback` and `Uplift` for the charge too (`Reaction.lua:318`). —
  Correct. (Found in the `Armor.lua` pass.)
- [ ] `:955-958` barding — "Three flat effects rather than one multiplier";
  damage is a multiplier. — Correct. (Found in the `Armor.lua` pass.)
- [ ] `:1842-1853` `uiActionListener` logs every UI event whose name contains
  dialog, item, money, msg, surrender or inventory whenever `LogTelemetry` is
  on. Investigation scaffolding. — Remove, or ruling.

### src/HorseCollisionMod_Settings.lua

Player-facing: descriptive only, no rationale, no measurements, no history.
Developer reasoning belongs in the entry point's `@field` list or
`docs/TECHNICAL_DETAILS.md`. Most orphans and duplicates in the entry point
recur here.

Orphans and misplaced blocks:

- [ ] `:36-40` — "They used to live here… which is why" is history. — Cut.
- [ ] `:136-145` — describes a health floor ("Set it to 0 to restore the
  behavior 3.0.0 shipped with") above `SuppressAutoCureSec` and
  `AutoCureHealthLimit`, which are not a floor. — Rewrite for the two
  settings under it.
- [ ] `:149-158` — the retaliation paragraph sits above the key bindings; the
  retaliation settings are at `:317`. — Move.
- [ ] `:179-196` — five orphan paragraphs above `ImpactDustEffectRear`: the
  charge push, the rear as its own tier, the rear's landing sound, "Its level
  is fixed", and "The two armor layers sit further back than they did… Both
  were confirmed playing in the log". — Delete; keep one line on the rear
  dust.
- [ ] `:199-208` — the charge's sound paragraph sits above the strike
  settings, and says `hs_hp_soil` "is set back from the ear", which `:861`
  says does nothing because the event ignores position. — Delete; the
  charge's sound note goes beside `ImpactSoundByTier`.
- [ ] `:342-361` — two damage-model paragraphs sit above `HitStrengthByTier`;
  the damage settings are at `:640-665`. The first says clothing sums to
  about 0.4 and is ignored; `ImpactDamageIgnoredArmor` is 0.5, which the
  worked example in the second uses. — Merge into one block above
  `ImpactDamageByTier`; use 0.5.
- [ ] `:423-431` — "What a tier does to the victim's body" heads
  `ImpactSoundByTier`; it belongs to `ReactionByTier` (`:552`). — Move.
- [ ] `:918-943` — the hit-readiness block (see the entry point finding),
  with its history ("The settle was 2000… That is what 'muddy and
  unresponsive' was"). Only `:944-948` describes `HitMinIntervalMs`. —
  Delete the rest; drop the two blank lines after.

Contradictions with the code:

- [ ] `:430-431` — layer format given as `{ event, delay, volume, optional
  pitch }`. `Sound.lua:255-258` reads `{ trigger, delay, distance, chance }`.
  — Correct.
- [ ] `:502-503` — `RiderVocalByTier` format given as `{ event, delay, pitch,
  volume }`; `Sound.lua:518-521` reads `{ trigger, delay, distance, chance }`.
  — Correct.
- [ ] `:272-278` — the lean doc names `LeanPeriod`, `LeanAmplitude` and "a
  period of 30 and a duration of 2"; the settings are `LeanTravelAmplitude`
  and `LeanHoldAmplitude`. `LeanPollMs`, `LeanDeadband`, `LeanMinFlipMs`,
  `LeanRunawayFactor` and `LeanShakePeriod` carry no comment. — Rewrite
  against `Lean.lua`.
- [ ] `:560-566` `ThrowByTier` — "What makes a charge throw further than a
  gallop is the speed it is resolved at". The charge's throw is
  `RearChargeThrow` times the lunge transfer; `ThrowByTier` is only trim on
  `Knockback` and `Uplift` for both tiers. — Say so.
- [ ] `:577-584` `ThrowProfileByTier` — describes the charge's cap as a
  counter-impulse held at the commanded speed; confirm against
  `Tiers.lua:371`. "armour" twice at `:588`. — Reduce to the three steps
  and the formula; American spelling.
- [ ] `:667-670` `CameraShake` and `:684` `RiderBlur` — "a gallop impact",
  "Gallop only: a trot knockdown should stay a shove"; both are per tier and
  the trot shakes at 0.6. — Describe per tier.
- [ ] `:766-771` `ImpactSound` — "the horse's own landing carries the weight,
  and a blunt impact ten milliseconds later"; no tier is built that way. —
  Cut.
- [ ] `:789-791` — "Walk names the cloth impact outright"; the walk tier is
  foley and bodyfall, no impact. — Cut.
- [ ] `:867` `ImpactSoundCrack` — "gallop only"; `Sound.lua:244` plays it on
  gallop and charge. The same error is in the `Sound.lua:240` comment. —
  Correct both.
- [ ] `:953-970` `ImpactDust` — describes a distance test against
  `ImpactDustSettleDistance`, which does not exist; the code watches
  vertical speed (`ImpactDustFallVz`, `ImpactDustLandVz`, `Marks.lua:319`).
  "The victim's height is position is sampled" is garbled. `arrow_soil` and
  "alternatives worth trying" as in the entry point. — Rewrite.
- [ ] `:989-990` `CollisionIsCrime` — "at trot and gallop"; `Impact.lua:233`
  reports a crime for any impact that wounds, which includes the rear and
  the charge. — Correct.
- [ ] `:1018-1021` `BarkCooldownMs` — "Keep at or below `HitCooldownMs`"; no
  such setting, and at 3000 it is already above `HitMinIntervalMs` (700). —
  Cut.
- [ ] `:556` `ReactionByTier` — "a rear is a trot-class blow, not a gallop's"
  ranks one tier under another. — Cut.
- [ ] `:640-648` `ImpactDamageByTier` — "kills about nine unarmored men in
  ten": with 0.15 variance a 111 hit exceeds 100 health about 83% of the
  time. — Verify NPC health and restate, or cut.

- [ ] `:127` `ArmorReferenceWeight` — "the weight counted as a full set";
  it is the weight whose impulse multiplier is 1.0 (the block above says
  so). — Correct. (Found in the `Armor.lua` pass.)
- [ ] `:730-732` barding — "Three flat effects rather than one multiplier";
  damage is a multiplier. — Correct. (Found in the `Armor.lua` pass.)

Duplicates:

- [ ] `:780-865` — the layer format, the distance-is-volume paragraph and the
  token paragraph each appear three times, and the walk, trot and gallop
  notes appear twice (inside the table at `:433-466` and again as orphans at
  `:846-865`). — One copy of each above `ImpactSoundByTier`; the tier notes
  stay inside the table.
- [ ] `RiderBark` (`:905`, default false) and `RiderBarks` (`:1017`, default
  true) are separate switches with near-identical names; both are read
  (`Bark.lua:464`, `:1045`). — Say in each comment what the other does, or
  ruling on merging them.

Fragments:

- [ ] `:1040-1041` `ProtectMutt` — "around on his back" is a stray fragment.
  — Cut.
- [ ] `:1114-1115` `RearChargeStrikePollMs` — "further hits" is a stray
  fragment. — Cut.
- [ ] `:777` — trailing empty `--` line. — Cut.

Narrative, rationale and people (player-facing, so reduce to what the setting
does):

- [ ] `:49-91` — the `DynamicRecovery` block and the "Native Engine Ragdoll
  Stillness CVars" label are title-case banners; the stillness settings
  overwrite the player's own `wh_rd_Still*` cvars and do not say so. The
  first block follows the DynamicRecovery ruling. — Say what the cvars are.
- [ ] `:159-168` — "the key a vanilla action answers to is not always
  visible…" is developer reasoning. — Keep the list of eight keys.
- [ ] `:174-175` — "set by feel". — Cut.
- [ ] `:212-228` `RearChargeImpactSpeed` and `:230-247` `RearChargeThrow` —
  measurements (0.02, 0.07, 25.9, 0.3 to 1.0 m) and design argument. —
  Keep: the figure is `RearChargeImpulse` over horse mass and should follow
  it; `RearChargeThrow` is the dial.
- [ ] `:248-266`, `:303-315` fear bands — "a man", "where he is standing";
  "the rank Henry's own lines were confirmed audible at". — Keep the reach
  derivation in one line; "they"; cut the history.
- [ ] `:322-323`, `:980-985` — victims are "him", "a man". — "they".
- [ ] `:524-526` `RiderBlurByTier` — "they came apart in tuning". — Cut.
- [ ] `:755-761` `HorseBoltsWhenSpent` — "A horse that always bolts is a
  punishment…". — Cut.
- [ ] `:896-916` `RiderBark`, `RiderBarkPriority` — points the player at
  `Bark.lua`; "confirmed audible in testing… makes the tested configuration
  the default". `RiderBarkKill` has no comment. — Describe each setting.
- [ ] `:1057-1063` banner — "tuned by riding at people repeatedly and the
  shipped values are the ones that felt right". — Keep only that deleting a
  line restores the default.
- [ ] `:1086-1093` — "Raise the risk here", "came out of tuning them
  together", "adding to it fought that". — Describe.
- [ ] Undocumented keys: `HorseVocal`, `HorseVocalCooldownMs`,
  `HorseVocalRankByTier`, `RiderBlurHoldMs`, `RiderBlurChroma`,
  `RiderBlurSteps`, `RagdollBrakeArmorScaleArmored`,
  `RagdollBrakeArmorScaleUnarmored`. — One line each, or move them under
  the Internals banner.

### src/HorseCollisionMod/Tiers.lua

- [ ] `:9-13`, `:21-23` header — "That shape is what let the rear and the
  charge quietly fall out…", "the entry point carried a second copy of all
  eight, and they drifted". There are nine tables. — Cut the history; say
  nine.
- [ ] `:67-70` `GetSpeedTier` — "It sat in `Log.lua` for as long as…". — Cut.
- [ ] `:98-133` `ImpactDamageByTier` — "across the whole testing diary",
  "measured live at `dealt=92.2 engineTook=29.1`", "The earlier 95 was set
  when…", "Measured live at 117.2 and 116.0", "the rider wanted", "Making it
  kill one in six would have cost 89", victims as "a man". The gallop
  derivation says 113 before barding and 111 with it, but
  `BardingDamageBonus` raises damage, so barding cannot lower the figure. —
  Keep the arithmetic (health 100, variance 0.85 to 1.15, the threshold per
  tier); verify and restate the barding step; "they".
- [ ] `:146-173` `StaminaShareByTier` — "measured 210 on the test horse and
  230 on another", "the diary records", "by the rider's ruling". — Keep the
  derivation: 0.20 is one pool at level 0 and five at the top; the perk
  unlock costs 0.72 and 0.60.
- [ ] `:194-196` `ReactionByTier` — "The rear sits with the trot… the old
  `RearReaction or TrotReaction` fallback" is history and ranks one tier
  under another. — Cut.
- [ ] `:205-222` `ThrowByTier` — "two such figures sat in the code for
  months", "the audit's fourth ruling", "It was briefly made to scale…".
  "What separates a charge from a gallop is the speed it is resolved at, and
  everything downstream is the gallop's own machinery" is false: the charge
  has its own launch and rail in `ThrowProfileByTier`. `ThrowByTier` reaches
  both tiers only as trim on `Knockback` and `Uplift`
  (`Reaction.lua:318`). — State that and stop. Resolves the settings file's
  `ThrowByTier` finding.
- [ ] `:228-297` `ThrowProfileByTier` — "years of circles", "every previous
  attempt here was", the 0.02, 0.07, 25.9 and 0.3 to 1.0 m readings. "armour"
  at `:269-270`, `:286`, `:316-319`, `:329` comment. — Keep the ownership
  statement, the three steps and the formula; American spelling.
- [ ] `:373-379` — "measured, a victim railed at 6.03 was driven to 8.64 and
  9.17 m/s". — Constraint only: drag does not bind a ragdoll, so the rail is
  enforced.
- [ ] `:401-403` `HitStrengthByTier` — "The charge used to probe itself as a
  minor injury…". — Cut.
- [ ] `:452-478` `TierTables` — the drift story (`:457-462`) and "those
  figures are now the same ones the shipped build runs". The claim of "one
  literal per concern" is false while the settings file ships whole copies
  of all nine tables (see the ruling). — Cut the history; describe the
  binding.

### src/HorseCollisionMod/Armor.lua

- [ ] `:1-15` module header — says two multipliers through a single curve.
  The stamina half is `ArmorStaminaAdd`, a surcharge off its own anchor, and
  damage is a third effect on `smash_def`; only the impulse uses
  `ArmorCurve`. — Rewrite: impulse (weight, `ArmorCurve`), stamina surcharge
  (weight), damage (`smash_def`), plus barding.
- [ ] `:15-16` no blank line or `---` between `@release` and the `TackTypes`
  doc, so LDoc folds "The `armor_type_id` values worn by a horse" into the
  module doc. — Separate.
- [ ] `:16-27` `TackTypes` — two docs spliced ("The values worn by a horse…"
  then "Only the saddle and the horseshoes…"); "which is why the barding
  multiplier had to be cranked before it did anything" is history. — One
  doc: ids 10 and 11 are tack; 12 is excluded because the game files
  head-and-neck barding under it.
- [ ] `:61-64` `ItemIndex` — "This replaces a 50 KB table… the download no
  longer carries them". — Cut.
- [ ] `:154-156`, `:159` `ArmorOf` — "`tack` true… is what Phase 3 barding
  needs". Nothing passes `tack` true: `BardingCoverage` (`:540`) calls
  `ArmorOf(horseEnt)` and sums the non-tack pieces. The doc also calls spurs
  and bridles tack; neither id is in `TackTypes`. — Drop the unused
  parameter (always exclude tack; behavior unchanged); rewrite the doc.
- [ ] `:237-246` `ArmorCurve` — "One curve serves both halves… the stamina
  cost takes it directly". `ArmorImpulseScale` is the only caller and always
  passes `invert` true. — Describe it as the impulse curve; drop `invert`,
  or record why it stays.
- [ ] `:304-318` `ArmorLerp` — "four copies of the same seven lines", "named
  for the brake because that is what first needed them", "Reading the
  endpoints as… is the way round it". The consumer list (brake, cap, drag,
  recovery) omits the charge's `transfer` (`Tiers.lua:366`); the recovery
  use goes with the DynamicRecovery ruling. — Keep: the span is
  `RagdollBrakeArmorScale*`, inside the curve's 0.35 to 1.5, and a villager
  (about 1.15) lands near but not at 1.
- [ ] `:364-367` `ArmorStaminaAdd` — "It used to be a multiplier running 0.75
  to 3.0…". — Cut. Keep the 50 derivation (villagers 5 to 7, mailed guards
  45 to 65).
- [ ] `:406-418` `ImpactDamageScale` — two `---` doc headers spliced; the
  first names `ArmorStaminaScale`, which does not exist, and calls this "the
  third of the three armor multipliers". — Delete the first block; keep the
  weight-versus-`smash_def` sentence in the second.
- [ ] `:423` formula omits `ImpactDamageArmorCurve` and the floor. — Give the
  full expression.
- [ ] `:427-431` — "Measured against the raw figure, a villager was already
  taking 17 per cent off…". — Constraint only: clothing sums to 0.30 to
  0.50 and is subtracted.
- [ ] `:441-449` table — multipliers check out at scale 2.9, ignored 0.5,
  curve 1. The hits column does not at gallop 111 ±15% on 100 health: heavy
  mail (33.6) is 3 to 4, plate (22.3) 4 to 6. — Recompute with the
  `Tiers.lua` health check, or drop the column.
- [ ] `:473-497` inner comment — "measured on ordinary town guards it lands
  between 0.08 and 0.19" contradicts the table (guard 0.52; it predates the
  2.9 scale). "a man", "Before `ImpactDamageOwnsTheHit` handed…", "a gallop
  now worth 111". — Keep: the curve exponent (1 is the plain hyperbola) and
  the floor, 0.14 = the engine trample's mean 16 over 111; "they".
- [ ] `:521-526` `BardingCoverage` — "barding's three effects are flat
  additions and reductions"; `BardingDamageScale` is a multiplier. `if not
  barding` (`:542`) can never be true. — Correct: force and stamina are
  flat, damage is a multiplier on the victim's damage; delete the dead
  check.
- [ ] `:600-601` `BardingDamageScale` — "Damage is a number rather than a
  picture, so a subtle change here is actually achievable, unlike
  knockback". — Cut.
- [ ] `:612-618` `BardingStaminaRelief` — "the half of barding a player
  actually feels: one more guard ridden down…"; "the two surcharges" (the
  combat surcharge and the armor one — name them). — Describe.
- [ ] `:219-220`, `:233-234`, `:286-287`, `:299-300`, `:341-342`,
  `:358-359`, `:507-508` — two blank lines between functions; the rest of
  the file and the other modules use one. — One.

### src/HorseCollisionMod/Reaction.lua

- [ ] `:1-19` module header — "`Ragdoll` and `ImpulseVictim` hand the body
  to physics": `Ragdoll` does, `ImpulseVictim` only pushes a body already
  handed over. No blank line or `---` between `@release` and the
  `SendHitReaction` doc (same LDoc fold as `Armor.lua`). — Correct; separate.
- [ ] `:26-27` `SendHitReaction` — says the message does not produce the
  bark; the settings file (`:1139-1140`, "posting this is what makes
  vanilla's own barks fire") and the entry point's `@field` (`:171`, "so
  barks still fire") say it does. — Settle which is true from the diary;
  make all three agree.
- [ ] `:72-73` `PlayReaction` `prefix` — lists `hcm_stagger_` at walk and
  `hcm_knockdown_` at trot. Shipped: walk stagger, trot and rear `hcm_fall_`;
  nothing ships `knockdown`. — List the three prefixes without tiers.
- [ ] `:80-89` — two comments on the same `so_` strip; the second is
  history ("which is how every direction ended up sharing one ragdoll
  timing"). — One line: option names and per-direction tables use the bare
  word.
- [ ] `:92`, `:1374-1379` — stray blank lines (double blank inside a
  function; five trailing). — Remove.
- [ ] `:97-102` — "This used to say the women had no AnimationControlled
  fragment…". — Cut.
- [ ] `:119`, `:920-933` — misindented `local ok, err`, comment block and
  `local function requestFall`. — Reindent.
- [ ] `:132-145` release repeats — "Victims were still being carried
  through walls occasionally". The first attempt's 50 ms is a literal. —
  Keep: a fragment re-applies its movement layer while blending, so the
  release repeats. Name the 50 or tie it to `ImpulseDelayMs`.
- [ ] `:160-183` fall handover — two comments spliced; "The innkeeper
  leaning on nothing" anecdote; "Until then both tiers that can knock
  someone down default to fall" is roadmap. — Keep: the fragment's Ragdoll
  ProcLayer times the handover; only `hcm_fall_` carries one, so only it
  gets the rebuild wait.
- [ ] `:185` "is now in flight" — timeless word. — "is in flight".
- [ ] `:215-219` `PlayTierReaction` — "Every tier used to decide this at its
  own call site…". — Cut to: the one place a tier becomes a reaction.
- [ ] `:239-241` — "reads exactly like vanilla's non-reactions, which is the
  thing this mod exists to replace". — Constraint only: a victim getting
  up still takes the reaction.
- [ ] `:268-275` — "which is why it is so hard to reproduce on purpose";
  "The readiness cooldown used to prevent this… the diary said so". — Keep
  the mechanism (a second clip cancels the first's pending handover); cut
  the rest.
- [ ] `:331`, `:1291` "armour", `:624` "neighbouring" — British spelling. —
  American.
- [ ] `:344-364` `WhenVictimIsPhysical` — "`actor:Fall` requests the fall":
  `Ragdoll` plays `SettleFragTag`, not `actor:Fall`. Carries measurements
  (1.81 m to 1.57 m over 18 impacts), "the rider described the victims as
  bricks", and a paragraph on the removed mass probe and its three
  settings. — Keep: physics writes to a body not yet ragdolled are
  discarded; the wait is `PhysicsReadyMs`, one frame.
- [ ] `:399-401` `DampVictim` `armorScale` — "Chooses the commanded throw
  distance". In this function it is only printed on the telemetry line;
  armor reaches the throw through `profile`. — "Logged only".
- [ ] `:421-432` `bodyPos` — "this project established that once already",
  "every one was fiction… while the rider watched". — One sentence: the
  entity does not follow a ragdoll; read the physics body.
- [ ] `:445-447`, `:529-531` banner blocks ("The Impact Parachute", "The
  Anti-Slide") — no other module uses them; the names appear nowhere else.
  — Replace with one plain line each, or drop.
- [ ] `:515-519` brake timing — "the diary checked exactly this and found
  16.83 m/s against a later `airPeak` of 12.51". `:524` `+ 10` is a
  literal. — Keep: the gallop's victim is thrown at contact, so the brake
  fires at the impulse delay. Name the 10 or record why it follows the
  impulse.
- [ ] `:586-591` — "It was computed and then dropped from this line…". —
  Cut.
- [ ] `:599-625` `release` — twenty lines of diagnosis ("Diagnosed from the
  rider's cure", "That is why the symptom was intermittent"). — Keep: a
  sleeping body discards writes, so wake it first; otherwise `min_energy`
  stays set and a corpse can sleep mid-air.
- [ ] `:642-648` — "A ceiling of 6 m/s was letting bodies travel eight to
  twelve meters because it was watching the wrong thing". — Keep: the cap
  and drag act on this speed, so it must be the body's.
- [ ] `:699-735` cap — carried forward from `Tiers.lua`. A table of 24
  throws, "the 1,208 kg the mod used to write", "The rewrite is gone". —
  Keep: the cap is a ceiling, not a subtraction, so it holds however the
  body got its speed; on a launch tier it is a rail at the commanded speed.
- [ ] `:743-762` rail enforcement — "Measured on a victim railed at 6.03…",
  "the enforcement that was removed". — Keep: drag does not bind a ragdoll;
  a counter-impulse of `mass * (speed - cap)` does, every poll, and cannot
  shorten the commanded throw.
- [ ] `:809-824` drag — measured peaks, "The rider rode armored victims at a
  flat 15.0 and reported no syrup". — Keep: `strength` saturates at
  `cap + span`, so the drag figure itself is armor scaled.
- [ ] `:863-868` `Ragdoll` doc — "Used at trot and gallop" (shipped: gallop
  and charge); "`actor:Fall` switches the victim". — Correct both.
- [ ] `:873` `tierScale` — "share of the configured impulse, 0 to 1"; it is
  `ThrowByTier`, trim on `Knockback` and `Uplift`, and nothing clamps it. —
  "the tier's `ThrowByTier` trim".
- [ ] `:874-875` `armorScale` — "sets their ragdoll mass and nothing else".
  The mod writes no mass (`:1194-1195` says so); it is passed on for
  logging. — Correct.
- [ ] `:882-885` `tierName` — justifies itself by `ImpactDamage` returning
  early. — "Logged on the `FallToBlend` line."
- [ ] `:888-899` damping clear — "one cause for three symptoms that looked
  separate", "Measured, a commanded 3.00 m/s… eight centimeters" (the same
  figure again at `:910-911`). — Keep: a body under `min_energy` sleeps and
  ignores impulses, so clear it first.
- [ ] `:906-919` — describes calling `RagDollize` then `Fall`; neither is in
  the code, and `:1025-1029` says `RagDollize` must never be added. —
  Delete.
- [ ] `:920-932` settle fragment — "the delayed reaction bug where a victim
  takes the hit, walks three steps". — Keep: `actor:Fall` is queued behind
  an uninterruptible animation; an interactive action with a Ragdoll
  ProcLayer at ExitTime 0 is not.
- [ ] `:947-961` `FallToBlend` — "the two moments the rider named", "Every
  earlier attempt read a position during the ragdoll and failed". — Keep:
  the two readings sit outside the ragdoll, where the entity matches the
  body.
- [ ] `:1031-1034` — "Nothing below throws the victim. The throw is the
  engine resolving its own collision". False for the charge:
  `ImpulseVictim` adds the launch. — Rewrite: the gallop is thrown by the
  engine and braked; the charge is thrown by the launch; both wait for a
  physical body.
- [ ] `:1041-1049` — "This tier uses actor:Fall" (it does not); both
  comments describe `WatchTurn` and `TraceRecovery` as controls for an
  investigation. They are diagnostics gated on `TraceRecovery`. — One line:
  traced as `engine-ragdoll` for comparison with the fall path.
- [ ] `:1052` `state, waitedForBody` — unused. — Drop.
- [ ] `:1063-1072` `ImpulseVictim` doc — "Separated from `Ragdoll` because
  the fall tier… needs the push without the rest": `Ragdoll` is the only
  caller. `profile` and `armorScale` undocumented; `horseEnt` and
  `horsePos` documented out of order. `armorScale` is unused in the body.
  — Rewrite the doc; drop `armorScale`.
- [ ] `:1094-1097` — "Leaving early on their account was what stopped the
  charge being thrown at all". — Keep: a launch tier proceeds with zero
  trim.
- [ ] `:1112` `+ 1.0` chest height — literal. — Name it, or record the
  derivation.
- [ ] `:1119-1124` — "the same target took 67.3 at full speed and 37.7…". —
  Keep the first paragraph; cut the measurement.
- [ ] `:1132-1138` — "which is exactly what a charge did whenever…". — Keep:
  with no velocity there is no direction; drop the impulse.
- [ ] `:1187-1190` — "which left a report of armored targets moving
  further…". — Cut; keep the mass explanation.
- [ ] `:1234-1238` — "a fixed 50 ms produced throws of four meters and of
  nothing at all". — Keep: an impulse before physicalization is ignored.
- [ ] `:1283-1289` — "a quarter of a second after impact" (`ImpulseDelayMs`
  ships 50); measurements 12.44 / 14.04 / 21.73 m. — Keep: floor here,
  ceiling in the watch.
- [ ] `:1310-1317` — "threw a peasant ten meters… thirteen samples", "a
  man". — Keep: the launch goes along the horse's line; the lift is trim.
- [ ] `:1345-1369` `ImpulseApplied` — reads `GetWorldPos`, which `:421-428`
  says does not follow a ragdoll, so `movedIn300ms` does not measure the
  body. "a quarter of a second later" (it is 50 ms). `300` is a literal. —
  Read `GetCenterOfMassPos`, or drop the movement figure.

### src/HorseCollisionMod/Rear.lua

The detection loop stands aside while `ChargeScoringUntil` is open
(`Update.lua:91`); it never scores a charge contact. Several comments here
say the opposite, and `RearCharging` is cleared by `WatchLunge`, not
`ChargeForward`. Those two corrections recur below.

- [ ] `:3-5`, `:1135-1137` — the "everything else needs speed" framing is
  said twice; the second adds "a stationary rider has never had anything to
  do but shove people". — Keep it once, in the module header.
- [ ] `:64-67` — the log lists the keys as `r, q, y, u, o, h`; `RearKeys`
  and the action map also declare `e` and `f`. — Build the list from
  `RearKeys`.
- [ ] `:92-100` `HookRearKey` — "bound to `jump`, this reared the horse and
  then jumped anyway" is history. — Constraint only: consuming a press does
  not stop the game acting on it, and a hold and a tap both deliver one
  `press`, so the mod uses its own action.
- [ ] `:172-184` `TrackHorseSpeed` — measurements (0.24, 0.12 m, 128 ms,
  0.94 m/s) and "The slide is the whole defect". — Keep: `GetVelocity`
  under-reports a slow horse, so speed is derived from two positions.
- [ ] `:220-224` — "These gates all returned silently… after seven attempts
  at the action map had not." — One line: each refusal logs its reason.
- [ ] `:275-278` — "Asking only the horse is what made the gate useless". —
  Constraint: a nil velocity would read as zero and pass every press.
- [ ] `:295-310` — "is not established", "was briefly thought", "the rider
  riding away", "is now short enough". — Keep: horizontal speed only,
  because the vertical component carries the settling fall.
- [ ] `:331-342` — measurements (0.24, 0.11 m/s, 1.4 cm, 0.00). — Keep:
  only the locomotion state predicts whether a rear slides.
- [ ] `:361-366` — "a second press there doubled the push" is history. —
  Keep the constraint: between the rear and the push the horse reads idle
  at 0 m/s, so the move's own state gates a second press.
- [ ] `:376-377` — "They used to share `RearNextAt`". — Cut.
- [ ] `:386-387` — "e.g." and a run-on, out of the file's register. —
  Rewrite; see the ruling on the cooldown icon after a wind-back.
- [ ] `:466` `UpdateMoveCooldowns` — "on a save load, which drops the
  deadline": a load winds the clock back and leaves the deadline in place
  (`:386`, `:1328-1329`). — Correct once that ruling is settled.
- [ ] `:488-495`, `:759-760`, `:832-833` — stray blank lines. — Remove.
- [ ] `:498-518` `ChargeForward` — "used to travel by root motion", the
  three movement-control measurements, "measured at 4300… at 20000". —
  Keep: inside an interactive action an impulse is discarded or stored and
  discharged later, so the rear plays in place and the push follows it.
  Move the measurements to the diary if absent there.
- [ ] `:538-546` — "The rider can steer during the rear, and does";
  paragraph on the old fragment. — One line: the heading is read at the
  push because the player can steer during the rear.
- [ ] `:564-568` — measured delays (1856 ms, 1408 ms). — Cut; the log line
  reports it.
- [ ] `:573-575` — "Started at the press it swept while…". — Constraint:
  the strike starts with the lunge, not the press.
- [ ] `:605-642` `WatchLunge` — "The rider's definition", "What came before
  was three numbers… All three were guesses", "the first version of this",
  measured spikes, and an open question ("is not settled… `moved=` is here
  to tell them apart"). `:634` says the peak is "the larger of each
  neighbouring pair"; the code takes `math.min`, the smaller. — Keep: the
  window closes when speed decays to `RearChargeLungeSpentAt` of the peak;
  the peak is the smaller of two consecutive samples, so one spike cannot
  set it; `RearChargeLungePeakMin` guards an early dip. "neighboring".
- [ ] `:714-717` `LogActionEnd` — "costs a ride per guess". Its instrument
  is `AnimationControlled`, but the standing rear starts with
  `StartAnimation` (`:879`), which bypasses Mannequin, so for the rear it
  likely reports on the first poll. — Cut the phrase; verify the log line
  still measures anything, and delete the function if not.
- [ ] `:761-782` `RearHorse` — describes the standing rear reaching
  `relaxed_rearing` through `StartInteractiveActionByName` and an `hcm_rear`
  option; the standing rear calls `StartAnimation` directly and only the
  charge uses the interactive action (`hcm_rear_charge`). "Reaching it took
  the whole chain", "Every earlier attempt passed the name only". Missing
  `@tparam fragTag`. — Rewrite for both paths; keep the four-file
  requirement and the `ObjectId` argument as constraints.
- [ ] `:787` `tierName` — assigned, never read. — Delete.
- [ ] `:793-797` — says the detection loop scores the charge "as a
  gallop"; it stands aside. "not what the rider asked for". — `RearCharging`
  gates the sweep, the lunge watcher and a second press.
- [ ] `:802-803` "The rider's voice" means Henry's. — "Henry's voice".
- [ ] `:807-817` — lockout anecdote ("the same woman", "the rider saw three
  charges"); "2.6 seconds" duplicates the setting. — Keep: a new press is a
  new attack, so the previous lunge's lockouts are cleared.
- [ ] `:820-829` — "How long the detection loop scores a contact as a
  charge": it is how long the loop stands aside. "cleared by
  `ChargeForward`", "measured at 144 to 256 ms", "before the loop took it
  over". — Rewrite: the loop defers to the sweep for `RearChargeStrikeMs`.
- [ ] `:836-844` — "which `ChargeForward` decides" (`WatchLunge` does);
  "any impact the detection loop finds is scored as a gallop"; "A fixed
  2600 ms outlives the move…". — One line: this timer is the ceiling for a
  lunge never seen to decay.
- [ ] `:876-878` — "SetAnimationDrivenMotion is left alone" beside
  `:858-865`, which sets it; "gracefully". — Settle with the ruling below.
- [ ] `:882` `-- hcm_rear_charge` — restates the branch. — Cut.
- [ ] `:888-891` — "the ordinary detection loop scores it" (the charge). —
  The charge has its own sweep; the standing rear has `RearStrike`.
- [ ] `:901-904` — "The call returns true for any string" describes
  `StartInteractiveActionByName`, which the standing rear does not use;
  `600` is a literal. — Scope the comment to the charge; name the delay.
- [ ] `:919-929` `ChargeStrike` — "until the horse was given a physical
  push", "Whether a special move connects should not rest on how well the
  physics behaved", "The rider asked for". — Keep: the sweep is the only
  thing that scores a charge; no cap, each victim once per charge.
- [ ] `:960-968` — "the sweep ran for 1600", "closed when the horse slows
  below walking pace" (it closes at a fraction of the peak). — Keep: the
  sweep lives while `RearCharging`; `RearChargeStrikeMs` is the ceiling.
- [ ] `:1007-1013` — "The detection loop is scoring the same lunge at the
  same time": it stands aside. "Loop first, then sweep, was the half of the
  double hit that survived". — Check whether `ImpactIsNewContact` is still
  needed here given the stand-down; if kept, state it as a guard.
- [ ] `:1034-1043` — readings 0.02, 0.07, 25.9; "never once clears its own
  minimum… at that 3.0 floor… at 10.5". — Keep: the horse is
  `AnimationControlled` through the lunge and cannot be measured, so the
  charge scores at `RearChargeImpactSpeed`.
- [ ] `:1086-1087` `RearCanHit` — "a faction test gave dogs a human
  fragment… reached women only by a fallback". — Constraint: humans are
  matched by class.
- [ ] `:1230-1235`, `:1247-1248` `RearHit` — the doc says "the trot
  treatment… the charge is the move that earns the ragdoll", but the
  function serves the charge too; the fixed-speed sentence is repeated in
  the body. Missing `@tparam tier` and `hitSpeed`. — Rewrite for both
  tiers; keep the sentence once.
- [ ] `:1264-1269` — "That is the double hit on one lunge". — Keep the
  constraint: the contact is recorded so `HitMinIntervalMs` can measure
  from it.
- [ ] `:1272-1277` — "applying it to both tiers closed a victim out… after
  an ordinary rear as well". — One line: only tiers listed in
  `VictimLockMsByTier` carry a lockout.
- [ ] `:1325-1331` `LoadRearActionMap` — "Nothing here was ever the cause…
  several rides were spent", "+112 ms". — Cut; the refusal logs in
  `RearRequested` say which gate refused.
- [ ] Settings `:269` `RearChargeWindowMs` — "how long a charge counts as a
  gallop"; it is the ceiling on `RearCharging`. — Correct.

### src/HorseCollisionMod/Retaliation.lua

File-wide: "the rider" is used throughout for the player (`:46`, `:483`,
`:509`, `:580`, `:583`, `:688`, `:862`, `:871`, `:888`, `:939-951`,
`:1043-1048`, `:1079-1101`). — "the player". "he/him" for a fighting
victim is accurate (only men reach the fight branch) and stays.

- [ ] `:17-22` — the `q_ledecko` and `q_hareHunt` examples justify the
  method by precedent. — Keep one clause: vanilla quests set context options
  the same way.
- [ ] `:44-49`, `:129-136` — the guard behavior is explained twice; the
  second adds "An earlier revision gated soldiers out; the gate was wrong
  and has been removed." — Keep it once, in `CanRetaliate`; cut the
  history.
- [ ] `:51-73`, `:118-122` — the gender routing is explained twice; `:68-73`
  carries a survey ("twenty one NPCs in Rattay", the morale ranges) and
  "the honest implementation, not a shortcut". — Keep once in the header:
  the combat tree tests gender, not morale, so the mod routes on gender.
  Move the survey to the diary if absent.
- [ ] `:77-78` — no blank line or `---` between `@release` and the
  `RetaliationOption` doc (same LDoc fold as `Armor.lua`). — Separate.
- [ ] `:94-95` — "Confirmed against telemetry rather than assumed". — "The
  values `GetGender` returns."
- [ ] `:138-141` — "if the distinction is ever wanted" is speculative. —
  "Read for the log only."
- [ ] `:183-184` — "this morning… today's ride" anecdote. — Cut.
- [ ] `:213-214` — "The first contact is always free" holds only while
  `RetaliationFreeBumps` is at least 1. — "Contacts up to
  `RetaliationFreeBumps` are free."
- [ ] `:279-281` — "the `Retaliation` line above" refers to a log line in
  another function. — Name it: the `Retaliation` telemetry line.
- [ ] `:328-329`, `:341-343` `IsStillFighting` — "observed on a guard
  closing to two meters"; "An earlier design classified running
  separately… fired in none of six incidents". — Cut both.
- [ ] `:366-369` — "it always arrives": `ReleaseWhenFighting` (`:279-281`)
  logs a victim who never reaches the fight as the case to watch for. —
  Drop the claim; state that `alwaysFightWhenHit` removes the morale test.
- [ ] `:372-373` — "in six measured incidents it was never reached". — Cut.
- [ ] `:481-500` `RepairVictim` — "which is what made this hard to see",
  "bought five seconds", "That is why an earlier reading of this called
  reputation irrelevant", "stood at a meter and a half for twelve
  seconds". — Keep: the flee in progress and the relationship are separate;
  a stand-down stops the first, raising the relationship changes the next
  decision.
- [ ] `:513-523` — "in a measured sweep" and the argument list tried. —
  Keep: `surrender_step` moves a fixed `RepairStepValue` whatever its
  argument, caps at 0.8430, and does not read back in the same frame.
- [ ] `:568-589`, `:834` — the `EndRetaliation` doc comment is separated
  from its function by `ShowSurrenderHint`; LDoc attaches both blocks to
  `ShowSurrenderHint`, and `EndRetaliation` is undocumented. — Move the
  block to `:834`.
- [ ] `:590-610` `ShowSurrenderHint` — "Nothing told the player so… the
  option existed and was invisible". Missing `@tparam npc`. — Keep: a
  provoked fight does not trigger vanilla's hint. Add the param.
- [ ] `:651-656` — "measured as the prompt appearing correctly, then
  disappearing". — Keep: leaving the saddle swaps the action map and drops
  the hint, so it is re-asserted on an interval.
- [ ] `:686-691` — "Hanging the prompt on that took it down a second after
  it appeared"; says `EndRetaliation` fires when the player is pulled off
  the horse, which `:840-843` says no longer happens (the watcher requires a
  seen fight). — Keep: the prompt follows `IsInCombatDanger`, which is when
  a surrender is possible. Drop the claim about `EndRetaliation`.
- [ ] `:709-714` — "needs six quiet passes… five or six seconds":
  `SurrenderHintCalmPasses` ships 3. "Measured after a beggar was reared to
  death, and newly reachable because the rear can now kill". — Cut; the
  constraint is `:704-707`.
- [ ] `:736`, `:1059` — log lines not gated on `LogTelemetry`, unlike every
  other line here. — Gate them.
- [ ] `:762-766` — "after the action map change wiped the hint… stayed gone
  for the rest of the fight". — Keep: re-showing an id the HUD believes is
  displayed does nothing, so it is hidden first.
- [ ] `:786-787` `SurrenderIsTheGames` — "the same source the retaliation
  answer uses, so the two cannot disagree about who is a soldier":
  `CanRetaliate` reads social class for the log only and does not decide on
  it. — Cut the sentence.
- [ ] `:840-843` — "no longer reads" is a timeless word. — "does not read".
- [ ] `:865-872` — two contradictory comments spliced: "Sent on every
  ending" and "The stand-down is deliberately not sent here"; the code sends
  none. "measured at 0.737". — Keep the second.
- [ ] `:884-904` `WatchAftermath` — "One measured victim was repaired…",
  "Measured on one beggar, one build… fourteen seconds… forty seconds". —
  Keep: the repair is re-run after `AftermathSettleMs` because the player
  may keep hitting the victim; a flee ends at `fleeFromNPCParams.distance`
  (150); a stand-down would stop it but holds the victim about 25 s.
- [ ] `:939-951` — "Measured at 1.93 m/s against a threshold of 1.8… on a
  rider who had shoved one merchant". — Keep: detection cannot tell who
  closed the distance, so no one new is provoked while the player is in
  combat.
- [ ] `:1038-1057` — two comment blocks spliced with no break (offense
  order, then the soldier hint). "which is the whole of what a provoked
  victim did before it existed", "is what made him punch the horse",
  "Reproducible every time", "The mod's own documentation already
  records…". The soldier-hint reason repeats `:782-784`. — Split; keep the
  pull-then-fight order as a constraint; for the hint, refer to
  `SurrenderIsTheGames`.
- [ ] `:1086-1089` — "with a Z angle and a zero angle alongside it" is
  unclear. — Name the cvars or cut.
- [ ] `:1093-1094` — "as it did before". — "without the pull".
- [ ] `:1133` — `local mounted` shadows the outer `mounted` at `:1106`. —
  Rename.
- [ ] `:1143-1145` — "one merchant gets the pull within a second and another
  never gets it". — Cut; the log line speaks for itself.
- [ ] `:1257-1264` — "Measured on one merchant across 32 polls…", "Whether
  the request is honoured anyway is a separate question"; "honoured". —
  Keep: `CanHorsePullDown` returns 2 enabled, 1 disabled, 0 not applicable;
  `PullDownForce` requests regardless.

### src/HorseCollisionMod/Bark.lua

- [ ] `:27`, `:45-50`, `:72-77` — "each of which has already cost a wrong
  choice"; the `KOLIZE_*` paragraph appears twice, both with "reverses an
  earlier decision", "now", "no longer". — Keep one sentence in the header:
  the `KOLIZE_*` sets are pooled because `HushVanillaBark` keeps vanilla from
  playing them itself.
- [ ] `:58-59`, `:306-307` — "for the same reason as `ImpactProbeSamples` in
  the entry point" / "above"; it lives in `Health.lua:27`. `:62-63` a doubled
  empty `--`. — Fix the pointer; one blank comment line.
- [ ] `:82-104` `Shove` — "the mod's own find", the removed
  `KOLIZE_S_HRACEM_LEHKA` story, "The rider heard", "The lesson
  generalises". Header test 3 already states the rule. — Keep the two
  sets' sample lines; cut the rest.
- [ ] `:111-113`, `:1211` — "the rider having just trampled them", "an NPC
  the rider passes". — "the player".
- [ ] `:136-148` hurt grades — "what the victim makes at the moment of
  impact, in three grades"; only `HurtDown` is audible (`:596-609`), and the
  two comments contradict each other. — One comment: `HurtDown` is the
  impact cry; `HurtLight` and `HurtHard` name where the graded recordings
  live and cannot be requested.
- [ ] `:150-164` bystander sets — removal history. Header test 4 states the
  rule. — Cut, or one line naming the three sets as excluded by test 4.
- [ ] `:169-208` `RiderBarkSets` — "These two are confirmed on him" above an
  empty table; the role survey, "The rider rejected it", the audition trap
  and the untested assumptions. — Follows the dead-set-path ruling; if the
  table stays, one line.
- [ ] `:211-297` `RiderBarkAliases` — "was recorded as unrecoverable", "the
  rider chose these", the quoted instruction, "for now", "turned out". —
  Follows the empty-pool ruling.
- [ ] `:299-314` `RiderBarkKillAliases` — the gender column is explained
  here and again in `PoolForVictim` (`:346-349`); "the two filters described
  above" (there are four). — Keep the explanation in `PoolForVictim`; "the
  four filters".
- [ ] `:397-398`, `:446-447` — "two at once is a defect rather than a richer
  moment" twice; "the same man". — Once, in `RiderVoiceReady`.
- [ ] `:400-403` — the rewind sentence is hard to parse. — "A hold further
  out than the longest cooldown means the save clock was wound back; it is
  ignored."
- [ ] `:406-410` — "A grunt is `RiderVoiceGrunt`" (it is
  `RiderVoiceRanks.Grunt`); "four gallop kills… produced one death line and
  three silences". — Correct the name; cut the measurement.
- [ ] `:419`, `:474`, `:527`, `:701`, `:709`, `:999` — redundant parentheses
  around single `cfg` reads. — Remove.
- [ ] `:484` "every spoken line the rider has" means Henry's. — "Henry".
- [ ] `:592-609` `PainByTier` — "Both tiers" over three entries; test
  history ("Both were tested rather than assumed… fourteen requests"). —
  Keep: those sets are combat shouts dispatched outside
  `dialog:monologRequest` and gated on the engine's `hitStrength`. See the
  charge-cry ruling.
- [ ] `:646-648` `PickFromPool` — "once the rider reports which lines they
  actually hear". — Cut.
- [ ] `:689-692` `BarkOnCooldown` — "which is the point of having a
  bystander set at all"; there are none. `:702-705` history. — Keep: per
  speaker, so two victims can both speak; a refusal is logged.
- [ ] `:723-724` `Bark` — "the whole finding of the investigation behind
  this file". `:756` double blank line. `priority` and `overrideSuppress`
  undocumented; `ignoreCooldown` is "used only for the recovery line", but
  `Fear.lua:106` and the recovery groans (`Recovery.lua:1178`) pass it too. —
  Cut; add the two params; describe `ignoreCooldown` without a caller list.
- [ ] `:783-809` — the `HushVanillaBark` note and the message-fields note run
  together with no break; "Three approaches failed… none should be
  retried", "this used to send two of them". — Split; keep: the branch is
  closed ahead of contact by `HushVanillaBark`, and a request below the top
  priority waits or is discarded.
- [ ] `:814-823`, `:892-895` — "a man" for the speaker. — "they".
- [ ] `:850-861` `BarkForTier` — "Mirrors `GetSpeedTier`" (it is a table
  lookup); "graded by how hard they were hit" (trot and gallop both use
  `HurtDown`); `@tparam` lists Walk, Trot, Gallop, and the charge also
  arrives here. — Correct.
- [ ] `:886-895` `BarkCollision` — "which the mod had no counterpart for",
  "The rider heard the gap". — Keep the vanilla condition and its source
  line.
- [ ] `:918-934`, `:965-971` `BarkRecovered` — the three failed timings are
  told twice, with the quoted ride. "about 0.15 of its standing height to
  1.59" mixes a fraction and meters. — Keep: the line fires when the body
  leaves flat, read by `WhenVictimRises`; check the figures in the
  `Recovery.lua` pass.
- [ ] `:947-950` — "the rear and the charge have a voice of their own"; the
  charge ships `"collision"` and reaches this function. — Follows the
  charge's bark set ruling.
- [ ] `:983-984` — "is how the death barks ended up firing over silence". —
  Keep: a dead victim does not rise.
- [ ] `:1031-1037` `BarkDeath` — removal history, and "logs the death and
  says nothing." is a fragment. — Follows the dead-set-path ruling.
- [ ] `:1054-1196` `ShieldFromEngineDamage`, `LiftCollisionShield` — damage
  code in the bark module; the caller is `Impact.lua:73` and the lifter is
  `ApplyImpactDamage` in `Health.lua`. — Move to `Health.lua`.
- [ ] `:1057-1062` — "Five separate levers leave it unchanged" names two. —
  Keep: the engine's collision damage cannot be stopped without a global
  that also governs arrows, so the victim is made immortal through the
  window.
- [ ] `:1071-1072` — "for a few hundred milliseconds"; the shield lasts until
  `ApplyImpactDamage`, after the ragdoll resolves, with a 6000 ms backstop. —
  Correct.
- [ ] `:1083-1088` — "Testing the entry alone was wrong… one was killed". —
  Keep: only a live shield blocks a second.
- [ ] `:1134-1138` — "Every other timer in this mod returns early" on a
  reload; `HushVanillaBark`'s timer does not either. — "Unlike the mod's
  polling timers".
- [ ] `:1200-1209` `HushVanillaBark` — "about ten times a second" and
  "twenty times a second"; `TickSeconds` is 0.033, about thirty. "The rider
  heard the result". — Correct the rate; cut the quote.

### src/HorseCollisionMod/Recovery.lua

- [ ] `:8-13` header — "The two waits"; the file has seven. It says
  `BlendRagdoll` is "while physics owns the body"; `:128-134` says it is the
  get-up on a fall tier and `:264-268` that it is the whole time down on a
  ragdoll tier. — Rewrite: the waits poll the animation state or the body,
  and each carries a ceiling.
- [ ] `:25-26` — no blank line or `---` break between `@release` and the
  `ReleaseActorMovement` doc (the same LDoc fold as `Armor.lua`). —
  Separate.
- [ ] `:36-38` — "victims clipped into walls exactly as they did without
  it". — Cut.
- [ ] `:62-67`, `:90-102` `RecordStandingHeight` — the doc says "Recorded
  once, at the first impact"; the code keeps the maximum ever seen. The body
  is history ("Recording once was wrong… one guard… he was never once
  judged"; "centimetres"). The value is named `head` and read from
  `GetCenterOfMassPos`. — Doc: the tallest reading seen, so a first reading
  off a downed body corrects itself; say what the reading is.
- [ ] `:111-146` — the `IsVictimFlat` doc sits above `DisarmVictim`, so LDoc
  attaches it there, and `IsVictimFlat` (`:221`) is undocumented.
  `DisarmVictim`, `RearmVictim` and `WhenVictimStands` have no docs, and the
  first two lack the file's blank lines around blocks. — Move the doc; add
  one line each.
- [ ] `:141-143` — "The halfway point is a bisection rather than a tuned
  figure" contradicts `:275-282`, "measured rather than bisected". — Cut
  with the `VictimFlatFraction` ruling.
- [ ] `:177-219` — `WatchRecoveryForRearm` is already listed as dead; its
  only callee `WhenVictimStands` is dead with it, and `RisePollMs` and
  `RiseCeilingMs` then serve only `Reaction.lua:964`. `:208` "no longer". —
  Delete both functions; keep the settings for their remaining reader.
- [ ] `:221-230` `IsVictimFlat` — returns one value on a nil victim and four
  otherwise; the orphan doc names one. — Document all four; return four
  throughout.
- [ ] `:252-254` — "interrupting there is what broke the pose". — Keep the
  constraint: a playing reaction counts as flat whatever the height.
- [ ] `:262-287` — "A shortcut stood here", "caught by twice", "Logged from
  play, one guard". — Keep: `BlendRagdoll` means rising on a fall tier and
  down on a ragdoll tier, so height alone decides; then the fraction's
  derivation, per the ruling.
- [ ] `:295-306` `WhenVictimRises` — "The rider heard", "A tuned delay stood
  here", "about 0.15 of its standing height to 1.59": both figures are
  meters. The same error is quoted at `Bark.lua:931-934`. — "from about
  0.15 m to 1.59 m"; cut the rest. See the ruling on the early return.
- [ ] `:332-334` — the inline comment contradicts the doc and `:262-270`. —
  Follows the ruling.
- [ ] `:441-452` `TraceFallLanding` — "the rider has been describing the
  second for hours", the diary's 76 calls. — Follows the diagnostics ruling.
- [ ] `:505-514` `WhenVictimIsUp` — "Named for what it measures", "Two
  separate mechanisms were built on the old reading"; a broken line at
  `:507`. On a ragdoll tier it fires as the victim stands, not on the
  get-up. — Keep: fires when the ragdoll state ends, which is the victim
  standing; the state must be seen first.
- [ ] `:566` `WhenBodyStops` — "the same thing `ImpactThrow` already means":
  `ImpactThrow` is a log line (`Health.lua:335`), not a function. `:571-576`
  "which the rider saw". — Name `RestStillMeters`; cut the story; keep why
  equality is too strict.
- [ ] `:644-649` `FinishRecovery` — skips the rebuild when
  `hcm_combat_injected` is set (`Health.lua:831`, `Impact.lua:234`, `:242`)
  and does not say why. `:660-664` "The delay that used to sit in front of
  this". — One line on the skip; cut the history.
- [ ] `:670-675` `TraceRecovery` — "the complaint is about one of them". —
  "to show which phase is long".
- [ ] `:743-752` `WatchTurn` — the polearm report, "his". — Follows the
  diagnostics ruling.
- [ ] `:869-870`, `:1086-1087` — two blank lines between functions. — One.
- [ ] `:877-878`, `:882`, `:884-887` `ReplanIfStranded` — the bucket
  anecdote, "Measured across nine recoveries", "the wait was only ever the
  cost of a weaker signal". — Keep: a replan restarts the daycycle and
  drops a carried prop, so only a victim idle after the get-up is replanned.
- [ ] `:946-948`, `:957-973` `ReplanVictim` — the entity-link probe, "every
  send this mod made before this one passed an empty payload", "Measured…
  moved him 0.00 m… 3.94 m". — Keep: `Utils.makeTable` fills the declared
  `reason` and `speed`, and an empty payload is discarded.
- [ ] `:1034-1085` `ImpactIsNewContact` — detection logic in the recovery
  module; both callers are `Update.lua:101` and `Rear.lua:1016`. `:1041-1051`
  "Repeats were suppressed by accident before this existed… came straight
  back", "now"; "a rider" for the player; "700 ms" repeats the setting. —
  Move to `Update.lua`; keep: one contact spans several 33 ms ticks, and the
  interval must be shorter than a turn and return.
- [ ] `:1088-1185` DynamicRecovery — follows that ruling. If it stays:
  "peasants", the armor range "~0.35… ~1.26" (the curve spans 0.35 to 1.5),
  the `- 400` literal, `npc:IsDead()` where `BarkRecovered` reads health, and
  the missing blank lines. If it goes, `ArmorLerp`'s consumer list loses
  recovery.

### src/HorseCollisionMod/Health.lua

- [ ] `:1-10` header — names `SuppressAutoCure` and the probe but not the
  damage path, which is most of the file. — One line per part: the probe,
  the auto-cure exemption, the mod's damage and its reclaim, story-character
  protection.
- [ ] `:17-27` — no break between `@release` and the `ImpactProbeSamples`
  comment, so it folds into the module doc (the `Armor.lua` pattern). The
  last two lines explain why it is not an LDoc block. — Separate; cut the
  LDoc aside.
- [ ] `:29-47` `SuppressAutoCure` — "cleared on a timer"; the option is held
  until health is back over `AutoCureHealthLimit`, rechecked every
  `SuppressAutoCureSec`. — Correct.
- [ ] `:65-69` — "reads as the tidier option… sent to a guard in combat, the
  option read back false immediately". — Keep: the brain message can be
  dropped by a busy brain; the direct call writes the table.
- [ ] `:101-103` — "doubles as the repair path for a save carrying stuck
  NPCs". The exemption is non-persistent and the cure patch is vanilla's, so
  this is true, but it is release history. — Cut to "reports false on a
  victim who was never held".
- [ ] `:160-161`, `:350-351` — two blank lines between functions. — One.
- [ ] `:176-178` — "The impulse throws the target, and a change in z…
  separates a fall from anything the collision itself did." — Follows the
  impact-throw probe ruling.
- [ ] `:228-234` — "a long investigation turned on being unable to tell them
  apart". — Keep: an impact on someone already down plays nothing and
  costs nothing, and the state separates that from a failed impact.
- [ ] `:278-281` — "Samples now run past the cooldown… no longer". — Keep:
  `from=` ties each sample to its impact when two interleave.
- [ ] `:296-348` — the rest watcher. Follows the impact-throw probe ruling;
  if kept, `restCeiling = 8000` is an unnamed literal.
- [ ] `:352-403` — the `ApplyImpactDamage` doc sits above
  `PredictImpactFatal`'s (`:404`) with no function between, and the
  function is at `:527`; LDoc gives `ApplyImpactDamage` no doc. — Move it
  to `:527`.
- [ ] `:352-369` — "on top of what the engine charged" and "the mod adds its
  own charge": with `ImpactDamageOwnsTheHit` (shipped true) the engine's
  charge is given back and the mod's figure is the whole cost. "87 per
  cent… with an error bar" is measurement narrative. — Say: the engine's
  charge is nearly flat against armor, so the mod reclaims it and deals an
  armor-scaled figure of its own; keep the variance paragraph.
- [ ] `:383-389` — "A victim the mod kills therefore dies silently, and that
  is a property of this call rather than of the bark system." — Keep the
  constraint; the `BarkDeath` call at `:837` follows the dead-set-path
  ruling.
- [ ] `:391-396` — "by the `combat:hit` that `Crime.lua` sends": the hit is
  sent from `Impact.lua:233` when the victim rises, and from `:830` here on
  a death. — Correct.
- [ ] `:401` `@tparam playerEnt` — "named as the attacker"; the attacker
  WUID (`:561-567`) feeds only the `attributed=` log field, and `DealDamage`
  takes no attacker (`:377-381`). — Delete `attacker`; describe
  `playerEnt` as the player the death is attributed to when crime is on.
- [ ] `:403` `@treturn` — "the damage dealt, or 0"; the function returns the
  rolled figure before the deferred path runs, whether or not it is dealt,
  and `Impact.lua:251` ignores it. — Return nothing.
- [ ] `:406-412` `PredictImpactFatal` — "produced words a second and a half
  after… never got a line whatsoever". — Keep: the damage is deferred until
  the body stops, so a line chosen from it arrives late.
- [ ] `:414-427` — says the prediction is taken at the **top** of the
  variance roll; the code (`:465-468`) uses the intended figure, the
  center. `4a36c11` chose the center deliberately and its message says so;
  the comment was rewritten the other way in the same commit. "Three of
  seven kills in one ride". — Rewrite for the center: a death line over a
  survivor is the worse error, so the prediction is the average outcome and
  misses some kills near the margin.
- [ ] `:429-431` — "The mod reclaims it" holds only with
  `ImpactDamageOwnsTheHit`. — Say so.
- [ ] `:473-499` `IsProtectedFromHarm` — "measured taking Bernard from 100
  down to 66", "reading it here reported every victim… six gallops", "has
  not been seen". — Keep: `DealDamage` ignores immortality; `apr` comes from
  `vip_attackprot` and the mod never writes it; `imm` is set on every victim
  by the shield, so it cannot identify anyone; the known gap is an immortal
  character without `apr`. Keep the `rat_bernard`/`villageGuard` sample.
- [ ] `:533-536` — "The settings file wins… belong where a player or a test
  can reach them rather than compiled in." This is how `TierValue` works
  for every table. — Cut.
- [ ] `:569-599` — "this is the whole of the crime fix", "until now a coin
  toss", "hanging offence" (British), and "A fixed wait, not a poll, and
  deliberately so", which contradicts the `WhenBodyStops` wait at `:888`.
  `:600-612` "the mod's design has always been… What it never did". —
  Collapse with `:675-697` into one block: the engine's trample is
  attributed to the rider and cannot be gated, and `sb_switch_awareness.xml`
  raises `murder` only from an attributed hit; so the victim is shielded
  from contact until the body stops, the engine's charge is reclaimed, and
  the mod's blow is the one that kills. Cite the setting, not 22.7 or 95.
- [ ] `:619-631` — "The Cheat mod's immortality works because…". — Keep
  the constraint: an NPC's health cannot be raised past 100 from Lua, so the
  exemption lives here and holds only `tools/dev_subject.lua` spawns.
- [ ] `:642-648` — "about 18 a pass", "still died after a handful of runs…
  the rider was charged with murder". — Keep: the engine charges a
  collision too, so health is restored to its value at impact.
- [ ] `:642-673` — the test-subject path returns before `deal`, so it never
  calls `LiftCollisionShield`; the shield comes off only at its 6000 ms
  backstop. — Lift it in this path as well.
- [ ] `:675-680` — "Nothing is timed here any more, and the local that used
  to hold a delay". `:677-679` says the test subject has "no body to watch";
  the subject is thrown like any victim, and the restore uses a timer only
  because nothing is dealt. — Cut; one line on why the restore is timed.
- [ ] `:687-692` — "Nothing here tries to work out whether this impact will
  be lethal any more", beside a function (`PredictImpactFatal`) that does,
  for the bark. — Cut with the collapse above.
- [ ] `:710-723` — keep; trim to: restored without the reclaim ceiling,
  because this character is not to be harmed; done after the shield lifts
  and the body stops, when the engine has finished charging.
- [ ] `:796-811` — "Observed on a beggar… mourned him", "It has been latent
  all along… Raising the rear's damage made it common". — Keep: a victim
  killed inside an interactive action is left standing in it, so the death
  is handed to a ragdoll, and only then.
- [ ] `:816-823` — prose in another register ("don't", unquoted
  identifiers, `'lastHitByPlayer'` in quotes). `lastHitByPlayer` appears
  nowhere else in the repository or the references cited. — Rewrite in the
  file's register; name the link only if a source is found in
  `vanilla_scripts/` or the decompilation, otherwise describe it as the hit
  that attributes the death.
- [ ] `:825-829` — `"Tickle"` literal as the strength fallback, repeated
  from the reaction path. — Use the same fallback `Impact.lua` uses, or
  pass `hitStrength` always and drop the chain.
- [ ] `:866-867` — `fatal=` recomputes `fatal` (`:812`). `:869` is
  misindented. — Use `fatal`; fix the indent.
- [ ] `:874-884` — "measured… victims lost between 6 and 32 health, and six
  of ten were driven onto the clamp". — Keep: the shield has to span the
  whole throw, since the engine charges the body while it moves.
- [ ] `:885` — the tier name `"Walk"` as a literal decides whether to wait.
  `WhenBodyStops` already reads a still body on its first poll. — Drop the
  branch, or key it on the tier's reaction rather than its name and say why.
- [ ] `HorseCollisionMod.lua:421-424` `@field ImpactDamageDelayMs` —
  describes the wait before charging; the setting only times the test
  subject's restore (the settings file, `:663-665`, says so). — Correct.

### src/HorseCollisionMod/Rider.lua

- [ ] `:1-18` header — "every impact at trot or gallop draws horse
  stamina"; the rear and the charge draw it too, the walk does not. The
  file also holds the camera shake, the blur, the bolt and `GrantPerks`.
  "offence" (British). No `@release`, unlike the other modules. — List the
  parts; "offense"; add `@release`.
- [ ] `:17-19` — the module block runs straight into `IsCombatCollision`
  with no break, so LDoc attaches the module doc to the function, which has
  none of its own. — Separate; give it a doc naming its three returns.
- [ ] `:40-54` — "used to count as well", "Measured… cost 103 stamina", "The
  signal never earned its place… no longer decides anything". — Keep: the
  player's combat state decides; the victim's drawn weapon is logged only,
  because guards patrol armed.
- [ ] `:55` — returns `danger` twice; `Impact.lua:51` names the first
  `isCombat` and the third `playerInDanger`, which are the same value. —
  Return two values; carried to `Impact.lua`.
- [ ] `:171` — `IsCombatCollision(nil)` runs the armed test on nil and logs
  nothing with the detail. — Harmless in the pcall; if the two-value change
  goes in, add a player-only query or say the npc is optional.
- [ ] `:60-66` `ThrowRider` — "which is what earlier builds did". — Cut.
- [ ] `:73-82` — the fallbacks exist "in case a different mount type
  differs", and the preference order is iterated with `pairs`. — `ipairs`;
  one line on the order.
- [ ] `:108-113` `DrainImpactStamina` — "They did not before… levelling".
  `:123-127` "puts a gallop anywhere between 14.85 and 1452", "The tier
  separation the rider tunes". — Keep the formula, the additive shape and
  the 0.38 worst case (checked: 0.20 + 0.13 + 0.05); cut the history.
- [ ] `:138` `@tparam tierName` — lists five tiers by hand. — "an impact
  tier name".
- [ ] `:232-235` `DrainHorseStamina` — says `DealDamage` takes
  `(stamina, health, attacker, ...)`; `Health.lua:377-381` says it takes two
  arguments and discards the rest (`C_ScriptBindSoul`). Double spaces
  around the dashes. — Match `Health.lua`; stamina first is the point.
- [ ] `:280-283` — "which was measured: two saves in a row at 0.0 stamina".
  — Keep: the seat is rolled only on the impact that empties the horse.
- [ ] `:305-317` `ShakeRiderCamera` — "on a gallop impact"; "A trot gets a
  fraction… through `CameraShakeTrotScale`", which does not exist; the
  scale is `CameraShakeByTier`. "Half a ton of horse". `@tparam tierName`
  names three tiers. — Correct to the tier table.
- [ ] `:359` — `cfg.LeanSuppressShake ~= false`; the setting is declared, so
  the test is a truthiness check. — `cfg.LeanSuppressShake`.
- [ ] `:377-385` — `(cfg.CameraShakeAngle)`, `(cfg.CameraShakeShift)`,
  `(cfg.CameraShakeDurationSec)` in stray parentheses, the residue of
  removed `or` defaults; `g_Deg2Rad or 0.0174532925` is a literal fallback.
  The same at `:480`, `:491-494`, `:559`, `:702`. — Remove the parentheses;
  `math.rad`, or name why the global may be absent.
- [ ] `:409-427` `BlurRiderView` — "What was confirmed working in game, by
  setting each and looking". — "These work:" and the table.
- [ ] `:437-442`, `:535-538` — the 7.7 m / 4.6 m camera measurement twice.
  — Keep it on `CameraIsFirstPerson` only.
- [ ] `:444-453` — "Raising it from 0.9 to 1.3 to 2.0 produced the same
  picture three times", "raising the amount alone stopped helping well
  before it read". — Keep: the amount has no effect past about 1.0, so
  weight comes from the hold and the chroma layer.
- [ ] `:469-472` — "They came apart in tuning". — Keep: strength and
  length are separate because a trot keeps the strength and cuts the length.
- [ ] `:492` — divides by `RiderBlurSteps`; 0 in the settings file gives an
  infinite interval and no clearing write, leaving the screen blurred,
  which `:455-457` says must never happen. — Floor at 1.
- [ ] `:562-595` `BoltHorse` — "### Why this is a chance and not a health
  system" is removal history; "how the 2.0.0-dev1 bug behaved when it
  charged 25 health an impact by mistake". — Cut the first section; keep:
  `hostilePerception` cannot reach the player's horse, whose combat subbrain
  is a bare `Wait`; emptying its health throws the rider and sends it off,
  and the health is restored after `HorseBoltRestoreMs`.
- [ ] `:624` — `DealDamage(0, before, nil, true)`: per `Health.lua` the last
  two arguments are discarded. — Two arguments.
- [ ] `:691-696` `HorsemanshipScale` — "Two curved shapes do not work, both
  measured in game". — Keep: linear, so each level is worth the same.
- [ ] `:707-729` `GrantPerks` — three perk GUIDs as bare literals, copies of
  `perk__horsecollisionmod.xml`; `local player = player or (type(g_localActor)
  == "userdata" and g_localActor)` shadows the global, and nowhere else in
  the mod falls back to `g_localActor`. No `@` tags. The doc says "on
  startup or settings apply"; the callers are `HorseCollisionMod.lua:1709`
  and `:1933`. — Name the perks (a table with the perk names beside the
  ids); use `player` as the rest of the mod does; check with
  `build.ps1` that the ids match the table.
- [ ] `:730` — trailing blank line at end of file. — Remove.

### src/HorseCollisionMod/Sound.lua

- [ ] `:3-5` header — "eighty kilograms of person was struck by half a ton
  of horse". — Cut to: vanilla plays nothing for a collision.
- [ ] `:15-17` — the vocabulary is "242 distinct `audio_trigger` parameters"
  in the `.animevents`, and "a name outside it does not resolve". The grunts
  (`voices.xml`) and the horse calls (`animals.xml`) are outside it and
  resolve; the vocabulary is the trigger list in
  `references/audio_triggers.tsv`. — Correct and cite the table.
- [ ] `:19-31` "Why this is not in the animation data" — "built, tested in
  game, and abandoned", "The rider's verdict… 'way off'". — Keep: a
  fragment's `PlaySound` starts with the reaction, a detection tick and an
  interactive-action call after contact, so the sound lands late.
- [ ] `:40-45` `ArmorMaterial` — "the heaviest type a victim is wearing";
  `heaviestType` is the type of the heaviest piece by weight
  (`Armor.lua:210-213`). Same at `:99-100`. — Correct.
- [ ] `:149-151` — "A footprint reaching sixty milliseconds of travel
  further forward" is an experiment. — Keep: sounding ahead of contact
  plays near misses and sounds a victim twice.
- [ ] `:155-163` — layers are "`{ trigger, delayMs }` pairs", then `:168`
  gives four fields. "`a_o_jump_landing`… A blunt body impact ten
  milliseconds later": only the rear uses the landing, at 0 ms beside its
  body layer, and the gallop settings exclude the hoofstep family. "of
  twenty three candidates" is measurement. — One format line; the reason
  for layers is that no single sample is a horse striking a person.
- [ ] `:172-174` — "Two literal trigger names are tokens"; `ImpactTokens`
  has five plus `foley`. — List them from the table, or point at it.
  Follows the unused-tokens ruling.
- [ ] `:181` — "names the same sample two or four times"; no tier names one
  four times. — "more than once".
- [ ] `:196` `@tparam tierName` — three tiers; the rear and the charge
  arrive too (`:244`). — "an impact tier name". Same at `:375`, `:502`.
- [ ] `:198`, `:376`, `:503` `@treturn` — no caller reads the result
  (`Impact.lua:102`, `:198-199`). — Return nothing.
- [ ] `:239-241` — "gallop only"; the code plays the crack on the gallop and
  the charge (carried from Settings). — Correct.
- [ ] `:246` — `(cfg.ImpactSoundCrackChance)` in stray parentheses. —
  Remove.
- [ ] `:260-263` — repeats `:168-170` and `PlayAtDistance`. — Cut to one
  line.
- [ ] `:282-296`, `:458-472`, `:564-578` — the same fire-now-or-later
  closure three times. — One helper taking entity, trigger, delay and
  distance.
- [ ] `:310-373` `PlayRiderVocal` — "until now the rider was silent",
  "Every earlier attempt", "The rider's verdict on the first build" and the
  quote. — Keep: a named FMOD event cannot answer with a monolog and joins
  no dialog auction; the cooldown stops a group impact from stacking grunts.
- [ ] `:313-319` — "three severities… each tier names one"; the tiers use
  `soft` and `heavy`, and `medium` is unused. `:367-369` — "three grunts in
  one window, soft then medium then heavy"; the worst case is two, rank 2
  then 3. — Correct both.
- [ ] `:363-365` — "Ranks are the mod's own reading of severity rather than
  config"; they are `RiderVocalRankByTier` in the settings file. — Cut.
- [ ] `:414-439` — reimplements `RiderVoiceReady` (`Bark.lua:415-431`)
  inline. `:420-421` credits the rewind guard to "the hit cooldown in
  `Update.lua`"; `Update.lua` has none, and the load handler
  (`HorseCollisionMod.lua:1883`) resets the rear's deadline instead. — Call
  `RiderVoiceReady(rank)`; drop the `Update.lua` reference.
- [ ] `:427-428` — "A spoken line stamps rank 3, which nothing outranks";
  lines stamp 4 or 5 (`Bark.lua:436`), grunts reach 3. `RiderVoiceRanks.Grunt
  = 3` duplicates the top of `RiderVocalRankByTier` and nothing reads it;
  `Bark.lua:406` names it `RiderVoiceGrunt`, which does not exist. — "A
  spoken line outranks every grunt"; delete `Grunt` and fix `:406`.
- [ ] `:484-499` `PlayHorseVocal` — "corrupts CryEngine's audio proxy
  because the triggers carry `path="horse"` metadata"; no source in the
  diary, the references or the commit (`9d4ef0d`). `:497-499` restates the
  settings. — Cut both; the horse's voice plays on the horse.
- [ ] `:504-588` — a copy of `PlayRiderVocal` with its own gate;
  `local longest = cooldown` is a pointless local; column-aligned `=` and no
  blank line before `return` depart from the file. — Share one gated
  player with `PlayRiderVocal`, the gate state passed in.
- [ ] `:606-610` — "Measured through speakers placed at verified
  distances". — Keep: only 3D events respond to distance, and
  `hoofsteps_player` ignores position, so `a_o_jump_landing` has a fixed
  level.
- [ ] `:624-633` — the proxy is created before `ExecuteAudioTrigger`, and
  its removal timer set after; a throw between them leaks the proxy. — Set
  the timer first.
- [ ] `:640-645` `AwayFromListener` — measures from the player, while
  `:188-192` says the listener follows the camera. — Say the player stands
  in for the listener.
- [ ] `:668` — `0.5` unnamed. — Name it or give its derivation.
- [ ] `:693` — trailing blank line at end of file. — Remove.

### src/HorseCollisionMod/Lean.lua

- [ ] `:1-57` header — no `@release`, unlike the other modules. "What the
  shake actually does, measured", "Polled from… every 100 ms", "Four
  identical calls two seconds apart drove the camera out…", "Sampling a
  short window is what makes this mechanism easy to get wrong… twenty times
  too large" are how it was found. "the argument names suggest". The
  160 ms return is stated at `:35` and again at `:51-52` (and at `:546`,
  `:562`, `:394`). — Keep: no `cl_cam*` CVar or bone moves the mounted
  first-person camera and `PlayerSetViewAngles` only turns it, so the lean
  is `SetViewShake`'s positional vector; the peak is about 0.63 of the
  amplitude and arrives at t = period; a shake fired over a running one
  reverses the camera; an expired shake returns home in about 160 ms (once).
  Add `@release`.
- [ ] `:47-49`, `:283-285` — the residual wobble is "travel speed times the
  poll interval… under a centimeter"; the hold only corrects outside
  `LeanDeadband` (0.06 m), so the deadband sets the wobble. — Say so; the
  entry point's `LeanHoldAmplitude` doc makes the same claim.
- [ ] `:83-97`, `:122`, `:162` — `GetPlayerAndHorse` returns `playerEnt`,
  which neither caller uses; `rawget(_G, "player")` here and at `:232`,
  `:295`, `:605`, where the rest of the mod reads `player`. The horse
  lookup `XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())` is
  repeated in `Rear.lua`, `Retaliation.lua` and `Update.lua`. — Return the
  horse only; use `player`; one shared horse lookup, adopted by those files
  in their passes.
- [ ] `:102-118` `LeanOffset` — "that is what made the two sides read
  differently", "Measured", "which is exactly what was reported". The 6 cm
  rest offset is also in the entry point's `LeanDistance` doc. — Keep:
  measured from the horse's centerline, because a world baseline moves with
  the horse and the camera rests about 6 cm left of center, so both sides
  finish the same distance from the head.
- [ ] `:159` `@treturn` — "always positive"; it can be 0. — "never
  negative".
- [ ] `:179-188`, `:203` — the flattening is explained twice, and the
  first block's opening line and the paragraph under it say the same thing.
  — One comment: pitch is checked first, because the flattened yaw loses
  meaning as the view nears vertical, which is also where the camera is
  nearest the rider's model.
- [ ] `:226-230` `FlipLean` — `force` is undocumented. — Add `@tparam`.
- [ ] `:238-257` — "Unrated, this floods… at the twenty second lifetime
  those were still occupying the queue", "Measured, 176
  `Animation-queue overflow` errors… ran until the scripts were
  reloaded", "a runaway of ten meters on fast taps"; "three centimeter
  deadband" (it ships at 0.06); no blank line between the two paragraphs at
  `:252-253`. — Keep: each shake holds one of the rider's sixteen animation
  queue entries for its life, and an overflowed queue rejects animations,
  so corrections are throttled; the press, the arrival and the release are
  not, because dropping one leaves the camera traveling. Depends on the
  throttle ruling.
- [ ] `:261`, `:268`, `:360`, `:424`, `:451`, `:564` — settings in stray
  parentheses. — Remove.
- [ ] `:302` — "the same check the rear uses". — Cut.
- [ ] `:315-328` — the home-return comment sits above the angle check,
  while its check is at `:340-344`; it runs straight into the angle
  comment. `:320-325` is the history of a fixed bug ("`now` was read from a
  global that does not exist… stayed dead through a save load"); "the
  pumping bug". — Move the first comment to `:340` as: a re-press before
  the camera is home would take its target from a displaced camera; cut the
  bug history.
- [ ] `:391-403` — "clips through Henry's back", "A rider turning slowly
  still gets the full 45 degrees" (copies the setting). — Keep: the return
  takes about 160 ms, so the angle is projected ahead by the turn rate and
  the limit tightens only for a fast turn.
- [ ] `:446-450` — "which the rider has seen", "including ones not yet
  found". — Keep: a ceiling bounds any failure in the loop.
- [ ] `:464-481` — "Measured across eight deliberate double taps" and the
  log table. — Keep: against a running shake a press reverses rather than
  choosing a side, so the direction is checked and corrected up to twice.
- [ ] `:498-511` — "Releases aimed at 0.65 landed at 0.11, -0.05 and
  -0.08". The stated cause, a shake reversing at its period, cannot occur at
  `LeanShakePeriod` 40 with `LeanShakeSec` 1.5; the expiry refresh at
  `:522` is a flip the loop makes without the correction logic. — Keep:
  direction is taken from two samples, never remembered, because the camera
  can reverse without a correction.
- [ ] `:518-522` — "to keep the animation queue" is an unfinished sentence;
  `150` is unnamed; two comments run together. — Finish it (the hold is
  renewed before its shake expires and sends the camera home); name the
  margin or derive it from `LeanPollMs`.
- [ ] `:544-547` `StopLean` doc and `:562-563` — the 160 ms return twice
  more. — Once, in the doc.
- [ ] `:566`, `:571` — `sign or 1`; `sign` is `LeanHeld`, checked non-nil
  at `:549`. — `sign`.
- [ ] `:572`, `:574` — `-9` and `-1` stand in for an unreadable offset and
  angle in the log. — Log `none`.
- [ ] Carried back to the settings file: `LeanHomeMs` is commented "how
  often the hold is corrected" (it is the wait after a release); `LeanShakeSec`
  "long enough to outlast a held lean" (a hold renews it before expiry).
  Part of the settings lean rewrite.

### Dead code (`tools/audit_code.py`)

- [ ] `Recovery.lua:177` `WatchRecoveryForRearm` — nothing calls it. — Delete.
- [ ] `Tutorial.lua:229` `ResetTutorials` — nothing calls it. — If it is a
  console helper, say so in its doc; otherwise delete.

### Install hygiene (not repository)

- [ ] Game install `Data/Libs/Tables/rpg/` holds stale
  `*__horsecollision.xml` tables (without `mod`) alongside the current ones. —
  Confirm they are unused and remove through the deploy tooling.
- [ ] `mod_assets/Libs/Tables/rpg/` holds stale generated copies of the perk
  tables; the source of truth is `src/Libs/Tables/rpg/`. — Confirm the build
  never reads them; clear.
