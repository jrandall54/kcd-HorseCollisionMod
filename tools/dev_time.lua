-- Moves game time forward without the in-game wait dialog.
--
-- Waiting is the most expensive thing a test can ask of this project. The
-- wait wheel caps at 24 hours, runs at `wh_pl_SkipTimeMaxWorldTimeRatio` 360,
-- which is about four real minutes a day, and in hardcore it also demands
-- food and a bed. A question needing several in-game days was therefore
-- abandoned rather than answered.
--
-- None of that is necessary. `Calendar` is a Lua global and world time is
-- directly settable. This is the same call spraguep's Cheat mod makes, and
-- the follow-up message is vanilla's own way of telling the world to catch up
-- after a jump.
--
-- WARNING. Setting HOURS jumps the world clock, and doing so broke a running
-- session: the rider reported that "everything broke" after a 24 hour jump and
-- had to reload. It also does not run NPCs through their day, so anything that
-- depends on a routine will not have happened. For those, raise
-- `wh_pl_SkipTimeMaxWorldTimeRatio` from its default of 360 to something like
-- 7200 and use the game's own wait, which takes about twelve seconds a day and
-- simulates the world properly.
--
-- Edit HOURS and run:
--
--     python tools/dev_console.py --file tools/dev_time.lua
--
-- Pair it with tools/dev_survival.lua, which holds nourishment and energy at
-- 100, so a multi-day skip does not become an errand of finding a meal.
--
-- Setting `RATIO` instead leaves ordinary time running fast rather than
-- jumping, which is what to use when the thing being measured needs the world
-- to tick rather than to arrive. 15 is the shipped default; 0 pauses.

local HOURS = 24
local RATIO = nil

local function stamp(label)
	local t = Calendar.GetWorldTime()

	System.LogAlways(string.format(
			"[TIME] %s day=%d %02d:%02d ratio=%s paused=%s",
			label,
			math.floor(t / 86400),
			(t / 3600) % 24,
			(t / 60) % 60,
			tostring(Calendar.GetWorldTimeRatio()),
			tostring(Calendar.IsWorldTimePaused())))
end

stamp("before")

if type(RATIO) == "number" then
	Calendar.SetWorldTimeRatio(RATIO)

	if RATIO ~= 0 then
		if Calendar.IsWorldTimePaused() then
			Calendar.SetWorldTimePaused(false)
		end

		if Calendar.IsFakedTimeOfDay() then
			Calendar.UnfakeTimeOfDay()
		end
	end

	System.LogAlways("[TIME] world time ratio set to " .. tostring(RATIO))
end

if type(HOURS) == "number" and HOURS ~= 0 then
	Calendar.SetWorldTime(Calendar.GetWorldTime() + (HOURS * 3600))

	-- Vanilla sends this after a jump. Without it the world keeps whatever it
	-- had computed against the old clock.
	local ok = pcall(function()
		XGenAIModule.SendMessageToEntity(player.this.id,
				"timekeeper:recalculate", "")
	end)

	System.LogAlways("[TIME] moved forward " .. tostring(HOURS)
			.. " hours, recalculate=" .. tostring(ok))
end

stamp("after")
