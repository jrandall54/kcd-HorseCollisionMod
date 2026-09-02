--- Victims who run out of patience and fight back.
--
-- Barging someone at a walk costs nobody anything. It plays a stagger, takes
-- no health, drains no stamina and raises no crime, so riding into the same
-- person repeatedly is an annoyance with no consequence attached to it. This
-- file attaches one.
--
-- Each walk impact is counted against its victim. Past `RetaliationFreeBumps`
-- every further shove rolls against a chance that grows with the count, and a
-- victim who fails that roll turns and fights.
--
-- ### How the fight is started
--
-- Two steps, and both are the game's own machinery rather than anything
-- invented here.
--
-- `alwaysFightWhenHit` is a context option from the shipped catalog in
-- `Scripts/Script/ContextData.lua`. Vanilla quests set options exactly this
-- way: `q_ledecko` gives four bandits `fightAllHostilePerceptibles`, and
-- `q_hareHunt` applies the `berserk` preset. In `sb_combat.xml` the option
-- sits in front of the morale comparison that otherwise decides whether a
-- civilian fights or flees, and skipping that comparison is all it does.
--
-- Then a `combat:hit` carrying `real = false`, which the victim's combat
-- subbrain answers without the reputation system ever seeing it. That is what
-- makes a provoked scuffle a scuffle rather than an assault charge.
--
-- ### What the game decides, and this file does not
--
-- The shape of the fight is vanilla's. Because the attacker is the player and
-- the player is not already an enemy, `sb_combat.xml` sets
-- `startInDefenseOnly`, so the victim squares up and blocks rather than
-- opening with an attack. Guards who witness the brawl join it, because the
-- game models what a bystander perceived. Neither is arranged here.
--
-- ### Women do not fight
--
-- `sb_combat.xml` tests `b_soul.gender == male` **after** the context option
-- is consulted, and fails everyone else outright. `alwaysFightWhenHit`
-- removes the morale comparison and nothing more, so a woman carrying it
-- still falls through to the report or flee branches. Provoking her would
-- send her walking off to fetch a guard over an incident that raised no
-- crime, which reads as a bug rather than a character. So the roll is not
-- offered to her, and the reason is logged.
--
-- @module Retaliation

--- The context option that makes a victim answer a hit with a fight.
--
-- From the game's own catalog. Named here rather than written inline at each
-- use so a search for it finds one definition.
HorseCollisionMod.RetaliationOption = "alwaysFightWhenHit"

--- The handle every context option this mod sets is carried on.
--
-- `Contexts` tracks each option against a named handle and clears it per
-- handle, so several systems can request the same option without treading on
-- each other. Using one of this mod's own means clearing it can never disturb
-- a quest that wanted the same option for its own reasons.
HorseCollisionMod.RetaliationHandle = "horseCollisionMod"

--- The soul gender that `sb_combat.xml` lets through to the fight branch.
--
-- Confirmed against telemetry rather than assumed: logged reactions report
-- `gender=1` for men and `gender=2` for women.
HorseCollisionMod.GenderMale = 1

--- Whether the context system is available.
--
-- `Contexts` is a vanilla global from `Scripts/Script/Context.lua`. Every use
-- below is wrapped anyway, but checking once gives the telemetry a specific
-- reason rather than a failed call.
-- @treturn boolean true when contexts can be set
function HorseCollisionMod:HasContexts()
	local contexts = rawget(_G, "Contexts")

	return type(contexts) == "table"
			and type(contexts.SetNonpersistentOption) == "function"
end

--- Whether this victim is one the game would let fight back.
--
-- @tparam table npc victim entity
-- @treturn boolean true when a provoked fight is possible
-- @treturn string why not, when it is not
function HorseCollisionMod:CanRetaliate(npc)
	local gender = nil

	pcall(function()
		gender = npc.soul:GetGender()
	end)

	if gender ~= self.GenderMale then
		return false, "gender=" .. tostring(gender)
	end

	if not self:HasContexts() then
		return false, "no-contexts"
	end

	return true, ""
end

--- Counts a shove against a victim and returns how many they have taken.
--
-- A count older than `RetaliationMemorySec` is discarded rather than aged
-- down. Someone barged twice this morning does not start today's ride one
-- shove from a fight.
--
-- @tparam table npc victim entity
-- @treturn number the running count, this shove included
function HorseCollisionMod:NoteAnnoyance(npc)
	local id = tostring(npc.id)
	local now = self:TimeMs()
	local record = self.Annoyance[id]
	local memory = (self.Config.RetaliationMemorySec or 0) * 1000

	if record and memory > 0 and (now - record.at) > memory then
		record = nil
	end

	if not record then
		record = { count = 0, at = now }
	end

	record.count = record.count + 1
	record.at = now
	self.Annoyance[id] = record

	return record.count
end

