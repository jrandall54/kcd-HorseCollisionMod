--- Logging, speed history and the speed tier.
--
-- What every other part of the mod reads before it decides anything: the
-- engine clock, vector length, the rolling speed history an impact is judged
-- against, and the two log calls. Attached to the `HorseCollisionMod` table
-- created by the entry point, which pulls this file in with
-- `Script.ReloadScript`.
--
-- `TimeMs` and `VectorLength` are methods rather than file-locals. A local is
-- visible only inside the chunk that declares it, and these are called from
-- part files that are separate chunks.
--
-- @module HorseCollisionMod.Log
-- @author jrandall54
-- @release 4.7.3
--- The engine clock in milliseconds.
--
-- `System.GetCurrTime` returns seconds as a float and `os.clock` returns nil
-- in this engine, so this is the only clock available. A method rather than a
-- file-local because the mod is split across files and a local is visible only
-- inside the one that declares it.
--
-- @treturn number milliseconds since the engine started
function HorseCollisionMod:TimeMs()
	return System.GetCurrTime() * 1000
end

--- Magnitude of a CryEngine vector.
--
-- A method for the same reason as `TimeMs`: callers are spread across the
-- mod's part files, which do not share locals.
--
-- @tparam ?table v vector with x, y and z components, or nil
-- @treturn number length, or 0 when v is nil
function HorseCollisionMod:VectorLength(v)
	if not v then
		return 0
	end

	return math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
end

--- Records one speed sample.
--
-- @tparam number speed the current sample, in meters per second
function HorseCollisionMod:TrackSpeed(speed)
	local history = self.SpeedHistory

	history[#history + 1] = speed

	while #history > self.SpeedHistorySize do
		table.remove(history, 1)
	end
end

--- The peak of the last `count` speed samples.
--
-- @tparam number count how many of the most recent samples to consider
-- @treturn number the highest speed among them, in meters per second
function HorseCollisionMod:RecentPeak(count)
	local history = self.SpeedHistory
	local first = #history - count + 1
	local peak = 0

	if first < 1 then
		first = 1
	end

	for i = first, #history do
		if history[i] > peak then
			peak = history[i]
		end
	end

	return peak
end

--- The recent speed samples, oldest first, as a compact string.
--
-- Printed on every impact while diagnosing. The width of the deceleration on
-- contact is what sets `ImpactSpeedSamples`, and it is only visible in the
-- samples either side of the collision.
--
-- @tparam number count how many of the most recent samples to include
-- @treturn string the samples, space separated, to two decimal places
function HorseCollisionMod:SpeedTrail(count)
	local history = self.SpeedHistory
	local first = #history - count + 1
	local parts = {}

	if first < 1 then
		first = 1
	end

	for i = first, #history do
		parts[#parts + 1] = string.format("%.2f", history[i])
	end

	return table.concat(parts, " ")
end

--- The speed a collision should be scored at.
--
-- A horse loses speed the moment it hits someone. Detection samples velocity
-- once per tick, so the speed read on the tick that notices a victim has
-- already been reduced by the collision it is meant to describe, and a gallop
-- impact can be scored as a walk. The peak of the last few samples brackets
-- the moment of contact instead.
--
-- The window is deliberately short. Taken over a whole second it would charge
-- gallop to a rider who galloped up and then slowed deliberately to nudge
-- someone.
--
-- Capped because the physics system reports occasional speeds above anything a
-- horse holds, and this value scales knockback force as well as selecting the
-- tier.
--
-- @treturn number the speed to score the impact at, in meters per second
function HorseCollisionMod:ImpactSpeed()
	local peak = self:RecentPeak(self.Config.ImpactSpeedSamples)

	if peak > self.Config.MaxImpactSpeed then
		return self.Config.MaxImpactSpeed
	end

	return peak
end

--- Logs why a candidate was passed over, at most once per second per entity.
--
-- Every rejection in the detection loop is silent, so an impact that produces
-- no reaction is indistinguishable from one that was never detected. This
-- names the reason.
--
-- Rate limited because the loop runs about twenty times a second and the
-- detection sphere returns everything nearby, including crates and doors.
--
-- @tparam table npc the entity that was rejected
-- @tparam string reason short label for which test rejected it
-- @tparam string detail the measurement behind that decision
function HorseCollisionMod:LogRejection(npc, reason, detail)
	if not self.Config.DiagnoseMisses then
		return
	end

	local id = tostring(npc and npc.id or "?")
	local now = self:TimeMs()
	local last = self.RecentRejections[id]

	if last and (now - last) < 1000 then
		return
	end

	self.RecentRejections[id] = now

	local name = "?"

	pcall(function()
		name = npc:GetName() or "?"
	end)

	self:Log("Miss " .. reason .. " name=" .. tostring(name)
			.. " " .. tostring(detail))
end


--- Current time in milliseconds.
-- @treturn number milliseconds since the game session started
--- Writes a prefixed line to kcd.log when telemetry is enabled.
-- @tparam string message text to log
function HorseCollisionMod:Log(message)
	if not self.Config.LogTelemetry then
		return
	end

	System.LogAlways("[HorseCollisionMod] " .. tostring(message))
end

--- Resolves a speed to its gait name.
-- @tparam number speed speed in meters per second
-- @treturn string one of "Gallop", "Trot", "Walk" or "Idle"
function HorseCollisionMod:GetSpeedTier(speed)
	local cfg = self.Config

	if speed >= cfg.SpeedGallop then
		return "Gallop"
	end

	if speed >= cfg.SpeedTrot then
		return "Trot"
	end

	if speed >= cfg.SpeedWalk then
		return "Walk"
	end

	return "Idle"
end
