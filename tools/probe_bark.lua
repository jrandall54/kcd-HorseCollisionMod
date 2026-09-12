-- Whether a chosen vanilla spoken line can be driven from Lua, and how an NPC
-- has to be addressed for it to land.
--
-- The project had this recorded as impossible: `dialog:monologRequest` accepted
-- every time, no error, no voice line. That was wrong, and two mistakes put it
-- there. The settling experiment called vanilla's own helper on the player with
-- `KOLIZE_S_HRACEM_NA_KONI`, a metarole Henry's soul does not hold, so silence
-- was guaranteed whatever the route did. And `monologRequestExecution` in
-- `final/sb_dialog.xml` drops a request outright when the speaker's context
-- carries `suppressMonologs` unless `overrideContextSuppress` is set, which no
-- earlier attempt set.
--
-- Corrected, it works. Sent to `player.this.id` with `JINDRICH_NARAZIL_NA_MRTVOLY`
-- and the gates overridden, Henry spoke two lines from that bark set, the
-- Skalitz line and the one over Bianca's body, standing in a street with no
-- corpse in sight. Both `DialogUtils.RequestPlayerMonologByMetarole` and a
-- typed `SendMessageToEntityData` produced it.
--
-- What remains open is the NPC. Every send to a woman two metres away was
-- silent while Henry talked, and the likely reason is the handle. The mod's own
-- messages that do land on NPCs -- `combat:hit` and `hitReaction` in
-- `Crime.lua` -- all resolve the target as `npc.this.id` and fall back to
-- `npc.id`, and vanilla addresses the player the same way. This probe sends the
-- same metarole both ways to separate the two.
--
-- Usage, from the repository root:
--   python tools/dev_console.py --file tools/probe_bark.lua --wait 50

-- Long enough for a line to finish. At five seconds Henry's second bark cut off
-- his first, which is how the interrupt behaviour was noticed.
local GAP_MS = 8000
local SEARCH = 15

local function log(message)
	System.LogAlways("[BarkProbe] " .. tostring(message))
end

--- Whether an entity's soul is currently flagged as being in dialog.
--
-- This is the probe's own witness. A speaking character reads true here, so a
-- run can be scored from the log alone rather than depending on the rider
-- catching a line by ear. It is how Henry's monolog was confirmed to have
-- executed even though the next candidate cut it short.
--
-- Nothing clears this any more. An earlier version interrupted a stuck dialog
-- before each send, which worked, and also truncated the very line the probe
-- had just successfully started.
local function inDialog(entity)
	local state = "?"

	pcall(function()
		state = tostring(entity.human:IsInDialog())
	end)

	return state
end

--- The entity handle brain messages are addressed to.
--
-- `npc.this.id` where it exists, `npc.id` otherwise, which is what
-- `HorseCollisionMod:SendCrimeHit` and every other message in this mod that
-- demonstrably reaches an NPC uses.
local function brainId(entity)
	if entity.this and entity.this.id then
		return entity.this.id
	end

	return entity.id
end

--- Builds a fully typed monologRequest and sends it.
--
-- `Utils.makeTable` fills every member the type declares. A hand-built table
-- leaves the receiving node with nothing to match on.
local function send(targetId, metarole, extra)
	local fields = {
		metarole = metarole,
		overrideContextSuppress = true,
		forceOnMuted = true,
		forceSubtitles = true
	}

	for k, v in pairs(extra or {}) do
		fields[k] = v
	end

	local ok, err = pcall(function()
		local msg = Utils.makeTable("dialog:monologRequest", fields)

		XGenAIModule.SendMessageToEntityData(targetId,
				"dialog:monologRequest", msg)
	end)

	if not ok then
		log("  send failed: " .. tostring(err))
	end
end

