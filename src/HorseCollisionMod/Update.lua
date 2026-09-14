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
-- @release 5.13.0
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

	-- There is no readiness wait any more, and nothing here counts time.
	--
	-- What stood here stamped a deadline per victim and refused every impact
	-- until it passed, with five settings behind it and a watcher polling the
	-- animation state to clear it early. It was wrong in both directions.
	-- It let an impact through mid-fall, because it declared a victim
	-- recovered after 250ms of being in neither reaction state and there is a
	-- 608ms stretch of exactly that while the body is face down between the
	-- fall clip ending and the ragdoll taking hold. And it refused impacts
	-- through the whole of a get-up, which reads as the mod having stopped
	-- working.
	--
	-- Whether a body can take an animation is now `IsVictimFlat`, read from
	-- the victim's own posture at the moment of the impact, and it lives with
	-- the reaction rather than in front of the whole collision. The impact
	-- always lands: a second hit on a downed victim registers and costs them
	-- health, so refusing it only ever lost damage the engine charged anyway.

	-- A lunge belongs to the charge, and this loop stays out of it.
	--
	-- What stood here relabelled a charge as a gallop: the lunge reads about
	-- 5.5 m/s, which scores as a trot, and a trot plays an animated knockdown
	-- rather than the ragdoll a deliberate charge should earn. That was written
	-- when the charge had no detection of its own and the loop was the only
	-- thing that could score it.
	--
	-- `ChargeStrike` now sweeps the corridor itself and carries a `Charge`
	-- tier the whole way down, with its own damage, sound, throw and lockout.
	-- So the relabel bought nothing and cost the separation: every rule written
	-- for a gallop silently governed the charge, and the log called it Gallop.
	--
	-- Standing out entirely is better than scoring alongside the sweep. Two
	-- paths on one collision is what the double hit was, and the contact gate
	-- suppresses the second rather than preventing it.
	if self.RearCharging then
		return
	end

	local tierName = self:GetSpeedTier(speed)

	-- One contact, one impact. A horse mid-pass is still inside the same
	-- collision it has already been charged for, and this is the only thing
	-- that debounces it. It measures the gap between two contacts rather than
	-- a victim's recovery, which is why it outlived the readiness wait.
	if not self:ImpactIsNewContact(npcId, now) then
		return
	end

	local strength = self.HitReactionStrength
	local cfg = self.Config
	local isCombat, combatDetail, playerInDanger = self:IsCombatCollision(npc)

	-- What makes one pass one impact, read by `ImpactIsNewContact` above.
	self.LastScoredHit[npcId] = now

	-- When the last impact of any kind landed, so the airborne probe above can
	-- say whether the horse left the ground off a collision or on its own.
	self.LastImpactAt = now

	-- Past every early return, so only a victim this impact is resolved for is
	-- ever made immortal. `ApplyImpactDamage` lifts it once the body is at
	-- rest, before it charges them.
	--
	-- Never at a walk. A stagger is an animation and never makes the victim a
	-- physical object, so there is no engine collision damage to shield from,
	-- and `ApplyImpactDamage` returns early on a tier worth no damage: the
	-- shield would go on with nothing left to take it off, and the victim
	-- would stand there immortal until the backstop fired.
	if tierName ~= "Walk" then
		self:ShieldFromEngineDamage(npc)
	end

	-- What actually prevents the lockup. A victim under 40 health carrying a
	-- bleeding buff is otherwise taken over by vanilla's auto-cure daycycle,
	-- which stands them in the street playing `PretendingIllness`.
	self:SuppressAutoCure(npc)

	-- Walked once per impact. Every use below wants the same totals, and
	-- enumerating an inventory per use would repeat the work three times.
	local armor = self:ArmorOf(npc)
	local armorImpulse = self:ArmorImpulseScale(armor)

	-- The horse's own contribution, read once per impact for the same reason
	-- the victim's is. Barding is three separate flat effects rather than one
	-- multiplier, and each lands on a different figure: a little more throw, a
	-- little more damage, and a real saving in the horse's stamina, which is
	-- the half a player feels. Coverage is logged because it is what the three
	-- are derived from, and nothing about the rider enters it.
	local bardingCover = self:BardingCoverage(horseEnt)
	local bardingForce = self:BardingForceBonus(horseEnt)

	self:Log("Impact tier=" .. tierName
			.. " speed=" .. string.format("%.2f", speed)
			.. " sampled=" .. string.format("%.2f", sampledSpeed or speed)
			.. (cfg.DiagnoseMisses
					and (" trail=[" .. self:SpeedTrail(self.SpeedHistorySize) .. "]")
					or "")
			.. " armorImpulse=" .. string.format("%.2f", armorImpulse)
			.. " bardingCover=" .. string.format("%.2f", bardingCover)
			.. " bardingForce=" .. string.format("%.2f", bardingForce.knockback)
			.. " " .. combatDetail)

	-- Before the tier branches, so the request goes out ahead of the
	-- reaction animation rather than behind it.
	self:PlayImpactSound(npc, tierName, armor)

	-- Spoken alongside the impact sound and for the same reason: it belongs
	-- to the moment of contact. The combat state is passed because vanilla
	-- refuses a collision bark during a fight and so should this.
	self:BarkCollision(npc, tierName, isCombat)

	-- The rider's own half of the impact. Sent here for the same reason as the
	-- sound: it belongs to the moment of contact, not to whatever the victim
	-- does afterwards. Each of these scales or chooses by tier itself, and
	-- returns false for a tier it has nothing for, so the tier is passed rather
	-- than branched on here.
	self:ShakeRiderCamera(playerEnt, tierName)
	self:BlurRiderView(playerEnt, tierName)

	-- Words before breath, both at the moment of contact, and only one of them
	-- heard because they share a ranked voice gate.
	--
	-- Which words depends on whether this impact is about to kill, and that is
	-- predicted rather than observed. The real answer is not settled until the
	-- body has come to rest and the deferred damage lands, and a line chosen
	-- from that arrives a second and a half after the collision it is about.
	self:BarkRiderOnImpact(playerEnt, tierName,
			self:PredictImpactFatal(npc, tierName, armor, horseEnt), npc)
	self:PlayRiderVocal(playerEnt, tierName)

	-- The ground's half. Spawned at the victim's feet, where they are struck
	-- rather than where they land, because a gallop throws them several
	-- meters and dust that follows the body reads as smoke.
	self:ImpactDust(npc, tierName)

	if tierName == "Walk" then
		-- Only a real fight suppresses the stagger. The combat test is also
		-- true for a victim merely holding a weapon, and a guard on patrol
		-- with a polearm holds his all day, so keying this off the combined
		-- signal meant he could never be staggered at all.
		local suppressed = cfg.SuppressStaggerInCombat and playerInDanger

		if cfg.WalkStagger and not suppressed then
			self:PlayTierReaction(npc, "Walk", velocity, speed,
					armorImpulse, horsePos, horseEnt)
		end

		self:ProbeImpactCost(npc, "Walk", strength.Tickle, armor)
		self:SendHitReaction(npc, horseWuid, strength.Tickle)

		-- After the stagger and the native hit reaction, so a provoked
		-- victim has already played their reaction to this shove and the
		-- fight starts from the shove rather than instead of it.
		self:ProvokeIfAnnoyed(npc, playerEnt)

		self:DrainImpactStamina(horseEnt, playerEnt, "Walk", armor)
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
		self:PlayTierReaction(npc, "Trot", velocity, speed,
				armorImpulse, horsePos, horseEnt)
		self:MarkVictim(npc, "Trot", velocity, speed)
		self:SendHitReaction(npc, horseWuid, strength.MinorInjury)
		self:SendCombatHit(npc, playerEnt, strength.MinorInjury)

		-- Called after the native hit, but calling order is not resolution
		-- order: `SendCombatHit` returns at once and the engine settles its
		-- own trample damage around half a second later. The wait that makes
		-- this mod's damage land last, and so own the killing blow and the
		-- crime attribution with it, is inside `ApplyImpactDamage`.
		self:ApplyImpactDamage(npc, "Trot", armor, playerEnt, horseEnt)
		self:DrainImpactStamina(horseEnt, playerEnt, "Trot", armor)
		return
	end

	if tierName == "Gallop" then
		-- Sampled before the impulse, not after. Ragdoll can cost the
		-- victim health of its own, and a probe that reads afterwards
		-- folds that into the starting figure instead of the delta.
		self:ProbeImpactCost(npc, "Gallop", strength.MajorInjury, armor)
		self:PlayTierReaction(npc, "Gallop", velocity, speed,
				armorImpulse, horsePos, horseEnt)
		self:MarkVictim(npc, "Gallop", velocity, speed)
		self:SendHitReaction(npc, horseWuid, strength.MajorInjury)
		self:SendCombatHit(npc, playerEnt, strength.MajorInjury)

		-- Called after the native hit, but calling order is not resolution
		-- order: `SendCombatHit` returns at once and the engine settles its
		-- own trample damage around half a second later. The wait that makes
		-- this mod's damage land last, and so own the killing blow and the
		-- crime attribution with it, is inside `ApplyImpactDamage`.
		self:ApplyImpactDamage(npc, "Gallop", armor, playerEnt, horseEnt)
		self:DrainImpactStamina(horseEnt, playerEnt, "Gallop", armor)
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

	-- The horse leaving the ground, reported when it happens and never
	-- otherwise.
	--
	-- The rider watched the horse thrown about five meters up and away off an
	-- impact, and nothing in the log had anything to say about it, because the
	-- mod records the victim's body in detail and the horse's own motion not
	-- at all. There is no cost to this: the detection loop already reads the
	-- horse's velocity every hundred milliseconds for the speed history, and
	-- this only decides whether to write a line about a reading it already
	-- has.
	--
	-- Vertical speed rather than height, because height off a slope is
	-- ordinary and a horse moving upward at several meters a second is not. A
	-- gallop up a hill reads well under the threshold.
	if velocity and self.Config.LogTelemetry then
		local vz = velocity.z or 0
		local trigger = self.Config.HorseAirborneVz or 2.5
		local last = self.HorseAirborneAt or 0
		local now = self:TimeMs()

		if vz >= trigger and (now - last) >= 1000 then
			self.HorseAirborneAt = now

			self:Log("HorseAirborne vz=" .. string.format("%.2f", vz)
					.. " speed=" .. string.format("%.2f", speed)
					.. " sinceImpactMs=" .. tostring(
					self.LastImpactAt and (now - self.LastImpactAt) or -1))
		end
	end

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

			-- The dog is already found here, so the collision filtering that
			-- stops him carrying the horse rides along with the check that
			-- keeps him from being trampled. It runs once per dog per
			-- generation and does nothing on any later pass.
			if isMutt then
			end

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
					-- Ahead of contact, while they are still in front of the
					-- horse, so vanilla's collision bark is already closed off
					-- by the time bodies touch.
					self:HushVanillaBark(ent)

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

	-- The horse's real speed, derived from where it has been rather than asked
	-- for, because the rear's standstill gate cannot trust `GetVelocity`.
	pcall(function()
		local horseEnt = XGenAIModule.GetEntityByWUID(
				player.player:GetPlayerHorse())

		self:TrackHorseSpeed(horseEnt)
	end)

	local success, err = pcall(function()
		self:SafeUpdate()
	end)

	if not success then
		self:Log("CRITICAL ERROR IN UPDATE TIMER: " .. tostring(err))
	end
end
