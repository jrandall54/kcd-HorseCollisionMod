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
-- Three steps, and all of them are the game's own machinery rather than
-- anything invented here.
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
-- Those two decide that he fights. A third decides that he attacks, and it is
-- needed because the first two do not: a victim struck by a player who is not
-- already an enemy enters the fight with `startInDefenseOnly`, holds his
-- guard and never strikes. `ReleaseWhenFighting` waits for him to reach the
-- fight and sends the one message that turns offense on. See
-- `SendOffenseRelease` for why it is a `hitReaction` and why it costs the
-- victim nothing.
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
-- @release 4.7.3
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

--- Waits for a provoked victim to reach the fight, then lets him throw a punch.
--
-- The release cannot travel with the provocation. The node that reads it runs
-- inside the fight subtree, which the victim is not in yet when the
-- provocation is sent, and `sb_combat.xml` clears that inbox on the way in.
-- A message sent too early therefore has nobody to read it, or is discarded
-- by the entry that follows.
--
-- The victim's own animation state says when he has arrived, so it is polled
-- rather than waited out. A fixed delay would be a guess about how long a
-- behavior tree takes to switch subtrees, and the answer is readable instead:
-- every combat state the tree reports carries the `Combat` prefix, and the
-- guard the victim holds during the stall reports `CombatIdle`.
--
-- Giving up is logged rather than silent, because a victim who never reaches
-- the fight is the interesting case: it means the provocation itself was
-- refused, which the `Retaliation` line above would not have shown.
--
-- @tparam table npc victim entity
function HorseCollisionMod:ReleaseWhenFighting(npc)
	local generation = self.TimerTick
	local interval = self.RetaliationReleaseMs
	local left = self.RetaliationReleaseTries

	local function attempt()
		if generation ~= self.TimerTick then
			return
		end

		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		if state ~= nil and string.find(state, "^Combat") ~= nil then
			self:SendOffenseRelease(npc)

			return
		end

		left = left - 1

		if left > 0 then
			Script.SetTimer(interval, attempt)

			return
		end

		if self.Config.LogTelemetry then
			self:Log("OffenseRelease " .. tostring(npc:GetName())
					.. " never reached the fight, state=" .. tostring(state))
		end
	end

	Script.SetTimer(interval, attempt)
end

--- Whether the victim is still in the fight.
--
-- Reads `actor:GetCurrentAnimationState()`, the same call the reaction
-- recovery polls. Two prefixes mean the incident is live:
--
-- * `Combat` is the obvious one, and `CombatMovement` was observed on a guard
--   closing to two meters.
-- * `Surrender` is the one that is easy to miss, and missing it is a real
--   fault: a victim who yields stands in `SurrenderIn`, which is perfectly
--   still, so it reads as finished and the incident closes in the middle of
--   the yield. The engine's surrender states all share the prefix:
--   `SurrenderIn`, `SurrenderDialog`, `SurrenderDialogToIdle`,
--   `SurrenderDialogToMove`, `SurrenderForcedWait` and `SurrenderToCombat`.
--
-- Anything else is finished, and that deliberately includes a victim running
-- away. Running is not a state this has to handle specially: a man sprinting
-- from the rider has left the fight, so the incident should close and the
-- aftermath should take him, which is exactly what treating it as finished
-- does. An earlier design classified running separately and only counted it
-- once the rider was 25 m clear, which never happens while the rider is
-- following him; it fired in none of six incidents.
--
-- @tparam string state the animation state
-- @treturn boolean true while the fight is still running
function HorseCollisionMod:IsStillFighting(state)
	if state == nil then
		return false
	end

	return string.find(state, "^Combat") ~= nil
			or string.find(state, "^Surrender") ~= nil
end

