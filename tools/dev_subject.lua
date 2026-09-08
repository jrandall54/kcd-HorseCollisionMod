--- Puts a test subject in front of the horse.
--
-- Riding around a village hitting whoever is nearby is not a test. Armor,
-- health, facing, whether the victim was already moving and whether they were
-- hit a moment ago all vary at once, and each of them changes the result. This
-- fixes them: a fresh subject, a known distance, standing still, facing the
-- rider, at full health.
--
-- Run with:
--
--   python tools/dev_console.py --file tools/dev_subject.lua
--
-- Edit `pick` below. Run it again for a new subject; the previous ones are
-- removed first, so they do not pile up.
--
-- ### Why a spawned NPC and not a relocated one
--
-- A spawned NPC does not move. The Cheat mod records this as a fault of its
-- spawn command, that the results "just stand around", and for a test subject
-- it is the entire point: nothing has to hold it in place, because it has
-- nowhere to be.
--
-- Moving an NPC that already exists does not work: it keeps its routine and
-- walks off, and `AIMovementAbility` is no lever on that, because seventy-five of
-- the hundred-odd NPCs around a village already read 0/0/0 for walk, run and
-- sprint and move about perfectly well. That field is descriptive, and the
-- Cheat mod only ever reads it.
--
-- ### Why a guard soul
--
-- The soul decides whether there is anything to see. A villager soul spawns an
-- entity the town reacts to but nothing renders, and with no faction it is read
-- as a bandit. A bandit soul renders and then fights, which ends with the
-- guards killing it. A guard soul renders, stands still, takes an impact and
-- gets back up, which is the whole requirement.
--
-- That the Cheat mod offers only bandit, cuman and guard for humans looks
-- deliberate rather than arbitrary.

local pick = {
	-- Which soul to spawn. "guard" renders and does not fight. "bandit" and
	-- "cuman" also render; both attack and are attacked.
	soul = "guard",

	-- Meters in front of the horse.
	--
	-- This has to suit the tier being tested, and getting it wrong silently
	-- tests the wrong thing: a subject at 6 m cannot be reached at more than a
	-- trot, so a run meant to measure a gallop scores as a trot and the gated,
	-- animation-driven tier answers instead. Check the tier in the log rather
	-- than trusting the intent.
	distance = 25.0,

	count = 1,

	-- Spread when more than one is asked for, so they do not spawn inside each
	-- other.
	spacing = 1.5,

	-- Put the subject on the ground straight away, for testing what an impact
	-- does to someone already down.
	--
	-- `actor:Fall` is what the mod's own trot and gallop tiers use, so the
	-- state produced is the state a real impact leaves. A raw `RagDollize` is
	-- not the same thing: it hands the body to physics without the reaction
	-- around it and leaves the subject T-posed.
	--
	-- A subject is only down for about seven seconds, which the ride over
	-- spends. For testing the whole window from flat to back on routine, leave
	-- this off and let the first pass do the knocking down.
	knockDown = false,
	knockDownDelayMs = 400,

	-- Make the subject unkillable, so one of them serves for a whole session
	-- of repeated impacts instead of dying on the second pass and needing the
	-- test set up again.
	--
	-- This is the Cheat mod's immortality in full, which is four things and not
	-- one. The ward buff alone leaves a subject that still dies: the health
	-- pool carries the weight, and 1000 is the figure the Cheat mod uses.
	--
	-- Even that is not enough on an NPC, whose pool clamps at 100 and whose cap
	-- has no writable path: `SetMaxHealth`, `SetStatLevel` and `SetDerivedStat`
	-- are all absent from a soul. The mod's own damage exemption in `Health.lua`
	-- is what actually keeps a subject alive; this block only sets the state a
	-- run should start from.
	--
	-- Zeroing the mod's damage settings would look similar and is worse: those
	-- are what is under test, and a run measured with them at zero measures
	-- nothing.
	immortal = true,
	immortalBuff = "a218af80-b2a5-11ed-afa1-0242ac120002",
	injuryBuff = "46683e3b-e261-412f-b402-99ee17dda62a",
	immortalHealth = 1000
}

local anchor = player
local mounted = false

pcall(function()
	if player.human:IsMounted() then
		local horse = XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())

		if horse then
			anchor = horse
			mounted = true
		end
	end
end)

local origin = anchor:GetWorldPos()
local dir = anchor:GetDirectionVector(1)
local flat = math.sqrt((dir.x * dir.x) + (dir.y * dir.y))

if flat <= 0 then
	System.LogAlways("[SUBJECT] no facing to place against")
	return
