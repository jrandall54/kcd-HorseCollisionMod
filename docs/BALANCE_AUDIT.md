# The balance pass: audit and plan

Written before any value is touched. It answers three questions: what tunable
surfaces the mod actually has, what is wrong with them structurally, and in what
order the tuning session should run so that no number has to be set twice.

Nothing in the mod was changed to produce this. Every figure below was read out
of `src/` at 5.26.0.

---

## 1. What the tuning surface is

252 `Config` keys, every one of them exposed in `HorseCollisionMod_Settings.lua`,
and 21 per-tier tables. Key parity is clean in both directions: no settings key
is rejected at load, and no `Config` key is unread. That part of the architecture
is sound and does not need work.

The tunables that decide how a collision *feels* fall into six systems.

| System | Governing settings | Applied in |
| --- | --- | --- |
| Tier identity | `SpeedWalk`, `SpeedTrot`, `SpeedGallop`, `MaxImpactSpeed`, `ImpactSpeedSamples`, `RearImpactSpeed`, `RearChargeImpactSpeed` | `Tiers.lua:GetSpeedTier`, `Update.lua` |
| Damage to the victim | `ImpactDamageByTier`, `ImpactDamageArmorScale/Curve/Floor/IgnoredArmor`, `ImpactDamageVariance`, `BardingDamageBonus` | `Health.lua`, `Armor.lua` |
| Throw of the body | `Knockback`, `Uplift`, `ThrowByTier`, `LateralImpulse`, `RagdollMass*`, `RagdollBrake*`, `RagdollSpeedCap*`, `RagdollAirDamping*`, `ArmorImpulseExponent` | `Reaction.lua` |
| Recovery | `RecoveryDelayByTier`, `RecoveryArmorScale*`, `RecoveryMin/MaxSec` | `Recovery.lua` |
| Cost to the horse | `StaminaDrainByTier`, `CombatStaminaMultiplier`, `ArmorStaminaExponent`, `BardingStaminaRelief`, `HorsemanshipStamina*` | `Rider.lua` |
| Fear and reaction | `RearFearReach`, `RearChargeFearReach`, the scream priorities | `Fear.lua` |

---

## 2. Defects that must be fixed before any value is set

These are not tuning questions. Each one means a number the rider sets will not
be the number the game uses, and tuning on top of them is how a session chases
its tail.

### 2.1 The eight tier tables exist in three places, and two already disagree

`ImpactDamageByTier`, `StaminaDrainByTier`, `ReactionByTier`, `ThrowByTier`,
`HitStrengthByTier`, `VictimBarkByTier`, `RetaliationByTier` and
`StaminaPerVictimByTier` are each declared in `Tiers.lua`, again in the `Config`
block of `HorseCollisionMod.lua`, and again in the settings file.

`TierValue` reads `Config` first and `self[name]` only as a fallback, and
`ApplySettings` assigns a settings table over `Config[key]` outright rather than
merging into it. So `Tiers.lua`'s copies are not dead: they are the per-tier
floor that makes a *partial* override work, and they are consulted only when a
player overrides one tier and leaves the rest out. In every other case the value
that runs comes from `Config` or from the settings file, and `Tiers.lua` — the
file carrying every derivation and every justification — is never read.

That is what made the drift invisible. Two have already drifted:

| Table | `Tiers.lua` says | `Config` says | Settings ship | Live |
| --- | --- | --- | --- | --- |
| `VictimBarkByTier.Charge` | `"rear"` | `"rear"` | `"collision"` | `"collision"` |
| `RiderVocalByTier` Walk/Trot/Rear | not declared | soft / medium / medium | `""` / soft / soft | settings |

The charge answers with the collision bark set, against the documented intent in
both defaults. `v_henry_hit_medium` is declared, documented, and never plays.

**Fix (done, Stage 0):** the eight copies are gone from the `Config` block, and
`Tiers.lua` binds its own tables into `Config` at its foot. Deleting them without
that binding would have been wrong in the other direction: `ApplySettings`
refuses a key `Config` does not declare, so the settings file's eight tables
would have been rejected at load. Now there is one literal per concern, serving
both roles — `Config[name]` as the whole-table default the settings file
replaces, `self[name]` as the floor under a partial override.

### 2.2 Fifty-four inline `or <number>` fallbacks, seventeen of them stale

Code reads settings as `cfg.Key or <literal>`. Fifty-four of those literals
disagree with the shipped default. Most are a harmless `or 0`, but seventeen are
a different plausible tuning value left behind by an earlier era:

