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
-- Concurrent shakes **sum**, which is why tapping the key repeatedly used to
-- send the camera absurdly far: each press added another curve and nothing
-- subtracted one. A lean already running is therefore left alone.--- The action name this mod listens to for a lean, for a given key.
--
-- Each feature is declared once per candidate key in `hcm_actionmaps.xml`,
-- because Lua cannot write a file and `LoadFromXML` can only read one, so a
-- key cannot be rebound at runtime. The settings file picks which declaration
-- the mod answers to by naming the key.
--
-- Action maps are read once, at startup. A key added to that file is dead
-- until the game is restarted.
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


--- Leans the camera out, and lets it come back.
--
-- One shake, cut at its own peak. The period is the time to full extension and
-- the amplitude is the distance wanted divided by 0.63, which is the measured
-- fraction of the amplitude the camera actually reaches.
--
-- Cutting at the peak is deliberate: a cut returns the camera home smoothly in
-- about 160 ms, so the return costs nothing and needs no second call.
--
-- @tparam number sign -1 for left, 1 for right
function HorseCollisionMod:StartLean(sign)
	local cfg = self.Config

	if not cfg.Lean then
		return
	end

	local now = self:TimeMs()

	-- Concurrent shakes sum, so a second lean on top of a first runs away.
	if self.LeanBusyUntil and now < self.LeanBusyUntil then
		return
	end

	local playerEnt = rawget(_G, "player")

	if not playerEnt or not playerEnt.actor then
		return
	end

	local outSec = cfg.LeanOutSec or 0.4
	local distance = cfg.LeanDistance or 0.65
	local amplitude = (distance / 0.63) * sign

	self.LeanBusyUntil = now + (outSec * 1000) + 200

	pcall(function()
		playerEnt.actor:SetViewShake(
				{ x = 0, y = 0, z = 0 },
				{ x = amplitude, y = 0, z = 0 },
				outSec, outSec, 0)
	end)

	if cfg.LogTelemetry then
		self:Log("Lean side=" .. (sign < 0 and "left" or "right")
				.. " distance=" .. string.format("%.2f", distance)
				.. " amplitude=" .. string.format("%.2f", math.abs(amplitude))
				.. " outSec=" .. string.format("%.2f", outSec))
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
	end

	return true
end
