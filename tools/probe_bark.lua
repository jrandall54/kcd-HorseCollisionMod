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
-- Corrected, it works on the player and on NPCs. By ear, Henry speaks
-- two lines from `JINDRICH_NARAZIL_NA_MRTVOLY` in a street with no corpse in
-- sight, and townspeople spoke `NASILI_UTEK`, `KDO_TAM_CITOSLOVCE`,
-- `RANENY_NA_ZEMI`, `UVIDI_MRTVOLU`, `VOLANI_STRAZE_MRTVOLA` and
-- `ZASAH_ZBRANI_IGNOROVANY` on request.
--
-- What decides whether a request is heard is audio, not holding. `GetMetaRoles`
-- on a townswoman returns five conversational sets and `HasMetaRoleByName` is
-- false for sets she had already spoken, so the holding tables are not a gate.
-- The speaker.s voice must simply have the topic recorded, which is what made
-- refugees look like proof the whole route was broken.
--
-- SOLO takes a metarole name or a topic id. One per run: a six candidate run
-- asks the rider to hold six observations while the reply is written, and four
-- lines were lost that way.
--
--   python tools/dev_console.py --file tools/probe_bark.lua --wait 14

local SOLO = "@dudeSurrender_combat"

-- Grant the metarole to the target before asking for it, then take it back.
--
-- The interesting case is a set no soul in the game holds. `COMBAT_TAUNTING_WEAK`
-- and `_STRONG` are held by zero of the 5025 souls, yet their topic carries
-- "Come on then, whoreson!" and the rest. If a
-- grant makes those reachable, every dead metarole opens up and the palette
-- stops being limited to what Warhorse happened to assign.
--
-- `entity.soul:AddMetaRoleByName` is live and vanilla pairs it with
-- `RemoveMetaRoleByName` on exit, in `sa_bathhouse.xml` and `archery_tourney.xml`
-- among others. The removal here matters: leaving a townsman holding a combat
-- taunt set would change his behavior for the rest of the save.
local GRANT = false

-- Send to Henry instead of an NPC.
--
-- The alias test needs this. Vanilla's own player barks are raised in
-- `player.xml` as `alias($barkAlias)` with values like `dudeSurrender_combat`
-- and `activity_advanceTutorial_henryEnd`, which are Henry's lines. Sending a
-- real label to the speaker it was written for is the only fair test of the
-- `alias` field: an invented label proves nothing when it is silent, which is
-- how the first attempt at this was wasted.
local AT_PLAYER = true

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

	-- A number is a topic id, which does not work. A string beginning with "@"
	-- is a topic label, the `alias` field, which vanilla uses heavily:
	-- `alias('monastery_amen')` and 860 others across its AI. `StartMonolog`
	-- on the dialog script bind takes its topic as a `const char*` too, which
	-- is the hint that the string key is the real addressing scheme and the
	-- integer one is not. Anything else is a metarole.
	if type(what) == "number" then
		fields.topicId = what
	elseif string.sub(what, 1, 1) == "@" then
		fields.alias = string.sub(what, 2)
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

if AT_PLAYER then
	log("target: Henry")
	log("firing " .. tostring(SOLO))
	send(player.this.id, SOLO)
	return
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

if GRANT and type(SOLO) == "string" then
	local ok, err = pcall(function()
		npc.soul:AddMetaRoleByName(SOLO)
	end)

	log("granted " .. SOLO .. ": " .. tostring(ok)
			.. (ok and "" or (" " .. tostring(err))))
end

log("firing " .. tostring(SOLO))

send((npc.this and npc.this.id) or npc.id, SOLO)

-- Taken back once the line has had time to play. Vanilla always pairs the two.
if GRANT and type(SOLO) == "string" then
	Script.SetTimer(9000, function()
		pcall(function()
			npc.soul:RemoveMetaRoleByName(SOLO)
		end)

		log("revoked " .. SOLO)
	end)
end
