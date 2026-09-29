# v6 audit ledger

Working document for the `audit/v6` branch. Deleted before the branch lands.

Phase 1 records findings only. Phase 2 applies them in small batches, each
checked off here with its commit.

## Resuming

Read this section first in a new session. It is updated and committed at the
end of every pass, so it always says where the audit stands.

**Phase:** 2 in progress. Batches 0 to 3 done; batch 4 under way.

**Current status:** every source file, every document except the diary, and
all tooling (`build.ps1`, `tools/`, `tools/legacy/`, the untracked
`.claude/` hooks, linter and notes) audited. `.claude/` was the last pass.

**Method for one pass:** read the whole file; check every factual claim in a
comment against the code it describes; record each problem under the file's
heading in **Findings** as `:line` — problem — planned edit; anything that
changes behavior or needs a decision goes in **Rulings needed** instead;
update this section; commit as `docs(audit): record findings for <file>`.

**Decisions are deferred.** Nothing in phase 1 waits on a ruling. Anything
needing one is recorded under **Rulings needed** with a proposal, and the
passes continue. Rulings are made together once phase 1 is complete.

**Rulings:** all decided; each entry under **Rulings needed** carries its
ruling. Several set phase-2 checks for the publish test runs (the rise
shortcut, `VictimFlatFraction`, the companion dog's class).

**Next step:** phase 2, batch 4, one source file per commit in the pass
order below. Done: `src/HorseCollisionMod.lua`, the settings file, `Tiers.lua`, `Armor.lua`, `Reaction.lua`, `Rear.lua`, `Retaliation.lua`, `Bark.lua`, `Recovery.lua`, `Health.lua`, `Rider.lua`, `Sound.lua`, `Lean.lua`, `Update.lua`, `Marks.lua`, `Fear.lua`. Next: `Crime.lua`. Read **Phase 2 plan**
below in full before starting; it gives the procedure for every batch and how each is
verified. Code changes found on the way go to batch 3, item 7, applied
after the comment passes.

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
- [x] `Update.lua`
- [x] `Marks.lua`
- [x] `Fear.lua`
- [x] `Crime.lua`
- [x] `Impact.lua`
- [x] `Log.lua`
- [x] `Tutorial.lua`
- [x] `Detection.lua`
- [x] `Enums.lua`
- [x] Documentation: `README`, `docs/*.md` except the diary
- [x] Tooling: `build.ps1`, `tools/`, `.claude/` hooks and linter

**Carried forward:** findings in one file that point into a file not yet
audited are listed here, so its pass picks them up. None open.


## Phase 2 plan

Agreed with the rider at the end of the rulings session. Every item under
**Rulings needed** and **Findings** is applied in the batches below, in this
order. Each batch is tested only as far as it can break something: a
comment edit is proved not to have changed code and needs no game; a change
of behavior gets one named ride.

### Verification levels

- **L0, static.** `.\build.ps1` (syntax, style, scope and staleness checks),
  `python .claude\lint_docs.py`, `python tools\audit_code.py`. Every batch.
- **L1, no code changed.** For a batch meant to touch only comments and
  whitespace, the token stream of every changed Lua file, comments and
  whitespace dropped, must be identical to the batch's base commit. Penlight's
  lexer (`pl.lexer`, installed with LDoc) produces it. LuaJIT bytecode cannot
  be used: this build randomizes string hashing, so one file compiled twice
  gives different bytes. From Git Bash, with `BASE` the commit the batch
  started from and `toks.lua` holding:

  ```lua
  local lexer = require "pl.lexer"
  local f = assert(io.open(arg[1], "rb")); local s = f:read("*a"); f:close()
  for t, v in lexer.lua(s, {space = true, comments = true}) do
    io.write(t, "\t", tostring(v), "\n")
  end
  ```

  ```
  export LUA_PATH='C:\Users\jummy\.luarocks\share\lua\5.1\?.lua;;'
  tk() { luajit toks.lua "$1"; }
  for f in $(git diff --name-only $BASE -- '*.lua'); do
    git show $BASE:$f > a.lua
    cmp -s <(tk a.lua) <(tk $f) && echo "same  $f" || echo "DIFF  $f"
  done
  ```

  Checked against a comment edit (same), an operator change and a string
  change (both DIFF).

  Python and PowerShell have no equivalent; for them, `git diff -w $BASE`
  must show only comment lines.
- **L2, loads.** `.\tools\flow.ps1 test` into the running game, then read
  `kcd.log` for Lua errors and the mod's startup line. No ride.
- **L3, one ride.** Before the ride, name the tier, what the rider should
  see if the change works, and what failure looks like. Confirm from the log
  that the change is live before asking for a verdict. One change per ride,
  nothing else running, and every test-world override restored afterwards
  (`flow.ps1 test -Unset`).

### Procedure for every batch

1. Note the base commit (`git rev-parse HEAD`).
2. Make the batch's edits. A finding whose line was deleted by an earlier
   batch is ticked as "superseded by batch N" rather than applied.
3. Run the batch's verification levels. A failure is fixed inside the batch
   or the batch is reverted; never carried forward.
4. Player-visible changes get an `[Unreleased]` entry in `CHANGELOG.md`.
5. Tick the batch's items in this ledger, add a line to **Phase 2 log**
   below, update **Resuming**, and commit together. The commit-msg hook
   rejects AI attribution trailers; add none.

### Batches

**Batch 0. Protect the horse animation files.** *(L0; pak comparison)*
Move `hcm_horse_database.adb`, `kcd_horse_fragmentids.xml` and
`kcd_horse_controllerdefs.xml` from `mod_assets/Animations/Mannequin/ADB/`
into `src/Animations/Mannequin/ADB/`; `build.ps1` copies them into the pak as
it does `src/Libs`, and the required-file list and `build_adb.py`'s sweep
follow the move. Correct `build.ps1:414-418`. Test: build, then compare the
new zip's pak entry list and the three files' bytes against
`releases/HorseCollisionMod_v5.31.4.zip`; identical means no ride.
`python tools\verify_additive.py <zip>` must pass 35 of 35.

**Batch 1. Enforcement and mechanical sweeps.** *(L0, L1)*
- `lint_docs.py` rules from **Tooling and enforcement**, added as
  **warnings**. Promoting them to errors now would block every commit until
  the comment batches finish; that happens in batch 7. Record the warning
  count in the log as the comment batches' starting figure.
- `audit_code.py` recognizes string references (`Rear.lua:431`).
- Hook comments rewritten in the standard.
- The seven tab-indented Python tools to four spaces (`git diff -w` empty;
  each tool's `--help` still runs).
- `@release` dropped from every source file and from `set_version.py`
  (the `land` ruling). L1 proves the Lua untouched. The build regenerates
  `docs/api`; commit it without comment.

**Batch 2. Dead code and removed features.** *(L0, L2, then one sweep ride)*
Intended to change nothing a player can see. Apply the rulings:
`DynamicRecovery` and its settings; `BarkDeath`, `RiderBarkSets`,
`RiderBarks` and `Bark`'s `rider` parameter; `CatchYieldImmediately`,
`sawYield`, `caught`, `SendStandDown`; the pull-down horse query, fallback
and angle tracking; the physics-proxy rescue and `HasRescuedPhysicsProxy`;
the cooldown wind-back branch; `WatchTurn`; `TraceFallLanding`; the throw
and height fields of `ProbeImpactCost`; the `face` and `foley` tokens; the
lean throttle and `LeanMinFlipMs`; the two tutorial cells; the four get-up
options (regenerate the databases; `verify_additive.py` must pass).
`ProtectMutt` goes last in the batch, after reading the companion dog's
class live (`python tools\dev_console.py --lua` against the entity named
`dogCompanion`); a human class reopens that ruling instead.

Checks specific to this batch:
- `git grep` for every removed name returns nothing outside the diary and
  this ledger.
- A removed setting must not break a player's settings file that still
  carries it. `ApplySettings` refuses keys `Config` lacks
  (`Tiers.lua:455`); confirm that a stale key is skipped and logged rather
  than aborting the load, by adding one to the test world and reading the
  log. If it aborts, make it skip before deleting any setting.
- Sweep ride (L3): one impact at each of walk, trot, gallop, rear and
  charge, telemetry on. Works: every tier reacts as before, the kill line
  and victim barks still play, no Lua errors, and `ImpactCost` rows still
  appear without `travel=` or `dz=`.

**Batch 3. Behavior changes, one ride each.** *(L0, L2, L3)*
In this order, each its own commit and ride:
1. `VictimFlatFraction` 0.15. Ride: trot knockdown, then strike the victim
   again while down. Works: no snap upright; the recovery line lands as
   they rise. Failure: a snap upright, which means 0.45 had a reason;
   record it in the comment and restore 0.45.
2. `HushVanillaBark` stamp check. Ride: hold the horse in front of an NPC
   for over three seconds, then walk into them. Works: only the mod's line.
   Failure: vanilla's collision bark plays.
3. The charge's bark set (`Charge = "collision"`, and the build refuses a
   settings tier table that differs from `Tiers.lua`) and impact cry
   (`PainByTier.Charge = HurtDown`). Ride: charge a villager. Works: a
   pain cry on impact, then a collision line.
4. `RearAnimMs` stops dividing by `RearAnimSpeed`. Ride: standing rear,
   then try to move. Works: control returns as the rear visibly ends.
5. The retaliation deletions from batch 2, if the sweep did not reach them.
   Ride: provoke a guard into pulling you off. Works: the pull-down happens
   and a `PullDown … done` row is logged.
6. `PullRiderDown` returns `true` once it has started polling, so
   `ProvokeIfAnnoyed` (`Retaliation.lua:1011`) stops releasing the offense
   at once. It has ended with `attempt()` and no return since `ec6fc1f`, so
   the deferral it documents has never happened. Asked of the rider before
   applying. Ride together with item 5: the victim pulls the rider down
   before throwing a punch.
7. Code changes found during batch 4, applied as one commit after the
   comment passes, since each deletes code nothing reaches or repeats. L0
   and L2; no ride.
   - Entry point: delete the second `ReactionAnimationState` assignment,
     and the unread `RagdollAnimationState` and `ReactionEndCeilingMs`.
   - Entry point: delete the `GrantPerks` call in `uiActionListener`;
     `ApplySettings` already makes it on the same load.
   - Entry point: `ApplySettings` passes `RagdollStillSpeedThreshold`
     directly instead of through `local threshold`.
   - Entry point: delete the `UIEvent` logging block at the head of
     `uiActionListener`, investigation scaffolding.
   - Entry point: `RiderVocalByTier` defaults to the shipped settings
     file's values (walk silent, trot and rear `v_henry_hit_soft` at 140).
     `7a6cbc5` changed only the settings file. No change for a player; it
     restores "deleting a line falls back to the default".
   - `Armor.lua`: drop `ArmorOf`'s `tack` parameter, which nothing passes,
     so it always excludes tack; drop `ArmorCurve`'s `invert`, which its
     only caller always sets; delete the unreachable `if not barding` in
     `BardingCoverage`. Trim the two docs that describe the parameters.
   - `Reaction.lua`: drop the unused `state, waitedForBody` parameters of
     the `WhenVictimIsUp` callback in `Ragdoll`; drop `ImpulseVictim`'s
     unused `armorScale` and its argument, with its doc line; in
     `ImpulseVictim`, log `ImpulseApplied` straight after the call and
     delete the 300 ms timer and the `GetWorldPos` movement figure, which
     reads an entity that does not follow a ragdoll.
   - `Rear.lua`: `CheckRearKeys` builds its "choose one of" list from
     `RearKeys` (it omits e and f); delete the unread `tierName` in
     `RearHorse`; delete `LogActionEnd` and its call, since the standing
     rear never reads `AnimationControlled` and every `ActionEnd` line in
     the log reports the first poll (400 to 432 ms).
   - `Retaliation.lua`: gate the `SurrenderHint nobody left` and
     `SurrenderHint left to the game` log lines on `LogTelemetry`; rename
     the inner `mounted` in `PullRiderDown`'s `attempt`, which shadows the
     outer one.
   - `Bark.lua`: move `ShieldFromEngineDamage` and `LiftCollisionShield` to
     `Health.lua`, beside `ApplyImpactDamage`, which lifts the shield; drop
     the redundant parentheses around single `cfg` reads.
   - `Recovery.lua`: delete `WatchRecoveryForRearm`, which nothing calls,
     and `WhenVictimStands`, its only callee (`RisePollMs` and
     `RiseCeilingMs` stay for `FallToBlend`); `IsVictimFlat` returns four
     values on a nil victim as it does elsewhere; move `ImpactIsNewContact`
     to `Update.lua`, beside its callers' concern.
   - `Health.lua`, `ApplyImpactDamage`: delete `attacker` and the
     `attributed=` field it feeds (`DealDamage` takes no attacker); return
     nothing, since `Impact.lua` ignores the figure; the crime hit's
     strength falls back as `Impact.lua`'s does rather than through a
     `"Tickle"` literal; the `fatal=` log field reads `fatal`; the
     immediate-deal branch keys on the tier's `ReactionByTier` being
     `stagger` rather than on the name `"Walk"`, which gives the same
     result for the shipped tables.
   - `Rider.lua`: `IsCombatCollision` returns two values (it returns
     `danger` twice), with `Impact.lua:51` following; `ThrowRider` iterates
     its holders with `ipairs`; `cfg.LeanSuppressShake` as a plain truth
     test; drop the stray parentheses and the `g_Deg2Rad or 0.0174532925`
     fallback in favor of `math.rad`; `BlurRiderView` floors
     `RiderBlurSteps` at 1, since 0 leaves the screen blurred; `BoltHorse`
     calls `DealDamage` with two arguments; `GrantPerks` uses `player` as
     the rest of the mod does, without the `g_localActor` fallback.
   - `Sound.lua`: `PlayImpactSound`, `PlayRiderVocal` and `PlayHorseVocal`
     return nothing, since no caller reads the result; drop the stray
     parentheses on `ImpactSoundCrackChance`; one helper for the
     fire-now-or-later closure the three repeat; `PlayRiderVocal` calls
     `RiderVoiceReady(rank)` instead of reimplementing it; delete the
     unread `RiderVoiceRanks.Grunt`; one gated player shared by the rider
     and horse vocals, the gate state passed in; `PlayAtDistance` sets the
     proxy's removal timer before executing the trigger, so a throw cannot
     leak the proxy.
   - `Lean.lua`: `GetPlayerAndHorse` returns the horse only; read `player`
     rather than `rawget(_G, "player")`; one shared horse lookup for the
     `XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())` chain,
     adopted in `Rear.lua`, `Retaliation.lua` and `Update.lua` too; drop
     the stray parentheses around settings; `StopLean` uses `sign` rather
     than `sign or 1`, and logs `none` for an unreadable offset or angle
     instead of `-9` and `-1`.
   - `Update.lua`: `SafeUpdate`'s player test is
     `not player or not player.human or not player.player`; the clock is
     read once per tick; the airborne log's 1000 ms repeat gap is named,
     and `sinceImpactMs` logs `none` rather than `-1`; the loop's error row
     is `UpdateError err=` rather than capitals.
   - `Marks.lua`: `MarkVictim` and `ImpactDust` return nothing; drop the
     `tierName == "Walk"` special cases, since the walk has no row in any
     of the tables; name the jitter's 0.75 and 0.5, the rear dust's 1.3 m
     chest height, and `GroundUnder`'s 1.0 m cast height and 3.0 m depth;
     drop the `ImpactDustEffectRear or ImpactDustEffect` fallback; the
     rear's dust row drops `INSTANT`; `table_` becomes `results`.
   - `Fear.lua`: drop the reads of `RearFearScreamOverrideSuppress` and
     `RearChargeFearScreamOverrideSuppress`, which were never declared in
     `Config` (since `00d6637` and `823eb6a`), so they are always nil and
     the scream never overrides suppression; behavior unchanged. Use
     `player` rather than the `playerEnt` alias; the target id and player
     WUID go through the helpers recorded under `Crime.lua`.

**Batch 4. Comment passes, one source file per commit.** *(L0, L1)*
All remaining **Findings** under `src/`, in the pass order. L1 must report
every file `same`; a finding that turns out to need a code change becomes
a new batch-3 item rather than riding along. Findings that say "settle
from the diary" are settled by reading it; one the diary cannot settle
goes to the rider as a question. Includes the ruled comment corrections
(the rise shortcut, `WhenBodyStops`, the impact pool, `RearAnimSpeed`).

**Batch 5. Tooling.** *(L0; each tool run)*
- `flow.ps1` the only front door: `dev_deploy.ps1` header marks it
  internal; a full deploy refuses with the game running, before touching
  the install; pointers in `AGENTS.md`, `publish_nexus.ps1:392`,
  `dev_console.py:777`, `DEV_LOOP.md` and `.claude/RELEASING.md` name
  `flow` commands; any switch `flow` cannot reach is added to `flow` or
  deleted. Test: `flow test` with the game closed and with it running; a
  direct full `dev_deploy` with the game running refuses and leaves the
  install folder unchanged.
- `:reload` and `reload_mod` deleted.
- `land`'s retry deleted; `pre_release_check.py:493-495` corrected. Not
  tested by landing, which is the rider's call; verified when it happens.
- `publish_nexus.ps1` runs `verify_additive.py` on the zip unless `-Force`.
  Test with `-DryRun`.
- The stale armor-table sweep deleted from `build.ps1`.
- README settings table generated by `nexus_settings_block.py` and checked
  by the build. Test: edit one inline comment, confirm the build refuses,
  revert.
- Deleted: the four closed-question probes, `tools/legacy/`,
  `dev_target.lua`, `dev_subject.lua`, with their README rows. Deleting
  `dev_subject.lua` leaves `HorseCollisionMod.ImmortalSubjects` and its
  read in `Health.lua` with no writer; delete them in the same commit, with
  the test-subject restore in `ApplyImpactDamage` and
  `ImpactDamageDelayMs`, which only that restore reads.
- Remaining tool **Findings**, file by file.

**Batch 6. Documentation.** *(L0, lint)*
README layout (the `tools/` catalog to `DEV_LOOP.md`), DEV_LOOP's hook
section, `BALANCE_AUDIT.md` deleted after confirming its derivations are in
the code and its rulings in the diary, the settled fear notes out of
`HANDOFF.md`, then the remaining document **Findings** file by file.

**Batch 7. Close.** *(L0 through L3)*
Promote the new lint rules to errors; the tree must pass. Full build and
`verify_additive.py`. A final sweep ride on shipped values
(`flow.ps1 test -Shipped`), every tier once, plus the publish-test checks
below. Then this ledger is deleted and the branch is ready to land when the
rider asks.

### Publish-test checks carried from the rulings

- A gallop or charge victim's recovery line or retaliation must not start
  while they are still on the ground (the rise shortcut).
- Mutt taking damage and fleeing is the rider's to raise if it recurs.

### Phase 2 log

One line per batch: batch, commit, what was verified.

- **Batch 0.** The three horse files moved to `src/Animations/Mannequin/ADB/`;
  `build.ps1` packs `src/Animations` beside `src/Libs`; `dev_deploy.ps1` reads
  ADB files from both folders, including in its withdrawn-override cleanup,
  which would otherwise have deleted the installed horse files. Dev build: zip
  and pak entry lists and every pak file's bytes identical to v5.31.4;
  `verify_additive.py` 35 of 35; `lint_docs.py` errors only in this ledger;
  `audit_code.py` unchanged. The old copies in `mod_assets/` are left for the
  rider to delete; they are byte-identical and harmless meanwhile.
- **Batch 1.** `@release` removed from the entry point and the sixteen part
  files that carried it, from `set_version.py` (two places remain) and from
  `build.ps1`'s release gate; `DEV_LOOP.md` and a `dev_deploy.ps1` comment
  follow. The `flow.ps1` retry and `pre_release_check.py:493` still mention
  it; both go in batch 5. L1 replaced (bytecode is not deterministic, see
  **Verification levels**); all 17 Lua files `same`. `audit_code.py` treats
  a key named as a string as read: 0 unread keys. Seven Python tools
  re-indented: `git diff -w` empty, only docstrings changed in the syntax
  tree, every `--help` runs, `nexus_settings_block.py` output identical.
  Hook comments cut to the standard (history, `.agent_instructions.md`,
  British spellings); every hook passes `bash -n`. `lint_docs.py` gains a
  `NARRATIVE` rule list (exempting `CHANGELOG.md`) and an escape-damage
  check, as warnings. **Starting figure for the comment batches: 288
  narrative warnings outside this ledger; 0 errors outside it.** The
  timeless `now` rule also matches "is now in flight"; review it before
  batch 7 promotes it. `.claude/` is untracked, so the hook and linter
  edits are local and absent from the commit. `docs/api` regenerated with `ldoc .`;
  the orphan `docs/api/modules/Retaliation.html` (unlinked, last written
  2 September, still showing `Release: 4.6.1`) deleted.
- **Batch 2.** Every batch-2 ruling applied. A stale settings key was
  confirmed live to be logged and skipped (`AuditStaleKey`, 33 others
  applied). Mutt read live as `player_dogCompanion_vorech class=Dog`, so
  `ProtectMutt` went last as ruled. `DynamicRecovery` was live, not dead: it
  played a `HurtDown` groan every 1.4 s on a downed victim, so its removal is
  player-visible and has a `CHANGELOG.md` entry with `ProtectMutt`,
  `RiderBarks` and `LeanMinFlipMs` (version check: 5.32.0). The impact-pool
  doc was reduced to its ruled form here, because deleting `RiderBarkSets`
  left it describing a table that no longer exists. Get-up options
  regenerated out of both databases and the tags file; `verify_additive.py`
  35 of 35. Removed-name grep clean outside the diary, this ledger and
  `BALANCE_AUDIT.md` (deleted in batch 6). Sweep ride: all five tiers
  reacted, kill line fired on gallop and charge, one `HurtDown` per downed
  victim, `ImpactCost` rows without `travel=`, `dz=` or `z=`, cooldown
  refusals correct, no Lua errors. **Open:** on two save reloads in a row
  only rear and charge registered; a third reload after a script reload
  registered every tier. Not reproduced and not attributed; recorded in the
  diary with the procedure for a recurrence. `YieldCaught` result recorded
  in the diary.
- **Batch 3, item 1.** `VictimFlatFraction` 0.15 in both files. Ride: a
  second trot hit on a downed victim popped them upright, which the rider
  prefers to no reaction. The fraction did not decide it: every second hit
  read `state=BlendRagdoll headUp=0.88 standing=0.88`, so the head-height
  test does not see a ragdolled body lie down and returns `flat=false` at
  any fraction. The derivation stands; the snap check is dropped from the
  publish test.
- **Batch 3, item 2.** `HushVanillaBark`'s timer clears the option only when
  `RecentHushes[id]` still holds the stamp it was armed with. Accepted
  without an ear test: the ride cannot tell vanilla's line from the mod's
  by ear and the engine does not log vanilla's, and the change can only
  hold the mute longer. Walk contact after lingering: stagger, the mod's
  `Shove` line sent, no errors.
- **Batch 3, item 3.** `VictimBarkByTier.Charge = "collision"` in
  `Tiers.lua`; `PainByTier.Charge = "HurtDown"`; `tools/check_tiers.lua`
  loads both files in LuaJIT and the build refuses any differing tier row
  (it refused the old `Charge` row, then passed 9 of 9). Ride: the charge
  cry is heard on unarmored villagers and not, per the rider, on armored
  guards. The mod sent `HurtDown` to all of them (`villageGuard`,
  `rat_guard22`, `sent=true`), and the set is the one trot and gallop use,
  so the guards' silence is not specific to this change. **Open, bark
  research:** whether guards can speak `HurtDown`; `HasMetaRoleByName`
  does not decide it (a villager who spoke also reads false). **Open, bark
  window:** the rider heard vanilla's collision bark after the mod's `Shove`
  line on a walk stagger, so item 2 does not close every path by which
  vanilla speaks inside the mod's window.
- **Batch 3, item 4.** `RearAnimMs` no longer divides by `RearAnimSpeed`,
  documented as the charge's playback speed. No ride: at the shipped 1.0
  the division changed nothing.
- **Batch 3, items 5 and 6.** `PullRiderDown` returns `true` once polling
  starts, and `ProvokeIfAnnoyed` clears the annoyance count before calling
  it, so a deferred provocation does not re-roll on every contact. Ride with
  retaliation on: Tonda pulled the rider down at 6544 ms after three
  requests and the offense was released on `dismounted`; Berthold was
  offered the pull (`can=2`), never took it, and fought on the 8000 ms
  ceiling; a beggar surrendered. No swing while mounted. The rider found it
  slow: the engine runs the accepted request when its brain is ready, 1 to
  5 s here, which this change does not affect. Retaliation switches
  restored afterwards.
- **Batch 4, `src/HorseCollisionMod.lua`.** Base `5a6a7ed`. L1 `same`;
  build passes; `audit_code.py` unchanged. Narrative warnings in the file
  32 to 18; the 18 left are false positives: "the rider" meaning Henry in
  game, and "before this table exists". The `the rider` rule cannot tell
  the in-game rider from the tester; review it with the `now` rule before
  batch 7 promotes either. Header rewritten against the six shipped data
  files and five tiers. Four code findings moved to batch 3, item 7.
- **Batch 4, `src/HorseCollisionMod_Settings.lua`.** L1 `same`; build
  passes and the tier tables agree (9 of 9). Comments rewritten for a
  player: descriptive, no history. Warnings left are the "the rider"
  false positive. A comparison of every shipped value against the entry
  point's defaults found one drift, `RiderVocalByTier`, added to batch 3,
  item 7.
- **Batch 4, `Tiers.lua`.** L1 `same`; lint clean for the file. History,
  readings and "armour" cut; derivations kept and rechecked.
- **Batch 4, `Armor.lua`.** L1 `same`; build passes. Header rewritten
  for the three effects (weight to impulse and stamina, `smash_def` to
  damage) plus barding; the `TackTypes` doc separated from the module doc.
  Three code findings moved to batch 3, item 7.
- **Batch 4, `Reaction.lua`.** L1 `same` for it, the entry point and the
  settings file. Measurements, anecdotes and the two banner blocks cut; the
  dead `RagDollize` paragraph deleted; blank lines normalized.
- **Batch 4, `Rear.lua`.** L1 `same` for it, the entry point and the
  settings file. The charge's scoring comments corrected throughout: the
  loop stands aside and the sweep scores; `WatchLunge` clears
  `RearCharging`. `LogActionEnd` shown by the log to measure nothing.
- **Batch 4, `Retaliation.lua`.** L1 `same`. Measurements and history cut;
  the doc that LDoc attached to the wrong function moved; the morale survey
  moved to the diary.
- **Batch 4, `Bark.lua`.** L1 `same`. Duplicate `KOLIZE_*` paragraphs,
  audition history and quoted rides cut; `Bark`'s parameters documented;
  the shield's duration and the hush rate corrected.
- **Batch 4, `Recovery.lua`.** L1 `same`. Docs follow the rise-shortcut
  and `WhenBodyStops` rulings; misplaced and missing docs fixed; history
  cut; the `hcm_combat_injected` skip explained from `7508a1a`.
- **Batch 4, `Health.lua`.** L1 `same` for it and the entry point. Header
  lists the file's five parts; the orphaned damage doc moved to its
  function; the prediction doc matches the code.
- **Batch 4, `Rider.lua`.** L1 `same`. Tier docs follow the per-tier
  tables; the `DealDamage` signature matches `Health.lua`; history cut.
- **Batch 4, `Sound.lua`.** L1 `same` for it, the entry point and the
  settings file. Quotes, experiments and measurements cut; the grunt
  worst case and ranks match the shipped tables; the master level's scope
  corrected in three files.
- **Batch 4, `Lean.lua`.** L1 `same` for it, the entry point and the
  settings file. Measurements and bug history moved to the diary; the
  unfinished expiry sentence completed.
- **Batch 4, `Update.lua`.** L1 `same` for it and `Bark.lua`. Rates named
  as `TickSeconds`; the removed readiness wait's history cut; the charge
  stand-aside described as it works.
- **Batch 4, `Marks.lua`.** L1 `same`. Tier docs follow the tables; the
  three failed landing signals kept as constraints without the history.
- **Batch 4, `Fear.lua`.** L1 `same`. The flee-state measurement reduced
  to its constraint; people-neutral wording; `ChargeFearBand`'s return
  documented. Two undeclared settings found, recorded for item 7.

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

- [x] **DynamicRecovery.** Ruled: remove entirely. The per-tier ground time
  and the ground groans it timed are one abandoned system; the get-up stays
  the global `wh_rd_StillDuration`. Delete `CalculateRecoveryDuration`,
  `ApplyDynamicRecovery` and its call (`Impact.lua:136`), `DynamicRecovery`,
  `RecoveryDelayByTier`, `RecoveryArmorScale*`, `RecoveryMinSec`,
  `RecoveryMaxSec`, `RecoveryGroundBarks`, `RecoveryBarkIntervalMs`, from the
  entry point and the settings file. Recovery barks (`WhenVictimRises`) are
  unaffected. Findings that follow this ruling delete rather than rewrite.

- [x] **RearChargeThrow ships at 0.6.** Ruled correct; revisit only if the
  publish test runs call for it. The comment keeps "1.0 throws like a gallop"
  as the scale, with no claim about which tier throws further.

- [x] **The charge's bark set.** Ruled as proposed: `Tiers.lua:422` becomes
  `Charge = "collision"`, matching the settings file (`:381`), and
  `build.ps1` refuses a settings tier table that differs from `Tiers.lua`.
  Decided together with the charge's impact cry below.

- [x] **The one-time physics-proxy rescue.** Ruled as proposed: delete the
  rescue (`Rear.lua:856-865`) and `HasRescuedPhysicsProxy`. Players' saves
  never reached the state it repairs, and `:876` states the mod leaves
  `SetAnimationDrivenMotion` to the engine.

- [x] **`RearAnimSpeed` and the standing rear.** Ruled as proposed: document
  `RearAnimSpeed` as the charge's playback speed (entry point `:235`,
  settings file `:1108`), and `RearAnimMs` (`Rear.lua:420`), used only for
  the standing rear, stops dividing by it.

