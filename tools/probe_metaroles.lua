-- Asks the character in front of the rider which bark sets they actually hold.
--
-- Everything so far inferred this from `soul2metarole.xml` and the resolved
-- view `v_soul2role_metarole.xml`, joined offline. That inference has been
-- wrong at least once already: a voice coverage check built the same way said
-- no village guard voice had topic 22722 recorded, and a village guard then
-- spoke it. Guessing which sets a target can receive is what produced most of
-- the silent auditions.
--
-- `soul:GetMetaRoles` and `soul:HasMetaRoleByName` are live binds, listed on
-- the soul script bind in `references/libKCD1`. Reading the running game
-- removes the guesswork entirely: whatever comes back is what that character
-- can be asked for.
--
--   python tools/dev_console.py --file tools/probe_metaroles.lua --wait 8

local SEARCH = 15

local function log(message)
	System.LogAlways("[Metaroles] " .. tostring(message))
end

--- The human the rider is looking at, falling back to the nearest.
local function pick()
	local pos = player:GetWorldPos()
	local dir = player:GetDirectionVector(1)
	local best, bestScore, bestDist, facing = nil, nil, 0, false

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
				if (not facing) or (d / aim) < bestScore then
					best, bestScore, bestDist, facing = ent, d / aim, d, true
				end
			elseif not facing then
				if (not best) or d < bestDist then
					best, bestDist = ent, d
				end
			end
		end
	end

	return best, bestDist, facing
end

local npc, dist, facing = pick()

if not npc then
	log("no human within " .. SEARCH .. "m")
	return
end

log(string.format("%s %.1fm away, %s",
		(npc.class == "NPC_Female") and "woman" or "man", dist,
		facing and "in front of you" or "NOT in view, nearest instead"))

-- The return shape is unknown, so it is probed rather than assumed. A table of
-- names, a table of ids, or something else entirely are all possible, and
-- printing the type first makes the next attempt cheap rather than a guess.
local roles = nil
local ok, err = pcall(function()
	roles = npc.soul:GetMetaRoles()
end)

if not ok then
	log("GetMetaRoles raised: " .. tostring(err))
elseif roles == nil then
	log("GetMetaRoles returned nil")
else
	log("GetMetaRoles returned a " .. type(roles))

	if type(roles) == "table" then
		local count, line = 0, {}

		for k, v in pairs(roles) do
			count = count + 1
			line[#line + 1] = tostring(k) .. "=" .. tostring(v)

			if #line >= 8 then
				log("  " .. table.concat(line, "  "))
				line = {}
			end
		end

		if #line > 0 then
			log("  " .. table.concat(line, "  "))
		end

		log("  " .. count .. " entries")
	else
		log("  value: " .. tostring(roles))
	end
end

-- The checked reader, against sets whose audition result is already known. If
-- these agree with what was heard, this is the instrument to drive every future
-- selection from.
local checks = {
	"ZASAH_ZBRANI_IGNOROVANY",   -- spoke
	"NASILI_UTEK",               -- spoke
	"REAKCE_NA_VRAZDU",          -- spoke
	"KOMENTAR_NA_JINDRU",        -- silent
	"COMBAT_TAUNTING_STRONG",    -- silent, held by nobody
	"HIT_REAKCE_SILNA"           -- silent, held by nobody
}

for _, name in ipairs(checks) do
	local has = "?"

	pcall(function()
		has = tostring(npc.soul:HasMetaRoleByName(name))
	end)

	log(string.format("  has %-26s %s", name, has))
end