--- Polls the victim and closes the incident when the fight is over.
--
-- The question "is this over" has a readable answer, so it is read rather
-- than waited out: a fight that runs long is not interrupted, and one that
-- ends in four seconds is not left hanging for another forty.
--
-- Finished has to hold for `RetaliationSettledSamples` rather than a single
-- sample, because a fighter between exchanges reads as finished for an
-- instant and closing there would cut a live fight short.
--
-- The fight is waited for rather than assumed, but it always arrives:
-- `alwaysFightWhenHit` skips the morale comparison that would otherwise let a
-- timid victim decline, so courage decides how the fight goes and not whether
-- there is one. A victim who yields to the first punch has still fought.
--
-- `RetaliationCeilingSec` bounds the poll so a victim who never resolves
-- cannot leave it running for the session. It is a failsafe rather than a
-- mechanism, and in six measured incidents it was never reached.
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

	local elapsed = 0
	local finishedFor = 0
	local sawFight = false

	local function sample()
		if generation ~= self.TimerTick then
			return
		end

		elapsed = elapsed + interval

		local state = nil

		pcall(function()
			state = tostring(npc.actor:GetCurrentAnimationState())
		end)

		if self:IsStillFighting(state) then
			sawFight = true
			finishedFor = 0
		else
			finishedFor = finishedFor + 1
		end

		if sawFight and finishedFor >= self.RetaliationSettledSamples then
			self:EndRetaliation(npc, "settled")

			return
		end

		if elapsed >= ceiling then
			self:EndRetaliation(npc, "ceiling")

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

--- Puts a victim right once the fight is over.
--
-- A man the rider fought is left at a relationship of 0.0 against the 0.50 an
-- untouched townsman reads, and below vanilla's 0.2 threshold he decides to
-- run every time he perceives the rider. Riding past him a week later still
-- sends him sprinting, which reads as a permanently ruined NPC rather than a
-- man who lost a fight.
--
-- **Two things are needed and neither works alone**, which is what made this
-- hard to see. Measured on a victim who had been fleeing on sight across a
-- save reload and an in game wait:
--
-- * `combat:stimulus:standDownRequest` cancels the flee that is running. Sent
--   by itself it bought five seconds, and then the next time he perceived the
--   rider he decided to flee again.
-- * Raising the relationship changes the decision but not the behavior
--   already executing, so sent by itself while he is mid-flight it does
--   nothing visible. That is why an earlier reading of this called reputation
--   irrelevant; the measurement could not have shown an effect either way.
--
-- Together they hold. The same victim stopped, stood at a meter and a half
-- for twelve seconds, and afterwards would talk and trade.
--
-- ### It marks him down, it does not reward him
--
-- The target is the victim's own standing before he was provoked, less
-- `RepairFightCost`, held above `RepairFloor`. He remembers the fight, which
-- is right, and he is never left under the threshold that ruins him, which is
-- the bug. The count is worked from his own figure rather than fixed, because
-- a count calibrated for a victim at 0.0 carries one to 0.84 against the 0.50
-- his untouched neighbors read, and a beating would pay the rider a bonus.
--
-- ### The step is a fixed quantum, so the count is arithmetic
--
-- `surrender_step` moves the relationship by `RepairStepValue` every time it
-- is applied, whatever second argument it is given: 0.1, 0.2 and no argument
-- at all each moved exactly 0.1389 in a measured sweep. The magnitude cannot
-- be tuned, so the number of applications is what decides where a victim
-- lands, and that is worked out once from the gap rather than approached by
-- trial. They apply in one pass, because a change does not read back in the
-- frame it is applied and re-reading between them would report stale values.
--
-- The quantum is also the precision: a victim lands within one step above his
-- target and no closer, and `surrender_step` cannot take anyone past 0.8430
-- however many are applied.
--
-- @tparam table npc victim entity
-- @treturn boolean true when a repair was applied
function HorseCollisionMod:RepairVictim(npc)
	local id = tostring(npc.id)
	local baseline = self.Baseline[id] or self.RepairDefaultTarget
	local target = baseline - self.RepairFightCost

	if target < self.RepairFloor then
		target = self.RepairFloor
	end

	local before = nil

	pcall(function()
		before = npc.soul:GetRelationship(player.this.id)
	end)

	if before == nil or before >= target then
		return false
	end

	local steps = math.ceil((target - before) / self.RepairStepValue)

	if steps > self.RepairMaxSteps then
		steps = self.RepairMaxSteps
	end

	for _ = 1, steps do
		pcall(function()
			npc.soul:ModifyPlayerReputation("surrender_step")
		end)
	end

	if self.Config.LogTelemetry then
		self:Log("RepairVictim " .. tostring(npc:GetName())
				.. " from=" .. string.format("%.3f", before)
				.. " target=" .. string.format("%.3f", target)
				.. " steps=" .. tostring(steps))
	end

	return true
