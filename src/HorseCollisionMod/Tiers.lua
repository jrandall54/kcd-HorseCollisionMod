--- The tier concept: five kinds of impact, and what each one is worth.
--
-- A tier is the unit this whole mod varies by. Walk, Trot, Gallop, Rear and
-- Charge each have their own sound, their own dust, their own camera shake,
-- their own reaction and so on. Each of those is one table keyed by tier, read
-- through one accessor, rather than a run of loose settings keys behind a
-- hand-written `if` chain at each point of use.
--
-- That shape is what let the rear and the charge quietly fall out of the
-- Horsemanship progression: nine separate chains, each typed by hand, and no
-- single place where all five tiers could be seen beside each other. A table
-- keyed by tier is one row per concern, so a tier that is missing a value is
-- missing it visibly.
--
-- `TierValue` is the only way those tables are read. It takes the settings
-- file's table when there is one and the compiled-in default when there is
-- not, per key rather than per table, so a player who overrides three tiers
-- still gets shipped values for the other two.
--
-- This file defines the data, one accessor, and the binding at its foot that
-- puts every table into `Config` so the settings file can reach it. It is the
-- only declaration of any of those figures: the entry point carried a second
-- copy of all eight, and they drifted. It is pulled in by
-- `Script.ReloadScript` from `Scripts/Startup/HorseCollisionMod.lua` and
-- re-running it is harmless.
--
-- @module HorseCollisionMod.Tiers
-- @author jrandall54
-- @release 5.29.0

--- One tier's value for one concern.
--
-- The single lookup behind every per-tier table. The settings file is asked
-- first and the compiled-in default answers when it has nothing, which is what
-- lets a player's partial table work: an override of `Gallop` alone leaves the
-- other four at their shipped figures rather than blanking them.
--
-- @tparam string name the table's name, such as "ImpactDamageByTier"
-- @tparam string tierName "Walk", "Trot", "Gallop", "Rear" or "Charge"
-- @return the tier's value, or nil when neither table carries one
function HorseCollisionMod:TierValue(name, tierName)
	if not tierName then
		return nil
	end

	local configured = self.Config and self.Config[name]

	if type(configured) == "table" then
		local value = configured[tierName]

		if value ~= nil then
			return value
		end
	end

	local shipped = self[name]

	if type(shipped) == "table" then
		return shipped[tierName]
	end

	return nil
end

--- Resolves a speed to the tier it falls in.
--
-- The three loop tiers are speed bands and this is where a speed becomes one
-- of them. It sat in `Log.lua` for as long as the telemetry was the only thing
-- that named a gait out loud; tier identity is this file's subject, so it
-- belongs beside the tables that say what each tier is worth.
--
-- The rear and the charge are not reachable from here. They are commanded
-- moves rather than speed bands, and their entry points name their own tier
-- and score it at `RearImpactSpeed` and `RearChargeImpactSpeed`.
--
-- @tparam number speed speed in meters per second
-- @treturn string one of "Gallop", "Trot", "Walk" or "Idle"
function HorseCollisionMod:GetSpeedTier(speed)
	local cfg = self.Config

	if speed >= cfg.SpeedGallop then
		return "Gallop"
	end

	if speed >= cfg.SpeedTrot then
		return "Trot"
	end

	if speed >= cfg.SpeedWalk then
		return "Walk"
	end

	return "Idle"
end

