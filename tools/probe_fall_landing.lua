-- When each fall clip actually puts a victim on the ground.
--
-- `FALL_SETTLE_AT` in tools/build_adb.py decides when Mannequin hands a
-- falling victim to physics, and its figures were derived as a fraction of
-- clip length -- 0.68 for male, 0.50 for female -- because nothing could
-- measure when the body reached the ground. Measured, male left lands at
-- 1.65s against a handover set to 2.80s, so the clip runs for over a second
-- on a body that is already flat and motionless.
--
-- Head height is what makes it measurable. `GetHeadPos().z` minus the entity
-- origin reads about 1.55 standing and about 0.15 flat, so landing is the
-- moment it stops falling.
--
-- Re-arms itself after every impact, so a run of trots from different angles
-- can be measured back to back without firing this again. Each line pairs
-- with the `Reaction action=` line logged just above it, which carries the
-- direction and the gender.
--
-- Diagnostic. It is not part of the mod and nothing may come to depend on it.

local PollMs = 50
local SettleMs = 400
local GiveUpMs = 9000
local RunMs = 300000

local mod = HorseCollisionMod
local armedAt = mod:TimeMs()
local lastSeen = nil

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

local function headUp(ent)
	local head, origin = nil, nil

	pcall(function()
		head = ent.actor:GetHeadPos().z
	end)

	pcall(function()
		origin = ent:GetWorldPos().z
	end)

	if not head or not origin then
		return nil
	end

	return head - origin
end

local watch, arm

--- Follows one victim down and reports the moment they stop descending.
function watch(ent, name, startedAt, standing)
	local lowest, lowestAt = nil, nil

	local function poll()
		local now = mod:TimeMs()
		local up = headUp(ent)

		if up then
			if not lowest or up < lowest then
				lowest, lowestAt = up, now
			end

			-- Landed once the head has stopped finding a new low for long
			-- enough that it is resting rather than still on its way down.
			if lowestAt and (now - lowestAt) >= SettleMs then
				System.LogAlways(string.format(
						"[LANDING] %s landedAt=%dms headUp=%.2f standing=%.2f",
						name, lowestAt - startedAt, lowest, standing))

				arm()

				return
			end
		end

		if now - startedAt < GiveUpMs then
			Script.SetTimer(PollMs, poll)
		else
			System.LogAlways("[LANDING] " .. name .. " never settled")
			arm()
		end
	end

	poll()
end

function arm()
	local function poll()
		local id, at = newest()

		if id and at and at ~= lastSeen and at >= armedAt then
			lastSeen = at

			local ent = entityFor(id)

			if ent then
				local standing = headUp(ent) or -1

				watch(ent, tostring(ent:GetName()), mod:TimeMs(), standing)

				return
			end
		end

		if mod:TimeMs() - armedAt < RunMs then
			Script.SetTimer(PollMs, poll)
		else
			System.LogAlways("[LANDING] finished")
		end
	end

	Script.SetTimer(PollMs, poll)
end

System.LogAlways("[LANDING] armed, trot people from different angles")
arm()
