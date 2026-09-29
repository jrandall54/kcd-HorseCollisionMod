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
-- `Scripts/Script/ContextData.lua`, set the way vanilla quests set their own
-- context options. In `sb_combat.xml` the option
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
-- Guards are included, and behave differently on purpose; see
-- `CanRetaliate`.
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
-- The combat tree tests gender, not morale, so the mod routes on gender.
-- Morale separates guards from townsmen and does not separate women from men.
--
-- @module HorseCollisionMod.Retaliation
-- @author jrandall54

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
-- The value `GetGender` returns for a man; logged reactions report
-- `gender=1` for men and `gender=2` for women.
HorseCollisionMod.GenderMale = 1

--- The soul gender that falls through to the report and flee branches.
--
-- The value `GetGender` returns for a woman.
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
-- decision rather than this mod's; see the module header.
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
-- who lack it.
--
-- `soul:GetSocialClass()` carries a class `Name`: a village guard reports
-- `soldier` against a townsman's `civilian`. It is read here for the log
-- only, so a session can be read afterwards for who was provoked.
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
-- down.
--
-- @tparam table npc victim entity
-- @treturn number the running count, this shove included
function HorseCollisionMod:NoteAnnoyance(npc)
	local id = tostring(npc.id)
	local now = self:TimeMs()
	local record = self.Annoyance[id]
	local memory = (self.Config.RetaliationMemorySec) * 1000

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
-- `RetaliationMaxChance`. Contacts up to `RetaliationFreeBumps` are free.
--
-- @tparam number count how many shoves this victim has taken
-- @treturn number a chance between 0 and 1
function HorseCollisionMod:RetaliationChance(count)
	local free = self.Config.RetaliationFreeBumps
	local beyond = count - free

	if beyond <= 0 then
		return 0.0
	end

	local chance = beyond * (self.Config.RetaliationChanceStep)
	local ceiling = self.Config.RetaliationMaxChance

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
-- refused, which the `Retaliation` telemetry line would not have shown.
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
-- * `Combat`, which covers `CombatMovement` and `CombatIdle`.
-- * `Surrender` is the one that is easy to miss, and missing it is a real
--   fault: a victim who yields stands in `SurrenderIn`, which is perfectly
--   still, so it reads as finished and the incident closes in the middle of
--   the yield. The engine's surrender states all share the prefix:
--   `SurrenderIn`, `SurrenderDialog`, `SurrenderDialogToIdle`,
--   `SurrenderDialogToMove`, `SurrenderForcedWait` and `SurrenderToCombat`.
--
-- Anything else is finished, and that deliberately includes a victim running
-- away: a man sprinting from the player has left the fight, so the incident
-- closes and the aftermath takes him.
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
-- The fight is waited for rather than assumed. `alwaysFightWhenHit` skips the
-- morale comparison that would otherwise let a timid victim decline, so
-- courage decides how the fight goes and not whether there is one; a victim
-- who yields to the first punch has still fought.
--
-- `RetaliationCeilingSec` bounds the poll so a victim who never resolves
-- cannot leave it running for the session. It is a failsafe rather than a
-- mechanism.
--
-- The poll is generation-guarded: a load screen moves `TimerTick`, and a
-- sample scheduled before it would otherwise fire into a world that does not
-- contain the entity it was about.
--
-- @tparam table npc victim entity
function HorseCollisionMod:WatchRetaliation(npc)
	local generation = self.TimerTick
	local interval = self.RetaliationPollMs
	local ceiling = (self.Config.RetaliationCeilingSec) * 1000

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

--- Puts a victim right once the fight is over.
--
-- A man the player fought is left at a relationship of 0.0 against the 0.50 an
-- untouched townsman reads, and below vanilla's 0.2 threshold he decides to
-- run every time he perceives the player. Riding past him a week later still
-- sends him sprinting, which reads as a permanently ruined NPC rather than a
-- man who lost a fight.
--
-- Raising the relationship changes his next decision, not a flee already
-- running; that flee ends on its own (see `WatchAftermath`).
--
-- ### It marks him down, it does not reward him
--
-- The target is the victim's own standing before he was provoked, less
-- `RepairFightCost`, held above `RepairFloor`. He remembers the fight, which
-- is right, and he is never left under the threshold that ruins him, which is
-- the bug. The count is worked from his own figure rather than fixed, because
-- a count calibrated for a victim at 0.0 carries one to 0.84 against the 0.50
-- his untouched neighbors read, and a beating would pay the player a bonus.
--
-- ### The step is a fixed quantum, so the count is arithmetic
--
-- `surrender_step` moves the relationship by `RepairStepValue` every time it
-- is applied, whatever second argument it is given, so the number of
-- applications decides where a victim lands, worked out once from the gap.
-- They apply in one pass, because a change does not read back in the
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

