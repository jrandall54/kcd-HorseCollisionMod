-- Lists the methods an object actually exposes in the running game.
--
-- Better evidence than either of the written references. The
-- `C_ScriptBind*` headers in `references/libKCD1` describe script binds, and
-- several of the most useful globals are reached another way and are absent
-- from them: `Calendar`, `Game`, `Database`, `Entity` and `Physics` are all
-- missing there. Grepping `vanilla_scripts/` finds only what vanilla happens
-- to call, which is a fraction of what exists.
--
-- This asks the game. Edit `WANTED` and run:
--
--     python tools/dev_console.py --file tools/probe_api.lua
--
-- A bound C++ object keeps its methods on its metatable's `__index` rather
-- than as direct keys, so the walk follows that chain. Depth is capped
-- because those chains can be circular.
--
-- The counts this found on a 1.9.7 build, for comparison: Entity 290, player
-- 437, player.actor 100, player.soul 56, player.human 43, player.player 30,
-- player.inventory 20.

local WANTED = {
	{ "Entity", function() return rawget(_G, "Entity") end },
	{ "player.actor", function() return player and player.actor end },
	{ "player.soul", function() return player and player.soul end },
	{ "player.human", function() return player and player.human end },
	{ "player.player", function() return player and player.player end },
}

-- Emitted in batches, because one line long enough to hold a hundred names is
-- truncated before it reaches the log.
local PER_LINE = 8

local function methodsOf(label, obj)
	if obj == nil then
		System.LogAlways("[API] " .. label .. " = nil")

		return
	end

	local seen = {}
	local out = {}

	local function walk(t, depth)
		if type(t) ~= "table" or depth > 3 then
			return
		end

		for k, v in pairs(t) do
			if type(k) == "string" and not seen[k] then
				seen[k] = true
				out[#out + 1] = k .. (type(v) == "function" and "()" or "")
			end
		end

		local mt = getmetatable(t)

		if type(mt) == "table" then
			walk(rawget(mt, "__index"), depth + 1)
		end
	end

	walk(obj, 1)
	table.sort(out)

	System.LogAlways("[API] " .. label .. " has " .. #out .. " entries")

	for i = 1, #out, PER_LINE do
		local part = {}

		for j = i, math.min(i + PER_LINE - 1, #out) do
			part[#part + 1] = out[j]
		end

		System.LogAlways("[API]   " .. label .. ": " .. table.concat(part, " "))
	end
end

for _, entry in pairs(WANTED) do
	local ok, obj = pcall(entry[2])

	methodsOf(entry[1], ok and obj or nil)
end
