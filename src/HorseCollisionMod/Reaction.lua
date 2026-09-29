--- Reaction: making a victim visibly respond to being ridden into.
--
-- The three ways a collision reaches the victim's body, in ascending force.
-- `SendHitReaction` posts the native brain message, which feeds the victim's
-- perception but drives no animation and does not cause the vanilla bark.
-- `PlayReaction` runs one of this mod's own clips through
-- `actor:StartInteractiveActionByName`, the only call that moves an actor's
-- body from Lua. `Ragdoll` hands the body to physics instead, for the ragdoll
-- tiers, and `ImpulseVictim` pushes the body once physics owns it.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. The clip names are built from
-- the direction `Detection.lua` returns, and the reaction strengths are the
-- engine enums in `Enums.lua`, so both are read through `self` at call time
-- rather than captured when this file loads.
--
-- @module HorseCollisionMod.Reaction
-- @author jrandall54

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
-- @tparam string prefix the reaction family, `hcm_stagger_`, `hcm_fall_` or
--   `hcm_knockdown_`, completed with the impact direction
-- @treturn boolean true when the call was accepted without error
function HorseCollisionMod:PlayReaction(npc, velocity, prefix)
	if not npc.actor or type(npc.actor.StartInteractiveActionByName) ~= "function" then
		return false
	end

	local dir = self:GetImpactDir(npc, velocity)

	-- `GetImpactDir` speaks the engine's `so_left` vocabulary; this mod's option
	-- names and per-direction tables use the bare word.
	local side = string.gsub(dir, "so_", "")
	local action = prefix .. side

	-- Gender is logged because the two character sets resolve this call through
	-- separate databases, so a reaction can work on one and not the other and
	-- the misses look random without it.
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
		-- Disarm before ragdolling to prevent IK glitches on the ground
		if string.find(action, "fall") then
			self:DisarmVictim(npc)
		end

		-- The second argument is the object being interacted with. There is
		-- no object in a collision, so the victim is passed as its own
		-- target; the animation needs no alignment to anything external.
		npc.actor:StartInteractiveActionByName(
					action, npc.id, true, 1)
	end)

	-- Deferred for the same reason the ragdoll impulse is: an interactive
	-- action applies its fragment's movement layer as it starts, so the first
	-- release waits 50 ms, a tick or so past the start, or it is overwritten.
	--
	-- Repeated rather than asked once, because a fragment can apply that layer
	-- again as it blends between clips and undo a single release. The call is
	-- idempotent, so repeating it costs nothing.
	if self.Config.ReleaseAnimationMovement then
		local generation = self.TimerTick
		local attempts = self.Config.ReleaseMovementAttempts
		local gap = self.Config.ReleaseMovementGapMs

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
	-- rebuild that follows has to land after it: a victim can leave the ragdoll
	-- upright and still have no plan, and only the rebuild gives them one. Only
	-- the `hcm_fall_` fragments carry a Ragdoll ProcLayer, so only they get the
	-- wait; a stagger plays its clip and nothing follows.
	if prefix == "hcm_fall_" then
		-- The handover this clip carries is in flight. Nothing may start
		-- another clip on this victim until it has landed.
		self:WatchFallHandover(npc)

		self:TraceRecovery(npc, action)

		local generation = self.TimerTick

		self:WhenVictimIsUp(npc, function(state, waitedForBody)
			if generation ~= self.TimerTick then
				return
			end

			self:RearmVictim(npc)

			self:FinishRecovery(npc, action, state, waitedForBody)
		end)
	end

	self:Log("Reaction action=" .. action
			.. " gender=" .. gender
			.. " ok=" .. tostring(ok)
			.. " err=" .. tostring(err))

	return ok
end