- [x] **The cooldown icon after a save load.** Ruled not a bug: the load
  handler already clears `RearNextAt` and `ChargeNextAt`
  (`HorseCollisionMod.lua:1893-1894`), so `UpdateMoveCooldowns` takes the
  icon down on the next tick. Delete the unreachable wind-back branch in
  `RearRequested` (`Rear.lua:385-393`) so a cooldown is `now < nextAt`, and
  correct its comment. Phase 2 also checks one unverified case: whether the
  icon buff is written into the save, so that a relaunch and load of a save
  taken with the icon up leaves it raised with `CooldownIconShown` empty.

- [x] **`CatchYieldImmediately`.** Ruled: delete. A vestigial alternative for
  the post-yield flee, which does not need handling. Remove the constant
  (`HorseCollisionMod.lua:1536-1547`), the yield branch in `WatchRetaliation`
  (`Retaliation.lua:414-425`), `sawYield`, `caught` and `SendStandDown`.
  Record the measured `YieldCaught` result in the diary if absent.

- [x] **The pull-down target probe.** Ruled: the target is the player. In
  nine backed-up game logs `bestCan` (player id) read enabled 23 times and
  `bestCanHorse` never read anything but 0, and vanilla passes the rider
  (`BasicAIActions.lua:59`). Keep the player query; delete the horse query
  and its fallback (`Retaliation.lua:1184`, `:1190-1199`, `:1248-1255`, the
  `pullTarget == "horse"` branch), the per-poll angle tracking
  (`:1203-1242`), and the matching fields of the `PullDown … done` line.

- [x] **The dead Henry set path.** Ruled as proposed: delete `BarkDeath`
  and its call (`Health.lua:837`), `RiderBarkSets`, `RiderBarks` (entry
  point and settings file), and `Bark`'s `rider` parameter; the calls at
  `Bark.lua:1009`, `Fear.lua:106` and `Recovery.lua:1178` drop the `false`
  they pass in that slot. The kill line (`RiderBarkKill`,
  `RiderBarkKillAliases`) is unaffected. Resolves the settings file's
  `RiderBark`/`RiderBarks` finding.

- [x] **The empty impact pool.** Ruled as proposed: keep
  `RiderBarkAliases`, `BarkRiderImpact` and `RiderBark`. Reduce the doc
  (`Bark.lua:211-296`) to what the pool is, that it is empty because an
  impact gets `PlayRiderVocal`'s grunt and sentences belong to kills, the
  four filters an entry must pass, and that a candidate is fired and heard
  in game before it is added. Move any survey or audition history the
  diary lacks (the survey is already at `TESTING_DIARY.md:21295`).

- [x] **The charge's impact cry is silent.** Ruled: `PainByTier.Charge`
  (`Bark.lua:613`) becomes `HurtDown`, as trot and gallop use; `HurtHard`
  (`ZASAH_ZBRANI_SILNY`) is a combat-shout set a bark request cannot reach.

- [x] **`HushVanillaBark` clears its own refresh.** Ruled as proposed: the
  timer (`Bark.lua:1237-1243`) captures the stamp it was armed with and
  clears the option only when `RecentHushes[id]` still holds that stamp, so
  a timer superseded by a refresh does nothing. Closes a gap of up to half
  of `BarkSuppressMs` with the victim still in front of the horse.

- [x] **`WhenVictimRises` and the ragdoll-state shortcut.** Ruled not a
  bug. The phase-1 premise was wrong: backed-up logs show gallop and charge
  victims take the shortcut (`on=ragdoll`) 1.7 to 2.0 s after impact, not
  on the first poll, and without it the same tiers ran the 15 s ceiling
  (`on=neverFlat`) because the height test never reads them flat. It also
  times the crime deferral (`Impact.lua:224`), not only the recovery line.
  No change of behavior; the comment at `Recovery.lua:332-334` and the doc
  above the function are corrected to say the height test serves the fall
  tiers and the ragdoll state serves the ragdoll tiers. Publish-test check:
  on a gallop or charge hit, the recovery line or retaliation must not
  start while the victim is still down; if it does, this reopens.

- [x] **`VictimFlatFraction` ships at 0.45 against a derivation for about
  0.13.** Ruled: restore 0.15 in the entry point (`:884`) and the settings
  file (`:421`); the derivation stands. `60f12a2` set 0.15 with the
  measurement; `2910119`, an unrelated weapon-unequip commit, raised it to
  0.45 with no reason in the commit or the diary. Publish-test check: a
  second hit on a victim still down must not snap them upright; if it does,
  that is the reason for a higher value, and the comment records it.

- [x] **`WhenBodyStops` reads `GetWorldPos`.** Ruled not a bug; no code
  change. Across the backed-up logs the entity reading reports `stopped` on
  about 98% of gallop and charge impacts and about 80% of trot and rear,
  and `RestStillMeters` is tuned against entity readings. The doc above
  `WhenBodyStops` (`Recovery.lua:563`) is corrected to say the entity does
  not track a ragdoll's distance but moves until the body settles, which is
  what timing the rest needs. Trot and rear give-ups (about one in ten
  each, damage at `RagdollLandCeilingMs`) are a known cost, not work.

- [x] **The investigation diagnostics.** Ruled: delete both. `WatchTurn`
  and its calls (`Reaction.lua:190`, `:1044`): its rows read `off by +0deg`,
  so its question is answered. `TraceFallLanding` and its call
  (`Impact.lua:209`): across the backed-up logs the ragdoll state arrives
  after 1.5 s on about 80% of trot, gallop and charge impacts, too often to
  be held falls, so the state it watches is not the landing and it cannot
  answer its question.

- [x] **The impact-throw probe.** Ruled: `ProbeImpactCost` keeps the health,
  state, exhaust and armor fields, which answer what an impact cost. Delete
  the `ImpactThrow` rest watcher (`Health.lua:296-348`, with its unnamed
  8000 ms ceiling), `origin`, the `travel=` field, and the `z=`/`dz=` fields
  with `height()` and `baseZ`, all of which read entity position that does
  not follow a ragdoll.

- [x] **Unused sound tokens.** Ruled as proposed: delete `face`, `foley`,
  `BodyFoleySounds`, `BodyFoleySound` (`Sound.lua:97-120`) and the `foley`
  branch in `ResolveTrigger`; the doc above `ImpactTokens` lists the four
  that remain (`body`, `body_armed`, `face_armed`, `blunt`).

- [x] **The lean's correction throttle is never applied.** `FlipLean`
  skips a flip inside `LeanMinFlipMs` unless `force` is set, and every call
  site passes `force = true` (`Lean.lua:368`, `:487`, `:496`, `:526`,
  `:566`), including the hold corrections the throttle exists for. The
  queue-overflow protection that `:238-257` and the entry point's
  `LeanMinFlipMs` doc describe is therefore off. **Ruled:** delete
  `LeanMinFlipMs` (entry point and settings file), the `force` parameter and
  the throttle block; no behavior change. `979d124` forced the hold
  corrections deliberately to fix a snap-back, and the logs attribute
  animation-queue overflows to many characters, dogs and NPCs among them,
  including sessions with no lean. The comment at `:238-257` becomes one
  line: each correction is a shake entry in the rider's sixteen-entry
  queue, and the deadband keeps the rate down.

- [x] **`ProtectMutt` has no effect.** `Update.lua:276-279` says dogs
  share the generic NPC class and are found by name; the human filter at
  `:312-316` admits only `NPC`, `NPC_Female` and `Player`, and dogs are class
  `Dog` (live scan in the diary, "The human filter was not one"). Henry's
  dog never reaches the `isProtected` test's consequences, and `:288-293` is
  an empty `if isMutt then end` left from removed collision filtering.
  `RearCanHit` (`Rear.lua:1094-1120`) repeats the name test behind the same
  class filter. **Ruled:** delete `ProtectMutt` (entry point, settings
  file, README row), both name checks and the empty block; the class filter
  protects every dog. Phase 2 first reads the companion dog's `ent.class`
  live; if it is a human class, this reopens. Mutt occasionally takes
  damage from an impact and runs off yelping; with the class filter in
  front, that is the engine's own collision, not the mod's reaction path.
  Not work: the rider raises it if it recurs.

- [x] **Two sets of tutorial text.** `Tutorial.lua:33-57` builds the
  banners in Lua, in English, with the configured keys; the localization
  table carries `ui_tutorial_hcm_rear` and `ui_tutorial_hcm_charge`, which
  nothing reads, with different text and no lean entry. Proposal: delete
  the two unused cells, since only the Lua text can name a rebound key.
  **Ruled as proposed.**

- [x] **README settings table.** It lists 97 settings as "the ones worth
  changing" while the player section of the settings file holds about 120
  more (`ShowTutorials`, `ImpactDamage`, `Barks`, `RiderBark`, `RearFear`,
  `ProtectStoryCharacters` among them), and every row repeats a fact the
  file's own comments own. `nexus_settings_block.py` already generates the
  mod page's block from the file. Proposal: generate the README table the
  same way, checked by `--check`, or cut it to a short list of headline
  toggles that points at the file.
  **Ruled: generate.** `nexus_settings_block.py` gains a markdown output;
  the README table is replaced with it, and the release checks refuse a
  README that differs. Descriptions become the file's inline comments. The
  README as a whole is expected to be revisited after the audit.

- [x] **DEV_LOOP's hook section.** `DEV_LOOP.md` is tracked and describes a
  pre-push hook whose script lives in the ignored `.claude/hooks/`, so a clone
  can never follow it. Proposal: cut the section; the hooks are local
  workflow and `STYLE.md` keeps those off the remote.
  **Ruled as proposed.** It also names `.githooks`, which does not exist;
  the local path is `.claude/hooks`. Delete the subsection (`:33-50`); keep
  the staleness-sweep scopes and drop their pre-push mention. The rider
  intends the dev loop to become its own tool for other KCD modders later,
  once its design generalizes; not work for this audit.

- [x] **The balance plan.** `docs/BALANCE_AUDIT.md` is a tracked session
  plan whose stages have run. Its figures and derivations already live in the
  settings file and `Tiers.lua`, as its own last rule requires; what remains
  is superseded tables and the account of the rulings. `HANDOFF.md:134-141`
  and `tools/probe_gait_speed.lua:3` cite it. Proposal: move the account of
  the four rulings to the diary, confirm each derivation is in the code, and
  delete the file.
  **Ruled: delete.** Every stage has run (diary `:22188-22379`, stage 3 at
  `:22611`; step 4 closed by the charge's 0.6 ruling, step 5 by the
  `DynamicRecovery` ruling). Before deleting, confirm the four rulings'
  derivations are in the code and their account is in the diary. Drop the
  settled fear notes from `HANDOFF.md:128-145` and the reference in
  `probe_gait_speed.lua:3`; the diary's references stay as history.

- [x] **README repository layout.** A player-facing README carries 120 lines
  of developer tooling. Proposal: keep the top-level layout in the README and
  move the `tools/` catalog to `DEV_LOOP.md`.
  **Ruled as proposed.** The README keeps the top level, `src/` and
  `docs/`; `tools/` becomes one line pointing at `docs/DEV_LOOP.md`, which
  takes the catalog.

- [x] **The stale armor-table sweep.** `build.ps1:431-440` deletes
  `mod_assets/Scripts/Startup/HorseCollisionMod_ItemData.lua`, a file no
  build has generated since `5718d08`. It exists only for working copies
  older than that. Proposal: delete the block; a clean `mod_assets/`
  regeneration covers the same case.
  **Ruled as proposed.** The only working copy's `Scripts/Startup/` is
  already empty.

- [x] **A full deploy into a running game.** `dev_deploy.ps1` warns and
  continues when the game is running (`:935-940`), then deletes
  `Mods\HorseCollisionMod_dev` (`:971-973`), whose pak the engine holds
  open; under `$ErrorActionPreference = "Stop"` that aborts the deploy
  midway. `flow.ps1 test` avoids it by running `-ScriptOnly` then
  `-AnimOnly` when the game is up (`flow.ps1:260-266`), so only a direct
  call reaches it. Proposal: with the game running, a full deploy syncs the
  loose files as `-Reload` does and says the pak was left alone.
  **Ruled, revised:** `flow.ps1` is the only front door. `dev_deploy.ps1`
  becomes an internal helper that only `flow` calls: its header says so,
  and the direct-call pointers (`AGENTS.md`, `publish_nexus.ps1:392`,
  `dev_console.py:777`, `DEV_LOOP.md`, `.claude/RELEASING.md`) name the
  `flow` command instead. A full deploy with the game running refuses
  before touching anything, since `flow` owns that case; the misleading
  "refusal is kept" comment is corrected. Any `dev_deploy` switch `flow`
  cannot reach (`-Reload` alone among them) becomes a `flow` option if
  still needed, or is deleted.

- [x] **The horse animation files are not in git.** `hcm_horse_database.adb`,
  `kcd_horse_fragmentids.xml` and `kcd_horse_controllerdefs.xml` are hand
  authored (`build_adb.py:905-910`) and live only in the ignored
  `mod_assets/`. `build.ps1:473-480` requires them, so a fresh clone cannot
  build, and a lost working copy loses them. `hcm_actionmaps.xml` is already
  force-tracked there. Proposal: move the three to
  `src/Animations/Mannequin/ADB/` and copy them into the pak as `src/Libs`
  is; correct `build.ps1:414-418`, which says everything in `mod_assets` is
  derived.
  **Ruled as proposed, and first in phase 2**: until it lands these three
  files exist only in the working copy and the install. `build_adb.py`
  already deleted them once (`:905-910`).

- [x] **Unused get-up options.** `hcm_getup_{forward,back,left,right}`
  (`build_adb.py:293-296`) ship on both databases and nothing in `src/`
  requests them; the knockdown chains its get-up inside its own option.
  Proposal: delete the four.
  **Ruled as proposed.** The `hcm_settle` comment (`:285-287`) drops its
  comparison with their rotations.

- [x] **The interactive `:reload`.** `dev_console.py` interactive mode's
  `:reload` (`reload_mod`, `:417-418`) re-executes only the entry point.
  `RELOAD_COMMANDS` (`:170-200`) documents why that leaves the settings
  stale and the detection loop stopped. Proposal: `:reload` queues
  `RELOAD_COMMANDS`; delete `reload_mod`.
  **Ruled: delete** `:reload`, `reload_mod` and the help line (`:835`);
  `flow test` is the reload path, per the front-door ruling.

- [x] **`land`'s build retry.** `flow.ps1:382-398` retries a refused build
  after staging, because "setting the version rewrites the `@release` line
  … which makes the generated API reference stale a second time".
  `pre_release_check.py:493-495` says the version does not appear in the
  LDoc output, and `docs/api` holds no version string. The retry also
  masks any other first-build failure. Proposal: delete the retry; if a
  real second-build cause exists, name it in the comment instead.
  **Ruled, revised:** the premise was wrong. The API reference does carry
  the version, as each module's **Release** field, and it is stale
  (`docs/api/modules/HorseCollisionMod.Armor.html:78` reads 5.11.3 against
  `@release 5.31.4`). Remove the cause: drop `@release` from every source
  file and from `set_version.py`; delete the retry; correct the comment at
  `pre_release_check.py:493-495`. The next build regenerates `docs/api`.

- [x] **`verify_additive.py` runs only by hand.** Its docstring says "Run
  it before publishing"; nothing calls it. `build.ps1`, `flow.ps1 land` and
  `publish_nexus.ps1` all skip it, and `.claude/RELEASING.md` lists it as a
  manual step. It needs the game install, so it cannot gate a clone's
  build. Proposal: `publish_nexus.ps1` runs it against the zip it is about
  to upload, unless `-Force`.
  **Ruled as proposed.** Passes 35 of 35 against `v5.31.4`. The manual step
  leaves `.claude/RELEASING.md:37`.

- [x] **Probes for closed questions.** Three probes exist to answer a
  question the project has settled:
  `probe_fall_landing.lua` measures head-stop landing to set
  `FALL_SETTLE_AT`, and `bcd2c31` ruled head-stop the wrong criterion;
  `probe_horse_mass.lua` starts from measuring the throw against victim
  mass, and throw distance was closed as not measurable from Lua;
  `probe_recovery_states.lua` searched for a flat-versus-rising signal,
  which `IsVictimFlat` now implements. Proposal: delete the three, or move
  them to `tools/legacy/`; the findings live in the diary.
  `restore_alive.lua` belongs with them: it repairs actors left in the
  `unragdoll` profile, which nothing in `src/` sets any more.
  **Ruled: delete all four**, with their README rows; git keeps them.

- [x] **`tools/legacy/`.** Tracked, unmaintained, and by construction a
  record of how investigations went, which the standard says belongs in the
  diary and version control. Every script is recoverable from git history
  (`1984553`). Proposal: delete the directory and the README row; the
  diary already names each script where it was used. Alternative: keep it,
  fix the fifteen stale paths, and exempt it from the narrative rule in
  `STYLE.md` as an archive.
  **Ruled: delete** the directory and its README row. The impact-pool doc
  keeps "fire it in game and hear it before adding" without naming
  `make_audition.py`, which git restores if a line is ever added.

- [x] **Two test-subject tools.** `dev_target.lua` moves an existing NPC
  and pins it with `AI.SetIgnorant`; `dev_subject.lua` spawns a guard soul
  and says moving an existing NPC does not work. Each header contradicts
  the other. Proposal: keep `dev_subject.lua`, delete `dev_target.lua`.
  **Ruled: delete both**, with their README rows; neither is used.


## Findings

Format: `file:line` — problem — planned edit.

### Tooling and enforcement

- [x] `.claude/lint_docs.py` — passes with 0 errors while
  `src/HorseCollisionMod.lua` alone carries about 41 narrative lines. The
  rules match a few exact phrases. — Add rules for timeless words, `the rider`,
  `It was <number>`, `used to <verb>`, `before this`, `no longer`, and
  `shipped before`. Promote to errors where false positives are rare.
- [x] `.claude/hooks/pre-commit`, `.claude/hooks/style-check.sh` — the hook
  comments are themselves narrative ("was broken repeatedly anyway"). —
  Rewrite in the standard.
- [x] `tools/audit_code.py` — reports `RearCooldownBuff` and
  `ChargeCooldownBuff` as unread; `Rear.lua:431` reads them by string. —
  Recognize string references, or record the exemption.
- [x] `tools/*.py` — seven files are tab-indented (`audit_code`,
  `bark_alias`, `bark_lines`, `henry_impact_lines`, `nexus_settings_block`,
  `npc_pain_sets`, `testworld`); the rest use four spaces. — Four spaces
  (PEP 8) throughout.

### src/HorseCollisionMod.lua

Batch 4: comments applied. Four findings need code and moved to batch 3,
item 7: the duplicate `ReactionAnimationState`, the second `GrantPerks`, the
needless `local threshold`, and the `uiActionListener` UI-event logging;
their comments are corrected here.

- [x] `:1-66` module header — says three tiers (there are five); lists
  `hcm_<set>_fragmentids.xml` and `hcm_<set>_controllerdefs.xml`, which do
  not ship; names `hcm_animationControlledTags.xml` (ships as
  `kcd_animationControlledTags.xml`); says seven data files (six); option
  counts stale. — Rewrite against `build.ps1:474-479`.
- [x] `@field` list — truncated or merged entries: `RagdollMinEnergy`,
  `RagdollDampCeilingMs` carries a fragment of the former. `RiderBlur` and
  `CameraShake` say "a gallop" but apply per tier. `ThrowProfileByTier`
  describes a "brake" or "launch" entry mode; verify against `Tiers.lua`. —
  Correct each against the code.
- [x] Config comments — orphans whose settings moved or were removed:
  "What a trot impact does" (describes `ReactionByTier`), the recovery-line
  delay paragraph above `BarkGapMs`, the retaliation paragraph now above the
  rear settings, "What a collision is worth" above `ImpactSoundByTier`. —
  Delete or move beside the setting they describe.
- [x] Config comments — contradict the code: "keep at or below
  `HitCooldownMs`" (setting is `HitMinIntervalMs`); "Gallop only: a trot
  knockdown should stay a shove" (trot shake is 0.6); `ShieldWindowMs` has two
  spliced half-sentences. — Correct.
- [x] Config comments — narrative throughout (`TickSeconds`, `MaxImpactSpeed`,
  `BarkCooldownMs`, `ShieldVictimFromEngineDamage`, blur/blood notes). —
  Reduce each to the constraint or derivation.

- [x] `:895-898` `CameraShake` and `:911` `RiderBlur` — "a gallop impact" and
  "Gallop only: a trot knockdown should stay a shove" contradict the per-tier
  tables. (The shake half is also listed above; fix once.) — Describe per
  tier.
- [x] `:980-1077` impact sound block — the layer format
  `{ trigger, delay, distance, chance }`, the distance-is-volume paragraph and
  the token paragraph each appear three times, from successive rewrites
  spliced together. Four orphan per-tier paragraphs (walk, trot, gallop, "no
  hoofstep") follow `ImpactSoundDistance` with no setting under them. — One
  copy of each above the per-tier table; tier notes beside
  `ImpactSoundByTier`.
- [x] `:1058-1061` `ImpactSoundCrack` — "came out at cartoon volume whatever was
  done to it". — State that the 2D event cannot be attenuated.
- [x] `:1063-1068` `RiderVocal` — "which is what made every earlier attempt at
  Henry's half unusable". — Cut.
- [x] `:1102-1108` `RiderBarkPriority` — "confirmed audible in testing … makes
  the tested configuration the default". — State the constraint (a request
  below the top is discarded) and the value.
- [x] `:1110-1136` hit-readiness block — orphan with no setting under it; names
  `HitCooldownStateDriven`, `HitCooldownMs`, `KnockdownRecoveryMs`,
  `HitReadySettleMs` and `HitReadyCeilingMs`, none of which exist anywhere in
  `src/`. A second paragraph ("Which tiers wait…") is spliced on. — Delete.
- [x] `:1138-1147` `ImpactDust` — says `arrow_soil` is the chosen effect; the
  default is `explosion_dust` and `arrow_soil` is the rear's. "The
  alternatives worth trying" is a note to self. — Correct; cut.
- [x] `:1157-1162` `VictimMarks` — "applied at trot and gallop only";
  `VictimBloodByTier` carries rear and charge. — Correct.
- [x] `:1173` orphan: "How long after the action ends before the displacement
  is read back." — Delete.
- [x] `:1184-1191` `ImpulseDelayMs` — "has been measured throwing one victim
  four meters and another none". — State the constraint.
- [x] `:1213-1244` ragdoll block — the damping paragraph runs into the brake
  paragraph with no break, so `RagdollDamping` and `RagdollMinEnergy` sit
  under the brake's text. Eight `RagdollDamp*`, `RagdollSpeedSoftCapSpan` and
  `SettleFragTag` keys have no comment. — Split; document or point to the
  `@field` list.
- [x] `:1232` "-- Dynamic Ragdoll Recovery" and `:1255` "-- Native Engine
  Ragdoll Stillness" — title-case labels unlike every other comment. The first
  goes with the DynamicRecovery ruling. — Replace with a sentence.
- [x] `:1246-1252` `RisePollMs` — "Both were read from `Config` and declared
  nowhere, so `ApplySettings` refused them…". — Keep the first sentence.
- [x] Victims are "he" throughout the retaliation and repair docs (`Baseline`,
  `RepairFloor`, `RepairFightCost`, `CatchYieldImmediately`,
  `RetaliationReleaseMs`); women are victims too. — "they".
- [x] `:1344` a stray `--- Last time each entity was reported as a miss` heads
  the `SphereCache` doc; it belongs to `RecentRejections` (`:1374`), which has
  none. `SphereCache` states its budget as "Measured in game it takes…". —
  Move the line; keep the figures as a derivation.
- [x] `:1398-1408` `SpeedHistory` — "That would explain a gallop being recorded
  as a walk" is a hypothesis. — State the purpose.
- [x] `:1413-1422` orphan: "How long after a reaction begins the victim is
  rebuilt, per tier … Not settings" spliced onto the `ReactionAnimationState`
  doc. — Delete.
- [x] **`ReactionAnimationState` is assigned twice**, `:1438` and `:1776`, with
  different docs. — Keep one.
- [x] `:1442-1444` orphan: "How long after the rebuild the victim is asked to
  re-plan". — Delete.
- [x] `:1458-1467` `PhysicsReadyMs` — "the readiness probe this replaced …
  Before this, the brake and the damping waited on a probe". — One frame; the
  handover is observed at 16 ms.
- [x] `:1469-1477` `RetaliationPollMs` — "The per-tier tables live in Tiers.lua"
  is spliced into its doc. — Delete the sentence.
- [x] `:1519-1527` `RepairStepValue` — sweep narrative. — One step is 0.1389,
  the argument is ignored, the ceiling is 0.8430.
- [x] `:1535-1546` `CatchYieldImmediately` — "measured as `YieldCaught…`",
  "Turn it on only if a victim is ever seen running". — Constraint only.
- [x] `:1576-1582` orphan "How the ragdoll handover is watched…" heads the
  `AudioProxyLifetimeMs` doc, which also carries "measured at four
  microseconds". — Move the orphan to `RagdollAnimationState`; trim.
