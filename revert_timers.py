def patch_file(f, orig, new):
    with open(f, 'r', encoding='utf-8') as fh: t = fh.read()
    if orig in t:
        t = t.replace(orig, new)
        with open(f, 'w', encoding='utf-8') as fh: fh.write(t)
    else:
        print(f"Warning: could not find target text in {f}")

# Revert Settings
orig_settings = '''	-- How long a victim is closed to further impacts, in milliseconds, preventing
	-- overlapping or double-impacts during a reaction sequence. All tiers have
	-- a baseline lock out period that supersedes the HitMinIntervalMs.
	VictimLockMsByTier       = { Charge = 2600, Gallop = 2000, Trot = 1200, Walk = 800 },'''
new_settings = '''	-- How long a victim is closed to further impacts, in milliseconds, for an
	-- impact that is one deliberate move rather than a pass of the horse. Only
	-- the charge has one; every other tier is debounced by HitMinIntervalMs.
	VictimLockMsByTier       = { Charge = 2600 },'''
patch_file('src/HorseCollisionMod_Settings.lua', orig_settings, new_settings)

# Revert Impact.lua
orig_impact = '''	local lock = self:TierValue("VictimLockMsByTier", tierName)
	if lock and lock > 0 and npc and npc.id then
		self.LockedUntil[tostring(npc.id)] = self:TimeMs() + lock
	end

	-- Walked once per impact.'''
new_impact = '''	-- Walked once per impact.'''
patch_file('src/HorseCollisionMod/Impact.lua', orig_impact, new_impact)

# Restore Rear.lua
orig_rear = '''	local lock = self:TierValue("VictimLockMsByTier", tier)

	-- Everything an impact does is shared with the detection loop and lives in'''
new_rear = '''	local lock = self:TierValue("VictimLockMsByTier", tier)

	if lock and lock > 0 then
		self.LockedUntil[victimId] = now + lock
	end

	-- Everything an impact does is shared with the detection loop and lives in'''
patch_file('src/HorseCollisionMod/Rear.lua', orig_rear, new_rear)
