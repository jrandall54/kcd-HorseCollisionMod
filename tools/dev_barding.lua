--- Puts barding on the player's horse, for testing `BardingImpulseScale`.
--
-- The barding multiplier reads the horse's own inventory through `ArmorOf`,
-- and an unbarded horse carries only its tack, so the multiplier sits at 1.00
-- and the feature cannot be judged. Nothing in the early game hands over
-- barding, and buying it needs a trader and money.
--
-- The item ids are from `Libs/Tables/item/item.xml` inside Tables.pak. Created
-- and added the way the cheat mod does it:
--
--     ItemManager.CreateItem(itemId, health, count)
--     inventory:AddItem(item)
--     actor:EquipInventoryItem(item)
--
-- Run with: python tools/dev_console.py --file tools/dev_barding.lua

local BARDING = {
	{ name = "horse_armor_head_neck_004", id = "4fc0012d-c8dd-cb42-28a6-f6acb6f64b83" },
	{ name = "horse_trappings_002", id = "4b609a17-9266-0e3e-75dc-d4d709533dba" },
	{ name = "horse_trappings_001", id = "46ee8c8f-2c9a-3002-a31e-8623e2da529d" }
}

local horse = nil

pcall(function()
	horse = XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())
end)

if not horse then
	System.LogAlways("[BARDING] no player horse, run dev_horse.lua first")
	return
end

local function report(label)
	local armor = HorseCollisionMod:ArmorOf(horse)
	local coverage = HorseCollisionMod:BardingCoverage(horse)

	System.LogAlways("[BARDING] " .. label
			.. " pieces=" .. tostring(armor and armor.pieces)
			.. " weight=" .. string.format("%.2f", (armor and armor.weight) or 0)
			.. " smashDef=" .. string.format("%.2f", (armor and armor.smashDef) or 0)
			.. " coverage=" .. string.format("%.2f", coverage))
end

report("before, " .. tostring(horse:GetName()))

for _, entry in ipairs(BARDING) do
	local item = nil

	local made = pcall(function()
		item = ItemManager.CreateItem(entry.id, 100, 1)
	end)

	local added, equipped = false, false

	if item then
		added = pcall(function()
			horse.inventory:AddItem(item)
		end)

		equipped = pcall(function()
			horse.actor:EquipInventoryItem(item)
		end)
	end

	System.LogAlways("[BARDING] " .. entry.name
			.. " created=" .. tostring(made)
			.. " added=" .. tostring(added)
			.. " equipped=" .. tostring(equipped))
end

report("after")