--- The nearest human NPC.
--
-- Class rather than `ent.actor and ent.soul`, which matches horses and dogs
-- too. Of the 1626 souls that do not hold `KOLIZE_S_HRACEM_NA_KONI`, 234 are
-- horses and 18 are dogs, so a mounted rider's own horse would otherwise be the
-- nearest match and could never say the line.
local function isHuman(ent)
	local human = false

	pcall(function()
		human = (ent.class == "NPC" or ent.class == "NPC_Female")
	end)

	return human
end

local function nearestNpc()
	local pos = player:GetWorldPos()
	local best, bestDist = nil, SEARCH + 1

	for _, ent in pairs(System.GetEntitiesInSphere(pos, SEARCH) or {}) do
		if ent ~= player and isHuman(ent) and ent.soul then
			local p = ent:GetWorldPos()
			local dx, dy = p.x - pos.x, p.y - pos.y
			local d = math.sqrt((dx * dx) + (dy * dy))

			if d < bestDist then
				best, bestDist = ent, d
			end
		end
	end

	return best, bestDist
end

local npc, npcDist = nearestNpc()
local npcName = npc and HorseCollisionMod:NameOf(npc) or "none"

-- Logged so a silence can be cross-referenced against `soul2metarole.xml`
-- afterwards. A speaker that does not hold the metarole is silent for a reason
-- that has nothing to do with the route, and that confusion is what stalled
-- this investigation the first time.
log("nearest npc " .. npcName
		.. (npc and string.format(" class=%s at %.1fm",
				tostring(npc.class), npcDist) or ""))

if npc then
	log("npc handles: this.id=" .. tostring(npc.this and npc.this.id ~= nil)
			.. " id=" .. tostring(npc.id ~= nil))
end

-- The NPC candidates run first, while the rider's attention is freshest, and
-- the known-good Henry line runs last as an end-to-end marker: if it speaks,
-- the probe reached the end and any NPC silence above it is a real result
-- rather than a probe that died half way.
local candidates = {
	{
		label = "1 npc via this.id, RANENY_NA_ZEMI",
		npc = true,
		fire = function()
			send(brainId(npc), "RANENY_NA_ZEMI")
		end
	},
	{
		label = "2 npc via this.id, KOLIZE_S_HRACEM_NA_KONI",
		npc = true,
		fire = function()
			send(brainId(npc), "KOLIZE_S_HRACEM_NA_KONI")
		end
	},
	{
		label = "3 npc via this.id, KOLIZE_S_HRACEM_LEHKA, priority 2",
		npc = true,
		fire = function()
			send(brainId(npc), "KOLIZE_S_HRACEM_LEHKA", { priority = 2 })
		end
	},
	{
		-- The control. Same metarole as candidate 1, addressed the way the
		-- silent runs addressed it. If 1 speaks and this does not, the handle
		-- is the whole answer.
		label = "4 npc via raw id, RANENY_NA_ZEMI  (control)",
		npc = true,
		fire = function()
			send(npc.id, "RANENY_NA_ZEMI")
		end
	},
	{
		-- Henry, a metarole he holds and would never volunteer in a street.
		-- Deliberately not the corpse set used before, in case a bark that has
		-- just played is suppressed as a repeat.
		label = "5 player marker, JINDRICH_NEMUZE_DO_HLUBOKE_VODY",
		fire = function()
			send(player.this.id, "JINDRICH_NEMUZE_DO_HLUBOKE_VODY")
		end
	}
}

local function fireAt(index)
	local candidate = candidates[index]

	if not candidate then
		log("done, all candidates fired")
		return
	end

	if candidate.npc and not npc then
		log(candidate.label .. "  SKIPPED, no npc in range")
	else
		log(candidate.label
				.. "  [player inDialog=" .. inDialog(player)
				.. (npc and ("  npc inDialog=" .. inDialog(npc)) or "")
				.. "]")

		local ok, err = pcall(candidate.fire)

		if not ok then
			log("  raised: " .. tostring(err))
		end
	end

	Script.SetTimer(GAP_MS, function()
		fireAt(index + 1)
	end)
end

log("firing " .. #candidates .. " candidates, "
		.. (GAP_MS / 1000) .. "s apart")
fireAt(1)
