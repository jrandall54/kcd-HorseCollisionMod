-- What does the physics engine think the horse weighs?
--
-- The mod writes a victim's mass and measures the throw, and across a 25 to
-- 295 kg range the throw does not respond. One explanation is that the horse
-- is not exchanging momentum with the victim at all: a living entity driven
-- by an animation controller imposes a velocity on what it hits rather than
-- trading momentum with it, and under that model the victim's mass cannot
-- affect the launch speed no matter what it is set to.
--
-- This reports the masses and physics identity of the horse, the player and
-- the nearest NPC, so the ratio the engine is actually working with is known
-- rather than assumed.
--
--     python tools/dev_console.py --file tools/probe_horse_mass.lua

local function say(text)
	System.LogAlways("[HorseMass] " .. tostring(text))
end

local function describe(label, ent)
	if not ent then
		say(label .. ": no entity")
		return
	end

	local mass = "?"
	local pos = "?"

	pcall(function()
		mass = ent:GetMass()
	end)

	pcall(function()
		local p = ent:GetWorldPos()
		pos = string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z)
	end)

	-- Which extensions the entity carries says what kind of physics it has.
	-- An actor is a living entity, which is animation driven; a rigid body
	-- is not.
	local parts = {}

	for _, name in ipairs({ "actor", "soul", "human", "horse", "physics" }) do
		if ent[name] then
			parts[#parts + 1] = name
		end
	end

	say(string.format("%s: mass=%s class=%s pos=%s ext=[%s]",
			label, tostring(mass), tostring(ent.class), pos,
			table.concat(parts, " ")))
end

local horseWuid = nil

pcall(function()
	horseWuid = player.player:GetPlayerHorse()
end)

local horseEnt = nil

if horseWuid then
	pcall(function()
		horseEnt = XGenAIModule.GetEntityByWUID(horseWuid)
	end)
end

describe("horse ", horseEnt)
describe("player", player)

-- The nearest human, for the figure a victim starts from.
local nearest = nil
local nearestDist = 1e9
local origin = player:GetWorldPos()

for _, ent in pairs(System.GetEntities() or {}) do
	if ent ~= player and ent ~= horseEnt and ent.actor and ent.soul then
		local ok, p = pcall(function()
			return ent:GetWorldPos()
		end)

		if ok and p then
			local dx, dy, dz = p.x - origin.x, p.y - origin.y, p.z - origin.z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)

			if d < nearestDist then
				nearestDist = d
				nearest = ent
			end
		end
	end
end

describe(string.format("npc@%.0fm", nearestDist), nearest)

-- The velocity the horse carries, for the momentum figure.
if horseEnt then
	pcall(function()
		local v = horseEnt:GetVelocity()
		say(string.format("horse velocity=%.2f m/s", math.sqrt(
				v.x * v.x + v.y * v.y + v.z * v.z)))
	end)
end
