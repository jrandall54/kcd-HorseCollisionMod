--- Spoken reactions to what the horse does.
--
-- Makes a victim, a bystander or Henry say a vanilla line at a moment the mod
-- causes. No new audio ships: every line is already in the game, spoken by the
-- character's own voice actor, and is selected by naming a **metarole**, which
-- is a named bark set.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- ## Why metarole and not anything else
--
-- `dialog:monologRequest` accepts four ways of naming what to say and only one
-- of them is usable here. Measured in game, not assumed:
--
--     metarole      works, and reaches the generic reaction sets
--     alias         works, but every label vanilla exposes is quest scoped
--     topicId       does not work at all from Lua
--     StartMonolog  does not work, proven against alias on one speaker
--
-- The consequence to keep in mind while reading the tables below is that **the
-- set is chosen, not the line**. The dialog system picks which line of a set
-- plays, so every entry here has to be acceptable in all of its variants.
--
-- ## What a set has to pass to be used here
--
-- Four tests:
--
-- 1. **It must be able to play.** Anything named `COMBAT_` speaks only from
--    combat, and a trampled townsman is not in combat. More generally, a
--    metarole that describes a state is silent outside that state.
-- 2. **Every member must be bark-length.** The set is chosen and the dialog
--    system picks the line, so one story monolog in an otherwise good set
--    poisons every firing.
-- 3. **Most members must carry a word.** Vanilla's lightest sets are mostly
--    the wordless marker `<...>`, which reads as the mod mumbling.
-- 4. **Vanilla must not couple the line to a behavior.** The corpse sets are
--    the audible part of a scripted flee-and-fetch-a-guard reaction, and
--    firing the audio alone produces an NPC who announces a body and strolls
--    on.
--
-- `tools/bark_lines.py` answers 2 and 3 offline. Only an audition answers 1,
-- and only watching vanilla answers 4.
--
-- The vanilla `KOLIZE_*` collision sets are pooled with the mod's own finds,
-- because `HushVanillaBark` keeps vanilla from playing them itself.
--
-- @module HorseCollisionMod.Bark
-- @author jrandall54

-- The bark sets, by the moment that causes them.
--
-- An ordinary comment rather than an LDoc block: LDoc reads an annotated table
-- as a set of named fields and refuses one carrying array entries, which every
-- weighted pool below is.
--
-- An entry is either one metarole name or a **weighted pool** written as a
-- list of `{ metarole, weight }` pairs, from which one is drawn per firing.
--
-- Pools exist because the dialog system chooses the line and the mod only
-- chooses the set. One set per moment means one bad member poisons every
-- firing of that moment, and it means the same voice every time. Drawing from
-- a pool spreads the risk and widens the palette without needing new audio.
HorseCollisionMod.BarkSets = {
	-- What a victim says about being shoved aside, at a walk and again once
	-- they have picked themselves up from a harder hit.
	--
	-- ZASAH_ZBRANI_IGNOROVANY escalates across repeated provocation, which is
	-- the shape of a rider shoving somebody more than once:
	--   "What the fuck are you doing!?"  "Have you lost your mind?"
	--   "Right, try that one more time and see what happens..."
	-- KOLIZE_S_HRACEM is vanilla's on-foot collision set, every line short:
	--   "Be a bit more careful!"  "Hey! Watch it!"  "Jesus! Look where you're going!"
	--   and a set of monk variants: "Slow down, brother!"  "In a rush to pray?"
	Shove = {
		{ "ZASAH_ZBRANI_IGNOROVANY", 3 },
		{ "KOLIZE_S_HRACEM",         3 }
	},

	-- What a victim says once they are back on their feet after being ridden
	-- down. Weighted towards the mounted set, because it is the only writing
	-- in the game that names the horse, and the player having just trampled
	-- them is the whole point of the line:
	--   "Learn how to ride a horse, idiot!"
	--   "Watch where you're going, you lout! You nearly killed me!"
	--   "That horse of yours nearly trampled me to death!"
	Ridden = {
		{ "KOLIZE_S_HRACEM_NA_KONI", 4 },
		{ "ZASAH_ZBRANI_IGNOROVANY", 2 },
		{ "KOLIZE_S_HRACEM",         1 }
	},

	-- Territorial. A horse standing over someone is an intrusion.
	--   "Hey, what are you doing here? Clear off quick"
	Loom = "KOMENTAR_NA_INTRUZI",

	-- Terror. For a rear in someone's face and for a charge.
	--   "Christ almighty!"  "Mother of God!"  "Aaaaaaaah!"
	--   "Please, someone! Do something!"
	Panic = "NASILI_UTEK",

	-- Startled, for a near miss that does no harm.
	--   "What in the -?"  "Who's there?"  "Jesus!"
	Startle = "KDO_TAM_CITOSLOVCE",

	-- Wordless pain, no subtitle. `HurtDown` is the cry at the moment of
	-- impact; the words come later, once the victim is up. `HurtLight` and
	-- `HurtHard` name where vanilla's graded recordings live, and a bark
	-- request cannot reach them (see `PainByTier`).
	--   HurtLight  "Uhh!"  "Ech!"  "Ow!"
	--   HurtHard   "Aaaaah!"  "Yow!"  "Enhhhh!"
	--   HurtDown   "Aaaah... dear God..."  "Christ!"
	HurtLight = "ZASAH_ZBRANI_SLABY",
	HurtHard  = "ZASAH_ZBRANI_SILNY",
	HurtDown  = "RANENY_NA_ZEMI",

	-- The corpse sets `UVIDI_MRTVOLU`, `VOLANI_STRAZE_MRTVOLA` and
	-- `REAKCE_NA_VRAZDU` are excluded by test 4 in the module header.
}

