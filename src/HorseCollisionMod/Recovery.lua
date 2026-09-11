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
-- @release 5.4.0-dev.1
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

--- Runs something once a victim is no longer a settling ragdoll.
--
-- `GetPhysicalizationProfile` is not usable for this: measured through a whole
-- ragdoll sequence it read `alive` from start to finish. The animation state
-- does report `BlendRagdoll` while the body is being blended back, so that is
-- what is watched instead.
--
-- The state has to be seen before its absence counts, for the same reason the
-- reaction wait requires it: a poll landing before the ragdoll takes hold
-- would otherwise report a recovery that has not started as already over.
--
-- @tparam table npc victim entity
-- @tparam function fn called with the reason and the wait in milliseconds
function HorseCollisionMod:WhenRagdollResolves(npc, fn)
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local deadline = startedAt + self.RagdollResolveCeilingMs
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
			fn("resolved", elapsed)

			return
		end

		if self:TimeMs() >= deadline then
			fn(seen and "ceiling" or "neverRagdolled", elapsed)

			return
		end

		Script.SetTimer(self.ReactionPollMs, poll)
	end

	Script.SetTimer(self.ReactionPollMs, poll)
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

		if now - startedAt < self.RagdollResolveCeilingMs then
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


--- Whether a tier waits for a victim to be ready before it will land.
--
-- The wait exists for one reason: a knockdown clip starts from standing, so
-- playing it at a victim already flat on the ground has nothing to blend from
-- and looks wrong. That reason applies to the tiers that play an animation and
-- to no others.
--
-- A gallop ragdolls. There is no clip and no pose to start from, so no stage of
-- a victim's recovery makes it impossible, and the rider's position is that it
-- should always be available:
--
-- A gallop is pure physics, so it belongs on the table of possibilities at
-- any stage of a victim's recovery.
--
-- Leaving a gallop gated is also what produced the worst of the feedback
-- problem. The mod declined the impact, the engine's own collision happened
-- regardless, and what the rider got was the vanilla result: the horse wedged
-- in the victim, no reaction, and a bark. Nothing this mod does should ever
-- hand an impact back to that.
--
-- A charge is here for the same reason a gallop is. It is a physical ride-down
-- that ends in a ragdoll, and it is already scored as a gallop.
--
-- @tparam string tierName the tier the impact scored as
-- @treturn boolean true when this tier waits
function HorseCollisionMod:HitReadyApplies(tierName)
	local byTier = self.Config.HitReadyByTier

	if type(byTier) ~= "table" then
		return true
	end

	local applies = byTier[tierName]

	-- A tier nobody has decided about waits, because that is the older and
	-- more cautious behavior, but it says so rather than deciding silently.
	if applies == nil then
		if self.Config.LogTelemetry then
			self:Log("HitReadyApplies has no entry for tier "
					.. tostring(tierName) .. ", waiting by default")
		end

		return true
	end

	return applies and true or false
end


--- Clears a victim's hit cooldown when they are back on their feet.
--
-- `HitCooldownMs` and `KnockdownRecoveryMs` are fixed durations standing in
-- for a question the mod can now ask directly: is this victim in a state where
-- another impact would do anything. A knockdown at 6000 ms was short. Measured
-- on a `villageGuard` sampled every 250 ms, the whole arc runs about seven
-- seconds at both tiers:
--
--     gallop   MotionIdle 0-1.8   BlendRagdoll 2.0-4.3   MotionIdle 4.6-5.3
--              IdleToMove 5.6-6.8   MotionMovement 7.1+
--     trot     AnimationControlled 0.2-3.0   MotionIdle 3.3-3.8
--              BlendRagdoll 4.0-6.4          MotionMovement 6.6+
--
-- An impact landing inside that arc plays no reaction, because every reaction
-- is a standing animation, and usually costs no health either.
--
-- ### Two traps the trace exposes
--
-- **`MotionIdle` appears in the middle of both arcs**, so leaving the busy
-- state is not the same as being recovered. A trot victim is idle for three
-- quarters of a second between the fall clip ending and the ragdoll taking the
-- body, and a gate that fired there would be worse than the timer. The wait
-- therefore requires the settle window to pass with no busy state in it, and
-- any busy state seen restarts it.
--
-- **A gallop victim is not busy for the first two seconds.** The impulse takes
-- that long to physicalize, and until it does they read `MotionIdle`, which is
-- indistinguishable from having recovered. So the settle window does not begin
-- counting until a busy state has actually been seen. Without that the
-- cooldown would clear before the victim had even fallen over.
--
-- The ceiling is what makes it safe. A victim who is never seen busy, because
-- the reaction was suppressed or they were already dead, is released on the
-- ceiling rather than left permanently immune.
--
-- @tparam table npc victim entity
-- @tparam string npcId the key this victim's deadline is stored under
-- @tparam string tierName the tier that hit them, for the telemetry line
function HorseCollisionMod:WatchHitReady(npc, npcId, tierName)
	local cfg = self.Config
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local settle = cfg.HitReadySettleMs or 2000
	local ceiling = cfg.HitReadyCeilingMs or 12000
	local seenBusy = false
	local freeSince = nil

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		-- Someone hit again while still down restarts the whole wait, and this
		-- watcher is replaced by the one that impact starts.
		if self.RecentHits[npcId] == nil then
			return
		end

		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		local busy = state == self.RagdollAnimationState
				or state == self.ReactionAnimationState
		local now = self:TimeMs()
		local elapsed = now - startedAt

		if busy then
			seenBusy = true
			freeSince = nil
		elseif seenBusy and freeSince == nil then
			freeSince = now
		end

		local settled = freeSince ~= nil and (now - freeSince) >= settle
		local expired = elapsed >= ceiling

		if settled or expired then
			self.RecentHits[npcId] = nil

			if cfg.LogTelemetry then
				self:Log("HitReady " .. self:NameOf(npc)
						.. " tier=" .. tostring(tierName)
						.. " after=" .. tostring(elapsed) .. "ms"
						.. " state=" .. tostring(state)
						.. " on=" .. (settled and "settled" or "ceiling"))
			end

			return
		end

		Script.SetTimer(cfg.HitReadyPollMs or 250, poll)
	end

	Script.SetTimer(cfg.HitReadyPollMs or 250, poll)
end
