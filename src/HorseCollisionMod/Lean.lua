--- Lean: leaning the rider out to see past the horse's head.
--
-- In first person the horse's head and neck sit between the rider and whatever
-- is directly in front, so lining up on someone and watching what happens to
-- them are both guesswork. A person solves this by moving their head to one
-- side and looking along the obstacle, which is parallax rather than rotation.
--
-- ### Why this is a shake
--
-- The camera cannot be moved any other way from Lua. All 47 `cl_cam*` CVars,
-- including the `cl_camModify` family that exists precisely to offset a camera,
-- are inert on the mounted first-person view. No bone is writable, so the head
-- the camera rides cannot be moved either. `PlayerSetViewAngles` turns the view
-- and holds, but turning the view does not help: the head is still between the
-- rider and the target, and now they are not even facing it.
--
-- `actor:SetViewShake` is the one call that displaces the camera. Its second
-- vector is a positional shake in meters, and vanilla uses it for explosions.
--
-- ### What the shake does
--
-- * **The peak is about 0.63 of the amplitude**, not the amplitude itself.
-- * **The peak arrives at t = period**, not at a quarter of it.
--
-- So the period is the time to full extension and the amplitude sets how far.
--
-- Firing a shake while one is running **reverses the camera's direction of
-- travel**. It neither sums with the running shake nor replaces it from zero.
--
-- That is a toggle for an actuator, and `System.GetViewCameraPos` is a sensor,
-- so the hold is bang-bang control: drive out, then flip on every crossing back
-- over the target. The hold corrects only outside `LeanDeadband`, so the
-- deadband sets how far the camera wobbles about the target.
--
-- A shake whose duration expires returns the camera home smoothly in about
-- 160 ms, and that is the release.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Lean
-- @author jrandall54

--- The action name this mod listens to for a lean, for a given key.
--
-- Each feature is declared once per candidate key in `hcm_actionmaps.xml`,
-- because Lua cannot write a file and `LoadFromXML` can only read one, so a
-- key cannot be rebound at runtime. The settings file picks which declaration
-- the mod answers to by naming the key.
--
-- Action maps are read once, at startup, so a key added to that file is dead
-- until the game is restarted.
--
-- @tparam string key one of the candidate keys
-- @tparam string side "left" or "right"
-- @treturn ?string the action name, or nil when no key is named
function HorseCollisionMod:LeanActionFor(key, side)
	if type(key) ~= "string" or key == "" then
		return nil
	end

	return "hcm_lean_" .. side .. "_" .. string.lower(key)
end

--- Where the camera sits across the horse, in meters from its centerline.
--
-- Measured against the **horse**, not against where the camera happened to be
-- when the lean started, and not against a remembered world position.
--
-- A world baseline is only valid standing still: at a walk the horse covers
-- more ground in a second than the whole lean travels, so the controller reads
-- the horse's journey instead of the camera's.
--
-- The rider's own resting position is not the right frame either: **the
-- camera rests about 6 cm to the horse's left**, so a lean of equal travel
-- each way would finish further out on the left. Against the centerline both
-- sides finish the same distance from the head, which is the thing being
-- aimed past.
--
-- @treturn ?number offset across the horse, positive to the horse's right
function HorseCollisionMod:LeanOffset()
	local horse = self:PlayerHorse()

	if not horse then
		return nil
	end

	local hp, fwd, cam = nil, nil, nil

	pcall(function()
		hp = horse:GetWorldPos()
		fwd = horse:GetDirectionVector(1)
		cam = System.GetViewCameraPos()
	end)

	if not hp or not fwd or not cam then
		return nil
	end

	local len = math.sqrt((fwd.x * fwd.x) + (fwd.y * fwd.y))

	if len <= 0 then
		return nil
	end

	local right = { x = fwd.y / len, y = -fwd.x / len }

	return ((cam.x - hp.x) * right.x) + ((cam.y - hp.y) * right.y)
end

