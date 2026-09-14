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
-- Four tests, each of which has already cost a wrong choice:
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
-- The vanilla `KOLIZE_*` collision sets **are** used, which reverses an earlier
-- decision. They were excluded while vanilla still fired its own collision bark
-- on every contact, because driving them would have duplicated what the player
-- already heard. `HushVanillaBark` now closes that branch, so they no longer
-- play on their own and excluding them would simply delete the game's most
-- directly descriptive writing for this exact situation.
--
-- @module HorseCollisionMod.Bark
-- @author jrandall54
-- @release 5.12.2

-- The bark sets, by the moment that causes them.
--
-- Documented as an ordinary comment rather than an LDoc block, for the same
-- reason as `ImpactProbeSamples` in the entry point: LDoc reads an annotated
-- table as a set of named fields and refuses one carrying array entries, which
-- every weighted pool below is.
--
--
-- An entry is either one metarole name or a **weighted pool** written as a
-- list of `{ metarole, weight }` pairs, from which one is drawn per firing.
--
-- Pools exist because the dialog system chooses the line and the mod only
-- chooses the set. One set per moment means one bad member poisons every
-- firing of that moment, and it means the same voice every time. Drawing from
-- a pool spreads the risk and widens the palette without needing new audio.
--
-- The vanilla `KOLIZE_*` collision sets are deliberately **in** these pools.
-- They were excluded while vanilla still fired its own collision bark, because
-- driving them from the mod would have duplicated what the player already
-- heard. `HushVanillaBark` now closes that branch, so those lines no longer
-- play on their own, and they are the most directly descriptive writing the
-- game has for exactly this situation. Excluding them now would delete them.
HorseCollisionMod.BarkSets = {
	-- What a victim says about being shoved aside, at a walk and again once
	-- they have picked themselves up from a harder hit.
	--
	-- ZASAH_ZBRANI_IGNOROVANY is the mod's own find and escalates across
	-- repeated provocation, which is the shape of a rider shoving somebody
	-- more than once:
	--   "What the fuck are you doing!?"  "Have you lost your mind?"
	--   "Right, try that one more time and see what happens..."
	-- KOLIZE_S_HRACEM is vanilla's on-foot collision set, every line short:
	--   "Be a bit more careful!"  "Hey! Watch it!"  "Jesus! Look where you're going!"
	--   and a set of monk variants: "Slow down, brother!"  "In a rush to pray?"
	--
	-- `KOLIZE_S_HRACEM_LEHKA` was in this pool and has been removed. It is
	-- vanilla's *lightest* bump set, and its job there is to be barely
	-- audible: of its 36 entries, 23 carry no word at all, being either the
	-- wordless marker `<...>` or a Hungarian interjection recorded for Cuman
	-- speakers. The rider heard the result as barks that "were just mmm" and
	-- made no sense for being hit by a horse. Measured rather than guessed:
	--
	--     KOLIZE_S_HRACEM_LEHKA     36 entries, 23 with no real word (64%)
	--     KOLIZE_S_HRACEM           35 entries,  1 with no real word (3%)
	--     ZASAH_ZBRANI_IGNOROVANY   14 entries,  0 with no real word
	--
	-- The lesson generalises: read a set's whole contents and count what
	-- carries meaning before pooling it, because the dialog system picks the
	-- line and a set that is mostly grunts will mostly grunt.
	Shove = {
		{ "ZASAH_ZBRANI_IGNOROVANY", 3 },
		{ "KOLIZE_S_HRACEM",         3 }
	},

	-- What a victim says once they are back on their feet after being ridden
	-- down. Weighted towards the mounted set, because it is the only writing
	-- in the game that names the horse, and the rider having just trampled
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

	-- Wordless pain, no subtitle, in three grades. These are what the victim
	-- makes at the moment of impact; the words come later, once they are up.
	--
	-- The grades are real sets and not a volume control: each was written for
	-- a different severity of blow and the recordings differ in kind, not just
	-- in loudness. Several of their members are the literal marker `<...>`,
	-- a grunt the subtitle file cannot render.
	--   HurtLight  "Uhh!"  "Ech!"  "Ow!"
	--   HurtHard   "Aaaaah!"  "Yow!"  "Enhhhh!"
	--   HurtDown   "Aaaah... dear God..."  "Christ!"
	HurtLight = "ZASAH_ZBRANI_SLABY",
	HurtHard  = "ZASAH_ZBRANI_SILNY",
	HurtDown  = "RANENY_NA_ZEMI",

	-- **Deliberately absent: the bystander sets.**
	--
	-- `UVIDI_MRTVOLU` ("Jesus Christ! Murder! Help!"),
	-- `VOLANI_STRAZE_MRTVOLA`, a bystander calling the guards to a body, and
	-- `REAKCE_NA_VRAZDU` were wired here and have been removed.
	--
	-- They played correctly and were still wrong. In vanilla each of those
	-- lines is the audible part of a whole reaction. The NPC notices a body,
	-- panics, runs and fetches a guard, and `dialog:monologRequest` reaches only
	-- the audio. The result was a bystander announcing a corpse and then
	-- strolling on, which reads as a bug rather than a reaction.
	--
	-- Vanilla already fires these at the right moment with the behavior
	-- attached, so the mod has nothing to add and something to break. The sets
	-- worth driving are the ones that are *only* a line.
}

