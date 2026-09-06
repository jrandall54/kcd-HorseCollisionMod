--- Turns off the world's reaction to the player, so a collision test is not
--- also a fight.
--
-- `CollisionIsCrime` only stops the mod reporting its own hit. It cannot stop
-- the engine attributing a death to the rider, and it does nothing at all
-- about the witnesses, so any test that kills villagers ends with a hostile
-- town and every later impact logged under `combatScale`. That invalidates the
-- measurement it was supposed to protect.
--
-- Four levers, found in the decompilation and in the game's own Lua, and
-- confirmed present in the running game:
--
--   CrimeUtils.CanDetectCrime   the game's own gate on whether a witness
--                            registers a crime at all. Stubbed to false, so
--                            nothing is ever reported. This is the one that
--                            stops crime; `ai_IgnorePlayer` alone does not,
--                            because the crime system is separate from AI
--                            target selection and a killing still flags.
--   ai_IgnorePlayer          a stock CryEngine cvar. AI stops treating the
--                            player as a perceivable target, so nobody
--                            engages and nobody calls for help.
--   Game.SetWantedLevel      clears the crime already on the books.
--   AI.ResetPersonallyHostiles  clears the per-NPC grudge list, which is what
--                            keeps someone hostile after the wanted level is
--                            gone.
--
-- None of this is a loop. The cvar is set once and holds for the session
-- including across a save load; the stub and the two cleanups are one-shot and
-- do not survive a load, so run this file again after every load.
--
-- Run with: python tools/dev_console.py --file tools/dev_peace.lua
--
-- To put the world back, without reloading:
--
--   python tools/dev_console.py --lua "System.SetCVar('ai_IgnorePlayer', 0)"

local RADIUS = 80

local blinded = false

if CrimeUtils and type(CrimeUtils.CanDetectCrime) == "function" then
	CrimeUtils.CanDetectCrime = function()
		return false
	end

	blinded = true
end

System.SetCVar("ai_IgnorePlayer", 1)

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
		.. " ai_IgnorePlayer=" .. tostring(System.GetCVar("ai_IgnorePlayer"))
		.. " wanted=" .. tostring(wanted)
		.. " forgiven=" .. tostring(cleared)
		.. " failed=" .. tostring(failed)
		.. " scanned=" .. tostring(#near))
