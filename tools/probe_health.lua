-- Logs a named entity's health whenever it changes.
--
-- A diagnostic, run from the console rather than shipped in the mod:
--
--     python tools/dev_console.py --file tools/probe_health.lua
--
-- Edit WATCH to the entity to follow. It samples twice a second and writes
-- only on a change, so a quiet watch costs two lines.
--
-- This lived in the mod as HorseCollisionMod:WatchHealth until 4.9.3. It was
-- never called by anything the mod does, only from the console, so it was
-- lifted here rather than shipped to players.

local WATCH = "rat_guard22"
local SECONDS = 90

local function log(message)
	System.LogAlways("[HEALTH] " .. tostring(message))
end

local function watchHealth(name, seconds)
	local ent = System.GetEntityByName(name)

	if not ent or not ent.soul then
		log("Watch " .. tostring(name) .. " not found")
		return
	end

	-- The same generation guard the detection loop uses. A watch left running
	-- across a load screen would otherwise hold a stale entity forever.
	local generation = HorseCollisionMod.TimerTick
	local deadline = System.GetCurrTime() + (seconds or 90)
	local last = nil

	local function tick()
		if generation ~= HorseCollisionMod.TimerTick then
			return
		end

		local ok, health = pcall(function()
			return ent.soul:GetState("health")
		end)

		if not ok or type(health) ~= "number" then
			log("Watch " .. name .. " lost")
			return
		end

		if last and health ~= last then
			local z = "?"
			local away = "?"

			-- Where the rider was standing when the health moved. A loss with
			-- the horse alongside is a contact the footprint rejected; a loss
			-- with the horse far off is something else entirely.
			pcall(function()
				local q = ent:GetWorldPos()
				local r = player:GetWorldPos()

				z = string.format("%.2f", q.z)
				away = string.format("%.1f", math.sqrt(
						(q.x - r.x) * (q.x - r.x)
						+ (q.y - r.y) * (q.y - r.y)))
			end)

			log("Watch " .. name
					.. " health=" .. string.format("%.4f", health)
					.. " delta=" .. string.format("%+.4f", health - last)
					.. " z=" .. z
					.. " rider=" .. away .. "m"
					.. " speed=" .. string.format("%.2f", HorseCollisionMod:RecentPeak(3)))
		end

		last = health

		if System.GetCurrTime() < deadline then
			Script.SetTimer(500, tick)
		else
			log("Watch " .. name .. " ended health="
					.. string.format("%.4f", health))
		end
	end

	log("Watch " .. name .. " started health="
			.. string.format("%.4f", ent.soul:GetState("health")))
	tick()
end

watchHealth(WATCH, SECONDS)