-- Henry's own sets.
--
-- Kept separate because the player is a different speaker with a different
-- voice, and because a line Henry has no recording for is silent however valid
-- the request. These two are confirmed on him.
HorseCollisionMod.RiderBarkSets = {
	-- **Henry is deliberately silent, and this table is deliberately empty.**
	--
	-- `soul:GetRoles()` returns 32 role ids for Henry, and that is his entire
	-- palette. It cannot be widened: `C_ScriptBindSoul` exposes `GetRoles`,
	-- `HasRoleByName`, `GetMetaRoles` and `HasMetaRoleByName`, but no setter
	-- for a role. (`AddMetaRoleByName` exists, returns true and changes
	-- nothing, which is consistent with the metarole not being what is
	-- consulted.)
	--
	-- Of those 32 roles: most carry no recorded lines at all; several are
	-- gated on a state he is never in while riding: hunger, tiredness,
	-- combat, deep water, being too far from the map; two are conversation
	-- roles under the generic `NPC` and `PLAYER` metaroles, which open a
	-- dialogue scene instead of speaking and must never be requested; and
	-- exactly one speaks freely. That one is `JINDRICH_NARAZIL_NA_MRTVOLY`,
	-- whose nine lines are the Skalitz massacre monologs. They name Bianca,
	-- the Bailiff, Deutsch and Henry's parents, and the longest runs 139
	-- characters. The rider rejected it: a story monolog in a bark slot reads
	-- as a bug however well the theme fits.
	--
	-- Ten further candidates were auditioned directly on Henry, through this
	-- same code path, and every one was silent.
	--
	-- The trap that made several of them look like they had worked: `Bark`
	-- writes its log line immediately after the `pcall` that sends the
	-- request, so `Bark Killed=... to Dude` appears whether or not a sound
	-- follows. A mod-written log line is evidence the mod asked, never
	-- evidence the game answered.
	--
	-- **Two assumptions above are untested and must not be treated as facts.**
	-- Whether the "state gate" is real has never been checked by *inducing* a
	-- state and then asking, and whether role membership gates anything rests
	-- on five observations that it does not fully explain. Henry holds
	-- `JINDRICH___UNAVA` and that set was still silent. Both are written up in
	-- `docs/TESTING_DIARY.md` as work for a later branch. If either turns out
	-- differently, Henry's palette may be much larger than this comment says.
}