| File | Key | Inline | Shipped |
| --- | --- | --- | --- |
| `Rider.lua:323` | `CameraShakeFrequency` | 12 | 0.05 |
| `Rider.lua:322` | `CameraShakeDurationSec` | 0.2 | 0.5 |
| `Rider.lua:429` | `RiderBlurMs` | 220 | 480 |
| `Rider.lua:427` | `RiderBlurSteps` | 5 | 7 |
| `Rear.lua:852` | `RearChargeStrikeReach` | 3.0 | 1.8 |
| `Rear.lua:853`, `Fear.lua:241` | `RearChargeStrikeWidth` | 1.6 | 0.9 |
| `Rear.lua:890` | `RearChargeImpactSpeed` | 9.0 | 7.5 |
| `Rear.lua:1009` | `RearReach` | 3.0 | 2.5 |
| `Rear.lua:885` | `HorseMaxVerticalDiff` | 2.0 | 2.35 |
| `Rear.lua:883` | `RearChargeStrikeBehind` | 0.5 | 0.2 |
| `Rear.lua:327` | `RearMaxSpeed` | 1.0 | 0.15 |
| `Reaction.lua:930` | `RagdollAirDamping` | 3.0 | 8.0 |
| `Reaction.lua:904` | `RagdollSpeedSoftCapSpan` | 6.0 | 3.0 |
| `Reaction.lua:459` | `RagdollMassArmorExponent` | 1.0 | 3.7 |
| `Retaliation.lua:751` | `SurrenderHintCalmPasses` | 6 | 3 |
| `Bark.lua:701,709` | `BarkCooldownMs` | 6000 | 3000 |
| `Log.lua:263` | `TickSeconds` | 0.1 | 0.033 |

They are dormant only while `Config` is intact. They are also a second, silent
declaration of every one of these numbers, which is the same defect as 2.1 at
statement level.

**Fix (done, Stage 0):** all 168 of them are gone. `Config` is a literal and
`ApplySettings` never writes a nil into it, so the right-hand side was
unreachable in every case. It was also actively wrong for a boolean, where
`cfg.Flag or true` reads `true` when the player set `false`.

### 2.3 Two settings are read but never declared

`Recovery.lua:189-190` reads `RisePollMs` (160) and `RiseCeilingMs` (15000).
Neither existed in `Config`, so `ApplySettings` rejected them and they could not
be tuned at all. **Fixed in Stage 0:** both are declared and exposed.

### 2.4 Three throw settings are inert as shipped

`RagdollMassArmorScaled = false`, so `MassVictim` computes
`wanted = RagdollMass / 1.0 = 80` — the engine's own figure for every human. The
mod polls the body repeatedly to write a value it never changes.
`RagdollMassArmorExponent = 3.7` is dead alongside it.

**Fix:** decide in the sweep whether mass returns as a lever — the roadmap's
position is that unarmored victims sit at their normal mass and the curve scales
*up* from there — or whether the path is removed. It must not stay as a no-op
that looks live.

### 2.5 `Config` and the settings file disagree on two values

`ShieldVictimFromEngineDamage` was `false` in `Config` and `true` in the settings
file; `VictimFlatFraction` was 0.15 and 0.45. The settings file wins, so both
were live at the settings value and the `Config` figures described a build that
no longer exists. **Fixed in Stage 0** by moving the defaults to the shipped
values, which changes no behaviour and makes deleting the line from a settings
file a no-op rather than a silent change.

### 2.6 `GetSpeedTier` lives in `Log.lua`

Tier identity is the mod's central concept and `Tiers.lua` was written to own it.
The function that assigns the tier sat in the logging module. **Moved in Stage
0.**

---

## 3. Inconsistencies the sweep has to rule on

These are design questions, not bugs. Each is a place where the five tiers are
not ordered the same way twice.

### 3.1 The rear is trot-class in six tables and gallop-class in two

Ranked by damage, the severity order is Walk 0 < Trot 18 < Rear 60 < Gallop 95 <
Charge 110. Against that order:

| Table | Walk | Trot | Rear | Gallop | Charge | Ordered? |
| --- | --- | --- | --- | --- | --- | --- |
| `ImpactDamageByTier` | 0 | 18 | 60 | 95 | 110 | the reference |
| `RecoveryDelayByTier` | — | 0.5 | 1.0 | 2.0 | 3.5 | yes |
| `CameraShakeByTier` | — | 0.6 | 0.8 | 1.0 | 1.2 | yes |
| `RiderBlurLengthByTier` | — | 0.3 | 0.4 | 1.0 | 1.1 | yes |
| `StaminaDrainByTier` | 0 | 14 | **12** | 22 | 22 | **rear below trot** |
| `RiderBlurByTier` | — | 0.7 | **0.6** | 1.0 | 1.1 | **rear below trot** |
| `ImpactDustScaleByTier` | — | 0 | **0.6** | 0.09 | 0.10 | **rear 6x gallop** |
| `VictimDirtByTier` | — | 0.35 | 0.35 | 0.60 | 0.60 | rear = trot |
| `VictimBloodByTier` | — | 0.15 | 0.15 | 0.45 | 0.45 | rear = trot |
| `HitStrengthByTier` | Tickle | Minor | Minor | Major | Major | rear = trot |
| `ReactionByTier` | stagger | fall | fall | ragdoll | ragdoll | rear = trot |
| `HorseVocalRankByTier` | 1 | 2 | 2 | 3 | 3 | rear = trot |

