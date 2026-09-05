--- Update: the loop that finds collisions, and what it does with one.
--
-- The detection loop runs ten times a second while the player is mounted. It
-- reads the horse's velocity, sweeps a footprint forward proportional to
-- speed, and for every human inside it decides a tier and dispatches the
-- reaction. Everything else in this mod is called from here.
--
-- `UpdateTimer` is what keeps it running, and it carries the generation guard.
-- Re-executing the entry point builds a fresh `HorseCollisionMod` table, and
-- without that guard every reload would leave another loop sweeping for
-- collisions ten times a second, all of them writing to the same cooldown
-- table.
--
-- `SafeUpdate` is wrapped in `pcall` by its caller for a reason worth keeping:
-- an error thrown inside a timer callback kills the loop silently, and the mod
-- would simply stop working with nothing in the log to say so.
--
-- This file was moved last, because it calls into every other part and a
-- mistake here would have been indistinguishable from a mistake in whichever
-- part it called.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Update
-- @author jrandall54
-- @release 4.11.0
--- Applies the appropriate reaction for one collision.
--
-- Enforces the per-victim cooldown, then dispatches on gait.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number speed speed to score the impact at, in meters per second
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
-- @tparam userdata horseWuid WUID of the horse
-- @tparam number sampledSpeed speed read on this tick, recorded in the log so
--   the correction for collision deceleration stays visible
function HorseCollisionMod:TriggerCollision(npc, velocity, speed, horseEnt, playerEnt,
		horseWuid, sampledSpeed)
	local npcId = tostring(npc.id)
	local now = self:TimeMs()

	-- Read here rather than passed in, because the detection loop's copy is
	-- a tick old by the time a reaction is dispatched and the impulse needs
	-- to know which side of the horse the victim is on right now.
	local horsePos = nil

	pcall(function()
		horsePos = horseEnt:GetPos()
	end)

	-- The detection sphere is tested ten times a second, so without a
	-- per-victim cooldown a single pass through a crowd would restart the
	-- same NPC's reaction every tick and they would never finish staggering.
	--
	-- The wait runs until the victim can act again rather than for a fixed
	-- time after the last impact. Someone knocked down is still on the
	-- ground long after a stagger would have finished, and an impact landing
	-- while they are down plays no reaction, because every reaction is a
	-- standing animation, and usually costs them no health either.
	--
	-- Nothing in the engine reports whether an actor is on the ground. The
	-- entity's angles stay upright through a ragdoll and no ScriptBind
	-- exposes the state, so the recovery is timed rather than observed, and
	-- it is timed from the impulse the mod applied itself.
	local readyAt = self.RecentHits[npcId]

	-- A deadline further away than the longest cooldown that can be written
	-- was not written against this clock. `System.GetCurrTime` is persisted
	-- in the save, so loading an earlier one moves it backwards by however
	-- far the save was rewound, and every victim hit before that point is
	-- then locked out for the length of the rewind. Deadlines up to 239
	-- seconds ahead were read out of a running game against a configured
	-- maximum of 6.
	--
	-- Discarding the stamp rather than trusting it also covers entity ids
	-- being reused across a load, which otherwise locks out a victim that
	-- was never hit at all.
	if readyAt then
		local longest = math.max(self.Config.HitCooldownMs,
				self.Config.KnockdownRecoveryMs)

		if readyAt - now > longest then
			self.RecentHits[npcId] = nil
			readyAt = nil
		end
	end

	if readyAt and now < readyAt then
		-- Logged outside the miss diagnostic. It fires only when a victim
		-- is hit again while still down, which is a handful of lines rather
		-- than the thousands that diagnostic writes, and it is the only
		-- evidence that the wait is doing anything.
		if self.Config.LogTelemetry then
			self:Log("Recovering " .. self:NameOf(npc)
					.. " for=" .. tostring(readyAt - now) .. "ms")
		end

		return
	end

	local tierName = self:GetSpeedTier(speed)
	local strength = self.HitReactionStrength
	local cfg = self.Config
	local combatScale = 1.0
	local isCombat, combatDetail, playerInDanger = self:IsCombatCollision(npc)

	-- Only the knockdown tiers put anyone on the ground, so the walk tier
	-- keeps the shorter wait.
	local recovery = cfg.HitCooldownMs

	if tierName ~= "Walk" then
		recovery = cfg.KnockdownRecoveryMs
	end

	self.RecentHits[npcId] = now + recovery

	-- What actually prevents the lockup. A victim under 40 health carrying a
	-- bleeding buff is otherwise taken over by vanilla's auto-cure daycycle,
	-- which stands them in the street playing `PretendingIllness`.
	self:SuppressAutoCure(npc)

	-- Walked once per impact. Every use below wants the same totals, and
	-- enumerating an inventory per use would repeat the work three times.
	local armor = self:ArmorOf(npc)
	local armorImpulse = self:ArmorImpulseScale(armor)
	local armorStamina = self:ArmorStaminaScale(armor)

	if isCombat then
		combatScale = cfg.CombatStaminaMultiplier
	end

	self:Log("Impact tier=" .. tierName
			.. " speed=" .. string.format("%.2f", speed)
			.. " sampled=" .. string.format("%.2f", sampledSpeed or speed)
			.. (cfg.DiagnoseMisses
					and (" trail=[" .. self:SpeedTrail(self.SpeedHistorySize) .. "]")
					or "")
			.. " combatScale=" .. string.format("%.1f", combatScale)
			.. " armorImpulse=" .. string.format("%.2f", armorImpulse)
			.. " armorStamina=" .. string.format("%.2f", armorStamina)
			.. " " .. combatDetail)

	-- Before the tier branches, so the request goes out ahead of the
	-- reaction animation rather than behind it.
	self:PlayImpactSound(npc, tierName, armor)

	if tierName == "Walk" then
		-- Only a real fight suppresses the stagger. The combat test is also
		-- true for a victim merely holding a weapon, and a guard on patrol
		-- with a polearm holds his all day, so keying this off the combined
		-- signal meant he could never be staggered at all.
		local suppressed = cfg.SuppressStaggerInCombat and playerInDanger

		if cfg.WalkStagger and not suppressed then
			self:PlayReaction(npc, velocity, speed, "hcm_stagger_")
		end

		self:ProbeImpactCost(npc, "Walk", strength.Tickle, armor)
		self:SendHitReaction(npc, horseWuid, strength.Tickle)

		-- After the stagger and the native hit reaction, so a provoked
		-- victim has already played their reaction to this shove and the
		-- fight starts from the shove rather than instead of it.
		self:ProvokeIfAnnoyed(npc, playerEnt)

		self:DrainHorseStamina(horseEnt, playerEnt,
				cfg.StaminaDrainWalk * combatScale * armorStamina)
		return
	end

	if tierName == "Trot" then
		-- Sampled before the impulse, not after. Ragdoll can cost the
		-- victim health of its own, and a probe that reads afterwards
		-- folds that into the starting figure instead of the delta.
		self:ProbeImpactCost(npc, "Trot", strength.MinorInjury, armor)

		-- An animated knockdown never makes the victim a physics object, so
		-- the horse cannot strike them the way it does at a gallop. It does
		-- not follow that the tier is free: measured, the engine still takes
		-- 6 to 8 from an unarmored victim here and up to 12 from a guard, so
		-- something other than the trample is charging for it. The
		-- ragdoll is kept because it is what shipped, and because an
		-- animation does not carry the impact's momentum.
		if cfg.TrotReaction == "knockdown" then
			self:PlayReaction(npc, velocity, speed, "hcm_knockdown_")
		elseif cfg.TrotReaction == "fall" then
			self:PlayReaction(npc, velocity, speed, "hcm_fall_")
		else
			self:Ragdoll(npc, velocity, speed, 0.6 * armorImpulse, horsePos)
		end
		self:MarkVictim(npc, "Trot", velocity, speed)
		self:SendHitReaction(npc, horseWuid, strength.MinorInjury)
		self:SendCombatHit(npc, playerEnt, strength.MinorInjury)

		-- After the native hit, so the engine's own charge for the collision
		-- lands first and the log reads in the order the victim experiences it.
		self:ApplyImpactDamage(npc, "Trot", armor, playerEnt)
		self:DrainHorseStamina(horseEnt, playerEnt,
				cfg.StaminaDrainTrot * combatScale * armorStamina)
		return
	end

	if tierName == "Gallop" then
		-- Sampled before the impulse, not after. Ragdoll can cost the
		-- victim health of its own, and a probe that reads afterwards
		-- folds that into the starting figure instead of the delta.
		self:ProbeImpactCost(npc, "Gallop", strength.MajorInjury, armor)
		self:Ragdoll(npc, velocity, speed, 1.0 * armorImpulse, horsePos)
		self:MarkVictim(npc, "Gallop", velocity, speed)
		self:SendHitReaction(npc, horseWuid, strength.MajorInjury)
		self:SendCombatHit(npc, playerEnt, strength.MajorInjury)

		-- After the native hit, so the engine's own charge for the collision
		-- lands first and the log reads in the order the victim experiences it.
		self:ApplyImpactDamage(npc, "Gallop", armor, playerEnt)
		self:DrainHorseStamina(horseEnt, playerEnt,
				cfg.StaminaDrainGallop * combatScale * armorStamina)
		return
	end
