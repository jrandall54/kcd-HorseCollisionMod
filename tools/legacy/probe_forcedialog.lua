-- Tries the two dialog script binds this project has never called.
--
-- `DialogModule.ForceDialog(speakerId, listenerId)` and
-- `DialogModule.StartMonolog(speakerId, topicId)` are both listed on
-- `C_ScriptBindDialog` in `references/libKCD1`. The diary records StartMonolog
-- as driving the dialog system without producing audio, but its signature
-- takes the topic as a `const char*`, and the earlier attempts passed numbers.
-- Since `alias` has now been shown to work on `dialog:monologRequest` --
-- `dudeSurrender_combat` made Henry say "Shit, leave me be, enough" -- the
-- string a topic is named by is worth trying here too.
--
-- ForceDialog may open a conversation rather than a bark, which would take
-- control away from the rider. Reloading a save undoes it.
--
--   python tools/dev_console.py --file tools/probe_forcedialog.lua --wait 10

local WHICH = "force"          -- "monolog" or "force"
local TOPIC = "dudeSurrender_combat"

local function log(message)
	System.LogAlways("[ForceDlg] " .. tostring(message))
end

local function pick()
	local pos = player:GetWorldPos()
	local dir = player:GetDirectionVector(1)
	local best, bestScore, bestDist = nil, nil, 0

	for _, ent in pairs(System.GetEntitiesInSphere(pos, 15) or {}) do
		local human = false

		pcall(function()
			human = (ent.class == "NPC" or ent.class == "NPC_Female")
		end)

		if ent ~= player and human and ent.soul then
			local p = ent:GetWorldPos()
			local dx, dy = p.x - pos.x, p.y - pos.y
			local d = math.sqrt((dx * dx) + (dy * dy))
			local aim = (d > 0.01) and (((dx * dir.x) + (dy * dir.y)) / d) or 0

			if aim > 0.3 and ((not bestScore) or (d / aim) < bestScore) then
				best, bestScore, bestDist = ent, d / aim, d
			end
		end
	end

	return best, bestDist
end

local npc, dist = pick()

if not npc then
	log("nobody in front of you")
	return
end

log(string.format("target: %s %.1fm in front",
		(npc.class == "NPC_Female") and "woman" or "man", dist))

if WHICH == "monolog" then
	-- The signature is (EntityId speakerId, const char* topicId), so the
	-- speaker is the entity and the topic is a string.
	log("StartMonolog on HENRY with topic string " .. TOPIC)

	local ok, err = pcall(function()
		DialogModule.StartMonolog(player.id, TOPIC)
	end)

	log("  returned ok=" .. tostring(ok)
			.. (ok and "" or (" " .. tostring(err))))
else
	log("ForceDialog npc -> player")

	local ok, err = pcall(function()
		DialogModule.ForceDialog(npc.id, player.id)
	end)

	log("  returned ok=" .. tostring(ok)
			.. (ok and "" or (" " .. tostring(err))))
end