--- Lines Henry can be made to say on an impact, addressed by `alias`.
--
-- This is the answer to the table above, and it works because the addressing
-- scheme is different rather than because anything about Henry changed.
--
-- `RiderBarkSets` is empty because a **metarole** names a whole bark set and
-- lets the dialog system choose the member, and the only set Henry speaks
-- freely is the Skalitz monologs. An **alias** names one topic, so the wording
-- is nearly pinned: a topic holding a single short line is effectively a line
-- the mod chose.
--
-- ### Where these came from
--
-- The alias namespace was recorded as unrecoverable, on the grounds that a
-- label is only visible where vanilla's AI files happen to reference one. It is
-- a shipped column: `label` in `Libs/Tables/text/topic.xml`, 1656 of them
-- against the 861 those files mention. `tools/bark_alias.py` reads it and
-- `tools/legacy/henry_quips.py` cross-references it with who recorded each line,
-- having the audio is the gate.
--
-- That produced 1076 lines Henry can be asked for, of which the rider chose
-- these. **Theirs to judge, not a filter applied here** -- the survey they picked
-- from was narrowed only by what is mechanically possible.
--
-- ### One flat pool, by instruction
--
-- Every impact draws from the whole list regardless of tier. Per-tier pools were
-- offered and declined:
--
-- > "Just wire them as a random pool that every impact calls from."
--
-- Weights are all 1 for now. `PickFromPool` reads the same
-- `{ name, weight }` shape as the victim pools, so any line can be made rarer
-- without restructuring anything.
--
-- Note that `NPC` and `PLAYER` are absent for a reason given at length above:
-- they are conversation roles, they open a dialogue scene rather than speaking,
-- and 58 further lines the rider liked are reachable by nothing else and so are
-- not reachable at all.
--
-- ### Empty on purpose: an impact is breath, not words
--
-- Every spoken line the mod has belongs to `RiderBarkKillAliases` and fires only
-- when the collision killed somebody. An ordinary impact gets `PlayRiderVocal`'s
-- wordless grunt instead, which is also what the engine itself does for the
-- player: Henry holds the `COMBAT_VICTIM_SCREAM_RECEIVED_HIT` and
-- `COMBAT_ACTOR_SCREAM_ATTACK` metaroles, but neither carries any audio recorded
-- by his actor -- only NPCs' -- so vanilla reaches for an audio trigger for the
-- player's own impact vocals, exactly as this mod does.
--
-- The reason is the length of what is available. Of 1,656 aliases, 173 hold a
-- Henry line on an always-true sequence and 124 survive every usability filter,
-- and the ones that actually speak are sentences. A sentence is right over a
-- body and wrong for a shove, and the short exclamations that would have suited
-- a shove are the ones that do not play.
--
-- The pool and its switch are kept rather than deleted so a line can be put back
-- here without restructuring anything. `RiderBark` defaults to false to match.
--
-- ### What makes a line usable, and why listening was not optional
--
-- Four filters, applied by `tools/henry_impact_lines.py`:
--
-- 1. **`topic2sequence.entry_condition` must be `'1'`**, always-true. A quest
--    condition refuses silently while the mod still logs `sent=true`.
-- 2. **`sequence.timeout` must not be `-1`**, which means usable once per
--    playthrough and then never again.
-- 3. **The shipped audio must exist and carry exactly one actor, Henry's.** The
--    localization paks name every file
--    `<actor>_t<topic>_s<sequence>_<n>_<slug>_<hash>.ogg`, so this is a matter of
--    record. Two actors means a conversation, which is refused or opens a
--    cutscene; no audio at all means a line that has text and no recording.
-- 4. **Every member of the topic must fit**, since the dialog system picks which
--    member plays. A label reading "Oh, shit!" fronted "Shit, where's that
--    damned ring?".
--
-- Passing all four is still not proof a line is audible, so every alias below
-- was fired individually in game and kept only on the rider's word that they
-- heard it. `tools/legacy/make_audition.py` fires one by number for that purpose.
--
-- One caution for anyone auditioning more: a silence observed during that
-- audition turned out not to be reliable, and several lines recorded silent
-- played perfectly when fired again. The cause was never established. So fire a
-- candidate again and hear it before adding it here.
--
-- @table RiderBarkAliases
HorseCollisionMod.RiderBarkAliases = {}

