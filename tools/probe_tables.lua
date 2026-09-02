-- Dumps the columns, and a few rows, of named game database tables.
--
-- `Database` exposes the tables the game ships, and `Armor.lua` already joins
-- two of them for item weights. The same access answers what any other table
-- holds, which is how a system with no Lua API can still be read.
--
-- Read-only. Edit `WANTED` and run through `dev_console.py --file`.

local WANTED = { "situation", "situation_role", "random_event",
		"random_event_option", "random_event_variant" }

local ROWS = 4

local db = rawget(_G, "Database")

if type(db) ~= "table" then
	System.LogAlways("[TBL] Database is unavailable")
	return
end

for _, name in pairs(WANTED) do
	local ok, err = pcall(function()
		local info = db.GetTableInfo(name)

		if not info then
			System.LogAlways("[TBL] " .. name .. " not found")

			return
		end

		local columns = {}

		for c = 0, info.ColumnCount - 1 do
			columns[#columns + 1] = db.GetColumnInfo(name, c).Name
		end

		System.LogAlways("[TBL] " .. name
				.. " rows=" .. tostring(info.RowCount)
				.. " cols=" .. tostring(info.ColumnCount))

		-- Column names in batches, because one line long enough to hold them
		-- all is truncated before it reaches the log.
		for i = 1, #columns, 5 do
			System.LogAlways("[TBL]   cols: "
					.. table.concat(columns, ", ", i, math.min(i + 4, #columns)))
		end

		-- The first column's values stand in for the rows themselves, which is
		-- enough to tell what a table is a list of.
		local first = db.GetTableColumnData(name, 0)

		if first then
			local sample = {}

			for i = 1, math.min(ROWS, #first) do
				sample[#sample + 1] = tostring(first[i])
			end

			System.LogAlways("[TBL]   first column: " .. table.concat(sample, " | "))
		end
	end)

	if not ok then
		System.LogAlways("[TBL] " .. name .. " failed: " .. tostring(err))
	end
end
