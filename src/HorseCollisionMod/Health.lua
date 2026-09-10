--- Health: what an impact cost, and keeping the game from undoing it.
--
-- Nothing in the ScriptBind surface reports damage, so what a collision cost
-- is established by reading health before and after and sampling it again as
-- the victim recovers. `tools/probe_health.lua` watches one entity from the
-- console, for the case where health moves with no impact to account for it.
--
-- `SuppressAutoCure` is here because it protects the measurement: vanilla's
-- daycycle clears a victim's buffs and restores health on its own schedule,
-- which would erase the loss before the later samples are taken.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Health
-- @author jrandall54
-- @release 5.2.0
-- When the impact probe samples, in milliseconds after the hit.
--
-- 500 catches what the impact cost, since the engine applies damage after the
-- message is handled. 3000 catches anything continuing. 6000 and 10000 reach
-- past the get-up, which a ragdoll does not finish before the earlier samples
-- have already been taken.
--
-- Documented as an ordinary comment rather than an LDoc block: LDoc reads an
-- annotated table as a set of named fields and refuses one holding an array.
HorseCollisionMod.ImpactProbeSamples = { 500, 3000, 6000, 10000 }

--- Exempts a collision victim from vanilla's auto-cure daycycle.
--
-- An NPC carrying a bleeding or poison buff whose health is under
-- `t_autoCureLowHealthLimit`, which vanilla sets to 40, enters the
-- `cureLookHurt` behavior in `Libs/AI/final/sb_daycycles_cure.xml`. That
-- subtree plays the `PretendingIllness` animation under a wait with no
-- timeout, and regenerates health at 0.02 per second. Nothing inside it ends,
-- so a victim left under the threshold stands in the street until health
-- climbs back over it, which takes a quarter of an hour of game time and
-- reads as a permanently broken NPC.
--
-- Vanilla exempts its own characters from the daycycle through a context
-- option, used for duellists and for scripted wanderers among others. The
-- same option is set here, and cleared on a timer.
--
-- The gate admitting the cure is read only on entry, so the option has to be
-- in place before health crosses the threshold. It is set at the moment of
-- impact, and collision damage resolves around half a second later.
--
-- @tparam table npc victim entity
function HorseCollisionMod:SuppressAutoCure(npc)
	local HANDLE = "HorseCollisionMod"
	local seconds = self.Config.SuppressAutoCureSec

	if type(seconds) ~= "number" or seconds <= 0 then
		return
	end

	if not npc or not npc.id or type(XGenAIModule) ~= "table" then
		return
	end

	if type(Contexts) ~= "table" then
		return
	end

	-- The message form, `context:timedOptionRequest`, carries its own
	-- expiration and reads as the tidier option, but it is a request to the
	-- brain and a busy brain drops it: sent to a guard in combat, the option
	-- read back false immediately. The direct call writes the Contexts table
	-- and does not depend on the brain accepting anything.
	--
	-- Non-persistent is deliberate. The option does not survive a save, so an
	-- exemption this code fails to clear cannot become permanent in a player's
	-- game.
	pcall(function()
		Contexts.SetNonpersistentOption(npc, "suppressAutoCure", HANDLE)
	end)

	local held = false
	pcall(function()
		held = Contexts.CheckOption(npc, "suppressAutoCure")
	end)

	if self.Config.LogTelemetry then
		self:Log("SuppressAutoCure " .. self:NameOf(npc)
				.. " for=" .. tostring(seconds)
				.. "s set=" .. tostring(held))
	end

	if not held then
		return
	end

	-- Releases a victim already held by the cure, which the exemption alone
	-- cannot do: the gate admitting the subtree is only read on entry, so an
	-- option set afterwards leaves a running cure running. The cure installs
	-- itself as a daycycle patch under this handle, and removing it ends the
	-- activity. The order matters, because removing the patch while the victim
	-- is still bleeding under the threshold and not yet exempt lets the cure
	-- start again immediately.
	--
	-- On a victim that was never stuck this reports false and costs nothing,
	-- so it doubles as the repair path for a save carrying stuck NPCs: any
	-- victim ridden into again is released.
	pcall(function()
		local wuid = XGenAIModule.GetMyWUID(npc)

		if wuid then
			XGenAIModule.RemoveDaycyclePatch(wuid, "curePatch")
		end
	end)

	-- Held for as long as the victim is a candidate for the cure, rather than
	-- for a fixed time. A fixed window cannot be chosen, because what it has
	-- to outlast is the victim climbing back over the threshold at vanilla's
	-- 0.02 health per second, which from thirty health is nearly nine minutes.
	-- A window that lapses while the victim is still below it opens the gate
	-- and the cure starts immediately.
	--
	-- One watcher per victim. A second impact replaces the token, so the
	-- earlier watcher stops on its next pass rather than running alongside.
	local token = (self.CureWatchToken or 0) + 1
	self.CureWatchToken = token
	self.CureWatch = self.CureWatch or {}

	local key = tostring(npc.id)
	self.CureWatch[key] = token

	local function release()
		pcall(function()
			Contexts.ClearOption(npc, "suppressAutoCure", HANDLE)
		end)
	end

	local function watch()
		if self.CureWatch[key] ~= token then
			return
		end

		local health = nil

		pcall(function()
			health = npc.soul:GetState("health")
		end)

		-- A victim that is gone, dead, or safely above the threshold has no
		-- further use for the exemption.
		if type(health) ~= "number" or health <= 0
				or health >= self.Config.AutoCureHealthLimit then
			self.CureWatch[key] = nil
			release()

			return
		end

		Script.SetTimer(seconds * 1000, watch)
	end

	Script.SetTimer(seconds * 1000, watch)
