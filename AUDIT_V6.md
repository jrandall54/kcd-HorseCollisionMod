# v6 audit ledger

Working document for the `audit/v6` branch. Deleted before the branch lands.

Phase 1 records findings only. Phase 2 applies them in small batches, each
checked off here with its commit.

## Resuming

Read this section first in a new session. It is updated and committed at the
end of every pass, so it always says where the audit stands.

**Phase:** 1, recording findings. No source file has been edited.

**Method for one pass:** read the whole file; check every factual claim in a
comment against the code it describes; record each problem under the file's
heading in **Findings** as `:line` — problem — planned edit; anything that
changes behavior or needs a decision goes in **Rulings needed** instead;
update this section; commit as `docs(audit): record findings for <file>`.

**Next pass:** `src/HorseCollisionMod/Rear.lua`.

**Pass order** (dependencies first, then largest):

- [x] `src/HorseCollisionMod.lua` (entry point)
- [x] `src/HorseCollisionMod_Settings.lua`
- [x] `src/HorseCollisionMod/Tiers.lua`
- [x] `Armor.lua`
- [x] `Reaction.lua`
- [ ] `Rear.lua`
- [ ] `Retaliation.lua`
- [ ] `Bark.lua`
- [ ] `Recovery.lua`
- [ ] `Health.lua`
- [ ] `Rider.lua`
- [ ] `Sound.lua`
- [ ] `Lean.lua`
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

- `Sound.lua:240` — the crack comment says "gallop only"; the code plays it
  on gallop and charge.
- `Marks.lua` — check the dust comments against the vertical-speed test.
- `Health.lua:364` — the note on `ImpactDamageScale`; check it against the
  `Armor.lua` findings on the floor and the formula.
- `Recovery.lua:1116` — the `ArmorBlend` use there goes with the
  DynamicRecovery ruling; if it goes, update the `ArmorLerp` consumer list.

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
