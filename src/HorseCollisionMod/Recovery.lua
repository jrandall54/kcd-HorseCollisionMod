--- Recovery: handing a victim back to the game after a collision.
--
-- A victim the mod has seized is not returned by the reaction ending. The
-- animation or the ragdoll finishing leaves an actor standing with no plan,
-- and something has to wait for that moment and then put the game back in
-- charge of them.
--
-- The waits here poll either `actor:GetCurrentAnimationState` or the body
-- itself. `AnimationControlled` means one of this mod's clips is playing;
-- `BlendRagdoll` is the get-up on a fall tier and the whole time down on a
-- ragdoll tier. Every wait carries a ceiling, because no state is guaranteed
-- to be observed at all, and a wait that never ends would strand the victim.
--
-- `ReleaseActorMovement` is here rather than with the reaction that needs it
-- because its ordering belongs to the recovery: it must run on the tick after
-- the action starts, never before, or the fragment's own movement control
-- overwrites it and the call does nothing.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Recovery
-- @author jrandall54

--- Stops the animation driving an actor's own movement.
--
-- `actor:SetMovementControlledByAnimation` is the runtime equivalent of a
-- fragment's `MovementControlMethod` layer, and it is the only lever that
-- applies to one actor rather than to every option in the database. Turning
-- it off leaves the actor on entity-driven movement, which is the state
-- vanilla's own hit reactions play in and the reason they respect geometry an
-- interactive action passes through.
--
-- Called on the tick after the action starts, never before it. An interactive
-- action applies the fragment's own movement control as it begins, so a call
-- made ahead of it is overwritten and does nothing.
--
-- Written for victims and used by the rear charge as well, where the actor is
-- the horse. The two want it at different moments, so the caller decides when.
--
-- @tparam table ent the actor entity
-- @tparam[opt] string what a name for the log line
-- @treturn boolean true when the call was accepted without error
function HorseCollisionMod:ReleaseActorMovement(ent, what)
	if not ent or not ent.actor
			or type(ent.actor.SetMovementControlledByAnimation) ~= "function" then
		return false
	end

	local ok, err = pcall(function()
		ent.actor:SetMovementControlledByAnimation(false)
	end)

	self:Log("MovementControl released on " .. tostring(what or "victim")
			.. " ok=" .. tostring(ok) .. " err=" .. tostring(err))

	return ok
end

--- How high a victim carries their body when they are on their feet.
--
-- The reading is the physics body's center-of-mass height above the entity
-- origin, which tracks posture. The tallest reading ever seen is kept, taken
-- at every impact, so a first reading off a body already down corrects itself
-- the first time the victim stands. It is the reference every later check is
-- read against, so nothing here is a number anybody chose.
--
-- @tparam table npc victim entity
function HorseCollisionMod:RecordStandingHeight(npc)
	if not npc or not npc.id then
		return
	end

	local id = tostring(npc.id)
	local head, origin = nil, nil

	pcall(function()
		head = npc:GetCenterOfMassPos().z
	end)

	pcall(function()
		origin = npc:GetWorldPos().z
	end)

	if not head or not origin or head <= origin then
		return
	end

	-- The tallest this victim has ever been seen, not the first reading. A
	-- maximum needs no threshold to decide whether a reading is plausible.
	local seen = head - origin
	local best = self.StandingHead[id]

	if not best or seen > best then
		self.StandingHead[id] = seen
	end
end

--- Holsters a victim's drawn weapon before a fall, and marks it for redrawing.
--
-- A drawn weapon on a body on the ground glitches its IK.
--
-- @tparam table npc victim entity
function HorseCollisionMod:DisarmVictim(npc)
	if npc and npc.human
			and npc.human:IsWeaponDrawn() then
		self.NeedsWeaponRedraw = self.NeedsWeaponRedraw or {}
		self.NeedsWeaponRedraw[tostring(npc.id)] = true
		pcall(function()
			npc.human:HolsterWeapon()
		end)
		if self.Config.LogTelemetry then
			self:Log("Disarmed " .. self:NameOf(npc) .. " to prevent IK glitch")
		end
	end
end

