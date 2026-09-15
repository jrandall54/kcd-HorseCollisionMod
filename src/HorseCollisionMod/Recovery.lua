--- Recovery: handing a victim back to the game after a collision.
--
-- A victim the mod has seized is not returned by the reaction ending. The
-- animation or the ragdoll finishing leaves an actor standing with no plan,
-- and something has to wait for that moment and then put the game back in
-- charge of them.
--
-- The two waits poll `actor:GetCurrentAnimationState`, which is the only
-- signal the engine offers for either transition: `AnimationControlled` while
-- one of this mod's clips is playing, `BlendRagdoll` while physics owns the
-- body. Both carry a ceiling, because neither state is guaranteed to be
-- observed at all, and a wait that never ends would strand the victim
-- permanently.
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
-- @release 5.14.2
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
-- made ahead of it is overwritten and does nothing at all: victims clipped
-- into walls exactly as they did without it.
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

--- How high a victim carries their head when they are on their feet.
--
-- Recorded once, at the first impact that reaches them, because a victim the
-- speed tiers have scored is by definition someone the horse rode into while
-- they were standing. It is the reference every later check is read against,
-- so nothing here is a number anybody chose.
--
-- @tparam table npc victim entity
function HorseCollisionMod:RecordStandingHeight(npc)
	if not npc or not npc.id then
		return
	end

	local id = tostring(npc.id)

	if self.StandingHead[id] then
		return
	end

	local head, origin = nil, nil

	pcall(function()
		head = npc.actor:GetHeadPos().z
	end)

	pcall(function()
		origin = npc:GetWorldPos().z
	end)

	if head and origin and head > origin then
		self.StandingHead[id] = head - origin
	end
end

--- Whether a victim is lying flat rather than upright or getting up.
--
-- The single answer to "can this body take an animation right now", and it
-- reads the body instead of a clock or a state string.
--
-- **Measured, through an untouched trot knockdown.** `headUp` is the head's
-- height above the entity origin, and the entity origin sits on the ground:
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
-- Two things that trace settles, both of which the rest of this mod had
-- wrong. **`BlendRagdoll` is the get-up, not the lie-down** -- the head climbs
-- right through it -- so anything treating that state as "still down" has the
-- sequence backwards. And the flat stretch is `AnimationControlled` followed
-- by `MotionIdle`, the second of which is indistinguishable from a person
-- standing about doing nothing, which is the hole every state-string test fell
-- through.
--
-- Nothing else measured separates the phases. The physicalization profile
-- reads `alive` from the impact to standing, the entity's pitch and roll stay
-- at 0.00 throughout because the entity does not rotate with the body, and the
-- velocity never exceeds 0.39.
--
-- The halfway point is a bisection rather than a tuned figure: flat reads 0.15
-- against a standing 1.55, so the two are an order of magnitude apart and any
-- split between them gives the same answer.
--
-- @tparam table npc victim entity
-- @treturn boolean true while they are flat on the ground
function HorseCollisionMod:IsVictimFlat(npc)
	if not npc or not npc.id then
		return false
	end

	local standing = self.StandingHead[tostring(npc.id)]

	if not standing then
		return false
	end

	local head, origin = nil, nil

	pcall(function()
		head = npc.actor:GetHeadPos().z
	end)

	pcall(function()
		origin = npc:GetWorldPos().z
	end)

	if not head or not origin then
		return false
	end

	local state = nil

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	-- A reaction still playing blocks regardless of height, because the body
	-- is high through most of a fall: it reads 0.94 of a standing 1.55 six
	-- hundred milliseconds in, and interrupting there is what broke the pose.
	if state == self.ReactionAnimationState then
		return true
	end

	-- `BlendRagdoll` is the get-up. The head climbs 0.27, 0.62, 1.21, 1.59
	-- across it, so reaching that state is the victim beginning to rise and is
	-- the moment they become a fair target again. Height alone cannot say so:
	-- the rise starts at 0.27 and does not pass halfway until a second later,
	-- which refuses a reaction through most of a get-up.
	if state == self.RagdollAnimationState then
		return false
	end

	-- What is left is the flat stretch, where the fall clip has ended and the
	-- ragdoll has not taken hold, and the victim reads `MotionIdle` face down.
	-- Height is the only thing that separates it from standing about, and the
	-- two are an order of magnitude apart -- 0.15 against 1.55 -- so the
	-- halfway split is a bisection rather than a tuned figure.
	return (head - origin) < (standing / 2)
end

