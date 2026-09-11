--- Reaction: making a victim visibly respond to being ridden into.
--
-- The three ways a collision reaches the victim's body, in ascending force.
-- `SendHitReaction` posts the native brain message, which feeds the victim's
-- perception but drives no animation and does not cause the vanilla bark.
-- `PlayReaction` runs one of this mod's own clips through
-- `actor:StartInteractiveActionByName`, the only call that moves an actor's
-- body from Lua. `Ragdoll` and `ImpulseVictim` hand the body to physics
-- instead, which is what the faster tiers use.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. The clip names are built from
-- the direction `Detection.lua` returns, and the reaction strengths are the
-- engine enums in `Enums.lua`, so both are read through `self` at call time
-- rather than captured when this file loads.
--
-- @module HorseCollisionMod.Reaction
-- @author jrandall54
-- @release 5.2.2
--- Posts the native `hitReaction` message to the victim's brain.
--
-- It feeds the victim's perception, so the reaction registers as something
-- the game knows happened rather than as an animation played over the top.
-- It does **not** drive animation.
--
-- It does not produce the collision bark either. Vanilla barks on a mounted
-- collision on its own, and does so with this message switched off.
--
-- Delivery is best effort. The receiving handler is declared `Atomic="true"`
-- and drops messages when busy, so nothing here may depend on a given
-- message arriving.
--
-- @tparam table npc victim entity
-- @tparam userdata horseWuid WUID of the horse, sent as the attacker
-- @tparam number strength a `HitReactionStrength` value
function HorseCollisionMod:SendHitReaction(npc, horseWuid, strength)
	if not self.Config.SendHitReaction then
		return
	end

	pcall(function()
		-- Brain messages carry their arguments as a "key(value), key(value)"
		-- string rather than a table.
		local values = "hitStrength(" .. tostring(strength)
				.. "), hitType(" .. tostring(self.HitReactionType.Collision) .. ")"

		-- The horse is named as the attacker, not Henry. That matches what
		-- the engine does for a trample, and the victim's brain resolves the
		-- rider from the horse itself when assigning blame.
		if horseWuid and Framework and Framework.WUIDToMsg then
			values = "attacker(" .. Framework.WUIDToMsg(horseWuid) .. "), " .. values
		end

		XGenAIModule.SendMessageToEntity(npc.id, "hitReaction", values)
	end)
end


--- Plays one of this mod's reactions on a victim.
--
-- Calls `actor:StartInteractiveActionByName` with a name this mod adds to the
-- animation database, chosen by joining `prefix` to the impact direction. See
-- the module header for why this is the only call that works.
--
-- The return value reports whether the call was accepted, which is **not**
-- the same as the animation playing: an unrecognized name is accepted and
-- then aborts within a frame. Only in-game observation confirms playback.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number speed horse speed in meters per second
-- @tparam string prefix the reaction family, `hcm_stagger_` at walk or
--   `hcm_knockdown_` at trot, completed with the impact direction
-- @treturn boolean true when the call was accepted without error
function HorseCollisionMod:PlayReaction(npc, velocity, speed, prefix)
	if not npc.actor or type(npc.actor.StartInteractiveActionByName) ~= "function" then
		return false
	end

	-- GetImpactDir speaks the engine's "so_" vocabulary; the database entries
	-- this mod adds are named without that prefix, so strip it.
	local dir = self:GetImpactDir(npc, velocity, speed)

	-- The engine's vocabulary is `so_left`; this mod's option names and its
	-- per-direction tables are keyed on the bare word. Stripping it once and
	-- using the result everywhere avoids a table lookup silently missing and
	-- falling back, which is how every direction ended up sharing one
	-- ragdoll timing while appearing to have four.
	local side = string.gsub(dir, "so_", "")
	local action = prefix .. side


	-- Gender is logged because the female animation set has no
	-- AnimationControlled fragment, so female victims accept the call and
	-- play nothing. Without this the misses look random.
	local gender = "?"

	pcall(function()
		if npc.soul and npc.soul.GetGender then
			gender = tostring(npc.soul:GetGender())
		end
	end)

	-- Recorded before the action seizes the body, because that is the last
	-- moment the victim's own activity is still readable. `ReplanIfStranded`
	-- compares against it to tell a victim who has resumed from one left
	-- standing.
	pcall(function()
		self.VictimActivity[tostring(npc.id)] = tostring(npc.actor:GetCurrentAnimationState())
	end)

	local ok, err = pcall(function()
		-- The second argument is the object being interacted with. There is
		-- no object in a collision, so the victim is passed as its own
		-- target; the animation needs no alignment to anything external.
		npc.actor:StartInteractiveActionByName(action, npc.id, true, 1)
	end)

	-- Deferred by a tick for the same reason the ragdoll impulse is: the
	-- action has to have started before anything it sets can be overridden.
	-- Repeated rather than asked once.
	--
	-- One call at 50 ms is right in principle: an interactive action applies
	-- its fragment's movement layer as it starts, so an earlier call is
	-- overwritten. But a fragment can apply that layer again as it blends
	-- between clips, and a single release is then undone. Victims were still
	-- being carried through walls occasionally with the call reporting
	-- success, which is what that looks like from outside.
	--
	-- Cheap to repeat: the call is idempotent, and a handful of attempts over
	-- the first part of the reaction costs nothing next to the loop that found
	-- the victim in the first place.
	if self.Config.ReleaseAnimationMovement then
		local generation = self.TimerTick
		local attempts = self.Config.ReleaseMovementAttempts or 4
		local gap = self.Config.ReleaseMovementGapMs or 80

		for index = 1, attempts do
			Script.SetTimer(50 + ((index - 1) * gap), function()
				if generation == self.TimerTick then
					self:ReleaseActorMovement(npc, "victim")
				end
			end)
		end
	end

	-- The fragment hands the body to physics itself, partway through the fall.
	--
	-- Each `hcm_fall_*` option carries a Ragdoll ProcLayer at its own ExitTime,
	-- with `Sleep` 1 and `Stiffness` 500 taken from the `HitDeath` option that
	-- drops a rider off a horse. Mannequin owns the timing, so this mod does not
	-- have to know how long any clip runs for.
	--
	-- The handover belongs during the fall rather than after it. A victim whose
	-- clip runs out stands up and re-enters their activity first, and a ragdoll
	-- arriving then evicts them from it, which the smart object does not undo.
	--
	-- What remains here is the wait for that ragdoll to resolve, because the
	-- rebuild that follows has to land after it. A victim can leave the ragdoll
	-- upright and still have no plan, and only the rebuild gives them one.
	-- Only the fall carries this. The knockdown and stagger prefixes play
	-- their clip and nothing follows, so a victim of one stands up wherever
	-- they finished, facing whatever direction the animation left them, with
	-- no activity to return to. The innkeeper leaning on nothing, facing the
	-- wrong way, is what that looks like.
	--
	-- The wait here is for a ragdoll to resolve, and only the fall fragments
	-- carry a Ragdoll ProcLayer, so extending this to the other prefixes needs
	-- a different signal rather than the same call. Until then both tiers that
	-- can knock someone down default to "fall".
	if prefix == "hcm_fall_" then
		self:TraceRecovery(npc, action)
		self:WatchTurn(npc, action)

		local generation = self.TimerTick

		self:WhenRagdollResolves(npc, function(state, waitedForBody)
			if generation ~= self.TimerTick then
				return
			end

			self:FinishRecovery(npc, action, state, waitedForBody)
		end)
	end

	self:Log("Reaction action=" .. action
			.. " gender=" .. gender
			.. " ok=" .. tostring(ok)
			.. " err=" .. tostring(err))

	return ok
