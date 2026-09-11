-- Measures where the first-person camera actually goes during a view shake.
--
-- A one second camera motion judged by eye cannot settle whether a shake cut
-- part way home eases or snaps. Polling the camera position through the swing
-- can, and gives the displacement curve directly.
--
-- `GetHeadPos` is the wrong source. It reports the head **bone**, and a view
-- shake is applied to the camera downstream of the skeleton: at an amplitude
-- of 2.0 the head bone moves 2.7 cm, which is idle breathing, while the camera
-- moves ten times that. `System.GetViewCameraPos` is the camera itself.
--
-- Samples are accumulated and written as one line at the end rather than one
-- line per sample. Per-sample logging during a reaction is what made a smooth
-- animation look jerky earlier in this project.
--
-- The horse must be standing still. Displacement is measured against the
-- camera position at t0, so a moving horse would swamp the signal.
--
--     python tools/dev_console.py --file tools/probe_camera.lua --wait 12

local AMPLITUDE = 2.0
local PERIOD = 8.0
local DURATION = 1.0     -- cut at 1.0s, well before the 2.0s far point
local POLL_MS = 30
local WATCH_MS = 4000

local p = player

if not p or not p.actor then
	System.LogAlways("[CAM] no player.actor")
	return
end

local base, right = nil, nil

pcall(function()
	base = System.GetViewCameraPos()
end)

-- The horse's own right vector, so the sideways component can be separated
-- from any drift along the line of travel. Taken from the head direction
-- flattened, rotated ninety degrees.
pcall(function()
	local hd = System.GetViewCameraDir()

	if hd then
		local len = math.sqrt((hd.x * hd.x) + (hd.y * hd.y))

		if len > 0 then
			right = { x = hd.y / len, y = -hd.x / len }
		end
	end
end)

if not base or not right then
	System.LogAlways("[CAM] no camera pos or dir, cannot measure")
	return
end

System.LogAlways(string.format(
		"[CAM] base={%.3f,%.3f,%.3f} amp=%.1f period=%.1f duration=%.2f",
		base.x, base.y, base.z, AMPLITUDE, PERIOD, DURATION))

local samples = {}
local started = System.GetCurrTime() * 1000

local function sample()
	local here = nil

	pcall(function()
		here = System.GetViewCameraPos()
	end)

	if here then
		local dx, dy, dz = here.x - base.x, here.y - base.y, here.z - base.z

		-- Signed sideways offset, and the total, so a shake that moves the
		-- camera on some other axis is still visible.
		local lateral = (dx * right.x) + (dy * right.y)
		local total = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
		local at = (System.GetCurrTime() * 1000) - started

		samples[#samples + 1] = string.format("%.0f:%.3f/%.3f", at, lateral, total)
	end

	if ((System.GetCurrTime() * 1000) - started) < WATCH_MS then
		Script.SetTimer(POLL_MS, sample)
	else
		-- Written in chunks, because a single line of 130 samples is truncated
		-- in the console stream and unreadable in the log.
		local chunk = {}

		for i = 1, #samples do
			chunk[#chunk + 1] = samples[i]

			if #chunk == 20 or i == #samples then
				System.LogAlways("[CAM] " .. table.concat(chunk, " "))
				chunk = {}
			end
		end

		System.LogAlways("[CAM] done, " .. #samples .. " samples, ms:lateral/total")
	end
end

pcall(function()
	p.actor:SetViewShake(
			{ x = 0, y = 0, z = 0 },
			{ x = AMPLITUDE, y = 0, z = 0 },
			DURATION, PERIOD, 0)
end)

sample()