--- Draws a victim's weapon again if `DisarmVictim` holstered it.
--
-- @tparam table npc victim entity
function HorseCollisionMod:RearmVictim(npc)
	if not self.NeedsWeaponRedraw then
		return
	end
	local id = tostring(npc.id)
	if self.NeedsWeaponRedraw[id] then
		self.NeedsWeaponRedraw[id] = nil
		pcall(function()
			npc.human:DrawWeapon()
		end)
		if self.Config.LogTelemetry then
			self:Log("Rearmed " .. self:NameOf(npc) .. " after recovery")
		end
	end
end

--- Rearms a disarmed victim once they stand. Nothing calls it.
--
-- @tparam table npc victim entity
function HorseCollisionMod:WatchRecoveryForRearm(npc)
	if not self.NeedsWeaponRedraw or not self.NeedsWeaponRedraw[tostring(npc.id)] then
		return
	end

	self:WhenVictimStands(npc, function(why, waited)
		self:RearmVictim(npc)
	end)
end

--- Runs something once a victim leaves the ragdoll state, polling every
-- `RisePollMs` up to `RiseCeilingMs`. Only `WatchRecoveryForRearm` calls it.
--
-- @tparam table npc victim entity
-- @tparam function fn called with the reason and the wait in milliseconds
function HorseCollisionMod:WhenVictimStands(npc, fn)
	local generation = self.TimerTick
	local gap = self.Config.RisePollMs
	local ceiling = self.Config.RiseCeilingMs
	local spent = 0

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		if spent >= ceiling then
			fn("gave up", spent)
			return
		end

		local state = nil
		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		-- Out of the ragdoll state is standing.
		if state and not self:IsRagdollState(state) and state ~= "?" then
			fn("stood", spent)
			return
		end

		spent = spent + gap
		Script.SetTimer(gap, poll)
	end

	Script.SetTimer(gap, poll)
end

--- Whether a victim is lying flat rather than upright or getting up.
--
-- The single answer to "can this body take an animation right now", read from
-- the body rather than a clock. `headUp` is the height `RecordStandingHeight`
-- reads. Traced through a trot knockdown:
--
--     t+0000ms  AnimationControlled  headUp 1.55   upright, the impact lands
--     t+0624ms  AnimationControlled  headUp 0.94   falling
--     t+1840ms  AnimationControlled  headUp 0.15   flat
--     t+2448ms  MotionIdle           headUp 0.15   flat
--     t+3072ms  MotionIdle           headUp 0.15   flat
--     t+3664ms  BlendRagdoll         headUp 0.27   rising
--     t+4880ms  BlendRagdoll         headUp 1.21   rising
--     t+5472ms  BlendRagdoll         headUp 1.59   standing
--
-- On a fall tier `BlendRagdoll` is the get-up, and the flat stretch includes
-- `MotionIdle`, which no state test can tell from a person standing idle. On
-- a ragdoll tier the victim is in `BlendRagdoll` the whole time they are down
-- and the height reads as standing, so this test cannot see them flat;
-- `WhenVictimRises` uses the ragdoll state for those tiers.
--
-- @tparam table npc victim entity
-- @treturn boolean true while they are flat on the ground
-- @treturn number the current height, or -1 when unreadable
-- @treturn number the recorded standing height, or -1 when none is recorded
-- @treturn string the animation state, `"unrecorded"` or `"?"`
function HorseCollisionMod:IsVictimFlat(npc)
	if not npc or not npc.id then
		return false
	end

	local standing = self.StandingHead[tostring(npc.id)]

	if not standing then
		return false, -1, -1, "unrecorded"
	end

	local head, origin = nil, nil

	pcall(function()
		head = npc:GetCenterOfMassPos().z
	end)

	pcall(function()
		origin = npc:GetWorldPos().z
	end)

	if not head or not origin then
		return false, -1, standing, "?"
	end

	local state = nil

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	-- A reaction still playing counts as flat whatever the height, because the
	-- body is high through most of a fall and interrupting it breaks the pose.
	if state == self.ReactionAnimationState then
		return true, head - origin, standing, state
	end

	-- Everything else is decided by height. Against their own standing
	-- height, every flat reading is 0.04 or 0.10 of it, and every reading of a
	-- body that has begun to rise is 0.17 or more. `VictimFlatFraction` sits
	-- between the two with margin on both sides; half of standing would be
	-- most of the way to their feet.
	local fraction = self.Config.VictimFlatFraction

	return (head - origin) < (standing * fraction), head - origin, standing, state