--- What a tier does to the victim's body, dispatched from `ReactionByTier`.
--
-- The one place a tier is turned into a reaction. Reading the style from a
-- table means a tier that does not ragdoll cannot carry a throw figure at all.
--
-- The caller still owns whether a reaction happens. A walk is suppressed during
-- a fight and a victim already reacting is left alone; those are the caller's
-- policy about this impact, not a property of the tier.
--
-- @tparam table npc victim entity
-- @tparam string tierName "Walk", "Trot", "Gallop", "Rear" or "Charge"
-- @tparam table velocity horse velocity vector
-- @tparam number speed horse speed in meters per second
-- @tparam number armorScale the victim's armor impulse scale
-- @tparam table horsePos the horse's world position
-- @tparam table horseEnt the player's horse
-- @treturn boolean true when a reaction was started
function HorseCollisionMod:PlayTierReaction(npc, tierName, velocity, speed,
										   armorScale, horsePos, horseEnt)
	local style = self:TierValue("ReactionByTier", tierName)

	-- An animation is refused on a body that is lying flat, and only then.
	--
	-- A victim who has begun to get up takes the reaction, rather than
	-- shrugging off a hoof as vanilla does.
	--
	-- Only the animation is refused. The impact itself lands in full: a second
	-- hit on a victim already down registers and costs them health, so
	-- declining the whole thing loses damage the engine charges anyway. The
	-- sound, the dust, the marks and the damage all happen; the body
	-- stays where it is instead of snapping upright into a second fall.
	--
	-- The ragdoll styles are never refused. `Ragdoll` re-physicalizes a body
	-- that is already down on purpose, so a gallop and a charge can throw
	-- someone where they lie, and that is the behavior they should share.
	local animated = style == "stagger" or style == "knockdown"
			or style == "fall"

	if animated then
		local flat, headUp, standing, state = self:IsVictimFlat(npc)

		-- A fall clip is refused while the last one's handover is still in
		-- flight, whatever the victim's posture.
		--
		-- `hcm_fall_` carries its ragdoll as a ProcLayer that fires partway
		-- through the clip. Starting a second clip in that window cancels the
		-- handover the first was carrying, and the canceled handover lands
		-- later against whatever the victim is doing by then: they collapse
		-- seconds after the impact if they are idle, or are pulled limp in the
		-- middle of another clip, which lifts the body and drops it. This
		-- refuses only that, and only while it is pending.
		local unsettled = self.RagdollUnsettled and self.RagdollUnsettled[tostring(npc.id)]
		local pending = self:HasFallPending(npc) or unsettled
		local refused = flat or pending

		-- Logged whichever way it goes, because the interesting case is the
		-- one where a reaction was allowed and should not have been, and a
		-- decision that only speaks when it refuses cannot show you that.
		if self.Config.LogTelemetry then
			self:Log("FlatCheck " .. self:NameOf(npc)
					.. " tier=" .. tostring(tierName)
					.. " flat=" .. tostring(flat)
					.. " pending=" .. tostring(pending)
					.. " headUp=" .. string.format("%.2f", headUp or -1)
					.. " standing=" .. string.format("%.2f", standing or -1)
					.. " state=" .. tostring(state)
					.. " refused=" .. tostring(refused))
		end

		if refused then
			return false
		end
	end

	if style == "stagger" then
		return self:PlayReaction(npc, velocity, "hcm_stagger_")
	end

	if style == "knockdown" then
		return self:PlayReaction(npc, velocity, "hcm_knockdown_")
	end

	if style == "fall" then
		return self:PlayReaction(npc, velocity, "hcm_fall_")
	end

	if style ~= "ragdoll" then
		self:Log("PlayTierReaction tier=" .. tostring(tierName)
				.. " has no reaction style, nothing played")

		return false
	end

	local throw = self:TierValue("ThrowByTier", tierName)

	-- A ragdoll tier with no throw figure still goes down; it is not
	-- pushed. Said out loud rather than defaulted silently, because the only
	-- way to reach it is a player editing one table and not the other.
	if type(throw) ~= "number" then
		self:Log("PlayTierReaction tier=" .. tostring(tierName)
				.. " ragdolls with no ThrowByTier figure, dropping unpushed")

		throw = 0
	end

	-- The tier's throw profile: how it enters, what ceiling holds it and how
	-- hard, with every armor pair already blended against this victim.
	--
	-- Resolved once, here, and carried through the whole throw. Nothing
	-- downstream reads a tier name or a setting of its own, which is what
	-- keeps one tier's figures from reaching another's throw.
	local profile = self:ThrowProfile(tierName, armorScale)

	return self:Ragdoll(npc, velocity, speed, throw, armorScale,
			horsePos, horseEnt, profile, tierName)