--- Shows the on-screen prompt telling the player they can surrender.
--
-- Surrendering works during a provoked brawl and resolves it cleanly, but the
-- hint that appears when guards attack is raised from the AI's own behavior
-- tree and a mod-provoked fight never triggers it, so the mod raises it.
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
--
-- @tparam table npc the provoked victim the prompt is raised for
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
	-- hint this mod raised is not among them.
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

		-- The prompt lives as long as a surrender is possible, which is not
		-- the same as the mod's own idea of when the brawl ended.
		-- `IsInCombatDanger` is the same read the collision code uses for
		-- whether the player is in a fight: while it holds, pressing the key
		-- does something.
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
			if self.Config.LogTelemetry then
				self:Log("SurrenderHint nobody left to surrender to")
			end

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
					>= (self.Config.SurrenderHintCalmPasses) then
				self:HideSurrenderHint(true)

				return
			end
		end

		pcall(function()
			local again = Game.GetActionControl("player", "surrender")

			if again then
				-- Taken down and put back rather than shown again: re-showing
				-- an id the HUD still believes it is displaying does nothing,
				-- even after the action map change has wiped it.
				UIAction.CallFunction("hud", -1, "HideActionHint",
						self.SurrenderHintId)
				UIAction.CallFunction("hud", -1, "ShowActionHint",
						self.SurrenderHintId, again, "@ui_hint_surrender", 0, "")
			end
		end)

		Script.SetTimer(self.Config.SurrenderHintHoldMs, hold)
	end

	Script.SetTimer(self.Config.SurrenderHintHoldMs, hold)
end

--- Whether the game will raise its own surrender prompt for this victim.
--
-- Guards arrest rather than brawl, and an arrest is where vanilla shows its
-- own prompt. Raising one alongside it puts two on screen offering the same
-- key, which is reproducible by provoking a guard in sight of another guard.
--
-- Read from the victim's social class.
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
-- * The context option comes back. Left set, every NPC the player had ever
--   shoved would answer any hit from anyone with a fight for the rest of the
--   session.
-- * His standing is repaired, because below vanilla's threshold he decides to
--   run from the player on sight, for good. See `RepairVictim`.
-- * `WatchAftermath` takes him from here.
--
-- @tparam table npc victim entity
-- @tparam string why either `settled` or `ceiling`
function HorseCollisionMod:EndRetaliation(npc, why)
	-- The prompt is for people who might accept a surrender, and this victim
	-- will not: the fight is over however it ended. Removing him here
	-- is what takes the prompt down promptly, rather than waiting for the
	-- danger reading to go quiet and stay quiet.
	--
	-- Safe to hang on this ending: the watcher requires having seen him fight
	-- before it counts settled samples, so being pulled off the horse does
	-- not read as the fight finishing.
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
	-- the player on sight, and that is what has to be undone.
	local repaired = self:RepairVictim(npc)

	-- The stand-down is deliberately not sent here. A victim who runs should
	-- be allowed to get away first, and the player is not necessarily finished
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
-- before the player is necessarily finished with him: a victim knocked down
-- again, or beaten while he stands up, loses more afterwards.
--
-- Nothing is done about a victim who runs, because a flee ends by itself:
-- `fleeFromNPCParams` has a `distance` of 150 with the player as
-- `t_fleeParams.entityToFleeFrom`, so the run ends when he is that far from
-- the player, and following him means he never gets there.
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

	-- Nobody new is provoked while the player is already in a fight.
	--
	-- Detection cannot tell a rider steering into someone from someone running
	-- into a nearly stationary horse, because it reads the horse's speed and
	-- who is close, not who closed the distance. During a brawl that is exactly
	-- what happens: guards charge the horse, each contact scores as a walk
	-- impact, and each one would provoke another attacker.
	--
	-- The impact still lands and still costs the victim. Only the provocation
	-- is withheld, so a fight grows from what the player did before it started
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

	-- The surrender prompt, except for a soldier, whose arrest raises the
	-- game's own; see `SurrenderIsTheGames`.
	if self:SurrenderIsTheGames(npc) then
		if self.Config.LogTelemetry then
			self:Log("SurrenderHint left to the game for " .. self:NameOf(npc))
		end
	else
		self:ShowSurrenderHint(npc)
	end

	-- The count is spent. Without this a victim already fighting keeps
	-- rolling on every further contact during the brawl.
	self.Annoyance[tostring(npc.id)] = nil

	-- The provocation decides that he fights; releasing the offense decides
	-- that he attacks. Without it he enters the fight in defense only and
	-- holds a guard.
	--
	-- Against a mounted player the release is held back until the player is
	-- on the ground: told to attack, he attacks the thing in front of him,
	-- the horse, and the pull-down request then queues behind the swing. So
	-- the order is pull, then fight, and `PullRiderDown` releases the offense
	-- itself when it takes the victim on.
	if not self:PullRiderDown(npc) then
		self:ReleaseWhenFighting(npc)
	end

	return true
