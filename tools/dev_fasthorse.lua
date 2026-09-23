--- Hands the player the fastest horse loaded in the level.
--
-- Every measurement this project has ever taken was ridden on Pebbles, so the
-- gait plateaus behind `SpeedWalk`, `SpeedTrot` and `SpeedGallop` are one
-- horse's. A horse's speed rides on its `agi` stat, which is one of the four
-- Horsetraders prices a horse on, so the widest spread available is Pebbles
-- against the highest `agi` horse standing in the level.
--
-- Same two calls as tools/dev_horse.lua, which is what the cheat mod uses; the
-- only difference is that this ranks the stable registry instead of taking the
-- first entry.
--
--     python tools/dev_console.py --file tools/dev_fasthorse.lua

local origin = player:GetWorldPos()
local best, bestName, bestAgi = nil, nil, -1

local function say(text)
	System.LogAlways("[FastHorse] " .. tostring(text))
end

if Horsetraders and Horsetraders.__data__ then
	for _, stable in pairs(Horsetraders.__data__.stables or {}) do
		for _, data in pairs(stable.horses or {}) do
			local entity = data.name and System.GetEntityByName(data.name)

			if entity and entity.soul then
				local agi = -1
				pcall(function()
					agi = entity.soul:GetStatLevel("agi")
				end)

				say(string.format("%s agi=%s", tostring(data.name),
						tostring(agi)))

				if type(agi) == "number" and agi > bestAgi then
					best, bestName, bestAgi = entity, data.name, agi
				end
			end
		end
	end
end

if not best then
	say("no stabled horse is loaded in this level")
	return
end

say(string.format("taking %s, agi=%d", bestName, bestAgi))

local ok = pcall(function()
	player.player:SetPlayerHorse(best.id)
end)

local moved = pcall(function()
	best:SetWorldPos({ x = origin.x - 2.0, y = origin.y - 2.0, z = origin.z })
end)

say("SetPlayerHorse ok=" .. tostring(ok) .. " teleport ok=" .. tostring(moved))
