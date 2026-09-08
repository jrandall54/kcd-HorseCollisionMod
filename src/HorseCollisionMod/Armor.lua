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
-- @release 4.19.3
-- The `armor_type_id` values worn by a horse rather than a person.
--
-- A sum over a person has to exclude them and a sum over a horse has to be
-- only them, because a saddle sits in the horse's inventory and a rider's
-- armor does not.
-- Only the saddle and the horseshoes. `armor_type_id` 12 is named
-- `horse_bridle` in `armor_type.xml` and looks like tack, but the game files
-- every `horse_armor_head_neck_*` piece under it, and those carry a
-- `smash_def` of 0.80 to 1.40 against the trappings' 0.06. Excluding the id
-- threw away all the real barding and left only cloth, which is why the
-- barding multiplier had to be cranked before it did anything. Genuine
-- bridles share the id and carry 0.00, so counting it costs nothing.
HorseCollisionMod.TackTypes = {
	[10] = true,
	[11] = true
}

-- `armor_type_id` as a readable name, for telemetry only. Nothing branches on
-- these; they exist so a log line names the heaviest piece.
HorseCollisionMod.ArmorTypeNames = {
	[1] = "default cloth",
	[2] = "light leather",
	[3] = "heavy leather",
	[4] = "chain",
	[5] = "plate",
	[6] = "decorated",
	[7] = "cloth",
	[8] = "spur",
	[9] = "shoe",
	[10] = "horse saddle",
	[11] = "horse shoe",
	[12] = "horse bridle"
}

--- Every armor class the game defines, with its weight and protection.
--
-- `Database` exposes the tables the game ships. `pickable_item` carries every
-- item's weight, and `armor` carries `smash_def` and `armor_type_id` for the
-- subset that is armor. They join on `item_id`, which is the class an item
-- reports through `ItemManager.GetItem`.
--
-- Membership of `armor` is what makes a carried item count. `pickable_item`
-- holds food, tools and coin as well, and summing all of it would weigh a
-- target by their shopping rather than their protection.
--
-- This replaces a 50 KB table generated from the game's paks at build time and
-- shipped with the mod. The join is the same one that generator performed, done
-- against the live tables instead, so nothing about the resulting weights
-- changed and the download no longer carries them.
--
-- Built once and cached. The tables do not change while the game runs, and the
-- join walks a few thousand rows.
--
-- @treturn table `Armor`, keyed by class, holding weight, smashDef and type.
--   Empty when the tables cannot be read, which leaves every target unarmored
--   rather than failing the impact.
function HorseCollisionMod:ItemIndex()
	if self.ItemIndexCache then
		return self.ItemIndexCache
	end

	local db = rawget(_G, "Database")

	if type(db) ~= "table" then
		self:Log("Database is unavailable, so armor scaling is off")
		self.ItemIndexCache = { Armor = {} }

		return self.ItemIndexCache
	end

	local index = { Armor = {} }

	local ok, err = pcall(function()
		-- Column order is not promised, so each table's columns are resolved
		-- by name rather than assumed to sit at a fixed index.
		local function columns(name)
			local info = db.GetTableInfo(name)
			local map = {}

			for c = 0, info.ColumnCount - 1 do
				map[db.GetColumnInfo(name, c).Name] = c
			end

			return map
		end

		local pc = columns("pickable_item")
		local ids = db.GetTableColumnData("pickable_item", pc["item_id"])
		local weights = db.GetTableColumnData("pickable_item", pc["weight"])
		local weight = {}

		for i = 1, #ids do
			weight[tostring(ids[i])] = weights[i]
		end

		local ac = columns("armor")
		local aids = db.GetTableColumnData("armor", ac["item_id"])
		local smash = db.GetTableColumnData("armor", ac["smash_def"])
		local kinds = db.GetTableColumnData("armor", ac["armor_type_id"])

		for i = 1, #aids do
			local class = tostring(aids[i])

			index.Armor[class] = {
				weight[class] or 0,
				smash[i] or 0,
				kinds[i]
			}
		end
	end)

	local count = 0

	for _ in pairs(index.Armor) do
		count = count + 1
	end

	self:Log("ItemIndex built ok=" .. tostring(ok)
			.. " armorPieces=" .. tostring(count)
			.. " err=" .. tostring(err))

	self.ItemIndexCache = index

	return index
end

