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
-- @release 5.30.0

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
-- Both tiers are 1.0, and the reason is worth keeping. This scales `Knockback`
-- and `Uplift`, together a velocity change of about 0.73 m/s on an 80 kg body,
-- so it is trim, and the audit's fourth ruling said so. It was briefly made to
-- scale the ragdoll brake and the airborne speed cap as well, to give the
-- charge its distance, and that stacked three multipliers on one throw: an
-- unarmored victim launched at 10.9 m/s under a ceiling raised by the same
-- factor traveled 20 meters.
--
-- One factor in one place. What separates a charge from a gallop is the speed
-- it is resolved at, `RearChargeImpactSpeed`, and everything downstream is the
-- gallop's own machinery working on a faster impact.
HorseCollisionMod.ThrowByTier = {
	Gallop = 1.0,
	Charge = 1.0,
}

--- How each ragdoll tier throws a victim, and what holds the throw down.
--
-- The two ragdoll tiers are opposite in kind under the hood and identical to
-- the player: both look like physical contact and both throw a body in
-- ragdoll. What differs is who owns the throw.
--
-- **The gallop reacts to physics.** The horse is genuinely moving at 8 to
-- 12 m/s under its own locomotion and carries through the victim, so the
-- engine's collision does the throwing and there is a real throw to take away.
-- The gallop is subtractive: a brake keeps a fraction of what the engine gave,
-- and a ceiling with a soft drag holds what is left.
--
-- **The charge sidesteps physics.** The lunge starts from a stop and ends at a
-- stop. The horse only moves because this mod hands it `RearChargeImpulse`,
-- and through the rear Mannequin holds it `AnimationControlled`, so its own
-- velocity reads 0.02 to 0.07 with occasional snaps of 25.9 and cannot be
-- measured at all. The engine's collision does not reliably deliver anything:
-- measured with no mod throw in place, charge victims moved 0.3 to 1.0 m.
--
-- So the mod owns the charge outright. It commands the throw, and nothing
-- downstream is allowed to take it back out. Half-ownership is what produced
-- years of circles here -- the mod launched the victim and then ran the
-- gallop's subtractive brake, ceiling and a per-poll cap enforcement over the
-- top, two systems fighting over one body, and the charge came out traveling
-- *less* than a gallop.
--
-- ## The steps
--
--  1. **Throw.** Either a brake, which keeps a fraction of the speed the body
--     arrived with (the gallop), or a launch, which commands a speed outright
--     as a floor under whatever the body holds (the charge). A tier carries
--     one or the other, never both.
--  2. **Cap.** The speed the body may not exceed while it is in the air, held
--     there by drag. For the gallop it is what removes variance from the
--     engine's throw. For the charge it is only a rail: it sits at the
--     commanded speed, so it never touches the throw itself and catches only
--     what the horse's collider adds on top afterwards.
--  3. **Settle.** Damping and a sleep threshold once it is on the ground,
--     which is the same for every tier and lives in the `RagdollDamp*`
--     settings.
--
-- Both endpoints of every pair are blended across the victim's armour, so
-- armour is what decides distance within a tier, in both tiers.
--
-- ## The charge's throw is 1:1 with the horse
--
-- The charge commands a speed, so that speed has to come from somewhere real
-- or it is an invented constant, which is what every previous attempt here
-- was. It is derived from the lunge the mod itself commanded:
--
--     throw = RearChargeImpactSpeed * transfer * RearChargeThrow
--
-- `RearChargeImpactSpeed` is the lunge, already declared rather than measured
-- for exactly this reason: `RearChargeImpulse` of 6000 on a horse of about 480
-- kg is 12.5 m/s, and the setting says 12.3.
--
-- `transfer` is the fraction of a striker's speed a struck body leaves with,
-- and the gallop supplies it, because the gallop is tuned and accepted. Its
-- ceilings are the speeds this mod has settled on as right for each armour
-- class -- 6.0 unarmored and 2.5 in full mail -- so the transfer that
-- reproduces them off a 12.3 m/s lunge is 6.0/12.3 = 0.49 and 2.5/12.3 = 0.20.
-- That is what makes a charge at `RearChargeThrow` of 1.0 land like a gallop.
--
-- `RearChargeThrow` is then the only dial, and it has a wide range on purpose:
-- a charge is an offensive attack the player commands, not a consequence of
-- riding into somebody, so it is allowed to be tuned well past what a gallop
-- would ever do.
--
-- The drag is the gallop's, 20.0 in mail and 4.0 unarmored, because drag is
-- not a distance axis in either tier. It is what makes a ceiling true.
HorseCollisionMod.ThrowProfileByTier = {
	Gallop = {
		brakeKeepArmored   = 0.45,
		brakeKeepUnarmored = 1.0,
		capArmored         = 2.5,
		capUnarmored       = 6.0,
		dragArmored        = 20.0,
		dragUnarmored      = 4.0,
	},

	Charge = {
		lungeTransferArmored   = 0.20,
		lungeTransferUnarmored = 0.49,
		dragArmored            = 20.0,
		dragUnarmored          = 4.0,
	},
}

