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
-- @release 4.11.0
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
end

--- How much of the tier's damage a target in this armor takes.
--
-- One falling curve against the summed `smash_def` of what the victim is
-- wearing, past the part of it that is not armor:
-- `1 / (1 + max(0, smashDef - ImpactDamageIgnoredArmor) / ImpactDamageArmorScale)`.
-- It reaches 1.0 on anyone in ordinary clothes and never reaches 0, so plate
-- is a very bad day rather than immunity.
--
-- The subtraction is what makes the curve work at all. Shoes, a shirt and a
-- hood are in the `armor` table and sum to 0.30 to 0.50 on a villager wearing
-- nothing anyone would call armor. Measured against the raw figure, a villager
-- was already taking 17 per cent off for being dressed, which meant the curve
-- could not be made steep enough to spare a knight without also sparing her.
--
-- `smash_def` is the game's own blunt resistance and is the right column for a
-- horse: it is what the engine consults for a mace or a hammer, and a horse's
-- chest is the same kind of problem for a breastplate. Weight is deliberately
-- not used, though `ArmorOf` returns it, because a heavy mail hauberk and a
-- heavy padded gambeson weigh alike and stop a blunt impact very differently.
--
-- The scale is a half-life rather than a ceiling: at
-- `ImpactDamageArmorScale` past the ignored figure the target takes half, at
-- twice it a third. With the shipped 0.6 that reads across the range actually
-- worn in game as
--
--     villager    smashDef 0.30   1.00
--     light       smashDef 1.50   0.37
--     mail        smashDef 4.99   0.12
--     heavy mail  smashDef 7.16   0.08
--     plate       smashDef 12.0   0.05
--
-- @tparam table armor totals from `ArmorOf`
-- @treturn number multiplier on the tier's damage, in (0, 1]
function HorseCollisionMod:ImpactDamageScale(armor)
	local scale = self.Config.ImpactDamageArmorScale

	if type(scale) ~= "number" or scale <= 0 then
		return 1.0
	end

	local smashDef = 0

	if type(armor) == "table" and type(armor.smashDef) == "number" then
		smashDef = armor.smashDef
	end

	local ignored = self.Config.ImpactDamageIgnoredArmor or 0
	local worn = smashDef - ignored

	if worn <= 0 then
		return 1.0
	end

	return 1.0 / (1.0 + (worn / scale))
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
-- @treturn number the damage dealt, or 0 when nothing was
function HorseCollisionMod:ApplyImpactDamage(npc, tierName, armor, playerEnt)
	if not self.Config.ImpactDamage or not npc or not npc.soul then
		return 0
	end

	local base = self.ImpactDamageByTier[tierName]

	if type(base) ~= "number" or base <= 0 then
		return 0
	end

	local scale = self:ImpactDamageScale(armor)

	-- Symmetric about the base, so the tier figure stays the average rather
	-- than the floor and a setting can be reasoned about as "what this
	-- usually costs".
	local variance = self.Config.ImpactDamageVariance or 0
	local spread = 1.0 + ((math.random() * 2.0) - 1.0) * variance
	local damage = base * scale * spread

	local attacker = nil

	if self.Config.CollisionIsCrime and playerEnt then
		pcall(function()
			attacker = XGenAIModule.GetMyWUID(playerEnt)
		end)
	end

	local before = nil

	pcall(function()
		before = npc.soul:GetState("health")
	end)

	local ok, err = pcall(function()
		npc.soul:DealDamage(0, damage, attacker, false)
	end)

	if self.Config.LogTelemetry then
		self:Log("ImpactDamage " .. self:NameOf(npc)
				.. " tier=" .. tostring(tierName)
				.. " base=" .. string.format("%.1f", base)
				.. " armorScale=" .. string.format("%.2f", scale)
				.. " dealt=" .. string.format("%.1f", damage)
				.. " health=" .. string.format("%.1f", before or -1)
				.. " attributed=" .. tostring(attacker ~= nil)
				.. " ok=" .. tostring(ok)
				.. " err=" .. tostring(err))
	end

	if not ok then
		return 0
	end

	return damage
end