-- Henry's lines for an impact that killed, drawn on instead of the impact pool.
--
-- A third column restricts a line to one gender of victim, `"m"` or `"f"`, and
-- is absent on a line that fits either. Some of these name the body: "he was
-- only a boy", "shameless hussy". Played over the wrong victim they read as the
-- mod talking about someone who is not there.
--
-- An ordinary comment rather than an LDoc block, for the same reason as
-- ImpactProbeSamples above: LDoc reads an annotated table as a set of named
-- fields and refuses an array of entries.
--
-- A death is the one moment in the mod worth a distinct reaction, so it gets a
-- distinct pool rather than a weight inside the ordinary one. Every member is an
-- ungated single-line topic whose full text is printed beside it -- see the two
-- filters described above the impact pool, which apply here identically.
--
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
-- fits, `"m"` or `"f"`. Lines that name the body -- "he was only a boy",
-- "shameless hussy" -- read as the mod describing someone who is not there when
-- they land on the wrong victim, which is what this removes.
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
-- One gate for words and breath alike, because both come out of the same man
-- and two at once is a defect rather than a richer moment.
--
-- A hold further out than any cooldown that can be written was not written
-- against this clock: `System.GetCurrTime` is persisted in the save, so loading
-- an earlier one moves it backwards, and without this the rewind would mute
-- Henry until it had been ridden back through.
--
-- Ranked, so that the more important sound wins a contest rather than whichever
-- was asked first. A grunt is `RiderVoiceGrunt`, an impact line outranks it, and
-- a line about a death outranks both: four gallop kills in quick succession
-- produced one death line and three silences when the gate was rank-blind,
-- because the grunt at each contact had already taken it.
--
-- Equal rank still loses, so two death lines do not talk over each other.
--
-- @tparam ?number rank what is asking, defaulting to the lowest
-- @treturn boolean true when nothing of equal or greater weight is holding him
function HorseCollisionMod:RiderVoiceReady(rank)
	local cfg = self.Config
	local now = self:TimeMs()
	local until_ = self.RiderVoiceUntil or 0
	local longest = math.max(cfg.RiderBarkCooldownMs or 0,
			cfg.RiderVocalCooldownMs or 0)

	if (until_ - now) > longest then
		return true
	end

	if now >= until_ then
		return true
	end

	return (rank or 0) > (self.RiderVoiceRank or 0)
end

--- What each kind of sound out of Henry is worth against the others.
--
-- @table RiderVoiceRanks
HorseCollisionMod.RiderVoiceRanks = { Grunt = 3, Impact = 4, Killed = 5 }

--- Henry says something about the impact, drawn from `RiderBarkAliases`.
--
-- Sent on the same message as every other bark, with `alias` in place of
-- `metarole`. Nothing else about the dispatch differs, so the priority and
-- suppression settings that were tuned for the victim's lines apply unchanged.
--
-- ### Why this cannot run alongside the grunt
--
-- `PlayRiderVocal` already puts a wordless grunt on every impact, and two Henry
-- voices at once is a defect rather than a richer moment. So the two share one
-- gate: a line that goes out stamps the rider's voice clock at the top rank,
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
	if math.random() >= (cfg.RiderBarkChance or 0) then
		return false
	end

	return self:SendRiderAlias(playerEnt, self.RiderBarkAliases, tierName,
			self.RiderVoiceRanks.Impact)
end

--- Sends one line from a pool as Henry, and takes the voice gate on success.
--
-- The dispatch shared by every spoken line the rider has: the impact pool and
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
		priority = cfg.RiderBarkPriority or cfg.BarkPriority or 0,
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
		self.RiderVoiceUntil = self:TimeMs() + (cfg.RiderBarkCooldownMs or 0)
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

