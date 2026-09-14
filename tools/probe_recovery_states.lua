-- Everything measurable about a victim, from the impact to standing again.
--
-- The mod currently decides "is this body down" from one animation-state
-- string, and that string has a hole in it: measured through an untouched trot
-- knockdown, a victim reads `AnimationControlled` for 1840ms, then
-- `MotionIdle` for 608ms while still mid-fall, then `BlendRagdoll` for 5008ms,
-- then `IdleToMove` as they rise. Anything keyed on that string alone cannot
-- tell the 608ms hole from a person standing about.
--
-- So this records every quantity the actor exposes, per poll, for the whole
-- sequence. The point is to find which of them actually separate "flat on the
-- ground" from "getting up", so a trigger can be tied to the real thing
-- instead of to a timer.
--
-- `GetHeadPos` is the one to watch. The entity origin does not descend when
-- the body does -- measured, z stayed 80.25 to 80.41 prone and standing alike
-- -- because the entity is not what moved. The head is.
--
-- Armed before the impact: it waits for a victim scored after it starts.
--
-- Diagnostic. It is not part of the mod and nothing may come to depend on it.

local PollMs = 100
local ArmMs = 60000
local TraceMs = 16000

local mod = HorseCollisionMod
local armedAt = mod:TimeMs()
local ent, name, started = nil, nil, nil

local function newest()
	local bestId, bestAt = nil, -1

	for id, at in pairs(mod.LastScoredHit or {}) do
		if at > bestAt then
			bestId, bestAt = id, at
		end
	end

	return bestId, bestAt
end

local function entityFor(id)
	for _, candidate in pairs(System.GetEntities() or {}) do
		if tostring(candidate.id) == id and candidate.actor then
			return candidate
		end
	end

	return nil
end

--- Whatever `GetPhysicalStats` holds, named once so the trace can be read.
local function dumpStats()
	local out = {}

	pcall(function()
		for key, value in pairs(ent:GetPhysicalStats() or {}) do
			out[#out + 1] = tostring(key) .. "=" .. tostring(value)
		end
	end)

	System.LogAlways("[TRACE] GetPhysicalStats -> " .. table.concat(out, " "))
end

local function bone(which)
	local pos = nil

	pcall(function()
		pos = ent:GetBonePos(which)
	end)

	if not pos then
		pcall(function()
			pos = ent:GetBonePos(0, which)
		end)
	end

	return pos
end

local function trace()
	local now = mod:TimeMs()
	local state, profile = "?", "?"
	local originZ, headZ, speed, health = -1, -1, -1, -1
	local unconscious, angles = "?", nil
	local pelvisZ, groundZ = -1, -1

	pcall(function()
		state = tostring(ent.actor:GetCurrentAnimationState())
	end)

	pcall(function()
		profile = tostring(ent.actor:GetPhysicalizationProfile())
	end)

	pcall(function()
		originZ = ent:GetWorldPos().z
	end)

	-- The rendered body's height. The entity origin does not follow it down.
	pcall(function()
		headZ = ent.actor:GetHeadPos().z
	end)

	pcall(function()
		local p = bone("Bip01 Pelvis")

		if p then
			pelvisZ = p.z
		end
	end)

	pcall(function()
		local v = ent:GetVelocity()

		speed = math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
	end)

	pcall(function()
		health = ent.soul:GetState("health")
	end)

	pcall(function()
		unconscious = tostring(ent.actor:IsUnconscious())
	end)

	pcall(function()
		angles = ent:GetAngles()
	end)

	pcall(function()
		groundZ = System.GetTerrainElevation(ent:GetWorldPos())
	end)

	System.LogAlways(string.format(
			"[TRACE] t+%05dms state=%s prof=%s originZ=%.2f headZ=%.2f "
			.. "headUp=%.2f pelvisZ=%.2f groundZ=%.2f speed=%.2f "
			.. "pitch=%.2f roll=%.2f hp=%.1f unc=%s",
			now - started, state, profile, originZ, headZ,
			(headZ > 0 and originZ > 0) and (headZ - originZ) or -1,
			pelvisZ, groundZ, speed,
			angles and angles.x or -99, angles and angles.y or -99,
			health, unconscious))

	if now - started < TraceMs then
		Script.SetTimer(PollMs, trace)
	else
		System.LogAlways("[TRACE] " .. name .. " done")
	end
end

local function waitForImpact()
	local id, at = newest()

	if id and at and at >= armedAt then
		ent = entityFor(id)

		if not ent then
			System.LogAlways("[TRACE] victim " .. tostring(id)
					.. " is not reachable")

			return
		end

		name = tostring(ent:GetName())
		started = mod:TimeMs()

		System.LogAlways("[TRACE] === " .. name .. " ===")
		dumpStats()
		trace()

		return
	end

	if mod:TimeMs() - armedAt < ArmMs then
		Script.SetTimer(PollMs, waitForImpact)
	else
		System.LogAlways("[TRACE] armed with no impact, stopping")
	end
end

waitForImpact()
