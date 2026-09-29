--- Health: what an impact costs a victim.
--
-- * `ApplyImpactDamage` deals the mod's own damage once the body stops,
--   reclaiming what the engine charged, so the mod's figure is the whole cost
--   and the mod's blow is the one that kills.
-- * `PredictImpactFatal` answers at the moment of contact whether that damage
--   will kill, for Henry's line.
-- * `IsProtectedFromHarm` exempts the characters the game protects.
-- * `SuppressAutoCure` keeps a hurt victim out of vanilla's auto-cure daycycle.
-- * `ProbeImpactCost` logs health across an impact, since nothing in the
--   ScriptBind surface reports damage.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Health
-- @author jrandall54

-- When the impact probe samples, in milliseconds after the hit.
--
-- 500 catches what the impact cost, since the engine applies damage after the
-- message is handled. 3000 catches anything continuing. 6000 and 10000 reach
-- past the get-up, which a ragdoll does not finish before the earlier samples
-- have already been taken.
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
-- same option is set here and held until the victim's health is back over
-- `AutoCureHealthLimit`, rechecked every `SuppressAutoCureSec`.
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

	-- The message form, `context:timedOptionRequest`, is a request to the
	-- brain, and a busy brain drops it. The direct call writes the Contexts
	-- table and does not depend on the brain accepting anything.
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
	-- On a victim that was never held this reports false and costs nothing.
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

	local exhaust = -1

	pcall(function()
		exhaust = npc.soul:GetState("exhaust") or -1
	end)

	-- What the victim was doing when the horse reached them.
	--
	-- An impact landing on someone already down plays nothing, and the state
	-- separates that from an impact that failed.
	local state = "?"

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	self:Log("ImpactCost " .. name .. " tier=" .. tierName
			.. " state=" .. state
			.. " strength=" .. tostring(strength)
			.. " health=" .. string.format("%.4f", before)
			.. " exhaust=" .. string.format("%.1f", exhaust)
			.. " " .. self:DescribeArmor(armor or self:ArmorOf(npc)))

	local function sample(label)
		local okAfter, after = pcall(function()
			return npc.soul:GetState("health")
		end)

		if not okAfter or type(after) ~= "number" then
			return
		end

		-- The starting health is repeated on every sample as `from=`, so the
		-- samples of two impacts on one target can be told apart when they
		-- interleave.
		self:Log("ImpactCost " .. name .. " " .. label
				.. " from=" .. string.format("%.4f", before)
				.. " health=" .. string.format("%.4f", after)
				.. " delta=" .. string.format("%+.4f", after - before))
	end

	for _, at in ipairs(self.ImpactProbeSamples) do
		Script.SetTimer(at, function()
			sample("t+" .. at .. "ms")
		end)
	end
end

--- Whether this impact is about to kill, worked out at the moment of contact.
--
-- Exists so Henry can react on time. `ApplyImpactDamage` defers its damage
-- until the thrown body comes to rest, so a line chosen from the resolved
-- death would arrive long after the collision.
--
-- The arithmetic is `ApplyImpactDamage`'s own, taken at the intended figure,
-- the center of the variance roll. A death line over a survivor is the worse
-- error, so the prediction is the average outcome and misses some kills near
-- the margin.
--
-- The engine's own trample damage is not added in: with
-- `ImpactDamageOwnsTheHit` the mod reclaims it, so the mod's own figure is
-- what decides the death.
--
-- @tparam table npc the victim
-- @tparam string tierName the impact tier
-- @tparam ?table armor the victim's armor reading, as `ApplyImpactDamage` takes it
-- @tparam ?table horseEnt the horse, for its barding
-- @treturn boolean true when this impact is expected to be fatal
function HorseCollisionMod:PredictImpactFatal(npc, tierName, armor, horseEnt)
	if not self.Config.ImpactDamage or not npc or not npc.soul then
		return false
	end

	-- Nothing this mod does can kill somebody the game protects, so nothing
	-- downstream should be told to expect it.
	if self:IsProtectedFromHarm(npc) then
		return false
	end

	local base = self:TierValue("ImpactDamageByTier", tierName)

	if type(base) ~= "number" or base <= 0 then
		return false
	end

	local health = nil

	pcall(function()
		health = npc.soul:GetState("health")
	end)

	if type(health) ~= "number" then
		return false
	end

	local intended = base * self:ImpactDamageScale(armor)
			* self:BardingDamageScale(horseEnt)

	return intended >= health
end

