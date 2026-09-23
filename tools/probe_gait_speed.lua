-- What speed does the horse actually travel at in each gait?
--
-- Stage 2 step 1 of docs/BALANCE_AUDIT.md is tier identity: SpeedWalk 1.8,
-- SpeedTrot 4.5 and SpeedGallop 8.5 were set from plateaus measured in the
-- 2.0.0 era, and the diary records trot impacts topping out at 8.03 against a
-- gallop threshold of 8.5, which is a cliff in reaction strength sitting right
-- where the horse spends much of its time. This samples the mounted horse's
-- speed at 10 Hz and reports the peak and mean of each second, so the four
-- gaits' plateaus can be read off rather than guessed at.
--
--     python tools/dev_console.py --file tools/probe_gait_speed.lua
--
-- Then ride: walk ~15 s, trot ~15 s, canter ~15 s, gallop ~15 s. It stops on
-- its own after three minutes.

local SAMPLE_MS = 100
local REPORT_EVERY = 10
local RUN_MS = 180000

HCM_GaitProbe = {
	started = 0,
	samples = {},
}

local function say(text)
	System.LogAlways("[GaitSpeed] " .. tostring(text))
end

local function speedNow()
	local player = System.GetEntityByName("Henry") or System.GetEntityByName("dude")
	if not player then
		return nil
	end

	local mounted = false
	pcall(function()
		mounted = player.human:IsMounted()
	end)
	if not mounted then
		return nil
	end

	local wuid = nil
	pcall(function()
		wuid = player.player:GetPlayerHorse()
	end)
	if not wuid then
		return nil
	end

	local horse = nil
	pcall(function()
		horse = XGenAIModule.GetEntityByWUID(wuid)
	end)
	if not horse then
		return nil
	end

	local v = nil
	pcall(function()
		v = horse:GetVelocity()
	end)
	if not v then
		return nil
	end

	return math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
end

function HCM_GaitProbe:Tick()
	local now = System.GetCurrTime() * 1000

	if self.started == 0 then
		self.started = now
	end

	local s = speedNow()
	if s then
		self.samples[#self.samples + 1] = s
	end

	if #self.samples >= REPORT_EVERY then
		local peak, sum = 0, 0
		for _, v in ipairs(self.samples) do
			if v > peak then peak = v end
			sum = sum + v
		end
		say(string.format("t=%.0fs peak=%.2f mean=%.2f n=%d",
				(now - self.started) / 1000, peak,
				sum / #self.samples, #self.samples))
		self.samples = {}
	end

	if (now - self.started) >= RUN_MS then
		say("done")
		return
	end

	Script.SetTimer(SAMPLE_MS, function()
		HCM_GaitProbe:Tick()
	end)
end

say("sampling for 180 s: ride walk, trot, canter, then gallop, ~15 s each")
HCM_GaitProbe:Tick()