end


--- Samples the victim's health across an impact.
--
-- Vanilla converts a collision hit whose rider is the player into a real
-- `combat:hit` attributed to the player, carrying the `hitStrength` sent
-- here. The engine resolves damage and the reputation change from that
-- strength, and applies both after the message is handled, so neither is
-- readable at the moment of the hit. The health state is sampled again on a
-- timer instead.
--
-- Four samples, because they answer different questions. The first shows what
-- the impact itself cost. The rest reach past the get-up, because health is
-- also lost after a ragdoll resolves, in discrete amounts that look like a
-- fall rather than like bleeding.
--
-- Height is sampled alongside health for the same reason. The impulse throws
-- the target, and a change in z across the recovery separates a fall from
-- anything the collision itself did.
--
-- @tparam table npc victim entity
-- @tparam string tierName the tier the impact scored
-- @tparam number strength the `HitReactionStrength` sent with the hit
-- @tparam[opt] table armor totals from `ArmorOf`, read again when absent
function HorseCollisionMod:ProbeImpactCost(npc, tierName, strength, armor)
	if not self.Config.LogTelemetry or not npc or not npc.soul then
		return
	end

	local ok, before = pcall(function()
		return npc.soul:GetState("health")
	end)

	if not ok or type(before) ~= "number" then
		return
	end

	local name = self:NameOf(npc)

	local function height()
		local okPos, pos = pcall(function()
			return npc:GetWorldPos()
		end)

		if okPos and type(pos) == "table" and type(pos.z) == "number" then
			return pos.z
		end

		return nil
	end

	local baseZ = height()

	-- Where the victim stood when the impact landed. A reaction should leave
	-- them near it; traveling on while animation-controlled is how a victim
	-- reaches somewhere the collision never put them.
	local origin = nil

	pcall(function()
		origin = npc:GetWorldPos()
	end)

	local exhaust = -1

	pcall(function()
		exhaust = npc.soul:GetState("exhaust") or -1
	end)

	-- What the victim was doing when the horse reached them.
	--
	-- Every reaction is a standing animation, so an impact landing on someone
	-- already down plays nothing and usually costs them no health. Without
	-- this, an impact that cost nothing by design reads exactly like one that
	-- failed, and a long investigation turned on being unable to tell them
	-- apart.
	local state = "?"

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	self:Log("ImpactCost " .. name .. " tier=" .. tierName
			.. " state=" .. state
			.. " strength=" .. tostring(strength)
			.. " health=" .. string.format("%.4f", before)
			.. " z=" .. (baseZ and string.format("%.2f", baseZ) or "?")
			.. " exhaust=" .. string.format("%.1f", exhaust)
			.. " " .. self:DescribeArmor(armor or self:ArmorOf(npc)))

	local function sample(label)
		local okAfter, after = pcall(function()
			return npc.soul:GetState("health")
		end)

		if not okAfter or type(after) ~= "number" then
			return
		end

		local z = height()
		local dz = "?"
		local travel = "?"

		pcall(function()
			if origin then
				local q = npc:GetWorldPos()

				if q then
					travel = string.format("%.2f",
							math.sqrt((q.x - origin.x) ^ 2
									+ (q.y - origin.y) ^ 2))
				end
			end
		end)

		if z and baseZ then
			dz = string.format("%+.2f", z - baseZ)
		end

		-- The starting health is repeated on every sample. Samples now run
		-- past the cooldown, so a second impact on the same target can
		-- interleave its lines with the first one's, and the name alone no
		-- longer identifies which impact a sample belongs to.
		self:Log("ImpactCost " .. name .. " " .. label
				.. " from=" .. string.format("%.4f", before)
				.. " health=" .. string.format("%.4f", after)
				.. " delta=" .. string.format("%+.4f", after - before)
				.. " dz=" .. dz
				.. " travel=" .. travel)
	end

	for _, at in ipairs(self.ImpactProbeSamples) do
		Script.SetTimer(at, function()
			sample("t+" .. at .. "ms")
		end)
	end

	-- The throw distance, sampled when the throw is actually over rather than
	-- at a fixed time. A clock sample catches the body mid-flight on one impact
	-- and long after it stopped on another, and worse, while the horse is still
	-- pushing it along, so the figure mixes the throw with how long the horse
	-- kept shoving.
	--
	-- Rest is read from the body's own position rather than from its animation
	-- state. `BlendRagdoll` never appears on a victim the impact killed, so a
	-- state test reports `neverRagdolled` on exactly the impacts that threw
	-- someone hardest and waits out its ceiling instead of measuring them.
	local restPoll = 200
	local restStill = 0.05
	local restCeiling = 8000
	local restStart = self:TimeMs()
	local restLast = nil

	local function atRest()
		local here = nil

		pcall(function()
			here = npc:GetWorldPos()
		end)

		local elapsed = self:TimeMs() - restStart

		if here and restLast then
			local moved = math.sqrt((here.x - restLast.x) ^ 2
					+ (here.y - restLast.y) ^ 2
					+ (here.z - restLast.z) ^ 2)

			if moved < restStill or elapsed >= restCeiling then
				local thrown = "?"

				if origin then
					thrown = string.format("%.2f",
							math.sqrt((here.x - origin.x) ^ 2
									+ (here.y - origin.y) ^ 2))
				end

				self:Log("ImpactThrow " .. name
						.. " why=" .. (moved < restStill and "still" or "ceiling")
						.. " atMs=" .. string.format("%.0f", elapsed)
						.. " thrown=" .. thrown)

				return
			end
		end

		restLast = here
		Script.SetTimer(restPoll, atRest)
	end

	Script.SetTimer(restPoll, atRest)
