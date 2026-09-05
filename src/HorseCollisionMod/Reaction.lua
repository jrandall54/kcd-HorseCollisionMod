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
-- @release 4.9.2
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
	if self.Config.ReleaseAnimationMovement then
		Script.SetTimer(50, function()
			self:ReleaseVictimMovement(npc)
		end)
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
function HorseCollisionMod:MassVictim(npc, armorScale)
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

			return
		end

		if index == #attempts and self.Config.LogTelemetry then
			self:Log("Mass " .. self:NameOf(npc)
					.. " never took, last read " .. string.format("%.0f", reading))
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
function HorseCollisionMod:DampVictim(npc)
	local damping = self.Config.RagdollDamping or 0
	local minEnergy = self.Config.RagdollMinEnergy or 0

	if damping <= 0 and minEnergy <= 0 then
		return
	end

	-- After the impulse has been applied rather than alongside it, since the
	-- impulse itself is deferred until the body has physicalized.
	local delay = (self.Config.ImpulseDelayMs or 50) + 100
	local generation = self.TimerTick

	Script.SetTimer(delay, function()
		if generation ~= self.TimerTick then
			return
		end

		local params = {}

		if damping > 0 then
			params.damping = damping
		end

		if minEnergy > 0 then
			params.min_energy = minEnergy
		end

		local ok, err = pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, params)
		end)

		if self.Config.LogTelemetry then
			self:Log("Damped " .. self:NameOf(npc)
					.. " damping=" .. tostring(damping)
					.. " minEnergy=" .. tostring(minEnergy)
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end)
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
-- @tparam number impulseScale multiplier on the configured impulse, 0 to 1
-- @tparam table horsePos horse world position, the origin a push points away
--   from, so a victim is never thrown back under the rider
function HorseCollisionMod:Ragdoll(npc, velocity, speed, impulseScale, horsePos)
	pcall(function()
		if npc.actor then
			npc.actor:Fall({x=0, y=0, z=0}, true)
		end
	end)

	-- Before the impulse and the damping, because it is the only one of the
	-- three that has to beat the horse's own collision rather than follow it.
	self:MassVictim(npc, impulseScale)

	self:ImpulseVictim(npc, velocity, impulseScale, horsePos)
	self:DampVictim(npc)

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
-- @tparam number impulseScale multiplier on the configured impulse, 0 to 1
-- @tparam table horsePos horse world position, the origin the push points away
--   from, so a victim is never thrown back under the rider
function HorseCollisionMod:ImpulseVictim(npc, velocity, impulseScale, horsePos)
	local k_back = self.Config.Knockback * impulseScale
	local k_up = self.Config.Uplift * impulseScale

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

		-- Logged because the multiplier and the tier scalar are both visible
		-- in telemetry while the figure they produce was not, which left a
		-- report of armored targets moving further at trot than at gallop
		-- with nothing to check it against.
		if self.Config.LogTelemetry then
			self:Log("Impulse " .. self:NameOf(npc)
					.. " scale=" .. string.format("%.2f", impulseScale)
					.. " magnitude=" .. string.format("%.1f", impulseMag))
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