--- Whether the game itself marks somebody as not to be harmed.
--
-- Vanilla never offers the option of swinging at Captain Bernard or the Lord of
-- Leipa: the refusal lives in the attack path, and this mod does not use that
-- path. `soul:DealDamage` charges health directly and ignores the game's own
-- immortality flag.
--
-- The marker is a flag rather than a name. Such characters carry the VIP
-- protection derived stats and an ordinary guard carries none of them:
--
--     rat_bernard  apr=1 imm=1 upr=1 ppr=1
--     villageGuard apr=0 imm=0 upr=0 ppr=0
--
-- `apr` is the one read. It is attack protection, granted by the
-- `vip_attackprot` buff, and nothing in this mod writes it. `imm` is generic
-- immortality, which `ShieldFromEngineDamage` grants **every** victim at the
-- moment of contact, so it cannot identify anybody. The known gap is a
-- character a quest makes immortal without attack protection.
--
-- Reading the flag rather than keeping a list of names covers every character
-- the game protects, including the ones protected only for one quest.
--
-- @tparam table npc the victim
-- @treturn boolean true when the game marks this character as protected
function HorseCollisionMod:IsProtectedFromHarm(npc)
	if not self.Config.ProtectStoryCharacters or not npc or not npc.soul then
		return false
	end

	local protected = false

	-- `apr` is read unconditionally. Nothing this mod does touches it, so it is
	-- always somebody else's mark.
	pcall(function()
		local value = npc.soul:GetDerivedStat("apr")

		if type(value) == "number" and value > 0 then
			protected = true
		end
	end)

	return protected
end

