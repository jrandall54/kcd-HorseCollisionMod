-- Refuses a settings file whose per-tier tables differ from Tiers.lua.
--
-- Tiers.lua declares each `...ByTier` table and the settings file restates it
-- for players. The settings file wins at load, so a row that differs silently
-- replaces the declared value. Run from the repository root:
--
--     luajit tools/check_tiers.lua
--
-- Exits 1 and names every differing row.

HorseCollisionMod = { Config = {} }
dofile("src/HorseCollisionMod/Tiers.lua")
dofile("src/HorseCollisionMod_Settings.lua")

local settings = HorseCollisionModSettings

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for k, v in pairs(a) do
		if not same(v, b[k]) then
			return false
		end
	end

	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end

	return true
end

local names = {}

for name, value in pairs(HorseCollisionMod) do
	if type(value) == "table" and name:match("ByTier$")
			and type(settings[name]) == "table" then
		names[#names + 1] = name
	end
end

table.sort(names)

local bad = 0

for _, name in ipairs(names) do
	local declared, written = HorseCollisionMod[name], settings[name]
	local tiers = {}

	for tier in pairs(declared) do tiers[tier] = true end
	for tier in pairs(written) do tiers[tier] = true end

	for tier in pairs(tiers) do
		if not same(declared[tier], written[tier]) then
			bad = bad + 1
			print(string.format("  %s.%s: Tiers.lua %s, settings file %s",
					name, tier, tostring(declared[tier]), tostring(written[tier])))
		end
	end
end

if bad > 0 then
	print(string.format("%d tier row(s) in the settings file differ from Tiers.lua.", bad))
	os.exit(1)
end

print(string.format("Tier tables agree (%d compared).", #names))
