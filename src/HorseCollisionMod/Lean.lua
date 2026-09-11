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


--- The camera's offset from where the lean started, in meters.
--
-- Sideways and forward are reported separately, measured against the camera's
-- own axes at the moment the lean began, so turning the horse mid lean does not
-- read as the camera having moved.
--
-- @treturn ?number sideways offset, positive to the right
function HorseCollisionMod:LeanOffset()
	local here = nil

	pcall(function()
		here = System.GetViewCameraPos()
	end)

	if not here or not self.LeanBase or not self.LeanRight then
		return nil
	end

	local dx = here.x - self.LeanBase.x
	local dy = here.y - self.LeanBase.y

	return (dx * self.LeanRight.x) + (dy * self.LeanRight.y)
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
function HorseCollisionMod:FlipLean(amplitude, sign, seconds)
	local cfg = self.Config
	local playerEnt = rawget(_G, "player")

	if not playerEnt or not playerEnt.actor then
		return
	end

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

	pcall(function()
		self.LeanBase = System.GetViewCameraPos()

		local d = System.GetViewCameraDir()
		local l = math.sqrt((d.x * d.x) + (d.y * d.y))

		if l > 0 then
			self.LeanRight = { x = d.y / l, y = -d.x / l }
		end
	end)

	if not self.LeanBase or not self.LeanRight then
		return
	end

	self.LeanHeld = sign
	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	local generation = self.LeanGeneration
	local timerTick = self.TimerTick
	local target = (cfg.LeanDistance or 0.65) * sign
	local pollMs = cfg.LeanPollMs or 50
	local reached = false

	self:FlipLean(cfg.LeanTravelAmplitude or 6.0, sign, cfg.LeanShakeSec or 20.0)

	local function watch()
		if generation ~= self.LeanGeneration or timerTick ~= self.TimerTick then
			return
		end

		if not self.LeanHeld then
			return
		end

		local offset = self:LeanOffset()

		if offset then
			-- Past the target in the direction of travel, so turn around. The
			-- first crossing switches to the hold amplitude, which is slower
			-- and makes the dither small.
			local past = (sign > 0 and offset >= target) or (sign < 0 and offset <= target)
			local back = (sign > 0 and offset < target) or (sign < 0 and offset > target)

			if not reached and past then
				reached = true
				self:FlipLean(cfg.LeanHoldAmplitude or 1.2, sign,
						cfg.LeanShakeSec or 20.0)
			elseif reached and ((past and not self.LeanGoingBack)
					or (back and self.LeanGoingBack)) then
				self.LeanGoingBack = not self.LeanGoingBack
				self:FlipLean(cfg.LeanHoldAmplitude or 1.2, sign,
						cfg.LeanShakeSec or 20.0)
			end
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

	self.LeanHeld = nil
	self.LeanGoingBack = false
	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	self:FlipLean(cfg.LeanHoldAmplitude or 1.2, 1, cfg.LeanReleaseSec or 0.05)

	if cfg.LogTelemetry then
		local offset = self:LeanOffset()

		self:Log("LeanBack from=" .. string.format("%.2f", offset or -9))
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