end

--- Waits for a falling victim to become a physics body, then hands control on.
--
-- The settle fragment requests the ragdoll; it does not perform it. For one
-- frame after the request the victim is still an animated character, and
-- physics calls aimed at one are discarded silently, so the impulse, the brake
-- and the damping wait. The wait is `PhysicsReadyMs`, one frame, which is
-- when the handover is observed on every impact.
--
-- @tparam table npc victim entity
-- @tparam func onReady called once the body is physical
function HorseCollisionMod:WhenVictimIsPhysical(npc, onReady)
	local generation = self.TimerTick

	Script.SetTimer(self.PhysicsReadyMs, function()
		if generation ~= self.TimerTick then
			return
		end

		if onReady then
			onReady()
		end
	end)
end

--- Slows a ragdolled victim so it stops sliding.
--
-- A thrown body keeps going long after the throw, which makes the ground
-- read as ice.
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
--   unarmored victim and low for one in mail. Logged only; armor reaches the
--   throw through `profile`
-- @tparam[opt] table profile the tier's resolved throw profile, from
--   `ThrowProfile`. Carries the brake or the rail, the ceiling and the drag, all
--   already blended against this victim's armor. Without one the victim is
--   neither braked nor held, which is what a tier with no profile means
function HorseCollisionMod:DampVictim(npc, armorScale, profile)
	local damping = self.Config.RagdollDamping
	local minEnergy = self.Config.RagdollMinEnergy

	local npcId = tostring(npc.id)
	self.RagdollUnsettled = self.RagdollUnsettled or {}
	self.RagdollUnsettled[npcId] = true

	local pollMs = self.Config.RagdollDampPollMs
	local settleAt = self.Config.RagdollDampSettleSpeed
	local floorMs = self.Config.RagdollDampFloorMs
	local ceilingMs = self.Config.RagdollDampCeilingMs
	local generation = self.TimerTick
	local startedAt = self:TimeMs()

	-- Read from the physics body with `GetCenterOfMassPos`, because the
	-- entity's `GetWorldPos` does not follow a ragdoll.
	local function bodyPos()
		local at = nil

		pcall(function()
			at = npc:GetCenterOfMassPos()
		end)

		return at
	end

	local origin = bodyPos()

	-- Step 1, the brake: a counter-impulse along the body's own velocity that
	-- leaves it `keep` of the speed it arrived with. Logged as `Phase1Brake`.
	--
	-- Only a tier that reacts to the engine's throw carries a keep, and it is
	-- the only kind that brakes. A tier that commands its own throw has
	-- nothing of the engine's to subtract and carries a launch and a rail
	-- instead; the two are exclusive, because a tier doing both fights itself.
	local keep = (profile and profile.keep) or 1.0
	local braked = false

	-- The brake itself, separated from when it fires, because when it fires is
	-- the tier's business and the impulse is not.
	local function fireBrake(why)
		if braked or generation ~= self.TimerTick or not npc.AddImpulse then
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

		local speed = math.sqrt((vel.x * vel.x) + (vel.y * vel.y)
				+ (vel.z * vel.z))

		if speed <= 0.5 then
			return
		end

		braked = true

		local impulseMag = mass * speed * (1.0 - keep)

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
					.. " why=" .. why
					.. " speed=" .. string.format("%.2f", speed)
					.. " keep=" .. string.format("%.2f", keep)
					.. " mag=" .. string.format("%.1f", impulseMag)
					.. " mass=" .. string.format("%.1f", mass)
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end

	-- The brake fires at a fixed delay, 10 ms after `ImpulseDelayMs` so it
	-- lands after the impulse. That is right for the one tier that uses it:
	-- the gallop's victim is thrown by the engine's collision at the moment of
	-- contact, so by then the body is at or past its peak speed.
	if self.Config.RagdollBrake and keep < 1.0 then
		Script.SetTimer((self.Config.ImpulseDelayMs) + 10, function()
			fireBrake("delay")
		end)
	end

	-- Steps 2 and 3, the airborne cap and the settle, polled until the body
	-- rests. Logged as `Phase2Grounded`.
	local last = nil
	local moving = false
	local contactLog = {}
	local touching = 0
	local traveled = 0

	local airSamples = 0
	local airPeak = 0

	-- The tier's cap, resolved once. It does not change over a throw.
	local capSpeed = (profile and profile.cap) or 0

	-- Whether this tier holds its rail by taking the excess speed away, and
	-- how many times it had to.
	local railEnforce = (profile and profile.railEnforce) or false
	local railImpulses = 0

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
					.. " railHits=" .. tostring(railImpulses)

					-- How far the body came, beside the fraction of its speed
					-- it was allowed to keep.
					.. " achieved=" .. string.format("%.2f", traveled)
					.. " sDamp=" .. string.format("%.2f", damping * scale)
					.. " ok=" .. tostring(ok)
					.. " err=" .. tostring(err))
		end
	end

	local function release()
		-- Woken before the write, because a sleeping body cannot receive one.
		--
		-- `min_energy` is the threshold below which physics puts a body to
		-- sleep, and a sleeping body ignores impulses and parameter writes
		-- alike. A body that slept before this watch ended would silently
		-- discard the release and keep `min_energy` permanently; a corpse
		-- carrying it sleeps the moment it slows, and one lifted by the horse
		-- and then left unsupported holds its position in the air.
		--
		-- `AwakePhysics` is the neighboring call to `SetPhysicParams`, and
		-- vanilla uses it on doors and elevators for the same reason.
		pcall(function()
			npc:AwakePhysics(1)
		end)

		pcall(function()
			npc:SetPhysicParams(PHYSICPARAM_SIMULATION, { damping = 0, min_energy = 0 })
		end)

		self.RagdollUnsettled[npcId] = nil
	end

	local function watch()
		if generation ~= self.TimerTick then
			return
		end

		-- The physics body again, and not as instrumentation: the speed
		-- derived from these positions is what the airborne cap and the drag
		-- act on, so it must be the body's own.
		local here = bodyPos()

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

		-- Drag on a body still traveling and not yet settled, and the lever
		-- that decides how far a victim goes.
		--
		-- The cap is what armor scales. It is a ceiling rather than a
		-- subtraction, so it does not care how the body got its speed or when
		-- the engine stopped pushing: a body held under 2.5 m/s cannot travel
		-- like one allowed 6.0 however it was set moving. A one-shot correction
		-- cannot do that, because the horse's collider goes on driving a limp
		-- body well past the moment of impact and overwrites whatever was
		-- applied once.
		--
		-- On a tier the mod throws itself the same figure is a rail rather
		-- than a ceiling: it is resolved to the speed that tier commanded, so
		-- it cannot shorten the throw and catches only what the collider adds
		-- on top of it afterwards.
		local cap = capSpeed

		lastCap = cap

		-- Holding the rail by taking the excess speed away, for a tier that
		-- commands its own throw.
		--
		-- Drag does not bind a ragdoll the horse's collider keeps pushing. A
		-- counter-impulse does, the same mechanism as the brake:
		-- `mass * (speed - cap)` against the body's own velocity removes
		-- exactly the excess and leaves the rail. It is applied on every poll
		-- the body is over the line rather than once, because the collider
		-- goes on pushing long after any single moment.
		--
		-- This cannot shorten the throw the tier commanded. The rail *is* that
		-- commanded speed, so it removes only what the collider added on top.
		if railEnforce and cap > 0 and speed and speed > cap
				and touching < (self.Config.RagdollDampContactRun) then
			pcall(function()
				local vel = npc:GetVelocity()
				local pos = npc:GetCenterOfMassPos()
				local mass = 0
				local stats = npc:GetPhysicalStats()

				if stats and stats.mass then
					mass = stats.mass
				end

				if not vel or not pos or mass <= 0 then
					return
				end

				local held = self:VectorLength(vel)

				if held <= cap then
					return
				end

				npc:AddImpulse(-1, pos, {
					x = -vel.x / held,
					y = -vel.y / held,
					z = -vel.z / held
				}, mass * (held - cap), 1)

				railImpulses = railImpulses + 1
			end)
		end

		if cap > 0 and speed and
				touching < (self.Config.RagdollDampContactRun) then
			local strength = 0
			if speed > cap then
				strength = (speed - cap) / (self.Config.RagdollSpeedSoftCapSpan)
				if strength > 1 then
					strength = 1
				end
				airSamples = airSamples + 1
				if speed > airPeak then
					airPeak = speed
				end
			end

			-- The drag itself is armor scaled, not only the ceiling.
			-- `strength` is `(speed - cap) / span` clamped to 1, so past
			-- `cap + span` it saturates and every victim would receive the
			-- same drag however their ceiling was set; the drag figure is what
			-- separates them on a hard throw.
			local drag = profile.drag

			lastDrag = drag

			pcall(function()
				npc:SetPhysicParams(PHYSICPARAM_SIMULATION, {
					damping = drag * strength
				})
			end)
		end

		if moving and elapsed >= floorMs
				and touching >= (self.Config.RagdollDampContactRun) then
			local ramp = self.Config.RagdollDampRampSamples
			local share = (touching - (self.Config.RagdollDampContactRun)) / ramp

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
-- Used by the ragdoll tiers, the gallop and the charge. The settle fragment
-- switches the victim to a ragdoll, after which an impulse can be applied.
-- Impulses are ignored on an upright, animation-driven actor, so the order
-- matters and the impulse waits for `WhenVictimIsPhysical`.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number speed horse speed in meters per second
-- @tparam number tierScale the tier's `ThrowByTier` trim on `Knockback` and
--   `Uplift`
-- @tparam number armorScale the victim's armor scale, passed on for logging;
--   armor reaches the throw through `profile`
-- @tparam table horsePos horse world position, the origin a push points away
--   from, so a victim is never thrown back under the rider
-- @tparam[opt] table horseEnt the player's horse, for the barding force bonus
-- @tparam[opt] table profile the tier's resolved throw profile, from
--   `ThrowProfile`: how the throw enters, the ceiling that holds it and the
--   drag that holds it there, all blended against this victim's armor
-- @tparam[opt] string tierName the tier this impact resolved as, logged on the
--   `FallToBlend` line
function HorseCollisionMod:Ragdoll(npc, velocity, speed, tierScale, armorScale,
								   horsePos, horseEnt, profile, tierName)
	-- Undo the previous impact's damping before doing anything else.
	--
	-- `DampVictim` sets `damping` and `min_energy` to stop a thrown body
	-- sliding forever. A physics body below its minimum energy is put to sleep,
	-- and a sleeping body ignores impulses and parameter writes alike, so on a
	-- victim hit while already down the impulse would be accepted and do
	-- nothing. Clearing both wakes it, so the fall and the impulse below meet
	-- a body that can respond.
	pcall(function()
		npc:SetPhysicParams(PHYSICPARAM_SIMULATION, {
			damping = 0, min_energy = 0
		})
	end)

	-- The ragdoll is requested through an interactive action rather than
	-- `actor:Fall`.
	--
	-- `actor:Fall` only queues a physics transition, which waits behind an
	-- uninterruptible animation such as a get-up, so a victim could take the
	-- hit, walk on and collapse seconds later. `SettleFragTag` is an empty
	-- fragment with a Ragdoll ProcLayer at ExitTime 0; as an interactive action
	-- it aborts whatever the victim is doing and ragdolls them at once.
	local function requestFall()
		pcall(function()
			self:DisarmVictim(npc)

			if npc.actor then
				npc.actor:StartInteractiveActionByName(
					self.Config.SettleFragTag,
					npc.id, false, 1.0)
			end
		end)
	end

	requestFall()

	-- How far the victim travels between the fall and the blend out of the
	-- ragdoll, logged as `FallToBlend`.
	--
	-- Both readings sit outside the ragdoll, where the entity matches the body.
	-- `requestFall` is the last moment the victim is still animation-driven,
	-- and the engine re-syncs the entity to the body to play the blend, so
	-- `GetWorldPos` is right at both ends. The figures are relative: they do
	-- not match the distance seen on screen.
	--
	-- `BlendRagdoll` is what `IsRagdollState` already recognizes, and the poll
	-- interval and ceiling are `RisePollMs` and `RiseCeilingMs`.
	if self.Config.LogTelemetry then
		local generation = self.TimerTick
		local gap = self.Config.RisePollMs
		local ceiling = self.Config.RiseCeilingMs
		local spent = 0
		local from = nil

		pcall(function()
			from = npc:GetWorldPos()
		end)

		if from then
			from = { x = from.x, y = from.y, z = from.z }
		end

		local function reached()
			if generation ~= self.TimerTick then
				return
			end

			local state = nil

			pcall(function()
				state = tostring(npc.actor:GetCurrentAnimationState())
			end)

			local blending = state and self:IsRagdollState(state)

			if not blending and spent < ceiling then
				spent = spent + gap
				Script.SetTimer(gap, reached)

				return
			end

			local to = nil

			pcall(function()
				to = npc:GetWorldPos()
			end)

			local moved = -1

			if from and to then
				moved = self:VectorLength({
					x = to.x - from.x,
					y = to.y - from.y,
					z = 0
				})
			end

			self:Log("FallToBlend " .. self:NameOf(npc)
					.. " tier=" .. tostring(tierName)
					.. " armorScale=" .. string.format("%.2f", armorScale or 1.0)
					.. " moved=" .. string.format("%.2f", moved)
					.. " afterMs=" .. tostring(spent)
					.. " state=" .. tostring(state)
					.. " why=" .. (blending and "blend" or "ceiling"))
		end

		Script.SetTimer(gap, reached)
	end

	-- `actor:RagDollize` does not belong here and must not be added back. It
	-- asks for the physics profile directly rather than telling the actor to
	-- fall, so it looks like the answer for re-hitting a victim who is already
	-- down, and in game it snaps the victim upright into a T-pose.

	-- The gallop's victim is thrown by the engine's own collision and braked
	-- here; the charge's is thrown by the launch in `ImpulseVictim`. Both wait
	-- for a body that physics owns.
	self:WhenVictimIsPhysical(npc, function()
		self:ImpulseVictim(npc, velocity, tierScale, horsePos, horseEnt,
				profile)
		self:DampVictim(npc, armorScale, profile)
	end)

	-- Traced as `engine-ragdoll`, for comparison with the fall path.
	self:TraceRecovery(npc, "engine-ragdoll")

	local generation = self.TimerTick
	self:WhenVictimIsUp(npc, function()
		if generation ~= self.TimerTick then
			return
		end
		self:RearmVictim(npc)
	end)
