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
-- @release 4.4.1

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
function HorseCollisionMod:Ragdoll(npc, velocity, speed, impulseScale)
	pcall(function()
		if npc.actor then
			npc.actor:Fall({x=0, y=0, z=0}, true)
		end
	end)

	self:ImpulseVictim(npc, velocity, impulseScale)

	-- Measured here as the control for the same reading taken on the fall
	-- path. This tier never seizes the actor, so it never rebuilds and never
	-- replans, and the engine recovers the victim on its own. How far a victim
	-- turns after that is therefore how far the game turns them with the mod
	-- doing nothing, which is the figure the fall path has to be compared
	-- against before anything is blamed for the difference.
	--
	-- Sampled from when the body settles rather than from the impact, so both
	-- tiers are measured from the same moment in their own sequence.
	local generation = self.TimerTick

	self:WhenRagdollResolves(npc, function(state)
		if generation ~= self.TimerTick then
			return
		end

		self:WatchHeading(npc, "ragdoll:" .. tostring(state))
	end)
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
function HorseCollisionMod:ImpulseVictim(npc, velocity, impulseScale)
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

		-- Forward push and upward lift are combined into one vector, then
		-- split back into a unit direction and a magnitude, because
		-- AddImpulse wants those as separate arguments.
		local combined = { x = dir.x * k_back, y = dir.y * k_back, z = k_up }
		local impulseMag = math.sqrt((combined.x * combined.x)
				+ (combined.y * combined.y)
				+ (combined.z * combined.z))

		-- Logged because the multiplier and the tier scalar are both visible
		-- in telemetry while the figure they produce was not, which left a
		-- report of armored targets moving further at trot than at gallop
		-- with nothing to check it against.
		if self.Config.LogTelemetry then
			self:Log("Impulse " .. tostring(npc:GetName())
					.. " scale=" .. string.format("%.2f", impulseScale)
					.. " magnitude=" .. string.format("%.1f", impulseMag))
		end

		if npc.AddImpulse and impulseMag > 0 then
			local normDir = {
				x = combined.x / impulseMag,
				y = combined.y / impulseMag,
				z = combined.z / impulseMag
			}

			-- The ragdoll needs a tick to physicalize before it accepts an
			-- impulse.
			Script.SetTimer(50, function()
				pcall(function()
					npc:AddImpulse(-1, hitPos, normDir, impulseMag, 1)
				end)
			end)
		end
	end)
end
