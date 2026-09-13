-- Auditions Henry's impact lines one at a time, on the rider's own timing.
--
--     python tools/dev_console.py --file tools/dev_riderbark.lua
--
-- Run it again for the next line. It walks `RiderBarkAliases` in order, keeping
-- its place on the mod table, and reports which line it just asked for so the
-- log says what should have been heard even if the moment was missed.
--
-- This exists because auditioning by firing on someone else's timing and asking
-- "did you hear it" does not work: a report of silence from a rider who was mid-ride or
-- looking elsewhere is a missed observation, not a negative result, and a theory
-- was built on three of them before that came out. Running it yourself removes
-- the attention problem entirely -- you fire when you are listening.
--
-- SPEAK names one alias to hear instead of advancing through the list, for when
-- a particular line needs checking twice.
--
-- The expected text for each alias is carried here so the log line says what to
-- listen for. It comes from `tools/bark_alias.py`, which reads the shipped
-- localization rather than anybody's memory of it.

local SPEAK = nil

local LINES = {
	{ "revelation_murderer_ohfuck", "Oh fuck!" },
	{ "q_rides_traitor_henry_trail_skirt", "Shameless hussy!" },
	{ "q_counterfeiters_crimeScene_area", "Good God, what a bloody mess." },
	{ "event_chase_thiefDown", "Had enough?" },
	{ "q_returnToSkalitz_deadPeople", "Jesus..." },
	{ "q_returnToSkalitz_deadHangman", "Oh, God." },
}

local m = HorseCollisionMod

if not m then
	System.LogAlways("[HorseCollisionMod] AUDITION mod not loaded")
	return
end

local alias, expected

if SPEAK then
	alias, expected = SPEAK, "(named directly)"
else
	local at = (m.AuditionAt or 0) + 1

	if at > #LINES then
		at = 1
	end

	m.AuditionAt = at
	alias, expected = LINES[at][1], LINES[at][2]
end

local target = player.id

if player.this and player.this.id then
	target = player.this.id
end

local fields = {
	alias = alias,
	forceOnMuted = true,
	priority = m.Config.BarkPriority or 0,
	canBeDelayed = false,
	overrideContextSuppress = true
}

local ok, err = pcall(function()
	XGenAIModule.SendMessageToEntityData(target, "dialog:monologRequest",
			Utils.makeTable("dialog:monologRequest", fields))
end)

System.LogAlways("[HorseCollisionMod] AUDITION "
		.. tostring(m.AuditionAt or "?") .. "/" .. tostring(#LINES)
		.. " alias=" .. alias
		.. " expect=\"" .. expected .. "\""
		.. " sent=" .. tostring(ok)
		.. (ok and "" or (" err=" .. tostring(err))))