end

--- Sets a ragdolled victim's physical mass, so the horse's own collision
--- does the work.
--
-- What throws a victim at gallop is the engine resolving a collision between
-- the horse, 480 kg at gravity -30, and the body. Nothing this mod adds on
-- top of that collision moves the body: an impulse and a set velocity produce
-- the same distribution across three rides.
--
-- Armor cannot matter while every human weighs the same. `GetMass` answers
-- **80 for every human including the player**, so the horse hits an identical
-- mass whether the target is a peasant or a man in mail.
--
-- `pe_simulation_params` carries `mass` beside the `damping` and `min_energy`
-- that `DampVictim` already sets through the same group. Changing it changes
-- what the horse is hitting, and the engine does the rest.
--
-- **It only takes while ragdolled.** Setting mass on a living entity is
-- accepted and ignored: measured, a value of 300 written to an actor on the
-- `alive` profile left `GetMass` reading 80, and the same write to the same
-- actor ragdolled read back 300.
--
-- Nothing here is written back. It does not need to be: standing up
-- re-physicalizes the actor as a living entity and the engine restores its own
-- 80. Measured on a guard written to 2543 kg, which read that figure while
-- down and 80 once it was walking again.
--
-- ### The coupling is weak, which is the whole design problem
--
-- The throw goes as roughly `mass ^ -0.185`, measured across a fiftyfold flat
-- comparison at p = 0.012. Doubling a victim's mass shortens the throw by 12%,
-- so a visible difference between armor and cloth costs a spread around a
-- hundredfold, and `RagdollMassArmorScaled` on its own, which is a 3.4x
-- spread, is worth nothing that can be seen. `RagdollMassArmorExponent` is
-- what buys the spread; see the config comments for which number does what.
--
-- ### Timing
--
-- The mass has to be in place before the collision resolves. The body is not
-- physicalized at the moment of contact, which is why the impulse path waits
-- `ImpulseDelayMs`, and a horse at ten meters per second covers a centimeter
-- a millisecond. So this retries on a short ladder rather than guessing one
-- delay, takes the first attempt that sticks, and logs which one that was
-- together with how far the victim had already traveled by then. Every
-- impact measured has taken, almost all at 16 ms with the victim still within
-- 8 cm of where they stood, so the write beats the horse.
--
-- @tparam table npc victim entity
-- @tparam number armorScale the tier's armor multiplier, high for an
--   unarmored target and low for one in mail
function HorseCollisionMod:MassVictim(npc, armorScale, onTook)
	local base = self.Config.RagdollMass or 0

	-- Zero means "do not touch the mass", and it must still hand control on.
	--
	-- This returned outright, which reads as harmless and is not: `onTook` is
	-- what fires the impulse, the brake and the damping, so a zero here
	-- silently removed every throw in the mod while the settings file
	-- described the value as leaving the engine's figure alone. Anyone
	-- turning the mass rewrite off the obvious way got victims who ragdolled
	-- and then sat there.
	--
	-- The wait cannot be skipped either. An impulse applied before the body
	-- is physicalized is ignored without saying so, which is the whole reason
	-- the ladder below exists. So the readiness test becomes the mass reading
	-- back as anything at all, rather than reading back as the figure that
	-- was written.
	if base <= 0 then
		local generation = self.TimerTick
		local attempts = self.RagdollMassAttemptsMs

		local function wait(index)
			if generation ~= self.TimerTick then
				return
			end

			local ready = false

			pcall(function()
				ready = (npc:GetMass() or 0) > 0
			end)

			if ready or index == #attempts then
				if self.Config.LogTelemetry then
					self:Log("Mass " .. self:NameOf(npc)
							.. " untouched, ready=" .. tostring(ready)
							.. " atMs=" .. tostring(attempts[index]))
				end

				if onTook then
					onTook(attempts[index])
				end

				return
			end

			Script.SetTimer(attempts[index + 1] - attempts[index], function()
				wait(index + 1)
			end)
		end

		wait(1)

		return
	end

	-- Inverted against the impulse scale deliberately. That scale runs high
	-- for an unarmored target, because it multiplied a force meant to throw
	-- them further. Mass is the other way round: a man in mail should be the
	-- heavier thing for the horse to move.
	local scale = armorScale or 1.0

	if scale <= 0 then
		scale = 1.0
	end

	-- Turning the scaling off gives every victim the same mass, which is the
	-- only way to read the direction of the effect. Armor scaling makes a
	-- guard heavier and a villager lighter at the same time, so a uniform
	-- shortening of the throw and a genuine momentum response look alike. A
	-- flat figure below the engine's 80 separates them: momentum transfer
	-- predicts a longer throw for everyone, a settling side effect predicts
	-- a shorter one.
	if self.Config.RagdollMassArmorScaled == false then
		scale = 1.0
	end

	-- Raising the scale to an exponent is the only term that widens the gap
	-- between an armored victim and an unarmored one. The written mass is
	-- `base / scale^k`, so the ratio between two victims is their scale ratio
	-- raised to k and the base cancels out of it. Bases of 80 and 40 both
	-- present the horse with the same 3.4x spread and both measured at parity;
	-- k is what moves that number.
	local exponent = self.Config.RagdollMassArmorExponent or 1.0

	if exponent ~= 1.0 then
		scale = scale ^ exponent
	end

	local wanted = base / scale
	local generation = self.TimerTick
	local origin = nil

	pcall(function()
		origin = npc:GetWorldPos()
	end)

	local attempts = self.RagdollMassAttemptsMs

	local function try(index)
		if generation ~= self.TimerTick or index > #attempts then
			return
		end

		local took = false
		local reading = -1

		pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, { mass = wanted })
		end)

		pcall(function()
			reading = npc:GetMass()
			took = math.abs(reading - wanted) < 1.0
		end)

		if took then
			local moved = 0

			pcall(function()
				local p = npc:GetWorldPos()

				if origin then
					moved = self:VectorLength({
						x = p.x - origin.x,
						y = p.y - origin.y,
						z = p.z - origin.z
					})
				end
			end)

			if self.Config.LogTelemetry then
				self:Log("Mass " .. self:NameOf(npc)
						.. " scale=" .. string.format("%.2f", scale)
						.. " wanted=" .. string.format("%.0f", wanted)
						.. " took=" .. string.format("%.0f", reading)
						.. " atMs=" .. tostring(attempts[index])
						.. " movedBy=" .. string.format("%.2f", moved) .. "m")
			end

			if onTook then
				onTook(attempts[index])
			end

			return
		end

		if index == #attempts then
			if self.Config.LogTelemetry then
				self:Log("Mass " .. self:NameOf(npc)
						.. " never took, last read " .. string.format("%.0f", reading))
			end

			-- The impulse still has to go out, on a body of whatever mass the
			-- engine kept, rather than being dropped with the mass write.
			if onTook then
				onTook(attempts[index])
			end
		end

		Script.SetTimer(attempts[index + 1] and
				(attempts[index + 1] - attempts[index]) or 16, function()
			try(index + 1)
		end)
	end

	-- The first attempt is immediate rather than on a timer, because the body
	-- may already be physicalized by the time this is reached and a frame
	-- given away is a centimeter of horse travel per millisecond.
	try(1)
