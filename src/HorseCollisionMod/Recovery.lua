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
-- `ReleaseVictimMovement` is here rather than with the reaction that needs it
-- because its ordering belongs to the recovery: it must run on the tick after
-- the action starts, never before, or the fragment's own movement control
-- overwrites it and the call does nothing.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Recovery
-- @author jrandall54
-- @release 4.4.0

--- Stops the animation driving a victim's own movement.
--
-- `actor:SetMovementControlledByAnimation` is the runtime equivalent of a
-- fragment's `MovementControlMethod` layer, and it is the only lever that
-- applies to one victim rather than to every option in the database. Turning
-- it off leaves the actor on entity-driven movement, which is the state
-- vanilla's own hit reactions play in and the reason they respect geometry an
-- interactive action passes through.
--
-- Called on the tick after the action starts, never before it. An interactive
-- action applies the fragment's own movement control as it begins, so a call
-- made ahead of it is overwritten and does nothing at all: victims clipped
-- into walls exactly as they did without it.
--
-- @tparam table npc victim entity
-- @treturn boolean true when the call was accepted without error
function HorseCollisionMod:ReleaseVictimMovement(npc)
	if not npc.actor
			or type(npc.actor.SetMovementControlledByAnimation) ~= "function" then
		return false
	end

	local ok, err = pcall(function()
		npc.actor:SetMovementControlledByAnimation(false)
	end)

	if self.Config.LogTelemetry then
		self:Log("MovementControl released ok=" .. tostring(ok)
				.. " err=" .. tostring(err))
	end

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

	-- After the rebuild rather than alongside it. The rebuild is what resets
	-- the victim's behavior, and asking a brain to re-plan in the same frame
	-- it is being torn down and remade is asking the wrong one.
	--
	-- Leaving the area and returning restores a beggar or an innkeeper to
	-- their animation where this sequence does not, and the difference between
	-- the two is time: the engine's own teardown and rebuild are separated by
	-- however long the player was away.
	local generation = self.TimerTick

	Script.SetTimer(self.ReplanAfterRebuildMs, function()
		if generation ~= self.TimerTick then
			return
		end

		self:ReplanVictim(npc)
	end)
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
			speed = enum_daycycleHaltSpeed.instant
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

--- Runs something once a victim's reaction animation has finished.
--
-- Polls `actor:GetCurrentAnimationState()`, which reports
-- `AnimationControlled` for as long as an interactive action owns the actor.
-- Leaving that value is the reaction ending, which makes the wait an
-- observation instead of a guess at how long a particular clip runs.
--
-- The state must have been seen at least once before leaving it counts. A poll
-- landing in the gap before the action takes hold would otherwise read an
-- ordinary locomotion state and report a reaction that has not started yet as
-- already over.
--
-- @tparam table npc victim entity
-- @tparam function fn called with the reason (`state`, `ceiling` or
--   `unreadable`) and how long the wait took in milliseconds
function HorseCollisionMod:WhenReactionEnds(npc, fn)
	-- Entity ids are reused across a save load, so a wait booked before one
	-- and finishing after it would act on whichever NPC inherited the id,
	-- having been aimed at a victim from a world that no longer exists. The
	-- detection loop and the health watch carry the same guard.
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local deadline = startedAt + self.ReactionEndCeilingMs
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

		if state == self.ReactionAnimationState then
			seen = true
		elseif seen then
			fn("state", elapsed)

			return
		end

		if self:TimeMs() >= deadline then
			fn(seen and "ceiling" or "unreadable", elapsed)

			return
		end

		Script.SetTimer(self.ReactionPollMs, poll)
	end

	Script.SetTimer(self.ReactionPollMs, poll)
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
