--- Victims who run out of patience and fight back.
--
-- Barging someone at a walk costs nobody anything. It plays a stagger, takes
-- no health, drains no stamina and raises no crime, so riding into the same
-- person repeatedly is an annoyance with no consequence attached to it. This
-- file attaches one.
--
-- Each walk impact is counted against its victim. Past `RetaliationFreeBumps`
-- every further shove rolls against a chance that grows with the count, and a
-- victim who fails that roll turns and fights.
--
-- ### How the fight is started
--
-- Two steps, and both are the game's own machinery rather than anything
-- invented here.
--
-- `alwaysFightWhenHit` is a context option from the shipped catalog in
-- `Scripts/Script/ContextData.lua`. Vanilla quests set options exactly this
-- way: `q_ledecko` gives four bandits `fightAllHostilePerceptibles`, and
-- `q_hareHunt` applies the `berserk` preset. In `sb_combat.xml` the option
-- sits in front of the morale comparison that otherwise decides whether a
-- civilian fights or flees, and skipping that comparison is all it does.
--
-- Then a `combat:hit` carrying `real = false`, which the victim's combat
-- subbrain answers without the reputation system ever seeing it. That is what
-- makes a provoked scuffle a scuffle rather than an assault charge.
--
-- ### What the game decides, and this file does not
--
-- The shape of the fight is vanilla's. Because the attacker is the player and
-- the player is not already an enemy, `sb_combat.xml` sets
-- `startInDefenseOnly`, so the victim squares up and blocks rather than
-- opening with an attack. Guards who witness the brawl join it, because the
-- game models what a bystander perceived. Neither is arranged here.
--
-- ### Guards are included, and behave differently on purpose
--
-- A provoked guard arrests the rider rather than brawling with him, because
-- the soldier branch of the hit handler raises assault information whenever
-- the attacker is the player. That is a guard using the authority a guard
-- has, and the crime-free brawl here is for the people who lack it.
--
-- ### Women do not fight
--
-- `sb_combat.xml` tests `b_soul.gender == male` **after** the context option
-- is consulted, and fails everyone else outright. `alwaysFightWhenHit`
-- removes the morale comparison and nothing more, so a woman carrying it
-- still falls through to the report or flee branches. Provoking her would
-- send her walking off to fetch a guard over an incident that raised no
-- crime, which reads as a bug rather than a character. So the roll is not
-- offered to her, and the reason is logged.
--
-- @module HorseCollisionMod.Retaliation
-- @author jrandall54
-- @release 4.6.3
--- The context option that makes a victim answer a hit with a fight.
--
-- From the game's own catalog. Named here rather than written inline at each
-- use so a search for it finds one definition.
HorseCollisionMod.RetaliationOption = "alwaysFightWhenHit"

--- The handle every context option this mod sets is carried on.
--
-- `Contexts` tracks each option against a named handle and clears it per
-- handle, so several systems can request the same option without treading on
-- each other. Using one of this mod's own means clearing it can never disturb
-- a quest that wanted the same option for its own reasons.
HorseCollisionMod.RetaliationHandle = "horseCollisionMod"

--- The soul gender that `sb_combat.xml` lets through to the fight branch.
--
-- Confirmed against telemetry rather than assumed: logged reactions report
-- `gender=1` for men and `gender=2` for women.
HorseCollisionMod.GenderMale = 1

--- Whether the context system is available.
--
-- `Contexts` is a vanilla global from `Scripts/Script/Context.lua`. Every use
-- below is wrapped anyway, but checking once gives the telemetry a specific
-- reason rather than a failed call.
-- @treturn boolean true when contexts can be set
function HorseCollisionMod:HasContexts()
	local contexts = rawget(_G, "Contexts")

	return type(contexts) == "table"
			and type(contexts.SetNonpersistentOption) == "function"
end