end

--- Has a provoked victim drag the player out of the saddle.
--
-- A man who has run out of patience with someone riding into him goes for the
-- rider, not the animal. Left to itself the AI gets there eventually, but it
-- fights the horse first while it works into position, and a person throwing
-- punches at a horse does not read as anything a person would do.
--
-- `RequestHorsePullDown` is the vanilla action, the same one guards use when
-- they unhorse the player, and it takes the victim's entity id, meaning the
-- person being pulled down. It is offered by the AI's own behavior tree as
-- `HorsePullDownAction`, governed by `wh_cs_HorsePullDownAngle` (55 degrees)
-- and its sibling angle cvars, so it is not available until the NPC has the
-- geometry.
--
-- So this asks repeatedly rather than once, from the moment the fight starts,
-- until the player is down. Nothing is forced: if the geometry never comes
-- the request is never made and the brawl proceeds without the pull.
--
-- A rider already on the ground is the other reason to stop, and it is the
-- common one, since the whole point is that this happens early.
--
-- Returns whether it has taken responsibility for starting the fight. When it
-- has, the caller must not release the offense: this does it once the player is
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

	local pollMs = self.Config.PullDownPollMs
	local ceilingMs = self.Config.PullDownCeilingMs
	local generation = self.TimerTick
	local startedAt = self:TimeMs()
	local polls = 0
	local bestCan = 0

	local function attempt()
		if generation ~= self.TimerTick then
			return
		end

		local stillMounted = false

		pcall(function()
			stillMounted = player.human:IsMounted()
		end)

		local elapsed = self:TimeMs() - startedAt

		if not stillMounted or elapsed >= ceilingMs then
			if self.Config.LogTelemetry then
				-- What the victim looked like when the pull ended.
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
						.. " done why=" .. (stillMounted and "ceiling" or "dismounted")
						.. " atMs=" .. string.format("%.0f", elapsed)
						.. " polls=" .. tostring(polls)
						.. " bestCan=" .. tostring(bestCan)
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

		pcall(function()
			can = npc.actor:CanHorsePullDown(player.id) or 0
		end)

		polls = polls + 1

		if can > bestCan then
			bestCan = can
		end

		-- `CanHorsePullDown` returns an HPS status: 2 enabled, 1 disabled and
		-- 0 not applicable, which some victims answer at every angle and
		-- distance. `PullDownForce` requests regardless of the answer.
		if can ~= 0 or self.Config.PullDownForce then
			local ok = pcall(function()
				npc.actor:RequestHorsePullDown(player.id)
			end)

			if self.Config.LogTelemetry then
				self:Log("PullDown " .. self:NameOf(npc)
						.. " requested can=" .. tostring(can)
						.. " ok=" .. tostring(ok)
						.. " atMs=" .. string.format("%.0f", elapsed))
			end

			-- Asked again on a slow cadence until the player is actually
			-- down. The request is accepted immediately but the brain runs
			-- it when it is ready, and without the offense released there is
			-- little for it to be busy with, so this is a safety net rather
			-- than the mechanism.
			Script.SetTimer(self.Config.PullDownRepeatMs, attempt)

			return
		end

		Script.SetTimer(pollMs, attempt)
	end

	attempt()

	return true
end
