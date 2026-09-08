-- Puts a pinned test victim directly in front of the rider.
--
--     python tools/dev_console.py --file tools/dev_target.lua
--
-- Run again to reposition. An existing NPC is moved rather than one spawned:
-- a spawned entity has no soul, armour or AI, so it would exercise none of the
-- armour scaling, damage, reactions or retaliation a real test needs.
--
-- Pinned with `AI.SetIgnorant`, the engine's switch for an actor that should
-- stop acting. Henry's dog is skipped, as everywhere else.

local DISTANCE = 4.0
local SEARCH = 40.0

local playerPos = player:GetWorldPos()
local forward = player:GetDirectionVector(1)
local flat = math.sqrt((forward.x * forward.x) + (forward.y * forward.y))

if flat <= 0 then
	System.LogAlways("[HorseCollisionMod] TARGET no facing")
	return
end

local fx, fy = forward.x / flat, forward.y / flat
local best, bestDist = nil, SEARCH

for _, ent in pairs(System.GetEntitiesInSphere(playerPos, SEARCH) or {}) do
	local ok = false

	pcall(function()
		if ent == player or not ent.actor then
			return
		end

		if ent.class ~= "NPC" and ent.class ~= "NPC_Female" then
			return
		end

		local name = ent:GetName()

		if name and string.find(name, "dogCompanion") then
			return
		end

		if ent.IsDead and ent:IsDead() then
			return
		end

		ok = true
	end)

	if ok then
		local p = ent:GetWorldPos()
		local dx, dy = p.x - playerPos.x, p.y - playerPos.y
		local d = math.sqrt((dx * dx) + (dy * dy))

		if d < bestDist then
			best, bestDist = ent, d
		end
	end
end

if not best then
	System.LogAlways("[HorseCollisionMod] TARGET nobody human within "
			.. tostring(SEARCH) .. " m")
	return
end

local name = "?"

pcall(function()
	name = tostring(best:GetName())
end)

local to = {
	x = playerPos.x + (fx * DISTANCE),
	y = playerPos.y + (fy * DISTANCE),
	z = playerPos.z
}

-- Mounted, the rider's position is up on the horse, so the ground under the
-- spot is found rather than assumed.
local found = {}
local hits = Physics.RayWorldIntersection(
		{ x = to.x, y = to.y, z = to.z + 3.0 },
		{ x = 0, y = 0, z = -12.0 }, 1,
		ent_terrain + ent_static, player.id, nil, found)

if (hits or 0) > 0 and found[1] and found[1].pos then
	to.z = found[1].pos.z
end

local placed = pcall(function()
	best:SetWorldPos(to)

	-- Facing the rider, so a collision lands front on.
	if best.SetDirectionVector then
		best:SetDirectionVector({ x = -fx, y = -fy, z = 0 })
	end
end)

-- Pinned, or they walk off before anything can be lined up.
--
-- `SetMovementRestriction` holds the player but not an AI, which keeps walking
-- its routine regardless. `AI.SetIgnorant` is the engine's own switch for an
-- actor that should stop acting, so it is the one that works here.
-- `ai_IgnorePlayer` keeps the rest of the town from reacting to what follows.
local pinned = pcall(function()
	AI.SetIgnorant(best.id, 1)
end)

pcall(function()
	best.actor:SetMovementRestriction(true, true)
end)

pcall(function()
	System.SetCVar("ai_IgnorePlayer", 1)
end)

System.LogAlways("[HorseCollisionMod] TARGET " .. name .. " moved from "
		.. string.format("%.1f", bestDist) .. " m to "
		.. tostring(DISTANCE) .. " m ahead, placed=" .. tostring(placed)
		.. " pinned=" .. tostring(pinned))
