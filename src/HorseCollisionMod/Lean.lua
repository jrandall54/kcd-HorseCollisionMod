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
-- ### What the shake actually does, measured
--
-- Polled from `System.GetViewCameraPos` every 100 ms across a full cycle. At
-- amplitude 2.0 and period 8.0 the camera reaches **1.264 m at 8.0 s** and then
-- falls away again.
--
--     2000ms 0.41   4000ms 0.78   6000ms 1.02   8064ms 1.264   12064ms 0.485
--
-- Two rules come out of it, and both differ from what the argument names
-- suggest:
--
-- * **The peak is about 0.63 of the amplitude**, not the amplitude itself.
-- * **The peak arrives at t = period**, not at a quarter of it.
--
-- So the period is the time to full extension and the amplitude sets how far.
-- A shake cut before its peak returns home smoothly in about 160 ms.
--
-- Sampling a short window is what makes this mechanism easy to get wrong: over
-- its first eighth the curve is indistinguishable from a straight line, and
-- reading a velocity off it gives an amplitude twenty times too large.
--
-- Firing a shake while one is running **reverses the camera's direction of
-- travel**. It neither sums with the running shake nor replaces it from zero.
-- Four identical calls two seconds apart drove the camera out, back through
-- center, out again and back, each flip smooth and continuous.
--
-- That is a toggle for an actuator, and `System.GetViewCameraPos` is a sensor,
-- so the hold is bang-bang control: drive out, then flip on every crossing back
-- over the target. The residual wobble is the travel speed times the poll
-- interval, which at the hold amplitude is under a centimeter.
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
-- The rider's own resting position is not the right frame either, and that is
-- what made the two sides read differently. Measured, the rider's entity sits
-- on the centerline to within 7 mm but **the camera rests 6 cm to the horse's
-- left**, so a lean of equal travel each way finishes 0.71 m out on the left
-- and 0.59 m on the right. A rider judging against the horse's head sees that
-- as the left reaching further, which is exactly what was reported.
--
-- Against the centerline both sides finish the same distance from the head,
-- which is the thing being aimed past. The travel differs slightly instead,
-- and travel is not what anyone is looking at.
--
-- @treturn ?number offset across the horse, positive to the horse's right
function HorseCollisionMod:LeanOffset()
	local playerEnt = rawget(_G, "player")
	local horse, hp, fwd, cam = nil, nil, nil, nil

	if not playerEnt then
		return nil
	end

	pcall(function()
		horse = XGenAIModule.GetEntityByWUID(playerEnt.player:GetPlayerHorse())
	end)

	if not horse then
		return nil
	end

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
-- @treturn ?number degrees, 0 looking straight ahead, always positive
function HorseCollisionMod:LeanViewAngle()
	local playerEnt = rawget(_G, "player")
	local horse, dir, heading = nil, nil, nil

	if not playerEnt then
		return nil
	end

	-- `GetPlayerHorse` answers with a WUID and not an entity, which is why
	-- every other call site in this mod pairs it with `GetEntityByWUID`.
	-- Calling an entity method straight on the WUID throws, and inside a pcall
	-- that shows up as a silent nil rather than as an error: the angle read
	-- `-1` on every release and the limit never refused anything.
	pcall(function()
		horse = XGenAIModule.GetEntityByWUID(playerEnt.player:GetPlayerHorse())
	end)

	if not horse then
		return nil
	end

	pcall(function()
		dir = System.GetViewCameraDir()
		heading = horse:GetDirectionVector(1)
	end)

	if not dir or not heading then
		return nil
	end

	local dl = math.sqrt((dir.x * dir.x) + (dir.y * dir.y))
	local hl = math.sqrt((heading.x * heading.x) + (heading.y * heading.y))

	if dl <= 0 or hl <= 0 then
		return nil
	end

	-- Steep pitch counts as out of range, reported as a right angle so the
	-- limit refuses on it.
	--
	-- The yaw below is flattened, deliberately, so that looking up or down is
	-- not treated as looking away. That is right in the middle of the range and
	-- wrong at the ends: looking straight down collapses the horizontal
	-- component toward zero and the yaw computed from it stops meaning
	-- anything, so the limit fires somewhere unpredictable. Looking down is
	-- also when the camera is nearest the rider's own model, which is why the
	-- clipping shows up there and nowhere else.
	local pitch = math.deg(math.asin(math.max(-1, math.min(1, dir.z))))

	if math.abs(pitch) > (self.Config.LeanMaxPitchDeg or 55) then
		return 90
	end

	-- Flattened, because looking up or down is not looking away.
	local dot = ((dir.x / dl) * (heading.x / hl)) + ((dir.y / dl) * (heading.y / hl))

	if dot > 1 then
		dot = 1
	elseif dot < -1 then
		dot = -1
	end

	return math.deg(math.acos(dot))
