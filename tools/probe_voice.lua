-- Auditions one vanilla *vocal* audio trigger on a chosen character.
--
--     python tools/dev_console.py --file tools/probe_voice.lua --wait 6
--
-- This is a different route to a voice than `probe_bark.lua`. That one sends a
-- `dialog:monologRequest` and lets the dialog system pick a line; this one
-- fires an FMOD event by name, the same way `Sound.lua` already fires impact
-- foley. Nothing about it touches metaroles, roles, topics, priorities or the
-- victim's subbrain.
--
-- That matters for two things the mod cannot currently do. `Libs/GameAudio`
-- declares vocal events the dialog system never offers:
--
--     v_stealth_stealthkill_man      the cry of a man being killed
--     v_stealth_stealthkill_woman
--     v_stealth_takedown_man_short   a short grunt
--     v_henry_hit_heavy              Henry taking a hit, three severities
--     v_henry_hit_medium
--     v_henry_hit_soft
--
-- All eleven candidates resolved to real handles under
-- `Sound.GetAudioTriggerID`, so the only open questions are how they sound and
-- whether they play on a corpse.
--
-- ONE trigger per run. `probe_bark.lua` records why: a six candidate run asks
-- the rider to hold six observations at once and four of them were lost.

local TRIGGER = "v_henry_hit_heavy"

-- "npc"    the nearest living person in front of the rider
-- "player" Henry himself
-- "dead"   the nearest corpse, which is the decisive case for death sounds
local ON = "player"

local SEARCH = 40.0

local function say(msg)
	System.LogAlways("[HorseCollisionMod] VOICE " .. msg)
end

local id = Sound.GetAudioTriggerID(TRIGGER)

if not id then
	say("trigger=" .. TRIGGER .. " DOES NOT RESOLVE")
	return
end

local target, label = nil, "?"

if ON == "player" then
	target, label = player, "Henry"
else
	local playerPos = player:GetWorldPos()
	local wantDead = (ON == "dead")
	local bestDist = SEARCH

	for _, ent in pairs(System.GetEntitiesInSphere(playerPos, SEARCH) or {}) do
		local ok = false

		pcall(function()
			if ent == player or not ent.actor then
				return
			end

			if ent.class ~= "NPC" and ent.class ~= "NPC_Female" then
				return
			end

			local name = ent:GetName()

			-- Henry's dog is skipped here as everywhere else in the mod.
			if name and string.find(name, "dogCompanion") then
				return
			end

			local dead = (ent.IsDead and ent:IsDead()) and true or false

			if dead ~= wantDead then
				return
			end

			ok = true
		end)

		if ok then
			local p = ent:GetWorldPos()
			local dx, dy = p.x - playerPos.x, p.y - playerPos.y
			local d = math.sqrt((dx * dx) + (dy * dy))

			if d < bestDist then
				target, bestDist = ent, d
			end
		end
	end

	if not target then
		say("nobody " .. (wantDead and "dead" or "living") .. " within "
				.. tostring(SEARCH) .. " m")
		return
	end

	pcall(function()
		label = tostring(target:GetName()) .. " at "
				.. string.format("%.1f", bestDist) .. " m"
	end)
end

local proxy = target:GetDefaultAuxAudioProxyID()

target:ExecuteAudioTrigger(id, proxy)

say("played=" .. TRIGGER .. " on=" .. ON .. " target=" .. label)