--- Whether this victim is one the game would let fight back at all.
--
-- **Gender** is the only real gate, and it is the game's rather than this
-- mod's. `sb_combat.xml` tests `b_soul.gender == male` after the context
-- option is consulted and fails everyone else outright.
-- `alwaysFightWhenHit` removes the morale comparison and nothing more, so a
-- provoked woman falls through to the report or flee branches and would walk
-- off to fetch a guard over an incident that raised no crime.
--
-- **Guards are deliberately not excluded.** They behave differently, and the
-- difference is correct: the soldier branch of the hit handler calls
-- `CreateInformation label='assault'` whenever the attacker is the player,
-- with no `real` check and no context option in front of it, so provoking one
-- is a crime and ends in an arrest. That is a guard exercising the authority
-- a guard has, and the crime-free brawl this file builds is for the people
-- who lack it. An earlier revision gated soldiers out; the gate was wrong and
-- has been removed.
--
-- `soul:GetSocialClass()` carries `SoulCrimeRoleId` and a class `Name` if the
-- distinction is ever wanted: a village guard reports `soldier` and 2 against
-- a townsman's `civilian` and 1. It is read here only for the telemetry, so a
-- log can be read afterwards for who was provoked.
--
-- @tparam table npc victim entity
-- @treturn boolean true when a provoked fight is possible
-- @treturn string why not, when it is not, or the role when it is
function HorseCollisionMod:CanRetaliate(npc)
	local gender = nil

	pcall(function()
		gender = npc.soul:GetGender()
	end)

	if gender ~= self.GenderMale then
		return false, "gender=" .. tostring(gender)
	end

	if not self:HasContexts() then
		return false, "no-contexts"
	end

	local roleName = "?"

	pcall(function()
		roleName = tostring(npc.soul:GetSocialClass().Name)
	end)

	return true, roleName
end

--- Counts a shove against a victim and returns how many they have taken.
--
-- A count older than `RetaliationMemorySec` is discarded rather than aged
-- down. Someone barged twice this morning does not start today's ride one
-- shove from a fight.
--
-- @tparam table npc victim entity
-- @treturn number the running count, this shove included
function HorseCollisionMod:NoteAnnoyance(npc)
	local id = tostring(npc.id)
	local now = self:TimeMs()
	local record = self.Annoyance[id]
	local memory = (self.Config.RetaliationMemorySec or 0) * 1000

	if record and memory > 0 and (now - record.at) > memory then
		record = nil
	end

	if not record then
		record = { count = 0, at = now }
	end

	record.count = record.count + 1
	record.at = now
	self.Annoyance[id] = record

	return record.count
end

--- The chance this shove ends in a fight.
--
-- Zero until the victim has taken more than `RetaliationFreeBumps`, then
-- `RetaliationChanceStep` per shove beyond that, capped at
-- `RetaliationMaxChance`. The first contact is always free, so brushing past
-- someone once never starts anything.
--
-- @tparam number count how many shoves this victim has taken
-- @treturn number a chance between 0 and 1
function HorseCollisionMod:RetaliationChance(count)
	local free = self.Config.RetaliationFreeBumps or 0
	local beyond = count - free

	if beyond <= 0 then
		return 0.0
	end

	local chance = beyond * (self.Config.RetaliationChanceStep or 0)
	local ceiling = self.Config.RetaliationMaxChance or 1.0

	if chance > ceiling then
		chance = ceiling
	end

	return chance
end

--- Gives a victim the disposition to fight, and watches for the fight to end.
--
-- The option is nonpersistent, so it does not survive a save reload. It is
-- taken back deliberately as well: left set, every NPC the player had ever
-- shoved would answer any hit from anyone with a fight for the rest of the
-- session, which is a different mod.
--
-- When it is taken back is decided by watching the victim, not by a duration.
-- A brawl has no characteristic length, and a timer either cuts a good fight
-- short or leaves a resolved one hanging. See `WatchRetaliation` for what is
-- actually read.
--
-- @tparam table npc victim entity
-- @treturn boolean true when the option was set
function HorseCollisionMod:HoldRetaliation(npc)
	local ok = pcall(function()
		Contexts.SetNonpersistentOption(npc, self.RetaliationOption,
				self.RetaliationHandle)
	end)

	if not ok then
		return false
	end

	self:WatchRetaliation(npc)

	return true