--- What an entity is wearing, summed from its inventory.
--
-- Nothing in the ScriptBind surface reports which items are equipped, and
-- nothing reports an item's weight directly. Neither gap matters for a
-- collision target: an NPC carries only what it wears plus a few trinkets, and
-- `ItemIndex` above supplies the class-to-weight join from the game's own
-- tables. Filtering an inventory to the classes the `armor` table contains is
-- therefore equivalent to reading the equipped set.
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

	local data = self:ItemIndex()

	if not entity or not entity.inventory then
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

			local isTack = self.TackTypes[row[3]] == true

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
	local kind = self.ArmorTypeNames[total.heaviestType] or "none"

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

--- How heavily barded the horse is, from nothing to a full set.
--
-- Barding is the horse's armor, and it is distinct from its tack. The game
-- files it in two places: the body trappings sit under `armor_type_id` 1 with
-- a `smash_def` of 0.05 to 0.06, and the head and neck piece, which is the
-- only substantial protection a horse can wear, runs 0.80 to 1.40.
--
-- Read from `smash_def` rather than from weight, because that is the figure
-- that separates a cloth caparison from a plated head, and it is the same
-- figure the victim's side of the collision is scored on.
--
-- Returned as a coverage fraction from 0 to 1 rather than as a multiplier,
-- because barding's three effects are flat additions and reductions rather
-- than a chain of multipliers. A multiplier on the impulse compounds with the
-- victim's own armor scale, so the same barding moves an unarmored villager
-- far more than an armored one, which is backwards for a property of the
-- horse. A flat addition contributes the same push whoever is hit.
--
-- Nothing about the rider enters this. Barding is what the horse is wearing,
-- so it does not scale with Horsemanship and must not be made to.
--
-- @tparam table horseEnt the player's horse entity
-- @treturn number coverage from 0 on a bare horse to 1 on a full set
function HorseCollisionMod:BardingCoverage(horseEnt)
	local cfg = self.Config

	if not cfg.Barding or not horseEnt then
		return 0
	end

	local barding = self:ArmorOf(horseEnt)

	if not barding then
		return 0
	end

	local full = cfg.BardingFullSmashDef or 1.5

	if full <= 0 then
		return 0
	end

	local coverage = barding.smashDef / full

	if coverage < 0 then
		return 0
	end

	if coverage > 1 then
		return 1
	end

	return coverage
end

--- What barding adds to the two knockdown force figures.
--
-- A flat addition to `Knockback` and `Uplift`, in five steps. No barding adds
-- nothing, a fifth of a full set adds a fifth of the bonus, and so on to a
-- full set adding all of it. Steps rather than a smooth curve so that the
-- table in the settings file is the whole rule and a player can read what
-- their own horse is getting.
--
-- The rows are `{ coverage at or above, knockback added, uplift added }`, and
-- the highest row the horse qualifies for wins.
--
-- @tparam table horseEnt the player's horse entity
-- @treturn table `knockback` and `uplift` additions, both 0 on a bare horse
function HorseCollisionMod:BardingForceBonus(horseEnt)
	local steps = self.Config.BardingForceSteps
	local bonus = { knockback = 0, uplift = 0 }

	if type(steps) ~= "table" then
		return bonus
	end

	local coverage = self:BardingCoverage(horseEnt)

	for _, step in ipairs(steps) do
		if coverage >= step[1] then
			bonus.knockback = step[2]
			bonus.uplift = step[3]
		end
	end

	return bonus
end

--- What barding adds to the damage an impact does.
--
-- An armored horse hits harder. Damage is a number rather than a picture, so
-- a subtle change here is actually achievable, unlike knockback.
--
-- @tparam table horseEnt the player's horse entity
-- @treturn number a multiplier on impact damage, 1 on a bare horse
function HorseCollisionMod:BardingDamageScale(horseEnt)
	return 1.0 + (self:BardingCoverage(horseEnt)
			* (self.Config.BardingDamageBonus or 0))
end

--- What barding saves the horse in stamina.
--
-- Barding is protection, so an impact tires the horse less. This is the half
-- of barding a player actually feels: one more guard ridden down before the
-- horse is spent and throws them.
--
-- @tparam table horseEnt the player's horse entity
-- @treturn number a multiplier on the stamina cost, 1 on a bare horse
function HorseCollisionMod:BardingStaminaScale(horseEnt)
	return 1.0 - (self:BardingCoverage(horseEnt)
			* (self.Config.BardingStaminaRelief or 0))
end