end


--- Slows a ragdolled victim so it stops sliding.
--
-- A thrown body keeps going long after the throw, and that slide is most of
-- the distance an impact appears to produce. It makes the ground read as ice,
-- and it makes distance a poor measure of force, because what is being
-- measured is mostly the surface rather than the impulse.
--
-- `damping` bleeds velocity off the body and `min_energy` is the threshold
-- below which physics puts it to rest. Both are fields of
-- `pe_simulation_params`, which `PHYSICPARAM_SIMULATION` selects. Vanilla uses
-- the same call for its own entities, with `PHYSICPARAM_COLLISION_CLASS` in
-- `GeomEntity.lua`.
--
-- Applied after the impulse, so the throw is not damped before it happens.
--
-- @tparam table npc victim entity
-- @tparam[opt] number armorScale the victim's armor scale, high for an
--   unarmored victim and low for one in mail, the same figure the ragdoll mass
--   is derived from. Chooses the commanded throw distance
function HorseCollisionMod:DampVictim(npc, armorScale)
	local damping = self.Config.RagdollDamping or 0
	local minEnergy = self.Config.RagdollMinEnergy or 0

	if damping <= 0 and minEnergy <= 0 then
		return
	end

	local pollMs = self.Config.RagdollDampPollMs or 100
	local settleAt = self.Config.RagdollDampSettleSpeed or 0.5
	local floorMs = self.Config.RagdollDampFloorMs or 200
	local ceilingMs = self.Config.RagdollDampCeilingMs or 6000
	local generation = self.TimerTick
	local startedAt = self:TimeMs()

	local origin = nil
	pcall(function()
		origin = npc:GetWorldPos()
	end)

	-- =========================================================================
	-- Phase 1: The Impact Parachute (Airborne Counter-Impulse)
	-- =========================================================================
	local keep = 1.0

	if self.Config.RagdollBrake then
		local heavy = self.Config.RagdollBrakeKeepArmored or 0.45
		local light = self.Config.RagdollBrakeKeepUnarmored or 1.0
		local lo = self.Config.RagdollBrakeArmorScaleArmored or 0.35

		-- The unarmored endpoint, and the reason `keep` in the log is rarely
		-- the figure the settings name.
		--
		-- `keep` is interpolated across this bracket, so a victim only
		-- receives `RagdollBrakeKeepUnarmored` if their armor scale reaches
		-- this endpoint exactly. Measured, ordinary villagers score about
		-- 1.15 against an endpoint of 1.26, so they are braked by six percent
		-- where the setting reads "untouched". That is wanted here, since the
		-- engine's throws run long at every armor level, but the setting is
		-- then describing an endpoint rather than a delivered figure and
		-- should be read that way.
		local hi = self.Config.RagdollBrakeArmorScaleUnarmored or 1.26
		local t = 1.0

		if armorScale and hi > lo then
			t = (armorScale - lo) / (hi - lo)
			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
		end

		keep = heavy + ((light - heavy) * t)
		if keep < 0.02 then
			keep = 0.02
		end
	end

	if self.Config.RagdollBrake and keep < 1.0 then
		local delayMs = (self.Config.ImpulseDelayMs or 50) + 10

		Script.SetTimer(delayMs, function()
			-- The same generation guard every other timer in this file
			-- carries. Without it a save load inside this sixty millisecond
			-- window fires the brake into the reloaded world, and the brake
			-- is the largest impulse this mod applies to anything: measured
			-- at 2576 units against an armored guard, forty times the mod's
			-- own knockback.
			if generation ~= self.TimerTick then
				return
			end

			if not npc.AddImpulse then
				return
			end

			local vel = nil
			local mass = -1
			local pos = nil

			pcall(function()
				vel = npc:GetVelocity()
				pos = npc:GetCenterOfMassPos()
				local stats = npc:GetPhysicalStats()
				if stats and stats.mass then
					mass = stats.mass
				end
			end)

			if not vel or not pos or mass <= 0 then
				return
			end

			local speed = math.sqrt((vel.x * vel.x) + (vel.y * vel.y) + (vel.z * vel.z))

			if speed > 0.5 then
				local removeFraction = 1.0 - keep
				local impulseMag = mass * speed * removeFraction

				local dir = {
					x = -vel.x / speed,
					y = -vel.y / speed,
					z = -vel.z / speed
				}

				local ok, err = pcall(function()
					npc:AddImpulse(-1, pos, dir, impulseMag, 1)
				end)

				if self.Config.LogTelemetry then
					self:Log("Phase1Brake " .. self:NameOf(npc)
							.. " speed=" .. string.format("%.2f", speed)
							.. " keep=" .. string.format("%.2f", keep)
							.. " mag=" .. string.format("%.1f", impulseMag)
							.. " mass=" .. string.format("%.1f", mass)
							.. " ok=" .. tostring(ok)
							.. " err=" .. tostring(err))
				end
			end
		end)
	end

	-- =========================================================================
	-- Phase 2: The Anti-Slide (Grounded & Bouncing Damping)
	-- =========================================================================
	local last = nil
	local moving = false
	local contactLog = {}
	local touching = 0
	local traveled = 0

	local airSamples = 0
	local airPeak = 0

	-- The armor-scaled ceiling this victim was actually held to, reported on
	-- the summary line. The cap is derived per victim, so without it nothing
	-- in the log says what the figure came out as.
	local lastCap = 0
	local lastDrag = 0

	local function apply(why, elapsed, speed, vertical, contact, share)
		local params = {}
		local scale = share or 1

		if damping > 0 then
			params.damping = damping * scale
		end

		if minEnergy > 0 and scale >= 1 then
			params.min_energy = minEnergy
		end

		local ok, err = pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, params)
		end)

		if self.Config.LogTelemetry and scale >= 1 then
			self:Log("Phase2Grounded " .. self:NameOf(npc)
					.. " why=" .. why
					.. " atMs=" .. string.format("%.0f", elapsed)
					.. " speed=" .. string.format("%.2f", speed or -1)
					.. " vertical=" .. string.format("%.2f", vertical or -1)
					.. " contact[" .. table.concat(contactLog, "") .. "]"
					.. " airBraked=" .. tostring(airSamples)
					.. " airPeak=" .. string.format("%.2f", airPeak)
					.. " scale=" .. string.format("%.2f", armorScale or -1)
					.. " keep=" .. string.format("%.2f", keep)
					.. " cap=" .. string.format("%.2f", lastCap)
					.. " drag=" .. string.format("%.1f", lastDrag)

					-- How far the body actually came, against the fraction of
					-- its speed it was allowed to keep. The pair is what makes
					-- a single throw readable: commanded beside achieved,
					-- with no ratio and no sample size in the way. It was
					-- computed and then dropped from this line, which left
					-- `traveled` accumulating every poll for nobody.
					.. " achieved=" .. string.format("%.2f", traveled)
					.. " sDamp=" .. string.format("%.2f", damping * scale)
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end

	local function release()
		pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, { damping = 0, min_energy = 0 })
		end)
	end

	local function watch()
		if generation ~= self.TimerTick then
			return
		end

		local here = nil
		pcall(function()
			here = npc:GetWorldPos()
		end)

		local elapsed = self:TimeMs() - startedAt
		local contact = "?"

		pcall(function()
			contact = tostring(npc:IsColliding())
		end)

		contactLog[#contactLog + 1] = (contact == "true") and "T" or "f"

		if contact == "true" then
			touching = touching + 1
		else
			touching = 0
		end

		local speed = nil
		local vertical = nil

		if here and last then
			local seconds = pollMs / 1000
			speed = self:VectorLength({
				x = here.x - last.x,
				y = here.y - last.y,
				z = here.z - last.z
			}) / seconds
			vertical = math.abs(here.z - last.z) / seconds

			if speed >= settleAt then
				moving = true
			end

			if origin and here then
				traveled = self:VectorLength({
					x = here.x - origin.x,
					y = here.y - origin.y,
					z = here.z - origin.z
				})
			end
		end

		last = here

		if elapsed >= ceilingMs then
			apply("ceiling", elapsed, speed, vertical, contact)
			release()
			return
		end

		-- Drag on a body still travelling and not yet settled, and **the lever
		-- that actually decides how far a victim goes**.
		--
		-- Measured over 24 throws with mass flat at 80 kg, the distance a body
		-- reached tracked the number of samples it spent above this cap and
		-- barely tracked `keep` at all:
		--
		--     airBraked 0     0.45  0.55  0.56  0.92  1.03  1.40
		--     airBraked 1-2   1.74  2.08  2.96  3.27  3.39
		--     airBraked 3-4   3.43 ... 5.32
		--
		-- Separation across the whole run was 1.11x, which is nothing, because
		-- this cap was the same figure for everyone. The counter-impulse
		-- removes 55 per cent of an armored victim's speed and the cap then
		-- flattens what is left onto the same curve as an unarmored one.
		--
		-- The impulse also fires before the engine has finished delivering the
		-- throw at this mass. A guard braked at 10.43 m/s with keep 0.45 should
		-- have been left at 4.7, and his `airPeak` afterwards read 11.17: the
		-- horse goes on driving a body of 80 kg well past the sixty
		-- millisecond mark. At 1,208 kg it did not, which is why the one-shot
		-- brake looked sufficient while the mass rewrite was carrying the
		-- separation.
		--
		-- So the cap is what armor scales. It is a ceiling rather than a
		-- subtraction, so it does not care when the engine stops pushing: a
		-- body held under 2.5 m/s cannot travel like one allowed 6.0 however
		-- it got its speed.
		local cap = self.Config.RagdollSpeedSoftCap or 0

		if self.Config.RagdollSpeedCapArmorScaled and armorScale then
			local heavy = self.Config.RagdollSpeedCapArmored or 2.5
			local light = self.Config.RagdollSpeedCapUnarmored or 6.0
			local lo = self.Config.RagdollBrakeArmorScaleArmored or 0.35
			local hi = self.Config.RagdollBrakeArmorScaleUnarmored or 1.26
			local t = 1.0

			if hi > lo then
				t = (armorScale - lo) / (hi - lo)

				if t < 0 then
					t = 0
				elseif t > 1 then
					t = 1
				end
			end

			cap = heavy + ((light - heavy) * t)
		end

		lastCap = cap

		if cap > 0 and speed and
				touching < (self.Config.RagdollDampContactRun or 3) then
			local strength = 0
			if speed > cap then
				strength = (speed - cap) / (self.Config.RagdollSpeedSoftCapSpan or 6.0)
				if strength > 1 then
					strength = 1
				end
				airSamples = airSamples + 1
				if speed > airPeak then
					airPeak = speed
				end
			end

			-- The drag itself is armor scaled, not only the ceiling.
			--
			-- The ceiling alone could not separate anyone on the throws that
			-- matter. `strength` is `(speed - cap) / span` clamped to 1, so
			-- past `cap + span`, about 5.5 m/s, it saturates and every victim
			-- receives the identical figure however their ceiling was set.
			-- Measured, armored bodies held to a ceiling of 2.50 still reached
			-- peaks of 11.37, 13.28 and 15.37 m/s, because 8.0 of drag is
			-- simply not enough to hold a body the engine threw that hard.
			-- The ceiling moved when the drag started and never moved how much
			-- there was.
			--
			-- Heavy drag was the objection raised against this whole approach
			-- before it was tested, on the grounds it would read as syrup. The
			-- rider rode armored victims at a flat 15.0 and reported no syrup
			-- at all, so the objection is already withdrawn on evidence.
			local drag = self.Config.RagdollAirDamping or 3.0

			if self.Config.RagdollAirDampingArmorScaled and armorScale then
				local heavy = self.Config.RagdollAirDampingArmored or 20.0
				local light = self.Config.RagdollAirDampingUnarmored or 4.0
				local lo = self.Config.RagdollBrakeArmorScaleArmored or 0.35
				local hi = self.Config.RagdollBrakeArmorScaleUnarmored or 1.26
				local t = 1.0

				if hi > lo then
					t = (armorScale - lo) / (hi - lo)

					if t < 0 then
						t = 0
					elseif t > 1 then
						t = 1
					end
				end

				drag = heavy + ((light - heavy) * t)
			end

			lastDrag = drag

			pcall(function()
				npc:SetPhysicParams(PHYSICPARAM_SIMULATION, {
					damping = drag * strength
				})
			end)
		end

		if moving and elapsed >= floorMs
				and touching >= (self.Config.RagdollDampContactRun or 3) then
			local ramp = self.Config.RagdollDampRampSamples or 8
			local share = (touching - (self.Config.RagdollDampContactRun or 3)) / ramp

			if share > 1 then
				share = 1
			end

			apply("grounded", elapsed, speed, vertical, contact, share)

			if share < 1 or (speed and speed >= settleAt) then
				Script.SetTimer(pollMs, watch)
				return
			end

			release()
			return
		end

		Script.SetTimer(pollMs, watch)
	end

	Script.SetTimer(pollMs, watch)
end


--- Knocks a victim down with a physics ragdoll.
--
-- Used at trot and gallop. `actor:Fall` switches the victim to a ragdoll,
-- after which an impulse can be applied. Impulses are ignored on an upright,
-- animation-driven actor, so the order matters and the impulse is deferred
-- by a tick.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number speed horse speed in meters per second
-- @tparam number tierScale the tier's share of the configured impulse, 0 to 1
-- @tparam number armorScale the victim's armor scale, which sets their ragdoll
--   mass and nothing else
-- @tparam table horsePos horse world position, the origin a push points away
--   from, so a victim is never thrown back under the rider
-- @tparam[opt] table horseEnt the player's horse, for the barding force bonus
function HorseCollisionMod:Ragdoll(npc, velocity, speed, tierScale, armorScale,
								   horsePos, horseEnt)
	-- Undo the previous impact's damping before doing anything else.
	--
	-- `DampVictim` sets `damping` and `min_energy` to stop a thrown body
	-- sliding forever. A physics body below its minimum energy is put to sleep,
	-- and a sleeping body ignores impulses and parameter writes alike. That is
	-- one cause for three symptoms that looked separate: on a victim hit while
	-- already down, the mass write is refused, the impulse is accepted and does
	-- nothing, and there is no visible reaction. Measured, a commanded 3.00 m/s
	-- on an 80 kg body moved it eight centimeters.
	--
	-- Clearing both wakes it, so the fall, the mass write and the impulse below
	-- all meet a body that can respond.
	pcall(function()
		npc:SetPhysicParams(PHYSICPARAM_SIMULATION, {
			damping = 0, min_energy = 0
		})
	end)

	-- A victim already ragdolling is re-physicalized before anything else.
	--
	-- `actor:Fall` on a body that is already down has nothing to perform, so
	-- the body never re-enters the physicalized state, the mass write is
	-- refused, and the impulse meets something that will not move: measured, a
	-- commanded 3.00 m/s moved an 80 kg body eight centimeters.
	--
	-- `RagDollize` does re-physicalize it, which is exactly why it looked like
	-- the answer, and on its own it snaps the victim into a T-pose. Calling it
	-- first and letting `Fall` follow immediately uses the half of it that
	-- works and lets the fall overwrite the pose it wrecks.
	--
	-- Only for a victim already down. The standing path does not need it and
	-- is where the T-pose came from when this was applied to every impact.
	local alreadyDown = false
	local entryState = "?"

	pcall(function()
		entryState = tostring(npc.actor:GetCurrentAnimationState())

		alreadyDown = entryState == self.RagdollAnimationState
	end)

	if alreadyDown then
		-- A victim already down is knocked down again by a fragment, not by
		-- driving physics from here.
		--
		-- Setting the physicalization profile by hand works and cannot be made
		-- to look right. It is the only thing that re-physicalizes a body
		-- already in `BlendRagdoll`, so the mass write succeeds and the throw
		-- reaches parity with a standing victim, 2.30 m against 2.05 to 2.18.
		-- But something has to set the profile back, and an alive actor is an
		-- upright capsule: returning to it from a body lying on the ground
		-- stands the victim in a single frame with nothing in between.
		--
		-- Ruled out along the way, each on its own: `RagDollize` with no
		-- argument and with the fall-and-play flag, cycling the profile out to
		-- `alive` and back, `PostPhysicalize` once and repeated across the whole
		-- get-up, `StandUp` before the fall, and playing an `hcm_getup_*`
		-- fragment afterwards, which carries a measured rotation of +53, +90,
		-- -176 and 0 degrees and is why those were removed from the reaction
		-- path once already.
		--
		-- `hcm_settle` is the fall tier's own shape with the clip taken out: an
		-- empty terminal animation so nothing imposes a pose, and a `Ragdoll`
		-- ProcLayer at ExitTime 0 so Mannequin owns the ragdoll from the first
		-- frame. The game then recovers the actor when the fragment ends, the
		-- same way it recovers one knocked down by `hcm_fall_`, which is the
		-- only recovery in this mod that has ever looked right.
		local played = false

		pcall(function()
			played = npc.actor:StartInteractiveActionByName(
					self.Config.SettleFragTag or "hcm_settle",
					npc.id, false, 1.0)
		end)

		if self.Config.LogTelemetry then
			self:Log("Settle " .. self:NameOf(npc)
					.. " played=" .. tostring(played)
					.. " entry=" .. entryState)
		end

		return
	end

	-- The fall is requested after the body is physicalized, not alongside it.
	--
	-- Called in the same frame as `RagDollize` the two race, the fall does not
	-- take, and the victim stands back up in the T-pose `RagDollize` left. The
	-- signal for when the body is ready is the one this file already relies on
	-- further down: the mass write succeeds exactly when the body is
	-- physicalized, and its ladder reports that at 0 to 120 ms.
	--
	-- A victim who was not already down keeps the original order, because
	-- there the fall is what physicalizes the body in the first place and
	-- nothing has to wait for anything.
	local function requestFall()
		pcall(function()
			if npc.actor then
				npc.actor:Fall({ x = 0, y = 0, z = 0 }, true)
			end
		end)
	end

	if not alreadyDown then
		requestFall()
	end

	-- `actor:RagDollize` does not belong here and must not be added back. It
	-- asks for the physics profile directly rather than telling the actor to
	-- fall, which is why it looks like the answer for re-hitting a victim who
	-- is already down, and in game it snaps the victim upright into a T-pose
	-- on every gallop impact.

	-- The impulse goes out the moment the mass write takes, and not before.
	--
	-- `actor:Fall` requests the fall, it does not perform it. Applied in the
	-- same instant, the mass write is rejected and the impulse meets the
	-- animated character rather than a ragdoll, which is why a victim used to
	-- read 80 kg, the engine's default, when this mod had just written 42.
	--
	-- Waiting on the `BlendRagdoll` animation state is the wrong signal and was
	-- tried: that state does not appear until about two seconds after a gallop
	-- impact, so the wait always ran to its ceiling and the throw visibly fired
	-- half a second after the victim had already fallen. The mass write is the
	-- right signal, because it succeeds exactly when the body is physicalized,
	-- and its own ladder reports that at 0 to 120 ms.
	self:MassVictim(npc, armorScale, function()
		if alreadyDown then
			requestFall()
		end

		self:ImpulseVictim(npc, velocity, tierScale, horsePos, horseEnt)
		self:DampVictim(npc, armorScale)
	end)

	-- The control for the same reading taken on the fall path. This tier uses
	-- actor:Fall and touches no animation data of this mod's, so a turn seen
	-- here belongs to the game rather than to the reaction.
	self:WatchTurn(npc, "engine-ragdoll")

	-- Traced as the control for the fall path. This tier hands the body to
	-- physics through actor:Fall with no fragment of this mod's involved, so
	-- how long the engine then holds it is the engine's own figure.
	self:TraceRecovery(npc, "engine-ragdoll")

end


--- Pushes a victim who is already a physics body.
--
-- Separated from `Ragdoll` because the fall tier ragdolls the victim itself,
-- partway through an animation rather than at the moment of impact, and needs
-- the push without the rest.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number tierScale the tier's share of the configured impulse, 0 to 1
-- @tparam[opt] table horseEnt the player's horse, for the barding force bonus
-- @tparam table horsePos horse world position, the origin the push points away
--   from, so a victim is never thrown back under the rider
function HorseCollisionMod:ImpulseVictim(npc, velocity, tierScale, horsePos, horseEnt)
	-- Barding is a flat addition to the two force figures rather than a factor
	-- on the result, so a barded horse adds the same absolute push whoever it
	-- hits, and the victim's own armor still scales the whole thing.
	--
	-- Added in five steps, so what a given horse gets is readable straight off
	-- the table in the settings file rather than out of a curve.
	local bonus = self:BardingForceBonus(horseEnt)

	local k_back = (self.Config.Knockback + bonus.knockback) * tierScale
	local k_up = (self.Config.Uplift + bonus.uplift) * tierScale

	if k_back <= 0 and k_up <= 0 then
		return
	end

	pcall(function()
		local hitPos = { x = 0, y = 0, z = 0 }
		local dir = { x = 1, y = 0, z = 0 }

		if npc.GetPos then
			hitPos = npc:GetPos()
		end

		-- Lift the application point to roughly chest height so the victim
		-- rotates over the impact instead of having their feet swept.
		hitPos.z = hitPos.z + 1.0

		-- Normalized against the velocity's own length, not against the
		-- scored speed. Those are different numbers: the score is the peak of
		-- the last few ticks, chosen so a collision is rated by the speed the
		-- horse carried into it, while the velocity here is what the horse is
		-- doing now, after the contact has slowed it.
		--
		-- Dividing one by the other leaves a direction shorter than unit and
		-- an impulse weakened by that ratio, so the same target took 67.3 at
		-- full speed and 37.7 when the horse had dropped to 2.84 against a
		-- score of 10.72. Knockback then varies with how hard the horse
		-- happened to brake rather than with the tier and the target.
		local moving = self:VectorLength(velocity or { x = 0, y = 0, z = 0 })

		if moving > 0 then
			dir.x = velocity.x / moving
			dir.y = velocity.y / moving
			dir.z = 0
		end

		-- A component across the horse's line, so the victim leaves it.
		--
		-- Thrown along the line they do not: at a gallop the horse covers
		-- ground faster than the impulse moves a body of this mass, so it
		-- overtakes its own victim and tramples them again. Pushing them
		-- across the line clears it whatever the magnitude.
		--
		-- The side is the one the victim is already on, from the sign of the
		-- cross product of the horse's heading with the offset to the victim.
		-- Carrying them further the way a glancing blow already sent them
		-- reads better than picking a side, and never pushes anyone back
		-- through the horse.
		local across = { x = 0, y = 0 }
		local lateral = self.Config.LateralImpulse or 0

		if lateral > 0 and horsePos then
			local side = ((hitPos.x - horsePos.x) * dir.y)
					- ((hitPos.y - horsePos.y) * dir.x)

			-- Perpendicular to the heading, pointing at the victim's side.
			local sign = 1

			if side > 0 then
				sign = -1
			end

			across.x = -dir.y * sign
			across.y = dir.x * sign
		end

		-- Forward push and upward lift are combined into one vector, then
		-- split back into a unit direction and a magnitude, because
		-- AddImpulse wants those as separate arguments.
		local combined = {
			x = (dir.x * k_back) + (across.x * math.abs(k_back) * lateral),
			y = (dir.y * k_back) + (across.y * math.abs(k_back) * lateral),
			z = k_up
		}
		local impulseMag = math.sqrt((combined.x * combined.x)
				+ (combined.y * combined.y)
				+ (combined.z * combined.z))

		-- What the mass write aims for, which is what the magnitude was tuned
		-- against. Reading the same setting the write uses keeps the two from
		-- drifting apart.
		-- Logged because the multiplier and the tier scalar are both visible
		-- in telemetry while the figure they produce was not, which left a
		-- report of armored targets moving further at trot than at gallop
		-- with nothing to check it against.
		if self.Config.LogTelemetry then
			-- The mass is read here rather than assumed, because the throw is
			-- a velocity and the velocity is the magnitude over the mass. The
			-- mod writes a ragdoll mass of its own, inverted against this same
			-- scale, so the figure the impulse actually meets is the one thing
			-- that decides whether changing the force does anything at all.
			local mass = -1

			pcall(function()
				local stats = npc:GetPhysicalStats()

				if stats and stats.mass then
					mass = stats.mass
				end
			end)

			self:Log("Impulse " .. self:NameOf(npc)
					.. " tier=" .. string.format("%.2f", tierScale)
					.. " magnitude=" .. string.format("%.1f", impulseMag)
					.. " mass=" .. string.format("%.1f", mass)
					.. " dv=" .. string.format("%.2f",
					mass > 0 and (impulseMag / mass) or -1))
		end

		if npc.AddImpulse and impulseMag > 0 then
			local normDir = {
				x = combined.x / impulseMag,
				y = combined.y / impulseMag,
				z = combined.z / impulseMag
			}

			-- The ragdoll needs time to physicalize before it accepts an
			-- impulse, and one applied too early is ignored without saying so.
			-- The wait is settable because a fixed 50 ms produced throws of
			-- four meters and of nothing at all from the same magnitude.
			Script.SetTimer(self.Config.ImpulseDelayMs or 50, function()
				local before, after = nil, nil

				pcall(function()
					before = npc:GetWorldPos()
				end)

				local ok, err = pcall(function()
					npc:AddImpulse(-1, hitPos, normDir, impulseMag, 1)
				end)

				-- Reported from inside the timer, and with what the body did
				-- next. The line written when the impulse is computed says
				-- only what was intended: the call itself happens a quarter of
				-- a second later, and a failure or a body that does not move
				-- looked identical to a throw from outside.
				Script.SetTimer(300, function()
					pcall(function()
						after = npc:GetWorldPos()
					end)

					local moved = 0

					if before and after then
						moved = math.sqrt(((after.x - before.x) ^ 2)
								+ ((after.y - before.y) ^ 2)
								+ ((after.z - before.z) ^ 2))
					end

					if self.Config.LogTelemetry then
						self:Log("ImpulseApplied " .. self:NameOf(npc)
								.. " ok=" .. tostring(ok)
								.. " err=" .. tostring(err)
								.. " movedIn300ms=" .. string.format("%.2f", moved) .. "m")
					end
				end)
			end)
		end
	end)
end