end

--- What a victim is doing right now, in the terms this file cares about.
--
-- Reads `actor:GetCurrentAnimationState()`, the same call the reaction
-- recovery polls, and classifies it alongside how far the victim moved since
-- the previous sample.
--
-- * `engaged` - the incident is still running. Two prefixes qualify.
--   `Combat` is the obvious one, and `CombatMovement` was observed on a guard
--   closing to two meters. `Surrender` is the one that was missed, and
--   missing it was a real fault: a victim who yields stands in `SurrenderIn`,
--   which carries neither prefix under the first version of this test and is
--   perfectly still, so three samples of it read as settled and the incident
--   was closed while the victim was in the middle of yielding. Both fights of
--   that build ended `why=natural state=SurrenderIn` and both victims were
--   left running afterwards. The engine's surrender states all share the
--   prefix: `SurrenderIn`, `SurrenderDialog`, `SurrenderDialogToIdle`,
--   `SurrenderDialogToMove`, `SurrenderForcedWait` and `SurrenderToCombat`.
-- * `fleeing` - not engaged, covering ground faster than an errand, **and**
--   the rider is far enough away that the running is no longer about him. A
--   runaway was measured at 4.79 m/s sustained, against roughly a meter per
--   second for someone walking to a stall.
--
--   The range test matters more than it looks. Every runaway observed while
--   developing this was observed by following the runaway, and a man who has
--   just been knocked down and is being pursued by the person who did it has
--   every reason to keep going. Fleeing with the rider on top of him is
--   counted as engaged instead: the incident is live, nothing is sent, and
--   the victim is left to do the sensible thing.
-- * `settled` - anything else, which includes every idle and every ordinary
--   working animation.
--
-- @tparam string state the animation state
-- @tparam number speed meters per second since the previous sample
-- @tparam number playerRange meters between the victim and the rider
-- @treturn string one of `engaged`, `fleeing` or `settled`
function HorseCollisionMod:ClassifyVictim(state, speed, playerRange)
	if state ~= nil then
		if string.find(state, "^Combat") ~= nil then
			return "engaged"
		end

		if string.find(state, "^Surrender") ~= nil then
			return "engaged"
		end
	end

	if speed >= (self.Config.RetaliationFleeSpeed or 3.5) then
		-- Running away from someone standing over you is not a fault, and
		-- interrupting it would be. Only a victim still running with the
		-- rider well clear has a flee that has outlived its cause.
		if playerRange >= (self.Config.RetaliationFleeIgnoreRange or 25) then
			return "fleeing"
		end

		return "engaged"
	end

	return "settled"
end