end

--- Runs something the moment a victim stops lying flat and starts to rise.
--
-- The middle of a get-up, which a recovery line and the deferred crime want
-- to land on. Waiting for the reaction to end fires while the victim is still
-- on the ground, and waiting for `BlendRagdoll` to end fires once they are
-- already walking.
--
-- Two signals, one per kind of tier. On a fall tier the height test serves:
-- the body reads about 0.15 m flat and 1.59 m standing, so leaving flat is
-- the instant wanted, and flat has to be seen before its absence counts, or
-- a poll before the body reaches the ground would report a rise already
-- over. On a ragdoll tier the height test cannot see the victim flat, and the
-- ragdoll state serves instead: it fires the first time the victim is seen in
-- it, 1.7 to 2.0 s after impact.
--
-- @tparam table npc victim entity
-- @tparam function fn called with the reason and the wait in milliseconds
function HorseCollisionMod:WhenVictimRises(npc, fn)
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local deadline = startedAt + self.GetUpCeilingMs
	local seen = false

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		local elapsed = self:TimeMs() - startedAt
		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		-- The ragdoll tiers' signal; see the doc above. On a fall tier the
		-- ragdoll state is the get-up itself, so it serves there as well.
		if self:IsRagdollState(state) then
			fn("ragdoll", elapsed)
			return
		end

		if self:IsVictimFlat(npc) then
			seen = true
		elseif seen then
			fn("rising", elapsed)

			return
		end

		if self:TimeMs() >= deadline then
			-- The last reading goes with the verdict. `neverFlat` has two
			-- causes that look identical from outside: a body whose head this
			-- cannot read at all, and one it reads fine and never finds low.
			if self.Config.LogTelemetry then
				local _flat, headUp, standing = self:IsVictimFlat(npc)

				self:Log("WhenVictimRises " .. self:NameOf(npc)
						.. " gave up, headUp=" .. string.format("%.2f", headUp or -1)
						.. " standing=" .. string.format("%.2f", standing or -1))
			end

			fn(seen and "ceiling" or "neverFlat", elapsed)

			return
		end

		Script.SetTimer(self.ReactionPollMs, poll)
	end

	Script.SetTimer(self.ReactionPollMs, poll)
end

--- Whether an animation state means the body is in a ragdoll.
--
-- @tparam ?string state an animation state name
-- @treturn boolean true when the body is ragdolling
function HorseCollisionMod:IsRagdollState(state)
	return state ~= nil and self.RagdollAnimationStates[state] == true
end

--- Whether a victim's last fall clip has yet handed them to physics.
--
-- True from the moment a `hcm_fall_` clip starts until the body is seen in a
-- ragdoll state, or until the wait gives up on it. A second clip started in
-- that window cancels the handover the first one was carrying, and the
-- canceled handover lands later against whatever the victim is doing then.
--
-- @tparam table npc victim entity
-- @treturn boolean true while a handover is in flight
function HorseCollisionMod:HasFallPending(npc)
	if not npc or not npc.id then
		return false
	end

	return self.FallPending[tostring(npc.id)] == true
end

--- Marks a handover as in flight, and clears it when the body ragdolls.
--
-- @tparam table npc victim entity
function HorseCollisionMod:WatchFallHandover(npc)
	if not npc or not npc.id then
		return
	end

	local id = tostring(npc.id)

	self.FallPending[id] = true

	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local deadline = startedAt + self.GetUpCeilingMs

	local function poll()
		if generation ~= self.TimerTick then
			self.FallPending[id] = nil

			return
		end

		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		-- Cleared the moment the body is physics, which is the handover
		-- having happened and the window being over.
		if self:IsRagdollState(state) or self:TimeMs() >= deadline then
			self.FallPending[id] = nil

			return
		end

		Script.SetTimer(self.ReactionPollMs, poll)
	end

	Script.SetTimer(self.ReactionPollMs, poll)
