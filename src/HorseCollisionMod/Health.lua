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
-- @release 5.21.2
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
	-- state test reports `neverDown` on exactly the impacts that threw someone
	-- hardest and waits out its ceiling instead of measuring them.
	local restPoll = self.RestPollMs
	local restStill = self.RestStillMeters
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
-- Applied through `soul:DealDamage`, which is vanilla's own call:
-- `deadBody.xml` and `questUtils.xml` use it to kill an entity outright and
-- `npc_roebuck.xml` to wound one. Stamina is left at zero because the horse's
-- side of the impact already debits the rider and the victim's stamina is not
-- what this models.
--
-- **It takes two arguments and no more.** `C_ScriptBindSoul` declares
-- `DealDamage(float stamina, float health)`, so an attacker passed as a third
-- argument is accepted by Lua and discarded by the engine. This call is a raw
-- subtraction on the soul: no attacker, no hit type, no hit data, and nothing
-- the victim's behavior tree ever sees.
--
-- That has a consequence beyond tidiness. Vanilla's death cry is raised inside
-- `IsDeadCheck -> Then` in `sb_switch_hitreactions.xml`, while a hit is being
-- processed, because the engine applies damage as part of resolving that hit.
-- Here the only hit the victim's brain receives is the one sent at the moment
-- of impact, when they are still alive, so the check finds them alive and
-- nothing looks again. A victim the mod kills therefore dies silently, and
-- that is a property of this call rather than of the bark system.
--
-- Attribution is handled separately, by the `combat:hit` that `Crime.lua`
-- sends, and by the ordering that makes this damage land last. With the crime
-- switch off the damage lands unattributed, so a collision test is not
-- interrupted by guards. This does not make a trampling death crime free on
-- its own: the engine attributes the trample itself, and that is not reachable
-- from here.
--
-- @tparam table npc victim entity
-- @tparam string tierName the tier the impact scored
-- @tparam table armor totals from `ArmorOf`
-- @tparam[opt] table playerEnt the player, named as the attacker when crime is on
-- @tparam[opt] table horseEnt the player's horse, for the barding bonus
-- @treturn number the damage dealt, or 0 when nothing was
--- Whether this impact is about to kill, worked out at the moment of contact.
--
-- Exists so Henry can react on time. `ApplyImpactDamage` cannot answer this: it
-- defers its damage until the thrown body comes to rest, up to a second after
-- contact, deliberately, so that the mod's blow lands last and owns the kill.
-- Choosing the rider's line from that resolved state produced words a second
-- and a half after the collision, detached from it, and a walk stagger -- whose
-- tier is worth no damage at all and so returns before dealing any -- never got
-- a line whatsoever.
--
-- The arithmetic is `ApplyImpactDamage`'s own, taken at the **top** of the
-- variance roll rather than at its center. Predicting from the center reads the
-- average outcome as the whole outcome and misses the most ordinary kill in the
-- game: a gallop into a healthy villager intends 95 * 1.00 * 1.02 = 96.9 against
-- 100 health, which is survivable on average and fatal on most rolls once the
-- spread is applied. Three of seven kills in one ride got no line for exactly
-- that reason, and the error was invisible in an earlier check because those
-- victims were already hurt.
--
-- So the question asked here is "can this impact kill", not "will it on
-- average". The cost of being wrong in this direction is a death line on a
-- victim who survives, which reads as Henry misjudging a blow; the cost in the
-- other direction is silence on a kill, which reads as the feature being
-- broken.
--
-- The engine's own trample damage is not added in. The mod reclaims it and
-- restores the health the victim had at impact, so the mod's own figure is what
-- decides the death.
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
-- path. `soul:DealDamage` charges health directly, and was measured taking
-- Bernard from 100 down to 66 over three gallops. It ignores the game's own
-- immortality flag while doing it, so nothing downstream was going to catch
-- this either.
--
-- The marker is readable, and it is a flag rather than a name. Such characters
-- carry the VIP protection derived stats; an ordinary guard carries none of
-- them. Measured on the pair, side by side:
--
--     rat_bernard  apr=1 imm=1 upr=1 ppr=1
--     villageGuard apr=0 imm=0 upr=0 ppr=0
--
-- `apr` is the one read, and the distinction from `imm` matters.
--
-- `apr` is attack protection, granted by the `vip_attackprot` buff. It is the
-- flag the game marks a story character with, and nothing in this mod writes
-- it. `imm` is generic immortality, and it is the same flag
-- `ShieldFromEngineDamage` grants **every** victim at the moment of contact, so
-- it cannot be used to recognize anybody: reading it here reported every victim
-- as protected, and a villager survived six gallops logging `protected=true`
-- while reading `apr=0 imm=0` at rest.
--
-- The cost of reading `apr` alone is a character a quest has made immortal
-- without also granting attack protection. That combination has not been seen,
-- and covering it would mean reintroducing the flag this mod contaminates.
--
-- Reading the flag rather than keeping a list of names is what makes this
-- cover every character the game protects, including the ones protected only
-- for the span of one quest, without the mod having to know who they are.
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