end


--- Flips the camera's direction of travel.
--
-- `SetViewShake` does not set a position or a speed. Firing it while a shake is
-- running reverses which way the camera is going, measured across four calls
-- at two second intervals. The sign of the amplitude only chooses a direction
-- when nothing is already running.
--
-- The forward component rides along on the same call, so a lean carries the
-- camera a little past the horse's shoulder rather than straight out from it.
--
-- @tparam number amplitude how hard, which sets how fast the camera travels
-- @tparam number sign the direction wanted, used only for the first call
-- @tparam number seconds how long this shake lives before it expires and
--   returns the camera home
function HorseCollisionMod:FlipLean(amplitude, sign, seconds, force)
	local cfg = self.Config
	local playerEnt = rawget(_G, "player")

	if not playerEnt or not playerEnt.actor then
		return
	end

	-- **Every shake is an entry in the rider's animation queue, and the queue
	-- holds sixteen.** A shake lives for its whole duration, so the cost of a
	-- correction is not paid when it is made but for however long the shake
	-- was given.
	--
	-- Unrated, this floods. The controller corrects on every crossing of a
	-- three centimeter deadband, which at the hold speed is two or three a
	-- second, and at the twenty second lifetime those were still occupying the
	-- queue long after the lean that made them had ended. Measured, 176
	-- `Animation-queue overflow` errors against one instance, `male.chr`,
	-- which is the rider, with no collision anywhere near them: the burst
	-- began after a release and ran until the scripts were reloaded.
	--
	-- An overflowed queue **rejects** further animations rather than merely
	-- warning, so this is not only noise.
	-- The limit is on **corrections only**. Applied to the press it would drop
	-- a lean that followed another too closely; applied to the release it
	-- swallows the call that ends the lean, and the camera then travels on at
	-- the full 2.75 m/s until the shakes expire. That is a sticky hold, a
	-- return measured in seconds, and a runaway of ten meters on fast taps.
	local now = self:TimeMs()

	if not force and self.LeanLastFlip
			and (now - self.LeanLastFlip) < (cfg.LeanMinFlipMs or 200) then
		return
	end

	self.LeanLastFlip = now
	self.LeanFlips = (self.LeanFlips or 0) + 1

	local forward = amplitude * (cfg.LeanForwardShare or 0.35)

	pcall(function()
		playerEnt.actor:SetViewShake(
				{ x = 0, y = 0, z = 0 },
				{ x = amplitude * sign, y = forward, z = 0 },
				seconds, cfg.LeanShakePeriod or 8.0, 0)
	end)
end