end

--- Pushes a victim who is already a physics body.
--
-- The trim push from `Knockback` and `Uplift`, plus the barding bonus, and
-- for a tier with a launch the shortfall up to the commanded speed. Called
-- from `Ragdoll` once the body is physical.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number tierScale the tier's `ThrowByTier` trim
-- @tparam table horsePos horse world position, the origin the push points away
--   from, so a victim is never thrown back under the rider
-- @tparam[opt] table horseEnt the player's horse, for the barding force bonus
-- @tparam[opt] table profile the tier's resolved throw profile, which carries
--   the launch when there is one
function HorseCollisionMod:ImpulseVictim(npc, velocity, tierScale, horsePos,
										horseEnt, profile)
	-- Barding is a flat addition to the two force figures rather than a factor
	-- on the result, so a barded horse adds the same absolute push whoever it
	-- hits, and the victim's own armor still scales the whole thing.
	--
	-- Added in five steps, so what a given horse gets is readable straight off
	-- the table in the settings file rather than out of a curve.
	local bonus = self:BardingForceBonus(horseEnt)

	local k_back = (self.Config.Knockback + bonus.knockback) * tierScale
	local k_up = (self.Config.Uplift + bonus.uplift) * tierScale

	-- The speed this tier's launch is entitled to, if it has one. A tier the
	-- engine's own collision already throws does not, and adds nothing.
	local launch = (profile and profile.launch) or 0

	if type(launch) ~= "number" or launch < 0 then
		launch = 0
	end

	-- A tier with a launch still has work to do here with the two trim figures
	-- set to nothing, because the launch is the part of this that carries the
	-- throw.
	if k_back <= 0 and k_up <= 0 and launch <= 0 then
		return
	end

	pcall(function()
		local hitPos = { x = 0, y = 0, z = 0 }
		local dir = { x = 1, y = 0, z = 0 }

		if npc.GetPos then
			hitPos = npc:GetPos()
		end

		-- Lift the application point a meter above the victim's origin,
		-- roughly chest height, so the victim rotates over the impact instead
		-- of having their feet swept.
		hitPos.z = hitPos.z + 1.0

		-- Normalized against the velocity's own length, not against the
		-- scored speed. Those are different numbers: the score is the peak of
		-- the last few ticks, chosen so a collision is rated by the speed the
		-- horse carried into it, while the velocity here is what the horse is
		-- doing now, after the contact has slowed it.
		--
		-- Dividing one by the other would leave a direction shorter than unit,
		-- so knockback would vary with how hard the horse happened to brake
		-- rather than with the tier and the target.
		local moving = self:VectorLength(velocity or { x = 0, y = 0, z = 0 })

		if moving > 0 then
			dir.x = velocity.x / moving
			dir.y = velocity.y / moving
			dir.z = 0
		else
			-- No velocity means no direction to throw along, and the default
			-- above is world +X, which is not a direction anything in the
			-- game is facing, so the impulse is dropped rather than sent the
			-- wrong way. The horse's velocity can read zero through the rear
			-- animation.
			self:Log("ImpulseVictim " .. self:NameOf(npc)
					.. " no velocity to throw along, dropping the impulse")

			return
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
		local lateral = self.Config.LateralImpulse

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

		-- Logged because the multiplier and the tier scalar are visible in
		-- telemetry elsewhere and the figure they produce is not.
		if self.Config.LogTelemetry then
			-- The mass is read rather than assumed, because the throw is a
			-- velocity and the velocity is the magnitude over the mass. The
			-- engine's figure is the only one there is: the mod writes no mass
			-- of its own, so this is what the impulse actually meets.
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

		if npc.AddImpulse and (impulseMag > 0 or launch > 0) then
			-- The shape of the push, separated from how hard it is, because
			-- the launch below is decided when the impulse lands rather than
			-- here and has to be sent along the same line.
			--
			-- A tier carrying a launch and no trim has nothing to normalize,
			-- so the direction falls back to the horse's own line with no
			-- lateral component and no lift. That is a throw straight along
			-- the charge, which is the right thing to do with a figure the
			-- player set to zero on purpose.
			local normDir = { x = dir.x, y = dir.y, z = dir.z }

			if impulseMag > 0 then
				normDir.x = combined.x / impulseMag
				normDir.y = combined.y / impulseMag
				normDir.z = combined.z / impulseMag
			end

			-- The ragdoll needs time to physicalize before it accepts an
			-- impulse, and one applied too early is ignored without saying so;
			-- the wait is `ImpulseDelayMs`.
			--
			-- No tier both brakes and launches, so this never has to be
			-- ordered against the brake.
			Script.SetTimer(self.Config.ImpulseDelayMs, function()
				-- The launch, decided here rather than where the trim was,
				-- because it is a floor under the body's speed and the body's
				-- speed is only knowable at the moment the impulse lands.
				--
				-- `ThrowProfileByTier` carries the derivation: the charge
				-- commands its throw because the engine does not reliably
				-- deliver one, while the gallop is thrown by a real collision
				-- and subtracts from it instead.
				local total = impulseMag

				if launch > 0 then
					local held = 0
					local mass = 0

					pcall(function()
						local vel = npc:GetVelocity()

						if vel then
							held = self:VectorLength(vel)
						end

						local stats = npc:GetPhysicalStats()

						if stats and stats.mass then
							mass = stats.mass
						end
					end)

					-- A floor, not the whole throw.
					--
					-- Only the shortfall above what the body already holds is
					-- sent, so a charge that did catch a real shove from the
					-- collider is not thrown twice. A body the collider shoved
					-- past the tier's figure is the rail's job in `DampVictim`:
					-- anything written once here, `ImpulseDelayMs` after
					-- impact, is overwritten by whatever the collider does
					-- next. Floor here, ceiling in the watch.
					--
					-- Armor has already been applied, when the profile was
					-- resolved. It is not applied again here.
					local shortfall = launch - held

					if mass > 0 and shortfall > 0 then
						total = total + (mass * shortfall)
					end

					if self.Config.LogTelemetry then
						self:Log("Launch " .. self:NameOf(npc)
								.. " commanded=" .. string.format("%.2f", launch)
								.. " horse=" .. string.format("%.2f", moving)
								.. " held=" .. string.format("%.2f", held)
								.. " added=" .. string.format("%.1f",
								total - impulseMag)
								.. " mass=" .. string.format("%.1f", mass))
					end
				end

				-- The launch goes along the ground, not along the trim's
				-- line. `Knockback` and `Uplift` are 50 and 30, so the
				-- direction they shape is about half vertical, and a launch
				-- sent along it throws a body high through the air. A horse
				-- knocking someone down drives them along its own line with
				-- the lift as trim on top, so the launch is added to the
				-- trim's vector rather than sent through its direction.
				local sendDir = normDir
				local sendMag = total

				if total > impulseMag then
					local extra = total - impulseMag
					local sum = {
						x = (normDir.x * impulseMag) + (dir.x * extra),
						y = (normDir.y * impulseMag) + (dir.y * extra),
						z = normDir.z * impulseMag
					}

					sendMag = math.sqrt((sum.x * sum.x) + (sum.y * sum.y)
							+ (sum.z * sum.z))

					if sendMag > 0 then
						sendDir = {
							x = sum.x / sendMag,
							y = sum.y / sendMag,
							z = sum.z / sendMag
						}
					end
				end

				local ok, err = pcall(function()
					npc:AddImpulse(-1, hitPos, sendDir, sendMag, 1)
				end)

				-- The line written when the impulse is computed says only
				-- what was intended; this one reports the call itself.
				if self.Config.LogTelemetry then
					self:Log("ImpulseApplied " .. self:NameOf(npc)
							.. " ok=" .. tostring(ok)
							.. " err=" .. tostring(err))
				end
			end)
		end
	end)
end