- [x] `:1591-1618` the `FallPending` doc is spliced into the middle of the
  `RagdollAnimationStates` doc, so each table sits under the other's text.
  Both are history ("the mod only ever knew the first. Counted over a
  session's log…"; "The readiness cooldown used to prevent this… the diary
  said so"). — Separate; constraint only.
- [x] `:1636-1648` `RagdollLandCeilingMs` — "On the fifteen second ceiling that
  victim waited out…". — Keep the 1.9 to 2.9 s derivation.
- [x] `:1707-1716` `ApplySettings` — stillness cvars under a title-case comment,
  with a needless `local threshold`. They overwrite the player's own
  `wh_rd_Still*` cvars on every load. — Tidy; say so in the settings file.
- [x] **`GrantPerks` runs twice on every load**: in `ApplySettings` (`:1703`)
  and again in `uiActionListener` (`:1938`). — Remove one.
- [x] `:1720-1758` `AnimationDatabases` doc — "the reason given on
  ImpactProbeSamples above" (it lives in `Health.lua`), "what 2.0.0 shipped",
  "the last point where the mod touched Theresa", a trailing empty `--`. —
  Fix the pointer; cut the history.
- [x] `:1784-1790` `AnimationSets` — "it resolves correctly, but … and stops"
  reads as a finding. — State the constraint.
- [x] `:1860-1897` load-screen reset — "was missed, which is the whole of
  why…", "Measured: presses reached the hook at +112 ms…", "the other
  deadline missed when the rear's was fixed". — One sentence: level time
  rewinds on load, so every deadline stamped against it is cleared.
- [x] `:543` — "Knockdown impulse. Trot and gallop only"; `ThrowByTier` trims
  `Knockback` and `Uplift` for the charge too (`Reaction.lua:318`). —
  Correct. (Found in the `Armor.lua` pass.)
- [x] `:955-958` barding — "Three flat effects rather than one multiplier";
  damage is a multiplier. — Correct. (Found in the `Armor.lua` pass.)
- [x] `:1842-1853` `uiActionListener` logs every UI event whose name contains
  dialog, item, money, msg, surrender or inventory whenever `LogTelemetry` is
  on. Investigation scaffolding. — Remove, or ruling.

### src/HorseCollisionMod_Settings.lua

Batch 4: comments rewritten throughout. Superseded by batch 2: the
`DynamicRecovery` block, `ProtectMutt`, `RiderBarks` (so the
`RiderBark`/`RiderBarks` pair is gone) and `LeanMinFlipMs`. Every key now
carries a description. `ImpactDamageByTier`'s gallop note corrected to four
in five (0.15 uniform variance on 111 against 100 health). The `Sound.lua`
half of the crack finding is carried to that file's pass.

Player-facing: descriptive only, no rationale, no measurements, no history.
Developer reasoning belongs in the entry point's `@field` list or
`docs/TECHNICAL_DETAILS.md`. Most orphans and duplicates in the entry point
recur here.

Orphans and misplaced blocks:

- [x] `:36-40` — "They used to live here… which is why" is history. — Cut.
- [x] `:136-145` — describes a health floor ("Set it to 0 to restore the
  behavior 3.0.0 shipped with") above `SuppressAutoCureSec` and
  `AutoCureHealthLimit`, which are not a floor. — Rewrite for the two
  settings under it.
- [x] `:149-158` — the retaliation paragraph sits above the key bindings; the
  retaliation settings are at `:317`. — Move.
- [x] `:179-196` — five orphan paragraphs above `ImpactDustEffectRear`: the
  charge push, the rear as its own tier, the rear's landing sound, "Its level
  is fixed", and "The two armor layers sit further back than they did… Both
  were confirmed playing in the log". — Delete; keep one line on the rear
  dust.
- [x] `:199-208` — the charge's sound paragraph sits above the strike
  settings, and says `hs_hp_soil` "is set back from the ear", which `:861`
  says does nothing because the event ignores position. — Delete; the
  charge's sound note goes beside `ImpactSoundByTier`.
- [x] `:342-361` — two damage-model paragraphs sit above `HitStrengthByTier`;
  the damage settings are at `:640-665`. The first says clothing sums to
  about 0.4 and is ignored; `ImpactDamageIgnoredArmor` is 0.5, which the
  worked example in the second uses. — Merge into one block above
  `ImpactDamageByTier`; use 0.5.
- [x] `:423-431` — "What a tier does to the victim's body" heads
  `ImpactSoundByTier`; it belongs to `ReactionByTier` (`:552`). — Move.
- [x] `:918-943` — the hit-readiness block (see the entry point finding),
  with its history ("The settle was 2000… That is what 'muddy and
  unresponsive' was"). Only `:944-948` describes `HitMinIntervalMs`. —
  Delete the rest; drop the two blank lines after.

Contradictions with the code:

- [x] `:430-431` — layer format given as `{ event, delay, volume, optional
  pitch }`. `Sound.lua:255-258` reads `{ trigger, delay, distance, chance }`.
  — Correct.
- [x] `:502-503` — `RiderVocalByTier` format given as `{ event, delay, pitch,
  volume }`; `Sound.lua:518-521` reads `{ trigger, delay, distance, chance }`.
  — Correct.
- [x] `:272-278` — the lean doc names `LeanPeriod`, `LeanAmplitude` and "a
  period of 30 and a duration of 2"; the settings are `LeanTravelAmplitude`
  and `LeanHoldAmplitude`. `LeanPollMs`, `LeanDeadband`, `LeanMinFlipMs`,
  `LeanRunawayFactor` and `LeanShakePeriod` carry no comment. — Rewrite
  against `Lean.lua`.
- [x] `:560-566` `ThrowByTier` — "What makes a charge throw further than a
  gallop is the speed it is resolved at". The charge's throw is
  `RearChargeThrow` times the lunge transfer; `ThrowByTier` is only trim on
  `Knockback` and `Uplift` for both tiers. — Say so.
- [x] `:577-584` `ThrowProfileByTier` — describes the charge's cap as a
  counter-impulse held at the commanded speed; confirm against
  `Tiers.lua:371`. "armour" twice at `:588`. — Reduce to the three steps
  and the formula; American spelling.
- [x] `:667-670` `CameraShake` and `:684` `RiderBlur` — "a gallop impact",
  "Gallop only: a trot knockdown should stay a shove"; both are per tier and
  the trot shakes at 0.6. — Describe per tier.
- [x] `:766-771` `ImpactSound` — "the horse's own landing carries the weight,
  and a blunt impact ten milliseconds later"; no tier is built that way. —
  Cut.
- [x] `:789-791` — "Walk names the cloth impact outright"; the walk tier is
  foley and bodyfall, no impact. — Cut.
- [x] `:867` `ImpactSoundCrack` — "gallop only"; `Sound.lua:244` plays it on
  gallop and charge. The same error is in the `Sound.lua:240` comment. —
  Correct both.
- [x] `:953-970` `ImpactDust` — describes a distance test against
  `ImpactDustSettleDistance`, which does not exist; the code watches
  vertical speed (`ImpactDustFallVz`, `ImpactDustLandVz`, `Marks.lua:319`).
  "The victim's height is position is sampled" is garbled. `arrow_soil` and
  "alternatives worth trying" as in the entry point. — Rewrite.
- [x] `:989-990` `CollisionIsCrime` — "at trot and gallop"; `Impact.lua:233`
  reports a crime for any impact that wounds, which includes the rear and
  the charge. — Correct.
- [x] `:1018-1021` `BarkCooldownMs` — "Keep at or below `HitCooldownMs`"; no
  such setting, and at 3000 it is already above `HitMinIntervalMs` (700). —
  Cut.
- [x] `:556` `ReactionByTier` — "a rear is a trot-class blow, not a gallop's"
  ranks one tier under another. — Cut.
- [x] `:640-648` `ImpactDamageByTier` — "kills about nine unarmored men in
  ten": with 0.15 variance a 111 hit exceeds 100 health about 83% of the
  time. — Verify NPC health and restate, or cut.

- [x] `:127` `ArmorReferenceWeight` — "the weight counted as a full set";
  it is the weight whose impulse multiplier is 1.0 (the block above says
  so). — Correct. (Found in the `Armor.lua` pass.)
- [x] `:730-732` barding — "Three flat effects rather than one multiplier";
  damage is a multiplier. — Correct. (Found in the `Armor.lua` pass.)

Duplicates:

- [x] `:780-865` — the layer format, the distance-is-volume paragraph and the
  token paragraph each appear three times, and the walk, trot and gallop
  notes appear twice (inside the table at `:433-466` and again as orphans at
  `:846-865`). — One copy of each above `ImpactSoundByTier`; the tier notes
  stay inside the table.
- [x] `RiderBark` (`:905`, default false) and `RiderBarks` (`:1017`, default
  true) are separate switches with near-identical names; both are read
  (`Bark.lua:464`, `:1045`). — Say in each comment what the other does, or
  ruling on merging them.

Fragments:

- [x] `:1040-1041` `ProtectMutt` — "around on his back" is a stray fragment.
  — Cut.
- [x] `:1114-1115` `RearChargeStrikePollMs` — "further hits" is a stray
  fragment. — Cut.
- [x] `:777` — trailing empty `--` line. — Cut.

Narrative, rationale and people (player-facing, so reduce to what the setting
does):

- [x] `:49-91` — the `DynamicRecovery` block and the "Native Engine Ragdoll
  Stillness CVars" label are title-case banners; the stillness settings
  overwrite the player's own `wh_rd_Still*` cvars and do not say so. The
  first block follows the DynamicRecovery ruling. — Say what the cvars are.
- [x] `:159-168` — "the key a vanilla action answers to is not always
  visible…" is developer reasoning. — Keep the list of eight keys.
- [x] `:174-175` — "set by feel". — Cut.
- [x] `:212-228` `RearChargeImpactSpeed` and `:230-247` `RearChargeThrow` —
  measurements (0.02, 0.07, 25.9, 0.3 to 1.0 m) and design argument. —
  Keep: the figure is `RearChargeImpulse` over horse mass and should follow
  it; `RearChargeThrow` is the dial.
- [x] `:248-266`, `:303-315` fear bands — "a man", "where he is standing";
  "the rank Henry's own lines were confirmed audible at". — Keep the reach
  derivation in one line; "they"; cut the history.
- [x] `:322-323`, `:980-985` — victims are "him", "a man". — "they".
- [x] `:524-526` `RiderBlurByTier` — "they came apart in tuning". — Cut.
- [x] `:755-761` `HorseBoltsWhenSpent` — "A horse that always bolts is a
  punishment…". — Cut.
- [x] `:896-916` `RiderBark`, `RiderBarkPriority` — points the player at
  `Bark.lua`; "confirmed audible in testing… makes the tested configuration
  the default". `RiderBarkKill` has no comment. — Describe each setting.
- [x] `:1057-1063` banner — "tuned by riding at people repeatedly and the
  shipped values are the ones that felt right". — Keep only that deleting a
  line restores the default.
- [x] `:1086-1093` — "Raise the risk here", "came out of tuning them
  together", "adding to it fought that". — Describe.
- [x] Undocumented keys: `HorseVocal`, `HorseVocalCooldownMs`,
  `HorseVocalRankByTier`, `RiderBlurHoldMs`, `RiderBlurChroma`,
  `RiderBlurSteps`, `RagdollBrakeArmorScaleArmored`,
  `RagdollBrakeArmorScaleUnarmored`. — One line each, or move them under
  the Internals banner.

### src/HorseCollisionMod/Tiers.lua

Batch 4: applied. The gallop derivation is restated as arithmetic: at 111
the roll clears 100 above 0.90, about four in five on a bare horse; the
barding step is gone, since barding raises damage. The rear's span
corrected to 64 to 86 (99 fully barded). The header now says the settings
file ships a copy of each table that the build checks.

- [x] `:9-13`, `:21-23` header — "That shape is what let the rear and the
  charge quietly fall out…", "the entry point carried a second copy of all
  eight, and they drifted". There are nine tables. — Cut the history; say
  nine.
- [x] `:67-70` `GetSpeedTier` — "It sat in `Log.lua` for as long as…". — Cut.
- [x] `:98-133` `ImpactDamageByTier` — "across the whole testing diary",
  "measured live at `dealt=92.2 engineTook=29.1`", "The earlier 95 was set
  when…", "Measured live at 117.2 and 116.0", "the rider wanted", "Making it
  kill one in six would have cost 89", victims as "a man". The gallop
  derivation says 113 before barding and 111 with it, but
  `BardingDamageBonus` raises damage, so barding cannot lower the figure. —
  Keep the arithmetic (health 100, variance 0.85 to 1.15, the threshold per
  tier); verify and restate the barding step; "they".
- [x] `:146-173` `StaminaShareByTier` — "measured 210 on the test horse and
  230 on another", "the diary records", "by the rider's ruling". — Keep the
  derivation: 0.20 is one pool at level 0 and five at the top; the perk
  unlock costs 0.72 and 0.60.
- [x] `:194-196` `ReactionByTier` — "The rear sits with the trot… the old
  `RearReaction or TrotReaction` fallback" is history and ranks one tier
  under another. — Cut.
- [x] `:205-222` `ThrowByTier` — "two such figures sat in the code for
  months", "the audit's fourth ruling", "It was briefly made to scale…".
  "What separates a charge from a gallop is the speed it is resolved at, and
  everything downstream is the gallop's own machinery" is false: the charge
  has its own launch and rail in `ThrowProfileByTier`. `ThrowByTier` reaches
  both tiers only as trim on `Knockback` and `Uplift`
  (`Reaction.lua:318`). — State that and stop. Resolves the settings file's
  `ThrowByTier` finding.
- [x] `:228-297` `ThrowProfileByTier` — "years of circles", "every previous
  attempt here was", the 0.02, 0.07, 25.9 and 0.3 to 1.0 m readings. "armour"
  at `:269-270`, `:286`, `:316-319`, `:329` comment. — Keep the ownership
  statement, the three steps and the formula; American spelling.
- [x] `:373-379` — "measured, a victim railed at 6.03 was driven to 8.64 and
  9.17 m/s". — Constraint only: drag does not bind a ragdoll, so the rail is
  enforced.
- [x] `:401-403` `HitStrengthByTier` — "The charge used to probe itself as a
  minor injury…". — Cut.
- [x] `:452-478` `TierTables` — the drift story (`:457-462`) and "those
  figures are now the same ones the shipped build runs". The claim of "one
  literal per concern" is false while the settings file ships whole copies
  of all nine tables (see the ruling). — Cut the history; describe the
  binding.

### src/HorseCollisionMod/Armor.lua

Batch 4: comments applied; the double blank lines are single. Three
findings need code and went to batch 3, item 7: `ArmorOf`'s `tack`,
`ArmorCurve`'s `invert`, and the dead `if not barding`; their docs describe
the code as it stands until then. The hits column is recomputed: villager 1
to 2, light 2, guard 2 to 3, mail 3, heavy mail 3 to 4, plate 4 to 6.

- [x] `:1-15` module header — says two multipliers through a single curve.
  The stamina half is `ArmorStaminaAdd`, a surcharge off its own anchor, and
  damage is a third effect on `smash_def`; only the impulse uses
  `ArmorCurve`. — Rewrite: impulse (weight, `ArmorCurve`), stamina surcharge
  (weight), damage (`smash_def`), plus barding.
- [x] `:15-16` no blank line or `---` between `@release` and the `TackTypes`
  doc, so LDoc folds "The `armor_type_id` values worn by a horse" into the
  module doc. — Separate.
- [x] `:16-27` `TackTypes` — two docs spliced ("The values worn by a horse…"
  then "Only the saddle and the horseshoes…"); "which is why the barding
  multiplier had to be cranked before it did anything" is history. — One
  doc: ids 10 and 11 are tack; 12 is excluded because the game files
  head-and-neck barding under it.
- [x] `:61-64` `ItemIndex` — "This replaces a 50 KB table… the download no
  longer carries them". — Cut.
- [x] `:154-156`, `:159` `ArmorOf` — "`tack` true… is what Phase 3 barding
  needs". Nothing passes `tack` true: `BardingCoverage` (`:540`) calls
  `ArmorOf(horseEnt)` and sums the non-tack pieces. The doc also calls spurs
  and bridles tack; neither id is in `TackTypes`. — Drop the unused
  parameter (always exclude tack; behavior unchanged); rewrite the doc.
- [x] `:237-246` `ArmorCurve` — "One curve serves both halves… the stamina
  cost takes it directly". `ArmorImpulseScale` is the only caller and always
  passes `invert` true. — Describe it as the impulse curve; drop `invert`,
  or record why it stays.
- [x] `:304-318` `ArmorLerp` — "four copies of the same seven lines", "named
  for the brake because that is what first needed them", "Reading the
  endpoints as… is the way round it". The consumer list (brake, cap, drag,
  recovery) omits the charge's `transfer` (`Tiers.lua:366`); the recovery
  use goes with the DynamicRecovery ruling. — Keep: the span is
  `RagdollBrakeArmorScale*`, inside the curve's 0.35 to 1.5, and a villager
  (about 1.15) lands near but not at 1.
- [x] `:364-367` `ArmorStaminaAdd` — "It used to be a multiplier running 0.75
  to 3.0…". — Cut. Keep the 50 derivation (villagers 5 to 7, mailed guards
  45 to 65).
- [x] `:406-418` `ImpactDamageScale` — two `---` doc headers spliced; the
  first names `ArmorStaminaScale`, which does not exist, and calls this "the
  third of the three armor multipliers". — Delete the first block; keep the
  weight-versus-`smash_def` sentence in the second.
- [x] `:423` formula omits `ImpactDamageArmorCurve` and the floor. — Give the
  full expression.
- [x] `:427-431` — "Measured against the raw figure, a villager was already
  taking 17 per cent off…". — Constraint only: clothing sums to 0.30 to
  0.50 and is subtracted.
- [x] `:441-449` table — multipliers check out at scale 2.9, ignored 0.5,
  curve 1. The hits column does not at gallop 111 ±15% on 100 health: heavy
  mail (33.6) is 3 to 4, plate (22.3) 4 to 6. — Recompute with the
  `Tiers.lua` health check, or drop the column.
- [x] `:473-497` inner comment — "measured on ordinary town guards it lands
  between 0.08 and 0.19" contradicts the table (guard 0.52; it predates the
  2.9 scale). "a man", "Before `ImpactDamageOwnsTheHit` handed…", "a gallop
  now worth 111". — Keep: the curve exponent (1 is the plain hyperbola) and
  the floor, 0.14 = the engine trample's mean 16 over 111; "they".
