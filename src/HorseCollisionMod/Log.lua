--- Logging, the clock and the speed history.
--
-- What every other part of the mod reads before it decides anything: the
-- engine clock, vector length, the detection interval, the rolling speed
-- history an impact is scored from, entity names for the log, and the log
-- calls. Attached to the `HorseCollisionMod` table created by the entry
-- point, which pulls this file in with `Script.ReloadScript`.
--
-- These are methods rather than file-locals: a local is visible only inside
-- the chunk that declares it, and they are called from part files that are
-- separate chunks.
--
-- @module HorseCollisionMod.Log
-- @author jrandall54

-- The shortest gap between two `Miss` lines for one entity.
HorseCollisionMod.RejectionLogGapMs = 1000

-- The shortest detection interval `TickMs` allows, in seconds: one frame at
-- 60 Hz.
HorseCollisionMod.MinTickSeconds = 0.016

--- The engine clock in milliseconds.
--
-- `System.GetCurrTime` returns seconds as a float and `os.clock` returns nil
-- in this engine, so this is the only clock available.
--
-- @treturn number milliseconds since the engine started
function HorseCollisionMod:TimeMs()
	return System.GetCurrTime() * 1000
end

--- Magnitude of a CryEngine vector.
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

--- The peak of the last `count` speed samples, ignoring lone spikes.
--
-- The peak is held rather than read instantaneously because contact slows the
-- horse, so the speed on the tick of impact under-rates the blow. A collision
-- should be scored by the speed the horse carried **into** it.
--
-- The hold alone cannot tell speed carried into a collision from speed
-- produced by one: walking a horse into someone kicks it off the body, and a
-- kick in the history would score a walking shove as a trot.
--
-- **A single sample cannot set the peak.** The peak is the largest of each
-- neighboring pair's smaller reading, so a figure has to be reached on two
-- consecutive samples before it counts. Real speed is sustained, and a horse
-- decelerating on contact still has the samples before the contact to be
-- rated by; a kick is one tick wide and its neighbor is an ordinary reading,
-- so it never wins. `WatchLunge` applies the same rule to the charge.
--
-- @tparam number count how many of the most recent samples to consider
-- @treturn number the highest speed held across two samples, meters per second
function HorseCollisionMod:RecentPeak(count)
	local history = self.SpeedHistory
	local first = #history - count + 1
	local peak = 0

	if first < 1 then
		first = 1
	end

	-- One sample is all there is on the first tick after a load or a reload,
	-- and there is no pair to check it against. Taken at face value, because
	-- refusing it would score that tick at zero and miss an impact outright.
	if first >= #history then
		return history[#history] or 0
	end

	for i = first + 1, #history do
		local held = math.min(history[i - 1], history[i])

		if held > peak then
			peak = held
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
-- horse holds. This value selects the tier and gives `GetImpactDir` its
-- direction; nothing downstream scales force by it. Every force figure is
-- flat per tier, the brake reads the body's own velocity, and the impulse is
-- `Knockback` and `Uplift`.
--
-- @treturn number the speed to score the impact at, in meters per second
function HorseCollisionMod:ImpactSpeed()
	local peak = self:RecentPeak(self.Config.ImpactSpeedSamples)

	if peak > self.Config.MaxImpactSpeed then
		return self.Config.MaxImpactSpeed
	end

	return peak
end

--- Logs why a candidate was passed over, rate limited per entity.
--
-- Every rejection in the detection loop is silent, so an impact that produces
-- no reaction is indistinguishable from one that was never detected. This
-- names the reason.
--
-- Rate limited, to once per `RejectionLogGapMs` per entity, because the loop
-- runs every `TickSeconds` and the detection sphere returns everything
-- nearby, including crates and doors.
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

	if last and (now - last) < self.RejectionLogGapMs then
		return
	end

	self.RecentRejections[id] = now

	self:Log("Miss " .. reason .. " name=" .. self:NameOf(npc)
			.. " " .. tostring(detail))
end

--- An entity's name, or "?" when it cannot be read.
--
-- Reading a name is not safe. An entity can be unstreamed between the moment
-- something is scheduled and the moment it runs, and `GetName` throws on one
-- that has gone. Almost every use of a name here is for a log line, and most
-- of those sit inside timer callbacks, so an unprotected lookup could kill the
-- callback and silently stop a watcher for the sake of a diagnostic.
--
-- @tparam table npc any entity, or nil
-- @treturn string the entity's name, or "?"
function HorseCollisionMod:NameOf(npc)
	local name = "?"

	pcall(function()
		name = npc:GetName() or "?"
	end)

	return name
end

--- Writes a prefixed line to kcd.log when telemetry is enabled.
-- @tparam string message text to log
function HorseCollisionMod:Log(message)
	if not self.Config.LogTelemetry then
		return
	end

	System.LogAlways("[HorseCollisionMod] " .. tostring(message))
end

--- The detection interval in milliseconds.
--
-- `TickSeconds` is the one figure the loop rate and the forward sweep are both
-- derived from, so a change to it moves them together. Clamped at
-- `MinTickSeconds`, because a zero would book a timer that never rests.
--
-- @treturn number milliseconds between detection ticks
function HorseCollisionMod:TickMs()
	local seconds = self.Config.TickSeconds

	if seconds < self.MinTickSeconds then
		seconds = self.MinTickSeconds
	end

	return math.floor(seconds * 1000)
end