--- Polls the victim and closes the incident out when their state says to.
--
-- Replaces a fixed hold. The question "is this over" has a readable answer,
-- and reading it is both more accurate and more honest than assuming a
-- duration: a fight that runs long is not interrupted, and one that ends in
-- four seconds is not left hanging for another forty.
--
-- Three ways it finishes, and the telemetry names which:
--
-- * `natural` - the victim settled by themselves. Nothing is sent. This is
--   the outcome that proves the game resolves its own fights, and it is the
--   reason the poll exists rather than an unconditional stand-down: the
--   previous build could not tell a victim it had rescued from one that never
--   needed rescuing.
-- * `runaway` - the victim left combat but kept running, sustained across
--   `RetaliationFleeSamples` consecutive samples. This is the case that was
--   observed running out of town and not stopping, and it is the only one
--   that genuinely needs the stand-down.
-- * `ceiling` - a failsafe, not a mechanism. If neither of the above has
--   happened by `RetaliationCeilingSec`, the incident is closed anyway so a
--   poll cannot run for the rest of the session.
--
-- The poll is generation-guarded: a load screen moves `TimerTick`, and a
-- sample scheduled before it would otherwise fire into a world that no longer
-- contains the entity it was about.
--
-- @tparam table npc victim entity
function HorseCollisionMod:WatchRetaliation(npc)
	local generation = self.TimerTick
	local interval = self.RetaliationPollMs
	local ceiling = (self.Config.RetaliationCeilingSec or 120) * 1000
	local needed = self.Config.RetaliationFleeSamples or 8

	local elapsed = 0
	local fledFor = 0
	local settledFor = 0
	local sawEngaged = false
	local last = nil

	pcall(function()
		local p = npc:GetWorldPos()

		last = { x = p.x, y = p.y, z = p.z }
	end)

	local function sample()
		if generation ~= self.TimerTick then
			return
		end

		elapsed = elapsed + interval

		local state = nil
		local moved = 0

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		pcall(function()
			local p = npc:GetWorldPos()

			if last then
				moved = self:VectorLength({
					x = p.x - last.x,
					y = p.y - last.y,
					z = p.z - last.z
				})
			end

			last = { x = p.x, y = p.y, z = p.z }
		end)

		local speed = moved / (interval / 1000)
		local playerRange = 999

		pcall(function()
			local pp = player:GetWorldPos()
			local p = npc:GetWorldPos()

			playerRange = self:VectorLength({
				x = p.x - pp.x,
				y = p.y - pp.y,
				z = p.z - pp.z
			})
		end)

		local what = self:ClassifyVictim(state, speed, playerRange)

		if what == "engaged" then
			sawEngaged = true
			fledFor = 0
			settledFor = 0
		elseif what == "fleeing" then
			fledFor = fledFor + 1
			settledFor = 0
		else
			fledFor = 0
			settledFor = settledFor + 1
		end

		-- Settled has to hold for more than one sample. A fighter between
		-- exchanges reads as settled for an instant, and closing the incident
		-- there would end a fight still in progress.
		if sawEngaged and settledFor >= 3 then
			self:EndRetaliation(npc, "natural", false)

			return
		end

		if fledFor >= needed then
			self:EndRetaliation(npc, "runaway", true)

			return
		end

		if elapsed >= ceiling then
			self:EndRetaliation(npc, "ceiling", true)

			return
		end

		Script.SetTimer(interval, sample)
	end

	Script.SetTimer(interval, sample)
end

--- Tells a victim the incident is over and they may stand down.
--
-- `combat:stimulus:standDownRequest` sets `t_state = standDown` in
-- `sb_combat.xml`, and it is one of only two stimulus kinds exempt from the
-- acceptance rule that rejects a stimulus outright while the receiver is
-- already fighting or fleeing. That exemption is the whole reason it works
-- here: every other message this mod could send is discarded by someone
-- mid-flight, which is exactly who needs it.
--
-- The payload is empty. `TypeDefinitions.xml` declares a single member `_`,
-- which is a placeholder rather than a field: passing it is rejected with
-- "override table does not match the type", and vanilla's own sends carry
-- `values=""`.
--
-- @tparam table npc victim entity
-- @treturn boolean true when the call was accepted
function HorseCollisionMod:SendStandDown(npc)
	local target = npc.id

	if npc.this and npc.this.id then
		target = npc.this.id
	end

	local ok = pcall(function()
		local message = Utils.makeTable("combat:stimulus:standDownRequest", {})

		XGenAIModule.SendMessageToEntityData(target,
				"combat:stimulus:standDownRequest", message)
	end)

	return ok
end