- [x] `:521-526` `BardingCoverage` — "barding's three effects are flat
  additions and reductions"; `BardingDamageScale` is a multiplier. `if not
  barding` (`:542`) can never be true. — Correct: force and stamina are
  flat, damage is a multiplier on the victim's damage; delete the dead
  check.
- [x] `:600-601` `BardingDamageScale` — "Damage is a number rather than a
  picture, so a subtle change here is actually achievable, unlike
  knockback". — Cut.
- [x] `:612-618` `BardingStaminaRelief` — "the half of barding a player
  actually feels: one more guard ridden down…"; "the two surcharges" (the
  combat surcharge and the armor one — name them). — Describe.
- [x] `:219-220`, `:233-234`, `:286-287`, `:299-300`, `:341-342`,
  `:358-359`, `:507-508` — two blank lines between functions; the rest of
  the file and the other modules use one. — One.

### src/HorseCollisionMod/Reaction.lua

Batch 4: applied. `SendHitReaction` settled from the diary ("The bark does
not come from the mod"): the message feeds perception and does not cause
vanilla's bark, so this file was right and the settings file and the entry
point's `@field` were corrected in the same commit. The 50 ms first release,
the brake's `+ 10` and the `+ 1.0` chest height keep their literals with the
derivation in the comment. Code findings (the unused callback parameters,
`armorScale`, the `ImpulseApplied` movement figure) went to batch 3, item 7.

- [x] `:1-19` module header — "`Ragdoll` and `ImpulseVictim` hand the body
  to physics": `Ragdoll` does, `ImpulseVictim` only pushes a body already
  handed over. No blank line or `---` between `@release` and the
  `SendHitReaction` doc (same LDoc fold as `Armor.lua`). — Correct; separate.
- [x] `:26-27` `SendHitReaction` — says the message does not produce the
  bark; the settings file (`:1139-1140`, "posting this is what makes
  vanilla's own barks fire") and the entry point's `@field` (`:171`, "so
  barks still fire") say it does. — Settle which is true from the diary;
  make all three agree.
- [x] `:72-73` `PlayReaction` `prefix` — lists `hcm_stagger_` at walk and
  `hcm_knockdown_` at trot. Shipped: walk stagger, trot and rear `hcm_fall_`;
  nothing ships `knockdown`. — List the three prefixes without tiers.
- [x] `:80-89` — two comments on the same `so_` strip; the second is
  history ("which is how every direction ended up sharing one ragdoll
  timing"). — One line: option names and per-direction tables use the bare
  word.
- [x] `:92`, `:1374-1379` — stray blank lines (double blank inside a
  function; five trailing). — Remove.
- [x] `:97-102` — "This used to say the women had no AnimationControlled
  fragment…". — Cut.
- [x] `:119`, `:920-933` — misindented `local ok, err`, comment block and
  `local function requestFall`. — Reindent.
- [x] `:132-145` release repeats — "Victims were still being carried
  through walls occasionally". The first attempt's 50 ms is a literal. —
  Keep: a fragment re-applies its movement layer while blending, so the
  release repeats. Name the 50 or tie it to `ImpulseDelayMs`.
- [x] `:160-183` fall handover — two comments spliced; "The innkeeper
  leaning on nothing" anecdote; "Until then both tiers that can knock
  someone down default to fall" is roadmap. — Keep: the fragment's Ragdoll
  ProcLayer times the handover; only `hcm_fall_` carries one, so only it
  gets the rebuild wait.
- [x] `:185` "is now in flight" — timeless word. — "is in flight".
- [x] `:215-219` `PlayTierReaction` — "Every tier used to decide this at its
  own call site…". — Cut to: the one place a tier becomes a reaction.
- [x] `:239-241` — "reads exactly like vanilla's non-reactions, which is the
  thing this mod exists to replace". — Constraint only: a victim getting
  up still takes the reaction.
- [x] `:268-275` — "which is why it is so hard to reproduce on purpose";
  "The readiness cooldown used to prevent this… the diary said so". — Keep
  the mechanism (a second clip cancels the first's pending handover); cut
  the rest.
- [x] `:331`, `:1291` "armour", `:624` "neighbouring" — British spelling. —
  American.
- [x] `:344-364` `WhenVictimIsPhysical` — "`actor:Fall` requests the fall":
  `Ragdoll` plays `SettleFragTag`, not `actor:Fall`. Carries measurements
  (1.81 m to 1.57 m over 18 impacts), "the rider described the victims as
  bricks", and a paragraph on the removed mass probe and its three
  settings. — Keep: physics writes to a body not yet ragdolled are
  discarded; the wait is `PhysicsReadyMs`, one frame.
- [x] `:399-401` `DampVictim` `armorScale` — "Chooses the commanded throw
  distance". In this function it is only printed on the telemetry line;
  armor reaches the throw through `profile`. — "Logged only".
- [x] `:421-432` `bodyPos` — "this project established that once already",
  "every one was fiction… while the rider watched". — One sentence: the
  entity does not follow a ragdoll; read the physics body.
- [x] `:445-447`, `:529-531` banner blocks ("The Impact Parachute", "The
  Anti-Slide") — no other module uses them; the names appear nowhere else.
  — Replace with one plain line each, or drop.
- [x] `:515-519` brake timing — "the diary checked exactly this and found
  16.83 m/s against a later `airPeak` of 12.51". `:524` `+ 10` is a
  literal. — Keep: the gallop's victim is thrown at contact, so the brake
  fires at the impulse delay. Name the 10 or record why it follows the
  impulse.
- [x] `:586-591` — "It was computed and then dropped from this line…". —
  Cut.
- [x] `:599-625` `release` — twenty lines of diagnosis ("Diagnosed from the
  rider's cure", "That is why the symptom was intermittent"). — Keep: a
  sleeping body discards writes, so wake it first; otherwise `min_energy`
  stays set and a corpse can sleep mid-air.
- [x] `:642-648` — "A ceiling of 6 m/s was letting bodies travel eight to
  twelve meters because it was watching the wrong thing". — Keep: the cap
  and drag act on this speed, so it must be the body's.
- [x] `:699-735` cap — carried forward from `Tiers.lua`. A table of 24
  throws, "the 1,208 kg the mod used to write", "The rewrite is gone". —
  Keep: the cap is a ceiling, not a subtraction, so it holds however the
  body got its speed; on a launch tier it is a rail at the commanded speed.
- [x] `:743-762` rail enforcement — "Measured on a victim railed at 6.03…",
  "the enforcement that was removed". — Keep: drag does not bind a ragdoll;
  a counter-impulse of `mass * (speed - cap)` does, every poll, and cannot
  shorten the commanded throw.
- [x] `:809-824` drag — measured peaks, "The rider rode armored victims at a
  flat 15.0 and reported no syrup". — Keep: `strength` saturates at
  `cap + span`, so the drag figure itself is armor scaled.
- [x] `:863-868` `Ragdoll` doc — "Used at trot and gallop" (shipped: gallop
  and charge); "`actor:Fall` switches the victim". — Correct both.
- [x] `:873` `tierScale` — "share of the configured impulse, 0 to 1"; it is
  `ThrowByTier`, trim on `Knockback` and `Uplift`, and nothing clamps it. —
  "the tier's `ThrowByTier` trim".
- [x] `:874-875` `armorScale` — "sets their ragdoll mass and nothing else".
  The mod writes no mass (`:1194-1195` says so); it is passed on for
  logging. — Correct.
- [x] `:882-885` `tierName` — justifies itself by `ImpactDamage` returning
  early. — "Logged on the `FallToBlend` line."
- [x] `:888-899` damping clear — "one cause for three symptoms that looked
  separate", "Measured, a commanded 3.00 m/s… eight centimeters" (the same
  figure again at `:910-911`). — Keep: a body under `min_energy` sleeps and
  ignores impulses, so clear it first.
- [x] `:906-919` — describes calling `RagDollize` then `Fall`; neither is in
  the code, and `:1025-1029` says `RagDollize` must never be added. —
  Delete.
- [x] `:920-932` settle fragment — "the delayed reaction bug where a victim
  takes the hit, walks three steps". — Keep: `actor:Fall` is queued behind
  an uninterruptible animation; an interactive action with a Ragdoll
  ProcLayer at ExitTime 0 is not.
- [x] `:947-961` `FallToBlend` — "the two moments the rider named", "Every
  earlier attempt read a position during the ragdoll and failed". — Keep:
  the two readings sit outside the ragdoll, where the entity matches the
  body.
- [x] `:1031-1034` — "Nothing below throws the victim. The throw is the
  engine resolving its own collision". False for the charge:
  `ImpulseVictim` adds the launch. — Rewrite: the gallop is thrown by the
  engine and braked; the charge is thrown by the launch; both wait for a
  physical body.
- [x] `:1041-1049` — "This tier uses actor:Fall" (it does not); both
  comments describe `WatchTurn` and `TraceRecovery` as controls for an
  investigation. They are diagnostics gated on `TraceRecovery`. — One line:
  traced as `engine-ragdoll` for comparison with the fall path.
- [x] `:1052` `state, waitedForBody` — unused. — Drop.
- [x] `:1063-1072` `ImpulseVictim` doc — "Separated from `Ragdoll` because
  the fall tier… needs the push without the rest": `Ragdoll` is the only
  caller. `profile` and `armorScale` undocumented; `horseEnt` and
  `horsePos` documented out of order. `armorScale` is unused in the body.
  — Rewrite the doc; drop `armorScale`.
- [x] `:1094-1097` — "Leaving early on their account was what stopped the
  charge being thrown at all". — Keep: a launch tier proceeds with zero
  trim.
- [x] `:1112` `+ 1.0` chest height — literal. — Name it, or record the
  derivation.
- [x] `:1119-1124` — "the same target took 67.3 at full speed and 37.7…". —
  Keep the first paragraph; cut the measurement.
- [x] `:1132-1138` — "which is exactly what a charge did whenever…". — Keep:
  with no velocity there is no direction; drop the impulse.
- [x] `:1187-1190` — "which left a report of armored targets moving
  further…". — Cut; keep the mass explanation.
- [x] `:1234-1238` — "a fixed 50 ms produced throws of four meters and of
  nothing at all". — Keep: an impulse before physicalization is ignored.
- [x] `:1283-1289` — "a quarter of a second after impact" (`ImpulseDelayMs`
  ships 50); measurements 12.44 / 14.04 / 21.73 m. — Keep: floor here,
  ceiling in the watch.
- [x] `:1310-1317` — "threw a peasant ten meters… thirteen samples", "a
  man". — Keep: the launch goes along the horse's line; the lift is trim.
- [x] `:1345-1369` `ImpulseApplied` — reads `GetWorldPos`, which `:421-428`
  says does not follow a ragdoll, so `movedIn300ms` does not measure the
  body. "a quarter of a second later" (it is 50 ms). `300` is a literal. —
  Read `GetCenterOfMassPos`, or drop the movement figure.

### src/HorseCollisionMod/Rear.lua

Batch 4: applied. Superseded by batch 2: the cooldown wind-back branch and
its "e.g." comment, and the physics-proxy rescue, so `SetAnimationDrivenMotion`
is now left to the engine and the comment says so. `ImpactIsNewContact` in
the sweep is kept as a guard: `ChargeScoringUntil` is stamped at the press
and closes about 150 ms into the lunge (push at about 1450 ms, window 1600),
while the sweep runs until the lunge is spent, 128 to 416 ms after the push.
Every charge contact in the current log is `tier=Charge` from the sweep, so
the overlap is not observed scoring. `RearChargeWindowMs` corrected in the
settings file and the entry point. The `600` in `RearHorse` keeps its
literal with the reason in the comment. Code findings went to batch 3,
item 7.

The detection loop stands aside while `ChargeScoringUntil` is open
(`Update.lua:91`); it never scores a charge contact. Several comments here
say the opposite, and `RearCharging` is cleared by `WatchLunge`, not
`ChargeForward`. Those two corrections recur below.

- [x] `:3-5`, `:1135-1137` — the "everything else needs speed" framing is
  said twice; the second adds "a stationary rider has never had anything to
  do but shove people". — Keep it once, in the module header.
- [x] `:64-67` — the log lists the keys as `r, q, y, u, o, h`; `RearKeys`
  and the action map also declare `e` and `f`. — Build the list from
  `RearKeys`.
- [x] `:92-100` `HookRearKey` — "bound to `jump`, this reared the horse and
  then jumped anyway" is history. — Constraint only: consuming a press does
  not stop the game acting on it, and a hold and a tap both deliver one
  `press`, so the mod uses its own action.
- [x] `:172-184` `TrackHorseSpeed` — measurements (0.24, 0.12 m, 128 ms,
  0.94 m/s) and "The slide is the whole defect". — Keep: `GetVelocity`
  under-reports a slow horse, so speed is derived from two positions.
- [x] `:220-224` — "These gates all returned silently… after seven attempts
  at the action map had not." — One line: each refusal logs its reason.
- [x] `:275-278` — "Asking only the horse is what made the gate useless". —
  Constraint: a nil velocity would read as zero and pass every press.
- [x] `:295-310` — "is not established", "was briefly thought", "the rider
  riding away", "is now short enough". — Keep: horizontal speed only,
  because the vertical component carries the settling fall.
- [x] `:331-342` — measurements (0.24, 0.11 m/s, 1.4 cm, 0.00). — Keep:
  only the locomotion state predicts whether a rear slides.
- [x] `:361-366` — "a second press there doubled the push" is history. —
  Keep the constraint: between the rear and the push the horse reads idle
  at 0 m/s, so the move's own state gates a second press.
- [x] `:376-377` — "They used to share `RearNextAt`". — Cut.
- [x] `:386-387` — "e.g." and a run-on, out of the file's register. —
  Rewrite; see the ruling on the cooldown icon after a wind-back.
- [x] `:466` `UpdateMoveCooldowns` — "on a save load, which drops the
  deadline": a load winds the clock back and leaves the deadline in place
  (`:386`, `:1328-1329`). — Correct once that ruling is settled.
- [x] `:488-495`, `:759-760`, `:832-833` — stray blank lines. — Remove.
- [x] `:498-518` `ChargeForward` — "used to travel by root motion", the
  three movement-control measurements, "measured at 4300… at 20000". —
  Keep: inside an interactive action an impulse is discarded or stored and
  discharged later, so the rear plays in place and the push follows it.
  Move the measurements to the diary if absent there.
- [x] `:538-546` — "The rider can steer during the rear, and does";
  paragraph on the old fragment. — One line: the heading is read at the
  push because the player can steer during the rear.
- [x] `:564-568` — measured delays (1856 ms, 1408 ms). — Cut; the log line
  reports it.
- [x] `:573-575` — "Started at the press it swept while…". — Constraint:
  the strike starts with the lunge, not the press.
- [x] `:605-642` `WatchLunge` — "The rider's definition", "What came before
  was three numbers… All three were guesses", "the first version of this",
  measured spikes, and an open question ("is not settled… `moved=` is here
  to tell them apart"). `:634` says the peak is "the larger of each
  neighbouring pair"; the code takes `math.min`, the smaller. — Keep: the
  window closes when speed decays to `RearChargeLungeSpentAt` of the peak;
  the peak is the smaller of two consecutive samples, so one spike cannot
  set it; `RearChargeLungePeakMin` guards an early dip. "neighboring".
- [x] `:714-717` `LogActionEnd` — "costs a ride per guess". Its instrument
  is `AnimationControlled`, but the standing rear starts with
  `StartAnimation` (`:879`), which bypasses Mannequin, so for the rear it
  likely reports on the first poll. — Cut the phrase; verify the log line
  still measures anything, and delete the function if not.
- [x] `:761-782` `RearHorse` — describes the standing rear reaching
  `relaxed_rearing` through `StartInteractiveActionByName` and an `hcm_rear`
  option; the standing rear calls `StartAnimation` directly and only the
  charge uses the interactive action (`hcm_rear_charge`). "Reaching it took
  the whole chain", "Every earlier attempt passed the name only". Missing
  `@tparam fragTag`. — Rewrite for both paths; keep the four-file
  requirement and the `ObjectId` argument as constraints.
- [x] `:787` `tierName` — assigned, never read. — Delete.
- [x] `:793-797` — says the detection loop scores the charge "as a
  gallop"; it stands aside. "not what the rider asked for". — `RearCharging`
  gates the sweep, the lunge watcher and a second press.
- [x] `:802-803` "The rider's voice" means Henry's. — "Henry's voice".
- [x] `:807-817` — lockout anecdote ("the same woman", "the rider saw three
  charges"); "2.6 seconds" duplicates the setting. — Keep: a new press is a
  new attack, so the previous lunge's lockouts are cleared.
- [x] `:820-829` — "How long the detection loop scores a contact as a
  charge": it is how long the loop stands aside. "cleared by
  `ChargeForward`", "measured at 144 to 256 ms", "before the loop took it
  over". — Rewrite: the loop defers to the sweep for `RearChargeStrikeMs`.
- [x] `:836-844` — "which `ChargeForward` decides" (`WatchLunge` does);
  "any impact the detection loop finds is scored as a gallop"; "A fixed
  2600 ms outlives the move…". — One line: this timer is the ceiling for a
  lunge never seen to decay.
- [x] `:876-878` — "SetAnimationDrivenMotion is left alone" beside
  `:858-865`, which sets it; "gracefully". — Settle with the ruling below.
- [x] `:882` `-- hcm_rear_charge` — restates the branch. — Cut.
- [x] `:888-891` — "the ordinary detection loop scores it" (the charge). —
  The charge has its own sweep; the standing rear has `RearStrike`.
- [x] `:901-904` — "The call returns true for any string" describes
  `StartInteractiveActionByName`, which the standing rear does not use;
  `600` is a literal. — Scope the comment to the charge; name the delay.
- [x] `:919-929` `ChargeStrike` — "until the horse was given a physical
  push", "Whether a special move connects should not rest on how well the
  physics behaved", "The rider asked for". — Keep: the sweep is the only
  thing that scores a charge; no cap, each victim once per charge.
- [x] `:960-968` — "the sweep ran for 1600", "closed when the horse slows
  below walking pace" (it closes at a fraction of the peak). — Keep: the
  sweep lives while `RearCharging`; `RearChargeStrikeMs` is the ceiling.
- [x] `:1007-1013` — "The detection loop is scoring the same lunge at the
  same time": it stands aside. "Loop first, then sweep, was the half of the
  double hit that survived". — Check whether `ImpactIsNewContact` is still
  needed here given the stand-down; if kept, state it as a guard.
- [x] `:1034-1043` — readings 0.02, 0.07, 25.9; "never once clears its own
  minimum… at that 3.0 floor… at 10.5". — Keep: the horse is
  `AnimationControlled` through the lunge and cannot be measured, so the
  charge scores at `RearChargeImpactSpeed`.
- [x] `:1086-1087` `RearCanHit` — "a faction test gave dogs a human
  fragment… reached women only by a fallback". — Constraint: humans are
  matched by class.
- [x] `:1230-1235`, `:1247-1248` `RearHit` — the doc says "the trot
  treatment… the charge is the move that earns the ragdoll", but the
  function serves the charge too; the fixed-speed sentence is repeated in
  the body. Missing `@tparam tier` and `hitSpeed`. — Rewrite for both
  tiers; keep the sentence once.
- [x] `:1264-1269` — "That is the double hit on one lunge". — Keep the
  constraint: the contact is recorded so `HitMinIntervalMs` can measure
  from it.
- [x] `:1272-1277` — "applying it to both tiers closed a victim out… after
  an ordinary rear as well". — One line: only tiers listed in
  `VictimLockMsByTier` carry a lockout.
- [x] `:1325-1331` `LoadRearActionMap` — "Nothing here was ever the cause…
  several rides were spent", "+112 ms". — Cut; the refusal logs in
  `RearRequested` say which gate refused.
- [x] Settings `:269` `RearChargeWindowMs` — "how long a charge counts as a
  gallop"; it is the ceiling on `RearCharging`. — Correct.

### src/HorseCollisionMod/Retaliation.lua

Batch 4: applied. "The rider" is "the player" in comments throughout; "he"
for a fighting victim stays, since only men reach the fight branch. The
morale survey moved to the diary ("Morale does not separate women from
men"). `RepairVictim`'s two-part account described the stand-down that
batch 2 removed; it now says the relationship changes the next decision and
a running flee ends on its own. The `EndRetaliation` doc sits on its
function. The pull-then-fight comment moved beside the `PullRiderDown`
call it explains. Code findings went to batch 3, item 7.

File-wide: "the rider" is used throughout for the player (`:46`, `:483`,
`:509`, `:580`, `:583`, `:688`, `:862`, `:871`, `:888`, `:939-951`,
`:1043-1048`, `:1079-1101`). — "the player". "he/him" for a fighting
victim is accurate (only men reach the fight branch) and stays.

- [x] `:17-22` — the `q_ledecko` and `q_hareHunt` examples justify the
  method by precedent. — Keep one clause: vanilla quests set context options
  the same way.
- [x] `:44-49`, `:129-136` — the guard behavior is explained twice; the
  second adds "An earlier revision gated soldiers out; the gate was wrong
  and has been removed." — Keep it once, in `CanRetaliate`; cut the
  history.
- [x] `:51-73`, `:118-122` — the gender routing is explained twice; `:68-73`
  carries a survey ("twenty one NPCs in Rattay", the morale ranges) and
  "the honest implementation, not a shortcut". — Keep once in the header:
  the combat tree tests gender, not morale, so the mod routes on gender.
  Move the survey to the diary if absent.
- [x] `:77-78` — no blank line or `---` between `@release` and the
  `RetaliationOption` doc (same LDoc fold as `Armor.lua`). — Separate.
- [x] `:94-95` — "Confirmed against telemetry rather than assumed". — "The
  values `GetGender` returns."
- [x] `:138-141` — "if the distinction is ever wanted" is speculative. —
  "Read for the log only."
- [x] `:183-184` — "this morning… today's ride" anecdote. — Cut.
- [x] `:213-214` — "The first contact is always free" holds only while
  `RetaliationFreeBumps` is at least 1. — "Contacts up to
  `RetaliationFreeBumps` are free."
- [x] `:279-281` — "the `Retaliation` line above" refers to a log line in
  another function. — Name it: the `Retaliation` telemetry line.
- [x] `:328-329`, `:341-343` `IsStillFighting` — "observed on a guard
  closing to two meters"; "An earlier design classified running
  separately… fired in none of six incidents". — Cut both.
- [x] `:366-369` — "it always arrives": `ReleaseWhenFighting` (`:279-281`)
  logs a victim who never reaches the fight as the case to watch for. —
  Drop the claim; state that `alwaysFightWhenHit` removes the morale test.
- [x] `:372-373` — "in six measured incidents it was never reached". — Cut.
- [x] `:481-500` `RepairVictim` — "which is what made this hard to see",
  "bought five seconds", "That is why an earlier reading of this called
  reputation irrelevant", "stood at a meter and a half for twelve
  seconds". — Keep: the flee in progress and the relationship are separate;
  a stand-down stops the first, raising the relationship changes the next
  decision.
- [x] `:513-523` — "in a measured sweep" and the argument list tried. —
  Keep: `surrender_step` moves a fixed `RepairStepValue` whatever its
  argument, caps at 0.8430, and does not read back in the same frame.
- [x] `:568-589`, `:834` — the `EndRetaliation` doc comment is separated
  from its function by `ShowSurrenderHint`; LDoc attaches both blocks to
  `ShowSurrenderHint`, and `EndRetaliation` is undocumented. — Move the
  block to `:834`.
- [x] `:590-610` `ShowSurrenderHint` — "Nothing told the player so… the
  option existed and was invisible". Missing `@tparam npc`. — Keep: a
  provoked fight does not trigger vanilla's hint. Add the param.
- [x] `:651-656` — "measured as the prompt appearing correctly, then
  disappearing". — Keep: leaving the saddle swaps the action map and drops
  the hint, so it is re-asserted on an interval.
- [x] `:686-691` — "Hanging the prompt on that took it down a second after
  it appeared"; says `EndRetaliation` fires when the player is pulled off
  the horse, which `:840-843` says no longer happens (the watcher requires a
  seen fight). — Keep: the prompt follows `IsInCombatDanger`, which is when
  a surrender is possible. Drop the claim about `EndRetaliation`.
- [x] `:709-714` — "needs six quiet passes… five or six seconds":
  `SurrenderHintCalmPasses` ships 3. "Measured after a beggar was reared to
  death, and newly reachable because the rear can now kill". — Cut; the
  constraint is `:704-707`.
- [x] `:736`, `:1059` — log lines not gated on `LogTelemetry`, unlike every
  other line here. — Gate them.
- [x] `:762-766` — "after the action map change wiped the hint… stayed gone
  for the rest of the fight". — Keep: re-showing an id the HUD believes is
  displayed does nothing, so it is hidden first.
- [x] `:786-787` `SurrenderIsTheGames` — "the same source the retaliation
  answer uses, so the two cannot disagree about who is a soldier":
  `CanRetaliate` reads social class for the log only and does not decide on
  it. — Cut the sentence.
- [x] `:840-843` — "no longer reads" is a timeless word. — "does not read".
- [x] `:865-872` — two contradictory comments spliced: "Sent on every
  ending" and "The stand-down is deliberately not sent here"; the code sends
  none. "measured at 0.737". — Keep the second.
- [x] `:884-904` `WatchAftermath` — "One measured victim was repaired…",
  "Measured on one beggar, one build… fourteen seconds… forty seconds". —
  Keep: the repair is re-run after `AftermathSettleMs` because the player
  may keep hitting the victim; a flee ends at `fleeFromNPCParams.distance`
  (150); a stand-down would stop it but holds the victim about 25 s.
- [x] `:939-951` — "Measured at 1.93 m/s against a threshold of 1.8… on a
  rider who had shoved one merchant". — Keep: detection cannot tell who
  closed the distance, so no one new is provoked while the player is in
  combat.
- [x] `:1038-1057` — two comment blocks spliced with no break (offense
  order, then the soldier hint). "which is the whole of what a provoked
  victim did before it existed", "is what made him punch the horse",
  "Reproducible every time", "The mod's own documentation already
  records…". The soldier-hint reason repeats `:782-784`. — Split; keep the
  pull-then-fight order as a constraint; for the hint, refer to
  `SurrenderIsTheGames`.
- [x] `:1086-1089` — "with a Z angle and a zero angle alongside it" is
  unclear. — Name the cvars or cut.
- [x] `:1093-1094` — "as it did before". — "without the pull".
- [x] `:1133` — `local mounted` shadows the outer `mounted` at `:1106`. —
  Rename.
- [x] `:1143-1145` — "one merchant gets the pull within a second and another
  never gets it". — Cut; the log line speaks for itself.
- [x] `:1257-1264` — "Measured on one merchant across 32 polls…", "Whether
  the request is honoured anyway is a separate question"; "honoured". —
  Keep: `CanHorsePullDown` returns 2 enabled, 1 disabled, 0 not applicable;
  `PullDownForce` requests regardless.

### src/HorseCollisionMod/Bark.lua

Batch 4: applied. Superseded by batch 2: `RiderBarkSets`, `BarkDeath` and the
impact-pool doc (reduced in batch 2 to its ruled form). The charge-set
finding follows the batch-3 ruling: `BarkRecovered` now says only the rear
has its own voice. Histories cut here and absent from the diary were moved
to it ("Moved from `Bark.lua` comments"): the three failed hush approaches
and the recovery-line timings. `HushVanillaBark`'s rate corrected to about
thirty ticks a second. The shield's move to `Health.lua` and the redundant
parentheses are code and went to batch 3, item 7.

- [x] `:27`, `:45-50`, `:72-77` — "each of which has already cost a wrong
  choice"; the `KOLIZE_*` paragraph appears twice, both with "reverses an
  earlier decision", "now", "no longer". — Keep one sentence in the header:
  the `KOLIZE_*` sets are pooled because `HushVanillaBark` keeps vanilla from
  playing them itself.
- [x] `:58-59`, `:306-307` — "for the same reason as `ImpactProbeSamples` in
  the entry point" / "above"; it lives in `Health.lua:27`. `:62-63` a doubled
  empty `--`. — Fix the pointer; one blank comment line.
- [x] `:82-104` `Shove` — "the mod's own find", the removed
  `KOLIZE_S_HRACEM_LEHKA` story, "The rider heard", "The lesson
  generalises". Header test 3 already states the rule. — Keep the two
  sets' sample lines; cut the rest.
- [x] `:111-113`, `:1211` — "the rider having just trampled them", "an NPC
  the rider passes". — "the player".
- [x] `:136-148` hurt grades — "what the victim makes at the moment of
  impact, in three grades"; only `HurtDown` is audible (`:596-609`), and the
  two comments contradict each other. — One comment: `HurtDown` is the
  impact cry; `HurtLight` and `HurtHard` name where the graded recordings
  live and cannot be requested.
- [x] `:150-164` bystander sets — removal history. Header test 4 states the
  rule. — Cut, or one line naming the three sets as excluded by test 4.
- [x] `:169-208` `RiderBarkSets` — "These two are confirmed on him" above an
  empty table; the role survey, "The rider rejected it", the audition trap
  and the untested assumptions. — Follows the dead-set-path ruling; if the
  table stays, one line.
- [x] `:211-297` `RiderBarkAliases` — "was recorded as unrecoverable", "the
  rider chose these", the quoted instruction, "for now", "turned out". —
  Follows the empty-pool ruling.
- [x] `:299-314` `RiderBarkKillAliases` — the gender column is explained
  here and again in `PoolForVictim` (`:346-349`); "the two filters described
  above" (there are four). — Keep the explanation in `PoolForVictim`; "the
  four filters".
- [x] `:397-398`, `:446-447` — "two at once is a defect rather than a richer
  moment" twice; "the same man". — Once, in `RiderVoiceReady`.
- [x] `:400-403` — the rewind sentence is hard to parse. — "A hold further
  out than the longest cooldown means the save clock was wound back; it is
  ignored."
- [x] `:406-410` — "A grunt is `RiderVoiceGrunt`" (it is
  `RiderVoiceRanks.Grunt`); "four gallop kills… produced one death line and
  three silences". — Correct the name; cut the measurement.
- [x] `:419`, `:474`, `:527`, `:701`, `:709`, `:999` — redundant parentheses
  around single `cfg` reads. — Remove.
- [x] `:484` "every spoken line the rider has" means Henry's. — "Henry".
- [x] `:592-609` `PainByTier` — "Both tiers" over three entries; test
  history ("Both were tested rather than assumed… fourteen requests"). —
  Keep: those sets are combat shouts dispatched outside
  `dialog:monologRequest` and gated on the engine's `hitStrength`. See the
  charge-cry ruling.
- [x] `:646-648` `PickFromPool` — "once the rider reports which lines they
  actually hear". — Cut.
- [x] `:689-692` `BarkOnCooldown` — "which is the point of having a
  bystander set at all"; there are none. `:702-705` history. — Keep: per
  speaker, so two victims can both speak; a refusal is logged.
- [x] `:723-724` `Bark` — "the whole finding of the investigation behind
  this file". `:756` double blank line. `priority` and `overrideSuppress`
  undocumented; `ignoreCooldown` is "used only for the recovery line", but
  `Fear.lua:106` and the recovery groans (`Recovery.lua:1178`) pass it too. —
  Cut; add the two params; describe `ignoreCooldown` without a caller list.
- [x] `:783-809` — the `HushVanillaBark` note and the message-fields note run
  together with no break; "Three approaches failed… none should be
  retried", "this used to send two of them". — Split; keep: the branch is
  closed ahead of contact by `HushVanillaBark`, and a request below the top
  priority waits or is discarded.
- [x] `:814-823`, `:892-895` — "a man" for the speaker. — "they".
- [x] `:850-861` `BarkForTier` — "Mirrors `GetSpeedTier`" (it is a table
  lookup); "graded by how hard they were hit" (trot and gallop both use
  `HurtDown`); `@tparam` lists Walk, Trot, Gallop, and the charge also
  arrives here. — Correct.
- [x] `:886-895` `BarkCollision` — "which the mod had no counterpart for",
  "The rider heard the gap". — Keep the vanilla condition and its source
  line.
- [x] `:918-934`, `:965-971` `BarkRecovered` — the three failed timings are
  told twice, with the quoted ride. "about 0.15 of its standing height to
  1.59" mixes a fraction and meters. — Keep: the line fires when the body
  leaves flat, read by `WhenVictimRises`; check the figures in the
  `Recovery.lua` pass.
- [x] `:947-950` — "the rear and the charge have a voice of their own"; the
  charge ships `"collision"` and reaches this function. — Follows the
  charge's bark set ruling.
- [x] `:983-984` — "is how the death barks ended up firing over silence". —
  Keep: a dead victim does not rise.
- [x] `:1031-1037` `BarkDeath` — removal history, and "logs the death and
  says nothing." is a fragment. — Follows the dead-set-path ruling.
- [x] `:1054-1196` `ShieldFromEngineDamage`, `LiftCollisionShield` — damage
  code in the bark module; the caller is `Impact.lua:73` and the lifter is
  `ApplyImpactDamage` in `Health.lua`. — Move to `Health.lua`.
- [x] `:1057-1062` — "Five separate levers leave it unchanged" names two. —
  Keep: the engine's collision damage cannot be stopped without a global
  that also governs arrows, so the victim is made immortal through the
  window.
- [x] `:1071-1072` — "for a few hundred milliseconds"; the shield lasts until
  `ApplyImpactDamage`, after the ragdoll resolves, with a 6000 ms backstop. —
  Correct.
- [x] `:1083-1088` — "Testing the entry alone was wrong… one was killed". —
  Keep: only a live shield blocks a second.
- [x] `:1134-1138` — "Every other timer in this mod returns early" on a
  reload; `HushVanillaBark`'s timer does not either. — "Unlike the mod's
  polling timers".
- [x] `:1200-1209` `HushVanillaBark` — "about ten times a second" and
  "twenty times a second"; `TickSeconds` is 0.033, about thirty. "The rider
  heard the result". — Correct the rate; cut the quote.

### src/HorseCollisionMod/Recovery.lua

Batch 4: applied. Superseded by batch 2: `TraceFallLanding`, `WatchTurn`
and the `DynamicRecovery` block. The rise shortcut and `WhenBodyStops` docs
follow their rulings: the height test serves the fall tiers and the ragdoll
state the ragdoll tiers, and the batch 3 finding (a ragdolled body reads at
standing height) is now in the `IsVictimFlat` doc. The misplaced
`IsVictimFlat` doc moved onto its function with all four returns;
`DisarmVictim`, `RearmVictim` and the two dead functions have one-line docs
until item 7 deletes the latter. The "0.15 of its standing height to 1.59"
mix is now meters in both files. Code findings went to batch 3, item 7.

- [x] `:8-13` header — "The two waits"; the file has seven. It says
  `BlendRagdoll` is "while physics owns the body"; `:128-134` says it is the
  get-up on a fall tier and `:264-268` that it is the whole time down on a
  ragdoll tier. — Rewrite: the waits poll the animation state or the body,
  and each carries a ceiling.
- [x] `:25-26` — no blank line or `---` break between `@release` and the
  `ReleaseActorMovement` doc (the same LDoc fold as `Armor.lua`). —
  Separate.
- [x] `:36-38` — "victims clipped into walls exactly as they did without
  it". — Cut.
- [x] `:62-67`, `:90-102` `RecordStandingHeight` — the doc says "Recorded
  once, at the first impact"; the code keeps the maximum ever seen. The body
  is history ("Recording once was wrong… one guard… he was never once
  judged"; "centimetres"). The value is named `head` and read from
  `GetCenterOfMassPos`. — Doc: the tallest reading seen, so a first reading
  off a downed body corrects itself; say what the reading is.
- [x] `:111-146` — the `IsVictimFlat` doc sits above `DisarmVictim`, so LDoc
  attaches it there, and `IsVictimFlat` (`:221`) is undocumented.
  `DisarmVictim`, `RearmVictim` and `WhenVictimStands` have no docs, and the
  first two lack the file's blank lines around blocks. — Move the doc; add
  one line each.
- [x] `:141-143` — "The halfway point is a bisection rather than a tuned
  figure" contradicts `:275-282`, "measured rather than bisected". — Cut
  with the `VictimFlatFraction` ruling.
- [x] `:177-219` — `WatchRecoveryForRearm` is already listed as dead; its
  only callee `WhenVictimStands` is dead with it, and `RisePollMs` and
  `RiseCeilingMs` then serve only `Reaction.lua:964`. `:208` "no longer". —
  Delete both functions; keep the settings for their remaining reader.
- [x] `:221-230` `IsVictimFlat` — returns one value on a nil victim and four
  otherwise; the orphan doc names one. — Document all four; return four
  throughout.
- [x] `:252-254` — "interrupting there is what broke the pose". — Keep the
  constraint: a playing reaction counts as flat whatever the height.
- [x] `:262-287` — "A shortcut stood here", "caught by twice", "Logged from
  play, one guard". — Keep: `BlendRagdoll` means rising on a fall tier and
  down on a ragdoll tier, so height alone decides; then the fraction's
  derivation, per the ruling.
- [x] `:295-306` `WhenVictimRises` — "The rider heard", "A tuned delay stood
  here", "about 0.15 of its standing height to 1.59": both figures are
  meters. The same error is quoted at `Bark.lua:931-934`. — "from about
  0.15 m to 1.59 m"; cut the rest. See the ruling on the early return.
- [x] `:332-334` — the inline comment contradicts the doc and `:262-270`. —
  Follows the ruling.
- [x] `:441-452` `TraceFallLanding` — "the rider has been describing the
  second for hours", the diary's 76 calls. — Follows the diagnostics ruling.
- [x] `:505-514` `WhenVictimIsUp` — "Named for what it measures", "Two
  separate mechanisms were built on the old reading"; a broken line at
  `:507`. On a ragdoll tier it fires as the victim stands, not on the
  get-up. — Keep: fires when the ragdoll state ends, which is the victim
  standing; the state must be seen first.
- [x] `:566` `WhenBodyStops` — "the same thing `ImpactThrow` already means":
  `ImpactThrow` is a log line (`Health.lua:335`), not a function. `:571-576`
  "which the rider saw". — Name `RestStillMeters`; cut the story; keep why
  equality is too strict.
- [x] `:644-649` `FinishRecovery` — skips the rebuild when
  `hcm_combat_injected` is set (`Health.lua:831`, `Impact.lua:234`, `:242`)
  and does not say why. `:660-664` "The delay that used to sit in front of
  this". — One line on the skip; cut the history.
- [x] `:670-675` `TraceRecovery` — "the complaint is about one of them". —
  "to show which phase is long".
- [x] `:743-752` `WatchTurn` — the polearm report, "his". — Follows the
  diagnostics ruling.
- [x] `:869-870`, `:1086-1087` — two blank lines between functions. — One.
- [x] `:877-878`, `:882`, `:884-887` `ReplanIfStranded` — the bucket
  anecdote, "Measured across nine recoveries", "the wait was only ever the
  cost of a weaker signal". — Keep: a replan restarts the daycycle and
  drops a carried prop, so only a victim idle after the get-up is replanned.
- [x] `:946-948`, `:957-973` `ReplanVictim` — the entity-link probe, "every
  send this mod made before this one passed an empty payload", "Measured…
  moved him 0.00 m… 3.94 m". — Keep: `Utils.makeTable` fills the declared
  `reason` and `speed`, and an empty payload is discarded.
- [x] `:1034-1085` `ImpactIsNewContact` — detection logic in the recovery
  module; both callers are `Update.lua:101` and `Rear.lua:1016`. `:1041-1051`
  "Repeats were suppressed by accident before this existed… came straight
  back", "now"; "a rider" for the player; "700 ms" repeats the setting. —
  Move to `Update.lua`; keep: one contact spans several 33 ms ticks, and the
  interval must be shorter than a turn and return.
- [x] `:1088-1185` DynamicRecovery — follows that ruling. If it stays:
  "peasants", the armor range "~0.35… ~1.26" (the curve spans 0.35 to 1.5),
  the `- 400` literal, `npc:IsDead()` where `BarkRecovered` reads health, and
  the missing blank lines. If it goes, `ArmorLerp`'s consumer list loses
  recovery.

### src/HorseCollisionMod/Health.lua

Batch 4: applied. Superseded by batch 2: the throw fields and the rest
watcher. The `ApplyImpactDamage` doc moved onto its function and rewritten
for `ImpactDamageOwnsTheHit`; the three spliced crime-fix blocks collapsed
into one section of that doc. `PredictImpactFatal` now describes the center
of the roll, which the code uses. `lastHitByPlayer` is real
(`sb_switch_hitreactions.xml:584`) and cited. The entry point's
`ImpactDamageDelayMs` field corrected in the same commit. The test-subject
path's missing shield lift is superseded by batch 5, which deletes that
path. Two measurements the diary lacked moved to it. Code findings went to
batch 3, item 7.

- [x] `:1-10` header — names `SuppressAutoCure` and the probe but not the
  damage path, which is most of the file. — One line per part: the probe,
  the auto-cure exemption, the mod's damage and its reclaim, story-character
  protection.
- [x] `:17-27` — no break between `@release` and the `ImpactProbeSamples`
  comment, so it folds into the module doc (the `Armor.lua` pattern). The
  last two lines explain why it is not an LDoc block. — Separate; cut the
  LDoc aside.
- [x] `:29-47` `SuppressAutoCure` — "cleared on a timer"; the option is held
  until health is back over `AutoCureHealthLimit`, rechecked every
  `SuppressAutoCureSec`. — Correct.
- [x] `:65-69` — "reads as the tidier option… sent to a guard in combat, the
  option read back false immediately". — Keep: the brain message can be
  dropped by a busy brain; the direct call writes the table.
- [x] `:101-103` — "doubles as the repair path for a save carrying stuck
  NPCs". The exemption is non-persistent and the cure patch is vanilla's, so
  this is true, but it is release history. — Cut to "reports false on a
  victim who was never held".
- [x] `:160-161`, `:350-351` — two blank lines between functions. — One.
- [x] `:176-178` — "The impulse throws the target, and a change in z…
  separates a fall from anything the collision itself did." — Follows the
  impact-throw probe ruling.
- [x] `:228-234` — "a long investigation turned on being unable to tell them
  apart". — Keep: an impact on someone already down plays nothing and
  costs nothing, and the state separates that from a failed impact.
- [x] `:278-281` — "Samples now run past the cooldown… no longer". — Keep:
  `from=` ties each sample to its impact when two interleave.
- [x] `:296-348` — the rest watcher. Follows the impact-throw probe ruling;
  if kept, `restCeiling = 8000` is an unnamed literal.
- [x] `:352-403` — the `ApplyImpactDamage` doc sits above
  `PredictImpactFatal`'s (`:404`) with no function between, and the
  function is at `:527`; LDoc gives `ApplyImpactDamage` no doc. — Move it
  to `:527`.
- [x] `:352-369` — "on top of what the engine charged" and "the mod adds its
  own charge": with `ImpactDamageOwnsTheHit` (shipped true) the engine's
  charge is given back and the mod's figure is the whole cost. "87 per
  cent… with an error bar" is measurement narrative. — Say: the engine's
  charge is nearly flat against armor, so the mod reclaims it and deals an
  armor-scaled figure of its own; keep the variance paragraph.
- [x] `:383-389` — "A victim the mod kills therefore dies silently, and that
  is a property of this call rather than of the bark system." — Keep the
  constraint; the `BarkDeath` call at `:837` follows the dead-set-path
  ruling.
- [x] `:391-396` — "by the `combat:hit` that `Crime.lua` sends": the hit is
  sent from `Impact.lua:233` when the victim rises, and from `:830` here on
  a death. — Correct.
- [x] `:401` `@tparam playerEnt` — "named as the attacker"; the attacker
  WUID (`:561-567`) feeds only the `attributed=` log field, and `DealDamage`
  takes no attacker (`:377-381`). — Delete `attacker`; describe
  `playerEnt` as the player the death is attributed to when crime is on.
- [x] `:403` `@treturn` — "the damage dealt, or 0"; the function returns the
  rolled figure before the deferred path runs, whether or not it is dealt,
  and `Impact.lua:251` ignores it. — Return nothing.
- [x] `:406-412` `PredictImpactFatal` — "produced words a second and a half
  after… never got a line whatsoever". — Keep: the damage is deferred until
  the body stops, so a line chosen from it arrives late.
- [x] `:414-427` — says the prediction is taken at the **top** of the
  variance roll; the code (`:465-468`) uses the intended figure, the
  center. `4a36c11` chose the center deliberately and its message says so;
  the comment was rewritten the other way in the same commit. "Three of
  seven kills in one ride". — Rewrite for the center: a death line over a
  survivor is the worse error, so the prediction is the average outcome and
  misses some kills near the margin.
- [x] `:429-431` — "The mod reclaims it" holds only with
  `ImpactDamageOwnsTheHit`. — Say so.
- [x] `:473-499` `IsProtectedFromHarm` — "measured taking Bernard from 100
  down to 66", "reading it here reported every victim… six gallops", "has
  not been seen". — Keep: `DealDamage` ignores immortality; `apr` comes from
  `vip_attackprot` and the mod never writes it; `imm` is set on every victim
  by the shield, so it cannot identify anyone; the known gap is an immortal
  character without `apr`. Keep the `rat_bernard`/`villageGuard` sample.
- [x] `:533-536` — "The settings file wins… belong where a player or a test
  can reach them rather than compiled in." This is how `TierValue` works
  for every table. — Cut.
- [x] `:569-599` — "this is the whole of the crime fix", "until now a coin
  toss", "hanging offence" (British), and "A fixed wait, not a poll, and
  deliberately so", which contradicts the `WhenBodyStops` wait at `:888`.
  `:600-612` "the mod's design has always been… What it never did". —
  Collapse with `:675-697` into one block: the engine's trample is
  attributed to the rider and cannot be gated, and `sb_switch_awareness.xml`
  raises `murder` only from an attributed hit; so the victim is shielded
  from contact until the body stops, the engine's charge is reclaimed, and
  the mod's blow is the one that kills. Cite the setting, not 22.7 or 95.
- [x] `:619-631` — "The Cheat mod's immortality works because…". — Keep
  the constraint: an NPC's health cannot be raised past 100 from Lua, so the
  exemption lives here and holds only `tools/dev_subject.lua` spawns.
- [x] `:642-648` — "about 18 a pass", "still died after a handful of runs…
  the rider was charged with murder". — Keep: the engine charges a
  collision too, so health is restored to its value at impact.
- [x] `:642-673` — the test-subject path returns before `deal`, so it never
  calls `LiftCollisionShield`; the shield comes off only at its 6000 ms
  backstop. — Lift it in this path as well.
- [x] `:675-680` — "Nothing is timed here any more, and the local that used
  to hold a delay". `:677-679` says the test subject has "no body to watch";
  the subject is thrown like any victim, and the restore uses a timer only
  because nothing is dealt. — Cut; one line on why the restore is timed.
- [x] `:687-692` — "Nothing here tries to work out whether this impact will
  be lethal any more", beside a function (`PredictImpactFatal`) that does,
  for the bark. — Cut with the collapse above.
- [x] `:710-723` — keep; trim to: restored without the reclaim ceiling,
  because this character is not to be harmed; done after the shield lifts
  and the body stops, when the engine has finished charging.
- [x] `:796-811` — "Observed on a beggar… mourned him", "It has been latent
  all along… Raising the rear's damage made it common". — Keep: a victim
  killed inside an interactive action is left standing in it, so the death
  is handed to a ragdoll, and only then.
- [x] `:816-823` — prose in another register ("don't", unquoted
  identifiers, `'lastHitByPlayer'` in quotes). `lastHitByPlayer` appears
  nowhere else in the repository or the references cited. — Rewrite in the
  file's register; name the link only if a source is found in
  `vanilla_scripts/` or the decompilation, otherwise describe it as the hit
  that attributes the death.
- [x] `:825-829` — `"Tickle"` literal as the strength fallback, repeated
  from the reaction path. — Use the same fallback `Impact.lua` uses, or
  pass `hitStrength` always and drop the chain.
- [x] `:866-867` — `fatal=` recomputes `fatal` (`:812`). `:869` is
  misindented. — Use `fatal`; fix the indent.
- [x] `:874-884` — "measured… victims lost between 6 and 32 health, and six
  of ten were driven onto the clamp". — Keep: the shield has to span the
  whole throw, since the engine charges the body while it moves.
- [x] `:885` — the tier name `"Walk"` as a literal decides whether to wait.
  `WhenBodyStops` already reads a still body on its first poll. — Drop the
  branch, or key it on the tier's reaction rather than its name and say why.
- [x] `HorseCollisionMod.lua:421-424` `@field ImpactDamageDelayMs` —
  describes the wait before charging; the setting only times the test
  subject's restore (the settings file, `:663-665`, says so). — Correct.

### src/HorseCollisionMod/Rider.lua

Batch 4: applied. The header lists the file's parts and says "offense";
`@release` is not added, since batch 1 removed it everywhere.
`IsCombatCollision` has its own doc with its three returns until item 7
reduces them to two. `CameraShakeTrotScale` is gone from the doc in favor of
`CameraShakeByTier`. The perk GUIDs carry their names from
`perk__horsecollisionmod.xml` as comments. The Horsemanship curve
measurement the diary lacked moved to it. Code findings went to batch 3,
item 7.

- [x] `:1-18` header — "every impact at trot or gallop draws horse
  stamina"; the rear and the charge draw it too, the walk does not. The
  file also holds the camera shake, the blur, the bolt and `GrantPerks`.
  "offence" (British). No `@release`, unlike the other modules. — List the
  parts; "offense"; add `@release`.
- [x] `:17-19` — the module block runs straight into `IsCombatCollision`
  with no break, so LDoc attaches the module doc to the function, which has
  none of its own. — Separate; give it a doc naming its three returns.
- [x] `:40-54` — "used to count as well", "Measured… cost 103 stamina", "The
  signal never earned its place… no longer decides anything". — Keep: the
  player's combat state decides; the victim's drawn weapon is logged only,
  because guards patrol armed.
- [x] `:55` — returns `danger` twice; `Impact.lua:51` names the first
  `isCombat` and the third `playerInDanger`, which are the same value. —
  Return two values; carried to `Impact.lua`.
- [x] `:171` — `IsCombatCollision(nil)` runs the armed test on nil and logs
  nothing with the detail. — Harmless in the pcall; if the two-value change
  goes in, add a player-only query or say the npc is optional.
- [x] `:60-66` `ThrowRider` — "which is what earlier builds did". — Cut.
- [x] `:73-82` — the fallbacks exist "in case a different mount type
  differs", and the preference order is iterated with `pairs`. — `ipairs`;
  one line on the order.
- [x] `:108-113` `DrainImpactStamina` — "They did not before… levelling".
  `:123-127` "puts a gallop anywhere between 14.85 and 1452", "The tier
  separation the rider tunes". — Keep the formula, the additive shape and
  the 0.38 worst case (checked: 0.20 + 0.13 + 0.05); cut the history.
- [x] `:138` `@tparam tierName` — lists five tiers by hand. — "an impact
  tier name".
- [x] `:232-235` `DrainHorseStamina` — says `DealDamage` takes
  `(stamina, health, attacker, ...)`; `Health.lua:377-381` says it takes two
  arguments and discards the rest (`C_ScriptBindSoul`). Double spaces
  around the dashes. — Match `Health.lua`; stamina first is the point.
- [x] `:280-283` — "which was measured: two saves in a row at 0.0 stamina".
  — Keep: the seat is rolled only on the impact that empties the horse.
- [x] `:305-317` `ShakeRiderCamera` — "on a gallop impact"; "A trot gets a
  fraction… through `CameraShakeTrotScale`", which does not exist; the
  scale is `CameraShakeByTier`. "Half a ton of horse". `@tparam tierName`
  names three tiers. — Correct to the tier table.
- [x] `:359` — `cfg.LeanSuppressShake ~= false`; the setting is declared, so
  the test is a truthiness check. — `cfg.LeanSuppressShake`.
- [x] `:377-385` — `(cfg.CameraShakeAngle)`, `(cfg.CameraShakeShift)`,
  `(cfg.CameraShakeDurationSec)` in stray parentheses, the residue of
  removed `or` defaults; `g_Deg2Rad or 0.0174532925` is a literal fallback.
  The same at `:480`, `:491-494`, `:559`, `:702`. — Remove the parentheses;
  `math.rad`, or name why the global may be absent.
- [x] `:409-427` `BlurRiderView` — "What was confirmed working in game, by
  setting each and looking". — "These work:" and the table.
- [x] `:437-442`, `:535-538` — the 7.7 m / 4.6 m camera measurement twice.
  — Keep it on `CameraIsFirstPerson` only.
- [x] `:444-453` — "Raising it from 0.9 to 1.3 to 2.0 produced the same
  picture three times", "raising the amount alone stopped helping well
  before it read". — Keep: the amount has no effect past about 1.0, so
  weight comes from the hold and the chroma layer.
- [x] `:469-472` — "They came apart in tuning". — Keep: strength and
  length are separate because a trot keeps the strength and cuts the length.
- [x] `:492` — divides by `RiderBlurSteps`; 0 in the settings file gives an
  infinite interval and no clearing write, leaving the screen blurred,
  which `:455-457` says must never happen. — Floor at 1.
- [x] `:562-595` `BoltHorse` — "### Why this is a chance and not a health
  system" is removal history; "how the 2.0.0-dev1 bug behaved when it
  charged 25 health an impact by mistake". — Cut the first section; keep:
  `hostilePerception` cannot reach the player's horse, whose combat subbrain
  is a bare `Wait`; emptying its health throws the rider and sends it off,
  and the health is restored after `HorseBoltRestoreMs`.
- [x] `:624` — `DealDamage(0, before, nil, true)`: per `Health.lua` the last
  two arguments are discarded. — Two arguments.
- [x] `:691-696` `HorsemanshipScale` — "Two curved shapes do not work, both
  measured in game". — Keep: linear, so each level is worth the same.
- [x] `:707-729` `GrantPerks` — three perk GUIDs as bare literals, copies of
  `perk__horsecollisionmod.xml`; `local player = player or (type(g_localActor)
  == "userdata" and g_localActor)` shadows the global, and nowhere else in
  the mod falls back to `g_localActor`. No `@` tags. The doc says "on
  startup or settings apply"; the callers are `HorseCollisionMod.lua:1709`
  and `:1933`. — Name the perks (a table with the perk names beside the
  ids); use `player` as the rest of the mod does; check with
  `build.ps1` that the ids match the table.
- [x] `:730` — trailing blank line at end of file. — Remove.

### src/HorseCollisionMod/Sound.lua

Batch 4: applied. The unused-tokens finding was settled in batch 2; the
`ImpactTokens` doc lists the four that remain. The trigger vocabulary now
cites `references/audio_triggers.tsv`. `ImpactSoundDistance` applies only
to the trot and gallop (`PlayImpactSound`), so the entry point's field and
Config comment and the settings file, which said every tier, are corrected
in this commit. The horse-proxy corruption claim had no source and is cut
here and from the entry point's `HorseVocal` comment. The `0.5` in
`AwayFromListener` is described as the half meter under which there is no
direction. Code findings went to batch 3, item 7.

- [x] `:3-5` header — "eighty kilograms of person was struck by half a ton
  of horse". — Cut to: vanilla plays nothing for a collision.
- [x] `:15-17` — the vocabulary is "242 distinct `audio_trigger` parameters"
  in the `.animevents`, and "a name outside it does not resolve". The grunts
  (`voices.xml`) and the horse calls (`animals.xml`) are outside it and
  resolve; the vocabulary is the trigger list in
  `references/audio_triggers.tsv`. — Correct and cite the table.
- [x] `:19-31` "Why this is not in the animation data" — "built, tested in
  game, and abandoned", "The rider's verdict… 'way off'". — Keep: a
  fragment's `PlaySound` starts with the reaction, a detection tick and an
  interactive-action call after contact, so the sound lands late.
- [x] `:40-45` `ArmorMaterial` — "the heaviest type a victim is wearing";
  `heaviestType` is the type of the heaviest piece by weight
  (`Armor.lua:210-213`). Same at `:99-100`. — Correct.
- [x] `:149-151` — "A footprint reaching sixty milliseconds of travel
  further forward" is an experiment. — Keep: sounding ahead of contact
  plays near misses and sounds a victim twice.
- [x] `:155-163` — layers are "`{ trigger, delayMs }` pairs", then `:168`
  gives four fields. "`a_o_jump_landing`… A blunt body impact ten
  milliseconds later": only the rear uses the landing, at 0 ms beside its
  body layer, and the gallop settings exclude the hoofstep family. "of
  twenty three candidates" is measurement. — One format line; the reason
  for layers is that no single sample is a horse striking a person.
- [x] `:172-174` — "Two literal trigger names are tokens"; `ImpactTokens`
  has five plus `foley`. — List them from the table, or point at it.
  Follows the unused-tokens ruling.
- [x] `:181` — "names the same sample two or four times"; no tier names one
  four times. — "more than once".
- [x] `:196` `@tparam tierName` — three tiers; the rear and the charge
  arrive too (`:244`). — "an impact tier name". Same at `:375`, `:502`.
- [x] `:198`, `:376`, `:503` `@treturn` — no caller reads the result
  (`Impact.lua:102`, `:198-199`). — Return nothing.
- [x] `:239-241` — "gallop only"; the code plays the crack on the gallop and
  the charge (carried from Settings). — Correct.
- [x] `:246` — `(cfg.ImpactSoundCrackChance)` in stray parentheses. —
  Remove.
- [x] `:260-263` — repeats `:168-170` and `PlayAtDistance`. — Cut to one
  line.
- [x] `:282-296`, `:458-472`, `:564-578` — the same fire-now-or-later
  closure three times. — One helper taking entity, trigger, delay and
  distance.
- [x] `:310-373` `PlayRiderVocal` — "until now the rider was silent",
  "Every earlier attempt", "The rider's verdict on the first build" and the
  quote. — Keep: a named FMOD event cannot answer with a monolog and joins
  no dialog auction; the cooldown stops a group impact from stacking grunts.
- [x] `:313-319` — "three severities… each tier names one"; the tiers use
  `soft` and `heavy`, and `medium` is unused. `:367-369` — "three grunts in
  one window, soft then medium then heavy"; the worst case is two, rank 2
  then 3. — Correct both.
- [x] `:363-365` — "Ranks are the mod's own reading of severity rather than
  config"; they are `RiderVocalRankByTier` in the settings file. — Cut.
- [x] `:414-439` — reimplements `RiderVoiceReady` (`Bark.lua:415-431`)
  inline. `:420-421` credits the rewind guard to "the hit cooldown in
  `Update.lua`"; `Update.lua` has none, and the load handler
  (`HorseCollisionMod.lua:1883`) resets the rear's deadline instead. — Call
  `RiderVoiceReady(rank)`; drop the `Update.lua` reference.
- [x] `:427-428` — "A spoken line stamps rank 3, which nothing outranks";
  lines stamp 4 or 5 (`Bark.lua:436`), grunts reach 3. `RiderVoiceRanks.Grunt
  = 3` duplicates the top of `RiderVocalRankByTier` and nothing reads it;
  `Bark.lua:406` names it `RiderVoiceGrunt`, which does not exist. — "A
  spoken line outranks every grunt"; delete `Grunt` and fix `:406`.
- [x] `:484-499` `PlayHorseVocal` — "corrupts CryEngine's audio proxy
  because the triggers carry `path="horse"` metadata"; no source in the
  diary, the references or the commit (`9d4ef0d`). `:497-499` restates the
  settings. — Cut both; the horse's voice plays on the horse.
- [x] `:504-588` — a copy of `PlayRiderVocal` with its own gate;
  `local longest = cooldown` is a pointless local; column-aligned `=` and no
  blank line before `return` depart from the file. — Share one gated
  player with `PlayRiderVocal`, the gate state passed in.
- [x] `:606-610` — "Measured through speakers placed at verified
  distances". — Keep: only 3D events respond to distance, and
  `hoofsteps_player` ignores position, so `a_o_jump_landing` has a fixed
  level.
- [x] `:624-633` — the proxy is created before `ExecuteAudioTrigger`, and
  its removal timer set after; a throw between them leaks the proxy. — Set
  the timer first.
- [x] `:640-645` `AwayFromListener` — measures from the player, while
  `:188-192` says the listener follows the camera. — Say the player stands
  in for the listener.
- [x] `:668` — `0.5` unnamed. — Name it or give its derivation.
- [x] `:693` — trailing blank line at end of file. — Remove.

### src/HorseCollisionMod/Lean.lua

Batch 4: applied. Superseded by batch 2: the throttle, `force` and their
comment. `@release` is not added (batch 1 removed it everywhere). The
header keeps the shake's rules and moves the measurements to the diary
("Moved from `Lean.lua` comments", with the two fixed bugs). The deadband,
not the poll interval, bounds the hold's wobble: corrected here and in the
entry point's `LeanHoldAmplitude` field. The "remembered direction" comment
now names the expiry refresh as the other thing that turns the camera. The
settings file's `LeanShakeSec` comment corrected. Code findings went to
batch 3, item 7.

- [x] `:1-57` header — no `@release`, unlike the other modules. "What the
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
- [x] `:47-49`, `:283-285` — the residual wobble is "travel speed times the
  poll interval… under a centimeter"; the hold only corrects outside
  `LeanDeadband` (0.06 m), so the deadband sets the wobble. — Say so; the
  entry point's `LeanHoldAmplitude` doc makes the same claim.
- [x] `:83-97`, `:122`, `:162` — `GetPlayerAndHorse` returns `playerEnt`,
  which neither caller uses; `rawget(_G, "player")` here and at `:232`,
  `:295`, `:605`, where the rest of the mod reads `player`. The horse
  lookup `XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())` is
  repeated in `Rear.lua`, `Retaliation.lua` and `Update.lua`. — Return the
  horse only; use `player`; one shared horse lookup, adopted at every site
  listed.
- [x] `:102-118` `LeanOffset` — "that is what made the two sides read
  differently", "Measured", "which is exactly what was reported". The 6 cm
  rest offset is also in the entry point's `LeanDistance` doc. — Keep:
  measured from the horse's centerline, because a world baseline moves with
  the horse and the camera rests about 6 cm left of center, so both sides
  finish the same distance from the head.
- [x] `:159` `@treturn` — "always positive"; it can be 0. — "never
  negative".
- [x] `:179-188`, `:203` — the flattening is explained twice, and the
  first block's opening line and the paragraph under it say the same thing.
  — One comment: pitch is checked first, because the flattened yaw loses
  meaning as the view nears vertical, which is also where the camera is
  nearest the rider's model.
- [x] `:226-230` `FlipLean` — `force` is undocumented. — Add `@tparam`.
- [x] `:238-257` — "Unrated, this floods… at the twenty second lifetime
  those were still occupying the queue", "Measured, 176
  `Animation-queue overflow` errors… ran until the scripts were
  reloaded", "a runaway of ten meters on fast taps"; "three centimeter
  deadband" (it ships at 0.06); no blank line between the two paragraphs at
  `:252-253`. — Keep: each shake holds one of the rider's sixteen animation
  queue entries for its life, and an overflowed queue rejects animations,
  so corrections are throttled; the press, the arrival and the release are
  not, because dropping one leaves the camera traveling. Depends on the
  throttle ruling.
- [x] `:261`, `:268`, `:360`, `:424`, `:451`, `:564` — settings in stray
  parentheses. — Remove.
- [x] `:302` — "the same check the rear uses". — Cut.
- [x] `:315-328` — the home-return comment sits above the angle check,
  while its check is at `:340-344`; it runs straight into the angle
  comment. `:320-325` is the history of a fixed bug ("`now` was read from a
  global that does not exist… stayed dead through a save load"); "the
  pumping bug". — Move the first comment to `:340` as: a re-press before
  the camera is home would take its target from a displaced camera; cut the
  bug history.
- [x] `:391-403` — "clips through Henry's back", "A rider turning slowly
  still gets the full 45 degrees" (copies the setting). — Keep: the return
  takes about 160 ms, so the angle is projected ahead by the turn rate and
  the limit tightens only for a fast turn.
- [x] `:446-450` — "which the rider has seen", "including ones not yet
  found". — Keep: a ceiling bounds any failure in the loop.
- [x] `:464-481` — "Measured across eight deliberate double taps" and the
  log table. — Keep: against a running shake a press reverses rather than
  choosing a side, so the direction is checked and corrected up to twice.
- [x] `:498-511` — "Releases aimed at 0.65 landed at 0.11, -0.05 and
  -0.08". The stated cause, a shake reversing at its period, cannot occur at
  `LeanShakePeriod` 40 with `LeanShakeSec` 1.5; the expiry refresh at
  `:522` is a flip the loop makes without the correction logic. — Keep:
  direction is taken from two samples, never remembered, because the camera
  can reverse without a correction.
- [x] `:518-522` — "to keep the animation queue" is an unfinished sentence;
  `150` is unnamed; two comments run together. — Finish it (the hold is
  renewed before its shake expires and sends the camera home); name the
  margin or derive it from `LeanPollMs`.
- [x] `:544-547` `StopLean` doc and `:562-563` — the 160 ms return twice
  more. — Once, in the doc.
- [x] `:566`, `:571` — `sign or 1`; `sign` is `LeanHeld`, checked non-nil
  at `:549`. — `sign`.
- [x] `:572`, `:574` — `-9` and `-1` stand in for an unreadable offset and
  angle in the log. — Log `none`.
- [x] Carried back to the settings file: `LeanHomeMs` is commented "how
  often the hold is corrected" (it is the wait after a release); `LeanShakeSec`
  "long enough to outlast a held lean" (a hold renews it before expiry).
  Part of the settings lean rewrite.

### src/HorseCollisionMod/Update.lua

Batch 4: applied. Superseded by batch 2: the `ProtectMutt` block and its
"dogs share the generic NPC class" comment. The charge stand-aside comment
now matches the `Rear.lua` pass: `ChargeScoringUntil` is stamped at the
press and `WatchLunge` clears `RearCharging`. `HushVanillaBark` runs for
every human within `HitRadius`; its doc in `Bark.lua` was corrected in this
commit, and its rate was corrected in the `Bark.lua` pass. The horse lookup
goes to the shared helper recorded under `Lean.lua`. Code findings went to
batch 3, item 7.

- [x] `:3`, `:11`, `:204`, `:381` — "ten times a second", "every hundred
  milliseconds", "every 100 ms"; the interval is `TickSeconds`, 0.033
  (`:354` says thirty, which is right). — Name `TickSeconds`, not a rate.
- [x] `:18-20` header — "This file was moved last…". — Cut.
- [x] `:27-28` — `@release` runs straight into `TriggerCollision`'s doc
  with no break, so LDoc merges the two. — Separate.
- [x] `:28-39` `TriggerCollision` doc — "Enforces the per-victim cooldown,
  then dispatches on gait"; it stands out of a charge, scores the tier from
  speed, refuses a repeat contact and hands off to `ResolveImpact`.
  `@tparam table playerEnt` receives `player`. — Correct the summary.
- [x] `:54-70` — the removed readiness wait, "There is no readiness wait
  any more", "What stood here…", the 608 ms stretch. — Cut; if anything,
  one line: every contact lands, and `IsVictimFlat` decides in the
  reaction whether the body can take an animation.
- [x] `:72-90` — "which whiffs on a walking man three times running", "the
  old double hit", "measured at 144 to 256 ms", "which is what a charge
  landing on nobody looked like". `:86-87` says `ChargeForward` clears
  `RearCharging` "the moment the horse stops accelerating"; it clears it
  when speed falls to `RearChargeLungeSpentAt` of the peak
  (`Rear.lua:681-683`). Resolves the carried item. — Keep: `ChargeStrike`
  raises the charge's impacts, so the loop scores nothing until
  `ChargeScoringUntil`, which spans the sweep's `RearChargeStrikeMs`;
  `RearCharging` ends sooner.
- [x] `:97-106` — "which is why it outlived the readiness wait"; `:105`
  repeats `:97-100`. — One comment: one pass is one impact, debounced by
  the gap between contacts.
- [x] `:136-139` — `type(player) == "nil" or (not player)` tests the same
  thing twice. — `not player or not player.human or not player.player`.
- [x] `:145`, `:215`, `:260` — the clock is read three times per tick. —
  Read once at the top.
- [x] `:163-181`, `:407-409` — the horse lookup, twice in this file. — The
  shared horse lookup from the Lean findings.
- [x] `:197-210` — "The rider watched the horse thrown about five meters
  up… nothing in the log had anything to say about it". `:217` `1000`
  unnamed; `:223` `-1` stands in for no impact yet. — Keep: logged when the
  upward speed crosses `HorseAirborneVz`, speed rather than height because
  height off a slope is ordinary. Name the 1000 ms repeat gap; log `none`.
- [x] `:230-231` — two blank lines. — One.
- [x] `:276-279` — "trampling him on every ride is nobody's idea of
  immersion"; "dogs share the generic NPC class" is false. See the
  `ProtectMutt` ruling.
- [x] `:305-311` — the faction fallback that "stood here", "a long run of
  female-specific faults in this mod". — Cut; `:300-303` stands alone.
- [x] `:319-325` — "buried the human misses entirely and a distance gate
  did not help". — Keep: non-humans are not logged, because the player's
  holster and dropped weapons sit permanently inside the sphere.
- [x] `:332-335` — "while they are still in front of the horse"; the call
  runs for every human the broad phase returns, all round the horse within
  `HitRadius`, before the dead and footprint tests. `HushVanillaBark`'s doc
  (`Bark.lua:1233`) says "somebody inside the horse's footprint", and
  `:1201`, `:1210` give the loop as "ten" and "twenty" times a second. —
  Correct both files: anyone within `HitRadius`, ahead of contact.
- [x] `:381-385` `UpdateTimer` — "Each load screen starts a new loop": the
  entry point's load handler (`HorseCollisionMod.lua:1867`) does. — Name it.
- [x] `:397-400` — "Those were separate figures until the impact sound made
  the difference audible… agreed only by accident". — Keep: the interval
  is `TickSeconds`, which the forward sweep also uses.
- [x] `:419` — "CRITICAL ERROR IN UPDATE TIMER" in capitals, unlike every
  other log row. — `UpdateError err=`.
- [x] `:84-89` — "`RearCharging` is cleared by `ChargeForward`… measured
  at 144 to 256 ms"; `WatchLunge` clears it. `ChargeScoringUntil` is
  stamped at the key press, so it covers the rear and about 150 ms of the
  lunge, not the sweep's whole run. — Correct. (Found in the `Rear.lua`
  pass.)

### src/HorseCollisionMod/Marks.lua

Batch 4: applied. The "entity follows the body" advice is cut in line with
the `WhenBodyStops` ruling; the doc now says only that the entity's
`GetVelocity` reports the vertical motion the dust needs. The measured
gallop trace stays as the derivation of the two thresholds. The carried
`Impact.lua` dust finding stays with that file's pass. Code findings went
to batch 3, item 7.

- [x] `:8-12` header — "Both arguments are deltas": `AddDirt` takes one.
  `:9-10` breaks the `actor:AddBlood(zone, n)` code span across lines. —
  "Each amount is a delta"; keep the span on one line.
- [x] `:17` — "a rider who is run down from behind"; the victim. — Correct.
- [x] `:83-84` `MarkVictim` — "from the trot and gallop branches of
  `OnImpact`"; `ResolveImpact` (`Impact.lua:215`) calls it for every tier,
  and the rear and the charge carry figures. `:95` `@tparam tierName`
  names two tiers. — "an impact tier name"; the tier tables decide, and
  the walk has no row.
- [x] `:98`, `:188` `@treturn` — neither caller reads the result
  (`Impact.lua:205`, `:215`), and `ImpactDust` returns true at `:246`
  whether or not dust is ever spawned. — Return nothing.
- [x] `:102`, `:192` — `tierName == "Walk"`; the walk has no row in any of
  the three tier tables, so the lookups already return nil. — Drop the
  special case.
- [x] `:119-121` — `0.75` and `0.5` express "a quarter either way" without
  a name. — Name the jitter.
- [x] `:171` — "one call covers all three tiers"; five tiers, the rear
  branching off. `:187` `@tparam tierName` lists three. — Correct.
- [x] `:216-219` — "since `Update` does not wrap this"; the caller is
  `ResolveImpact`. — Cut the clause; the `pcall` needs no defense.
- [x] `:229` — `cfg.ImpactDustEffectRear or cfg.ImpactDustEffect`; the rear
  effect is declared. — Drop the fallback.
- [x] `:230` — `1.3` unnamed chest height. — Name it.
- [x] `:236` — `INSTANT` in capitals in a log row. — `onContact=true` or
  drop it; the tier already says rear.
- [x] `:276-286` — "All three look reasonable and all three were wrong in
  game", "Frame-by-frame footage caught it". — "These do not report the
  landing:" and the three reasons.
- [x] `:288-290` — "its transform follows the body… Anything asking this
  question again should start there". `Reaction.lua:421-428` says the
  entity does not follow a ragdoll. — Cut the advice; the claim belongs to
  the `WhenBodyStops` ruling, which decides which file is right.
- [x] `:292-294`, `:363-373` — the 0.7 m terrain measurement twice;
  "which is why the dust appeared on some collisions and not others with
  the spawn reporting success every time". — Once, on `GroundUnder`; cut
  the history.
- [x] `:381-383` — `1.0` and `-3.0` unnamed; `table_`. — Name the cast
  height and depth; `results`.
- [x] Carried to `Impact.lua:201-203` — says dust is "Spawned where they are
  struck rather than where they land… dust that follows a body reads as
  smoke"; `ImpactDust` waits for the landing (`DustWhenLanded`), except on
  the rear.

### src/HorseCollisionMod/Fear.lua

Batch 4: applied. `@release` is not added (batch 1 removed it). The
`ProtectMutt` wording follows that ruling: `RearCanHit` admits living
humans. Found in this pass: the two scream override settings the bands
read were never declared, so they are always nil; recorded in batch 3,
item 7. Code findings went there too.

- [x] `:29-31` header — no `@release`. — Add.
- [x] `:72-92` `FrightenBystander` — "Startled, not hurt. One line, at the
  fright, and it is the scream rather than the startle" is a fragment;
  "The moment wanted two… Measured over several rides", "was the weaker
  half of the pair". — Keep: a line sent to an NPC already fleeing is
  accepted and never spoken, so the one line goes out with the stimulus,
  from `NASILI_UTEK` (the `Panic` alias).
- [x] `:127-129` `FearBand` — "a living human who is not Henry's dog";
  follows the `ProtectMutt` ruling.
- [x] `:140`, `:235` — `local playerEnt = player` aliases the global for no
  reason. — Use `player`.
- [x] `:195` — "thirty feet"; the mod measures in meters. — "several
  meters".
- [x] `:221-222` — "normalised". — "normalized".
- [x] `:227` `ChargeFearBand` — returns a count with no `@treturn`. — Add.

### src/HorseCollisionMod/Crime.lua

- [ ] `:3`, `:12` — "offence". — "offense".
- [ ] `:9-13` header — "a harder impact is charged as a worse offence";
  `:108-111` says strength changes nothing about the charge and the fine
  follows the victim's social class. — Take `:108-111` as the fact; cut the
  header sentence.
- [ ] `:20-21` — `@release` runs straight into the `CombatAttackKind`
  comment, so LDoc folds it into the module doc. — Separate.
- [ ] `:28-33` — "for a blunt reason", "which is the better place for it
  anyway". — One line: kept here because LDoc rejects a third annotated
  table in `Enums.lua`.
- [ ] `:50-52` `SendCombatHit` — "why this is worth trying at all", "have
  always had to be played by seizing the actor". — Cut; `:48-50` stands.
- [ ] `:60-62`, `:101-106` — the `Melee` substitution explained twice;
  "Measured across nine runs". — Once: the crime system prosecutes `Melee`,
  `MeleeStealth` and `Bullet` and ignores `Collision` and `Fall`, and
  vanilla rewrites a ridden collision to `Melee` for that reason.
- [ ] `:66` — "the same fault that made `daycycle:restartRequest` look
  inert". — Cut.
- [ ] `:97-100` — "Both overridable, so a single impact can be run at a
  chosen setting without a rebuild… one impact per save load": nothing in
  the function is overridable; residue of a removed test hook, and it runs
  into the next comment. — Delete.
- [ ] `:75`, `:165`, `:256` `@treturn` — no caller reads the result of
  `SendCombatHit` (`Impact.lua:233`, `Health.lua:830`),
  `SendProvocationHit` (`Retaliation.lua:1014`, `:1036`) or
  `SendOffenseRelease` (`Retaliation.lua:301`). — Return nothing.
- [ ] `:81-95`, `:171-185`, `:258-262` — the target id and the player WUID
  are resolved inline in each sender, and again in `Fear.lua:48-52`,
  `:151-155`. — Two helpers, used by both files.
- [ ] `:211-213` `SendOffenseRelease` — "observed doing for twenty-two
  seconds before the rider swung first". — Cut; "never strikes" stands.
- [ ] `:227` — "and that is the whole trick". — "The attacker named is the
  horse".
- [ ] `:239` — "measured against a null control". — Keep the two sample
  rows alone.
- [ ] `:244-247`, `:264-268` — why the horse and not the victim, twice. —
  Once, in the doc.
- [ ] `:255` `@tparam npc` — "who is also named as the attacker"; the horse
  is, and the victim only when there is no horse. — "victim entity".

### src/HorseCollisionMod/Impact.lua

- [ ] `:4` header — "ten times a second"; the interval is `TickSeconds`. —
  Correct.
- [ ] `:5-6` — the rear and the charge "sweep a corridor in front of a
  standing horse"; the rear strikes an arc (`RearReach`, `RearArc`) and the
  charge sweeps a corridor while the horse lunges. — Correct.
- [ ] `:7-8`, `:13-16` — "why the two lived as two whole functions for as
  long as they did", "Written twice, they drifted… for months". — Cut; keep
  `:18-22`.
- [ ] `:10-12` — "the same thirteen steps in the same order"; the list is
  not in code order (the reaction follows the sound) and leaves out the
  shield, the standing height and the auto-cure suppression. — Drop the
  count and the list; the function is the list.
- [ ] `:51`, `:124-127` — three returns where two are the same value;
  "the combined signal… meant he could never be staggered at all".
  Resolves the carried item with the Rider finding: take two returns, and
  keep one line on why the player's danger decides.
- [ ] `:53-56` — "The charge used to probe itself as a minor injury…". —
  Cut.
- [ ] `:58`, `:63` — `or "Tickle"`, `or 0`; `TierValue` falls back to the
  shipped row, which every tier has. — Drop the fallbacks.
- [ ] `:84-86` — "What actually prevents the lockup"; the 40-health
  threshold is restated from `Health.lua`. — "Keeps vanilla's auto-cure
  daycycle from taking a bleeding victim over"; no figure.
- [ ] `:94-101` — "the rider reported impacts landing silently when this
  was moved below", "which is worth remembering". — Keep: the request goes
  out before the body is handed to physics.
- [ ] `:107-118` — "measured across two builds… seven gallops… where three
  such gallops in the older build produced three". — Keep: `Ragdoll` reads
  the victim's animation state, so the reaction runs next to the probe and
  before anything cosmetic.
- [ ] `:118-119`, `:182-183` — comments and code run together without a
  blank line. — Separate.
- [ ] `:146-147` — `-1` stands in for a missing speed. — Log `none`.
- [ ] `:156-157` — two blank lines. — One.
- [ ] `:185-190` — "1500 ms" restates a setting; "two guards in one lunge
  produced two grunts and a kill line over the top of each other". — Keep:
  a charge resolves every victim inside one sweep tick, so the rider's and
  the horse's vocals play once per charge, as the stamina is charged once.
- [ ] `:202-204` — says dust is spawned where the victim is struck; it
  waits for the landing except on the rear (`Marks.lua` `DustWhenLanded`).
  Resolves the carried item. — Correct.
- [ ] `:207-209` — `TraceFallLanding` follows the investigation-diagnostics
  ruling.
- [ ] `:218-223` — past 80 columns; "it perfectly overrides the casual
  recovery dialogue". Resolves the carried item. — Keep: the combat hit and
  the provocation wait until the victim stands, because the combat hit
  makes `sb_switch_hitreactions.xml` broadcast the assault at once.
  `WhenVictimRises` follows the early-return ruling.
- [ ] `:224` — `reason, elapsed` unused. — Drop.
- [ ] `:248-251` — the return value of `ApplyImpactDamage` is ignored;
  resolves the carried item with the Health finding.
- [ ] `:262` — `-- test reload` left at end of file. — Delete.
- [ ] `:200-202` — "Spawned where they are struck rather than where they
  land"; only the rear spawns on contact, every other tier waits for the
  landing (`Marks.lua:208`, `DustWhenLanded`). — Correct. (Found in the
  settings file pass.)

### src/HorseCollisionMod/Log.lua

- [ ] `:1-5` header — "and the speed tier"; `GetSpeedTier` is in
  `Tiers.lua`. "the two log calls"; the file also holds `NameOf`,
  `SpeedTrail`, `ImpactSpeed` and `TickMs`. — Correct the summary.
- [ ] `:15-16` — `@release` runs straight into `TimeMs`'s doc, and LDoc
  folds it into the module: `TimeMs` is missing from
  `docs/api/modules/HorseCollisionMod.Log.html`. The same merge drops
  `TriggerCollision` from the Update page, confirming the Update and Crime
  findings. — Separate.
- [ ] `:9-11`, `:19-21`, `:30-31` — why these are methods, three times. —
  Once, in the header.
- [ ] `:62-88` `RecentPeak` — "The flaw that fixes is real and the hold
  must stay. What it could not do…", the four-row measurement, "what the
  rider experienced as walking into her", the `WatchLunge` readings of
  21.2 to 25.8 m/s; "neighbouring". — Keep: the peak is the larger of each
  neighbouring pair's minimum, so a one-tick kick off a body cannot set it
  while sustained speed and the samples before a deceleration still do;
  `ChargeForward` applies the same rule. "neighboring".
- [ ] `:155-163` `ImpactSpeed` — "narrower than it used to claim",
  "Raising the ceiling from 11.0 to 13.0… changed nothing a rider could
  feel". — Keep: capped against physics spikes, and the speed only picks
  the tier and gives `GetImpactDir` a direction; no force scales by it.
- [ ] `:182` `LogRejection` — "about twenty times a second"; the interval is
  `TickSeconds`. `:197` `1000` unnamed. — Correct; name the interval.
- [ ] `:206-209` — two blank lines, then an orphan doc ("Current time in
  milliseconds", `@treturn`) that LDoc merges into `NameOf`'s. — Delete.
- [ ] `:250` — `0.016` unnamed. — Name it (one frame at 60 Hz).

### src/HorseCollisionMod/Tutorial.lua

- [ ] `:1-6` header — "detailing key controls, standstill requirements,
  stamina drain, and crime consequences" describes the banner text, not
  the file. — "Shows each maneuver's banner once, when it is first
  available."
- [ ] `:12`, `:87`, `:131`, `:192` — `TutorialsShown or {}` four times; the
  first runs when the file loads. — Keep `:12`; drop the rest.
- [ ] `:27`, `:64` `@tparam name` — "etc."; there are three. — Name them.
- [ ] `:65` `force` — no caller passes it. — Remove the parameter and its
  two tests.
- [ ] `:103`, `:119`, `:158` — the 10 s display and the `10500` ms follow-up
  are separate literals. — One named duration; derive the follow-up from
  it.
- [ ] `:115`, `:180`, `:185` — summaries past 80 columns; `:187-190`
  "spammed", "does NOT". — Shorten; plain case.
- [ ] `:126`, `:195` — `rawget(_G, "player")`. — `player`.
- [ ] `:134-138`, `:201-205` — the banner-to-ability table twice, and again
  as the perk ids in `Rider.lua` `GrantPerks`. — One table, beside the
  Rider perk table.
- [ ] `:166-170` — without `RequirePerks` only the rear's banner is shown on
  mount; the charge's and the lean's appear on first use
  (`Rear.lua:260`, `Lean.lua:313`). — Say so in the doc.
- [ ] `:173-183` — `CheckMountTutorials(playerEnt)` ignores its argument, and
  both it and `CheckMenuTutorials` only call `QueueNextTutorial`. — Call
  `QueueNextTutorial` from `Update.lua:160` and
  `HorseCollisionMod.lua:1858`; delete both.
- [ ] Whole file — no blank line after local declarations or before
  `return` and control blocks (`:18-19`, `:76-77`, `:95-96`, `:100-101`,
  `:141-148`, `:156-158`), unlike every other module. — Match the mod.

### src/HorseCollisionMod/Detection.lua

- [ ] `:15-16` — `@release` runs straight into `IsInHorseFootprint`'s doc;
  the function is missing from the generated Detection page. — Separate.
- [ ] `:18-21` — "under a meter wide"; `HorseHalfWidth` is 0.70, a 1.4 m
  footprint. "what makes collisions feel like they reach too far". — Cut
  the figures; the sphere catches people beside and behind the horse.
- [ ] `:29-32`, `:118-119` — the diagnostic string is "the most expensive
  thing in the loop", and `GetEntitiesInSphere` is "the most expensive call
  the mod makes". — Keep the second; the first says only that the string
  is built on request.
- [ ] `:81-84` — "gating it on `LogTelemetry` instead wrote a line for every
  tick". — Keep the first sentence.
- [ ] `:101-102` — two blank lines. — One.
- [ ] `:103-109` `FootprintDetail` — no `@tparam`s. — Add, or refer to
  `IsInHorseFootprint`.
- [ ] `:123-128` `EntitiesNearHorse` — the margin is argued from
  `HorseFrontReach` plus `MaxSweepExtra` (1.40 m); the footprint's far
  corner is 1.57 m out with `HorseHalfWidth`, leaving 0.93 m against the
  0.8 m `SphereCacheTravel`, and the argument ignores the victim's own
  movement over the 150 ms cache life and the 2.35 m vertical allowance,
  which the sphere does not contain. — State the corner, the margin and
  what it assumes.
- [ ] `:137` `@treturn boolean` — the caller (`Update.lua:260`) reads one
  value. — Return the list only.
- [ ] `:200-204` `GetImpactDir` — divides the velocity by `speed`, which is
  the capped impact speed rather than the velocity's own length; the
  comparisons are scale-free, so the division does nothing. — Drop it and
  the `speed` parameter (callers `MarkVictim`, the reaction).

### src/HorseCollisionMod/Enums.lua

Values checked against `vanilla_scripts/Libs/AI/TypeDefinitions.xml`; all
match.

- [ ] `:1` header — "used by the collision reaction calls"; `Crime.lua`
  uses both for the combat hit and the offense release. — "used by the
  messages the mod sends".
- [ ] `:29` — "`Tickle` and `Unpleasant` cost the victim no health"; the
  type definition gives `Exhausting` as no health loss too. — Add it.

### README.md

`lint_docs.py` reports nothing. Every default in the settings table matches
the file except `ThrowByTier`.

- [ ] `:14-16` table — Rear "Higher cost", Charge "Highest cost"; gallop, rear
  and charge all ship 0.20 (`Settings:108-114`). — "Same as a gallop", and
  "Same, once per charge".
- [ ] `:18-20` — "Two moves on two keys" names only `F`; the charge's `R` is
  never given. — Name both keys.
- [ ] `:25-27` — "genuinely is not charged to you". — Cut "genuinely".
- [ ] `:43` — "every stamina cost is multiplied"; `CombatStaminaAdd` adds
  0.13 to the share. — "raised".
- [ ] `:55-61` — "no longer recognizes", "now", "no longer describe", "moved
  to `F`": upgrade history from 4.x. — Keep the first paragraph's
  instruction; move the 4.x note to the changelog if it is not there.
- [ ] `:65-68` — "The ones worth changing are listed below"; see the
  settings-table ruling.
- [ ] `:77-80` — the hard-link explanation for editing the Vortex staging
  copy. — "Edit this copy, not the deployed one under `Mods\`."
- [ ] `:100-101` `Knockback`, `Uplift` — "trot and gallop only"; they reach
  only ragdoll tiers (`Reaction.lua:311-338`), gallop and charge as shipped.
  Same error at `Settings:32`. — "ragdoll tiers only".
- [ ] `:102`, `:118`, `:124`, `:142`, `:145`, `:146`, `:148`, `:161`, `:183`,
  `:188` — rationale in the player's table (why a delay decides murder, why
  the rear dust differs, "a master rides through four or five guards", "the
  half of barding you actually feel", "exists for future investigation"). —
  One sentence each: what the setting does and its unit.
- [ ] `:111` `ThrowByTier` — "Charge 0.7"; the file ships 1.0, and the charge's
  throw is `RearChargeThrow` with `ThrowByTier` as trim. — Correct the figure
  and say it is trim.
- [ ] `:113` `ReleaseAnimationMovement` — "restores the behavior before
  4.0.0". — Say what false does.
- [ ] `:117` `ProtectMutt` — follows the `ProtectMutt` ruling.
- [ ] `:159`, `:167` — the rear keys are "r, q, e, f, y, u, o, h", correct; the
  lean list gives `g` where the action map has `f` (`hcm_lean_*_f`, no `g`). —
  One key list, stated once.
- [ ] `:180-182` — "he" for the victim. — "the victim".
- [ ] `:184` `RetaliationSurrenderHint` — "Surrendering already worked;
  nothing told you so." — Cut.
- [ ] `:190` — "A few detection internals are omitted"; about 120 settings
  above the file's internals line are omitted. — Follows the settings-table
  ruling.
- [ ] `:194-195` — "No vanilla file is replaced"; three declaration files
  are (see `HOW_IT_WORKS.md` `:304-314`). "RPG tables are untouched"; the mod
  ships perk rows under `src/Libs/Tables/rpg/`. — Correct both.
- [ ] `:200-205` Planned — "a rear frightens people the hooves never reach"
  shipped in 5.25.0 (`Fear.lua`). — Keep the line and the polearm; add fear
  to **What happens**.
- [ ] `:207-332` layout — `docs/` omits `ARCHITECTURE_NOTES.md` and
  `BALANCE_AUDIT.md`; the tool descriptions carry purpose clauses ("so a ride
  is not also a search for someone standing usefully") and `legacy/` a
  paragraph of justification. — See the layout ruling; one line per entry.
- [ ] `:342` — `-Version "3.0.0"`; `-Version` defaults to `dev`, and releases
  are versioned by `flow.ps1 land`. — Show the default build.

### docs/HOW_IT_WORKS.md

`lint_docs.py`: 0 errors; 13 warnings (`simply` twice, `which is why`, ten
sentences over 40 words) and 27 eight-word sequences repeated from the
changelog and README. Most of the page is history; the edit is a rewrite in
the present tense against the findings below.

- [ ] `:12-16` — three tiers; the rear and the charge are missing, and the
  gallop is "knocked down harder" where it is a physics throw. — Five rows;
  point at README's table rather than restating it.
- [ ] `:21-23` — "lands about half as far away"; throw distance is not
  measured. — Cut the figure.
- [ ] `:25-29` — "That damage is the game's own rather than the mod's";
  `:37-59` describe the mod's own damage. — State the mod applies it.
- [ ] `:31-35`, `:41-42`, `:51-54`, `:124`, `:155`, `:198-199`, `:223-225`,
  `:231-232`, `:279-302`, `:316-323` — history: what the trample "was
  charged", "two hundred test impacts", "no longer tries", "no longer stand
  up", "now runs out of patience", "It used to borrow a gallop's", "The first
  version", "was narrowed after logging", "Before 3.0.0", "What 3.0.0 does
  instead", the pre-3.0 download size, the `wh_female_fragmentids.xml`
  account. — Cut; the constraint alone stays (shipping a whole database
  breaks another mod's copy).
- [ ] `:44-50` — the charge waits for the body to stop, then "The mod waits a
  moment before charging"; `ImpactDamageDelayMs` is only for a test
  subject (`Settings:663-665`). — Keep the first; cut the second. Same
  error at README `:142`.
- [ ] `:75-80` — "was found clean again after a night had passed"; README
  says the marks wear off once the victim's routine takes them home. — One
  statement, and only what is known.
- [ ] `:76` — "a gallop draws blood"; every knockdown tier does, trot at
  0.07. — "a harder blow draws more blood".
- [ ] `:89-95` — "a moment and a half" for `RiderVocalCooldownMs` 1500. —
  "a second and a half".
- [ ] `:147-150` — "Henry himself says nothing"; `:97-102` gives his kill
  lines, and `RiderBarkKill` ships on. — "Henry speaks only over a body."
- [ ] `:152-176` Losing patience — omits the pull-down and the surrender
  prompt, which README lists. — Add one sentence each.
- [ ] `:181-182` — "R rears and drives forward, Q rears on the spot"; the rear
  on the spot is `F` (`RearOnlyKey`). — Correct.
- [ ] `:185`, `:192` — the rear is "its own kind of blow" and then "scored as
  a trot"; it is its own tier with its own figures and shares only the
  `"fall"` reaction. — "plays the same fall as a trot".
- [ ] `:215` — keys "R, Q, Y, U, O and H"; the list is r, q, e, f, y, u, o,
  h. — Point at README's single key list.
- [ ] `:235-236` — "Nothing is hardcoded"; the source findings list unnamed
  literals (`Log.lua:197`, `:250`, `Tutorial.lua:103-119`). — Cut, or state
  it once the no-magic-numbers findings are applied.
- [ ] `:238` "The three parts" — four follow. — "The parts".
- [ ] `:240` — "Roughly twenty times a second"; `TickSeconds` is 0.033,
  about thirty. — Cite the setting.
- [ ] `:249-250` — the gallop "is given an impulse and the ragdoll takes
  over"; the engine's collision throws the body and the impulse is trim
  (`Reaction.lua:1030-1033`). — Correct.
- [ ] `:252-272`, `:297` — "the stagger is the part that needs new data",
  "four options, one per direction", "30 vanilla options + 4 new"; the mod
  declares 19 tags (stagger, knockdown, fall, get-up, rear, charge, settle). —
  Describe the option set without a count, or with the current one.
- [ ] `:301-302` — database and download sizes. — Cut.
- [ ] `:304-314` — "One small declaration file"; the mod replaces three:
  `kcd_animationControlledTags.xml`, `kcd_horse_fragmentids.xml`,
  `kcd_horse_controllerdefs.xml` (`verify_additive.py:110-114`). README `:194`
  says none. — List all three here; README points at this section.
- [ ] `:327-328` — "checks every claim on this page"; it checks the
  animation layout and the packaged file set. — Say that.

### docs/DEV_LOOP.md

`lint_docs.py`: 0 errors; two sentences over 40 words (`:124-128`, and the
landing block read as prose).

- [ ] Whole file — the page never mentions `flow.ps1 test`, `status`,
  `branch` or `shipping`, which the project uses to reach every state it
  describes; the loop is given as bare `dev_deploy.ps1` calls. — Lead with
  the `flow.ps1` verbs; keep `dev_deploy.ps1` switches as reference beneath.
- [ ] `:33-67` pre-push hook — `git config core.hooksPath .githooks`; there
  is no `.githooks`. The hooks live in `.claude/hooks/`, which is ignored,
  and `core.hooksPath` points there. `STYLE.md` keeps local workflow off
  the remote. — See the hook-section ruling.
- [ ] `:56-60` — the justification for keeping mod-page checks out of the
  build. — One sentence: `publish_nexus.ps1` also checks the page copy.
- [ ] `:72-79` — omits `-NoDevMode`, `-NoLooseScript`, `-ReleaseSettings`,
  `-Force`; `-Force` appears only in prose at `:30`. — Complete the table.
- [ ] `:90-92` — "rewrites all four animation databases"; the build writes
  three `.adb` files. — Drop the count.
- [ ] `:98-105` — the loose-file list omits `Libs\Config\hcm_actionmaps.xml`,
  which `-Reload` deploys (`dev_deploy.ps1:781`). — Add it, with the note
  that it needs a restart.
- [ ] `:111` — "A file one level higher is never read" with no referent. —
  Name the path, or cut.
- [ ] `:124-128` — 58-word sentence; the `dev` world also switches off the
  bolt and `WomenRaiseAlarm`. — List what `[dev]` sets, or point at
  `testworlds.ini`.
- [ ] `:156-160` — "which a regex over the settings file could not do once
  everything per-tier moved into tables". — Cut the clause.
- [ ] `:168-169` — "A world nobody could see is how a setting stays on through
  the next three tests." — Cut.
- [ ] `:190` — omits `--diagnose`, `--file`, `--raw`, `--ride`, `--wait`. —
  Complete the table; `--file` is used at `:235`.
- [ ] `:222` — sample log line says `v3.0.0`. — Use `v<version>`.
- [ ] `:227-235` — "None of that is necessary. It is not necessary."; the
  command block has a broken line (`python tools/dev_survival.lua-style
  setup, then`). — One sentence; two `--file` commands.
- [ ] `:238` — "verified moving day 38 to day 39 instantly". — Cut.
- [ ] `:249-251` — "fourteen places", "thirteen part files"; there are twenty
  part files, and `set_version.py` lists the directory. Same stale count in
  README `:318` and `set_version.py:3-5` ("eleven"). — Drop the counts.
- [ ] `:266-282` — the manual landing sequence restates `flow.ps1 land` and
  argues that `--merged` is safe. — "`flow.ps1 land` does this:" and a
  one-line list of its steps.
- [ ] `:289-297` "Two things that used to bite" — history. — Cut.
- [ ] `:299-310` — the packaged-build checklist never names `flow.ps1
  shipping`, which sets up exactly that state. — Name it; keep the list as
  what it establishes.

### docs/ARCHITECTURE_NOTES.md

Local: excluded through `.git/info/exclude`, so the linter never sees it. Held
to the same standard because it is not the diary.

- [ ] `:14`, `:72`, `:114`, `:123`, `:133`, `:176`, `:266-272`, `:318` — em
  dashes. — Replace.
- [ ] `:47`, `:85-88`, `:152-153`, `:206-213`, `:238-241`, `:302-305` —
  anecdotes: "four hundred log lines", "cost hours", the manifest gate, the
  readiness watcher's 608 ms, how the watcher was caught. — Move to the
  diary; keep each constraint.
- [ ] `:327-361` "Look for the mechanism this project already has" —
  narrative of one fix, with "the rider" at `:358`. — Move to the diary;
  keep the rule (read the neighboring working mechanism before the engine
  API) as one paragraph, and the empty-terminal-clip fragment as a fact.
- [ ] `:63`, `:171`, `:177` — "sixteen files", "roughly a hundred and fifty
  methods"; there are twenty part files and 169 methods. — Drop the counts.
- [ ] `:99-125` "What has moved since this was written" — a changelog inside
  the assessment. — Fold into **Assessment** as current state.
- [ ] `:109-110` — `RetaliationByTier` is "the worked example from this
  document, implemented as written"; it ships as booleans
  (`Settings:386-392`), not the `{ policy, escalates }` rows at `:187-193`,
  and `NoteImpact` (`:196`) does not exist. — Say the table exists as
  booleans and the policy rows are still the target.
- [ ] `:215-253` — "every remaining duration was enumerated"; the lists omit
  `ChargeCooldownMs`, `HorseVocalCooldownMs`, `PhysicsReadyMs`,
  `RagdollDampFloorMs`, `RearChargeWindowMs`, `RecoveryBarkIntervalMs`,
  `RecoveryMinSec`, `RecoveryMaxSec`, `ReleaseMovementGapMs`,
  `RiseCeilingMs`, `RisePollMs`, `TickMs`. — Classify them.
- [ ] `:264`, `:273`, `:307` — "now have been", "now governs", "from now". —
  Timeless.
- [ ] `:278-284` `ImpulseDelayMs` — "an impulse and a set velocity produce the
  same distribution across three rides". — Cut the measurement; keep "the
  engine's collision does the throwing".

### docs/BALANCE_AUDIT.md

Tracked. `lint_docs.py`: 0 errors; nine warnings and eight repeated
sequences. A plan "written before any value is touched" whose stages have
since run; most of it now describes superseded state. See the balance-plan
ruling. If it is kept, these stand:

- [ ] `:7-8`, `:14`, `:53-104`, `:112-148`, `:275-280` — "read out of `src/`
  at 5.26.0", "252 `Config` keys", and the defect tables, each marked
  "Fixed in Stage 0". — Record as done or cut.
- [ ] `:23-28` — system table names `StaminaDrainByTier`,
  `CombatStaminaMultiplier`, `RagdollSpeedCap*`, `RagdollAirDamping*`,
  `RagdollBrakeKeep*`; none exists in `src/`. — Current names.
- [ ] `:159-211` — damage figures 60, 95, 110 and the stamina and blood rows
  predate Rulings 2 and 3 (shipped 75, 111, 118; shares 0.13, 0.20; trot
  blood 0.07). — Current figures or cut.
- [ ] `:34`, `:248`, `:315`, `:359-364`, `:373`, `:408-411`, `:429` — "the
  rider", quoted rulings. — Cut the quotes; state the ruling.
- [ ] `:377-385`, `:494-500` — derivations told as discovery ("The first
  version of this derivation", "stage 2 step 2 proved it in the log"). —
  State the condition; move the account to the diary.
- [ ] `:439` Rear share 0.10; shipped 0.20. `:460` `RearCooldownMs` 2500;
  shipped 7500, with a separate `ChargeCooldownMs` 12500, which `:461-463`
  still proposes. — Correct.
- [ ] `:505-507` Stage 2 step 4 — "the charge's throw distance, reported as
  too far"; the charge has its own throw (`RearChargeThrow`). — Update or cut.
- [ ] `:515-519` Stage 3 — "Give `Fear.lua` the tier-table shape"; `:225-232`
  resolved against it. `ROADMAP.md` item 2 is already corrected. — Cut.

### docs/ENGINE_BINDS.md

`lint_docs.py`: 0 errors; five warnings. The tables are extracted
reference; the findings are in the prose and the markers.

- [ ] `:5-7` — "A name here has not been called unless it is marked", and
  the dagger marks "Entries this mod calls". The daggers are wrong both
  ways: `CanHuntAttack`, `CanStealthKill`, `CanStealthKnockout` carry one
  and nothing in `src/` calls them; `RequestHorsePullDown`, `AddBlood`,
  `AddDirt`, `SetViewShake`, `RagDollize`, `HolsterWeapon`, `IsWeaponDrawn`
  and `GetCenterOfMassPos` are called and carry none. — Regenerate the marks
  from a grep of `src/`; one meaning for the dagger.
- [ ] `:744-785` "Actor and human methods vanilla uses" — "Already used by
  this mod" names `SetPhysicalizationProfile`, `SetHealth`, `ForceDismount`,
  none called in `src/`; "Untried" names `AddBlood`, `AddDirt`,
  `SetViewShake`, `CanHorsePullDown`, `RequestHorsePullDown`,
  `IsWeaponDrawn`, all shipped; "the cosmetic roadmap item" and "never
  considered" have shipped. — Fold into the dagger; delete the section's
  status claims.
- [ ] `:787-804` pull-down — "Whether an NPC can be the `user` … is
  untested"; the retaliation pull-down ships on it. — State that it works
  and what gates it.
- [ ] `:806-820` — "The roadmap item about striking a heavy target rearing
  the horse" has no roadmap entry. — Cut the sentence.
- [ ] `:822-827`, `:855-860` — "The lists above were gathered by reading
  vanilla scripts…", and `SetVelocity` "matters most": `Knockback` "has
  never meant anything", "50 was measured as indistinguishable", "600 threw
  a villager 27 meters". Narrative, and it contradicts the settled design
  (the engine's collision throws; `Knockback` is trim). — Cut; list
  `SetVelocity` without advocacy.
- [ ] `:860-861` — "the opposite of what this project recorded". — Cut.
- [ ] `:895-896` — "`human:HolsterWeapon()` is the clean answer to forcing
  an unarmed brawl"; the mod calls it. — Mark it used; cut the claim.
- [ ] `:617`, `:737` — "which is why". `:694` 42 words. — Rephrase.
- [ ] `:614-623` — "43 entry points out of 43 tried" and the Cheat mod's
  author credited as the source. — Keep the source as a citation; cut the
  tally.
- [ ] `:630` — `3,319,760 read at day 38`. — Cut the sample.

### docs/TECHNICAL_DETAILS.md

`lint_docs.py`: 0 errors; 25 warnings (four `which is why`, 21 sentences over
40 words) and 22 repeated sequences. The reference content is sound; the
defects are history mixed into it and sections describing removed code.

**History to cut** (keep the constraint each one supports):

- [ ] `:80-82`, `:110-114`, `:138-156`, `:331-334`, `:405-413`, `:438-452`,
  `:465-475`, `:500-504`, `:528-532`, `:573-576`, `:634`, `:644-650`,
  `:713-723`, `:753-754`, `:814-821`, `:830-832`, `:857-858`, `:906-908`,
  `:970-973`, `:979-980`, `:986`, `:1047-1069`, `:1083-1084`, `:1088-1095`,
  `:1118-1149`, `:1195`, `:1304-1305`, `:1357-1358`, `:1420-1421`,
  `:1463-1464`, `:1487-1491`, `:1519-1524`, `:1553-1554`, `:1559-1562`,
  `:1578-1589`, `:1593-1597`, `:1606-1607`, `:1636-1638`, `:1647-1662`. —
  Each is how something was found, what it used to be, or a closing lesson
  ("The general lesson is", "cost seven attempts", "the rider described the
  victims as bricks", "A player reported it after 90 hours"). Move the
  accounts the diary lacks; cut the rest.

**Wrong or stale:**

- [ ] `:117-118`, `:1195` — "the one vanilla file the mod still replaces",
  "without replacing a vanilla file"; three are replaced
  (`verify_additive.py:110-114`). — Name all three.
- [ ] `:119-120`, `:1231`, `:1235` — the mod's options are "standing hit
  reactions", "vanilla's 30 options + this mod's 4", "vanilla's 16 FragTags +
  this mod's 4"; the mod declares 19 tags across stagger, knockdown, fall,
  get-up, rear, charge and settle. — Describe the set.
- [ ] `:182-216` — "thirteen part files", a load list of thirteen and a table
  of thirteen; the entry point loads twenty (`Tiers`, `Bark`, `Lean`,
  `Rear`, `Fear`, `Impact`, `Tutorial` missing). `Rider.lua` holds "the combat
  multiplier"; it is an additive surcharge. — Drop the count and the copied
  load list; complete the table.
- [ ] `:255` — ` - ` used as a dash; `:924`, `:970` `--`. — Rephrase.
- [ ] `:261-262` — "reloads only `Scripts/Startup/HorseCollisionMod.lua`";
  `--reload` runs the settings file first (`DEV_LOOP.md:210`). — Correct.
- [ ] `:376-383` — plateaus give a trot at 6.38 to 7.03 and a gallop from
  9.18, then "the gap between 8.03 and 8.84 m/s is empty". The two
  measurements disagree. — One set of plateaus, as `probe_gait_speed.lua`
  last reported.
- [ ] `:357-363` — the cache margin is `HorseFrontReach` plus `MaxSweepExtra`
  and omits the footprint's corner; same defect as `Detection.lua`
  `:123-128`. — Apply that finding here.
- [ ] `:428` — "tested ten times a second"; `TickSeconds` is 0.033. — "every
  tick".
- [ ] `:494` `RagdollSpeedSoftCap` — no such setting; the cap is per tier in
  `ThrowProfileByTier`. — Name it.
- [ ] `:556-557` — "by the rider's ruling". — Cut.
- [ ] `:679-683` against `:1544-1548` — refused "only while the victim is
  flat" (`IsVictimFlat`), and later "a victim already in
  `AnimationControlled` or `BlendRagdoll` is not given a second action". —
  Keep the first; correct the second.
- [ ] `:830` and `Settings:1019-1020` — `HitCooldownMs` does not exist; the
  per-victim interval is `HitMinIntervalMs`. — Correct both.
- [ ] `:916-920` — two events "may be worth adding". `:947-949` — death
  sounds "Not yet implemented; the mechanism is proven". — Roadmap
  material; move to `ROADMAP.md` if still wanted.
- [ ] `:871` — "line 3610277 of the decompilation". — Name the function.
- [ ] `:1100` `WhenRagdollResolves` — no such function. — Cut the bullet or
  name the current one.
- [ ] `:1139-1144` — a gallop "deals `95 * …`" and survives seven times in
  ten; shipped figure is 111. — Cut with the section.
- [ ] `:1227-1236` layout — "Seven files, all named `hcm_*`", including
  `hcm_<set>_fragmentids.xml`, `hcm_<set>_controllerdefs.xml` and
  `hcm_animationControlledTags.xml`. The build ships
  `kcd_animationControlledTags.xml` under vanilla's name, no human fragment
  ids or controller defs, and a horse database with `kcd_horse_*`
  declarations. — Rewrite from the build's file list.
- [ ] `:1263-1267` requirement 4 — "`ActionController` must be redirected as
  well"; `:1309-1312`, the entry point (`HorseCollisionMod.lua:1777`) and
  `verify_additive.py` claim 7 all say it stays on vanilla. — Delete
  requirement 4; "The four requirements" becomes three.
- [ ] `:1387-1402` — the watcher polls "once a second" and ends as
  `natural`, `runaway` or `ceiling` on `RetaliationFleeSpeed`,
  `RetaliationFleeIgnoreRange` and `RetaliationFleeSamples`; none of the
  three settings exists, and the endings in `Retaliation.lua` are
  `settled` and `ceiling`. — Rewrite from `WatchRetaliation`.
- [ ] `:1468-1477` against `:1499-1511` — the charge is `relaxed_rearing` cut
  at 0.8 s into `relaxed_gallop_jump`, then the fragment "rears in place",
  cut at 1.0 s into `relaxed_idle_jump_land`, with travel from an impulse. —
  Keep the second; cut the first.
- [ ] `:1479-1480` — "`RearCharging` forces it to a gallop"; the loop stands
  out for `ChargeScoringUntil` and scores nothing during a charge
  (`Update.lua:85-92`). — Correct.
- [ ] `:1574-1575` — `RearChargeVictimLockMs` is `VictimLockMsByTier.Charge`;
  the charge's throw is `RearChargeThrow`, not "throw scalar". — Correct.
- [ ] `:1688` — "the same mechanism third-party perk mods use"; the mod's own
  four `rpg/*__horsecollisionmod.xml` tables use it. — Say so; README
  `:194` depends on it.

### build.ps1

The checks are sound; the defects are history in the comments and one stale
instruction.

**History to cut** (keep the constraint each one supports):

- [ ] `:10-13` `-Development` — "That cost a working session, and the fix
  belongs here rather than in a habit of bumping the version by hand". — Keep
  "release checks describe a release; a development deploy is not one".
- [ ] `:159-162` — "was one 2,558-line file and was split across ten part
  files", and how the split "would be undone". Twenty part files ship. — Cut;
  keep `:164-168`, the rule and what the entry point owns.
- [ ] `:253-256` — "has reached this repository four times: it broke
  dev_deploy.ps1's build path and corrupted two documented commands. Cheaper
  to fail the build than to keep noticing it by hand." — Keep the mechanism
  (`\b`, `\v` written by an escaping tool); cut the tally.
- [ ] `:312-315` — "which is how twelve files were bumped one at a time". —
  Keep "reported together; `set_version.py` fixes all of them".
- [ ] `:465-472` — "which put this mod in the resolution path of every human
  animation and broke unrelated ones", and `wh_female_fragmentids.xml` "was in
  this list", "the copy that shipped was the launch one". — State the
  constraint: never ship `wh_female_fragmentids.xml`, because a copy
  overrides the patched file and drops its fragment ids.
- [ ] `:507-508` — "which is what made this bug so slow to spot". — Cut.
- [ ] `:555-562` — "Same defect as the pak above, and it reached players",
  "which is why manual testing never caught it". — "Built entry by entry for
  the same reason as the pak; a backslash entry extracts as one file in 7-Zip
  and Vortex."
- [ ] `:576-578` — "and it did once". — Cut.
- [ ] `:598-612` archive — "which matters more than it first appears", "the
  one thing worse than a full directory". — Keep the rule: move, never
  delete, because a tagged release cannot be rebuilt; keep the two names.

**Wrong or stale:**

- [ ] `:454-459` — "the additive layout, which claims no vanilla filename"
  and "Any file under a vanilla name is a bug"; `:462-464` and the list ship
  three vanilla-named files. — "No vanilla filename beyond the three
  declaration files below."
- [ ] `:426` — "Check the game path at the top of it"; `build_adb.py`
  resolves the game from `--game-root`, `KCD_PATH`, then the Steam
  libraries (`:57-64`). — "Check that the game install resolves."
- [ ] `:282-284` — "-dev and -diag builds skip every check below"; so does
  `-Development` at a plain version (`:285`). — Name both.
- [ ] The build does not stop on a PowerShell error: a failed pak step still
  printed "Successfully built" over a broken zip. — Set
  `$ErrorActionPreference = "Stop"` at the top, then confirm a clean build
  still passes. Batch 5.
- [ ] `:249`, `:503` — comment block runs straight on from the closing brace
  with no blank line, unlike every other section. `:632-633` trailing blank
  lines. — Format.

### tools/dev_deploy.ps1

Sound mechanics; the comments carry most of the project's deploy history, and
four of them describe behavior that does not exist.

**History to cut** (keep the constraint each one supports):

- [ ] `:157-165` — "That happened with wh_female_fragmentids.xml…". — Keep
  `:157-160`: a withdrawn loose file goes on overriding vanilla.
- [ ] `:193-201` `log_SpamDelay` — two comments that disagree: the first
  says the delay leaves the mod's telemetry alone, the second why development
  wants none; "was half of every line written to kcd.log". — One comment:
  development keeps every repeat, because the overflow message differs only
  by a pointer.
- [ ] `:209-212` — "hunted across about 130 impacts … on the rider's console
  the whole time". — Cut.
- [ ] `:323-327` — "that is how a mod folder was lost rather than parked". —
  Keep the half-parked failure; cut the account.
- [ ] `:342-345` — "truncating the manifest on the second run orphaned the 31
  items". — "Appended, because the park is rerun after a refusal."
- [ ] `:356-363` — "the ten part files were added when the Lua was split",
  `HorseCollisionMod_ItemData.lua` "left behind by every list written since".
  — Keep "matched by location, not by a list, because one surviving loose
  file masks the pak".
- [ ] `:484-487` — "a restore that removed the whole tree destroyed a folder
  of parked scripts". — Keep "things are put there by hand".
- [ ] `:602-606` — "This used to name `Libs\Config` alone … simply absent
  from the running game". — Cut.
- [ ] `:633-638` — "That happened with -ScriptOnly … two test rides were
  spent". — Keep `:640-642`.
- [ ] `:662-665` — "Every installed file now matches … nothing left to
  normalize away". — Cut; the check needs no comment.
- [ ] `:778-780` — "a lean was added on two new keys … reported as doing
  nothing". — Cut.
- [ ] `:924-930` — "This used to refuse outright … indistinguishable from a
  crash and cost several rides", "the rider". — Cut.
- [ ] `:1074-1077` — "The `sys_DevMode = 1` line in system.cfg does nothing:
  querying it … answers Unknown command". The `STYLE.md` rejected-example
  table names this sentence. — Keep "Without -devmode the console refuses
  `VF_CHEAT` commands, `lua_reload_script` among them."

**Wrong or stale:**

- [ ] `:12` usage — `-Crime` "keep riding people down a crime"; no such
  parameter. `-NoDevMode`, `-NoLooseScript`, `-ScriptOnly`, `-AnimOnly`,
  `-ReleaseSettings` and `-Force` are missing. — Rewrite the usage from
  `param`.
- [ ] `:366-367` — "Two vanilla file names are listed explicitly"; the list
  holds four, and duplicates `$claimedVanillaAdb` (`:166-171`). — Use
  `$claimedVanillaAdb`; drop the count.
- [ ] `:516-535` — the doc for `Sync-LooseFiles` (copies, returns which
  halves were written) sits above `Get-LooseFileMap`, run together with that
  function's own doc. — Move `:516-528` above `Sync-LooseFiles` (`:727`).
- [ ] `:617` — `TrimStart('')` trims nothing (the leading `\` survives);
  works only because `Join-Path` tolerates it. — `TrimStart('\')`.
- [ ] `:747-750` — "build.ps1 regenerates every animation database on each
  run"; it runs `build_adb.py` only when `hcm_male_database.adb` is missing
  (`build.ps1:422`). — "A regeneration rewrites every database whether or
  not the bytes moved."
- [ ] `:801-803` — "build.ps1 rejects a release that ships CollisionIsCrime
  = false"; nothing checks `CollisionIsCrime`. The real reason is that the
  settings file ships. — Say that.
- [ ] `:932-934` — "The pak case is still real, so the refusal is kept for
  it"; there is no refusal, only the warning below. A full deploy with the
  game running then removes `$devDir` (`:971-973`), whose pak the engine
  holds open. — Correct the comment; see the ruling.
- [ ] `:1034-1037` — "The check below says so"; the check below is
  `Test-InstalledFiles`, which compares hashes. `sys_PakPriority` is checked
  by `Assert-DevEnvironment` (`:507-511`). — Point at that.
- [ ] `:1084-1088` — "there are two user.cfg files in this install"; a
  single machine's layout. — "The engine resolves `user.cfg` relative to
  the working directory."
- [ ] `:902` — `--` as a dash. — Rephrase.
- [ ] `:1091-1096` — two branches differing only in the argument string. —
  One call.
- [ ] `:166-171` — four-space indentation in a tab-indented file. — Tabs.

### tools/build_adb.py

The generator is correct; its module docstring and several constant comments
describe the layout before `wh_female_fragmentids.xml` was withdrawn, and two
comments contradict the values beside them.

**Wrong or stale:**

- [ ] `:9-29` docstring — "Four files are generated now" and lists three;
  one is `wh_female_fragmentids.xml`, which is no longer generated (`:785`).
  Three are generated: the two parent databases and
  `kcd_animationControlledTags.xml`. "vanilla's 16 FragTags plus this mod's
  4"; the file adds 19 (17 reactions, 2 horse). "The last two keep vanilla's
  names"; one does. "Before 2.1.0" is history. — Rewrite from what
  `write_additive` writes.
- [ ] `:4` "Vanilla ships 30 options" against `:324` "29 of the 32
  options". — One figure, from the patched database.
- [ ] `:170-171` — orphaned comment ("The subTagDef … with four tags
  added") above `HORSE_TAGS`; it describes `TAGS_ENTRY`. — Move it to
  `TAGS_ENTRY`; drop the count.
- [ ] `:185-193` `GENDERS` — "All three are read only" over four keys;
  `ids` and `ctrl` described as "copied", which nothing does. `ids` and
  `tags` are referenced by the parent's `FragDef`/`TagDef`; `ctrl` is read
  by nothing. — Describe `db`, `ids`, `tags`; delete `ctrl`.
- [ ] `:265-271` — "the settle layer … is left disabled and recovery is
  driven from Lua"; every `hcm_fall_` option carries the settle layer
  (`FALL_SETTLE_AT`, `settle_for` `:644-651`). — Cut the paragraph; the fall
  tier's handover is documented at `:414`.
- [ ] `:277-291` — the get-up comment ("The recovery half of the
  knockdown") sits above `hcm_settle`, with the settle comment run on after
  it. — Put each above its own entries.
- [ ] `:389-392` — "at zero the clip plays in a flat plane and a body on a
  slope is buried", above `MCM_ZMOVE = 0`, run together with the
  `MCM_DECLARE` comment. — Split; state why `ZMove` ships 0 when the
  comment names 0 as the failure, or cut the claim.
- [ ] `:443-463` `FALL_SETTLE_AT` — the head-stop derivation and "Both now
  carry their measured landing"; male left and right ship 2.80 and 2.08, the
  clip-pose figures `bcd2c31` restored because a head-stop handover gives
  physics a half-posed body. — Replace with that derivation; keep the
  clip-length table.
- [ ] `:653`, `:841` — `hcm_pb_` prefix; no option carries it. — Delete.
- [ ] `:728` `write_shared_tags` — "Adds the stagger FragTags"; it adds
  every reaction tag and the horse tags. — Correct.
- [ ] `:559`, `:573` — "Normalises", "normalised". — American spelling.
- [ ] `:566` — em dash. — Rephrase.
- [ ] `:322`, `:877`, `:927` — one blank line between top-level
  definitions. — Two.

**History to cut** (keep the constraint each one supports):

- [ ] `:210-217` — `hcm_shove_*` "existed briefly … Add them back here when
  the trot tier moves off the physics ragdoll". — Cut.
- [ ] `:222-223`, `:229` — "since 2.0.0", "Trot, replacing the physics
  ragdoll"; trot ships `fall`, and `knockdown` is a selectable style no
  tier uses. — "Knockdown: an animated fall and get-up."
- [ ] `:329-334` — "An earlier value of None was chosen by matching…". —
  Keep the collider reason.
- [ ] `:355-359` — "the physics knockdown the trot tier moved away from". —
  Cut.
- [ ] `:386` — "False restores the build before this." — Cut.
- [ ] `:465-469` — "Handover timing was tested against it". — Cut.
- [ ] `:532-538` — "a player reported being locked in place picking a herb
  as Theresa". — Keep "the base pak is the launch game; patches replace whole
  files".
- [ ] `:566-567` — "It happened during this fix: the first version of the
  resolver silently picked 1.7.1b." — Cut.
- [ ] `:640-642` — "which is what the knockdown tier did from Lua with a
  timer". — Cut.
- [ ] `:732-744` — "An earlier layout did that, and unrelated animations
  stopped playing: the beggar's kneeling…". — Keep "copies of the id and
  controller files would sit in the resolution path of every human
  fragment".
- [ ] `:760-764` — "That has happened … seventy-seven rears that worked,
  then seventeen". — Keep "regenerating without them deletes them, and an
  unresolvable fragment is not an error".
- [ ] `:785-811` — the account of `wh_female_fragmentids.xml`. — Two
  sentences: it is not generated because patch 1.9 declares the fragment,
  and a copy would override the patched file; `read_vanilla` resolves
  through `Data/patch/` so the same mistake raises.
- [ ] `:907-910` — "This sweep did exactly that to the horse database". —
  Keep "hand-authored files here are not in git".

### tools/dev_console.py

The protocol notes are the value of this file and are sound; history is woven
through them, and two comment blocks sit above the wrong constants.

**Wrong or stale:**

- [ ] `:31-38` usage — omits `--file`, `--ride`, `--anim-reload`,
  `--commands`, `--diagnose`, `--noisy`, `--verbose`, `--quiet`, `--wait`. —
  Rewrite from the parser, or point at `--help`.
- [ ] `:40-42`, `:589-592` — "Setup, once, in the game's system.cfg";
  `dev_deploy.ps1 -SetDevEnvironment` writes it. — Name the command.
- [ ] `:134-144` — two orphaned blocks above `MAX_CHUNK_BYTES`: one
  describes `RELOAD_COMMANDS` and says "Both are listed" (only
  `lua_reload_script` is), the other describes `RIDE_SCRIPTS`. — Move each
  above its constant; drop "Both are listed".
- [ ] `:159-163` `GAME_ROOT` — read from `KCD_ROOT`; `dev_deploy.ps1` and
  `build_adb.py` use `KCD_PATH` and resolve Steam libraries. A machine with
  `KCD_PATH` set gets scratch files written into the wrong folder. — Use
  `KCD_PATH`, and share the resolution order.
- [ ] `:517-518` — the echo filter names `log_SpamDelay`, which the setup
  never sends. — Drop it; derive the list from `setup_commands`.
- [ ] `:777` — advises `dev_deploy.ps1 -NoBuild -Launch`; the tooling's
  relaunch is `flow.ps1 test -Launch`, and the advice fires when the game is
  running, where a full deploy hits the running-game ruling. — Name
  `flow.ps1 test -Launch`.
- [ ] `:71`, `:123`, `:253`, `:281` — one blank line between top-level
  definitions; `:415-416` two inside the class. — PEP 8.
- [ ] `:194` — `--` as a dash. — Rephrase.

**History to cut** (keep the constraint each one supports):

- [ ] `:5-15` — "Confirmed against the running game: `MemInfo` executed…",
  "Two limits found the same way", and `sys_DevMode` "is inert: querying it
  answers Unknown command" (the `STYLE.md` rejected example). — State the
  two limits.
- [ ] `:27` — "which is exactly what the first run produced". — Cut.
- [ ] `:67-68` — "That cost one wrong conclusion already." — Cut.
- [ ] `:98-100` — "read off a live session and confirmed". — Cut.
- [ ] `:147-156` — "Found the same way as the two limits above". — Keep the
  measured edge (4200 accepted, 4250 dropped) as the derivation.
- [ ] `:178-181` — "Without this a world change needed a restart, which is
  the opposite of what it exists for". — Cut.
- [ ] `:204-207` — "is the reason mn_reload appeared to do nothing". —
  "`mn_reload` needs it; it resets with the game."
- [ ] `:226-228` — "Verified rather than assumed: … went from 0 to 182". —
  Cut.
- [ ] `:258-262` — "a run that relied on a previous session having set it
  looked like the command had vanished". — Cut.
- [ ] `:282-286` — "Why no log line ever came back on the first working
  session." — "Turns on console output and reads it back."
- [ ] `:329-331` — "that ambiguity has cost several rounds of guessing". —
  Cut.
- [ ] `:412-413` — "An earlier comment credited sys_DevMode". — Cut.
- [ ] `:427-430` — "replying only to requests got a single autocomplete
  entry and then silence … rules out the reply's content". — "The server
  alternates strictly: one reply per packet received."
- [ ] `:471-473` — "That is 4545 entries here". — Cut the count.
- [ ] `:762-764` — "a session was spent probing an unresponsive game". —
  Cut.
- [ ] `:773-776` — "which failed the deploy's reload step". — Keep "stderr
  output fails a PowerShell caller".

### tools/publish_nexus.ps1

The upload flow and its safeguards are sound. One corrupted string, one
comment that contradicts `build.ps1`, and release history in the comments.

**Wrong or stale:**

- [ ] `:516-517` — `releases\notes-$Version.md` was written through an
  escaping tool: `\n` became a line break, so the `-ChangelogOnly` error
  reads "Write releases" / "otes-…". `build.ps1`'s control-character check
  (`:257-278`) excludes LF, so it cannot catch this. — Restore the
  backslash. Extend the check: a line break inside a quoted string whose
  next line starts a path fragment is not detectable in general, so add
  `releases\n`, `tools\n`, `src\n` and similar known-path breaks to the
  linter's patterns instead.
- [ ] `:461-466` — "Compress-Archive stores Windows separators, so the
  release zip does does hold `Data\HorseCollisionMod.pak`. Harmless for the
  outer zip". `build.ps1:555-591` builds the outer zip entry by entry because
  a backslash entry breaks the install, and refuses one. The replace at
  `:467` is then a no-op. — Cut the comment; keep the replace only if an
  older zip must still validate, otherwise delete it.
- [ ] `:454-457` — "its <version> is maintained by hand and can drift";
  `set_version.py` writes it and `build.ps1:298-301` refuses a mismatch. —
  "Checked again against the zip, since `-Zip` can name any file."
- [ ] `:359-363` — game root is `KCD_PATH` or one hardcoded path; the other
  tools also search Steam libraries. — Share the resolution.
- [ ] `:620-621` — "around 190 KB"; the current zip is 239 KB. — Cut the
  figure.
- [ ] `:663` — "Finalising" in output. — "Finalizing" (the endpoint keeps
  its own spelling).
- [ ] `:533-534` — two blank lines. — One.

**History to cut** (keep the constraint each one supports):

- [ ] `:144-145` — "4.2.2 went out with none". — Cut.
- [ ] `:354` — "Version 4.0.0 was published without this check." — Cut.
- [ ] `:418-420` — "which is what happened to 4.2.2". — Keep "found without
  being asked, because the field is optional".
- [ ] `:724-731` — "A changelog posted for 4.2.2 … That was concluded twice
  from the page alone … both were wrong." — Keep "the public changelog page
  lags; its absence is not evidence the call failed".

### tools/pre_release_check.py

The checks are sound. One docstring contradicts its own function, three
regular expressions carry literal tab characters, and release history sits in
the docstrings.

**Wrong or stale:**

- [ ] `:487-488` `check_generated_docs` — "This regenerates into a temporary
  directory and compares"; `:522-531` runs LDoc in place in `docs/api`,
  because `ldoc -d <dir>` fails on this project. — Keep the second; cut the
  first.
- [ ] `:241`, `:250`, `:255` — literal tab characters inside the patterns
  (`[ <TAB>]`, `"<TAB>-- ====="`, `"^<TAB>(\w+)"`), invisible in an editor;
  the shape an escaping tool leaves when it writes `\t`. — Write `\t`.
- [ ] `:16` — `import tempfile`, unused. — Delete.
- [ ] `:88-91` — exempts `2.0.0`, `1.9.7`, `1.1.0`, `3.0.3` as "Semantic
  Versioning itself, and the game's own version" without saying which is
  which. — One named constant per exemption.
- [ ] `:26` — "Each of these has been wrong in this repository." — Cut.

**History to cut** (keep the constraint each one supports):

- [ ] `:195-197` — "The Files tab entry has always been checked; the
  changelog never was … 4.2.2 published with an empty one". — Keep "the
  field is optional on the upload, so nothing else asks for it".
- [ ] `:238-240` — "Matching from column zero collected every heading …
  twenty-nine keys". — Cut.
- [ ] `:361-363` — "That happened: the manifest named 1.9.7 exactly, the
  game shipped 1.9.8". — Cut; `:356-359` states the constraint.
- [ ] `:490-501` — "Commit times were the previous approach …". — Cut.
- [ ] `:514-516` — "raised OSError on the machine that has it installed and
  the check quietly passed. A check that never fires is worse than the one
  it replaced." — Keep "subprocess does not apply `PATHEXT` to a bare name".

- [ ] LDoc never deletes a page whose module it no longer produces, and the
  staleness check compares only the pages it regenerates, so an orphan in
  `docs/api/modules/` passes. — Report files present in `docs/api` that the
  regeneration does not write. Batch 5.

### tools/flow.ps1

The verbs work as documented. Defects: a hardcoded game path the deploy it
calls does not share, a vestigial splat, and people and history in the
comments.

**Wrong or stale:**

- [ ] `:70` — `$gameRoot` is hardcoded; `dev_deploy.ps1` resolves
  `-GameRoot`, `KCD_PATH` and Steam libraries. `Dev-Configured`, `Parked`
  and `Enter-Shipping` read the hardcoded path while the deploy writes to the
  resolved one. — Resolve the same way; one shared resolver for the
  PowerShell tools.
- [ ] `:9-13` usage — omits `world`, `test -Launch` and the world switches'
  pointer. — Add `world`; point at the `param` block for the switches.
- [ ] `:255-258`, `:265-269`, `:277` — "The deploy carries no world switches
  any more … nothing to splat"; `$deployArgs` is always empty and every call
  splats it. — Delete `$deployArgs`; pass `-NoBuild -Launch` directly.
- [ ] `:142-157` — an empty `status` section header, then the world helpers,
  then `Show-Status` after a double blank line. — Put `Show-Status` under
  its header; one blank line.
- [ ] `:338-339` — `$src_changed`, `$diary_changed`; the file is camelCase.
  — Rename.
- [ ] `:192` — "the world is its own file now". — Cut "now".

**History and people to cut** (keep the constraint each one supports):

- [ ] `:5-7` — "every one of them was previously a list of steps". — Cut.
- [ ] `:194-195` — "and the rider has paid for that more than once". — Cut.
- [ ] `:231-232` — "a rider mid-test suddenly has a horse that tires". —
  Keep "a switch persists until `land`".
- [ ] `:263` — "and has cost rides". — Cut.
- [ ] `:272-276` — "Passed as a bare switch in front of a splat it was
  accepted and did nothing … Same family as the splatting defect above";
  the defect above no longer exists. — Cut with the splat.
- [ ] `:454-466` — two comments run together, "a rider wondering why their
  horse never tired", "So the next branch started with crime". — One
  comment: the deploy writes an empty world, then `--reset` removes the
  file, because no file and an empty file mean different things.
- [ ] `:471-473` — "Re-entering here is what left main carrying a branch's
  test values." — Cut.
- [ ] `:480-481` — "The rider had to ask for this three times before it was
  automated". — Cut.

- [ ] Every `flow test` builds at the manifest version with
  `-Development`, so `releases/HorseCollisionMod_v<version>.zip` is
  overwritten by each deploy and is not the released artifact; the
  original v5.31.4 zip was lost this way and only the tag can rebuild it. —
  Deploy builds use a `-dev` version, leaving the release zip alone.
  Batch 5.
- [ ] Every deploy reports every file `updated` and warns that
  `hcm_actionmaps.xml` changed while the game runs, whether or not anything
  changed. — Copy and report only files whose bytes differ. Batch 5.

### tools/verify_additive.py

The checks are right; the wording around claim 1 predates the horse files,
and the section comments number the claims differently from the docstring.

**Wrong or stale:**

- [ ] `:9-10` — "the two small declaration files"; `intended_vanilla`
  (`:111-115`) holds three. (Carried forward from `HOW_IT_WORKS.md`.) —
  "the three declaration files".
- [ ] `:97` heading — "The release overrides no vanilla file"; it claims
  three by design. `README.md:305` repeats it ("proves the release
  overrides no vanilla file"). — "The release claims only the intended
  vanilla names", in both.
- [ ] `:96`, `:188`, `:277`, `:294`, `:302` — section comments number tags
  6, pak hygiene 7 and the redirect 8; the docstring numbers pak hygiene 6
  and the redirect 7, and `TECHNICAL_DETAILS.md` cites "claim 7" for the
  redirect. Tags are not a docstring claim. — Number by the docstring; fold
  the tag check into claim 3.
- [ ] `:309` — `Scripts.pak` is a hardcoded path, not
  `build_adb.GAME_ROOT`. When it is absent, `exposed` is empty and the
  redirect check passes on zero classes. — Use `GAME_ROOT`; fail when the
  pak is missing.
- [ ] `:276-277` — no blank line before the next section comment. — Add one.

**History to cut** (keep the constraint each one supports):

- [ ] `:68-72` — "This script used to read `Animations-part1.pak` directly,
  and so verified the mod against the game as it was in February 2018". —
  "Resolved through the patches, as the game serves it."
- [ ] `:106-110` — "`wh_female_fragmentids.xml` was on this list and failed
  both tests … deleted 103 fragment ids". — Keep the two tests.
- [ ] `:214-218` — "The table it reads was called STAGGERS … this check
  went unrun for long enough that the rename was not noticed." — Keep the
  first sentence.

### tools/version_check.py

- [ ] `:29-33` `NOT_BREAKING` — nothing reads it; the comment says so
  ("no longer excuses anything; it is documentation"). — Delete the
  constant; the changelog marker needs no code.
- [ ] `:115-119` `implied_bump` docstring — lists major, minor, patch and
  omits the rule at `:135-139` that a dropped setting is a minor. — Add it.
- [ ] `:121-128` — "and made ordinary cleanup expensive". — Cut.
- [ ] `:203-207` — prerelease headings "under this project's workflow"
  (`4.0.0-dev.1`); `set_version.py` writes plain versions and the changelog
  holds no prerelease heading. "Matching only a bare x.y.z reported…" is
  history. — "A prerelease heading counts as the release it precedes."
- [ ] `:235-243` — "Comparing against the newest tag made a build of the
  version that had just been tagged fail against itself: 4.6.0 tagged …". —
  Keep `:232-233` and `:242-243`.
- [ ] `:220` — `--release` with no value raises `IndexError`. — Report it.

### tools/set_version.py

- [ ] `:3-6` — "fourteen places … each of the eleven part files"; twenty
  part files carry `@release`. (Carried forward from `DEV_LOOP.md`.) — Drop
  the counts: "the manifest, `HorseCollisionMod.Version`, and the
  `@release` tag in every Lua file".
- [ ] `:8-11` — "because the build reported only the first mismatch it
  found; that half is fixed in `build.ps1`". — Cut.
- [ ] `:127-132` — "That was misdiagnosed as a problem with the tables …
  which was never the cause." — Keep the LDoc failure it prevents.
- [ ] `:164-165` — "That failure was silent and therefore the worst kind". —
  Cut.

### tools/audit_code.py

- [ ] `:14-15`, `:143-146`, `:173-175` — "Each found real drift at 5.26.0",
  "Seventeen of them disagreed … at 5.26.0, among them
  `CameraShakeFrequency or 12`", "`ShieldVictimFromEngineDamage` read
  `false`…". — Keep each check's reason; cut the tallies and examples.
- [ ] `:98` — "reports all eight"; `Tiers.lua` declares nine. — Drop the
  count.
- [ ] `:39-42`, `:272` — `src` and `tools` are relative to the working
  directory, so the script only works from the repository root. — Resolve
  from `__file__`, as the other tools do.
- [ ] `:3` — "judgement". — "judgment".

### tools/testworld.py

- [ ] `:3-16` — "The problem this replaces", the three PowerShell switches
  it replaced, and a quoted, profane remark from the rider. History, a
  person, and a quote, in a tracked file. — Cut entirely; `:18-34` is the
  docstring.
- [ ] `:18` — "How it works now." — Cut the lead-in.
- [ ] `:278-279` — "how a setting stays on through the next three tests". —
  "Printed after any change, so the live world is always visible."

### tools/dev_subject.lua

Accurate; the rationale sections run long.

- [ ] `:23-27` — "seventy-five of the hundred-odd NPCs around a village
  already read 0/0/0". — "`AIMovementAbility` is descriptive; setting it
  does not stop an NPC's routine."
- [ ] `:37-38` — "looks deliberate rather than arbitrary". — Cut.

### tools/nexus_settings_block.py

- [ ] `:5` — "There were 150 missing at the 5.10.0 audit." — Cut.
- [ ] `:92-93` — "which is what the page showed before". — Cut.
- [ ] `:10-11` — `--` as dashes. — Rephrase.
- [ ] `:28-29` — paths relative to the working directory. — Resolve from
  `__file__`.

### Bark research scripts

`bark_lines.py`, `bark_alias.py`, `bark_chain.py`, `henry_impact_lines.py`,
`npc_pain_sets.py`. Offline readers of the shipped dialogue tables. One
correctness bug; the rest is history in the docstrings and duplicated
plumbing.

**Wrong or stale:**

- [ ] `npc_pain_sets.py:91` — `if -1 in gate["timeouts"]`; the timeouts are
  strings read from XML, so a once-only sequence is never reported and a
  set carrying one passes as unconditional. — Compare against `"-1"`.
- [ ] `bark_chain.py:63-65` — `for topic, speaker, txt in B.lines(): pass`
  parses every dialogue line and discards it. `:68` imports `re` inside the
  function. `walk`'s `only_role` and `role_name` are unused. — Delete the
  loop and the unused names; import at the top.
- [ ] `henry_impact_lines.py:6-20` — "Three things have to be true" over a
  list of five; "The third point is the reason this tool exists" means the
  fifth. — "Five conditions"; "The fifth is the reason".
- [ ] `bark_alias.py:153-156` — cites
  `pick-bark-sets-by-line-length-not-just-fit`, an assistant memory file
  that is not in the repository. — State the rule: one long member spoils
  the whole alias, because the dialog system picks the member.
- [ ] `bark_alias.py:49-67` — `_read` duplicated from `bark_lines.py`
  ("Lifted from"). — Import it.
- [ ] `bark_lines.py:34`, `bark_alias.py:44` — `KCD_ROOT`; the build tools
  use `KCD_PATH`. — `KCD_PATH`, as in the `dev_console.py` finding.
- [ ] `bark_alias.py:117` — "labelled". — "labeled".
- [ ] `bark_alias.py:13`, `:15`; `henry_impact_lines.py:11` — `--` as
  dashes. — Rephrase.

**History and people to cut:**

- [ ] `bark_alias.py:3-5`, `:10-20` — "the diary proves it works",
  "The diary recorded the alias route as a dead end … the second of them is
  wrong", "Around 795 aliases had never been seen by this project". — Keep
  "`topic.xml` carries the alias namespace as its `label` column".
- [ ] `henry_impact_lines.py:22-28` — "the rider had to discover that by
  hearing it" and a quoted remark. — Cut.
- [ ] `henry_impact_lines.py:94-95` — "Three of the rider's picks were
  silent for this reason alone". — Cut.
- [ ] `henry_impact_lines.py:62-64`, `:16-17` — "refused every single time
  in testing". — "A two-actor sequence is a conversation; a monolog request
  for one is refused."
- [ ] `npc_pain_sets.py:4-5` — `RANENY_NA_ZEMI` "reads far too strong"; it
  ships as `HurtDown` (`Bark.lua:148`). — Cut the judgment.

### Probe scripts (`tools/probe_*.lua`)

Console diagnostics. Several carry the investigation that produced them as
their header, and three answer questions that are closed (see the ruling).

**Wrong or stale:**

- [ ] `probe_gait_speed.lua:8-9`, `:13`, `:104` — "the four gaits",
  "canter ~15 s", "ride walk, trot, canter, then gallop". The horse has three
  commandable gaits. — Walk, trot, gallop.
- [ ] `probe_gait_speed.lua:3-7` — cites "Stage 2 step 1 of
  docs/BALANCE_AUDIT.md" (proposed for deletion), "the 2.0.0 era", "the
  diary records". — "Samples the mounted horse's speed so each gait's
  plateau can be read against `SpeedWalk`, `SpeedTrot`, `SpeedGallop`."
- [ ] `probe_tables.lua:38` — `info.RowCount`; the field is `LineCount`
  (`dev_subject.lua:149`, `dev_console.py:250`), so the row count prints
  `nil`. — `LineCount`.
- [ ] `probe_camera.lua:40-42` — "The horse's own right vector … Taken from
  the head direction"; the code takes the camera's direction
  (`GetViewCameraDir`). — "The camera's right vector".
- [ ] `probe_bark.lua:21` — "The speaker.s voice". — "speaker's".
- [ ] `probe_bark.lua:103-107`, `:164-165` — "the rider" as the person
  running the probe. — "you".
- [ ] `probe_fall_landing.lua:5`, `probe_recovery_states.lua:16-17` — `--`
  as dashes. — Rephrase.

**History to cut** (keep the constraint each one supports):

- [ ] `probe_api.lua:18-20` — "The counts this found on a 1.9.7 build". —
  Cut.
- [ ] `probe_bark.lua:3-26` — "The project had recorded this as
  impossible … Two faults put it there … Corrected, it works … By ear, Henry
  speaks…", and "a six candidate run asks the rider to hold six
  observations … four lines were lost that way". — Keep `:18-20` (audio is
  the gate, not holding) and "one per run".
- [ ] `probe_bark.lua:52-53` — "which is how the first attempt at this was
  wasted". — Cut.
- [ ] `probe_bark.lua:112-113`, `:34-35` — "of the 1626 souls … 234 are
  horses", "zero of the 5025 souls". — Keep the class filter's reason; cut
  the tallies.
- [ ] `probe_camera.lua:12-14` — "what made a smooth animation look jerky
  earlier in this project". — "Per-sample logging costs frames."
- [ ] `probe_health.lua:10-12` — "This lived in the mod as
  HorseCollisionMod:WatchHealth until 4.9.3". — Cut.

### Development helpers (`tools/dev_*.lua`, `testworlds.ini`)

**Wrong or stale:**

- [ ] `dev_target.lua:107`, `:116-118` — sets `ai_IgnorePlayer 1` and says
  it "keeps the rest of the town from reacting"; `dev_peace.lua:21-27`
  records that this was never shown to do anything and forbids adding it
  without a test. — Delete the cvar and the claim (or see the ruling).
- [ ] `dev_target.lua:5-7` — "a spawned entity has no soul, armour or AI";
  `dev_subject.lua` spawns with a guard soul and is the tool the rest of the
  project uses. "armour" twice. — See the ruling; "armor" if kept.
- [ ] `dev_target.lua:10`, `:41-43` — skips Henry's dog by name, behind a
  class filter that already excludes dogs (the `ProtectMutt` ruling). —
  Delete the name check.
- [ ] `dev_survival.lua:14` — "established by reading them back rather than
  assumed" (a `STYLE.md` rejected form). — Cut the clause.
- [ ] `dev_horse.lua:3-5` — "the earliest save on hand is already level
  5". — "Tests at low Horsemanship need a horse before the prologue grants
  one."

**History and people to cut:**

- [ ] `dev_peace.lua:21-26` — "It was described as the lever that mattered
  … set on every run for several sessions while the rider went on being
  attacked". — Keep "not included: no test has shown it changes anything".
- [ ] `dev_time.lua:5-7` — "A question needing several in-game days was
  therefore abandoned rather than answered." — Cut.
- [ ] `dev_time.lua:14-16` — "the rider reported that 'everything broke'".
  — "A jump can leave the session inconsistent; reload if it does."
- [ ] `dev_fasthorse.lua:3` — "Every measurement this project has ever
  taken was ridden on Pebbles". — "The gait thresholds were measured on one
  horse."
- [ ] `testworlds.ini:16` — "interrupts the rider mid-test". — "interrupts
  a test".

### tools/legacy/

Thirteen scripts from closed investigations. `README.md:309-312` states
they are kept unmaintained. Not audited line by line; see the ruling.

- [ ] Fifteen usage lines across eleven files still name the pre-move path
  (`--file tools/audition_batch.lua`, `python tools/make_audition.py`), so
  the documented command fails. — `tools/legacy/…`, if the directory stays.
- [ ] Nine files say "the rider" and several open with the investigation's
  account ("The question this answers is the rider's", "Everything so far
  inferred this…"). — Falls under the ruling.

### .claude/ (local, untracked)

Hooks, linter and workflow notes. None of it reaches the remote, and none of
it is checked by anything: `.git/info/exclude` excludes `/.claude/`, so
`git ls-files --others --exclude-standard` never lists these files for
`lint_docs.py` or `build.ps1`'s control-character check.

**Wrong or stale:**

- [ ] `RELEASING.md:76` — `releases\file-description` holds a form feed
  (0x0C) where `\f` was; `:116-117` — `HorseCollisionMod\nexus.cred` holds a
  line break where `\n` was. The same escaping defect as
  `publish_nexus.ps1:516`. — Restore both backslashes.
- [ ] `lint_docs.py`, `build.ps1:259` — both enumerate files through git, so
  `.claude/` is never checked. — Have the linter and the control-character
  check also walk `.claude/`.
- [x] `hooks/diary-check.sh:5`, `:86`; `hooks/pre-commit:21`;
  `hooks/pre-push:8` — cite `.agent_instructions.md`, which no longer
  exists; `AGENTS.md` is the instructions file. — Name `AGENTS.md`, or drop
  the citation.
- [ ] `hooks/diary-check.sh:35-36` — watches `src/HorseCollisionMod.lua`
  and four tools; the twenty part files, the settings file and `flow.ps1`
  are not watched, so almost every mod change never raises the reminder. —
  Watch `src/` and `tools/` as `flow.ps1 land` does (`:338`).
- [ ] `hooks/pre-push:15-31`, `HOOKS.md:72-75` — "Four levels" over three,
  and a "Releases" level that adds the mod page on a release version; the
  hook runs `pre_release_check.py --merge` only (`:145-150`), and `release`
  (`:94-100`) is computed and never read. `:22` "not older than the source";
  the check regenerates and compares. — Describe what runs; delete
  `release`.
- [ ] `hooks/pre-merge-commit` — a copy of `pre-commit` without the main
  check, printing "pre-commit:". — `exec` `pre-commit`, which already exempts
  a merge through `MERGE_HEAD`.
- [ ] `hooks/pre-commit:56-60` — parses Lua with `luac` or `luac5.1` only;
  `build.ps1` uses `luajit`. On a machine with only LuaJIT the parse check
  silently does nothing. — Fall back to `luajit -bl`, as
  `dev_console.py:350` does. `:37-38` `python` is set and unused.
- [ ] `RELEASING.md:8-19` — step 1 bumps the version by hand;
  `set_version.py` and `flow.ps1 land` do it. `:40-42` "Thirty-one checks",
  "the two intended declaration files" (three). `:56-63`, `:103-111` —
  shipping test via `-SetPlayEnvironment` and back via
  `-SetDevEnvironment`; the tooling is `flow.ps1 shipping` and
  `flow.ps1 test`, which also park and restore the loose files. — Rewrite
  against `flow.ps1`, and add `verify_additive.py` per its ruling.
- [ ] `RESEARCH_BRIEF.md:3-4`, `:16-21` — "Written after a previous run of
  it lost almost everything"; `:40` points at the flat
  `references/WHGame_Decompiled.c`, where `AGENTS.md` sends engine
  questions to `references/decomp/RESEARCH_GUIDE.md`. — Point at the guide;
  cut the history.

**History to cut** (the existing finding at the top of this section
covers the hooks' tone; these are the specific lines):

- [x] `hooks/diary-check.sh:5-8`, `:26-30`; `hooks/pre-commit:10-11`,
  `:20-23`; `hooks/pre-merge-commit:10-11`; `hooks/pre-push:6-9`, `:76-83`,
  `:119-122`, `:146` ("now"); `hooks/style-check.sh:4-5`; `HOOKS.md:56-57`,
  `:79-83`; `lint_docs.py:30-31`.
- [x] British spelling: `hooks/pre-commit:78` "recognised";
  `hooks/pre-push:24-26` "Behaviour", "behaviour"; `hooks/commit-msg:9`
  "acknowledgement".

**Linter rules to add** (extends the `lint_docs.py` finding above):

- [x] ` -- ` used as a dash inside a comment or paragraph.
- [x] An escape-corrupted path: a control character, or a line ending in a
  known directory name (`releases`, `tools`, `src`) whose next line starts a
  path fragment.
- [x] `the rider`, `no longer`, `used to <verb>`, `now` in the timeless
  sense, and quoted speech (`> "` or `"…" the rider`).

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