end

--- Closes the incident out and puts the victim back the way he was found.
--
-- `why` names which ending applied and goes into the telemetry, so a session
-- can be read afterwards for how often a fight resolved itself against how
-- often the failsafe had to close it.
--
-- Three things happen, and every one of them happens on every ending. None of
-- them is conditional on how the fight finished, because a settled victim is
-- not a safe victim: a man released through the yield menu settles first and
-- only then walks away for good.
--
-- * The context option comes back. Left set, every NPC the rider had ever
--   shoved would answer any hit from anyone with a fight for the rest of the
--   session, which is a different mod.
-- * His standing is repaired, because below vanilla's threshold he decides to
--   run from the rider on sight, for good. See `RepairVictim`.
-- * `WatchAftermath` takes him from here, because the fight can end with a
--   flee already running that his standing does not explain and that nothing
--   else stops.
--
-- @tparam table npc victim entity
-- @tparam string why either `settled` or `ceiling`
function HorseCollisionMod:EndRetaliation(npc, why)
	local cleared = pcall(function()
		Contexts.ClearOption(npc, self.RetaliationOption,
				self.RetaliationHandle)
	end)

	local state = nil

	pcall(function()
		state = tostring(npc.actor:GetCurrentAnimationState())
	end)

	-- Every ending, not only the ones that need a stand-down. However the
	-- fight finished, whether he yielded, ran, or was knocked out and got up
	-- again, he is left below the threshold that decides he should run from
	-- the rider on sight, and that is what has to be undone.
	local repaired = self:RepairVictim(npc)

	-- Sent on every ending, not only the runaway and ceiling ones. A victim
	-- released through the yield menu walks away in a flee
	-- his own standing does not explain: measured at 0.737, well clear of the
	-- threshold that decides a man should run, and running anyway. Reputation
	-- cannot reach that and only the stand-down ends it.
	-- The stand-down is deliberately not sent here. A victim who runs should
	-- be allowed to get away first, and the rider is not necessarily finished
	-- with him either, so both are left to the aftermath.
	self:WatchAftermath(npc)

	if self.Config.LogTelemetry then
		self:Log("RetaliationEnd " .. tostring(npc:GetName())
				.. " why=" .. tostring(why)
				.. " cleared=" .. tostring(cleared)
				.. " state=" .. tostring(state)
				.. " repaired=" .. tostring(repaired))
	end
end