end

--- Runs something once a victim has finished getting up.
--
-- It watches for the ragdoll state and fires when that state ends, which is
-- the victim standing, on either kind of tier. `GetPhysicalizationProfile` is
-- no use here: it reads `alive` from the impact to standing.
--
-- The state has to be seen before its absence counts. A poll landing before
-- the get-up begins would otherwise report a recovery that has not started as
-- already finished.
--
-- @tparam table npc victim entity
-- @tparam function fn called with the reason and the wait in milliseconds
function HorseCollisionMod:WhenVictimIsUp(npc, fn)
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local deadline = startedAt + self.GetUpCeilingMs
	local seen = false

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		local elapsed = self:TimeMs() - startedAt

		if self:IsRagdollState(state) then
			seen = true
		elseif seen then
			fn("stood", elapsed)

			return
		end

		if self:TimeMs() >= deadline then
			fn(seen and "ceiling" or "neverDown", elapsed)

			return
		end

		Script.SetTimer(self.ReactionPollMs, poll)
	end

	Script.SetTimer(self.ReactionPollMs, poll)
end

--- Runs something the moment a victim's body stops moving.
--
-- Rest means the entity has moved less than `RestStillMeters` since the last
-- poll. Read from position rather than from the animation state, because
-- `BlendRagdoll` never appears on a victim the impact killed. The entity
-- position does not track how far a ragdoll travels, but it moves until the
-- body settles, which is what timing the rest needs.
--
-- Exact position equality would be the wrong test: a body only returns
-- identical coordinates once the physics has fully slept, and a settled body
-- keeps micro-jittering well past the point it has visibly stopped.
--
-- The body has to be seen moving before stillness counts, or a victim struck
-- while standing still is reported at rest on the first poll, before the
-- collision has moved them at all.
--
-- The irreducible cost is the poll interval: Lua is given no physics event, so
-- this is observed rather than signaled and lands within one poll of the
-- moment it happens.
--
-- @tparam table npc victim entity
-- @tparam function fn called with the reason and the wait in milliseconds
function HorseCollisionMod:WhenBodyStops(npc, fn)
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local deadline = startedAt + self.RagdollLandCeilingMs
	local step = self.RestPollMs
	local moved = false
	local last = nil

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		local here = nil

		pcall(function()
			here = npc:GetWorldPos()
		end)

		local elapsed = self:TimeMs() - startedAt

		if here and last then
			local shift = math.sqrt((here.x - last.x) ^ 2
					+ (here.y - last.y) ^ 2
					+ (here.z - last.z) ^ 2)

			if shift >= self.RestStillMeters then
				moved = true
			elseif moved then
				fn("stopped", elapsed)

				return
			end
		end

		last = here

		if self:TimeMs() >= deadline then
			fn(moved and "ceiling" or "neverMoved", elapsed)

			return
		end

		Script.SetTimer(step, poll)
	end

	Script.SetTimer(step, poll)
end

--- Rebuilds a victim and sends them back to their activity.
--
-- The rebuild is skipped for a victim marked `hcm_combat_injected`, whom the
-- crime hit or a provocation has put into combat, because a rebuild would
-- wipe that combat state.
--
-- @tparam table npc victim entity
-- @tparam string action the reaction that played
-- @tparam string why how the wait before this ended
-- @tparam number waited how long that wait took, in milliseconds
function HorseCollisionMod:FinishRecovery(npc, action, why, waited)
	if npc.hcm_combat_injected then
		npc.hcm_combat_injected = nil

		if self.Config.LogTelemetry then
			self:Log("VictimRebuild skipped, active combat injected")
		end
	else
		self:RebuildVictim(npc)

		if self.Config.LogTelemetry then
			self:Log("VictimRebuild action=" .. action
					.. " on=" .. why
					.. " waited=" .. string.format("%.0f", waited) .. "ms")
		end
	end

	self:ReplanIfStranded(npc)
end

