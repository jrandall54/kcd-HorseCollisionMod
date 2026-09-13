-- Answers one question: does a *dead* entity still play an audio trigger?
--
--     python tools/dev_console.py --file tools/probe_voice_dead.lua --wait 10
--
-- The diary establishes that vanilla's death sounds are the dialog system
-- (proven with `wh_dlg_Enable 0`), and that a dead victim will not take a
-- `dialog:monologRequest` because its subbrain is torn down. That closed off
-- every message-based route and left "let the engine resolve the killing hit"
-- as the only remaining idea, which is a redesign of how the mod kills.
--
-- An FMOD event fired with `ExecuteAudioTrigger` is not a message and does not
-- go near a subbrain. It is played on the entity's audio proxy. So the
-- teardown that silences a monologRequest may not silence this, and that is
-- worth one test before anybody redesigns the kill ordering.
--
-- The nearest living person in front of the rider is killed outright, then the
-- stealth-kill cry is fired on the corpse two seconds later -- long after the
-- brain is gone. Audible means the mod can own its death sounds outright.
--
-- Reversible the usual way: reload the save.

local TRIGGER = "v_stealth_stealthkill_man"
local DELAY_MS = 2000
local SEARCH = 40.0

local function say(msg)
	System.LogAlways("[HorseCollisionMod] VOICEDEAD " .. msg)
end

local id = Sound.GetAudioTriggerID(TRIGGER)

if not id then
	say("trigger=" .. TRIGGER .. " DOES NOT RESOLVE")
	return
end

local playerPos = player:GetWorldPos()
local target, bestDist = nil, SEARCH

for _, ent in pairs(System.GetEntitiesInSphere(playerPos, SEARCH) or {}) do
	local ok = false

	pcall(function()
		if ent == player or not ent.actor or not ent.soul then
			return
		end

		if ent.class ~= "NPC" and ent.class ~= "NPC_Female" then
			return
		end

		local name = ent:GetName()

		-- Henry's dog is skipped here as everywhere else in the mod.
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
			target, bestDist = ent, d
		end
	end
end

if not target then
	say("nobody living within " .. tostring(SEARCH) .. " m")
	return
end

local label = "?"

pcall(function()
	label = tostring(target:GetName())
end)

-- `soul:DealDamage` takes stamina then health. An attacker passed as a third
-- argument does nothing; the diary records that trap costing several rides.
target.soul:DealDamage(0, 9999)

say("killed=" .. label .. " at " .. string.format("%.1f", bestDist)
		.. " m, firing " .. TRIGGER .. " in " .. tostring(DELAY_MS) .. "ms")

Script.SetTimer(DELAY_MS, function()
	local dead = "?"

	pcall(function()
		dead = tostring(target:IsDead())
	end)

	local played = false

	pcall(function()
		target:ExecuteAudioTrigger(id, target:GetDefaultAuxAudioProxyID())
		played = true
	end)

	say("fired=" .. tostring(played) .. " isDead=" .. dead
			.. " target=" .. label)
end)
