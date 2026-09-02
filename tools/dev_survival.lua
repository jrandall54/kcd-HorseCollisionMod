-- Keeps the player fed and rested, for tests that need game time to pass.
--
-- Hardcore mode makes hunger and exhaustion real constraints, which is fine
-- while playing and useless while measuring. A test that needs several
-- in-game days otherwise turns into an errand of finding food and beds that
-- has nothing to do with what is being measured.
--
-- Run through `dev_console.py --file`, and it keeps running until the game is
-- closed, a save is loaded, or `HorseCollisionModSurvival.stop` is set true.
-- Nothing here ships: it is a development aid and touches only the player.
--
--     python tools/dev_console.py --file tools/dev_survival.lua
--
-- The state names were established by reading them back rather than assumed.
-- `hunger` is nourishment and `exhaust` is energy, and both run the way that
-- reads oddly: **higher is better**, 100 being fully fed and fully rested. A
-- healthy player reads about 99 exhaust, and the mod's own telemetry logs
-- `exhaust=100.0` for a fresh NPC.
--
-- `stamina` is deliberately not touched. The player's maximum is 150 rather
-- than 100, so writing 100 to it lowers it.

HorseCollisionModSurvival = HorseCollisionModSurvival or {}

-- Bumped on every run so an earlier loop retires instead of doubling up.
HorseCollisionModSurvival.generation =
		(HorseCollisionModSurvival.generation or 0) + 1
HorseCollisionModSurvival.stop = false

local INTERVAL = 20000

local generation = HorseCollisionModSurvival.generation

local function topUp()
	if HorseCollisionModSurvival.stop then
		System.LogAlways("[SURVIVAL] stopped")

		return
	end

	if generation ~= HorseCollisionModSurvival.generation then
		return
	end

	local pe = System.GetEntityByName("dude") or player

	if pe and pe.soul then
		pcall(function()
			pe.soul:SetState("hunger", 100)
			pe.soul:SetState("exhaust", 100)
		end)
	end

	Script.SetTimer(INTERVAL, topUp)
end

Script.SetTimer(INTERVAL, topUp)

local pe = System.GetEntityByName("dude") or player

pcall(function()
	pe.soul:SetState("hunger", 100)
	pe.soul:SetState("exhaust", 100)
end)

System.LogAlways("[SURVIVAL] keeping hunger and exhaust at 100 every "
		.. (INTERVAL / 1000) .. "s, generation " .. generation
		.. ". Set HorseCollisionModSurvival.stop = true to end it.")
