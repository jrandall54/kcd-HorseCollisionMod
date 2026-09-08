--- Turns off the world's reaction to the player, so a collision test is not
--- also a fight.
--
-- `CollisionIsCrime` only stops the mod reporting its own hit. It cannot stop
-- the engine attributing a death to the rider, and it does nothing at all
-- about the witnesses, so any test that kills villagers ends with a hostile
-- town and every later impact logged under `combatScale`. That invalidates the
-- measurement it was supposed to protect.
--
-- Three levers, found in the decompilation and in the game's own Lua, and
-- confirmed present in the running game:
--
--   CrimeUtils.CanDetectCrime   the game's own gate on whether a witness
--                            registers a crime at all. Stubbed to false, so
--                            nothing is ever reported.
--   Game.SetWantedLevel      clears the crime already on the books.
--   AI.ResetPersonallyHostiles  clears the per-NPC grudge list, which is what
--                            keeps someone hostile after the wanted level is
--                            gone.
--
-- `ai_IgnorePlayer` used to be set here and is deliberately gone. It was
-- described as the lever that mattered, and that was never true and never
-- tested: it was set on every run for several sessions while the rider went on
-- being attacked, and reading it back as 1 only ever confirmed the cvar had
-- taken a value, not that it did anything. Do not put it back without a test
-- that shows a difference with it on and off.
--
-- None of this is a loop, and none of it survives a save load, so run this
-- file again after every load.
--
-- Run with: python tools/dev_console.py --file tools/dev_peace.lua

local RADIUS = 80

local blinded = false

if CrimeUtils and type(CrimeUtils.CanDetectCrime) == "function" then
	CrimeUtils.CanDetectCrime = function()
		return false
	end

	blinded = true
end

local wanted = pcall(function()
	Game.SetWantedLevel(0)
end)

local cleared, failed = 0, 0

local function forgive(ent)
	if not ent or not ent.id then
		return
	end

	if pcall(function()
		AI.ResetPersonallyHostiles(ent.id)
	end) then
		cleared = cleared + 1
	else
		failed = failed + 1
	end
end

forgive(player)

local pos = player:GetWorldPos()
local near = {}

pcall(function()
	near = System.GetEntitiesInSphere(pos, RADIUS) or {}
end)

for _, ent in pairs(near) do
	if ent ~= player and ent.actor and ent.soul then
		forgive(ent)
	end
end

System.LogAlways("[PEACE] crimeBlind=" .. tostring(blinded)
		.. " wanted=" .. tostring(wanted)
		.. " forgiven=" .. tostring(cleared)
		.. " failed=" .. tostring(failed)
		.. " scanned=" .. tostring(#near))