end

--- One tick of collision detection.
--
-- Bails out early unless the player is mounted and moving at least at
-- walking pace, then tests every entity within `HitRadius` of the horse.
--
-- Every engine call is wrapped in `pcall`, because entities can be unstreamed
-- or partially initialized at any moment and an uncaught error would kill the
-- timer loop for the rest of the session.
function HorseCollisionMod:SafeUpdate()
	if type(player) == "nil"
			or (not player)
			or type(player.human) == "nil"
			or type(player.player) == "nil" then
		return
	end

	local isMounted = false

	pcall(function()
		isMounted = player.human:IsMounted()
	end)

	if not isMounted then
		return
	end

	local horseWuid = nil

	pcall(function()
		horseWuid = player.player:GetPlayerHorse()
	end)

	if not horseWuid then
		return
	end

	local horseEnt = nil

	pcall(function()
		horseEnt = XGenAIModule.GetEntityByWUID(horseWuid)
	end)

	if not horseEnt then
		return
	end

	local velocity = nil

	pcall(function()
		if horseEnt.GetVelocity then
			velocity = horseEnt:GetVelocity()
		end

		if not velocity and player.GetVelocity then
			velocity = player:GetVelocity()
		end
	end)

	local speed = self:VectorLength(velocity)
	self:TrackSpeed(speed)

	local impactSpeed = self:ImpactSpeed()

	-- Below walking pace nothing can happen, so the loop normally stops here
	-- before looking at a single entity. While diagnosing it keeps going, or
	-- an impact lost because the collision itself slowed the horse would leave
	-- no trace at all.
	if impactSpeed < self.Config.SpeedWalk and not self.Config.DiagnoseMisses then
		return
	end

	local horsePos = nil
	local horseForward = nil

	pcall(function()
		horsePos = horseEnt:GetPos()
	end)

	pcall(function()
		if horseEnt.GetDirectionVector then
			horseForward = horseEnt:GetDirectionVector(1)
		end
	end)

	if not horsePos or not horseForward then
		return
	end

	-- The broad phase, which is the only expensive call in this loop and is
	-- reused between ticks while the horse has not moved far enough for the
	-- answer to have changed. `EntitiesNearHorse` documents why that is safe.
	local hitEnts = self:EntitiesNearHorse(horsePos, self:TimeMs())

	if type(hitEnts) ~= "table" then
		return
	end

	for _, ent in pairs(hitEnts) do
		local isCandidate = (ent
				and type(ent) == "table"
				and ent.id
				and ent.id ~= player.id
				and ent.id ~= horseEnt.id)

		if isCandidate then
			local isMutt = false

			-- Henry's dog follows close enough to be caught constantly, and
			-- trampling him on every ride is nobody's idea of immersion. He
			-- is identified by entity name because dogs share the generic
			-- NPC class.
			pcall(function()
				local entName = ent:GetName()

				if entName and string.find(entName, "dogCompanion") then
					isMutt = true
				end
			end)

			local isProtected = (self.Config.ProtectMutt and isMutt)

			if not isProtected then
				local isHuman = false

				-- The sphere returns everything nearby: crates, doors, loose
				-- items, animals. Humans are named by class, and there are
				-- three: men spawn as NPC, women as NPC_Female, and the rider
				-- as Player. Naming them is what keeps this a human filter.
				--
				-- A faction fallback stood here and was wrong in both
				-- directions. Dogs carry `esFaction`, so a guard dog was
				-- given a human knockdown fragment on a dog skeleton, which
				-- is a fragment that cannot resolve. And women passed only
				-- through that fallback rather than by class, which is a
				-- fragile way to reach half the population and sits behind a
				-- long run of female-specific faults in this mod.
				pcall(function()
					isHuman = (ent.class == 'NPC'
							or ent.class == 'NPC_Female'
							or ent.class == 'Player')
				end)

				if not isHuman then
					-- Deliberately silent. The diagnostic exists to find
					-- people the mod failed to react to, and an item is never
					-- one. The player's own holster and any dropped weapon
					-- ride along inside the search radius permanently, so
					-- logging these buried the human misses entirely and a
					-- distance gate did not help: the holster is on the
					-- player.
				elseif not ent.actor and self.Config.DiagnoseMisses then
					self:LogRejection(ent, "no-actor",
							"class=" .. tostring(ent.class))
				end

				if isHuman and ent.actor then
					local isDead = false

					-- Corpses are already ragdolls. Reacting to them would
					-- twitch bodies around and re-trigger every tick.
					if ent.IsDead then
						pcall(function()
							isDead = ent:IsDead()
						end)
					end

					local inFootprint = self:IsInHorseFootprint(ent, horsePos,
							horseForward, speed)

					-- The diagnostic branches are guarded rather than relying
					-- on `LogRejection` returning early, because their
					-- arguments are built before the call: the footprint
					-- detail re-runs the whole geometry a second time, and
					-- this loop sees every nearby entity thirty times a
					-- second.
					if isDead or not inFootprint
							or impactSpeed < self.Config.SpeedWalk then
						if self.Config.DiagnoseMisses then
							if isDead then
								self:LogRejection(ent, "dead", "")
							elseif not inFootprint then
								self:LogRejection(ent, "outside-footprint",
										self:FootprintDetail(ent, horsePos,
												horseForward, speed))
							else
								self:LogRejection(ent, "below-walk-speed",
										string.format("impact=%.2f sampled=%.2f",
												impactSpeed, speed))
							end
						end
					else
						self:TriggerCollision(ent, velocity, impactSpeed, horseEnt,
								player, horseWuid, speed)
					end
				end
			end
		end
	end
end

--- Reschedules itself every 100 ms and runs one detection tick.
--
-- The tick number guards against duplicate loops. Each load screen starts a
-- new loop, and any loop whose number no longer matches the current one stops
-- on its next iteration, so reloading a save leaves no stale timers running.
--
-- @tparam number assignedTick the loop generation this timer belongs to
function HorseCollisionMod:UpdateTimer(assignedTick)
	if self.TimerTick ~= assignedTick then
		return
	end

	-- The next tick is booked before any work is done. If detection ever
	-- throws in a way pcall cannot contain, the loop still survives; booking
	-- afterwards would end the mod for the rest of the session.
	--
	-- The interval comes from `TickSeconds`, which the forward sweep is also
	-- computed from. Those were separate figures until the impact sound made
	-- the difference audible: the timer was a hardcoded 100 and the sweep
	-- assumed whatever `TickSeconds` said, so the two agreed only by accident.
	Script.SetTimer(self:TickMs(), function()
		HorseCollisionMod:UpdateTimer(assignedTick)
	end)

	local success, err = pcall(function()
		self:SafeUpdate()
	end)

	if not success then
		self:Log("CRITICAL ERROR IN UPDATE TIMER: " .. tostring(err))
	end
end