--- Leans out and holds there until the key is released.
--
-- Bang-bang control. The camera is driven out at the travel amplitude, and once
-- it has passed the target offset every crossing back over that offset flips it
-- again, so it dithers around the target rather than sailing past. The dither
-- is the travel speed times the poll interval, which at the hold amplitude is
-- under a centimeter.
--
-- @tparam number sign -1 for left, 1 for right
function HorseCollisionMod:StartLean(sign)
	local cfg = self.Config

	if not cfg.Lean or self.LeanHeld then
		return
	end

	local playerEnt = rawget(_G, "player")

	if not playerEnt or not playerEnt.actor then
		return
	end

	-- On foot there is no horse's head in the way, so there is nothing to lean
	-- around. `player.human:IsMounted` is the same check the rear uses.
	local mounted = false

	pcall(function()
		mounted = playerEnt.human:IsMounted()
	end)

	if not mounted then
		return
	end

	-- Refused while the last lean is still on its way home. Re-basing against a
	-- camera that is still displaced is the pumping bug: each tap took its
	-- baseline from wherever the camera had got to, so release and re-press
	-- ratcheted the offset further out every time.
	--
	-- `now` was read from a global that does not exist. The first press worked,
	-- because `LeanHomeUntil` is nil until a lean has been released and the
	-- `and` short circuits before the comparison. Every press after that
	-- compared nil against a number, threw, and the error was swallowed by the
	-- pcall wrapping the action hook, so the lean died silently and stayed dead
	-- through a save load, since the mod's table survives one.
	-- Refused when looking too far off the horse's line, because the camera
	-- travels in its own space and past a point that takes it through the
	-- rider and the horse rather than out beside them.
	local maxAngle = cfg.LeanMaxAngleDeg or 45
	local angle = self:LeanViewAngle()

	if maxAngle > 0 and angle and angle > maxAngle then
		return
	end

	local now = self:TimeMs()

	if self.LeanHomeUntil and now < self.LeanHomeUntil then
		return
	end

	-- Refused if the offset cannot be read, since the whole hold is closed loop
	-- on it and an open loop lean would simply travel until the key came up.
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
	local target = (cfg.LeanDistance or 0.65) * sign
	local pollMs = cfg.LeanPollMs or 30
	local reached = false
	local last = nil

	self:FlipLean(cfg.LeanTravelAmplitude or 110.0, sign, cfg.LeanShakeSec or 1.5, true)

	local function watch()
		if generation ~= self.LeanGeneration or timerTick ~= self.TimerTick then
			return
		end

		if not self.LeanHeld then
			return
		end

		-- Turning past the limit mid lean ends it, rather than leaving the
		-- camera parked inside the horse until the key comes up.
		local turned = self:LeanViewAngle()

		if (cfg.LeanMaxAngleDeg or 45) > 0 and turned
				and turned > (cfg.LeanMaxAngleDeg or 45) then
			self:StopLean()

			return
		end

		local offset = self:LeanOffset()

		-- Nothing may travel far past the target, whatever went wrong. The
		-- camera moves at nearly three meters a second on the way out, so a
		-- correction that does not land is ten meters away in a few seconds,
		-- which the rider has seen. A ceiling costs one comparison a poll and
		-- bounds every failure in here, including ones not yet found.
		local ceiling = (cfg.LeanDistance or 0.65) * (cfg.LeanRunawayFactor or 2.0)

		if offset and math.abs(offset) > ceiling then
			self:StopLean()

			return
		end

		if offset then
			local hold = cfg.LeanHoldAmplitude or 3.0
			local live = cfg.LeanShakeSec or 20.0
			local past = (sign > 0 and offset >= target) or (sign < 0 and offset <= target)

			if not reached and past then
				-- Arrived. Forced, because this is the one-time change down to
				-- the hold speed and delaying it means sailing past the target
				-- at the full travel speed.
				reached = true
				self:FlipLean(hold, sign, live, true)
			elseif reached and last then
				-- **Direction is measured, never remembered.**
				--
				-- A boolean flipped on each correction cannot work here,
				-- because it assumes the camera only ever changes direction
				-- when this loop turns it. A shake's own curve peaks at its
				-- period and reverses with no flip involved, and a remembered
				-- direction is wrong from that moment on: the loop then
				-- "corrects" the way the camera is already going and the lean
				-- drifts home five or six seconds into a hold. Releases aimed
				-- at 0.65 landed at 0.11, -0.05 and -0.08, the last two having
				-- crossed through center to the wrong side.
				--
				-- Comparing two samples cannot go stale, whatever moved the
				-- camera or why.
				local moving = offset - last
				local gap = target - offset
				local band = cfg.LeanDeadband or 0.03

				-- Away from the target, and far enough out to be worth a
				-- correction. The deadband is what stops a flip every poll
				-- once the camera is sitting on the target.
				if math.abs(gap) > band and (gap * moving) < 0 then
					self:FlipLean(hold, sign, live)
				end
			end

			last = offset
		end

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
-- so the release is a short shake rather than any attempt to drive back.
function HorseCollisionMod:StopLean()
	if not self.LeanHeld then
		return
	end

	local cfg = self.Config

	-- Read before the hold is cleared, because clearing it is what loses which
	-- side this lean was.
	local sign = self.LeanHeld

	self.LeanHeld = nil
	self.LeanGoingBack = false
	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	-- A shake whose duration expires returns the camera home in about 160 ms,
	-- and nothing may re-base until it has.
	self.LeanHomeUntil = self:TimeMs() + (cfg.LeanHomeMs or 220)

	self:FlipLean(cfg.LeanHoldAmplitude or 3.0, 1, cfg.LeanReleaseSec or 0.05, true)

	if cfg.LogTelemetry then
		local offset = self:LeanOffset()

		self:Log("LeanBack side=" .. ((sign or 1) < 0 and "left" or "right")
				.. " from=" .. string.format("%.2f", offset or -9)
				.. " target=" .. string.format("%.2f", cfg.LeanDistance or 0.65)
				.. " angle=" .. string.format("%.0f", self:LeanViewAngle() or -1)
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

	if activation == "press" then
		self:StartLean(sign)
	elseif activation == "release" then
		self:StopLean()
	end

	return true
end