function HorseCollisionMod:ApplyImpactDamage(npc, tierName, armor, playerEnt, horseEnt)
	if not self.Config.ImpactDamage or not npc or not npc.soul then
		return 0
	end

	-- The settings file wins, and the table on the module is the fallback.
	-- These figures are the mod's account of what each kind of collision is
	-- worth, so they belong where a player or a test can reach them rather
	-- than compiled in.
	local base = self:TierValue("ImpactDamageByTier", tierName)

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

	-- Story characters the game protects are handled further down instead of
	-- here, inside `deal`. Returning early would skip the shield lift and the
	-- reclaim, and the reclaim is most of what keeps them whole: the engine
	-- charges a collision whatever this mod does, and the mod is the only thing
	-- in a position to give it back.
	local protected = self:IsProtectedFromHarm(npc)

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

	-- Nothing is timed here any more, and the local that used to hold a delay
	-- was read into and never used: the wait below is `WhenBodyStops`, which
	-- watches the body rather than counting. `ImpactDamageDelayMs` survives for
	-- the immortal-subject restore above, which has no body to watch because
	-- the whole point of that path is that nothing about the victim changed.
	--
	-- Waiting is right only while the engine cannot land the killing blow.
	--
	-- The delay exists so the engine's collision resolves first and the mod
	-- lands last, which puts the death under the mod's attribution and lets
	-- `CollisionIsCrime` govern it.
	--
	-- Nothing here tries to work out whether this impact will be lethal any
	-- more. That prediction, and the rushing and rounding-up it drove, existed
	-- because the engine could take a victim during the wait and the crime went
	-- to whoever landed the last blow. It could not be made reliable: it had to
	-- be right about a number it does not control, and when it was wrong the
	-- rider was charged with murder at random.
	--
	-- The shield settles it instead of predicting it. A victim the horse strikes
	-- is immortal from the moment of contact until this call lifts it, so the
	-- engine cannot reach them during the wait however hurt they are, and the
	-- blow below is always the one that kills.

	local function deal()
		-- The shield goes on at the top of this call and comes off here, so
		-- the victim is mortal by the time the line below charges them.
		self:LiftCollisionShield(npc)

		local before = nil

		pcall(function()
			before = npc.soul:GetState("health")
		end)

		-- A protected character is put straight back to the health they had at
		-- the impact and charged nothing, so the collision leaves no mark on
		-- them at all.
		--
		-- Restored without the ceiling the ordinary reclaim below applies. That
		-- ceiling exists so a horse walking past cannot heal somebody an archer
		-- shot in the meantime, and it is a sensible bound on handing back an
		-- unknown. Here there is nothing to bound: this character is not to be
		-- harmed, and a large loss during the window is far more likely to be
		-- this collision than a coincidence.
		--
		-- Done here rather than at the top of the call so that the shield has
		-- already come off and the body has already stopped moving, which is
		-- the point after which the engine has finished charging them.
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
			npc.soul:DealDamage(0, damage)
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
		local fatal = type(before) == "number" and before > 0
				and type(after) == "number" and after <= 0

		if fatal then
			-- The moment the mod's own damage killed somebody, which is the
			-- only place the death is attributable to the mod rather than to
			-- anything else that might have finished them.
			self:BarkDeath(npc)

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

	-- Fired by the victim's own state, not by a clock.
	--
	-- Shield, then lift and damage the moment the body stops moving.
	--
	-- The shield goes on at the impact and has to span everything the engine
	-- charges the victim for, which is the whole time the body is being thrown:
	-- measured between the impact and the body coming to rest, victims lost
	-- between 6 and 32 health, and six of ten were driven onto the clamp. Lift
	-- it before that is over and those are engine kills, charged to the rider.
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
