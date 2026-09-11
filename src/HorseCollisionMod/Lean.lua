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
-- ### How a shake is made to hold still
--
-- A shake oscillates, which is the opposite of what a lean wants. The fourth
-- argument is what makes it usable, and it is **a period in seconds rather
-- than a frequency**, which is the reverse of what `Rider.lua` documented.
-- Measured across a 2000x spread at a fixed amplitude, 0.01 read as a blur,
-- 1.0 as a natural shake, and 20.0 was not noticed at all.
--
-- A long period means the duration only ever covers the opening sliver of one
-- swing, so the camera pushes out and the return half never arrives. The
-- amplitude is therefore much larger than the distance traveled: at a 30
-- second period a 2 second window reaches roughly 40 per cent of it.
--
-- Holding the lean out is then a matter of refreshing it before the duration
-- expires, which is what a held key does.
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
-- @tparam string key one of r, q, y, u, o, h
-- @tparam string side "left" or "right"
-- @treturn ?string the action name, or nil when the key is not one of the six
function HorseCollisionMod:LeanActionFor(key, side)
	if type(key) ~= "string" or key == "" then
		return nil
	end

	return "hcm_lean_" .. side .. "_" .. string.lower(key)
end


--- Pushes the camera out to one side, or refreshes a lean already running.
--
-- Called on the key press and then on a timer while the key is held. Each call
-- restarts the shake, so the camera never reaches the point in the swing where
-- it would come back.
--
-- @tparam number sign -1 for left, 1 for right
function HorseCollisionMod:PushLean(sign)
	local cfg = self.Config
	local playerEnt = rawget(_G, "player")

	if not playerEnt or not playerEnt.actor then
		return
	end

	local amplitude = (cfg.LeanAmplitude or 3.0) * sign
	local period = cfg.LeanPeriod or 30.0
	local duration = cfg.LeanDurationSec or 2.0

	pcall(function()
		playerEnt.actor:SetViewShake(
				{ x = 0, y = 0, z = 0 },
				{ x = amplitude, y = 0, z = 0 },
				duration, period, 0)
	end)
end


--- Starts a lean and keeps it out until the key is released.
--
-- The refresh interval is a fraction of the duration rather than the whole of
-- it, so the next push lands before the current one has begun its return.
--
-- A ceiling is kept regardless of the key, because whether a mod-declared
-- action delivers `release` at all is not established. If it does not, the
-- lean ends on the ceiling and the feature still works as a glance rather than
-- as a hold.
--
-- @tparam number sign -1 for left, 1 for right
function HorseCollisionMod:StartLean(sign)
	local cfg = self.Config

	if not cfg.Lean then
		return
	end

	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	local generation = self.LeanGeneration
	local timerTick = self.TimerTick
	local startedAt = self:TimeMs()
	local ceiling = (cfg.LeanHoldMaxSec or 4.0) * 1000
	local every = ((cfg.LeanDurationSec or 2.0) * 1000)
			* (cfg.LeanRefreshShare or 0.5)

	self.LeanSign = sign
	self:PushLean(sign)

	local function hold()
		if generation ~= self.LeanGeneration or timerTick ~= self.TimerTick then
			return
		end

		if (self:TimeMs() - startedAt) >= ceiling then
			self:StopLean("ceiling")

			return
		end

		self:PushLean(sign)
		Script.SetTimer(every, hold)
	end

	Script.SetTimer(every, hold)

	if cfg.LogTelemetry then
		self:Log("LeanStart side=" .. (sign < 0 and "left" or "right")
				.. " amp=" .. string.format("%.1f", cfg.LeanAmplitude or 3.0)
				.. " period=" .. string.format("%.0f", cfg.LeanPeriod or 30.0)
				.. " dur=" .. string.format("%.1f", cfg.LeanDurationSec or 2.0))
	end
end


--- Ends a lean and brings the camera back.
--
-- Stopping the refresh alone would leave the camera out until the last shake's
-- duration expired, which is up to a whole duration of nothing happening. A
-- short shake the other way carries it home instead, at a period short enough
-- to arrive promptly and long enough not to read as a snap.
--
-- @tparam string why what ended it, for the log
function HorseCollisionMod:StopLean(why)
	self.LeanGeneration = (self.LeanGeneration or 0) + 1

	local cfg = self.Config
	local playerEnt = rawget(_G, "player")

	if not playerEnt or not playerEnt.actor then
		return
	end

	pcall(function()
		playerEnt.actor:SetViewShake(
				{ x = 0, y = 0, z = 0 },
				{ x = 0, y = 0, z = 0 },
				cfg.LeanReturnSec or 0.35,
				cfg.LeanReturnPeriod or 4.0, 0)
	end)

	if cfg.LogTelemetry then
		self:Log("LeanStop why=" .. tostring(why))
	end
end


--- Answers a key event, and reports whether it belonged to the lean.
--
-- Both activations are logged the first few times, because whether a
-- mod-declared action delivers `release` as well as `press` decides whether
-- this is a hold or a glance and has never been established on this project.
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

	-- Recorded for the first handful of presses only. The question it answers
	-- is asked once per build, and a line per keypress forever afterwards is
	-- the kind of noise this project has already paid for.
	self.LeanSeen = (self.LeanSeen or 0) + 1

	if cfg.LogTelemetry and self.LeanSeen <= 8 then
		self:Log("LeanKey action=" .. tostring(action)
				.. " activation=" .. tostring(activation))
	end

	if activation == "press" then
		self:StartLean(sign)
	elseif activation == "release" then
		self:StopLean("release")
	end

	return true
end
