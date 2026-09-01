-- Reports the live state of nearby actors, to tell a mod-driven animation
-- apart from a vanilla one.
--
-- Read-only. Nothing here starts, stops or cancels anything; it only reads
-- state the engine already holds and prints it. Run through
-- `dev_console.py --file`.
--
-- What each field answers:
--
-- * `anim` is the actor's animation state. `AnimationControlled` is the
--   fragment this mod's reactions play through, and is the one value that
--   would indicate the mod is holding the body. `BlendRagdoll` means physics
--   still owns it. Anything else is vanilla driving the actor.
-- * `hcm` is whether the mod currently has that entity in its own tables:
--   `RecentHits` holds a reaction cooldown, and a victim awaiting recovery is
--   named there. An actor the mod never touched appears as `no`.
-- * `cure` is whether the auto-cure suppression is still applied, which the
--   mod sets for thirty seconds after an impact.

local player = System.GetEntityByName("dude")

if not player then
	System.LogAlways("[PROBE] no player entity")
	return
end

local origin = player:GetWorldPos()
local found = 0

for _, ent in pairs(System.GetEntities() or {}) do
	local name = ent:GetName() or "?"
	local ok, pos = pcall(function() return ent:GetWorldPos() end)

	if ok and pos and ent.actor and ent ~= player then
		local dx = pos.x - origin.x
		local dy = pos.y - origin.y
		local dz = pos.z - origin.z
		local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

		if dist <= 30 then
			-- The same call the mod polls in WhenReactionEnds and
			-- WhenRagdollResolves, so the value read here is the value the
			-- mod would act on.
			local anim = "?"
			pcall(function()
				anim = tostring(ent.actor:GetCurrentAnimationState())
			end)

			local hit = HorseCollisionMod
					and HorseCollisionMod.RecentHits
					and HorseCollisionMod.RecentHits[tostring(ent.id)]

			-- Printed on the scale the mod records. `GetState("health")`
			-- already returns 0 to 100, the same scale the `ImpactCost` lines
			-- carry, so it is formatted rather than converted.
			local health = "?"
			pcall(function()
				health = string.format("%.1f", ent.soul:GetState("health"))
			end)

			System.LogAlways("[PROBE] " .. name
					.. " dist=" .. string.format("%.1f", dist)
					.. " anim=" .. anim
					.. " hcm=" .. (hit and "yes" or "no")
					.. " health=" .. health)

			found = found + 1
		end
	end
end

System.LogAlways("[PROBE] " .. tostring(found) .. " actors within 30m")
