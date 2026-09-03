-- Does a written ragdoll mass survive the victim standing back up?
--
-- The mod writes a victim's mass through `PHYSICPARAM_SIMULATION` and never
-- writes it back. That write is only accepted once the body is a ragdoll, so
-- the open question is whether standing up re-physicalizes the actor as a
-- living entity and restores the engine's own figure, or whether a victim
-- ridden down at a base of 100 walks around at several tonnes for the rest of
-- the save.
--
-- Every human is 80 kg to the engine by default, so anything else is a mass
-- this mod wrote and the engine did not take back.
--
--     python tools/dev_console.py --file tools/probe_mass_persistence.lua

local function say(text)
	System.LogAlways("[MassPersist] " .. tostring(text))
end

local origin = player:GetWorldPos()
local found = {}

for _, ent in pairs(System.GetEntities() or {}) do
	if ent ~= player and ent.actor and ent.soul then
		local ok, pos = pcall(function()
			return ent:GetWorldPos()
		end)

		if ok and pos then
			local dx, dy = pos.x - origin.x, pos.y - origin.y
			local dist = math.sqrt(dx * dx + dy * dy)

			if dist < 60 then
				local mass = -1
				local health = -1
				local standing = "?"

				pcall(function()
					mass = ent:GetMass()
				end)

				pcall(function()
					health = ent.soul:GetState("health")
				end)

				-- A body still on the ground is a different case from one that
				-- has got up, and only the second answers the question.
				pcall(function()
					standing = tostring(ent.actor:IsFallen())
				end)

				found[#found + 1] = {
					name = tostring(ent:GetName()),
					mass = mass,
					health = health,
					fallen = standing,
					dist = dist
				}
			end
		end
	end
end

table.sort(found, function(a, b)
	return a.mass > b.mass
end)

say("humans within 60 m, heaviest first. 80 is the engine default.")

local heavy = 0

for i, e in ipairs(found) do
	if e.mass > 100 then
		heavy = heavy + 1
	end

	if i <= 25 then
		say(string.format("  %-28s mass=%-8.0f health=%-6.1f fallen=%-5s %.0fm",
				e.name, e.mass, e.health, e.fallen, e.dist))
	end
end

say(string.format("total=%d  above 100 kg=%d", #found, heavy))