--- What each tier is worth in health, before armor.
--
-- Every figure here is derived from the outcome it should produce against an
-- unarmored man, and the arithmetic is the same each time. NPC health is a
-- flat 100: across the whole testing diary every health reading tops out at
-- exactly 100.00, while stamina runs to 121 and 132, so health is not a
-- vitality-scaled pool. `ImpactDamageVariance` rolls the figure uniformly
-- across 0.85 to 1.15. The mod's damage is the only damage the victim keeps:
-- `ShieldVictimFromEngineDamage` hands the engine's own trample straight back,
-- measured live at `dealt=92.2 engineTook=29.1` leaving a victim on 7.8, so a
-- tier reaches 100 on its own or it does not reach it. A rear charges no
-- engine collision at all, since the horse is standing still.
--
-- Walk is 0 deliberately: a shove staggers, it does not wound. A trot is worth
-- far less than the gallop rather than proportionally less, because the mod
-- puts a man on the ground at a trot and being knocked down is most of the
-- weight the rider wanted a trotting horse to carry.
--
-- The gallop is the blow that kills, at about nine in ten. That needs the roll
-- to clear 100 nine times in ten, which is a threshold of 0.88, so the figure
-- is 100 / 0.88 = 113 before the horse's barding and 111 with it. The earlier
-- 95 was set when the trample was believed to add 15 to 20 on top of it, and
-- measured live it kills about two in five.
--
-- The rear and the charge are commanded moves rather than speed bands, so
-- neither is derived from a speed.
--
-- A rear never kills a healthy man outright. At 75 its span is 65 to 88, so a
-- man on full health always survives one and a man already hurt does not: it
-- takes two rears to put someone down. This keeps clear air between the rear
-- and the gallop, which the rear is below in reaction, hit strength, dirt,
-- blood and vocal rank. Making it kill one in six would have cost 89 and
-- collapsed that gap.
--
-- A charge is the heaviest thing the mod does and the only impact a player
-- spends a perk, a key and most of the horse's stamina on. It is the one blow
-- that kills on every roll: 118 x the worst roll of 0.85 is 100.3. Measured
-- live at 117.2 and 116.0 dealt, both fatal from full health.
HorseCollisionMod.ImpactDamageByTier = {
	Walk = 0,
	Trot = 18,
	Gallop = 111,
	Rear = 75,
	Charge = 118,
}

--- What each tier costs the horse, as a share of that horse's own maximum
--- stamina, before the rider's Horsemanship, the horse's barding and the
--- combat surcharge.
--
-- A share rather than a point figure because the pool is not fixed: it
-- measured 210 on the test horse and 230 on another, so it is that horse's own
-- stamina stat and a flat cost would mean different things on different
-- mounts.
--
-- The gallop's 0.20 is the anchor and everything else is derived from it. It
-- comes from two statements of intent held together: a horse should not become
-- a tank but Henry should be able to ride down a few people with ease, and one
-- gallop impact empties the horse at level 0 Horsemanship. With the
-- Horsemanship span running 5.0 down to 1.0, 0.20 of the pool is exactly one
-- full pool at level 0 and five back-to-back impacts at the top of the skill.
-- A trot is 0.13, about eight impacts back to back, because it puts a man on
-- the ground without being the blow that kills and should not be rationed the
-- way the gallop is. Walk is 0 for the same reason it deals no damage: a shove
-- is not an impact. These are back-to-back counts, and the diary records
-- stamina refilling between passes, so a player who circles and lines up again
-- gets more than the figure says.
--
-- The rear and the charge carry figures of their own rather than borrowing a
-- loop tier's. They are also the two tiers that are not limited by stamina at
-- all: they are commanded attacks rather than consequences of riding, so what
-- stops a player spamming them is `RearCooldownMs` on the move itself, and
-- their share is only a cost the player feels.
--
-- A charge is charged once for the whole lunge rather than once per victim,
-- which is decided at the call site, because riding down a group is the move
-- and a crowd should not empty the horse for standing close together.
HorseCollisionMod.StaminaShareByTier = {
	Walk = 0.00,
	Trot = 0.13,
	Gallop = 0.20,
	Rear = 0.10,
	Charge = 0.20,
}

--- What a victim's body does when the tier lands on them.
--
-- Three kinds, and the split is not the two it looks like from the outside:
--
--   * `stagger` plays `hcm_stagger_` and never makes the victim a physics
--     object at all.
--   * `fall` plays `hcm_fall_`, whose fragments carry a Ragdoll ProcLayer at
--     their own ExitTime, so Mannequin hands the body to physics partway
--     through the clip and owns the timing.
--   * `ragdoll` drops the victim at the moment of contact and drives the
--     throw from this mod.
--
-- The rear sits with the trot rather than with the gallop, which is what the
-- old `RearReaction or TrotReaction` fallback was saying in a way that could
-- silently change the rear by changing the trot.
HorseCollisionMod.ReactionByTier = {
	Walk = "stagger",
	Trot = "fall",
	Gallop = "ragdoll",
	Rear = "fall",
	Charge = "ragdoll",
}