--- How far off the horse's line the rider is looking, in degrees.
--
-- Leaning only makes sense while looking roughly along the horse. Turned far
-- enough to the side the camera travels into the rider's own body and into the
-- horse, because the offset is applied in camera space and the camera is
-- already inside the pair of them once it stops pointing down the horse's line.
--
-- @treturn ?number degrees, 0 looking straight ahead, never negative
-- @treturn boolean true if pitch limit was exceeded
function HorseCollisionMod:LeanViewAngle()
	local horse = self:PlayerHorse()

	if not horse then
		return nil, false
	end

	local dir, heading = nil, nil

	pcall(function()
		dir = System.GetViewCameraDir()
		heading = horse:GetDirectionVector(1)
	end)

	if not dir or not heading then
		return nil, false
	end

	-- Pitch is checked first. The yaw below is flattened so that looking up or
	-- down is not treated as looking away, and it stops meaning anything as
	-- the view nears vertical, which is also where the camera is nearest the
	-- rider's own model.
	local pitch = math.deg(math.asin(math.max(-1, math.min(1, dir.z))))
	local maxPitch = self.Config.LeanMaxPitchDeg

	if maxPitch > 0 and math.abs(pitch) > maxPitch then
		return nil, true
	end

	local dl = math.sqrt((dir.x * dir.x) + (dir.y * dir.y))
	local hl = math.sqrt((heading.x * heading.x) + (heading.y * heading.y))

	if dl <= 0 or hl <= 0 then
		return nil, false
	end

	-- Flattened, because looking up or down is not looking away.
	local dot = ((dir.x / dl) * (heading.x / hl)) + ((dir.y / dl) * (heading.y / hl))

	if dot > 1 then
		dot = 1
	elseif dot < -1 then
		dot = -1
	end

	return math.deg(math.acos(dot)), false
end

--- Flips the camera's direction of travel.
--
-- `SetViewShake` does not set a position or a speed. Firing it while a shake is
-- running reverses which way the camera is going; the sign of the amplitude
-- only chooses a direction when nothing is already running.
--
-- The forward component rides along on the same call, so a lean carries the
-- camera a little past the horse's shoulder rather than straight out from it.
--
-- @tparam number amplitude how hard, which sets how fast the camera travels
-- @tparam number sign the direction wanted, used only for the first call
-- @tparam number seconds how long this shake lives before it expires and
--   returns the camera home
function HorseCollisionMod:FlipLean(amplitude, sign, seconds)
	local cfg = self.Config
	if not player or not player.actor then
		return
	end

	-- Each correction is a shake entry in the rider's sixteen-entry animation
	-- queue for its whole lifetime; the deadband keeps the rate down.
	local now = self:TimeMs()

	self.LeanLastFlip = now
	self.LeanFlips = (self.LeanFlips or 0) + 1

	local forward = amplitude * cfg.LeanForwardShare

	pcall(function()
		player.actor:SetViewShake(
				{ x = 0, y = 0, z = 0 },
				{ x = amplitude * sign, y = forward, z = 0 },
				seconds, cfg.LeanShakePeriod, 0)
	end)
end