--- Closes the incident out: takes the option back and, if needed, intervenes.
--
-- `why` names which of `WatchRetaliation`'s three endings applied, and it
-- goes straight into the telemetry, so a session can be read afterwards for
-- how often the game resolved its own fight against how often this mod had to
-- step in. That ratio is the thing worth knowing about this feature.
--
-- `intervene` decides whether anything is sent at all. On a natural ending
-- the victim has already settled and the correct action is none: sending a
-- stand-down and a replan to someone who is fine interrupts whatever they
-- went back to.
--
-- When intervention is warranted, both messages go out in order. The
-- stand-down ends the combat state, and it is the only message that reaches
-- someone mid-flight at all: `sb_combat.xml` rejects every stimulus arriving
-- during `fight` or `flee` except `standDownRequest` and
-- `customBehaviorRequest`, which are named exemptions in the condition.
-- Measured on a victim who would not stop, 16.95 m of travel per sample
-- became `MotionIdle` at 0.00 m within a second, and a daycycle idle ten
-- seconds later.
--
-- The replan follows, and is the same `daycycle:restartRequest` the reaction
-- recovery uses. It covers a victim who has stopped but has nothing to return
-- to.
--
-- @tparam table npc victim entity
-- @tparam string why one of `natural`, `runaway` or `ceiling`
-- @tparam boolean intervene whether to send the stand-down and the replan
function HorseCollisionMod:EndRetaliation(npc, why, intervene)
	local cleared = pcall(function()
		Contexts.ClearOption(npc, self.RetaliationOption,
				self.RetaliationHandle)
	end)

	local state = nil

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	local stoodDown = false
	local replanned = false

	if intervene then
		stoodDown = self:SendStandDown(npc)
		replanned = self:ReplanVictim(npc)
	end

	if self.Config.LogTelemetry then
		self:Log("RetaliationEnd " .. tostring(npc:GetName())
				.. " why=" .. tostring(why)
				.. " cleared=" .. tostring(cleared)
				.. " state=" .. tostring(state)
				.. " stoodDown=" .. tostring(stoodDown)
				.. " replanned=" .. tostring(replanned))
	end
end

--- Decides whether this walk impact provokes a fight, and starts one if so.
--
-- Called for every walk-tier impact. Everything before the roll is cheap, and
-- the expensive half only runs on a victim who has actually lost patience.
--
-- @tparam table npc victim entity
-- @tparam table playerEnt the player entity
-- @treturn boolean true when a fight was provoked
function HorseCollisionMod:ProvokeIfAnnoyed(npc, playerEnt)
	if not self.Config.Retaliation then
		return false
	end

	local count = self:NoteAnnoyance(npc)
	local chance = self:RetaliationChance(count)

	if chance <= 0 then
		return false
	end

	local able, note = self:CanRetaliate(npc)

	if not able then
		if self.Config.LogTelemetry then
			self:Log("Retaliation " .. tostring(npc:GetName())
					.. " count=" .. tostring(count)
					.. " skipped=" .. note)
		end

		return false
	end

	local roll = math.random()
	local provoked = roll < chance

	if self.Config.LogTelemetry then
		self:Log("Retaliation " .. tostring(npc:GetName())
				.. " role=" .. note
				.. " count=" .. tostring(count)
				.. " chance=" .. string.format("%.2f", chance)
				.. " roll=" .. string.format("%.2f", roll)
				.. " provoked=" .. tostring(provoked))
	end

	if not provoked then
		return false
	end

	if not self:HoldRetaliation(npc) then
		self:Log("Retaliation " .. tostring(npc:GetName())
				.. " could not take the context option")

		return false
	end

	-- Sent after the option is in place, not before. The option decides how
	-- the stimulus is answered, so one that arrives first is answered the old
	-- way and the provocation is wasted.
	self:SendProvocationHit(npc, playerEnt)

	-- The count is spent. Without this a victim already fighting keeps
	-- rolling on every further contact during the brawl.
	self.Annoyance[tostring(npc.id)] = nil

	return true
end
