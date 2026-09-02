-- Names what a guard is holding, and what its class weighs.
--
-- `ItemManager.GetItem(wuid).class` returns a GUID rather than a readable
-- name, so matching class names against words like "halberd" or "spear" finds
-- nothing. Two ways back to a name:
--
--   ItemManager.GetItemUIName(class)   the item's display name
--   Database, pickable_item            the row the class id keys
--
-- Read-only. Edit `WHO` and run through `dev_console.py --file`.

local WHO = { "rat_guard2", "rat_guard4", "rat_guard22", "villageGuard" }

local function describe(wuid)
	local entry = ItemManager.GetItem(wuid)

	if not entry or not entry.class then
		return "?"
	end

	local class = tostring(entry.class)
	local name = "?"

	pcall(function()
		name = tostring(ItemManager.GetItemUIName(entry.class))
	end)

	local weight = "?"

	pcall(function()
		local index = HorseCollisionMod:ItemIndex()
		local row = index.Armor[class]

		if row then
			weight = string.format("%.1f", row[1])
		end
	end)

	return name .. " (w=" .. weight .. ")"
end

for _, who in pairs(WHO) do
	local ent = System.GetEntityByName(who)

	if not ent then
		System.LogAlways("[INV] " .. who .. " not found")
	else
		local drawn = "?"

		pcall(function()
			drawn = tostring(ent.human:IsWeaponDrawn())
		end)

		local hands = {}

		for hand = 0, 1 do
			pcall(function()
				local wuid = ent.human:GetItemInHand(hand)

				if wuid then
					hands[#hands + 1] = "hand" .. hand .. "=" .. describe(wuid)
				end
			end)
		end

		System.LogAlways("[INV] " .. who .. " drawn=" .. drawn
				.. " " .. table.concat(hands, " "))
	end
end
