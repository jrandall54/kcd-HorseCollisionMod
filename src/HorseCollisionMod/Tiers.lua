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
-- This file defines data and one accessor: it is pulled in by
-- `Script.ReloadScript` from `Scripts/Startup/HorseCollisionMod.lua` and
-- re-running it is harmless.
--
-- @module HorseCollisionMod.Tiers
-- @author jrandall54
-- @release 5.13.0

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

--- What each tier is worth in health, before armor.
--
-- The gallop figure is set from measurement rather than picked. At 90 the soft
-- end killed six of eight, and both survivors finished on 3.5 and 0.5 health,
-- having been dealt 81.0 and 80.6 against a villager's 100. The engine's own
-- trample adds a further 15 to 20 on top in most impacts but varies from
-- nothing to 28, and that variation is what leaves any survivors at all. 95
-- carries those two over and lands the rate near the nine in ten asked for.
--
-- Walk is 0 deliberately: a shove staggers, it does not wound. A trot is worth
-- far less than the gallop rather than proportionally less, because the mod
-- puts a man on the ground at a trot and being knocked down is most of the
-- weight the rider wanted a trotting horse to carry.
HorseCollisionMod.ImpactDamageByTier = {
	Walk = 0,
	Trot = 18,
	Gallop = 95,
	Rear = 60,
	Charge = 110,
}

--- What each tier costs the horse, before the rider's Horsemanship, the
--- horse's barding and the combat penalty.
--
-- The rear and the charge carry figures of their own rather than borrowing a
-- loop tier's. They are separate moves with separate costs: a rear is hooves
-- coming down from a standstill and is charged near a trot, while a charge is
-- the heaviest thing the mod does and is charged a gallop's.
--
-- A charge is charged once for the whole lunge rather than once per victim,
-- which is decided at the call site, because riding down a group is the move
-- and a crowd should not empty the horse for standing close together.
HorseCollisionMod.StaminaDrainByTier = {
	Walk = 0.0,
	Trot = 14.0,
	Gallop = 22.0,
	Rear = 12.0,
	Charge = 22.0,
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