--- Records every animation state a victim passes through while recovering.
--
-- The recovery is not one phase. A victim is animation-driven while the fall
-- clip plays, limp while physics holds the body, and animation-driven again
-- while the game stands them up. A single duration covering all of it cannot
-- show which phase is long.
--
-- So each distinct state is timed and the sequence is logged as one line. Any
-- state occupying seconds is where the time is going, and it is named.
--
-- Diagnostic, and off unless `TraceRecovery` is set, because it polls at the
-- reaction poll rate for the length of a recovery.
--
-- @tparam table npc victim entity
-- @tparam string action the reaction that played
function HorseCollisionMod:TraceRecovery(npc, action)
	if not self.Config.TraceRecovery then
		return
	end

	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local seen = {}
	local current, since = nil, startedAt

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		-- Paired with the animation state, because the two answer different
		-- questions. The animation state says what is playing; the
		-- physicalization profile says who owns the body. `alive` is the
		-- engine's, `ragdoll` is physics, and `sleep` is a settled body that
		-- vanilla's own commented-out code pairs with `actor:StandUp`.
		pcall(function()
			state = state .. "/" .. tostring(npc.actor:GetPhysicalizationProfile())
		end)

		local now = self:TimeMs()

		if state ~= current then
			if current ~= nil then
				seen[#seen + 1] = current .. "=" .. string.format("%.0f", now - since) .. "ms"
			end

			current, since = state, now
		end

		if now - startedAt < self.GetUpCeilingMs then
			Script.SetTimer(self.ReactionPollMs, poll)

			return
		end

		seen[#seen + 1] = tostring(current)
				.. "=" .. string.format("%.0f", now - since) .. "ms"

		self:Log("RecoveryTrace " .. self:NameOf(npc)
				.. " action=" .. tostring(action)
				.. " " .. table.concat(seen, " "))
	end

	poll()
end

--- Replans a victim only when the game has not recovered them itself.
--
-- The replan restarts the victim's daycycle, which is the only way a beggar or
-- an innkeeper regains their loop: they are bound to a smart object they
-- cannot re-approach on their own, and without it they stand where they got
-- up. Everyone else recovers unaided, and for them the restart interrupts
-- correct behavior visibly: restarting the daycycle tears down the activity
-- holding any prop they carry, and they drop it.
--
-- The two cases are told apart by one reading, taken as soon as the victim is
-- up. A stranded victim sits in `MotionIdle`; a recovered one is already in
-- `MotionMovement`, `IdleToMove` or a turn.
--
-- A victim whose own activity is standing still is not stranded, so a state
-- matching what they were hit in counts as recovered whatever it is.
--
-- @tparam table npc victim entity
function HorseCollisionMod:ReplanIfStranded(npc)
	if not self.Config.ReplanAfterReaction then
		return
	end

	local id = tostring(npc.id)
	local was = self.VictimActivity[id]
	local state = nil

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	self.VictimActivity[id] = nil

	local idle = state ~= nil and string.find(state, "^MotionIdle") ~= nil
	local resumed = (was ~= nil and state == was) or not idle

	if self.Config.LogTelemetry then
		self:Log("Stranded " .. self:NameOf(npc)
				.. " was=" .. tostring(was)
				.. " now=" .. tostring(state)
				.. " resumed=" .. tostring(resumed))
	end

	if resumed then
		return
	end

	self:ReplanVictim(npc)
end

--- Sends a victim back to their activity by way of approaching it again.
--
-- A smart object reaches its loop through `Move` to the object followed by
-- `ExactMove directionType="AlignWithEntity"`, so the angle an NPC holds while
-- leaning on a wall or standing at a stall is the object's, written by the
-- approach rather than owned by the NPC.
--
-- A reaction leaves the victim near enough to that object to resume the loop
-- without approaching it. The alignment never runs, and the loop plays at
-- whatever angle the fall left them at, which reads in game as an innkeeper
-- leaning into a wall from the wrong side. A victim thrown clear of the object
-- walks back instead and is aligned correctly on the way in, which is the same
-- code producing the correct result for the only reason that matters: the
-- approach happened.
--
-- Restarting the daycycle is what makes the approach happen. Vanilla sends the
-- same message from `Libs/AI/final/sb_switch_hitreactions.xml` after its own
-- hit reactions, and from `Scripts/Haste/hasteInstruction_teleportBase.lua`
-- after teleporting an NPC, both being cases where a body has been moved
-- without its behavior being told.
--
-- Entity links are not involved: a victim's persistent assignments are
-- unchanged by a reaction and the rebuild, and no `usedSO` link appears.
--
-- @tparam table npc victim entity
-- @treturn boolean true when the message was accepted without error
function HorseCollisionMod:ReplanVictim(npc)
	if not self.Config.ReplanAfterReaction then
		return false
	end

	-- Sent with its members filled in.
	--
	-- `daycycle:restartRequest` declares `reason` and `speed` in
	-- `Libs/AI/TypeDefinitions.xml`, and a message with an empty payload is
	-- delivered and discarded with nothing for the receiving node to match on.
	-- Vanilla's own trees send it both as `values="reason(...), speed(...)"`
	-- and as a table built by `Utils.makeTable`, which is used here because it
	-- is checked against the type definition rather than parsed from text.
	local target = npc.id

	if npc.this and npc.this.id then
		target = npc.this.id
	end

	local ok, err = pcall(function()
		local message = Utils.makeTable("daycycle:restartRequest", {
			reason = enum_daycycleHaltReason.interrupt,
			speed = self.ReplanHaltSpeed
		})

		XGenAIModule.SendMessageToEntityData(target,
				"daycycle:restartRequest", message)
	end)

	if self.Config.LogTelemetry then
		self:Log("VictimReplan typed=" .. tostring(ok)
				.. " err=" .. tostring(err))
	end

	return ok
end

--- Rebuilds a victim so their own behavior reattaches to their body.
--
-- An animated reaction hands the victim's body to the animation, and their
-- behavior is never told. The reaction ends with the body standing where it
-- fell while the victim's own idea of where they are carries on elsewhere, and
-- the two only rejoin the next time the engine rebuilds the actor. A player
-- triggers that by looking away and back, which drops the NPC to a level of
-- detail the engine repositions them from; until then the victim stands still
-- and then appears to teleport.
--
-- `entity:Hide(1)` followed immediately by `entity:Hide(0)` forces that
-- rebuild. Both calls are made together, with no timer between them: the
-- teardown happens on the call rather than over elapsed time, so the actor is
-- rebuilt without ever missing a frame of rendering. Separating them by even
-- twenty milliseconds is visible as a blink and buys nothing.
--
-- @tparam table npc victim entity
-- @treturn boolean true when the calls were accepted without error
function HorseCollisionMod:RebuildVictim(npc)
	if type(npc.Hide) ~= "function" then
		return false
	end

	local ok, err = pcall(function()
		npc:Hide(1)
		npc:Hide(0)
	end)

	if self.Config.LogTelemetry then
		self:Log("VictimRebuild ok=" .. tostring(ok)
				.. " err=" .. tostring(err))
	end

	return ok
end

--- Whether enough time has passed since this victim was last scored.
--
-- One contact should be one impact. The detection loop runs every 33 ms and a
-- galloping horse takes about 150 ms to clear a person, so a single pass
-- crosses four or five ticks and every one of them is a collision by the
-- loop's reckoning. This asks whether the horse has already been charged for
-- the contact it is still in, which is a different question from whether a
-- victim can take an animation (`IsVictimFlat`).
--
-- The interval only has to outlast one pass. It must not approach the time a
-- player needs to turn around and come back, because a deliberate second run
-- is a second impact and should be scored as one.
--
-- @tparam string npcId the victim's id, as the table is keyed
-- @tparam number now the current time in milliseconds
-- @treturn boolean true when this impact should be scored
function HorseCollisionMod:ImpactIsNewContact(npcId, now)
	local interval = self.Config.HitMinIntervalMs

	if interval <= 0 then
		return true
	end

	-- An explicit lockout outlives the ordinary interval.
	--
	-- A charge is one deliberate move, not a series of collisions, so a victim
	-- it strikes is closed to further impacts for the whole of it rather than
	-- for the `HitMinIntervalMs` that separates two passes of a gallop.
	local until_ = self.LockedUntil and self.LockedUntil[npcId]

	if until_ and now < until_ then
		return false
	end

	local last = self.LastScoredHit[npcId]

	if last and now - last < interval then
		return false
	end

	return true
end
