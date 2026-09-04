--- Health: what an impact cost, and keeping the game from undoing it.
--
-- Nothing in the ScriptBind surface reports damage, so what a collision cost
-- is established by reading health before and after and sampling it again as
-- the victim recovers. `WatchHealth` is the console-driven version of the same
-- idea, used when health moves with no impact to account for it.
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
-- @release 4.9.1
--- Logs a named entity's health whenever it changes.
--
-- Health has moved in every ride with no impact to account for it, and an
-- impact the footprint rejects writes no line at all, so there is nothing to
-- correlate the loss against. Watching one target records the moment health
-- moves, whether or not the mod caused it.
--
-- A diagnostic, started from the console rather than from play. It samples
-- twice a second and writes only on a change, so a quiet watch costs two
-- lines.
--
-- @tparam string name entity name to watch
-- @tparam number seconds how long to watch, default 90
function HorseCollisionMod:WatchHealth(name, seconds)
	local ent = System.GetEntityByName(name)

	if not ent or not ent.soul then
		self:Log("Watch " .. tostring(name) .. " not found")
		return
	end

	-- The same generation guard the detection loop uses. A watch left running
	-- across a load screen would otherwise hold a stale entity forever.
	local generation = self.TimerTick
	local deadline = System.GetCurrTime() + (seconds or 90)
	local last = nil

	local function tick()
		if generation ~= self.TimerTick then
			return
		end

		local ok, health = pcall(function()
			return ent.soul:GetState("health")
		end)

		if not ok or type(health) ~= "number" then
			self:Log("Watch " .. name .. " lost")
			return
		end

		if last and health ~= last then
			local z = "?"
			local away = "?"

			-- Where the rider was standing when the health moved. A loss with
			-- the horse alongside is a contact the footprint rejected; a loss
			-- with the horse far off is something else entirely.
			pcall(function()
				local q = ent:GetWorldPos()
				local r = player:GetWorldPos()

				z = string.format("%.2f", q.z)
				away = string.format("%.1f", math.sqrt(
						(q.x - r.x) * (q.x - r.x)
						+ (q.y - r.y) * (q.y - r.y)))
			end)

			self:Log("Watch " .. name
					.. " health=" .. string.format("%.4f", health)
					.. " delta=" .. string.format("%+.4f", health - last)
					.. " z=" .. z
					.. " rider=" .. away .. "m"
					.. " speed=" .. string.format("%.2f", self:RecentPeak(3)))
		end

		last = health

		if System.GetCurrTime() < deadline then
			Script.SetTimer(500, tick)
		else
			self:Log("Watch " .. name .. " ended health="
					.. string.format("%.4f", health))
		end
	end

	self:Log("Watch " .. name .. " started health="
			.. string.format("%.4f", ent.soul:GetState("health")))
	tick()
end


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
		local name = "?"
		pcall(function() name = npc:GetName() or "?" end)
		self:Log("SuppressAutoCure " .. name .. " for=" .. tostring(seconds)
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

	local name = "?"
	pcall(function()
		name = npc:GetName() or "?"
	end)

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