--- Charges a victim for being ridden down.
--
-- The engine charges a collision itself, at `CollisionVelocityDeltaToDmgR`, a
-- global this mod will not override, and that charge is nearly flat against
-- armor. With `ImpactDamageOwnsTheHit` the mod reclaims it and deals its own
-- figure, scaled by `ImpactDamageScale`, so the mod's figure is the whole cost.
-- The outcome is left to arithmetic rather than decided by a kill roll: a
-- villager dies at a gallop because the damage usually exceeds what a villager
-- has, and a knight survives because it usually does not come close.
-- `ImpactDamageVariance` is what makes "usually" mean anything.
--
-- Applied through `soul:DealDamage`, vanilla's own call: `deadBody.xml` and
-- `questUtils.xml` use it to kill an entity outright and `npc_roebuck.xml` to
-- wound one. Stamina is left at zero; the horse's side of the impact already
-- debits the rider.
--
-- **It takes two arguments and no more.** `C_ScriptBindSoul` declares
-- `DealDamage(float stamina, float health)`: a raw subtraction on the soul,
-- with no attacker, no hit type and nothing the victim's behavior tree sees.
-- Vanilla's death cry is raised inside `IsDeadCheck -> Then` in
-- `sb_switch_hitreactions.xml` while a hit is processed, so a victim this call
-- kills dies silently.
--
-- ### Why the damage waits for the body to stop
--
-- The engine attributes its own trample to the rider and cannot be gated, and
-- `sb_switch_awareness.xml` raises `murder` only from a hit that names an
-- attacker and finds the target dead; a death with no attributed hit is found
-- later as a `corpse`, which `Scripts/Script/Crime.lua` marks
-- `isCrime = false`. So the killing blow decides whether guards know who did
-- it. The victim is shielded from the moment of contact
-- (`ShieldFromEngineDamage`) until the body stops, the engine's charge is
-- reclaimed, and the mod's blow is the one that kills, which lets
-- `CollisionIsCrime` govern the death. The crime hit is sent from `Impact.lua`
-- when a victim rises, and from here on a death.
--
-- @tparam table npc victim entity
-- @tparam string tierName the tier the impact scored
-- @tparam table armor totals from `ArmorOf`
-- @tparam[opt] table playerEnt the player, to whom a death is attributed when
--   `CollisionIsCrime` is on
-- @tparam[opt] table horseEnt the player's horse, for the barding bonus
-- @tparam[opt] number hitStrength the `HitReactionStrength` the crime hit
--   carries on a death
-- @treturn number the rolled damage, before the deferred path deals it
function HorseCollisionMod:ApplyImpactDamage(npc, tierName, armor,
		playerEnt, horseEnt, hitStrength)
	if not self.Config.ImpactDamage or not npc or not npc.soul then
		return 0
	end

	local base = self:TierValue("ImpactDamageByTier", tierName)

	if type(base) ~= "number" or base <= 0 then
		return 0
	end

	local scale = self:ImpactDamageScale(armor)

	-- Symmetric about the base, so the tier figure stays the average rather
	-- than the floor and a setting can be reasoned about as "what this
	-- usually costs".
	local variance = self.Config.ImpactDamageVariance
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

	-- The victim's health at the moment of the impact, before anything has had
	-- a chance to charge them for it. Sampled again when the damage is dealt,
	-- the difference is what the engine took, which the reclaim gives back.
	local atImpact = nil

	pcall(function()
		atImpact = npc.soul:GetState("health")
	end)

	-- Subjects the development tooling created take no damage.
	--
	-- An NPC cannot be made unkillable through the engine: `SetMaxHealth`,
	-- `SetStatLevel` and `SetDerivedStat` are absent from a soul, and
	-- `SetState("health", n)` clamps at 100.
	--
	-- So the exemption lives here instead, and it is narrow on purpose: only
	-- entities `tools/dev_subject.lua` spawned are in this table, nothing in
	-- normal play ever puts anything in it, and it is not a setting. Damage is
	-- the only thing skipped. The reaction, the impulse, the sound and every
	-- log line still run, which is what a test of collision feedback needs.
	local exempt = self.ImmortalSubjects and npc.id
			and self.ImmortalSubjects[tostring(npc.id)]

	-- Story characters the game protects are handled further down instead of
	-- here, inside `deal`. Returning early would skip the shield lift and the
	-- reclaim, and the reclaim is most of what keeps them whole: the engine
	-- charges a collision whatever this mod does, and the mod is the only thing
	-- in a position to give it back.
	local protected = self:IsProtectedFromHarm(npc)

	if exempt then
		-- Skipping the mod's own damage is not enough on its own, because the
		-- engine charges a collision too. So the health is put back to what it
		-- was at the impact, after `ImpactDamageDelayMs`, since nothing is
		-- dealt here to wait for.
		local was = nil

		pcall(function()
			was = npc.soul:GetState("health")
		end)

		Script.SetTimer(self.Config.ImpactDamageDelayMs, function()
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

	-- The shield keeps the engine from killing the victim during the wait,
	-- however hurt they are, so the blow below is always the one that kills.
	local function deal()
		-- The shield goes on at the top of this call and comes off here, so
		-- the victim is mortal by the time the line below charges them.
		self:LiftCollisionShield(npc)

		local before = nil

		pcall(function()
			before = npc.soul:GetState("health")
		end)

		-- A protected character is put straight back to the health they had at
		-- the impact and charged nothing, without the reclaim ceiling below,
		-- because this character is not to be harmed. Done here, after the
		-- shield lifts and the body stops, when the engine has finished
		-- charging them.
		if protected then
			local restored = false

			if type(atImpact) == "number" then
				restored = pcall(function()
					npc.soul:SetState("health", atImpact)
				end)
			end

			if self.Config.LogTelemetry then
				self:Log("ImpactDamage " .. self:NameOf(npc)
						.. " tier=" .. tostring(tierName)
						.. " protected=true"
						.. " health=" .. string.format("%.1f", before or -1)
						.. " restoredTo=" .. string.format("%.1f", atImpact or -1)
						.. " ok=" .. tostring(restored))
			end

			return
		end

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
			local ceiling = self.Config.ImpactDamageReclaimCeiling

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
			npc.soul:DealDamage(0, damage)
		end)

		-- Read back rather than subtracted, because whether this call emptied
		-- the victim is the question the whole deferral exists to answer.
		local after = nil

		pcall(function()
			after = npc.soul:GetState("health")
		end)

		-- A victim killed while an animated reaction is still playing is left
		-- standing in it. The game marks them dead, but the interactive action
		-- still owns the body: it holds an idle pose, has no collision, and
		-- walks through walls.
		--
		-- So a death during an interactive action is handed to a ragdoll,
		-- which is where the engine's own death handling would have put them.
		-- Only then: an ordinary death outside an action already works, and
		-- forcing a ragdoll onto it would override whatever the game chose.
		local fatal = type(before) == "number" and before > 0
				and type(after) == "number" and after <= 0

		if fatal then
			-- A death is attributed to the player at once. A survivor's crime
			-- hit waits for `WhenVictimRises`, so a victim on the ground does not
			-- shout crime barks, but a corpse never rises. Without the hit the
			-- `lastHitByPlayer` link (`sb_switch_hitreactions.xml:584`) is never
			-- made and guards find an unattributed corpse rather than a murder.
			-- A dead victim's hit skips the reaction stimulus, so nothing is
			-- shouted.
			if self.Config.CollisionIsCrime and playerEnt then
				local strength = hitStrength
						or (self.HitReactionStrength
							and self.HitReactionStrength[
								self:TierValue("HitStrengthByTier", tierName) or "Tickle"])
						or 0
				self:SendCombatHit(npc, playerEnt, strength)
				npc.hcm_combat_injected = true
			end

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
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end

	-- Fired by the victim's own state, not by a clock: lift the shield and deal
	-- the damage the moment the body stops moving. The shield has to span the
	-- whole throw, because the engine charges the body while it moves.
	--
	-- A walk stagger never moves the body, so it deals immediately.
	if tierName == "Walk" then
		deal()
	else
		self:WhenBodyStops(npc, function(why, waited)
			if self.Config.LogTelemetry then
				self:Log("BodyStopped " .. self:NameOf(npc)
						.. " why=" .. tostring(why)
						.. " waited=" .. tostring(waited) .. "ms")
			end

			deal()
		end)
	end

	return damage
end
