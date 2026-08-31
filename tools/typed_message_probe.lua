-- Retries the messages this project recorded as inert, sent as typed tables.
--
-- Every message tried so far went through `XGenAIModule.SendMessageToEntity`,
-- which takes its values as text. A message type that declares members gets
-- them unset that way, so it is delivered and discarded with nothing for the
-- receiving node to match on. `Libs/AI/TypeDefinitions.xml` declares what each
-- one carries, and `Utils.makeTable` builds it.
--
-- Run against an NPC parked in MotionIdle after a collision. Each candidate is
-- sent on its own and the victim is measured before the next, so whichever one
-- moves them is identified rather than inferred from a batch.
--
-- Usage, from the repository root:
--   python tools/dev_console.py --file tools/typed_message_probe.lua
--
-- Or set HCM_PROBE_TARGET to a name before running to skip the search.

HCMProbe = HCMProbe or {}

HCMProbe.Candidates = {
	{
		name = "daycycle:restartRequest",
		build = function(entity, wuid)
			return {
				reason = enum_daycycleHaltReason.interrupt,
				speed = enum_daycycleHaltSpeed.instant
			}
		end
	},
	{
		name = "daycycle:haltContext",
		build = function(entity, wuid)
			return {
				reason = enum_daycycleHaltReason.interrupt,
				speed = enum_daycycleHaltSpeed.instant
			}
		end
	},
	{
		name = "daycycle:interrupt",
		build = function(entity, wuid)
			return {
				behaviorSource = wuid,
				behaviorName = "",
				includeXml = "",
				includeTree = "",
				daycycleHaltSpeed = enum_daycycleHaltSpeed.instant,
				immediateActivityBeingSwitchedIntoHandle = ""
			}
		end
	},
	{
		name = "daycycle:behavior:progress",
		build = function(entity, wuid)
			return { progress = false, behavior = "" }
		end
	}
}

--- Reads an actor's animation state, or "?" when it cannot be read.
function HCMProbe.State(entity)
	local state = "?"

	pcall(function()
		state = tostring(entity.actor:GetCurrentAnimationState())
	end)

	return state
end

--- Horizontal distance between two positions.
function HCMProbe.Travel(from, to)
	local dx = to.x - from.x
	local dy = to.y - from.y

	return math.sqrt((dx * dx) + (dy * dy))
end

--- Finds an NPC parked in an idle state, or returns the configured target.
function HCMProbe.FindTarget(names)
	for _, name in ipairs(names) do
		local entity = System.GetEntityByName(name)

		if entity then
			local state = HCMProbe.State(entity)

			System.LogAlways("[PROBE] " .. name .. " = " .. state)

			if state == "MotionIdle" or state == "MotionIdleVARdefault" then
				return entity, name
			end
		end
	end

	return nil, nil
end

--- Sends one candidate and reports what the victim did over the next window.
--
-- Each result is logged with the message name, so a run reads as a table of
-- which messages moved the victim and which did not.
function HCMProbe.Try(entity, name, index, waitMs)
	local candidate = HCMProbe.Candidates[index]

	if not candidate then
		System.LogAlways("[PROBE] finished")

		return
	end

	local before = entity:GetWorldPos()
	local wuid = nil

	pcall(function()
		wuid = XGenAIModule.GetMyWUID(entity)
	end)

	local target = entity.id

	if entity.this and entity.this.id then
		target = entity.this.id
	end

	local ok, err = pcall(function()
		local message = Utils.makeTable(candidate.name,
				candidate.build(entity, wuid))

		XGenAIModule.SendMessageToEntityData(target, candidate.name, message)
	end)

	System.LogAlways("[PROBE] sent " .. candidate.name
			.. " built=" .. tostring(ok) .. " err=" .. tostring(err))

	Script.SetTimer(waitMs, function()
		local after = entity:GetWorldPos()

		System.LogAlways("[PROBE] " .. candidate.name
				.. " -> travel="
				.. string.format("%.2f", HCMProbe.Travel(before, after))
				.. " state=" .. HCMProbe.State(entity))

		HCMProbe.Try(entity, name, index + 1, waitMs)
	end)
end

--- Runs the whole battery against the first parked NPC found.
function HCMProbe.Run()
	local names = {
		"rat_refugee_kunes", "rat_refugee_vojcek", "rat_refugee_ales",
		"rat_refugee_lokna", "rat_refugee_beranMr",
		"rat_merchant_shop1", "rat_merchant_shop2", "rat_merchant_shop3",
		"rat_innkeeper1"
	}

	local entity, name = HCMProbe.FindTarget(names)

	if not entity then
		System.LogAlways("[PROBE] nothing parked; ride into one and rerun")

		return
	end

	System.LogAlways("[PROBE] target " .. name
			.. " state=" .. HCMProbe.State(entity))

	HCMProbe.Try(entity, name, 1, 9000)
end

HCMProbe.Run()
