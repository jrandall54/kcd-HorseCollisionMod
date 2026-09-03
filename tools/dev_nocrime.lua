-- Keeps a measurement ride from turning into a fight.
--
-- Two separate things end a ride and clearing the wanted level fixes only one.
--
-- **The charge.** `CollisionIsCrime = false` stops this mod reporting a
-- collision, and cannot stop the engine attributing a death to the rider.
-- `Game.SetWantedLevel(0)` undoes that.
--
-- **The grudge.** An NPC who has already turned hostile keeps swinging
-- whatever the wanted level says. Hostility is per NPC and lives in their
-- context options, so there is no single call for it. Two are set on everyone
-- nearby: `disableChangeHostilityOnHit`, so being hit does not turn them
-- hostile, and `suppressDudeHostilePerceptionStimuli`, so bystanders do not
-- join in. Both were confirmed holding on 19 NPCs.
--
-- These are non-persistent, so they cannot survive a save into a player's
-- game, and they touch nothing any test measures. Nothing here may hold a
-- victim's health up: the auto-cure daycycle is gated on health below 40, so a
-- floor above that silently suppresses the lockup rides are run to observe.
--
-- The sweep repeats because NPCs stream in as the rider moves. This prevents a
-- fight rather than ending one, so reload first if a brawl is in progress.
--
--     python tools/dev_console.py --ride
--
-- Does not survive a save load. Re-run `--ride` after one.

HorseCollisionModNoCrime = HorseCollisionModNoCrime or {}

-- Bumped on every run so an earlier loop retires instead of doubling up.
HorseCollisionModNoCrime.generation =
		(HorseCollisionModNoCrime.generation or 0) + 1
HorseCollisionModNoCrime.stop = false

-- Advanced on every pass. A load screen discards the timer while leaving
-- this table behind, so the generation number alone cannot say whether the
-- loop is still running; a pass count that stops rising can.
HorseCollisionModNoCrime.passes = 0

local WANTED_INTERVAL = 1000

-- The option sweep is far cheaper than it looks, because setting an option an
-- NPC already holds is a no-op, but it still walks the entity list. Every two
-- seconds is well inside the time it takes to ride up to a fresh crowd.
local PEACE_INTERVAL = 2000
local RANGE = 50

local HANDLE = "hcm_peace"

local OPTIONS = {
	"disableChangeHostilityOnHit",
	"suppressDudeHostilePerceptionStimuli"
}

local generation = HorseCollisionModNoCrime.generation

local function alive()
	return not HorseCollisionModNoCrime.stop
			and generation == HorseCollisionModNoCrime.generation
end

local function clearWanted()
	if not alive() then
		return
	end

	pcall(function()
		Game.SetWantedLevel(0)
	end)

	Script.SetTimer(WANTED_INTERVAL, clearWanted)
end

local function keepPeace()
	if not alive() then
		System.LogAlways("[NOCRIME] stopped")

		return
	end

	local origin = nil

	pcall(function()
		origin = player:GetWorldPos()
	end)

	if origin then
		for _, ent in pairs(System.GetEntities() or {}) do
			if ent ~= player and ent.actor and ent.soul then
				local pos = nil

				pcall(function()
					pos = ent:GetWorldPos()
				end)

				if pos then
					local dx = pos.x - origin.x
					local dy = pos.y - origin.y

					if (dx * dx + dy * dy) < (RANGE * RANGE) then
						for _, option in ipairs(OPTIONS) do
							pcall(function()
								Contexts.SetNonpersistentOption(ent, option, HANDLE)
							end)
						end
					end
				end
			end
		end
	end

	HorseCollisionModNoCrime.passes = HorseCollisionModNoCrime.passes + 1

	Script.SetTimer(PEACE_INTERVAL, keepPeace)
end

clearWanted()
keepPeace()

System.LogAlways("[NOCRIME] clearing the wanted level every "
		.. (WANTED_INTERVAL / 1000) .. "s and holding "
		.. #OPTIONS .. " peace options on humans within " .. RANGE
		.. "m, generation " .. generation
		.. ". Set HorseCollisionModNoCrime.stop = true to end it.")
