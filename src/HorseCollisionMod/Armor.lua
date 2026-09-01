--- Armor: what a collision victim is wearing, and what it changes.
--
-- Weight is read from the entity's inventory and turned into two multipliers,
-- one for the impulse an impact carries and one for the stamina it costs the
-- horse. Both run through a single curve so the two settings that shape them
-- behave the same way.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. The curve reads `Config`, so
-- the settings it depends on live in the entry point and exist before this
-- file runs.
--
-- @module HorseCollisionMod.Armor
-- @author jrandall54
-- @release 4.3.9

--- What an entity is wearing, summed from its inventory.
--
-- Nothing in the ScriptBind surface reports which items are equipped, and
-- nothing reports an item's weight. Neither gap matters for a collision
-- target: an NPC carries only what it wears plus a few trinkets, and the
-- weights are generated into `HorseCollisionMod_ItemData.lua` from the game's
-- own tables. Filtering an inventory to the classes in that table is therefore
-- equivalent to reading the equipped set.
--
-- The player is the exception, carrying whatever has been picked up, but the
-- player is never the victim of an impact.
--
-- Saddles, bridles, horseshoes and spurs are filed as armor. `tack` selects
-- between the two: false for what a person is wearing, true for a horse's own
-- gear, which is what Phase 3 barding needs from the same call.
--
-- @tparam table entity any entity with an inventory
-- @tparam[opt] boolean tack true to sum horse gear instead of worn armor
-- @treturn table weight, smashDef, pieces, heaviest and heaviestType
function HorseCollisionMod:ArmorOf(entity, tack)
	local total = {
		weight = 0,
		smashDef = 0,
		pieces = 0,
		heaviest = 0,
		heaviestType = 0,
	}

	local data = rawget(_G, "HorseCollisionModItemData")

	if not data or not entity or not entity.inventory then
		return total
	end

	local ok, items = pcall(function()
		return entity.inventory:GetInventoryTable()
	end)

	if not ok or type(items) ~= "table" then
		return total
	end

	for _, wuid in pairs(items) do
		-- Per item rather than around the loop. An entity streaming out
		-- mid-sum would otherwise discard the pieces already counted.
		pcall(function()
			local item = ItemManager.GetItem(wuid)

			if not item or not item.class then
				return
			end

			local row = data.Armor[item.class]

			if not row then
				return
			end

			local isTack = data.TackTypes[row[3]] == true

			if isTack ~= (tack == true) then
				return
			end

			total.weight = total.weight + row[1]
			total.smashDef = total.smashDef + row[2]
			total.pieces = total.pieces + 1

			if row[1] > total.heaviest then
				total.heaviest = row[1]
				total.heaviestType = row[3]
			end
		end)
	end

	return total
end


--- An armor total as a log fragment.
--
-- @tparam table total a table from `ArmorOf`
-- @treturn string the totals, and the heaviest piece's type by name
function HorseCollisionMod:DescribeArmor(total)
	local data = rawget(_G, "HorseCollisionModItemData")
	local kind = "none"

	if data and data.TypeNames[total.heaviestType] then
		kind = data.TypeNames[total.heaviestType]
	end

	return "pieces=" .. tostring(total.pieces)
			.. " weight=" .. string.format("%.1f", total.weight)
			.. " smashDef=" .. string.format("%.2f", total.smashDef)
			.. " heaviest=" .. kind
end


--- How much a target's armor changes the impact it takes.
--
-- One curve serves both halves. `weight` is the target's armor weight and
-- `reference` the weight that changes nothing, so the ratio between them is
-- the whole signal; `exponent` sets how sharply it bites and 0 switches the
-- scaling off entirely.
--
-- Armor makes a target harder to throw and more tiring to hit, so the impulse
-- takes the reciprocal of the ratio and the stamina cost takes it directly.
-- Both are clamped, because the curve has no natural floor or ceiling and an
-- unclamped extreme reads in game as a target that cannot be moved at all, or
-- one that flies out of sight.
--
-- @tparam number weight the target's armor weight
-- @tparam number reference the weight that produces 1.0
-- @tparam number exponent how strongly weight matters, 0 to disable
-- @tparam boolean invert true for the impulse, false for the stamina cost
-- @tparam number low the smallest multiplier allowed
-- @tparam number high the largest
-- @treturn number the multiplier
function HorseCollisionMod:ArmorCurve(weight, reference, exponent, invert, low, high)
	if exponent == 0 or reference <= 0 then
		return 1.0
	end

	-- A target wearing nothing at all still has a body. Without a floor the
	-- ratio goes to infinity and the clamp becomes the only thing deciding
	-- the result, which hides the setting rather than applying it.
	local w = weight

	if w < 0.5 then
		w = 0.5
	end

	local ratio = w / reference

	if invert then
		ratio = reference / w
	end

	local scale = math.pow(ratio, exponent)

	if scale < low then
		return low
	end

	if scale > high then
		return high
	end

	return scale
end


--- The impulse multiplier for a target's armor.
--
-- @tparam table armor a table from `ArmorOf`
-- @treturn number a multiplier on the tier's impulse scale
function HorseCollisionMod:ArmorImpulseScale(armor)
	local cfg = self.Config

	return self:ArmorCurve(armor.weight, cfg.ArmorReferenceWeight,
			cfg.ArmorImpulseExponent, true,
			cfg.MinArmorImpulse, cfg.MaxArmorImpulse)
end


--- The stamina multiplier for a target's armor.
--
-- Composes with the combat multiplier already applied, and is the same shape
-- the Phase 3 Horsemanship multiplier will take, so the three multiply rather
-- than each becoming its own rule.
--
-- @tparam table armor a table from `ArmorOf`
-- @treturn number a multiplier on the tier's stamina cost
function HorseCollisionMod:ArmorStaminaScale(armor)
	local cfg = self.Config

	return self:ArmorCurve(armor.weight, cfg.ArmorReferenceWeight,
			cfg.ArmorStaminaExponent, false,
			cfg.MinArmorStamina, cfg.MaxArmorStamina)
end
