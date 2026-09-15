def patch_file(f, orig, new):
    with open(f, 'r', encoding='utf-8') as fh: t = fh.read()
    if orig in t:
        t = t.replace(orig, new)
        with open(f, 'w', encoding='utf-8') as fh: fh.write(t)
    else:
        print(f"Warning: could not find target text in {f}")

orig_rear = '''	-- two share this function.


	-- Everything an impact does is shared with the detection loop and lives in'''

new_rear = '''	-- two share this function.
	local lock = self:TierValue("VictimLockMsByTier", tier)

	if lock and lock > 0 then
		self.LockedUntil[victimId] = now + lock
	end

	-- Everything an impact does is shared with the detection loop and lives in'''

patch_file('src/HorseCollisionMod/Rear.lua', orig_rear, new_rear)
