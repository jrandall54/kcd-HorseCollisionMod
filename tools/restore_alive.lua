-- Returns nearby actors to the `alive` physicalization profile.
--
-- `SetPhysicalizationProfile("unragdoll")` moves an actor into a profile the
-- engine does not leave on its own. An actor left there keeps its animation
-- state machine running while the body is not driven by it, which reads in
-- game as walking on the spot.
--
-- Read-only for anything already `alive`, so it is safe to run at any time.
-- Run through `dev_console.py --file`.

local player = System.GetEntityByName("dude")

if not player then
	System.LogAlways("[RESTORE] no player entity")
	return
end

local origin = player:GetWorldPos()
local restored, checked = 0, 0

for _, ent in pairs(System.GetEntities() or {}) do
	local ok, pos = pcall(function() return ent:GetWorldPos() end)

	if ok and pos and ent.actor and ent ~= player then
		local dx, dy, dz = pos.x - origin.x, pos.y - origin.y, pos.z - origin.z

		if math.sqrt((dx * dx) + (dy * dy) + (dz * dz)) <= 60 then
			checked = checked + 1

			pcall(function()
				local profile = tostring(ent.actor:GetPhysicalizationProfile())

				if profile ~= "alive" then
					ent.actor:SetPhysicalizationProfile("alive")

					System.LogAlways("[RESTORE] " .. tostring(ent:GetName())
							.. " " .. profile .. " -> "
							.. tostring(ent.actor:GetPhysicalizationProfile()))

					restored = restored + 1
				end
			end)
		end
	end
end

System.LogAlways("[RESTORE] " .. tostring(restored) .. " of "
		.. tostring(checked) .. " actors within 60m returned to alive")