--- Runs something once a victim has finished getting up.
--
-- Named for what it measures. It watches for `BlendRagdoll` and fires when
-- that state ends, which is not a ragdoll settling: sampling a knockdown
-- every 100ms shows
-- the head climbing 0.27, 0.62, 1.21, 1.59 across `BlendRagdoll`, so that
-- state is the get-up itself and its end is the victim back on their feet.
--
-- The distinction is not cosmetic. Two separate mechanisms were built on the
-- old reading, each treating `BlendRagdoll` as "still down", and both were
-- wrong in the same direction: they held a victim immune through the whole of
-- their own recovery. `docs/TECHNICAL_DETAILS.md` carries the measurements.
--
-- `GetPhysicalizationProfile` is no use here. Measured through the same
-- sequence it reads `alive` from the impact to standing, without exception.
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

		if state == self.RagdollAnimationState then
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
-- Rest is the same thing `ImpactThrow` already means by it: the body has moved
-- less than `RestStillMeters` since the last poll. Read from position rather
-- than from `GetVelocity`, and rather than from the animation state, because
-- `BlendRagdoll` never appears on a victim the impact killed.
--
-- Exact position equality is the stricter test and is the wrong one. A body
-- only returns identical coordinates once the physics has fully slept, and a
-- settled body keeps micro-jittering well past the point it has visibly
-- stopped: measured against the throw's own reading, equality fired between
-- 400ms and 1150ms late, which the rider saw as the damage landing long after
-- the body came to rest.
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
-- @tparam table npc victim entity
-- @tparam string action the reaction that played
-- @tparam string why how the wait before this ended
-- @tparam number waited how long that wait took, in milliseconds
function HorseCollisionMod:FinishRecovery(npc, action, why, waited)
	self:RebuildVictim(npc)

	if self.Config.LogTelemetry then
		self:Log("VictimRebuild action=" .. action
				.. " on=" .. why
				.. " waited=" .. string.format("%.0f", waited) .. "ms")
	end

	-- Watching starts here rather than after a delay. The delay that used to
	-- sit in front of this existed so a replan did not land in the frame the
	-- brain was being remade in; watching carries no such constraint, and the
	-- wait it imposed was paid by every victim including the ones that needed
	-- nothing.
	self:ReplanIfStranded(npc)
end

--- Records every animation state a victim passes through while recovering.
--
-- The recovery is not one phase. A victim is animation-driven while the fall
-- clip plays, limp while physics holds the body, and animation-driven again
-- while the game stands them up. A single duration covering all of it cannot
-- say which phase is long, and the complaint is about one of them: the pause
-- between the ragdoll taking hold and the victim beginning to rise.
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