--- Lets a beaten victim run, then stops him and leaves him right.
--
-- The incident closing is the event everything here hangs off, so this is a
-- timer rather than a search. A victim released through the vanilla yield
-- menu settles first, which is what closes the incident, and only then walks
-- away in a flee that does not stop on its own.
--
-- He is given `AftermathRunMs` to get clear, and then stopped. The pause that
-- follows a stand-down is the combat subbrain's own wind-down and nothing
-- reachable from Lua shortens it, so the run is what decides whether he does
-- his standing about near the rider or somewhere else.
--
-- Whether he is actually running is read once, at the moment of stopping him,
-- from his own speed. That is the only signal that separates the two cases:
-- `GetCurrentAnimationState` reports `MotionMovement` both for a man fleeing
-- at four and a half meters per second and for one walking to his stall at
-- one, and the combat state that would say `flee` is subbrain local and reads
-- nil. A victim who is not running is left alone, because a stand-down would
-- park him for the wind-down he did not need.
--
-- His standing is then checked a second time. The repair at the end of the
-- incident runs before the rider is necessarily finished with him, and a
-- victim knocked down again loses more afterwards; one measured victim was
-- repaired at the close, dropped back to 0.0 by what followed, and restored
-- here.
--
-- @tparam table npc victim entity
function HorseCollisionMod:WatchAftermath(npc)
	local generation = self.TimerTick

	local function where()
		local p = nil

		pcall(function()
			local q = npc:GetWorldPos()

			p = { x = q.x, y = q.y }
		end)

		return p
	end

	local function finish()
		self:RepairVictim(npc)
		self.Baseline[tostring(npc.id)] = nil
	end

	-- One reading, taken where the decision is made rather than tracked
	-- throughout.
	local function speedThen(after)
		local first = where()

		Script.SetTimer(self.AftermathSampleMs, function()
			if generation ~= self.TimerTick then
				return
			end

			local second = where()
			local speed = 0

			if first ~= nil and second ~= nil then
				speed = self:VectorLength({
					x = second.x - first.x,
					y = second.y - first.y,
					z = 0
				}) / (self.AftermathSampleMs / 1000)
			end

			after(speed)
		end)
	end

	Script.SetTimer(self.AftermathRunMs, function()
		if generation ~= self.TimerTick then
			return
		end

		speedThen(function(speed)
			local running = speed > self.AftermathFleeSpeed
			local stoodDown = false

			if running and self.AftermathStandDown then
				stoodDown = self:SendStandDown(npc)
				self:OfferYield(npc)
			end

			local replanned = self:ReplanVictim(npc)

			if self.Config.LogTelemetry then
				self:Log("Aftermath " .. tostring(npc:GetName())
						.. " speed=" .. string.format("%.1f", speed)
						.. " running=" .. tostring(running)
						.. " stoodDown=" .. tostring(stoodDown)
						.. " replanned=" .. tostring(replanned))
			end

			Script.SetTimer(self.AftermathSettleMs, function()
				if generation ~= self.TimerTick then
					return
				end

				finish()
			end)
		end)
	end)
end

--- Offers the yield behavior until the victim takes it.
--
-- Delayed rather than immediate, and repeated rather than sent once. A yield
-- arriving while he is still coming out of the flee is discarded and he
-- serves the full wind-down standing still; one arriving after he has settled
-- had him walking 1.25 seconds later. Rather than trust a single delay to
-- suit every victim, it is offered again while he has not moved.
--
-- Stops as soon as he is under way, so a victim who took the first offer is
-- not sent another.
--
-- @tparam table npc victim entity
function HorseCollisionMod:OfferYield(npc)
	local generation = self.TimerTick
	local last = nil

	local function where()
		local p = nil

		pcall(function()
			local q = npc:GetWorldPos()

			p = { x = q.x, y = q.y }
		end)

		return p
	end

	local function offer(triesLeft)
		if generation ~= self.TimerTick then
			return
		end

		local at = where()

		if at ~= nil and last ~= nil then
			local moved = self:VectorLength({
				x = at.x - last.x,
				y = at.y - last.y,
				z = 0
			})

			if moved > 0.5 then
				return
			end
		end

		last = at

		self:SendYieldBehavior(npc)

		if triesLeft > 0 then
			Script.SetTimer(self.YieldRetryMs, function()
				offer(triesLeft - 1)
			end)
		end
	end

	Script.SetTimer(self.YieldDelayMs, function()
		offer(self.YieldRetries)
	end)
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

	-- Taken before the fight rather than after it, so the repair has a figure
	-- to restore rather than a guess. Nothing up to here has touched it: the
	-- shoves raise no crime and the provocation names the victim as his own
	-- attacker.
	pcall(function()
		self.Baseline[tostring(npc.id)] =
				npc.soul:GetRelationship(player.this.id)
	end)

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

	-- The provocation decides that he fights; this decides that he attacks.
	-- Without it he enters the fight in defense only and holds a guard until
	-- something else closes the incident, which is the whole of what a
	-- provoked victim did before it existed.
	self:ReleaseWhenFighting(npc)

	-- The count is spent. Without this a victim already fighting keeps
	-- rolling on every further contact during the brawl.
	self.Annoyance[tostring(npc.id)] = nil

	return true
end