--- Lines Henry says on an impact, addressed by dialog `alias`, drawn as one
-- weighted pool (`{ name, weight }`, read by `PickFromPool`) whatever the tier.
--
-- Empty on purpose. An impact gets `PlayRiderVocal`'s wordless grunt; the lines
-- Henry can speak are sentences, and sentences belong to kills
-- (`RiderBarkKillAliases`). The pool and `RiderBark`, which defaults to false,
-- are kept so a line can be added without restructuring.
--
-- An entry must pass four filters, which `tools/henry_impact_lines.py` applies:
--
-- 1. `topic2sequence.entry_condition` is `'1'`, always-true. A quest condition
--    refuses silently.
-- 2. `sequence.timeout` is not `-1`, which allows one use per playthrough.
-- 3. The shipped audio carries exactly one actor, Henry's. Two actors is a
--    conversation; no audio is a line that cannot be heard.
-- 4. Every member of the topic fits, since the dialog system picks the member.
--
-- Passing the filters does not prove a line is audible. Fire a candidate in
-- game and hear it, more than once, before adding it.
--
-- @table RiderBarkAliases
HorseCollisionMod.RiderBarkAliases = {}

-- Henry's lines for an impact that killed, drawn on instead of the impact pool.
--
-- An ordinary comment rather than an LDoc block: LDoc reads an annotated table
-- as a set of named fields and refuses an array of entries.
--
-- A death is the one moment in the mod worth a distinct reaction, so it gets a
-- distinct pool rather than a weight inside the ordinary one. Every member
-- passes the four filters described above the impact pool, and its full text
-- is printed beside it. A third column restricts a line to one gender of
-- victim; see `PoolForVictim`.
HorseCollisionMod.RiderBarkKillAliases = {
	{ "revelation_murderer_ohfuck", 1 },                   -- "Oh fuck!"
	{ "q_rides_traitor_henry_trail_skirt", 1, "f" },       -- "Shameless hussy!"
	-- "How could anyone be so cruel?"
	{ "q_massacre_deadPeasasnt", 1 },
	-- "Jesus, something stinks here!"
	{ "revelation_murderer_smell", 1 },
	-- "Good God, what a bloody mess."
	{ "q_counterfeiters_crimeScene_area", 1 },
	-- "Fuck, the alarm's been sounded!"
	{ "q_night_rescue_alarmHenry", 1 },
	-- "It started getting interesting here."
	{ "q_rides_traitor_henry_trail_shirt", 1 },
	-- "Jesus Christ, he was only a boy."
	{ "revelation_murderer_trigger_caveBody4", 1, "m" },
	-- "Poor wretch. What did he do to deserve such a fate?"
	{ "revelation_murderer_trigger_caveBody5", 1, "m" },
	-- "This one won't be going anywhere any time soon."
	{ "q_counterfeiters_crimeScene_brokenWheel", 1 },
	-- "He's still breathing but he probably won't wake up again."
	{ "player_examineInjuredWorker", 1, "m" },
	-- "...no better than that bastard Zbyshek."
	{ "q_returnToSkalitz_butcher_stolenGoods", 1 },
	-- "And now to get away quickly before anyone catches me here."
	{ "q_libri_prohibiti_henry_shouldBeLeaving", 1 },
	-- "There! They won't be pulling anything for a few days. Except long faces!"
	{ "q_execExec_troughBarkDone", 1 },
}

