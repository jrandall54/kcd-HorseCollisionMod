--- Logs what a provoked victim is actually doing, once a second.
--
-- The retaliation telemetry reports the start and the end of an incident and
-- nothing in between, so a fight that stalls leaves no record of what it
-- stalled in. This samples every human near the player, and the player
-- alongside them, so the moment of a swing and whatever the victim does next
-- sit in the same timeline.
--
-- Read the `[FIGHT]` lines in kcd.log. Each carries the animation state,
-- whether a weapon is drawn, the distance to the player, and the victim's
-- relationship to him, which is the value several `sb_combat.xml` branches
-- are gated on.
--
--     python tools/dev_console.py --file tools/dev_watchfight.lua
--
-- Development only. It touches nothing and does not survive a save load.

HorseCollisionModWatchFight = HorseCollisionModWatchFight or {}

-- Bumped on every run so an earlier loop retires instead of doubling up.
HorseCollisionModWatchFight.generation =
		(HorseCollisionModWatchFight.generation or 0) + 1
HorseCollisionModWatchFight.stop = false

-- Advanced on every pass. A load screen discards the timer while leaving this
-- table behind, so a pass count that stops rising is what says it died.
HorseCollisionModWatchFight.passes = 0

local INTERVAL = 1000
local RANGE = 10

local generation = HorseCollisionModWatchFight.generation

local function describe(ent, origin)
	local state = "?"
	local drawn = "?"
	local rel = "?"
	local dist = -1

	pcall(function()
		state = tostring(ent.actor:GetCurrentAnimationState())
	end)

	pcall(function()
		drawn = tostring(ent.human:IsWeaponDrawn())
	end)

	pcall(function()
		rel = string.format("%.2f", ent.soul:GetRelationship(player.this.id))
	end)

	pcall(function()
		local p = ent:GetWorldPos()

		dist = math.sqrt((p.x - origin.x) ^ 2 + (p.y - origin.y) ^ 2)
	end)

	return tostring(ent:GetName()) .. " state=" .. state
			.. " drawn=" .. drawn .. " rel=" .. rel
			.. " dist=" .. string.format("%.1f", dist)
end

local function sample()
	if HorseCollisionModWatchFight.stop
			or generation ~= HorseCollisionModWatchFight.generation then
		System.LogAlways("[FIGHT] stopped")

		return
	end

	local origin = nil

	pcall(function()
		origin = player:GetWorldPos()
	end)

	if origin then
		local own = "?"

		pcall(function()
			own = tostring(player.actor:GetCurrentAnimationState())
		end)

		System.LogAlways("[FIGHT] dude state=" .. own)

		for _, ent in pairs(System.GetEntities() or {}) do
			if ent ~= player and ent.actor and ent.soul then
				local p = nil

				pcall(function()
					p = ent:GetWorldPos()
				end)

				if p and ((p.x - origin.x) ^ 2 + (p.y - origin.y) ^ 2)
						< (RANGE * RANGE) then
					System.LogAlways("[FIGHT] " .. describe(ent, origin))
				end
			end
		end
	end

	HorseCollisionModWatchFight.passes =
			HorseCollisionModWatchFight.passes + 1

	Script.SetTimer(INTERVAL, sample)
end

sample()

System.LogAlways("[FIGHT] sampling humans within " .. RANGE .. "m every "
		.. (INTERVAL / 1000) .. "s, generation " .. generation
		.. ". Set HorseCollisionModWatchFight.stop = true to end it.")
