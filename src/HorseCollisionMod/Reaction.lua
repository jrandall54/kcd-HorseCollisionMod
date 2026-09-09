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
-- @release 5.0.0
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
		self.VictimActivity[tostring(npc.id)] =
				tostring(npc.actor:GetCurrentAnimationState())
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

	if base <= 0 then
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

	pcall(function() origin = npc:GetWorldPos() end)

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

	-- Applied when the body has finished traveling, not on a stopwatch.
	--
	-- This used to fire 150 ms after the impact, which is before a thrown body
	-- has reached its top speed. Measured, it arrested victims wherever it
	-- happened to catch them: at an identical launch velocity the throws ran
	-- 2.9 m to 71.8 m, and every short one came to rest around 1000 ms while
	-- the long ones stayed in motion for two to four seconds. With the damping
	-- off, the same ride had no throw under 7.5 m. It was eating the mod's own
	-- impulse on roughly a quarter of impacts.
	--
	-- It is also why a victim already lying on the ground barely moved. They
	-- are slow at 150 ms whatever was done to them, so they were damped
	-- immediately and never traveled.
	--
	-- The damping itself is not the problem and must stay. Without it a ragdoll
	-- slides a long way and the ground reads as ice.
	--
	-- So the body is watched instead. Speed is taken from how far it moved
	-- between two polls, which works on a ragdoll where a velocity read may
	-- not. Damping waits until the body has been seen moving and has since
	-- dropped below the settling speed, with a floor so it cannot fire during
	-- the launch and a ceiling so it always fires eventually.
	local pollMs = self.Config.RagdollDampPollMs or 100
	local settleAt = self.Config.RagdollDampSettleSpeed or 0.5
	local floorMs = self.Config.RagdollDampFloorMs or 200

	local ceilingMs = self.Config.RagdollDampCeilingMs or 6000
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local last = nil
	local moving = false

	-- Where the body was when it was struck, so how far it has come can be
	-- measured rather than inferred from how long it has been moving.
	local origin = nil

	pcall(function()
		origin = npc:GetWorldPos()
	end)

	-- Contact across the whole flight, kept and written once.
	--
	-- The value at the moment of damping is always `true`, because damping
	-- happens after the body has landed. Whether `IsColliding` is usable as a
	-- trigger depends on what it says while the body is in the air, and that
	-- needs the samples in between rather than the last one.
	local contactLog = {}

	-- How many samples in a row have reported contact.
	local touching = 0

	-- The distance this throw is allowed, sculpted from what the engine gave.
	--
	-- The engine resolves the collision on its own and hands over a body that
	-- is, deliberately, moving too fast. Nothing here tries to change that. From
	-- the moment the body is a ragdoll it is the mod's, and the job is to remove
	-- exactly enough of that motion to land on a chosen distance.
	--
	-- **This can only ever subtract.** No energy is added to a victim, ever, so
	-- a commanded distance is a ceiling and not a target: a body the engine only
	-- threw a meter will travel a meter whatever is commanded. That is the point
	-- rather than a shortcoming. The complaint this exists to answer is that
	-- throws within one configuration ran 0.07 m to 7.71 m, so cutting the long
	-- tail to a commanded ceiling is the whole fix.
	--
	-- Armor chooses the ceiling, between two figures that are set directly in
	-- meters rather than derived from a lie about what a person weighs. The
	-- armor scale runs high for an unarmored victim and low for one in mail.
	local commanded = 0

	if self.Config.RagdollThrowSculpt then
		local far = self.Config.RagdollThrowDistanceUnarmored or 4.0
		local near = self.Config.RagdollThrowDistanceArmored or 1.5
		local lo = self.Config.RagdollThrowArmorScaleArmored or 0.35
		local hi = self.Config.RagdollThrowArmorScaleUnarmored or 1.50
		local t = 1.0

		if armorScale and hi > lo then
			t = (armorScale - lo) / (hi - lo)

			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
		end

		commanded = near + ((far - near) * t)
	end

	-- Where the body started, so travel can be measured rather than assumed.
	local origin = nil

	pcall(function()
		origin = npc:GetWorldPos()
	end)

	local travelled = 0
	local sculptDamping = 0

	-- Written once, when the body becomes a ragdoll, and never again.
	--
	-- Two actuators were tried per poll and both failed. `damping` in
	-- `PHYSICPARAM_SIMULATION` is clamped or ignored on a ragdoll: raising it
	-- from 30 to 250 left the overshoot unchanged, so no value of it would ever
	-- have held a body. Setting velocity through `PHYSICPARAM_VELOCITY` was
	-- accurate -- mean error fell from +1.31 m to -0.69 m with nothing
	-- overshooting -- and looked, in the rider's words, absolutely horrible:
	-- writing one velocity onto an articulated body flattens its per-limb
	-- state, so the whole reaction glitches rather than just the moment of
	-- correction. That is structural and no amount of gentler scaling fixes it.
	--
	-- `pe_params_articulated_body` is the group that actually governs a
	-- ragdoll. `dampingLyingMode` is the damping the solver applies once the
	-- body is in lying mode, which is a body sliding on the ground, and that is
	-- where the unnatural distance comes from. The solver applies it itself, so
	-- the limbs keep their own motion and there is nothing per-frame to glitch.
	--
	-- Armor picks the figure. `nCollLyingMode` is lowered as well so lying mode
	-- engages after fewer contacts and the damping starts acting sooner.
	if self.Config.RagdollThrowSculpt then
		local heavy = self.Config.RagdollLyingDampingArmored or 6.0
		local light = self.Config.RagdollLyingDampingUnarmored or 1.5
		local lo = self.Config.RagdollThrowArmorScaleArmored or 0.35
		local hi = self.Config.RagdollThrowArmorScaleUnarmored or 1.50
		local t = 1.0

		if armorScale and hi > lo then
			t = (armorScale - lo) / (hi - lo)

			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
		end

		sculptDamping = heavy + ((light - heavy) * t)

		pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_ARTICULATED, {
				dampingLyingMode = sculptDamping,
				nCollLyingMode = self.Config.RagdollLyingContacts or 2
			})
		end)
	end

	-- What the air braking did, accumulated rather than logged per sample. A
	-- line every poll while a body is in flight is exactly the kind of probe
	-- that costs frames in the window the throw is being watched.
	local airSamples = 0
	local airPeak = 0

	local function apply(why, elapsed, speed, vertical, touching, share)
		local params = {}
		local scale = share or 1

		if damping > 0 then
			params.damping = damping * scale
		end

		-- The rest threshold is not ramped. It decides when physics puts the
		-- body to sleep, and a fraction of it applied to a moving body would
		-- stop it outright, which is the braking this ramp exists to avoid.
		if minEnergy > 0 and scale >= 1 then
			params.min_energy = minEnergy
		end

		local ok, err = pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, params)
		end)

		-- Written once, when the ramp is finished.
		--
		-- `apply` is called on every sample while the damping climbs, so an
		-- unconditional log here is ten lines a throw. Per-sample logging
		-- during a reaction is what made a smooth animation look jerky earlier
		-- in this project, and it cost several rounds of judgment.
		if self.Config.LogTelemetry and scale >= 1 then
			self:Log("Damped " .. self:NameOf(npc)
					.. " why=" .. why
					.. " atMs=" .. string.format("%.0f", elapsed)
					.. " speed=" .. string.format("%.2f", speed or -1)
					.. " vertical=" .. string.format("%.2f", vertical or -1)
					.. " contact[" .. table.concat(contactLog, "") .. "]"
					.. " airBraked=" .. tostring(airSamples)
					.. " airPeak=" .. string.format("%.2f", airPeak)

					.. " ramp=" .. string.format("%.2f", scale)

					-- The pair that makes this verifiable on a single throw
					-- instead of across a hundred. If commanded and achieved
					-- agree, the controller works; no ratios, no sample size,
					-- and none of the variance that made every separation
					-- measurement on this project swing by a factor of two.
					.. " commanded=" .. string.format("%.2f", commanded)
					.. " achieved=" .. string.format("%.2f", travelled)
					.. " sculptDamping=" .. string.format("%.2f", sculptDamping)

					-- Named for the slide rather than for the corpse. Both
					-- values are released the moment this watch ends, so they
					-- describe what acted on the body while it was moving and
					-- not the state it is left in. Read as `damping` and
					-- `minEnergy` they said the opposite.
					.. " slideDamping=" .. string.format("%.2f", damping * scale)
					.. " slideMinEnergy=" .. tostring(minEnergy)
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end

	-- Hand the body back to the engine once its slide has ended.
	--
	-- `damping` and `min_energy` are persistent physics parameters rather than
	-- a one-shot effect, so a body damped once carries them for the rest of its
	-- existence. `min_energy` is the threshold below which physics puts a body
	-- to sleep, and at 1.0 that is anything slower than about 1.4 m/s, which an
	-- ordinary corpse nudged by a horse drops under almost immediately. A
	-- sleeping body holds the position it had, so one lifted by the horse and
	-- then left unsupported stays in the air. Striking it wakes it and it
	-- falls, which is how this was found.
	--
	-- Both values exist to end a slide and have no job once the slide is over.
	-- Leaving them written is the mod changing how a body behaves long after
	-- its own effect has finished. `Ragdoll` already clears them with this
	-- exact call, but only when the same victim is hit a second time, which
	-- most bodies never are.
	local function release()
		pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, {
				damping = 0, min_energy = 0
			})
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

		local speed = nil

		local vertical = nil

		if here and last then
			local seconds = pollMs / 1000

			speed = self:VectorLength({
				x = here.x - last.x,
				y = here.y - last.y,
				z = here.z - last.z
			}) / seconds

			-- Vertical speed on its own is what separates a body still being
			-- thrown from one sliding along the ground. Both are moving, and a
			-- speed threshold cannot tell them apart, which is why damping on
			-- speed alone either fires mid-flight or waits out the whole slide.
			vertical = math.abs(here.z - last.z) / seconds

			-- Whether the engine says the body is in contact with anything.
			--
			-- This is the question the speed and vertical tests have been
			-- approximating. `pe_status_living` carries `bFlying`,
			-- `groundHeight` and `bStuck`, but none of that struct is exposed
			-- to Lua; `IsColliding` is, on every entity, and vanilla uses the
			-- neighbouring `AwakePhysics` on doors and elevators.
			--
			-- Logged before being trusted. A ragdoll that has landed may report
			-- contact permanently, which would make it useless as a trigger,
			-- and that cannot be settled by reading a header.

			if speed >= settleAt then
				moving = true
			end

			-- Measurement only. The sculpting is a single write at ragdoll
			-- time, above, and nothing is written from inside this loop: that
			-- is what stopped the animation glitching, so it must stay true.
			if origin and here then
				travelled = self:VectorLength({
					x = here.x - origin.x,
					y = here.y - origin.y,
					z = here.z - origin.z
				})
			end
		end

		last = here

		if elapsed >= ceilingMs then
			apply("ceiling", elapsed, speed, vertical, contact)

			-- Released here as well as at the settled exit. This is the
			-- failsafe, so the body may still be moving, and letting it slide
			-- on is the lesser fault: the alternative is a corpse left carrying
			-- `min_energy` for the rest of its existence, which is what made
			-- bodies sleep in mid-air. The window this mod owns is over either
			-- way, and it should not still be writing physics when it is.
			release()

			return
		end

		-- The floor covers the case where the impulse has not taken effect by
		-- the first poll, so the body reads slow before it has been thrown.
		--
		-- A second test here damped as soon as vertical
		-- motion fell below a threshold, on the reasoning that a body still
		-- moving without rising must be sliding. That is a guess about state
		-- rather than state, and it is wrong for the case it is worst in: a
		-- victim hit while already lying down has no vertical component from
		-- the first frame, so it read as a slide immediately and the throw was
		-- damped at 736 ms, before it happened. An impact on someone already
		-- on the ground produced no visible reaction at all because of it.
		--
		-- The test below is the real question and needs no proxy: the body has
		-- been seen moving and has since slowed. Removing the guess leaves one
		-- threshold doing the work instead of two that had to agree.

		-- Damped when the body has been in contact for a run of samples.
		--
		-- `IsColliding` is the engine's own answer to whether the body is
		-- touching anything, and it is the question every test here was
		-- approximating. It is noisy rather than a clean landed flag: measured
		-- across six throws it reads `ffffTTTfffTTTTT` for a body that leaves
		-- the ground, lands, bounces and lands again. A single contact sample
		-- would damp mid-bounce.
		--
		-- A run of them does not. Continuous contact means the body has come
		-- down and stayed down, which is exactly the moment a throw is over and
		-- a slide begins, and it needs no threshold to agree with any other.
		--
		-- Contact is not enough on its own, and speed was not enough on its
		-- own. They answer different questions and both have to hold.
		--
		-- Speed alone fires whenever the tumble happens to dip under half a
		-- meter per second, which for an airborne body is arbitrary: measured,
		-- anywhere from 736 ms to 2848 ms, and the throw ended wherever it
		-- caught the body. Contact alone fires on a body skidding along the
		-- ground, which reports contact continuously while still traveling:
		-- measured at 8.61 m/s and 8.59 m/s, which is a body being braked in
		-- front of the rider.
		--
		-- Landed and stopped are two facts, not one fact and a proxy for it.
		if contact == "true" then
			touching = touching + 1
		else
			touching = 0
		end

		-- Drag on a body that is traveling and not yet in contact.
		--
		-- The grounded damping below cannot arm until `IsColliding` has read
		-- true three samples running, and the first three or four samples of a
		-- long throw are exactly the ones that read false. That window is where
		-- the distance is, and nothing touched it.
		--
		-- Read straight off a paired trace, one sample per column:
		--
		--   contact[fffTTTTTTTTTTT]
		--   speeds[8.9,8.1,8.4,7.3,6.1,5.7,4.5,3.9,3.1,2.4,1.4,0.6,0.1]
		--
		-- About 3.3 m of a 6 m throw is spent in those first columns, before
		-- any damping exists, and the rest bleeds off once the grounded ramp
		-- takes over. A short throw never passes 3.9 m/s and is over inside
		-- half a second, so 4 separates them cleanly.
		--
		-- This was first written with the cap at 9, on the theory that the far
		-- throws were victims launched into the air. They are not. The rider
		-- watched them and reported the distance is a slide along the ground,
		-- and the traces agree: `airBraked=0` on every long throw, because none
		-- of them ever reached the old cap. The peak that suggested flight was
		-- a single early sample; the sustained speed is what carries the body.
		--
		-- Drag rather than a velocity clamp, deliberately. A hard ceiling
		-- applied every frame reads as the body hitting an invisible wall.
		-- Damping is a decay coefficient, so the body eases down over several
		-- frames, and the strength scales with how far over the line it is: a
		-- body barely above the cap gets a nudge and a fast one gets real drag.
		--
		-- Released again below the cap rather than left in place, because the
		-- damping is a persistent physics parameter and a body that has already
		-- slowed should fall the rest of the way on its own. `min_energy` is
		-- deliberately not set here: it puts a body to sleep, which is right for
		-- a slide that has ended and wrong for one still moving.
		local cap = self.Config.RagdollSpeedSoftCap or 0

		if cap > 0 and speed and touching < (self.Config.RagdollDampContactRun or 3) then
			local strength = 0

			if speed > cap then
				strength = (speed - cap)
						/ (self.Config.RagdollSpeedSoftCapSpan or 6.0)

				if strength > 1 then
					strength = 1
				end

				airSamples = airSamples + 1

				if speed > airPeak then
					airPeak = speed
				end
			end

			pcall(function()
				npc:SetPhysicParams(PHYSICPARAM_SIMULATION, {
					damping = (self.Config.RagdollAirDamping or 3.0) * strength
				})
			end)
		end

		-- Grounded is the trigger, and the damping ramps in from there.
		--
		-- Requiring the body to be slow as well as grounded means damping waits
		-- until the slide has nearly ended on its own, which is too late to be
		-- the thing that ends it: measured, a low throw skidded for 1900 ms and
		-- 13.87 m before its speed fell under the threshold. Bleeding off a
		-- slide is the whole job, so a body still moving is exactly what should
		-- be damped.
		--
		-- Applying full damping the moment it lands is what made this noticeable
		-- the other way, braking a body doing 8.6 m/s in front of the rider. So
		-- it comes in over several samples instead, in proportion to how long
		-- the body has been down. A fast landing decelerates rather than
		-- stopping, and a body that has been sliding a while gets the full
		-- figure.
		if moving and elapsed >= floorMs
				and touching >= (self.Config.RagdollDampContactRun or 3) then
			local ramp = self.Config.RagdollDampRampSamples or 8
			local share = (touching - (self.Config.RagdollDampContactRun or 3))
					/ ramp

			if share > 1 then
				share = 1
			end

			apply("grounded", elapsed, speed, vertical, contact, share)

			-- Held open until the ramp is finished and the body has stopped,
			-- so each sample can raise the damping further.
			if share < 1 or (speed and speed >= settleAt) then
				Script.SetTimer(pollMs, watch)

				return
			end

			-- The ramp is finished and the body has stopped, so the damping has
			-- done its whole job and is released rather than left on the corpse.
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
				npc.actor:Fall({x=0, y=0, z=0}, true)
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
		local hitPos = {x=0, y=0, z=0}
		local dir = {x=1, y=0, z=0}

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
		local moving = self:VectorLength(velocity or {x = 0, y = 0, z = 0})

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