`ReactionByTier` documents the rear as trot-class deliberately, and that is a
sound ruling about what the body does. But damage then puts the rear at 3.3x a
trot and two thirds of a gallop, which is the opposite ruling about what the blow
is worth. **Both cannot be right, and the sweep must pick one.** Everything in
the table above follows from the answer.

The dust figure is a separate question: the rear uses a different effect
(`arrow_soil` against `explosion_dust`), so 0.6 and 0.09 are not comparable
scales. It needs judging by eye, not by number.

### 3.2 The charge is scored slower than a gallop and hits harder

`RearChargeImpactSpeed` is 7.5, below `SpeedGallop`'s 8.5, yet the charge deals
110 against a gallop's 95. Either the charge's scored speed is wrong or the
damage is not derived from speed at all. Related: `RearImpactSpeed` is 6.0, a
trot and a half, for a blow worth 60.

### 3.3 Damage is flat within a tier

A gallop impact at 8.6 m/s and one at 11.0 m/s both deal 95. Tier thresholds
decide everything and speed inside the tier decides nothing. That is a defensible
design, but it is the reason the tier figures cannot be derived from physics and
have to be picked. **This is the largest single decision in the sweep**, and it
is question 1 in section 5.

For reference, if damage were made proportional to kinetic energy and normalised
so that the measured gallop figure of 95 is preserved, the other tiers land at:

| Tier | Scored speed | Energy-derived | Shipped |
| --- | --- | --- | --- |
| Walk | 1.8 | 4.3 | 0 (deliberate) |
| Trot | 4.5 | 26.6 | 18 |
| Rear | 6.0 | 47.3 | 60 |
| Gallop | 8.5 | 95 | 95 |
| Charge | 7.5 | 74.0 | 110 |

Walk must stay 0 whatever is decided: `wounds` is derived from
`ImpactDamageByTier > 0` and gates the crime and the shield.

### 3.4 Fear exists for two tiers out of five

`RearFear` and `RearChargeFear` are loose per-manoeuvre settings with their own
reaches and scream priorities. A gallop — the heaviest thing that happens in
ordinary riding — frightens nobody. `Fear.lua` is the one pillar that never
adopted the tier-table shape `Tiers.lua` exists to enforce. It shipped in 5.25.0
and 5.26.0, after the roadmap entry that scheduled it *after* the balance pass,
so `ROADMAP.md` item 2 is stale.

### 3.5 The horse's stamina modifiers span 100x and drown the tier

`cost = base x combat x victimArmor x barding x horsemanship`, all multiplicative
and unbounded:

| Factor | Range |
| --- | --- |
| tier base | 12 – 22 |
| combat | 1.0 – 2.2 |
| victim armor | 0.75 – 3.0 |
| barding | 0.75 – 1.0 |
| Horsemanship | 1.2 – 10.0 |

A gallop costs 14.85 at the best end and 1452 at the worst, against a pool of
about 210. The tier separation the rider tunes — 14 against 22, a factor of 1.6 —
is invisible beside a modifier stack spanning nearly 100x. The progressive drain
at low Horsemanship is settled design and is not in question; what is in question
is whether the other three factors should compound with it or be bounded.

### 3.6 The mod's own throw force is a rounding error

`Knockback` 50 and `Uplift` 30 combine to a magnitude of 58.3 against a mass of
80 — a velocity change of 0.73 m/s. The brake applied a few frames later was
measured at 2576 units, forty times larger, and `Reaction.lua` says so in a
comment. The throw is the engine's collision; the only levers that move distance
are `RagdollBrakeKeep*`, the speed cap and the air damping.

`Knockback`, `Uplift`, `ThrowByTier` and `LateralImpulse` are therefore near-dead
knobs presented to the player as the throw settings. The sweep should either give
them authority or say plainly in the settings file that they are trim.

### 3.7 The armor axis is redeclared in three shapes

`ArmorImpulseScale` produces a value bounded by `MinArmorImpulse` 0.35 and
`MaxArmorImpulse` 1.5. Four consumers then re-derive a 0–1 position from a
*different* pair of endpoints, `RagdollBrakeArmorScaleArmored` 0.35 and
`RagdollBrakeArmorScaleUnarmored` 1.26, hardcoded as fallbacks at eight call
sites across `Reaction.lua` (brake, speed cap, air damping) and `Recovery.lua`.
The unarmored endpoint does not match the curve's own ceiling, which is why the
log's `keep` is never the figure the setting names.