--- Measures how far a victim has turned once the whole recovery is over.
--
-- A guard carrying a polearm was reported finishing his get-up facing roughly
-- the opposite way, where other victims do not. The get-up options carry no
-- weapon tag at all, four per direction and nothing else, so whatever is
-- happening is not a different clip being chosen. That leaves the victim's
-- orientation, which is what this measures.
--
-- Sampled at the impact and again well after the stand-up has finished, so it
-- covers the whole sequence rather than a phase of it. The item in hand is
-- recorded alongside, because the whole question is whether what a victim is
-- carrying changes the result.
--
-- Diagnostic, and off unless `TraceRecovery` is set.
--
-- @tparam table npc victim entity
-- @tparam string action the reaction that played
function HorseCollisionMod:WatchTurn(npc, action)
	if not self.Config.TraceRecovery then
		return
	end

	local function facing()
		local ok, dir = pcall(function()
			return npc:GetDirectionVector(1)
		end)

		if not ok or not dir then
			return nil
		end

		return { x = dir.x, y = dir.y }
	end

	-- Both hands, because a shouldered polearm is not in the main one, and the
	-- whole inventory as a fallback, because a weapon that is neither drawn nor
	-- held still reports nothing at all. Named by class rather than by WUID,
	-- which is what the hand calls return and is not readable.
	local held = {}

	pcall(function()
		for hand = 0, 1 do
			local wuid = npc.human and npc.human:GetItemInHand(hand)
			local entry = wuid and ItemManager.GetItem(wuid)

			if entry and entry.class then
				held[#held + 1] = "hand" .. hand .. "=" .. tostring(entry.class)
			end
		end
	end)

	pcall(function()
		local drawn = npc.human and npc.human:IsWeaponDrawn()
		held[#held + 1] = "drawn=" .. tostring(drawn)
	end)

	pcall(function()
		local carried = {}

		for _, wuid in pairs(npc.inventory:GetInventoryTable() or {}) do
			local entry = ItemManager.GetItem(wuid)

			if entry and entry.class then
				local name = tostring(entry.class)

				if string.find(name, "hlbrd") or string.find(name, "halberd")
						or string.find(name, "spear") or string.find(name, "pole")
						or string.find(name, "pike") or string.find(name, "axe") then
					carried[#carried + 1] = name
				end
			end
		end

		if #carried > 0 then
			held[#held + 1] = "polearm=" .. table.concat(carried, "/")
		end
	end)

	held = table.concat(held, " ")

	if held == "" then
		held = "none"
	end

	local before = facing()

	if not before then
		return
	end

	local generation = self.TimerTick

	local function report(at)
		local after = facing()

		if not after then
			return
		end

		-- The angle between two unit headings, from their dot product. Clamped
		-- because drift can push it outside the domain of acos and return nan
		-- for two identical headings.
		local dot = (before.x * after.x) + (before.y * after.y)

		if dot > 1 then
			dot = 1
		elseif dot < -1 then
			dot = -1
		end

		self:Log("Turn " .. self:NameOf(npc)
				.. " action=" .. tostring(action)
				.. " at=" .. tostring(at) .. "ms"
				.. " turned=" .. string.format("%.0f", math.deg(math.acos(dot)))
				.. "deg " .. held)
	end

	-- Twice, because the turn was described as happening near the end of the
	-- get-up and then being undone. One late sample cannot tell a victim who
	-- turned and came back from one who never turned.
	for _, at in pairs({ 5000, 9000 }) do
		Script.SetTimer(at, function()
			if generation == self.TimerTick then
				report(at)
			end
		end)
	end
end


--- Replans a victim only when the game has not recovered them itself.
--
-- The replan restarts the victim's daycycle, which is the only way a beggar or
-- an innkeeper regains their loop: they are bound to a smart object they
-- cannot re-approach on their own, and without it they stand where they got
-- up. Everyone else recovers unaided, and for them the restart interrupts
-- correct behavior visibly. A woman carrying a bucket drops it, because
-- restarting the daycycle tears down the activity holding the prop.
--
-- The two cases are told apart by one reading. A stranded victim sits in
-- `MotionIdle`; a recovered one is already in `MotionMovement`, `IdleToMove`
-- or a turn. Measured across nine recoveries, that held without exception.
--
-- Taken immediately rather than after a wait. Nothing about the reading
-- improves by being taken later, and everything a victim needs is owed to them
-- the moment they are on their feet: the wait was only ever the cost of a
-- weaker signal.
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
-- Entity links are not involved. Probing a victim before a reaction, after it
-- and after the rebuild showed an unchanged list of persistent assignments, a
-- home and a workplace, with no `usedSO` link visible at any point.
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
	-- `Libs/AI/TypeDefinitions.xml`, and every send this mod made before this
	-- one passed an empty payload. The message was delivered and discarded with
	-- nothing for the receiving node to match on, which is indistinguishable
	-- from a call that does nothing, and it is why a beggar, an innkeeper and a
	-- merchant could be left standing with no way found to recover them.
	--
	-- Measured on one victim parked after a collision: the empty send moved him
	-- 0.00 m and this one moved him 3.94 m, back to his stall.
	--
	-- The fault was the empty payload rather than the string form. Vanilla's own
	-- trees send this message both ways, as `values="reason(...), speed(...)"`
	-- and as a table built by `Utils.makeTable`, which is what is used here
	-- because it is checked against the type definition rather than parsed from
	-- text.
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
-- loop's reckoning.
--
-- Repeats were suppressed by accident before this existed. The readiness
-- wait blocked a second
-- impact for seconds afterward, which suppressed the repeats as a side effect
-- of suppressing everything. Taking a gallop out of that wait, so it can land
-- at any stage of a victim's recovery, removed the accident with it and the
-- repeats came straight back.
--
-- So they are separate rules now, because they are separate questions.
-- Readiness asks whether an animation has anything to blend from. This asks
-- whether the horse has already been charged for the contact it is still in.
-- A gallop needs the second and not the first.
--
-- The interval only has to outlast one pass. It must not approach the time a
-- rider needs to turn around and come back, because a deliberate second run is
-- a second impact and should be scored as one.
--
-- @tparam string npcId the victim's id, as the table is keyed
-- @tparam number now the current time in milliseconds
-- @treturn boolean true when this impact should be scored
function HorseCollisionMod:ImpactIsNewContact(npcId, now)
	local interval = self.Config.HitMinIntervalMs or 0

	if interval <= 0 then
		return true
	end

	-- An explicit lockout outlives the ordinary interval.
	--
	-- A charge is one deliberate move, not a series of collisions, so a victim
	-- it strikes is closed to further impacts for the whole of it rather than
	-- for the 700 ms that separates two passes of an ordinary gallop.
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
