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
-- ### Women raise the alarm instead of fighting
--
-- `sb_combat.xml` tests `b_soul.gender == male` **after** the context option
-- is consulted, and fails everyone else outright. `alwaysFightWhenHit`
-- removes the morale comparison and nothing more, so a woman carrying it
-- still falls through to the report or flee branches of the same handler.
--
-- That fall-through is the feature rather than an obstacle. A woman shoved
-- once too often runs and fetches a guard, which is a response to being
-- ridden down rather than an absence of one, and it is the tree's own
-- behavior: the same provocation is sent, and the branch she lands in is
-- chosen by the game.
--
-- She is given neither the context option nor the offense release. Both exist
-- to push a victim through a fight subtree she cannot enter, so setting them
-- would only leave an option to clear afterwards for no effect.
--
-- Morale is not what separates her from a man, and it was measured rather
-- than assumed. Across twenty one NPCs in Rattay the women read 0.15 to 0.22
-- and the male civilians read 0.16 to 0.52 against guards at 0.54 to 0.79, so
-- the morale comparison tells a guard from a townsman and says nothing about
-- sex. Routing on the gender the combat tree itself tests is therefore the
-- honest implementation, not a shortcut around a stat that would have done it.
--
-- @module HorseCollisionMod.Retaliation
-- @author jrandall54
-- @release 4.20.0
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

--- The soul gender that falls through to the report and flee branches.
--
-- Same source as `GenderMale`: logged reactions report `gender=2` for women.
HorseCollisionMod.GenderFemale = 2

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

