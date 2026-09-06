--- Gives the player a horse, for testing early-game saves.
--
-- The horsemanship tuning has to be judged at a low skill level, and the
-- earliest save on hand is already level 5. Starting a new game reaches level
-- 1 but not a horse: the prologue hands one over hours in.
--
-- Nothing is spawned. Every horse in the level is already an entity, so this
-- finds the nearest one and makes it the player's, which is the same pair of
-- calls the cheat mod uses:
--
--     player.player:SetPlayerHorse(horse.id)
--     horse:SetWorldPos(...)
--
-- Run with: python tools/dev_console.py --file tools/dev_horse.lua

local origin = player:GetWorldPos()
local best, bestName = nil, nil

-- The stable registry rather than whatever horse is standing nearest. A loose
-- horse in the world is an entity like any other and `SetPlayerHorse` accepts
-- it, but it cannot actually be mounted: the rideable ones are those
-- `Horsetraders` knows about, which is the list the cheat mod searches for the
-- same reason.
if Horsetraders and Horsetraders.__data__ then
	for _, stable in pairs(Horsetraders.__data__.stables or {}) do
		for _, data in pairs(stable.horses or {}) do
			if not best and data.name then
				local entity = System.GetEntityByName(data.name)

				if entity then
					best, bestName = entity, data.name
				end
			end
		end
	end
end

if not best then
	System.LogAlways("[HORSE] no stabled horse is loaded in this level")
	return
end

System.LogAlways("[HORSE] taking " .. bestName .. " from the stable registry")

local ok = pcall(function()
	player.player:SetPlayerHorse(best.id)
end)

System.LogAlways("[HORSE] SetPlayerHorse ok=" .. tostring(ok))

local moved = pcall(function()
	best:SetWorldPos({ x = origin.x - 1.5, y = origin.y - 1.5, z = origin.z })
end)

System.LogAlways("[HORSE] teleport ok=" .. tostring(moved)
		.. " riding=" .. tostring(player.soul:GetSkillLevel("horse_riding")))
