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

### Install hygiene (not repository)

- [ ] Game install `Data/Libs/Tables/rpg/` holds stale
  `*__horsecollision.xml` tables (without `mod`) alongside the current ones. —
  Confirm they are unused and remove through the deploy tooling.
- [ ] `mod_assets/Libs/Tables/rpg/` holds stale generated copies of the perk
  tables; the source of truth is `src/Libs/Tables/rpg/`. — Confirm the build
  never reads them; clear.
