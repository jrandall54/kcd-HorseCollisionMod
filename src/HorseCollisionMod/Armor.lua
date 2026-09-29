--- Armor: what a collision victim is wearing, and what it changes.
--
-- What a victim wears changes an impact three ways. Its armor **weight**
-- sets the impulse multiplier, through `ArmorCurve`, and the stamina
-- surcharge, off its own full-set anchor. Its summed **`smash_def`** sets the
-- damage multiplier. The horse's own barding, also read from `smash_def`,
-- adds force, damage and stamina relief.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. The curves read `Config`, so
-- the settings they depend on live in the entry point and exist before this
-- file runs.
--
-- @module HorseCollisionMod.Armor
-- @author jrandall54

--- The `armor_type_id` values that are a horse's tack rather than armor:
-- the saddle and the horseshoes.
--
-- `armor_type_id` 12 is named `horse_bridle` in `armor_type.xml` but is not
-- excluded: the game files every `horse_armor_head_neck_*` piece under it,
-- with a `smash_def` of 0.80 to 1.40, and genuine bridles share the id at
-- 0.00, so counting it costs nothing.
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
-- Saddles and horseshoes are filed as armor; `TackTypes` names them. `tack`
-- true sums only those, false sums everything else, which is both a
-- person's armor and a horse's barding.
--
-- @tparam table entity any entity with an inventory
-- @tparam[opt] boolean tack true to sum tack instead of armor
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

--- How much a target's armor weight changes the impulse it takes.
--
-- `weight` is the target's armor weight and `reference` the weight that
-- changes nothing, so the ratio between them is the whole signal; `exponent`
-- sets how sharply it bites and 0 switches the scaling off entirely. Armor
-- makes a target harder to throw, so the impulse takes the reciprocal of the
-- ratio (`invert`, which `ArmorImpulseScale`, the only caller, always sets).
--
-- Clamped, because the curve has no natural floor or ceiling and an unclamped
-- extreme reads in game as a target that cannot be moved at all, or one that
-- flies out of sight.
--
-- @tparam number weight the target's armor weight
-- @tparam number reference the weight that produces 1.0
-- @tparam number exponent how strongly weight matters, 0 to disable
-- @tparam boolean invert true to take the reciprocal of the ratio
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

--- Where a target sits between "fully armored" and "unarmored", 0 to 1.
--
-- `ArmorImpulseScale` answers a multiplier; the throw wants a position, and
-- the gallop's brake, cap and drag and the charge's lunge transfer each
-- interpolate their own pair of figures across it.
--
-- The span is `RagdollBrakeArmorScaleArmored` to
-- `RagdollBrakeArmorScaleUnarmored`. They are not the same pair as
-- `MinArmorImpulse` and `MaxArmorImpulse`, which bound the curve itself: the
-- unarmored endpoint here is 1.26, inside the curve's 0.35 to 1.5. Ordinary
-- villagers score about 1.15, so they land near but not at 1, and the endpoint
-- figures in a throw profile describe a bracket rather than a delivered value.
--
-- @tparam[opt] number armorScale a value from `ArmorImpulseScale`
-- @treturn number 0 at the armored endpoint, 1 at the unarmored one
function HorseCollisionMod:ArmorLerp(armorScale)
	local lo = self.Config.RagdollBrakeArmorScaleArmored
	local hi = self.Config.RagdollBrakeArmorScaleUnarmored

	if not armorScale or not lo or not hi or hi <= lo then
		return 1.0
	end

	local t = (armorScale - lo) / (hi - lo)

	if t < 0 then
		return 0
	end

	if t > 1 then
		return 1
	end

	return t
end

--- One pair of figures interpolated across a target's armor.
--
-- The shape every consumer of `ArmorLerp` wanted. `armored` is what a victim
-- in full mail gets and `unarmored` is what a victim in none gets; everyone
-- else lands between them.
--
-- @tparam[opt] number armorScale a value from `ArmorImpulseScale`
-- @tparam number armored the figure at the armored endpoint
-- @tparam number unarmored the figure at the unarmored endpoint
-- @treturn number the interpolated figure
function HorseCollisionMod:ArmorBlend(armorScale, armored, unarmored)
	local t = self:ArmorLerp(armorScale)

	return armored + ((unarmored - armored) * t)
end

--- The stamina surcharge for a target's armor.
--
-- A share of the horse's pool added to the tier's own share, rising from zero
-- on a victim in clothes to `MaxArmorStaminaAdd` on one in a full set, so the
-- worst it can do is the figure it names.
--
-- The weight of what the victim is wearing is the input, not their armor
-- rating, for the same reason the impulse curve uses weight: what tires a
-- horse is shifting a heavy body, not the plate's rating against a hoof.
--
-- It has its own full-set weight rather than sharing `ArmorReferenceWeight`,
-- and the two figures are far apart on purpose. The impulse curve's reference
-- is the weight that multiplies an impulse by exactly one, a point inside the
-- range; a surcharge needs the weight where a victim is *fully* armored, or
-- everybody pays the maximum. Villagers weigh 5 to 7 and mailed guards 45 to
-- 65, so 50 is where a full set sits and a villager pays a tenth of the
-- surcharge.
--
-- @tparam table armor a table from `ArmorOf`
-- @treturn number a share of the horse's maximum stamina, near 0 on a victim
--   in ordinary clothes
function HorseCollisionMod:ArmorStaminaAdd(armor)
	local cfg = self.Config
	local reference = cfg.ArmorStaminaFullWeight

	if reference <= 0 then
		return 0.0
	end

	local ratio = (armor.weight or 0) / reference

	if ratio < 0 then
		ratio = 0
	end

	if ratio > 1 then
		ratio = 1
	end

	return cfg.MaxArmorStaminaAdd * math.pow(ratio, cfg.ArmorStaminaExponent)