--- The tier's share of the configured impulse, for the tiers that ragdoll.
--
-- Only the `ragdoll` tiers appear. The others hand the body to physics through
-- Mannequin and this mod never pushes it, so a figure for them would be a
-- number that looks live and is not; two such figures sat in the code for
-- months behind branches that shipped settings never reached.
--
-- The charge is below a gallop rather than above it. The horse is still moving
-- under its own impulse when the victim goes down in front of it, so its
-- collider shoves the ragdoll on top of whatever this applies.
HorseCollisionMod.ThrowByTier = {
	Gallop = 1.0,
	Charge = 0.7,
}

--- How hard the engine is told each tier hit, by `HitReactionStrength` name.
--
-- Named rather than numbered so the settings file reads as English and so a
-- value that is not a strength fails visibly instead of becoming a plausible
-- integer.
--
-- The charge used to probe itself as a minor injury while sending a major one.
-- The probe was written once for both rear tiers and the send was branched, so
-- the two disagreed and the telemetry named the wrong figure.
HorseCollisionMod.HitStrengthByTier = {
	Walk = "Tickle",
	Trot = "MinorInjury",
	Gallop = "MajorInjury",
	Rear = "MinorInjury",
	Charge = "MajorInjury",
}

--- Which set of spoken lines a victim answers each tier with.
--
-- The collision reactions and the rear are separate pillars with separate
-- switches, and this is where that separation is stated rather than implied by
-- which file the call happened to sit in.
HorseCollisionMod.VictimBarkByTier = {
	Walk = "collision",
	Trot = "collision",
	Gallop = "collision",
	Rear = "rear",
	Charge = "rear",
}

--- Which tiers can make a victim lose patience and fight back.
--
-- Retaliation answers being shoved, and the escalating roll behind it is built
-- around a nuisance that does no real harm. A rear brings hooves down on
-- somebody and a charge rides them down; neither is a shove.
HorseCollisionMod.RetaliationByTier = {
	Walk = true,
	Trot = false,
	Gallop = false,
	Rear = false,
	Charge = false,
}

--- Which tiers charge the horse once per victim.
--
-- The detection loop resolves one victim per impact, so it charges there. A
-- rear and a charge are one deliberate move that can land on several people at
-- once, and charging per victim would empty the horse for riding at a crowd,
-- so their entry points charge once for the whole move instead.
HorseCollisionMod.StaminaPerVictimByTier = {
	Walk = true,
	Trot = true,
	Gallop = true,
	Rear = false,
	Charge = false,
}

--- Binds every table above into `Config`, which is the only place a player can
--- reach them from.
--
-- `ApplySettings` refuses a settings key that `Config` does not already
-- declare, so a tier table that lived only on this module could never be
-- overridden at all. Both were therefore declared, with the value written out
-- twice: once here beside its derivation and once as a bare literal in the
-- entry point. The two drifted. `VictimBarkByTier.Charge` read "rear" in one
-- and "collision" in the other, and `RiderVocalByTier` was a whole tier apart,
-- and neither difference was visible, because a whole-table override hides the
-- module copy until a player overrides a single tier.
--
-- Bound rather than copied, so there is one literal per concern and the two
-- lookups `TierValue` makes have distinct jobs rather than duplicate contents:
--
--   * `Config[name]` is the whole table, replaced outright when the settings
--     file carries one, because `ApplySettings` assigns rather than merges.
--   * `self[name]` is this module's own table, which that assignment cannot
--     reach, and is therefore the per-tier floor under a partial override.
--
-- A player who writes `ImpactDamageByTier = { Gallop = 200 }` gets 200 for a
-- gallop and the shipped figures for the other four, and those figures are now
-- the same ones the shipped build runs.
--
-- Re-running this file rebinds `Config` to the shipped tables and so discards
-- an applied override, which is harmless: every path that reloads the mod
-- reloads the settings file and calls `ApplySettings` after it.
HorseCollisionMod.TierTables = {
	"ImpactDamageByTier",
	"StaminaShareByTier",
	"ReactionByTier",
	"ThrowByTier",
	"HitStrengthByTier",
	"VictimBarkByTier",
	"RetaliationByTier",
	"StaminaPerVictimByTier",
}

for _, hcmTierTable in ipairs(HorseCollisionMod.TierTables) do
	HorseCollisionMod.Config[hcmTierTable] = HorseCollisionMod[hcmTierTable]
end