end


--- Charges a victim for being ridden down, on top of what the engine charged.
--
-- The engine already takes something. A ragdoll under a moving horse is a
-- physics object and the velocity delta is charged at
-- `CollisionVelocityDeltaToDmgR`, which is a global this mod will not
-- override. That cost is real but it is nearly flat against armor: measured
-- across matched impacts an armored target took 87 per cent of what an
-- unarmored one did, with an error bar that includes no difference at all.
-- Being ridden down at a gallop in a shirt and being ridden down in plate
-- therefore cost about the same, which is the thing this function exists to
-- fix.
--
-- So the mod adds its own charge, scaled by `ImpactDamageScale`, and the
-- outcome is left to arithmetic rather than decided by a kill roll. A villager
-- dies at a gallop because the damage usually exceeds what a villager has, and
-- occasionally does not; a knight survives because it usually does not come
-- close. `ImpactDamageVariance` is what makes "usually" mean anything, and a
-- roll that decides death directly would be a different and much cruder thing.
--
-- Applied through `soul:DealDamage(stamina, health, attacker, ...)`, which is
-- vanilla's own call: `deadBody.xml` and `questUtils.xml` use it to kill an
-- entity outright and `npc_roebuck.xml` to wound one. Stamina is left at zero
-- because the horse's side of the impact already debits the rider and the
-- victim's stamina is not what this models.
--
-- **Attribution follows `CollisionIsCrime`.** Named as the player's doing, a
-- death is the player's murder, which is what riding someone down at a gallop
-- ought to be. With the crime switch off the damage lands unattributed, so a
-- collision test is not interrupted by guards. This does not make a trampling
-- death crime free on its own: the engine attributes the trample itself, and
-- that is not reachable from here.
--
-- @tparam table npc victim entity
-- @tparam string tierName the tier the impact scored
-- @tparam table armor totals from `ArmorOf`
-- @tparam[opt] table playerEnt the player, named as the attacker when crime is on
-- @tparam[opt] table horseEnt the player's horse, for the barding bonus
-- @treturn number the damage dealt, or 0 when nothing was
function HorseCollisionMod:ApplyImpactDamage(npc, tierName, armor, playerEnt, horseEnt)
	if not self.Config.ImpactDamage or not npc or not npc.soul then
		return 0
	end

	-- The settings file wins, and the table on the module is the fallback.
	-- These figures are the mod's account of what each kind of collision is
	-- worth, so they belong where a player or a test can reach them rather
	-- than compiled in.
	local byTier = self.Config.ImpactDamageByTier

	if type(byTier) ~= "table" then
		byTier = self.ImpactDamageByTier
	end

	local base = byTier[tierName]

	if type(base) ~= "number" then
		base = self.ImpactDamageByTier[tierName]
	end

	if type(base) ~= "number" or base <= 0 then
		return 0
	end

	local scale = self:ImpactDamageScale(armor)

	-- Symmetric about the base, so the tier figure stays the average rather
	-- than the floor and a setting can be reasoned about as "what this
	-- usually costs".
	local variance = self.Config.ImpactDamageVariance or 0
	local spread = 1.0 + ((math.random() * 2.0) - 1.0) * variance

	-- An armored horse hits harder. Small, because this is the one barding
	-- effect the player cannot see happening and can only infer from how often
	-- someone gets up again.
	local bardingDamage = self:BardingDamageScale(horseEnt)

	-- What this impact is worth before the roll, which is the figure the tier
	-- and the armor curve actually decided.
	local intended = base * scale * bardingDamage
	local damage = intended * spread

	local attacker = nil

	if self.Config.CollisionIsCrime and playerEnt then
		pcall(function()
			attacker = XGenAIModule.GetMyWUID(playerEnt)
		end)
	end

	-- Deferred rather than dealt here, and this is the whole of the crime fix.
	--
	-- The engine applies its own trample damage for a horse collision. The mod
	-- neither sees it nor can gate it, and the engine attributes it to the
	-- rider. Measured on a full-health guard with `CollisionIsCrime` off, so
	-- the mod had sent no hit of its own, it was 22.7.
	--
	-- That much cannot kill a healthy villager on its own. It only ever gets
	-- the kill because this damage lands first and leaves a sliver: the tier
	-- figure is 95 against a villager's 100, so it falls a little short about
	-- two times in three, and the trample finishes what is left.
	--
	-- It matters who finishes them. `sb_switch_awareness.xml` raises the
	-- `murder` stimulus from a hit event that names an attacker and finds the
	-- target dead. A death with no attributed hit behind it is discovered
	-- later as a `corpse`, which `Scripts/Script/Crime.lua` marks
	-- `isCrime = false`. So the killing blow decides whether guards know who
	-- did it, and until now a coin toss decided the killing blow. That is why
	-- riding someone down was sometimes ignored and sometimes an instant
	-- hanging offence, with `CollisionIsCrime` powerless over either.
	--
	-- Waiting puts this damage last. The trample lands on a victim at full
	-- health and cannot kill them, and whatever it leaves is finished here,
	-- under this mod's attribution. `CollisionIsCrime` then decides the
	-- outcome in both directions rather than in neither.
	--
	-- A fixed wait, not a poll, and deliberately so: what is being waited for
	-- is damage that frequently never arrives at all, so there is no state
	-- that says "the trample has resolved" to read. The figure comes from the
	-- impact probe, whose first sample at 500 ms already shows the trample
	-- settled.
	-- The victim's health at the moment of the impact, before anything has had
	-- a chance to charge them for it.
	--
	-- This is what makes the damage the mod's own. The engine charges a
	-- collision itself, at `CollisionVelocityDeltaToDmgR`, and that figure is
	-- neither readable nor overridable from here; the mod's design has always
	-- been to wait it out and land the last blow, so that `CollisionIsCrime`
	-- governs the death. What it never did was account for what the engine
	-- took, so the mod's tier figure was padding on top of an unknown, and a
	-- collision hard enough to kill inside the delay window took the death
	-- out of the mod's hands entirely.
	--
	-- Sampling here and again after the wait gives that unknown a number.
	local atImpact = nil

	pcall(function()
		atImpact = npc.soul:GetState("health")
	end)

	-- Subjects the development tooling created take no damage.
	--
	-- An NPC cannot be made unkillable through the engine. There is no
	-- writable path to its health cap: `SetMaxHealth`, `SetStatLevel` and
	-- `SetDerivedStat` are all absent from a soul, and `SetState("health", n)`
	-- clamps at 100. The Cheat mod's immortality works because it is applied
	-- to the player, who is not capped that way.
	--
	-- So the exemption lives here instead, and it is narrow on purpose: only
	-- entities `tools/dev_subject.lua` spawned are in this table, nothing in
	-- normal play ever puts anything in it, and it is not a setting. Damage is
	-- the only thing skipped. The reaction, the impulse, the sound and every
	-- log line still run, which is what a test of collision feedback needs.
	local exempt = self.ImmortalSubjects and npc.id
			and self.ImmortalSubjects[tostring(npc.id)]

	if exempt then
		-- Skipping the mod's own damage is not enough on its own. The engine
		-- charges a collision too, at about 18 a pass, and that accumulates
		-- unopposed: a subject exempted this way still died after a handful of
		-- runs, and because the engine landed the killing blow the rider was
		-- charged with murder.
		--
		-- So the health is put back to what it was at the impact, which undoes
		-- the engine's charge as well as declining to add one.
		local was = nil

		pcall(function()
			was = npc.soul:GetState("health")
		end)

		Script.SetTimer(self.Config.ImpactDamageDelayMs or 600, function()
			pcall(function()
				if was then
					npc.soul:SetState("health", was)
				end
			end)
		end)

		if self.Config.LogTelemetry then
			self:Log("ImpactDamage " .. self:NameOf(npc)
					.. " tier=" .. tostring(tierName)
					.. " testSubject=true restoredTo="
					.. string.format("%.1f", was or -1))
		end

		return 0
	end

	local delay = self.Config.ImpactDamageDelayMs or 0

	-- Waiting is right only while the engine cannot land the killing blow.
	--
	-- The delay exists so the engine charges its collision first and this mod
	-- finishes the victim, which is what puts the death under the mod's
	-- attribution and lets `CollisionIsCrime` decide it. That reasoning holds
	-- at full health and fails at low health, where the engine's own charge is
	-- enough on its own: measured, it takes between 7 and 21, and a victim left
	-- on 3.7 by a previous impact was killed by it inside the window. The mod
	-- logged `preempted=true`, the kill belonged to the engine, and the rider
	-- was charged with murder.
	--
	-- So when the victim cannot survive what the engine might take, the order
	-- reverses and this lands immediately. The mod still delivers the killing
	-- blow; it just has to be first rather than last to do it.
	local overkill = self.Config.ImpactDamageOverkill or 1.0

	-- Variance may change the number. It may not change the outcome.
	--
	-- A charge on an unarmored villager intends 110 x 1.00 x 1.02 = 112.2,
	-- which kills her twice over. The roll turned it into 96.0 against 96.6
	-- health and she got up with 0.57 left. Nothing about that was a decision:
	-- the tier and the armor curve had already said this blow was fatal, and a
	-- flavor multiplier overruled them by six tenths of a point.
	--
	-- So the roll is free to move the damage anywhere except across the line
	-- between living and dying. A blow that was never lethal to begin with is
	-- untouched by this, which is what keeps an armored victim's survival the
	-- armor's doing.
	if type(atImpact) == "number" and atImpact > 0
			and intended >= atImpact and damage < atImpact then
		if self.Config.LogTelemetry then
			self:Log(string.format(
					"ImpactDamage %s tier=%s variance undercut a fatal blow,"
							.. " %.1f -> %.1f against %.1f health",
					self:NameOf(npc), tostring(tierName), damage,
					atImpact + overkill, atImpact))
		end

		damage = atImpact + overkill
	end

	-- Who lands the killing blow, decided before the wait rather than by it.
	--
	-- The delay exists so the engine charges its collision first and this mod
	-- lands last, which is what puts a death under the mod's attribution and
	-- lets `CollisionIsCrime` govern it. That reasoning holds in exactly one
	-- case: when this damage cannot kill and what it leaves is out of the
	-- engine's reach. Every other case has to be settled here, because once
	-- the wait has started the race is already lost.
	--
	-- Two ways to lose it, both measured with the switch off and both charging
	-- the rider with murder:
	--
	--   A charge on an unarmored woman at full health. The engine took her from
	--   100 to 0 inside the 600 ms window on its own; this damage arrived to
	--   find her dead and logged `preempted=true`. The mod's figure was 112
	--   against her 100, so it would have killed her cleanly.
	--
	--   A charge on a chainmail guard on 51.8 health. Armor cut 110 down to
	--   16.6, so the blow was not fatal and the old health-based rush band of
	--   35 did not cover him. It waited, and the engine took all 51.8.
	--
	-- So the question is not how much health the victim has. It is whether this
	-- impact is going to be lethal at all, by anyone's hand. When it is, the
	-- mod makes sure the hand is its own.
	--
	-- The ceiling is per tier, and it has to be. The engine's trample scales
	-- with the collision, and one figure across all of them is wrong in both
	-- directions: 58 is right for a charge and would have the mod executing
	-- anyone under 58 health for a trot that does two damage. From the log,
	-- largest seen over 136 impacts: rear 0.0, trot 9.2, gallop 33.1, charge
	-- 58.5. `ImpactDamageEngineCeiling` carries those with a little headroom,
	-- because a sample maximum is not a bound.
	--
	-- A rear reads zero because the horse is not moving, so nothing on that
	-- tier is ever finished early.
	-- The settings file wins and the table on the module is the fallback, the
	-- same way `ImpactDamageByTier` is read, so a settings file written before
	-- this existed still gets the measured figures rather than zero.
	local ceilings = self.Config.ImpactDamageEngineCeiling

	if type(ceilings) ~= "table" then
		ceilings = self.ImpactDamageEngineCeiling
	end

	local ceiling = 0

	if type(ceilings) == "table" and type(ceilings[tierName]) == "number" then
		ceiling = ceilings[tierName]
	end

	if type(atImpact) == "number" and atImpact > 0 then
		local why = nil

		if damage >= atImpact then
			-- Already fatal. Waiting only gives the engine a head start on a
			-- victim this was always going to kill.
			why = "fatal"
		elseif ceiling > 0 and (atImpact - damage) <= ceiling then
			-- Not fatal, but what it leaves is inside what the engine takes on
			-- this tier. The victim dies either way, so nothing changes for
			-- the player except which system is credited.
			damage = atImpact + overkill
			why = "finishing"
		end

		-- Left alone otherwise: a victim who would have survived both is not
		-- killed to tidy up attribution.
		if why then
			delay = 0

			if self.Config.LogTelemetry then
				self:Log(string.format(
						"ImpactDamage %s tier=%s %s, dealing %.1f against"
								.. " %.1f health, engine reaches %.1f",
						self:NameOf(npc), tostring(tierName), why, damage,
						atImpact, ceiling))
			end
		end
	end

	local function deal()
		local before = nil

		pcall(function()
			before = npc.soul:GetState("health")
		end)

		-- Give back whatever the engine took, so the only damage on this
		-- victim's account for this impact is the mod's.
		--
		-- Bounded deliberately. Anything can happen in the delay window, and a
		-- victim shot by an archer or falling off a roof must not be healed by
		-- a horse walking past: `ImpactDamageReclaimCeiling` is the most that
		-- can be handed back for one impact, and a larger loss than that is
		-- treated as somebody else's doing and left alone.
		local reclaimed = 0

		if self.Config.ImpactDamageOwnsTheHit
				and type(atImpact) == "number" and type(before) == "number"
				and before > 0 and before < atImpact then
			local taken = atImpact - before
			local ceiling = self.Config.ImpactDamageReclaimCeiling or 0

			if taken <= ceiling then
				if pcall(function()
					npc.soul:SetState("health", atImpact)
				end) then
					reclaimed = taken
					before = atImpact
				end
			end
		end

		-- The engine got there first. This happens when the trample lands on
		-- someone already hurt, and nothing here can take the death back, so
		-- it is logged rather than worked around.
		if type(before) == "number" and before <= 0 then
			if self.Config.LogTelemetry then
				self:Log("ImpactDamage " .. self:NameOf(npc)
						.. " tier=" .. tostring(tierName)
						.. " preempted=true")
			end

			return
		end

		local ok, err = pcall(function()
			npc.soul:DealDamage(0, damage, attacker, false)
		end)

		-- Read back rather than subtracted, because whether this call emptied
		-- the victim is the question the whole deferral exists to answer.
		local after = nil

		pcall(function()
			after = npc.soul:GetState("health")
		end)

		-- A victim killed while an animated reaction is still playing is left
		-- standing in it. The game marks them dead, so other NPCs treat them
		-- as a corpse and the world reacts accordingly, but the interactive
		-- action still owns the body: it holds an idle pose, has no collision,
		-- and walks through walls. Observed on a beggar reared twice, standing
		-- in front of the rider while everyone around him mourned him.
		--
		-- It has been latent all along. The gallop tier ragdolls its victims,
		-- so a death there lands on a body physics already owns, and the tiers
		-- that play animated reactions did too little damage to kill. Raising
		-- the rear's damage made it common.
		--
		-- So a death during an interactive action is handed to a ragdoll,
		-- which is where the engine's own death handling would have put them.
		-- Only then: an ordinary death outside an action already works, and
		-- forcing a ragdoll onto it would override whatever the game chose.
		if type(before) == "number" and before > 0
				and type(after) == "number" and after <= 0 then
			local state = "?"

			pcall(function()
				state = tostring(npc.actor:GetCurrentAnimationState())
			end)

			if state == "AnimationControlled" then
				local freed = pcall(function()
					npc.actor:RagDollize()
				end)

				self:Log("ImpactDeath " .. self:NameOf(npc)
						.. " died in " .. state
						.. ", ragdolled=" .. tostring(freed))
			end
		end

		if self.Config.LogTelemetry then
			self:Log("ImpactDamage " .. self:NameOf(npc)
					.. " tier=" .. tostring(tierName)
					.. " base=" .. string.format("%.1f", base)
					.. " armorScale=" .. string.format("%.2f", scale)
					.. " barding=" .. string.format("%.2f", bardingDamage)
					.. " dealt=" .. string.format("%.1f", damage)
					.. " engineTook=" .. string.format("%.1f", reclaimed)
					.. " health=" .. string.format("%.1f", before or -1)
					.. " after=" .. string.format("%.1f", after or -1)
					.. " fatal=" .. tostring(after ~= nil and after <= 0
							and (before == nil or before > 0))
					.. " attributed=" .. tostring(attacker ~= nil)
					.. " delayed=" .. tostring(delay)
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end

	if delay > 0 then
		Script.SetTimer(delay, deal)
	else
		deal()
	end

	return damage
end