end

--- How much of the tier's damage a target in this armor takes.
--
-- Driven by the armor's **`smash_def`**, its rating against blunt force,
-- rather than by weight through `ArmorCurve`, because what stops a hoof is the
-- plate rather than the mass.
--
-- One falling curve against the summed `smash_def` of what the victim is
-- wearing, past the part of it that is not armor, with a floor:
--
--     worn    = max(0, smashDef - ImpactDamageIgnoredArmor)
--     falloff = 1 / (1 + (worn / ImpactDamageArmorScale) ^ ImpactDamageArmorCurve)
--     result  = max(falloff, ImpactDamageArmorFloor)
--
-- It is 1.0 on anyone in ordinary clothes and never reaches 0, so plate is a
-- bad day rather than immunity. The subtraction exists because shoes, a
-- shirt and a hood are in the `armor` table and sum to 0.30 to 0.50 on a
-- villager wearing nothing anyone would call armor.
--
-- `smash_def` is the game's own blunt resistance and is the right column for a
-- horse: it is what the engine consults for a mace or a hammer, and a horse's
-- chest is the same kind of problem for a breastplate. Weight is deliberately
-- not used, though `ArmorOf` returns it, because a heavy mail hauberk and a
-- heavy padded gambeson weigh alike and stop a blunt impact differently.
--
-- The scale is a half-life rather than a ceiling: at
-- `ImpactDamageArmorScale` past the ignored figure the target takes half, at
-- twice it a third. With the shipped 2.9 that reads across the range actually
-- worn in game as, in gallop impacts (111, rolled 0.85 to 1.15) to take a
-- victim from 100 health,
--
--     villager    smashDef 0.30   1.00   1 to 2
--     light       smashDef 1.50   0.74   2
--     guard       smashDef 3.22   0.52   2 to 3
--     mail        smashDef 4.99   0.39   3
--     heavy mail  smashDef 7.16   0.30   3 to 4
--     plate       smashDef 12.0   0.20   4 to 6
--
-- @tparam table armor totals from `ArmorOf`
-- @treturn number multiplier on the tier's damage, in (0, 1]
function HorseCollisionMod:ImpactDamageScale(armor)
	local scale = self.Config.ImpactDamageArmorScale

	if type(scale) ~= "number" or scale <= 0 then
		return 1.0
	end

	local smashDef = 0

	if type(armor) == "table" and type(armor.smashDef) == "number" then
		smashDef = armor.smashDef
	end

	local ignored = self.Config.ImpactDamageIgnoredArmor
	local worn = smashDef - ignored

	if worn <= 0 then
		return 1.0
	end

	-- The curve, and then a floor under it.
	--
	-- `1 / (1 + worn / scale)` alone is a hyperbola with no bottom, so heavy
	-- enough armor drives the multiplier arbitrarily close to zero.
	--
	-- `ImpactDamageArmorCurve` bends it. Above 1 armor bites harder and sooner,
	-- below 1 it flattens, and 1 is the plain hyperbola.
	--
	-- `ImpactDamageArmorFloor` is the share of an impact armor cannot refuse:
	-- no plate makes a body weigh less than the horse standing on it. 0.14 is
	-- the engine trample's mean of 16 on an armored victim over the gallop's
	-- 111, which `ImpactDamageOwnsTheHit` hands back, so the mod delivers the
	-- floor the engine would have. At the shipped scale the curve stays above
	-- it for everything worn in the game, so the floor guards against armor
	-- heavier than plate rather than clamping inside the range.
	local curve = self.Config.ImpactDamageArmorCurve
	local falloff = 1.0 / (1.0 + ((worn / scale) ^ curve))
	local floor = self.Config.ImpactDamageArmorFloor

	if falloff < floor then
		falloff = floor
	end

	return falloff
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
-- because each of barding's three effects scales it differently: the force
-- is a flat addition and the stamina relief a flat reduction, while the damage
-- is a multiplier on the victim's damage. The force is flat because a
-- multiplier on the impulse would compound with the victim's own armor scale
-- and move an unarmored villager far more than an armored one, which is
-- backwards for a property of the horse.
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

	local full = cfg.BardingFullSmashDef

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
-- An armored horse hits harder, by up to `BardingDamageBonus` on a full set.
--
-- @tparam table horseEnt the player's horse entity
-- @treturn number a multiplier on impact damage, 1 on a bare horse
function HorseCollisionMod:BardingDamageScale(horseEnt)
	return 1.0 + (self:BardingCoverage(horseEnt)
			* (self.Config.BardingDamageBonus))
end

--- What barding saves the horse in stamina.
--
-- Barding is protection, so an impact tires the horse less. A share of the
-- horse's pool subtracted from the tier's own share, in the same currency as
-- the tier figure, the combat surcharge and the armor surcharge, so a full set
-- is worth exactly the figure `BardingStaminaRelief` names.
--
-- @tparam table horseEnt the player's horse entity
-- @treturn number a share of the horse's maximum stamina, 0 on a bare horse
function HorseCollisionMod:BardingStaminaRelief(horseEnt)
	return self:BardingCoverage(horseEnt) * self.Config.BardingStaminaRelief
end
