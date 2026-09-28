# v6 audit ledger

Working document for the `audit/v6` branch. Deleted before the branch lands.

Phase 1 records findings only. Phase 2 applies them in small batches, each
checked off here with its commit.

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
  `HitCooldownStateDriven`, `HitCooldownMs` and `KnockdownRecoveryMs`, none of
  which exist. A second paragraph ("Which tiers wait…") is spliced on. The
  settings file (`:1019`) repeats the `HitCooldownMs` reference. — Move what
  is true beside `HitReadySettleMs` / `HitReadyCeilingMs`; delete the rest.
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
- [ ] `:1842-1853` `uiActionListener` logs every UI event whose name contains
  dialog, item, money, msg, surrender or inventory whenever `LogTelemetry` is
  on. Investigation scaffolding. — Remove, or ruling.

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