--- How this victim answers a shove too many.
--
-- **Gender** decides which of two answers is available, and it is the game's
-- decision rather than this mod's. `sb_combat.xml` tests
-- `b_soul.gender == male` after the context option is consulted and fails
-- everyone else outright, so a man reaches the fight branch and a woman falls
-- through to the report or flee branches of the same handler.
--
-- Both are answers, so both are offered: `"fight"` for a man and `"alarm"`
-- for a woman, with `"none"` for anyone the game would let do neither. The
-- caller sends the same provocation either way and does the extra work that
-- only a fight needs.
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
-- @treturn string `"fight"`, `"alarm"` or `"none"`
-- @treturn string the victim's social class, or why the answer is `"none"`
function HorseCollisionMod:CanRetaliate(npc)
	local gender = nil

	pcall(function()
		gender = npc.soul:GetGender()
	end)

	local roleName = "?"

	pcall(function()
		roleName = tostring(npc.soul:GetSocialClass().Name)
	end)

	if gender == self.GenderFemale then
		if not self.Config.WomenRaiseAlarm then
			return "none", "alarm-off"
		end

		return "alarm", roleName
	end

	if gender ~= self.GenderMale then
		return "none", "gender=" .. tostring(gender)
	end

	-- Only the fight needs a context option, so a missing context system
	-- rules out the fight and leaves the alarm above untouched.
	if not self:HasContexts() then
		return "none", "no-contexts"
	end

	return "fight", roleName
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
			self:Log("OffenseRelease " .. self:NameOf(npc)
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
	local sawYield = false
	local caught = false

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

			if state ~= nil and string.find(state, "^Surrender") ~= nil then
				sawYield = true
			end
		else
			finishedFor = finishedFor + 1

			-- Off by default. See `CatchYieldImmediately`.
			if self.CatchYieldImmediately and sawYield and not caught then
				caught = true

				local stoodDown = self:SendStandDown(npc)

				if self.Config.LogTelemetry then
					self:Log("YieldCaught " .. self:NameOf(npc)
							.. " state=" .. tostring(state)
							.. " stoodDown=" .. tostring(stoodDown))
				end
			end
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
		self:Log("RepairVictim " .. self:NameOf(npc)
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
--- Shows the on-screen prompt telling the player they can surrender.
--
-- Surrendering already works during a provoked brawl and resolves it cleanly.
-- Nothing told the player so: the hint that appears when guards attack is
-- raised from the AI's own behavior tree and a mod-provoked fight never
-- triggers it, so the option existed and was invisible.
--
-- The HUD element declares `ShowActionHint(ActionId, Control, Text, Type,
-- Name)` in `Libs/UI/UIElements/HUD.xml`, reachable through
-- `UIAction.CallFunction`. `Control` is not the action name but a localized
-- control token, which `Game.GetActionControl` resolves from the action map
-- and the action: `player` and `surrender` give `@ui_control_uc_33`. Resolved
-- each time rather than stored, so a player who rebinds the key sees their own
-- binding rather than the default.
--
-- `Type` 0 is a press and 1 is a hold. Surrender is a press.
--
-- One hint for any number of provoked victims, counted rather than shown per
-- fight, so a brawl with three of them does not stack three copies and does
-- not disappear when the first one yields.
function HorseCollisionMod:ShowSurrenderHint(npc)
	if not self.Config.RetaliationSurrenderHint then
		return
	end

	self.SurrenderHintCount = (self.SurrenderHintCount or 0) + 1
	self.SurrenderHintCalm = 0

	-- Who the prompt is for. Surrendering is something offered to a person,
	-- and once every person it was raised for is dead there is nobody to
	-- offer it to, however long the engine keeps reporting danger.
	self.SurrenderHintFor = self.SurrenderHintFor or {}

	if npc and npc.id then
		self.SurrenderHintFor[tostring(npc.id)] = npc
	end

	if self.SurrenderHintCount > 1 then
		return
	end

	local control = nil

	pcall(function()
		control = Game.GetActionControl("player", "surrender")
	end)

	if not control then
		return
	end

	local ok = pcall(function()
		UIAction.CallFunction("hud", -1, "ShowActionHint",
				self.SurrenderHintId, control, "@ui_hint_surrender", 0, "")
	end)

	if self.Config.LogTelemetry then
		self:Log("SurrenderHint shown control=" .. tostring(control)
				.. " ok=" .. tostring(ok))
	end

	-- Put back on an interval for as long as a fight is running, because the
	-- HUD drops it on its own. Being pulled off the horse swaps the action map
	-- from `horse` to `player`, the hints are rebuilt for the new map, and a
	-- hint this mod raised is not among them: measured as the prompt appearing
	-- correctly, then disappearing at the moment of the unhorsing and staying
	-- gone for the rest of the brawl.
	--
	-- The control is resolved again on each pass rather than reused, since the
	-- map it belongs to is exactly what changed.
	local generation = self.TimerTick

	-- Exactly one of these loops, ever.
	--
	-- The guard above starts a loop only for the first fight, and the loop
	-- ends by noticing the count has reached zero. But it only notices on its
	-- next pass, up to a second later, so a fight ending and another starting
	-- inside that second leaves the old loop scheduled while the guard lets a
	-- new one through. Two loops then assert the same hint on their own
	-- timers, each taking it down and putting it back, and they interleave.
	--
	-- A token settles it: starting a loop claims the token, and any loop
	-- holding a stale one retires on its next pass.
	self.SurrenderHintLoop = (self.SurrenderHintLoop or 0) + 1

	local token = self.SurrenderHintLoop

	local function hold()
		if generation ~= self.TimerTick or token ~= self.SurrenderHintLoop then
			return
		end

		if (self.SurrenderHintCount or 0) <= 0 then
			return
		end

		-- The prompt lives as long as a surrender is actually possible, which
		-- is not the same as the mod's own idea of when the brawl ended.
		-- `EndRetaliation` fires the moment the rider is pulled off the horse,
		-- because the victim stops reading as fighting during the pull, and
		-- the fight then carries on for another half minute. Hanging the
		-- prompt on that took it down a second after it appeared.
		--
		-- `IsInCombatDanger` is the same read the collision code uses for
		-- whether the player is in a fight, and it is the honest condition
		-- here: while it holds, pressing the key does something.
		local danger = false

		pcall(function()
			danger = player.soul:IsInCombatDanger()
		end)

		-- Nobody left to surrender to.
		--
		-- The table holds the victims this prompt was raised for. They are
		-- removed as they die and as their fights end, so an empty table means
		-- there is nobody who could accept a surrender, whatever the engine
		-- still reports about danger.
		--
		-- The prompt is held by the danger reading alone, which lingers after
		-- a fight ends and needs six quiet passes to clear, so killing the
		-- last person offering to fight left the prompt up for five or six
		-- seconds with nobody to accept it. Measured after a beggar was
		-- reared to death, and newly reachable because the rear can now kill
		-- the victims it provokes.
		--
		-- Checked before the danger reading rather than after, because this is
		-- the stronger condition: a live opponent may briefly read as no
		-- danger, but a dead one is never going to accept a surrender.
		local anyoneLeft = false

		for id, victim in pairs(self.SurrenderHintFor or {}) do
			local dead = true

			pcall(function()
				dead = victim:IsDead()
			end)

			if dead then
				self.SurrenderHintFor[id] = nil
			else
				anyoneLeft = true
			end
		end

		if not anyoneLeft then
			self:Log("SurrenderHint nobody left to surrender to")
			self:HideSurrenderHint(true)

			return
		end

		if danger then
			self.SurrenderHintCalm = 0
		else
			-- Not taken down on the first quiet pass. The reading drops out
			-- briefly during a fight, and a prompt that blinks with it would
			-- be worse than one that lingers a moment.
			self.SurrenderHintCalm = (self.SurrenderHintCalm or 0) + 1

			if self.SurrenderHintCalm
					>= (self.Config.SurrenderHintCalmPasses or 6) then
				self:HideSurrenderHint(true)

				return
			end
		end

		pcall(function()
			local again = Game.GetActionControl("player", "surrender")

			if again then
				-- Taken down and put back rather than simply shown again.
				-- Re-showing an id the HUD still believes it is displaying
				-- is a no-op, so after the action map change wiped the hint
				-- from the screen the re-assert changed nothing and the
				-- prompt stayed gone for the rest of the fight.
				UIAction.CallFunction("hud", -1, "HideActionHint",
						self.SurrenderHintId)
				UIAction.CallFunction("hud", -1, "ShowActionHint",
						self.SurrenderHintId, again, "@ui_hint_surrender", 0, "")
			end
		end)

		Script.SetTimer(self.Config.SurrenderHintHoldMs or 1000, hold)
	end

	Script.SetTimer(self.Config.SurrenderHintHoldMs or 1000, hold)
end

--- Whether the game will raise its own surrender prompt for this victim.
--
-- Guards arrest rather than brawl, and an arrest is where vanilla shows its
-- own prompt. Raising one alongside it puts two on screen offering the same
-- key, which is reproducible by provoking a guard in sight of another guard.
--
-- Read from the victim's social class, the same source the retaliation answer
-- uses, so the two cannot disagree about who is a soldier.
--
-- @tparam table npc the provoked victim
-- @treturn boolean true when the prompt belongs to the game
function HorseCollisionMod:SurrenderIsTheGames(npc)
	if not self.Config.SurrenderHintYieldsToGame then
		return false
	end

	local role = nil

	pcall(function()
		role = tostring(npc.soul:GetSocialClass().Name)
	end)

	return role == "soldier"
end

--- Takes the surrender prompt down when the last provoked fight ends.
--
-- @tparam[opt] boolean all clear the count outright, for a load or a reset
function HorseCollisionMod:HideSurrenderHint(all)
	local count = self.SurrenderHintCount or 0

	if count <= 0 then
		return
	end

	self.SurrenderHintCount = all and 0 or (count - 1)

	if all then
		self.SurrenderHintFor = {}
	end

	if self.SurrenderHintCount > 0 then
		return
	end

	local ok = pcall(function()
		UIAction.CallFunction("hud", -1, "HideActionHint", self.SurrenderHintId)
	end)

	if self.Config.LogTelemetry then
		self:Log("SurrenderHint hidden ok=" .. tostring(ok))
	end
end

function HorseCollisionMod:EndRetaliation(npc, why)
	-- The prompt is for people who might accept a surrender, and this victim
	-- no longer will: the fight is over however it ended. Removing him here
	-- is what takes the prompt down promptly, rather than waiting for the
	-- danger reading to go quiet and stay quiet.
	--
	-- Safe to hang on this ending where it was not safe to hang the whole
	-- prompt on it. The watcher requires having seen him fight before it
	-- counts settled samples, so being pulled off the horse no longer reads
	-- as the fight finishing a second after it started.
	if self.SurrenderHintFor and npc and npc.id then
		self.SurrenderHintFor[tostring(npc.id)] = nil
	end

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
		self:Log("RetaliationEnd " .. self:NameOf(npc)
				.. " why=" .. tostring(why)
				.. " cleared=" .. tostring(cleared)
				.. " state=" .. tostring(state)
				.. " repaired=" .. tostring(repaired))
	end
end

--- Leaves a victim right once the fight is over.
--
-- He is replanned so he has somewhere to be, and his standing is checked
-- again a little later, because the repair at the close of the incident runs
-- before the rider is necessarily finished with him: a victim knocked down
-- again, or beaten while he stands up, loses more afterwards. One measured
-- victim was repaired at the close, dropped back to 0.0 by what followed, and
-- was restored here.
--
-- Nothing is done about a victim who runs, because a flee ends by itself.
-- Measured on one beggar, one build, the only difference being what the rider
-- did: left alone he stopped after fourteen seconds, and chased he was still
-- at full speed forty seconds later. `fleeFromNPCParams` gives the reason,
-- with a `distance` of 150 and `t_fleeParams.entityToFleeFrom` set to the
-- player, so the run ends when he is that far from the man he is running
-- from and following him means he never gets there.
--
-- `combat:stimulus:standDownRequest` does stop that run, and is not sent.
-- It hands him to `state_standDown`, which holds him through a hot entity
-- cooldown for about twenty five seconds of standing still, which is a
-- visible cost for a problem that resolves on its own.
--
-- @tparam table npc victim entity
function HorseCollisionMod:WatchAftermath(npc)
	local generation = self.TimerTick
	local replanned = self:ReplanVictim(npc)

	if self.Config.LogTelemetry then
		self:Log("Aftermath " .. self:NameOf(npc)
				.. " replanned=" .. tostring(replanned))
	end

	Script.SetTimer(self.AftermathSettleMs, function()
		if generation ~= self.TimerTick then
			return
		end

		self:RepairVictim(npc)
		self.Baseline[tostring(npc.id)] = nil
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

	-- Nobody new is provoked while the rider is already in a fight.
	--
	-- Detection cannot tell a rider steering into someone from someone running
	-- into a nearly stationary horse, because it reads the horse's speed and
	-- who is close, not who closed the distance. During a brawl that is exactly
	-- what happens: guards charge the horse, each contact scores as a walk
	-- impact, and each one provokes another attacker. Measured at 1.93 m/s
	-- against a threshold of 1.8, with `danger=true` on the same line, on a
	-- rider who had shoved one merchant and touched no guard at all.
	--
	-- The impact still lands and still costs the victim. Only the provocation
	-- is withheld, so a fight grows from what the rider did before it started
	-- rather than from the fight itself.
	if not self.Config.ProvokeDuringCombat then
		local danger = false

		pcall(function()
			danger = player.soul:IsInCombatDanger()
		end)

		if danger then
			return false
		end
	end

	local count = self:NoteAnnoyance(npc)
	local chance = self:RetaliationChance(count)

	if chance <= 0 then
		return false
	end

	local answer, note = self:CanRetaliate(npc)

	if answer == "none" then
		if self.Config.LogTelemetry then
			self:Log("Retaliation " .. self:NameOf(npc)
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
		self:Log("Retaliation " .. self:NameOf(npc)
				.. " role=" .. note
				.. " answer=" .. answer
				.. " count=" .. tostring(count)
				.. " chance=" .. string.format("%.2f", chance)
				.. " roll=" .. string.format("%.2f", roll)
				.. " provoked=" .. tostring(provoked))
	end

	if not provoked then
		return false
	end

	-- A woman takes the same provocation and none of the fight scaffolding.
	-- The context option and the offense release both act on a fight subtree
	-- she cannot enter, so setting them would leave an option to clear
	-- afterwards and change nothing about what she does.
	if answer == "alarm" then
		self:SendProvocationHit(npc, playerEnt)
		self.Annoyance[tostring(npc.id)] = nil

		-- Nothing repairs her afterwards, so the baseline taken above would
		-- sit in the table for the rest of the session. The hit carries
		-- `real = false` and the reputation system never sees it, so there
		-- is nothing for a repair to put back.
		self.Baseline[tostring(npc.id)] = nil

		return true
	end

	if not self:HoldRetaliation(npc) then
		self:Log("Retaliation " .. self:NameOf(npc)
				.. " could not take the context option")

		return false
	end

	-- Sent after the option is in place, not before. The option decides how
	-- the stimulus is answered, so one that arrives first is answered the old
	-- way and the provocation is wasted.
	self:SendProvocationHit(npc, playerEnt)

	-- The provocation decides that he fights; releasing the offense decides
	-- that he attacks. Without it he enters the fight in defense only and
	-- holds a guard until something else closes the incident, which is the
	-- whole of what a provoked victim did before it existed.
	--
	-- Against a mounted rider that release is held back until the rider is on
	-- the ground. Handing him the offense first is what made him punch the
	-- horse: told to attack, he attacks the thing in front of him, and the
	-- pull-down request then queues behind the swing. A man who wants to
	-- fight someone on a horse takes them off it first, so the order here is
	-- pull, then fight.
	-- Not for a soldier. The game raises its own surrender prompt when it
	-- arrests you, and a guard provoked in front of a witness is an arrest, so
	-- this one would sit beside it: two prompts on screen offering the same
	-- thing. Reproducible every time by provoking a guard another guard can
	-- see, and never with a villager, who cannot arrest anyone.
	--
	-- The mod's own documentation already records that a shoved guard arrests
	-- rather than brawls, and that the game's rule for soldiers is left alone.
	-- Its prompt should be left alone with it.
	if self:SurrenderIsTheGames(npc) then
		self:Log("SurrenderHint left to the game for " .. self:NameOf(npc))
	else
		self:ShowSurrenderHint(npc)
	end

	if self:PullRiderDown(npc) then
		return true
	end

	self:ReleaseWhenFighting(npc)

	-- The count is spent. Without this a victim already fighting keeps
	-- rolling on every further contact during the brawl.
	self.Annoyance[tostring(npc.id)] = nil

	return true
end

--- Has a provoked victim drag the rider out of the saddle.
--
-- A man who has run out of patience with someone riding into him goes for the
-- rider, not the animal. Left to itself the AI gets there eventually, but it
-- fights the horse first while it works into position, and a person throwing
-- punches at a horse does not read as anything a person would do.
--
-- `RequestHorsePullDown` is the vanilla action, the same one guards use when
-- they unhorse the player, and it takes the victim's entity id, meaning the
-- person being pulled down. It is offered by the AI's own behavior tree as
-- `HorsePullDownAction`, governed by `wh_cs_HorsePullDownAngle` at 55 degrees
-- with a Z angle and a zero angle alongside it, so it is not available until
-- the NPC has the geometry. `CanHorsePullDown` returns 0 until then.
--
-- So this asks repeatedly rather than once, from the moment the fight starts,
-- until the rider is down. Nothing is forced: if the geometry never
-- comes the request is simply never made and the brawl proceeds as it did
-- before.
--
-- A rider already on the ground is the other reason to stop, and it is the
-- common one, since the whole point is that this happens early.
--
-- Returns whether it has taken responsibility for starting the fight. When it
-- has, the caller must not release the offense: this does it once the rider is
-- down, or on the ceiling if the pull never comes.
--
-- @tparam table npc the provoked victim
-- @treturn boolean true when the offense release has been deferred to this
function HorseCollisionMod:PullRiderDown(npc)
	local mounted = false

	pcall(function()
		mounted = player.human:IsMounted()
	end)

	if not self.Config.RetaliationPullsRiderDown or not mounted then
		return false
	end

	local pollMs = self.Config.PullDownPollMs or 250
	local ceilingMs = self.Config.PullDownCeilingMs or 8000
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local polls = 0
	local bestCan = 0
	local bestCanHorse = 0
	local bestAngle = 999
	local widestAngle = -1
	local angleWhenEnabled = -1
	local pullTarget = "player"

	local function attempt()
		if generation ~= self.TimerTick then
			return
		end

		local mounted = false

		pcall(function()
			mounted = player.human:IsMounted()
		end)

		local elapsed = self:TimeMs() - startedAt

		if not mounted or elapsed >= ceilingMs then
			if self.Config.LogTelemetry then
				-- What the victim looked like when it never became available,
				-- since one merchant gets the pull within a second and
				-- another never gets it at all across the whole ceiling.
				local state, dist, hostile = "?", -1, "?"

				pcall(function()
					state = tostring(npc.actor:GetCurrentAnimationState())
				end)

				pcall(function()
					dist = npc:GetDistance(player.id)
				end)

				pcall(function()
					hostile = tostring(npc.soul:IsInCombatDanger())
				end)

				self:Log("PullDown " .. self:NameOf(npc)
						.. " done why=" .. (mounted and "ceiling" or "dismounted")
						.. " atMs=" .. string.format("%.0f", elapsed)
						.. " polls=" .. tostring(polls)
						.. " bestCan=" .. tostring(bestCan)
						.. " bestCanHorse=" .. tostring(bestCanHorse)
						.. " angles=" .. string.format("%.0f", bestAngle)
						.. "-" .. string.format("%.0f", widestAngle)
						.. " enabledAt=" .. string.format("%.0f", angleWhenEnabled)
						.. " state=" .. state
						.. " dist=" .. string.format("%.2f", dist)
						.. " hostile=" .. hostile)
			end

			-- Now he may swing. Held until here so the pull is the opening
			-- move rather than something queued behind a punch, and released
			-- on the ceiling too so a victim who never gets the geometry is
			-- not left standing with his guard up forever.
			self:ReleaseWhenFighting(npc)

			return
		end

		local can = 0
		local canHorse = 0

		pcall(function()
			can = npc.actor:CanHorsePullDown(player.id) or 0
		end)

		-- The rider is pulled off a horse, so the id the action wants may be
		-- the horse rather than the person. Both are asked until one of them
		-- is shown to be the right one.
		pcall(function()
			local h = XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())

			if h then
				canHorse = npc.actor:CanHorsePullDown(h.id) or 0
			end
		end)

		polls = polls + 1

		-- The angle between where the horse is pointing and where the victim
		-- is standing. `wh_cs_HorsePullDownAngle` is 55 degrees, so a victim
		-- who only ever approaches from the flank may never qualify.
		pcall(function()
			local h = XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())
			local hp = h and h:GetWorldPos()
			local np = npc:GetWorldPos()
			local dir = h and h:GetDirectionVector(1)

			if hp and np and dir then
				local dx, dy = np.x - hp.x, np.y - hp.y
				local len = math.sqrt(dx * dx + dy * dy)

				if len > 0 then
					local dot = ((dx / len) * dir.x) + ((dy / len) * dir.y)

					if dot > 1 then
						dot = 1
					end

					if dot < -1 then
						dot = -1
					end

					local deg = math.acos(dot) * 180 / math.pi

					if deg < bestAngle then
						bestAngle = deg
					end

					if deg > widestAngle then
						widestAngle = deg
					end

					if can ~= 0 and angleWhenEnabled < 0 then
						angleWhenEnabled = deg
					end
				end
			end
		end)

		if can > bestCan then
			bestCan = can
		end

		if canHorse > bestCanHorse then
			bestCanHorse = canHorse
		end

		if can == 0 and canHorse ~= 0 then
			can = canHorse
			pullTarget = "horse"
		end

		-- Asked regardless of what the check says when `PullDownForce` is on.
		-- `CanHorsePullDown` returns an HPS status, 2 enabled and 1 disabled,
		-- and some victims answer 0, meaning the engine does not consider the
		-- action applicable to them at all. Measured on one merchant across
		-- 32 polls at every angle from 1 to 117 degrees and under two meters,
		-- while another merchant answers 2 within a second. Whether the
		-- request is honoured anyway is a separate question from whether the
		-- check advertises it.
		if can ~= 0 or self.Config.PullDownForce then
			local ok = pcall(function()
				local id = player.id

				if pullTarget == "horse" then
					local h = XGenAIModule.GetEntityByWUID(
							player.player:GetPlayerHorse())
					id = h and h.id or player.id
				end

				npc.actor:RequestHorsePullDown(id)
			end)

			if self.Config.LogTelemetry then
				self:Log("PullDown " .. self:NameOf(npc)
						.. " requested can=" .. tostring(can)
						.. " ok=" .. tostring(ok)
						.. " atMs=" .. string.format("%.0f", elapsed))
			end

			-- Asked again on a slow cadence until the rider is actually
			-- down. The request is accepted immediately but the brain runs
			-- it when it is ready, and without the offense released there is
			-- little for it to be busy with, so this is a safety net rather
			-- than the mechanism.
			Script.SetTimer(self.Config.PullDownRepeatMs or 1500, attempt)

			return
		end

		Script.SetTimer(pollMs, attempt)
	end

	attempt()
end