end

local forward = { x = dir.x / flat, y = dir.y / flat }
local right = { x = forward.y, y = -forward.x }

-- Clear the last run's subjects first. Without this a session leaves a row of
-- bodies across the map, and the detection loop has more to look at every tick.
HorseCollisionMod = HorseCollisionMod or {}

local removed = 0

if HorseCollisionMod.TestSubjects then
	for _, ent in pairs(HorseCollisionMod.TestSubjects) do
		if pcall(function() System.RemoveEntity(ent.id) end) then
			removed = removed + 1
		end
	end
end

HorseCollisionMod.TestSubjects = {}

local souls = {}

pcall(function()
	local tableName = "v_soul_character_data"

	Database.LoadTable(tableName)

	local info = Database.GetTableInfo(tableName)
	local want = string.upper(pick.soul)

	for i = 0, info.LineCount - 1 do
		local row = Database.GetTableLine(tableName, i)

		if row and row.soul_id then
			local named = string.upper(tostring(row.name_string_id or ""))

			if string.find(named, want, 1, true) then
				souls[#souls + 1] = row.soul_id
			end
		end
	end
end)

if #souls == 0 then
	System.LogAlways("[SUBJECT] no soul matched '" .. tostring(pick.soul) .. "'")

	return
end

-- Ground under a point. The anchor's height is the horse's back when mounted,
-- and a subject placed at that height drops in from above.
local function groundAt(x, y, from)
	local z = from
	local hits = {}

	pcall(function()
		local found = Physics.RayWorldIntersection(
				{ x = x, y = y, z = from + 3.0 }, { x = 0, y = 0, z = -12.0 },
				1, ent_terrain + ent_static, nil, nil, hits)

		if found and found > 0 and hits[1] and hits[1].pos then
			z = hits[1].pos.z
		end
	end)

	return z
end

local made = 0

for i = 1, pick.count do
	-- Centered on the aim line: one subject is dead ahead, two straddle it.
	local offset = (i - ((pick.count + 1) / 2)) * pick.spacing
	local x = origin.x + (forward.x * pick.distance) + (right.x * offset)
	local y = origin.y + (forward.y * pick.distance) + (right.y * offset)
	local z = groundAt(x, y, origin.z)

	local ok, err = pcall(function()
		local ent = System.SpawnEntity({
			class = "NPC",
			name = "hcm_subject_" .. tostring(i) .. "_"
					.. tostring(math.floor(System.GetCurrTime() * 100)),
			position = { x = x, y = y, z = z },

			-- Facing the rider, so the front of the subject is what gets hit
			-- and the same body zones are struck every run.
			orientation = { x = -forward.x, y = -forward.y, z = 0 },
			properties = { sharedSoulGuid = souls[((i - 1) % #souls) + 1] }
		})

		if not ent then
			error("SpawnEntity returned nothing")
		end

		HorseCollisionMod.TestSubjects[#HorseCollisionMod.TestSubjects + 1] = ent
		made = made + 1

		local warded = false

		if pick.immortal then
			warded = pcall(function()
				ent.soul:AddBuff(pick.immortalBuff)
				ent.soul:AddBuff(pick.injuryBuff)

				for limb = 1, 6 do
					ent.soul:HealBleeding(1, limb)
				end

				ent.soul:SetState("health", pick.immortalHealth)
				ent.soul:SetState("stamina", pick.immortalHealth)

				-- The engine offers no way to raise an NPC's health cap, so
				-- the mod is told to charge this one nothing instead.
				HorseCollisionMod.ImmortalSubjects = HorseCollisionMod.ImmortalSubjects or {}
				HorseCollisionMod.ImmortalSubjects[tostring(ent.id)] = true
			end)
		end

		System.LogAlways(string.format(
				"[SUBJECT] %s at %.1f m, z=%.2f, immortal=%s",
				tostring(ent:GetName()), pick.distance, z, tostring(warded)))

		if pick.knockDown then
			Script.SetTimer(pick.knockDownDelayMs, function()
				local downed = pcall(function()
					ent.actor:Fall({ x = 0, y = 0, z = 0 }, true)
				end)

				System.LogAlways("[SUBJECT] knocked down ok="
						.. tostring(downed))
			end)
		end
	end)

	if not ok then
		System.LogAlways("[SUBJECT] failed: " .. tostring(err))
	end
end

System.LogAlways(string.format(
		"[SUBJECT] spawned %d of %d as '%s', removed %d, mounted=%s",
		made, pick.count, tostring(pick.soul), removed, tostring(mounted)))