--- The subset of a pool whose lines suit this victim.
--
-- A pool entry may carry a third field naming the only gender of victim the line
-- fits, `"m"` or `"f"`, and none on a line that fits either. Lines that name the
-- body, such as "he was only a boy" or "shameless hussy", read as the mod
-- describing someone who is not there when they land on the wrong victim.
--
-- Returns the pool unchanged when the victim's gender cannot be read, because a
-- line is better than silence and an unreadable soul is not evidence of anything.
--
-- @tparam table pool a `{ name, weight, gender }` list
-- @tparam ?table npc the victim
-- @treturn table a pool holding only the entries that fit
function HorseCollisionMod:PoolForVictim(pool, npc)
	if type(pool) ~= "table" then
		return pool
	end

	local gender = nil

	if npc and npc.soul then
		pcall(function()
			gender = npc.soul:GetGender()
		end)
	end

	local wanted = nil

	if gender == self.GenderMale then
		wanted = "m"
	elseif gender == self.GenderFemale then
		wanted = "f"
	else
		return pool
	end

	local fits = {}

	for _, entry in ipairs(pool) do
		if entry[3] == nil or entry[3] == wanted then
			fits[#fits + 1] = entry
		end
	end

	if #fits == 0 then
		return pool
	end

	return fits
end

--- Whether Henry is free to speak, or still inside a hold from his last sound.
--
-- One gate for words and breath alike, because both come out of Henry and two
-- at once is a defect rather than a richer moment.
--
-- A hold further out than the longest cooldown means the save clock was wound
-- back by a load; it is ignored.
--
-- Ranked, so that the more important sound wins a contest rather than whichever
-- was asked first: a grunt at its `RiderVocalRankByTier`, then an impact line,
-- then a line about a death, so a grunt at the contact cannot silence a kill
-- line.
--
-- Equal rank still loses, so two death lines do not talk over each other.
--
-- @tparam ?number rank what is asking, defaulting to the lowest
-- @treturn boolean true when nothing of equal or greater weight is holding him
function HorseCollisionMod:RiderVoiceReady(rank)
	return self:VoiceGateOpen(self:RiderVoiceGate(), rank)
end

--- Henry's voice gate, as `VoiceGateOpen` and `PlayGatedVocal` read it.
--
-- `cooldown` is the grunt's hold; a spoken line stamps its own.
--
-- @treturn table the gate
function HorseCollisionMod:RiderVoiceGate()
	local cfg = self.Config

	return {
		name = "RiderVocal",
		untilKey = "RiderVoiceUntil",
		rankKey = "RiderVoiceRank",
		cooldown = cfg.RiderVocalCooldownMs,
		longest = math.max(cfg.RiderBarkCooldownMs, cfg.RiderVocalCooldownMs),
	}
end

--- Whether a ranked voice gate lets a sound through.
--
-- A gate is a hold stamped on this table: `untilKey` names the field holding
-- when it ends and `rankKey` the rank that set it. A sound of higher rank
-- passes a hold; equal or lower is refused. A hold further out than
-- `longest`, the longest the gate can legitimately carry, means the save
-- clock was wound back by a load, and it is ignored.
--
-- @tparam table gate `untilKey`, `rankKey` and `longest`
-- @tparam ?number rank what is asking, defaulting to the lowest
-- @treturn boolean true when nothing of equal or greater weight is holding it
function HorseCollisionMod:VoiceGateOpen(gate, rank)
	local now = self:TimeMs()
	local until_ = self[gate.untilKey] or 0

	if (until_ - now) > gate.longest or now >= until_ then
		return true
	end

	return (rank or 0) > (self[gate.rankKey] or 0)
end

--- What each kind of spoken line out of Henry is worth against the others,
-- above every grunt's `RiderVocalRankByTier`.
--
-- @table RiderVoiceRanks
HorseCollisionMod.RiderVoiceRanks = { Impact = 4, Killed = 5 }

--- Henry says something about the impact, drawn from `RiderBarkAliases`.
--
-- Sent on the same message as every other bark, with `alias` in place of
-- `metarole`. Nothing else about the dispatch differs, so the priority and
-- suppression settings that were tuned for the victim's lines apply unchanged.
--
-- ### Why this cannot run alongside the grunt
--
-- `PlayRiderVocal` already puts a wordless grunt on every impact, and the two
-- share one gate (`RiderVoiceReady`): a line that goes out stamps Henry's
-- voice clock at a rank above the grunt,
-- which suppresses the grunt for the length of `RiderBarkCooldownMs`. The two
-- are therefore alternatives on any given impact, and `RiderBarkChance` decides
-- how often Henry uses words instead of breath.
--
-- The stamp is taken when the request is *sent*, not when a sound arrives,
-- because the dialog system reports nothing back. That is the same caution the
-- log line below carries: a mod-written line is evidence the mod asked, never
-- evidence the game answered.
--
-- @tparam table playerEnt the player entity
-- @tparam string tierName the impact tier, for the telemetry only
-- @treturn boolean true when a request was sent
function HorseCollisionMod:BarkRiderImpact(playerEnt, tierName)
	local cfg = self.Config

	if not cfg.RiderBark or not playerEnt then
		return false
	end

	if not self:RiderVoiceReady(self.RiderVoiceRanks.Impact) then
		return false
	end

	-- Rolled after the cooldown so a losing roll does not start one, which
	-- would silence the following impact as well.
	if math.random() >= cfg.RiderBarkChance then
		return false
	end

	return self:SendRiderAlias(playerEnt, self.RiderBarkAliases, tierName,
			self.RiderVoiceRanks.Impact)
end

--- Sends one line from a pool as Henry, and takes the voice gate on success.
--
-- The dispatch shared by every spoken line Henry has: the impact pool and
-- the kill pool differ only in which pool they draw from and what the telemetry
-- calls the moment. Both stamp the same clock, because there is one Henry.
--
-- Deliberately does not test the cooldown or the chance. Those belong to the
-- caller: an ordinary impact rolls against `RiderBarkChance` and a kill does
-- not, since a death is rare enough to be worth a line every time.
--
-- @tparam table playerEnt the player entity
-- @tparam table pool a `{ name, weight }` list for `PickFromPool`
-- @tparam string tag what to call this in the log
-- @tparam number rank what this sound is worth, from `RiderVoiceRanks`
-- @treturn boolean true when a request was sent
function HorseCollisionMod:SendRiderAlias(playerEnt, pool, tag, rank)
	local cfg = self.Config
	local alias = self:PickFromPool(pool)

	if not alias then
		return false
	end

	local target = playerEnt.id

	if playerEnt.this and playerEnt.this.id then
		target = playerEnt.this.id
	end

	local fields = {
		alias = alias,
		forceOnMuted = true,
		priority = cfg.RiderBarkPriority or cfg.BarkPriority,
		canBeDelayed = cfg.BarkCanBeDelayed == true,
		overrideContextSuppress = cfg.BarkOverrideSuppress == true
	}

	local ok, err = pcall(function()
		XGenAIModule.SendMessageToEntityData(target, "dialog:monologRequest",
				Utils.makeTable("dialog:monologRequest", fields))
	end)

	if ok then
		-- Both spoken ranks sit above every grunt, so no breath follows a line
		-- inside the hold, and a death line can still cut across an impact one.
		self.RiderVoiceUntil = self:TimeMs() + cfg.RiderBarkCooldownMs
		self.RiderVoiceRank = rank or self.RiderVoiceRanks.Impact
	end

	self:Log("RiderBark tier=" .. tostring(tag)
			.. " alias=" .. alias
			.. " target=" .. tostring(target)
			.. " prio=" .. tostring(fields.priority)
			.. " sent=" .. tostring(ok)
			.. (ok and "" or (" err=" .. tostring(err))))

	return ok
end

--- Chooses Henry's spoken line at the moment of contact.
--
-- `fatal` comes from `PredictImpactFatal` rather than from the victim's actual
-- state, and that is the point. The real death is not settled until the thrown
-- body has come to rest and the mod's deferred damage lands, up to a second and
-- a half later, so a line chosen from it arrives long after the collision it is
-- about. Predicting the outcome from the same arithmetic lets the words land
-- with the impact.
--
-- A death always gets a line and never rolls against `RiderBarkChance`: a
-- collision that kills is rare enough to be worth hearing every time, and the
-- ordinary impact line is skipped rather than competing with it.
--
-- @tparam table playerEnt the player entity
-- @tparam string tierName the impact tier, for the telemetry
-- @tparam boolean fatal whether this impact is expected to kill
-- @tparam ?table npc the victim, so a gendered line is not misplaced
-- @treturn boolean true when a request was sent
function HorseCollisionMod:BarkRiderOnImpact(playerEnt, tierName, fatal, npc)
	if not fatal then
		return self:BarkRiderImpact(playerEnt, tierName)
	end

	if not self.Config.RiderBarkKill then
		return false
	end

	-- Logged rather than returned silently, because every way a death can fail
	-- to produce a line looks identical from the saddle. A kill with no line in
	-- the log at all means the death was not predicted; this names the other two
	-- reasons.
	if not self:RiderVoiceReady(self.RiderVoiceRanks.Killed) then
		self:Log("RiderBark tier=Killed skipped=cooldown"
				.. " held=" .. tostring(self.RiderVoiceRank or 0)
				.. " forMs=" .. tostring((self.RiderVoiceUntil or 0) - self:TimeMs()))

		return false
	end

	local pool = self:PoolForVictim(self.RiderBarkKillAliases, npc)

	if #pool == 0 then
		self:Log("RiderBark tier=Killed skipped=no-line-fits-this-victim")

		return false
	end

	return self:SendRiderAlias(playerEnt, pool, "Killed",
			self.RiderVoiceRanks.Killed)
end

-- The wordless pain set an impact at each tier makes.
--
-- Walk and the rear are absent: a shove does not hurt, and the victim goes
-- straight to words.
--
-- Every tier here uses `HurtDown`, the one pain set a bark request can reach.
-- `HurtLight` and `HurtHard` name `ZASAH_ZBRANI_SLABY` and
-- `ZASAH_ZBRANI_SILNY`, two of the metaroles registered in
-- `Libs/Tables/rpg/combat_shout_type.xml`: those are dispatched by the combat
-- shout system rather than by `dialog:monologRequest`, and their entry
-- conditions read `var('hitStrength')`, which the engine hangs on its own
-- `CombatShout_*` request rather than on the character, so no state a mod can
-- set satisfies them.
HorseCollisionMod.PainByTier = {
	Trot   = "HurtDown",
	Gallop = "HurtDown",
	Charge = "HurtDown"
}

--- Whether a bark may be raised at all right now.
--
-- Two gates, deliberately separate. The feature has its own switch so it can
-- be turned off without touching anything else, and each pillar has its own,
-- because the collision reactions and the rear are independent mechanics and
-- one must never silently carry the other's setting.
--
-- @tparam string pillar "Collision" or "Rear"
-- @treturn boolean true when barks are allowed for that pillar
function HorseCollisionMod:BarksEnabled(pillar)
	local cfg = self.Config

	if not cfg.Barks then
		return false
	end

	if pillar == "Rear" then
		return cfg.RearBarks ~= false
	end

	return cfg.CollisionBarks ~= false
end

--- Draws one metarole from a bark set entry.
--
-- An entry is either a plain metarole name, which is returned as it stands, or
-- a weighted pool written as `{ { name, weight }, ... }`. Weights are relative
-- and need not sum to anything; a pool of `{a,3},{b,1}` speaks `a` three times
-- as often as `b`.
--
-- Kept separate from `Bark` so that a pool can be drawn from and inspected
-- without sending anything.
--
-- @tparam ?string|table entry a metarole name, a weighted pool, or nil
-- @treturn ?string the metarole to speak, or nil when the entry is empty
function HorseCollisionMod:PickFromPool(entry)
	if type(entry) == "string" then
		return entry
	end

	if type(entry) ~= "table" or #entry == 0 then
		return nil
	end

	local total = 0

	for _, option in ipairs(entry) do
		total = total + (option[2] or 1)
	end

	if total <= 0 then
		return nil
	end

	local roll = math.random() * total

	for _, option in ipairs(entry) do
		roll = roll - (option[2] or 1)

		if roll <= 0 then
			return option[1]
		end
	end

	-- Floating point can leave the roll a hair above zero after the last
	-- subtraction. Falling back to the final option is correct rather than
	-- merely safe: that is the bucket the roll landed in.
	return entry[#entry][1]
end

--- Whether this speaker has said something recently enough to stay quiet.
--
-- Without this a rider working through a crowd produces a chorus, and a single
-- victim struck twice talks over their own first line. Tracked per entity
-- rather than globally so two different people can react to the same event.
--
-- @tparam table entity the prospective speaker
-- @treturn boolean true when they are still inside their cooldown
function HorseCollisionMod:BarkOnCooldown(entity)
	local id = tostring(entity and entity.id or "?")
	local now = self:TimeMs()
	local last = self.RecentBarks[id]

	if last and (now - last) < self.Config.BarkCooldownMs then
		-- Logged, so a silent second shove can be told from a missed impact.
		if self.Config.LogTelemetry then
			self:Log("BarkCooldown " .. self:NameOf(entity)
					.. " silent for another "
					.. tostring(self.Config.BarkCooldownMs
							- (now - last)) .. "ms")
		end

		return true
	end

	self.RecentBarks[id] = now

	return false
end

--- Asks a character to speak one of a named bark set.
--
-- `Utils.makeTable` builds the message from its declared type, filling every
-- member. A hand-built table leaves the receiving node with nothing to match
-- on and is accepted in silence.
--
-- The target is `npc.this.id` where it exists. That is what every message this
-- mod successfully lands on an NPC already uses, and vanilla addresses the
-- player the same way in `DialogUtils.RequestPlayerMonologByMetarole`.
--
-- `overrideContextSuppress` clears the `suppressMonologs` gate that
-- `monologRequestExecution` checks in `final/sb_dialog.xml`, which otherwise
-- discards the request outright. `forceOnMuted` covers a muted speaker.
--
-- Subtitles are deliberately **not** forced. Vanilla barks do not carry them
-- unless the player has them on, and forcing them would make the mod's lines
-- look different from the game's own.
--
-- Failure is silent by design: a character whose voice never recorded the set
-- says nothing, with no error and no glitch, exactly as in vanilla.
--
-- @tparam table entity who should speak
-- @tparam string set a key of `BarkSets`
-- @tparam ?boolean ignoreCooldown true to speak even inside the speaker's
--   cooldown, for a line deliberately sequenced after another; it still
--   stamps the clock
-- @tparam ?number priority the rank to send at, in place of `BarkPriority`
-- @tparam ?boolean overrideSuppress true to ignore a `suppressMonologs`
--   context whatever `BarkOverrideSuppress` says
-- @treturn boolean true when a request was sent
function HorseCollisionMod:Bark(entity, set, ignoreCooldown,
		priority, overrideSuppress)
	if not entity then
		return false
	end

	local metarole = self:PickFromPool(self.BarkSets[set])

	if not metarole then
		return false
	end

	-- A line sequenced after another, such as the recovery line after the
	-- cry of pain, must not be refused by the cooldown the first started. It
	-- still stamps the clock, so a second impact is governed normally.
	if ignoreCooldown then
		self.RecentBarks[tostring(entity.id or "?")] = self:TimeMs()
	elseif self:BarkOnCooldown(entity) then
		return false
	end

	local target = entity.id

	if entity.this and entity.this.id then
		target = entity.this.id
	end

	local name = self:NameOf(entity)

	-- Vanilla's collision bark is not dealt with here. `HushVanillaBark` has
	-- already closed that branch while the victim was still in front of the
	-- horse, which is the only way to win the race against the engine raising
	-- its own hit reaction the moment bodies touch.
	--
	-- Doing it here as well would also mean two writers sharing one context
	-- handle, where whichever timer expired first would hand vanilla's bark back
	-- while the other still believed it was suppressed.

	-- The message fields that matter are read from settings, so they can be
	-- changed in a running game.
	--
	-- `priority` is the one that matters most. Requests register their
	-- priority in a shared array which `monologRequestProcess` sorts
	-- descending, and a request below the top either waits, when
	-- `canBeDelayed` is set, or is discarded with no error. At the default of
	-- zero this mod loses every contest it enters.
	local cfg = self.Config
	local fields = {
		metarole = metarole,
		forceOnMuted = true,
		-- A caller may outbid the shipped rank for a line that has to be
		-- heard over whatever the speaker's own brain is saying at the time.
		-- The fear scream is the case: it is spoken by someone in the middle
		-- of running away, and running away has lines of its own.
		priority = priority or cfg.BarkPriority,
		canBeDelayed = cfg.BarkCanBeDelayed == true,
		-- Likewise overridable per call. Someone running for their life is
		-- inside a brain that raises `suppressMonologs` on itself, and a request
		-- that does not say it outranks that context is discarded with no
		-- error, exactly as a losing bid is.
		overrideContextSuppress = overrideSuppress == true
				or cfg.BarkOverrideSuppress == true
	}

	local ok, err = pcall(function()
		XGenAIModule.SendMessageToEntityData(target, "dialog:monologRequest",
				Utils.makeTable("dialog:monologRequest", fields))
	end)

	-- `ok` says the send did not raise, and nothing more. Whether a sound
	-- follows is decided inside the dialog system, which reports nothing back:
	-- a speaker whose voice never recorded the set, or who is not in the state
	-- the set describes, is silent with no error. So this line is evidence the
	-- mod asked, never evidence the game answered, and it must never be read
	-- as "the bark fired".
	self:Log("Bark " .. set .. "=" .. metarole .. " to " .. name
			.. " target=" .. tostring(target)
			.. " prio=" .. tostring(fields.priority)
			.. " delay=" .. tostring(fields.canBeDelayed)
			.. " override=" .. tostring(fields.overrideContextSuppress)
			.. " sent=" .. tostring(ok)
			.. (ok and "" or (" err=" .. tostring(err))))

	return ok
end

--- The bark set an impact at this tier should raise at the moment of contact.
--
-- A walk shoves, which does not hurt, so the victim goes straight to words.
-- A tier in `PainByTier` knocks them down, and what comes out at the moment
-- of impact is a wordless cry. Their words come later, from `BarkRecovered`,
-- once they are back on their feet.
--
-- @tparam string tier "Walk", "Trot", "Gallop" or "Charge"
-- @treturn ?string a key of `BarkSets`, or nil when nothing should be said
function HorseCollisionMod:BarkForTier(tier)
	if tier == "Walk" then
		return "Shove"
	end

	return self.PainByTier[tier]
end

--- Speaks for a collision, at the moment of contact.
--
-- A walk speaks words straight away. A knockdown cries out here and says
-- something later, from `BarkRecovered`, which this schedules.
--
-- Refused outright during a fight, matching vanilla.
--
-- @tparam table npc the victim
-- @tparam string tier the speed tier the impact was scored at
-- @tparam ?boolean inCombat true when the player is in combat, which silences
--   the whole moment unless `BarkInCombat` says otherwise
function HorseCollisionMod:BarkCollision(npc, tier, inCombat)
	if not self:BarksEnabled("Collision") then
		return
	end

	-- Vanilla gates its entire collision bark branch on
	-- `!$b_inCombat & !$b_context['suppressCollisionsBark']`, at
	-- `sb_switch_hitreactions.xml:293`. `HushVanillaBark` supplies the second
	-- half, which is how the mod takes the line over outside a fight; this is
	-- the first: someone in a fight does not remark on being bumped.
	if inCombat and self.Config.BarkInCombat ~= true then
		if self.Config.LogTelemetry then
			self:Log("BarkCollision " .. self:NameOf(npc) .. " skipped, in combat")
		end

		return
	end

	local set = self:BarkForTier(tier)

	if set then
		self:Bark(npc, set)
	end

	-- The knockdown tiers speak twice: this cry of pain, and words while they
	-- are getting up. `BarkRecovered` filters the tier and schedules its own
	-- delay, so it is called unconditionally here.
	self:BarkRecovered(npc, tier)
end

--- Speaks for a victim who is getting back to their feet.
--
-- Without it a knocked-down victim cries out on impact, stands up and walks
-- off without a word about what happened.
--
-- **Fired when the body begins to rise**, a moment inside the get-up rather
-- than at either end of it. No animation state marks it, and a delay from
-- the impact cannot, because a get-up is not one length. `WhenVictimRises`
-- reads it: the head height for a fall, the ragdoll state for a throw.
--
-- @tparam table npc the victim
-- @tparam string tier the speed tier the impact was scored at
function HorseCollisionMod:BarkRecovered(npc, tier)
	if not self:BarksEnabled("Collision") then
		return
	end

	if self.Config.BarkOnRecovery == false then
		return
	end

	-- Only the tiers that answer with the collision voice and put somebody on
	-- the ground. A shove has no knockdown to recover from and already spoke
	-- at the moment of contact, and the rear has a voice of its own.
	if self:TierValue("VictimBarkByTier", tier) ~= "collision" then
		return
	end

	if self:TierValue("ReactionByTier", tier) == "stagger" then
		return
	end

	if not npc or not npc.soul then
		return
	end

	local generation = self.TimerTick

	-- A body is flat from about 1.8 s and starts rising anywhere from there
	-- to past 7 s, depending on the fall and the character set.
	self:WhenVictimRises(npc, function(why, waited)
		if generation ~= self.TimerTick then
			return
		end

		if self.Config.LogTelemetry then
			self:Log("BarkRecovered " .. self:NameOf(npc)
					.. " on=" .. tostring(why)
					.. " waited=" .. tostring(waited) .. "ms")
		end

		-- A victim the impact killed is not getting up and does not speak.
		local ok, health = pcall(function()
			return npc.soul:GetState("health")
		end)

		if ok and type(health) == "number" and health <= 0 then
			return
		end

		-- The cry of pain this line is sequenced behind started the speaker's
		-- cooldown, so the cooldown is bypassed; `BarkGapMs` is what keeps the
		-- two from overlapping, checked here rather than inside `Bark` because
		-- only this caller sequences two lines from one speaker.
		local last = self.RecentBarks[tostring(npc.id or "?")]

		if last and (self:TimeMs() - last) < self.Config.BarkGapMs then
			if self.Config.LogTelemetry then
				self:Log("BarkRecovered " .. self:NameOf(npc)
						.. " skipped, only " .. tostring(self:TimeMs() - last)
						.. "ms since their last line")
			end

			return
		end

		self:Bark(npc, "Ridden", true)
	end)
end

--- Speaks for a rear, its own pillar with its own switch.
--
-- @tparam ?table npc whoever the rear was aimed at or struck, may be nil
-- @tparam boolean struck true when contact was actually made
function HorseCollisionMod:BarkRear(npc, struck)
	if not self:BarksEnabled("Rear") then
		return
	end

	if not npc then
		return
	end

	self:Bark(npc, struck and "Panic" or "Startle")
end

--- Switches off vanilla's collision bark on somebody near the horse.
--
-- Per impact suppression loses a race it cannot win. The mod's detection loop
-- runs about thirty times a second, while the engine raises its own hit
-- reaction the instant bodies touch, so vanilla's line can already be playing
-- before the tick that would have silenced it.
--
-- Setting the option while the victim is still in front of the horse removes
-- the race: by the time contact happens the branch is already closed. It is
-- refreshed every half `BarkSuppressMs` rather than set every tick, because a
-- context write every tick per nearby person is not free.
--
-- Cleared on a timer well after the impact, so an NPC the player passes without
-- touching gets their own bark back a moment later and nothing is permanently
-- changed. Non-persistent, so a save cannot carry it.
--
-- @tparam table npc a human within `HitRadius` of the horse
function HorseCollisionMod:HushVanillaBark(npc)
	if not self:BarksEnabled("Collision") then
		return
	end

	local id = tostring(npc and npc.id or "?")
	local now = self:TimeMs()
	local last = self.RecentHushes[id]
	local window = self.Config.BarkSuppressMs

	if last and (now - last) < (window * 0.5) then
		return
	end

	self.RecentHushes[id] = now

	pcall(function()
		Contexts.SetNonpersistentOption(npc, "suppressCollisionsBark", "hcmBark",
				{ suppressNonexistentHandleError = true })
	end)

	-- A refresh re-arms the hush with a new stamp. Only the timer armed with
	-- the current stamp may clear it, so a superseded timer does nothing.
	Script.SetTimer(window, function()
		if self.RecentHushes[id] ~= now then
			return
		end

		pcall(function()
			Contexts.ClearOption(npc, "suppressCollisionsBark", "hcmBark",
					{ suppressNonexistentHandleError = true })
		end)
	end)
end