-- The wordless pain grade an impact at this tier should make.
--
-- Walk is absent on purpose. A shove at walking pace does not hurt, and the
-- victim goes straight to words.
-- Both tiers use the one pain set that is **proven to speak**, and the graded
-- ladder above it can never be wired in. `HurtLight` and `HurtHard` name
-- `ZASAH_ZBRANI_SLABY` and `ZASAH_ZBRANI_SILNY`, whose metaroles are two of the
-- fifteen registered in `Libs/Tables/rpg/combat_shout_type.xml`: those are
-- dispatched by the combat shout system rather than by `dialog:monologRequest`,
-- so a bark request for one reaches the wrong subsystem entirely. Their entry
-- conditions also read `var('hitStrength')`, which the engine hangs on its own
-- `CombatShout_*` request rather than on the character, so no state a mod can
-- set will satisfy them.
--
-- Both were tested rather than assumed: relaxing the entry condition to `1` and
-- raising `speech_coef` from 0 to 1, through additive table patches the engine
-- confirmed it had applied, left fourteen requests in one ride silent. The two
-- names are kept above because they document where the right recordings live.
HorseCollisionMod.PainByTier = {
	Trot   = "HurtDown",
	Gallop = "HurtDown"
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
-- without sending anything, and because the weighting is the part most likely
-- to be tuned once the rider reports which lines they actually hear.
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
-- rather than globally so two different people can react to the same event,
-- which is the point of having a bystander set at all.
--
-- @tparam table entity the prospective speaker
-- @treturn boolean true when they are still inside their cooldown
function HorseCollisionMod:BarkOnCooldown(entity)
	local id = tostring(entity and entity.id or "?")
	local now = self:TimeMs()
	local last = self.RecentBarks[id]

	if last and (now - last) < (self.Config.BarkCooldownMs or 6000) then
		return true
	end

	self.RecentBarks[id] = now

	return false
end

--- Asks a character to speak one of a named bark set.
--
-- The shape of this call is the whole finding of the investigation behind this
-- file, so it is worth stating precisely why each part is here.
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
-- simply says nothing, with no error and no glitch, exactly as in vanilla.
--
-- @tparam table entity who should speak
-- @tparam string set a key of `BarkSets` or `RiderBarkSets`
-- @tparam ?boolean rider true to read from the rider's table instead
-- @tparam ?boolean ignoreCooldown true to speak even inside the speaker's
--   cooldown, used only for the recovery line that follows a cry of pain
-- @treturn boolean true when a request was sent
function HorseCollisionMod:Bark(entity, set, rider, ignoreCooldown)
	if not entity then
		return false
	end


	local table_ = rider and self.RiderBarkSets or self.BarkSets
	local metarole = self:PickFromPool(table_[set])

	if not metarole then
		return false
	end

	-- The recovery line is deliberately sequenced after the victim's cry of
	-- pain, several seconds later, so it must not be refused by the cooldown
	-- that the cry itself started. It still stamps the clock, so a second
	-- impact is governed normally.
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
	--
	-- Three approaches failed before the pre-emptive one and none should be
	-- retried. Delaying the mod's line by a second made it worse, because vanilla
	-- keeps firing. Setting `suppressMonologs` silenced every line including the
	-- mod's own,
	-- because the gate does not exempt `overrideContextSuppress` the way its
	-- condition reads at a glance. Removing the victim's `KOLIZE_*` metaroles
	-- succeeded, logged as `tookVanilla=3`, and vanilla barked anyway, which is
	-- one more confirmation that holding a metarole is not what decides what is
	-- spoken.
	-- The message carries thirteen fields and this used to send two of them,
	-- one of which vanilla itself uses exactly once. The rest are read from
	-- settings so they can be changed in a running game and compared by ear.
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
		priority = cfg.BarkPriority or 0,
		canBeDelayed = cfg.BarkCanBeDelayed == true,
		overrideContextSuppress = cfg.BarkOverrideSuppress == true
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

--- The bark set an impact at this speed should raise.
--
-- Mirrors `GetSpeedTier` rather than inventing a second set of thresholds, so
-- that what is said always agrees with what the body does.
--
-- A walk shoves, which does not hurt, so the victim goes straight to words.
-- Anything harder knocks them down, and what comes out at the moment of
-- impact is a wordless cry graded by how hard they were hit. Their words come
-- later, from `BarkRecovered`, once they are back on their feet.
--
-- @tparam string tier "Walk", "Trot" or "Gallop"
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
	-- the first half, which the mod had no counterpart for.
	--
	-- The rider heard the gap: a guard already fighting them still stopped to
	-- complain about being ridden into. Vanilla's judgment is that a man in a
	-- fight does not remark on being bumped, and it is followed here rather
	-- than second-guessed.
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
-- The gap this closes: a trot or gallop victim cried out on impact, lay there,
-- stood up and walked off without ever saying a word about what had happened,
-- which reads as the game forgetting rather than as a person recovering.
--
-- **Timed from the impact rather than triggered by standing up.** Two earlier
-- attempts were driven by state and both landed late. `WatchHitReady` requires
-- `HitReadySettleMs` of stillness before it reports, so it could not fire until
-- two seconds after the victim was already upright; and waiting for the
-- animation state to leave `BlendRagdoll` fires only once the get-up has
-- finished. Both left an audible hole, which the rider described as "a large
-- gap between when they actually stand up and then the 2nd line plays".
--
-- A timer is the right instrument here and not a shortcut, because the target
-- is a moment *inside* an animation rather than its end, and no readable state
-- marks it. `BarkRecoveryDelayMs` is tuned by ear against the get-up so the
-- line lands while the victim is rising.
--
-- Walk is excluded: a shove has no knockdown to recover from and already spoke
-- at the moment of contact.
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

	if tier ~= "Trot" and tier ~= "Gallop" then
		return
	end

	if not npc or not npc.soul then
		return
	end

	local generation = self.TimerTick
	local delay = self.Config.BarkRecoveryDelayMs or 3200

	Script.SetTimer(delay, function()
		if generation ~= self.TimerTick then
			return
		end

		-- A victim the impact killed is not getting up, and asking a corpse to
		-- speak is how the death barks ended up firing over silence.
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

		if last and (self:TimeMs() - last) < (self.Config.BarkGapMs or 2500) then
			if self.Config.LogTelemetry then
				self:Log("BarkRecovered " .. self:NameOf(npc)
						.. " skipped, only " .. tostring(self:TimeMs() - last)
						.. "ms since their last line")
			end

			return
		end

		self:Bark(npc, "Ridden", false, true)
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

--- Speaks when the mod's own actions have killed somebody.
--
-- Henry only. The bystander raising the alarm used to fire from here and has
-- been removed: vanilla couples that line to a whole flee-and-fetch-a-guard
-- reaction that the mod cannot reproduce, and it already fires it correctly on
-- its own when a body is found.
--
-- Henry speaks from `RiderBarkKillAliases` here, chosen in `BarkRiderOnImpact`.
-- logs the death and says nothing.
--
-- @tparam table npc the victim who died
function HorseCollisionMod:BarkDeath(npc)
	if not self:BarksEnabled("Collision") then
		return
	end

	if self.Config.RiderBarks == false then
		return
	end

	if not self:Bark(player, "Killed", true) and self.Config.LogTelemetry then
		self:Log("BarkDeath " .. self:NameOf(npc) .. " no rider set wired")
	end
end

--- Makes a victim briefly immortal so the engine's collision damage lands on
-- nothing.
--
-- The engine charges a victim health for being struck by a moving physical
-- body and the mod cannot stop it. Five separate levers leave it unchanged.
-- `BasicActor`'s collision multipliers belong to CryEngine's legacy damage
-- path rather than to the RPG layer that charges `soul` health, and the
-- one parameter that does work, `CollisionVelocityDeltaToDmgR`, is global and
-- also governs arrows.
--
-- So rather than stop the damage, this stops it **landing**. `imm=1` is the
-- parameter behind the game's own `immortality` and `death_protection` buffs,
-- and `immortality_nonpersistent` carries it without being able to survive a
-- save. Applied ahead of contact and removed once the engine has settled, the
-- victim is untouchable for exactly the window the trample occupies, and the
-- mod's own damage lands afterwards on a mortal target.
--
-- **This is deliberately narrow.** It is one buff, on one victim, for a few
-- hundred milliseconds, and it is removed by GUID so nothing of it persists.
--
-- @tparam table npc somebody in front of the horse
function HorseCollisionMod:ShieldFromEngineDamage(npc)
	if not self.Config.ShieldVictimFromEngineDamage or not npc or not npc.soul then
		return
	end

	local id = tostring(npc.id or "?")
	local existing = self.ShieldedVictims[id]

	-- Only a **live** shield blocks a second one. Testing the entry alone was
	-- wrong: a record whose buff has already been removed still reads truthy,
	-- and every later impact on that victim then skipped the shield silently,
	-- with no log line to say so. A victim left at low health by an earlier
	-- impact is exactly who cannot afford that, and one was killed by the
	-- engine on a second gallop having never been shielded for it.
	if existing and not existing.removed then
		return
	end

	-- The instance handle, not the GUID, is what gets handed back later.
	--
	-- `RemoveAllBuffsByGuid` would strip **every** instance of this buff from
	-- the victim, and immortality is exactly what a quest uses to keep a story
	-- character alive. Shielding such a character and then clearing by GUID
	-- would quietly remove protection this mod never granted. Removing the
	-- single instance that was added cannot.
	local ok, instance = pcall(function()
		return npc.soul:AddBuff(self.ImmortalityBuffGuid)
	end)

	if not ok or instance == nil then
		self.ShieldedVictims[id] = nil

		if self.Config.LogTelemetry then
			self:Log("Shield failed on " .. self:NameOf(npc))
		end

		return
	end

	-- Held in a record rather than bare, so the backstop timer can close over
	-- it. A script reload replaces the whole `HorseCollisionMod` table and with
	-- it this map, and the one thing that must survive a reload is the removal.
	-- A closure survives; a table lookup does not.
	local state = { instance = instance, removed = false }
	self.ShieldedVictims[id] = state

	if self.Config.LogTelemetry then
		self:Log("Shield on " .. self:NameOf(npc) .. " ok=true")
	end

	-- Nothing here decides when the shield ends. `ApplyImpactDamage` lifts it as
	-- the first thing it does, and that call is itself fired by the victim's
	-- ragdoll resolving, so the shield covers exactly the window the engine can
	-- charge the body for and not a millisecond that has to be guessed at.
	--
	-- This timer is a crash backstop and nothing else: if the damage call never
	-- happens, nobody is left permanently unkillable. Reaching it means
	-- something else went wrong, which is why it says so.
	--
	-- **Deliberately not generation guarded.** Every other timer in this mod
	-- returns early when a script reload has bumped the generation, so a stale
	-- loop stops doing work. This one must not: the work it does is removing
	-- immortality, and skipping it would leave a victim unkillable for the rest
	-- of the session. A reload happens on every deploy, so that is not remote.
	Script.SetTimer(self.Config.ShieldWindowMs or 6000, function()
		if state.removed then
			return
		end

		state.removed = true

		if self.ShieldedVictims[id] == state then
			self.ShieldedVictims[id] = nil
		end

		local lifted = pcall(function()
			npc.soul:RemoveBuff(state.instance)
		end)

		if self.Config.LogTelemetry then
			self:Log("Shield backstop fired on " .. self:NameOf(npc)
					.. " ok=" .. tostring(lifted)
					.. " (the damage call never lifted it)")
		end
	end)
end

--- Takes the collision shield off a victim, now.
--
-- Called from `ApplyImpactDamage` immediately before it charges the victim, so
-- the immortality that swallowed the engine's trample cannot also swallow the
-- mod's own damage. Safe to call on somebody who was never shielded.
--
-- @tparam table npc the victim
-- @treturn boolean true when a removal was attempted
function HorseCollisionMod:LiftCollisionShield(npc)
	if not npc or not npc.soul then
		return false
	end

	local id = tostring(npc.id or "?")
	local state = self.ShieldedVictims[id]

	if state == nil or state.removed then
		return false
	end

	state.removed = true
	self.ShieldedVictims[id] = nil

	-- The instance this mod added, never every instance by GUID, so a quest's
	-- own immortality on the same victim is untouched.
	local ok = pcall(function()
		npc.soul:RemoveBuff(state.instance)
	end)

	if self.Config.LogTelemetry then
		self:Log("Shield lifted on " .. self:NameOf(npc) .. " ok=" .. tostring(ok))
	end

	return ok
end

--- Switches off vanilla's collision bark on somebody the horse is approaching.
--
-- Per impact suppression loses a race it cannot win. The mod's detection loop
-- runs about ten times a second, while the engine raises its own hit reaction
-- the instant bodies touch, so vanilla's line can already be playing before the
-- tick that would have silenced it. The rider heard the result as "a vanilla
-- interrupted by the mod's".
--
-- Setting the option while the victim is still in front of the horse removes
-- the race: by the time contact happens the branch is already closed. It is
-- refreshed rather than set every tick, because a context write twenty times a
-- second per nearby person is not free.
--
-- Cleared on a timer well after the impact, so an NPC the rider passes without
-- touching gets their own bark back a moment later and nothing is permanently
-- changed. Non-persistent, so a save cannot carry it.
--
-- @tparam table npc somebody inside the horse's footprint
function HorseCollisionMod:HushVanillaBark(npc)
	if not self:BarksEnabled("Collision") then
		return
	end

	local id = tostring(npc and npc.id or "?")
	local now = self:TimeMs()
	local last = self.RecentHushes[id]
	local window = self.Config.BarkSuppressMs or 2500

	if last and (now - last) < (window * 0.5) then
		return
	end

	self.RecentHushes[id] = now

	pcall(function()
		Contexts.SetNonpersistentOption(npc, "suppressCollisionsBark", "hcmBark",
				{ suppressNonexistentHandleError = true })
	end)

	Script.SetTimer(window, function()
		pcall(function()
			Contexts.ClearOption(npc, "suppressCollisionsBark", "hcmBark",
					{ suppressNonexistentHandleError = true })
		end)
	end)
end
