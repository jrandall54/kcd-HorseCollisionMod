--- Dumps a fleeing victim's brain state the moment he runs.
--
-- Reputation was measured not to drive the flee, so this dumps the context
-- options set on a victim and tries a reset, in game because he unloads
-- before a console round trip lands.
--
--     python tools/dev_console.py --file tools/dev_fleerepair.lua
--
-- Development only. It does not survive a save load.

HorseCollisionModFleeRepair = HorseCollisionModFleeRepair or {}

HorseCollisionModFleeRepair.generation =
		(HorseCollisionModFleeRepair.generation or 0) + 1
HorseCollisionModFleeRepair.stop = false
HorseCollisionModFleeRepair.passes = 0

local INTERVAL = 1000
local RANGE = 60

-- Below this a victim counts as damaged and is worth watching. A healthy
-- villager reads around 0.5, and the one measured fleeing read 0.23.
local DAMAGED = 0.35

-- Meters per second directly away from the player. Walking somewhere is about
-- one; the measured flee was four and a half.
local FLEE_SPEED = 2.5
local CONFIRM = 2

-- Declared in sb_combat.xml, so these are the real names rather than guesses.
local VARS = {
	"currentState", "t_state", "t_state_current", "t_state_next",
	"t_fleeParams", "t_fleeParams_current", "isPlayerHostile", "isHostile",
	"threat", "t_stateSwitchQueued"
}


local generation = HorseCollisionModFleeRepair.generation
local seen = {}

local function sample()
	if HorseCollisionModFleeRepair.stop
			or generation ~= HorseCollisionModFleeRepair.generation then
		System.LogAlways("[FLEE] stopped")

		return
	end

	local origin = nil

	pcall(function()
		origin = player:GetWorldPos()
	end)

	if origin then
		for _, ent in pairs(System.GetEntities() or {}) do
			if ent ~= player and ent.actor and ent.soul and ent.human then
				local p = nil

				pcall(function()
					p = ent:GetWorldPos()
				end)

				if p then
					local d = math.sqrt((p.x - origin.x) ^ 2
							+ (p.y - origin.y) ^ 2)

					if d < RANGE then
						local name = tostring(ent:GetName())
						local rec = seen[name]
								or { d = d, fled = 0, fixed = false }
						local away = (d - rec.d) / (INTERVAL / 1000)
						local rel = 0
						local class = "?"
						local state = "?"

						pcall(function()
							rel = ent.soul:GetRelationship(player.this.id)
						end)

						pcall(function()
							class = tostring(ent.soul:GetSocialClass().Name)
						end)

						pcall(function()
							state = tostring(
									ent.actor:GetCurrentAnimationState())
						end)

						if rel < DAMAGED or rec.fixed then
							System.LogAlways("[FLEE] " .. name
									.. " (" .. class .. ")"
									.. " rel=" .. string.format("%.3f", rel)
									.. " d=" .. string.format("%.1f", d)
									.. " away=" .. string.format("%.1f", away)
									.. " state=" .. state
									.. (rec.fixed and " AFTER-REPAIR" or ""))

							if away > FLEE_SPEED then
								rec.fled = rec.fled + 1
							end

							if rec.fled >= CONFIRM and not rec.fixed then
								rec.fixed = true

								local w = nil
								local out = {}

								pcall(function()
									w = XGenAIModule.GetMyWUID(ent)
								end)

								for _, v in ipairs(VARS) do
									local got = nil

									pcall(function()
										got = XGenAIModule.GetBrainVariable(
												w, v)
									end)

									if got ~= nil then
										out[#out + 1] = v .. "="
												.. tostring(got)
									end
								end

								System.LogAlways("[FLEE] BRAIN " .. name
										.. " hits=" .. #out .. " "
										.. table.concat(out, " "))
							end
						end

						rec.d = d
						seen[name] = rec
					end
				end
			end
		end
	end

	HorseCollisionModFleeRepair.passes =
			HorseCollisionModFleeRepair.passes + 1

	Script.SetTimer(INTERVAL, sample)
end

sample()

System.LogAlways("[FLEE] armed within " .. RANGE .. "m, generation "
		.. generation .. ". Set HorseCollisionModFleeRepair.stop = true to end.")