--- Leans out and holds there until the key is released.
--
-- Bang-bang control. The camera is driven out at the travel amplitude, and once
-- it has passed the target offset every crossing back over that offset flips it
-- again, so it dithers around the target rather than sailing past, within
-- `LeanDeadband`.
--
-- @tparam number sign -1 for left, 1 for right
function HorseCollisionMod:StartLean(sign)
	local cfg = self.Config

	if not cfg.Lean or self.LeanHeld then
		return
	end

	if not player or not player.actor then
		return
	end

	-- On foot there is no horse's head in the way, so there is nothing to lean
	-- around.
	local mounted = false

	pcall(function()
		mounted = player.human:IsMounted()
	end)

	if not mounted then
		return
	end

	self:ShowTutorial("lean")

	-- Refused when looking too far off the horse's line, because the camera
	-- travels in its own space and past a point that takes it through the
	-- rider and the horse rather than out beside them.
	local maxAngle = cfg.LeanMaxAngleDeg
	local angle, pitchExceeded = self:LeanViewAngle()

	if pitchExceeded then
		return
	end

	if maxAngle > 0 and angle and angle > maxAngle then
		return
	end

	-- Refused while the last lean is still on its way home, since a re-press
	-- would take its target from a displaced camera.
	local now = self:TimeMs()

	if self.LeanHomeUntil and now < self.LeanHomeUntil then
		return
	end

	-- Refused if the offset cannot be read, since the whole hold is closed loop
	-- on it and an open loop lean would travel until the key came up.
	if not self:LeanOffset() then
		return
	end

	self.LeanHeld = sign
	self.LeanFlips = 0
	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	local generation = self.LeanGeneration
	local timerTick = self.TimerTick
	-- A position across the horse rather than a distance traveled, so both
	-- sides finish the same distance from the head.
	local target = cfg.LeanDistance * sign
	local pollMs = cfg.LeanPollMs
	local reached = false
	local last = nil
	local turns = 0
	local lastAngle = nil
	local lastAngleAt = nil

	self:FlipLean(cfg.LeanTravelAmplitude, sign, cfg.LeanShakeSec)

	local function watch()
		if generation ~= self.LeanGeneration or timerTick ~= self.TimerTick then
			return
		end

		if not self.LeanHeld then
			return
		end

		local isMounted = false

		pcall(function()
			isMounted = player.human:IsMounted()
		end)

		if not isMounted then
			self:StopLean()

			return
		end

		-- Turning past the limit mid lean ends it, and the limit is **led by how
		-- fast the rider is turning**.
		--
		-- Ending a lean is not instant: the camera comes home over about 160 ms,
		-- so reacting at the limit is too late for a fast turn, and the view
		-- swings behind the rider while the camera is still displaced. The
		-- angle is projected forward by `LeanTurnLeadMs` at the current turn
		-- rate, so the limit tightens only for a fast turn.
		local turned, pitchViolation = self:LeanViewAngle()

		if pitchViolation then
			self:StopLean()

			return
		end

		local limit = cfg.LeanMaxAngleDeg

		if limit > 0 and turned then
			local now = self:TimeMs()
			local projected = turned

			if lastAngle and lastAngleAt and now > lastAngleAt then
				local rate = (turned - lastAngle) / ((now - lastAngleAt) / 1000)

				-- Only a turn heading toward the limit leads it. Coming back
				-- toward the horse's line should not cancel anything.
				if rate > 0 then
					projected = turned + (rate * (cfg.LeanTurnLeadMs / 1000))
				end
			end

			lastAngle = turned
			lastAngleAt = now

			if projected > limit then
				self:StopLean()

				return
			end
		end

		local offset = self:LeanOffset()

		if not offset then
			self:StopLean()

			return
		end

		-- Nothing may travel far past the target, whatever went wrong. The
		-- camera moves at nearly three meters a second on the way out, so a
		-- correction that does not land is meters away in a few seconds. A
		-- ceiling costs one comparison a poll and bounds any failure in here.
		local ceiling = cfg.LeanDistance * cfg.LeanRunawayFactor

		if math.abs(offset) > ceiling then
			self:StopLean()

			return
		end

		local hold = cfg.LeanHoldAmplitude
		local live = cfg.LeanShakeSec
		local past = (sign > 0 and offset >= target) or (sign < 0 and offset <= target)

		if not reached and last and not past then
			-- **The press cannot choose a direction, so it is checked.**
			--
			-- `SetViewShake` only picks a side when nothing is already
			-- running; against a live shake it reverses. Re-pressing
			-- inside the shake lifetime therefore sends the camera whichever
			-- way the last one was not going, so the direction is checked and
			-- corrected.
			--
			-- Two corrections are allowed, because one flip may not have
			-- reached the camera by the next poll and a third would mean
			-- something else is wrong.
			local moving = offset - last
			local gap = target - offset

			if turns < 2 and (gap * moving) < 0 and math.abs(moving) > 0.001 then
				turns = turns + 1
				self:FlipLean(cfg.LeanTravelAmplitude, sign, live)
			end
		end

		if not reached and past then
			-- Arrived: the one-time change down to the hold speed, made at
			-- once or the camera sails past the target at the travel speed.
			reached = true
			self:FlipLean(hold, sign, live)
		elseif reached and last then
			-- **Direction is measured, never remembered.**
			--
			-- A boolean flipped on each correction would assume the camera
			-- only changes direction when this loop turns it, and the expiry
			-- refresh below turns it too. Comparing two samples cannot go
			-- stale, whatever moved the camera or why.
			local moving = offset - last
			local gap = target - offset
			local band = cfg.LeanDeadband
			local now = self:TimeMs()
			local timeSinceFlip = self.LeanLastFlip and (now - self.LeanLastFlip) or 0

			-- Away from the target, and far enough out to be worth a
			-- correction. The deadband is what stops a flip every poll
			-- once the camera is sitting on the target.
			--
			-- Also renewed 150 ms before the running shake expires, which
			-- is several polls of warning, since an expired shake sends the
			-- camera home.
			local expired = timeSinceFlip > (live * 1000 - 150)
			local turning = math.abs(gap) > band and (gap * moving) < 0

			if turning or expired then
				self:FlipLean(hold, sign, live)
			end
		end

		last = offset

		Script.SetTimer(pollMs, watch)
	end

	if cfg.LogTelemetry then
		self:Log("LeanOut side=" .. (sign < 0 and "left" or "right")
				.. " target=" .. string.format("%.2f", math.abs(target)))
	end

	Script.SetTimer(pollMs, watch)