**Fix (done, Stage 0):** `Armor.lua` now carries `ArmorLerp`, which is the
position across that span — 0 at the armored endpoint, 1 at the unarmored one —
and `ArmorBlend`, which interpolates a consumer's own pair of figures across it.
The four consumers are one line each and the span's endpoints are read in exactly
one place. The orientation is the one the code already used rather than the
inverse, so no lerp had to be re-signed.

---

## 4. What already works and should not be reopened

Said explicitly so the sweep does not spend rides on it.

- **Damage attribution.** The shield, the deferred blow and the reclaim make the
  mod's tier figure the victim's actual loss. `ImpactDamageByTier` is a real
  number rather than padding on an unknown, so tuning it is meaningful.
- **`wounds`** is derived from `ImpactDamageByTier > 0` rather than by naming the
  walk, so the crime, the shield and the hit event all follow the damage table.
  Setting a tier to zero damage correctly makes it a shove everywhere at once.
- **`TierValue`'s per-key fallback**, which lets a player override three tiers and
  keep shipped values for the other two.
- **Key parity**, already enforced by `tools/audit_code.py`.
- **The gallop ragdoll, the horse's own collision as the source of the throw,
  barding as a flat effect, and progressive stamina drain by Horsemanship.** All
  settled.

---

## 5. How the session should run

The roadmap's position is that armor separation, armor defence and base damage
are one project, because each changes what the others compensate for. That is
right, and it extends further than three numbers. The way to keep it from chasing
its tail is to pin every axis but one, and to fix the structure first.

### Stage 0 — structural, no in-game testing

Everything in section 2. Delete the duplicate tier tables, strip the stale
fallbacks, declare the two missing keys, reconcile the two drifted values, move
`GetSpeedTier`, normalise the armor factor. No behaviour changes except the two
already-drifted values, which come to the rider as a question rather than a
decision made alone.

Then extend `tools/audit_code.py` with the three checks that found section 2:
fallback literals against `Config`, tier-table declarations against `Tiers.lua`,
and `Config` against the settings file. All three are mechanical, and they keep
this class of drift from coming back between sessions and between agents.

**Nothing is tuned until Stage 0 is merged**, because until then every damage
figure exists in three files.

### Stage 1 — four rulings, made at the desk

Answered before anything is measured, because each one determines what the later
stages mean:

1. **Is damage flat per tier, or continuous in speed within the tier?**
   Continuous lets the five figures be derived from one named constant and the
   scored speed, which is what the no-invented-constants rule wants, at the cost
   of the tiers no longer being crisply distinguishable. Flat keeps the current
   design and keeps five picked numbers.
2. **Is the rear a trot-class blow or a gallop-class one?** Section 3.1. The
   answer sets reaction, hit strength, dirt, blood, vocal rank and damage
   together.
3. **Do the stamina modifiers compound or bound?** Section 3.5.
4. **Do `Knockback` and `Uplift` get authority, or get labelled as trim?**
   Section 3.6.

### Stage 2 — one axis at a time, in this order

Each stage pins everything downstream of it. The order is chosen so that no stage
changes an input to a stage already finished.

1. **Tier identity.** `SpeedWalk`, `SpeedTrot`, `SpeedGallop`, and the scored
   speeds for the rear and the charge. Everything else is keyed off which tier
   fires, so this is first, and it is judged by riding rather than by numbers.
2. **Base damage per tier, unarmored.** Armor pinned out, victim unarmored. The
   question is only what a gallop is worth against 100 health.
3. **Armor defence.** `ImpactDamageArmorScale`, `Curve`, `Floor`,
   `IgnoredArmor`. Base damage fixed from stage 2; this decides how much a
   knight refuses. The figure to beat: a charge worth 110 currently becomes 12
   against chainmail.
4. **Throw and armor separation.** The brake, the speed cap and the air damping
   against the normalised armor factor from Stage 0. Includes the charge's throw
   distance, reported as too far.
5. **Recovery.** How long each tier keeps someone down, now that the damage and
   the throw are settled.
6. **Horse stamina.** Last, because its inputs are all decided elsewhere.
7. **Cosmetics.** Dust, dirt, blood, camera shake, blur — ordered against the
   final tier severity, judged by eye.

### Stage 3 — fear, and the roadmap

Give `Fear.lua` the tier-table shape and decide which tiers have a fear band.
This is also when `ROADMAP.md` is corrected: item 2 partly shipped in 5.25.0 and
5.26.0.

### Discipline for the session

- One axis open at a time, and every test setting restored before the next.
- A save reload between configurations, so each run is a separable block in
  `kcd.log`.
- Each stage ends with its figures and their derivation written into `Tiers.lua`
  or the settings file's comments. A number that survives without a recorded
  derivation is a magic number and does not ship.