--- Resolves a tier's throw profile against a victim's armour.
--
-- Returns a flat table of the figures the throw pipeline needs, with every
-- armour pair already blended, or nil for a tier that does not ragdoll. The
-- pipeline reads only what comes back from here, so no part of it knows which
-- tier it is working for.
--
-- @tparam string tierName the tier that struck
-- @tparam[opt] number armorScale the victim's armor scale, high for an
--   unarmored victim and low for one in mail
-- @treturn[1] table a keep or a launch, the cap that rails it and the drag
-- @treturn[2] nil for a tier with no profile
function HorseCollisionMod:ThrowProfile(tierName, armorScale)
	local shape = self:TierValue("ThrowProfileByTier", tierName)

	if type(shape) ~= "table" then
		return nil
	end

	local profile = {
		drag = self:ArmorBlend(armorScale, shape.dragArmored,
				shape.dragUnarmored),
	}

	-- A brake keeps a fraction, so no brake is 1.0 and not 0.
	profile.keep = 1.0

	if shape.brakeKeepArmored or shape.brakeKeepUnarmored then
		profile.keep = self:ArmorBlend(armorScale, shape.brakeKeepArmored,
				shape.brakeKeepUnarmored)

		if profile.keep < 0.02 then
			profile.keep = 0.02
		end
	end

	-- A tier the mod throws itself, derived 1:1 from the lunge it commanded.
	--
	-- The transfer is the fraction of the striker's speed a struck body leaves
	-- with, so the lunge speed is the thing it is a fraction *of*, and the dial
	-- multiplies the result. Nothing here is a constant: the lunge is
	-- `RearChargeImpulse` over the horse's mass, and the transfer reproduces
	-- the gallop's accepted ceilings off it.
	--
	-- The cap is then the commanded speed itself, so it is a rail rather than
	-- a ceiling. It cannot shorten a throw the mod set, because it sits exactly
	-- where that throw lands; it catches only what the horse's collider adds
	-- afterwards. A tier that commands its own throw must not have anything
	-- downstream subtracting from it.
	if shape.lungeTransferArmored or shape.lungeTransferUnarmored then
		local transfer = self:ArmorBlend(armorScale,
				shape.lungeTransferArmored, shape.lungeTransferUnarmored)

		profile.launch = (self.Config.RearChargeImpactSpeed) * transfer
				* (self.Config.RearChargeThrow)
		profile.cap = profile.launch

		-- And the rail is enforced, which is the half that makes ownership
		-- real. Drag does not bind a ragdoll: measured, a victim railed at
		-- 6.03 was driven to 8.64 and 9.17 m/s by the horse's collider with
		-- the drag applied throughout, and lowering the commanded speed did
		-- not shorten a single throw, because the commanded speed was only
		-- ever a floor. A tier that owns its throw has to hold it at both
		-- ends.
		profile.railEnforce = true
	end

	-- A tier whose ceiling is stated outright rather than derived from a throw
	-- it commanded, which is every tier that lets the engine do the throwing.
	if shape.capArmored or shape.capUnarmored then
		profile.cap = self:ArmorBlend(armorScale, shape.capArmored,
				shape.capUnarmored)
	end

	profile.cap = profile.cap or 0

	return profile
end

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
	"ThrowProfileByTier",
	"HitStrengthByTier",
	"VictimBarkByTier",
	"RetaliationByTier",
	"StaminaPerVictimByTier",
}

for _, hcmTierTable in ipairs(HorseCollisionMod.TierTables) do
	HorseCollisionMod.Config[hcmTierTable] = HorseCollisionMod[hcmTierTable]
end
