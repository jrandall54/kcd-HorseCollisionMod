-- Makes a chosen character speak a chosen vanilla line, to audition it.
--
-- The project had recorded this as impossible: `dialog:monologRequest` accepted
-- every time, no error, no voice line. Two faults put it there. The settling
-- experiment called vanilla's helper on the player with
-- `KOLIZE_S_HRACEM_NA_KONI`, a metarole Henry's soul does not hold, so silence
-- was guaranteed whatever the route did. And the model that a dialog subbrain
-- is not running on an idle townsman is wrong: `monologRequest` is mounted in
-- `final/sb_switch.xml` inside `<While condition="true">` in the always-running
-- Parallel, a sibling of `combatSubbrainStarter`.
--
-- Corrected, it works on the player and on NPCs. Confirmed by ear: Henry spoke
-- two lines from `JINDRICH_NARAZIL_NA_MRTVOLY` in a street with no corpse in
-- sight, and townspeople spoke `NASILI_UTEK`, `KDO_TAM_CITOSLOVCE`,
-- `RANENY_NA_ZEMI`, `UVIDI_MRTVOLU`, `VOLANI_STRAZE_MRTVOLA` and
-- `ZASAH_ZBRANI_IGNOROVANY` on request.
--
-- Two things decide whether a request is heard. The soul must hold the
-- metarole, which is in `soul2metarole.xml`, and that character's voice must
-- have the topic recorded, which is in the ogg filenames in `English.pak`. A
-- request that fails either is accepted and silent, which is what made
-- refugees look like proof the whole route was broken.
--
-- SOLO takes a metarole name or a topic id. One per run: a six candidate run
-- asks the rider to hold six observations while I reply, and four lines were
-- lost that way.
--
--   python tools/dev_console.py --file tools/probe_bark.lua --wait 14

local SOLO = 22722

local SEARCH = 15

local function log(message)
	System.LogAlways("[BarkProbe] " .. tostring(message))
end

--- Sends the request. A number selects a topic, a string a metarole.
--
-- `topicId` matters because a metarole can be state gated while the lines
-- behind it are not, and because some topics have no metarole holding them at
-- all. Vanilla sends topics directly too: `archery_tourney.xml` uses
-- `values="topicId(11002)"`.
--
-- `Utils.makeTable` fills every member the type declares; a hand-built table
-- leaves the receiving node with nothing to match on. `overrideContextSuppress`
-- clears the `suppressMonologs` gate in `monologRequestExecution`.
local function send(targetId, what)
	local fields = {
		overrideContextSuppress = true,
		forceOnMuted = true,
		forceSubtitles = true
	}

	if type(what) == "number" then
		fields.topicId = what
	else
		fields.metarole = what
	end

	local ok, err = pcall(function()
		XGenAIModule.SendMessageToEntityData(targetId, "dialog:monologRequest",
				Utils.makeTable("dialog:monologRequest", fields))
	end)

	if not ok then
		log("send failed: " .. tostring(err))
	end
end

--- The human the rider is looking at, falling back to the nearest.
--
-- Proximity alone picks the wrong person constantly: in a street the closest
-- human flips between whoever the rider is following and whoever brushes past,
-- and the rider cannot tell which was chosen because their game has no
-- nametags. Scored as distance over how well the target lines up with the view
-- axis, so someone further away but straight ahead beats someone closer to the
-- side.
--
-- Class rather than `ent.actor and ent.soul`, which matches horses and dogs:
-- of the 1626 souls that cannot say `KOLIZE_S_HRACEM_NA_KONI`, 234 are horses.
local function pick()
	local pos = player:GetWorldPos()
	local dir = player:GetDirectionVector(1)
	local best, bestScore, bestDist, bestFacing = nil, nil, 0, false

	for _, ent in pairs(System.GetEntitiesInSphere(pos, SEARCH) or {}) do
		local human = false

		pcall(function()
			human = (ent.class == "NPC" or ent.class == "NPC_Female")
		end)

		if ent ~= player and human and ent.soul then
			local p = ent:GetWorldPos()
			local dx, dy = p.x - pos.x, p.y - pos.y
			local d = math.sqrt((dx * dx) + (dy * dy))
			local aim = (d > 0.01 and dir)
					and (((dx * dir.x) + (dy * dir.y)) / d) or 0

			if aim > 0.3 then
				local score = d / aim

				if (not bestFacing) or score < bestScore then
					best, bestScore, bestDist, bestFacing = ent, score, d, true
				end
			elseif not bestFacing then
				if (not best) or d < bestDist then
					best, bestDist = ent, d
				end
			end
		end
	end

	return best, bestDist, bestFacing
end

local npc, dist, facing = pick()

if not npc then
	log("no human within " .. SEARCH .. "m")
	return
end

-- Described the way the rider sees them. Their game shows no nametags, so an
-- internal entity name tells them nothing about who to watch.
local who = (npc.class == "NPC_Female") and "woman" or "man"

log(string.format("target: %s %.1fm away, %s", who, dist,
		facing and "in front of you" or "NOT in view, nearest instead"))
log("firing " .. tostring(SOLO))

send((npc.this and npc.this.id) or npc.id, SOLO)
