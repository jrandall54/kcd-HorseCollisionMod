-- Finds out what the dialog system reports about a refused request.
--
--     python tools/dev_console.py --file tools/probe_dialog_state.lua
--
-- The problem this serves: the mod sent 57 spoken-line requests in one ride and
-- the rider heard perhaps eight of them. Every one logged `sent=true`, because
-- `SendMessageToEntityData` reports only that the message was posted. So there
-- is no signal at all for the refusals, and without one the only instrument is
-- the rider's attention, which has already been established as the wrong tool
-- for a fleeting event.
--
-- `C_ScriptBindDialog` exposes four readers that might carry that signal:
-- `IsSoulInDialog`, `IsSequenceAvailable`, `IsSequenceUsed` and `AnalyzeRequest`.
-- None of their argument lists survive in the headers, only their names, so this
-- calls each one through several plausible shapes and logs what comes back. A
-- shape that errors is as informative as one that answers.
--
-- Reads only. Nothing here sends a request or makes a sound, so it can be run
-- while the rider is doing something else.

local m = HorseCollisionMod

if not m then
	System.LogAlways("[HorseCollisionMod] DLGPROBE mod not loaded")
	return
end

-- One sequence from each alias in the impact pool, resolved from
-- `topic2sequence.xml` where its entry condition is always-true.
local SEQUENCES = {
	{ "q_dlc_revelation_pavelForce", 72447 },
	{ "q_nightWatch_noGateGuards", 51778 },
	{ "q_night_rescue_prepare", 47997 },
	{ "q_returnToSkalitz_heyYou", 22074 },
	{ "event_chase_thiefDown", 48633 },
	{ "q_millerDate_dFirstDateAfterTalk", 35703 },
	{ "q_rides_traitor_henry_trail_skirt", 66453 },
	{ "revelation_murderer_ohfuck", 66549 },
	{ "q_abbots_list_henry_foundList", 41605 },
}

local function log(text)
	System.LogAlways("[HorseCollisionMod] DLGPROBE " .. text)
end

if type(DialogModule) ~= "table" and type(DialogModule) ~= "userdata" then
	log("DialogModule is " .. type(DialogModule) .. ", nothing to read")
	return
end

-- What the table actually holds, which is the ground truth the header only
-- describes. A name absent here is not callable however it is documented.
local names = {}

for key, value in pairs(DialogModule) do
	if type(value) == "function" then
		names[#names + 1] = tostring(key)
	end
end

table.sort(names)
log("functions=" .. table.concat(names, ","))

-- Henry, in each of the shapes the bind might want him in.
local soulId = nil

pcall(function()
	soulId = player.soul:GetSoulId()
end)

local wuid = nil

pcall(function()
	wuid = XGenAIModule.GetMyWUID(player)
end)

log("player id=" .. tostring(player.id)
		.. " soulId=" .. tostring(soulId)
		.. " wuid=" .. tostring(wuid))

-- Calls one function through one argument list and says what happened. A
-- returned value and a raised error are both results worth having.
local function try(name, label, ...)
	local fn = DialogModule[name]

	if type(fn) ~= "function" then
		log(name .. " absent")
		return
	end

	local args = { ... }
	local ok, result = pcall(function()
		return fn(DialogModule, unpack(args))
	end)

	log(name .. "(" .. label .. ") ok=" .. tostring(ok)
			.. " -> " .. tostring(result))
end

try("IsSoulInDialog", "soulId", soulId)
try("IsSoulInDialog", "entityId", player.id)
try("IsSoulInDialog", "wuid", wuid)

local alias, sequence = SEQUENCES[1][1], SEQUENCES[1][2]

try("IsSequenceAvailable", "seq", sequence)
try("IsSequenceAvailable", "soulId,seq", soulId, sequence)
try("IsSequenceAvailable", "entityId,seq", player.id, sequence)
try("IsSequenceUsed", "seq", sequence)
try("IsSequenceUsed", "soulId,seq", soulId, sequence)
try("IsSequenceUsed", "entityId,seq", player.id, sequence)
try("AnalyzeRequest", "nothing")
try("AnalyzeRequest", "entityId", player.id)
try("IsDialogInterruptibleByPlayer", "nothing")

log("first sequence tried was " .. alias .. " seq=" .. tostring(sequence))

-- Once a working shape is known, the same reader over the whole pool says
-- whether the refusals are per-sequence or global. Both loops are written
-- against the bare-sequence shape and simply report nothing if that is wrong.
for _, entry in ipairs(SEQUENCES) do
	local avail, used = "?", "?"

	pcall(function()
		avail = tostring(DialogModule:IsSequenceAvailable(entry[2]))
	end)

	pcall(function()
		used = tostring(DialogModule:IsSequenceUsed(entry[2]))
	end)

	log("pool " .. entry[1] .. " seq=" .. tostring(entry[2])
			.. " available=" .. avail .. " used=" .. used)
end