--- The chance this shove ends in a fight.
--
-- Zero until the victim has taken more than `RetaliationFreeBumps`, then
-- `RetaliationChanceStep` per shove beyond that, capped at
-- `RetaliationMaxChance`. The first contact is always free, so brushing past
-- someone once never starts anything.
--
-- @tparam number count how many shoves this victim has taken
-- @treturn number a chance between 0 and 1
function HorseCollisionMod:RetaliationChance(count)
	local free = self.Config.RetaliationFreeBumps or 0
	local beyond = count - free

	if beyond <= 0 then
		return 0.0
	end

	local chance = beyond * (self.Config.RetaliationChanceStep or 0)
	local ceiling = self.Config.RetaliationMaxChance or 1.0

	if chance > ceiling then
		chance = ceiling
	end

	return chance
end

--- Gives a victim the disposition to fight, and takes it away again.
--
-- The option is nonpersistent, so it does not survive a save reload, and it
-- is cleared on a timer regardless. Left set, every NPC the player had ever
-- shoved would answer any hit from anyone with a fight for the rest of the
-- session, which is a different mod.
--
-- The clear is generation-guarded like every other timer here: a load screen
-- moves `TimerTick`, and a timer set before it fires into a world that no
-- longer contains the entity it was about.
--
-- @tparam table npc victim entity
-- @treturn boolean true when the option was set
function HorseCollisionMod:HoldRetaliation(npc)
	local ok = pcall(function()
		Contexts.SetNonpersistentOption(npc, self.RetaliationOption,
				self.RetaliationHandle)
	end)

	if not ok then
		return false
	end

	local generation = self.TimerTick
	local hold = (self.Config.RetaliationHoldSec or 30) * 1000

	Script.SetTimer(hold, function()
		if generation ~= self.TimerTick then
			return
		end

		self:EndRetaliation(npc)
	end)

	return true
end

--- Takes the disposition back and puts the victim back to work.
--
-- Clearing the option is not enough on its own. A brawl leaves its loser
-- somewhere the daycycle does not resume from: a victim who yielded was
-- observed still running long after the fight was over and the fine had been
-- paid, because nothing had told him the incident was finished.
--
-- `ReplanVictim` is the same `daycycle:restartRequest` the reaction recovery
-- uses, with the payload that was measured moving a parked victim 3.94 m back
-- to his stall. Sent unconditionally rather than behind the idle test
-- `ReplanIfStranded` applies, because a victim still fleeing is not idle and
-- would fail that test while being exactly the case this is for.
--
-- @tparam table npc victim entity
function HorseCollisionMod:EndRetaliation(npc)
	local cleared = pcall(function()
		Contexts.ClearOption(npc, self.RetaliationOption,
				self.RetaliationHandle)
	end)

	local state = nil

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	local replanned = self:ReplanVictim(npc)

	if self.Config.LogTelemetry then
		self:Log("RetaliationEnd " .. tostring(npc:GetName())
				.. " cleared=" .. tostring(cleared)
				.. " state=" .. tostring(state)
				.. " replanned=" .. tostring(replanned))
	end
end

--- Decides whether this walk impact provokes a fight, and starts one if so.
--
-- Called for every walk-tier impact. Everything before the roll is cheap, and
-- the expensive half only runs on a victim who has actually lost patience.
--
-- @tparam table npc victim entity
-- @tparam table playerEnt the player entity
-- @treturn boolean true when a fight was provoked
function HorseCollisionMod:ProvokeIfAnnoyed(npc, playerEnt)
	if not self.Config.Retaliation then
		return false
	end

	local count = self:NoteAnnoyance(npc)
	local chance = self:RetaliationChance(count)

	if chance <= 0 then
		return false
	end

	local able, why = self:CanRetaliate(npc)

	if not able then
		if self.Config.LogTelemetry then
			self:Log("Retaliation " .. tostring(npc:GetName())
					.. " count=" .. tostring(count)
					.. " skipped=" .. why)
		end

		return false
	end

	local roll = math.random()
	local provoked = roll < chance

	if self.Config.LogTelemetry then
		self:Log("Retaliation " .. tostring(npc:GetName())
				.. " count=" .. tostring(count)
				.. " chance=" .. string.format("%.2f", chance)
				.. " roll=" .. string.format("%.2f", roll)
				.. " provoked=" .. tostring(provoked))
	end

	if not provoked then
		return false
	end

	if not self:HoldRetaliation(npc) then
		self:Log("Retaliation " .. tostring(npc:GetName())
				.. " could not take the context option")

		return false
	end

	-- Sent after the option is in place, not before. The option decides how
	-- the stimulus is answered, so one that arrives first is answered the old
	-- way and the provocation is wasted.
	self:SendProvocationHit(npc, playerEnt)

	-- The count is spent. Without this a victim already fighting keeps
	-- rolling on every further contact during the brawl.
	self.Annoyance[tostring(npc.id)] = nil

	return true
end