end

--- Releases the lean and lets the camera come home.
--
-- A shake whose duration expires returns the camera smoothly in about 160 ms,
-- so the release is a short shake rather than any attempt to drive back, and
-- `LeanHomeMs` refuses a new lean until the camera is home.
function HorseCollisionMod:StopLean()
	if not self.LeanHeld then
		return
	end

	local cfg = self.Config

	-- Read before the hold is cleared, because clearing it is what loses which
	-- side this lean was.
	local sign = self.LeanHeld

	self.LeanHeld = nil
	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	self.LeanHomeUntil = self:TimeMs() + cfg.LeanHomeMs

	self:FlipLean(cfg.LeanHoldAmplitude, sign, cfg.LeanReleaseSec)

	if cfg.LogTelemetry then
		local offset = self:LeanOffset()
		local angle = self:LeanViewAngle()

		self:Log("LeanBack side=" .. (sign < 0 and "left" or "right")
				.. " from=" .. (offset and string.format("%.2f", offset) or "none")
				.. " target=" .. string.format("%.2f", cfg.LeanDistance)
				.. " angle=" .. (angle and string.format("%.0f", angle) or "none")
				.. " flips=" .. tostring(self.LeanFlips or 0))
	end
end

--- Answers a key event, and reports whether it belonged to the lean.
--
-- @tparam string action the action name from `Player:OnAction`
-- @tparam string activation "press", "release" or "hold"
-- @treturn boolean true when the action was one of this feature's
function HorseCollisionMod:HandleLeanAction(action, activation)
	local cfg = self.Config

	if not cfg.Lean then
		return false
	end

	local left = self:LeanActionFor(cfg.LeanLeftKey, "left")
	local right = self:LeanActionFor(cfg.LeanRightKey, "right")
	local sign = nil

	if left and action == left then
		sign = -1
	elseif right and action == right then
		sign = 1
	else
		return false
	end

	if cfg.RequirePerks then
		local hasAbility = false

		if player and player.soul then
			pcall(function()
				hasAbility = player.soul:HasAbility("hcm_lean")
			end)
		end

		if not hasAbility then
			return false
		end
	end

	if activation == "press" then
		self:StartLean(sign)
	elseif activation == "release" then
		self:StopLean()
	end

	return true
end
