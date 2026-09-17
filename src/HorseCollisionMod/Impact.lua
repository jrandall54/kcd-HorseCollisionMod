--- Impact: what happens to a victim, once something has decided one happened.
--
-- The mod has two ways of striking somebody and they have nothing in common.
-- The detection loop samples the horse's surroundings ten times a second and
-- scores whatever it finds; the rear and the charge are key presses that sweep
-- a corridor in front of a standing horse. Their entry conditions are
-- genuinely different, and that difference is why the two lived as two whole
-- functions for as long as they did.
--
-- What follows an impact is not different. Probe, sound, bark, camera, blur,
-- vocal, dust, reaction, marks, hit reaction, combat hit, damage, stamina --
-- the same thirteen steps in the same order, with a different set of numbers.
-- Written twice, they drifted: the rear and the charge never shielded their
-- victims from the engine's own collision damage, never wrote an `Impact` line
-- to the log, and for months took none of the Horsemanship, barding or combat
-- scaling that every other tier's stamina cost did.
--
-- So the two entries keep only what is theirs. The loop keeps its contact
-- debounce and its stand-down during a lunge; the rear and charge keep their
-- corridor sweep, their fixed scoring speed and their victim lockout. Both
-- then call `ResolveImpact`, and every difference that remains between tiers
-- is a row in a table in `Tiers.lua` rather than a branch in either.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Impact
-- @author jrandall54
-- @release 5.21.2

--- Everything one impact does to one victim.
--
-- Called once an entry point has decided this impact happens. It decides
-- nothing about whether it should: no cooldown, no readiness, no gate of any
-- kind lives here.
--
-- @tparam table npc the victim
-- @tparam string tierName "Walk", "Trot", "Gallop", "Rear" or "Charge"
-- @tparam table ctx what the entry point knows: `velocity`, `speed`,
--   `horsePos`, `horseEnt`, `playerEnt`, `horseWuid`, and optionally
--   `sampledSpeed` for the telemetry line
function HorseCollisionMod:ResolveImpact(npc, tierName, ctx)
	local cfg = self.Config
	local horseEnt, playerEnt = ctx.horseEnt, ctx.playerEnt
	local velocity, speed = ctx.velocity, ctx.speed

	-- Walked once per impact. Every use below wants the same totals, and
	-- enumerating an inventory per use would repeat the work several times.
	local armor = self:ArmorOf(npc)
	local armorImpulse = self:ArmorImpulseScale(armor)
	local isCombat, combatDetail, playerInDanger = self:IsCombatCollision(npc)

	-- How hard the engine is told this hit, as a name rather than a number so
	-- the settings file reads as English. The charge used to probe itself as a
	-- minor injury while sending a major one, because the probe was written
	-- once for both rear tiers and the send was branched.
	local strength = self.HitReactionStrength[
			self:TierValue("HitStrengthByTier", tierName) or "Tickle"]

	-- Whether this tier wounds at all, which several things below turn on.
	-- Read from the damage table rather than by naming the walk, so a tier
	-- set to zero damage behaves like a shove everywhere at once.
	local wounds = (self:TierValue("ImpactDamageByTier", tierName) or 0) > 0

	-- The shield spans the whole time the engine can charge for this
	-- collision, and `ApplyImpactDamage` lifts it once the body is at rest.
	--
	-- Never on a tier that does no damage. A shove never makes the victim a
	-- physical object, so there is nothing to shield from, and the damage call
	-- returns early on such a tier: the shield would go on with nothing left
	-- to take it off and the victim would stand there immortal.
	if wounds then
		self:ShieldFromEngineDamage(npc)
	end

	-- How tall they stand, taken now because now is when they are upright.
	--
	-- It is the reference everything about posture is read against: whether a
	-- body is flat enough to refuse an animation, and when it begins to rise.
	-- Recorded here rather than with the reaction because a gallop ragdolls
	-- without an animated reaction at all and still needs the figure.
	self:RecordStandingHeight(npc)

	-- What actually prevents the lockup. A victim under 40 health carrying a
	-- bleeding buff is otherwise taken over by vanilla's auto-cure daycycle,
	-- which stands them in the street playing `PretendingIllness`.
	self:SuppressAutoCure(npc)

	-- Sampled before anything moves the body. A reaction can cost the victim
	-- health of its own, and a probe reading afterwards folds that into the
	-- starting figure instead of the delta.
	self:ProbeImpactCost(npc, tierName, strength, armor)

	-- Sound first, and then the reaction.
	--
	-- The request has to go out ahead of the body being seized. Sent after the
	-- ragdoll it is requested against an entity that is already being handed
	-- to physics, and the rider reported impacts landing silently when this
	-- was moved below. The mod logs a full set of accepted layers either way,
	-- which is worth remembering: a sent request is evidence the mod asked,
	-- never that the game answered.
	self:PlayImpactSound(npc, tierName, armor)

	-- The reaction goes out here, next to the probe that just read the
	-- victim, and ahead of everything cosmetic.
	--
	-- Not a preference about ordering. `Ragdoll` reads the victim's animation
	-- state to decide whether they are already down, and a victim who is takes
	-- a different path entirely. With the sound, the barks, the camera, the
	-- blur and the dust in between, the state it reads is no longer the state
	-- the probe saw: measured across two builds of the same `Ragdoll` code,
	-- seven gallops onto victims logged as `BlendRagdoll` produced not one
	-- `Settle`, where three such gallops in the older build produced three.
	-- They had left that state by the time anything acted on it, so they took
	-- the standing path and the impact did nothing visible.
	--
	-- Everything below is about the moment of contact too, but none of it
	-- reads the victim. Only this does, so only this has to be adjacent.
	-- A stagger is the one reaction a player can switch off, and the one a
	-- fight suppresses. Both are properties of that style rather than of the
	-- walk, so they are asked of the style: a tier set to stagger obeys them
	-- whichever tier it is.
	--
	-- The combat test is `playerInDanger` and not the combined signal. The
	-- combined one is true for a victim merely holding a weapon, and a guard
	-- on patrol with a polearm holds his all day, so keying off it meant he
	-- could never be staggered at all.
	local style = self:TierValue("ReactionByTier", tierName)
	local staggerRefused = style == "stagger"
			and (not cfg.WalkStagger
					or (cfg.SuppressStaggerInCombat and playerInDanger))

	if not staggerRefused then
		self:PlayTierReaction(npc, tierName, velocity, speed,
				armorImpulse, ctx.horsePos, horseEnt)
	end

	if cfg.LogTelemetry then
		-- Read here only because the line reports them. Barding's three
		-- effects are applied inside the calls that use them.
		local bardingCover = self:BardingCoverage(horseEnt)
		local bardingForce = self:BardingForceBonus(horseEnt)

		self:Log("Impact tier=" .. tierName
				.. " speed=" .. string.format("%.2f", speed or -1)
				.. " sampled=" .. string.format("%.2f", ctx.sampledSpeed or speed or -1)
				.. (cfg.DiagnoseMisses
						and (" trail=[" .. self:SpeedTrail(self.SpeedHistorySize) .. "]")
						or "")
				.. " armorImpulse=" .. string.format("%.2f", armorImpulse)
				.. " bardingCover=" .. string.format("%.2f", bardingCover)
				.. " bardingForce=" .. string.format("%.2f", bardingForce.knockback)
				.. " " .. tostring(combatDetail))
	end


	-- Which voice answers a hit is the tier's, because the collision
	-- reactions and the rear are separate pillars and neither may carry the
	-- other's setting. The combat state is passed to the collision set
	-- because vanilla refuses a collision bark during a fight and so does this.
	local voice = self:TierValue("VictimBarkByTier", tierName)

	if voice == "rear" then
		self:BarkRear(npc, true)
	elseif voice == "collision" then
		self:BarkCollision(npc, tierName, isCombat)
	end

	-- Each of these chooses or scales by tier itself and returns false for a
	-- tier it has nothing for, so the tier is passed rather than branched on.
	self:ShakeRiderCamera(playerEnt, tierName)
	self:BlurRiderView(playerEnt, tierName)

	-- Words before breath, both at the moment of contact, and only one of them
	-- heard because they share a ranked voice gate.
	--
	-- Whether it kills is predicted rather than observed. The real answer is
	-- not settled until the body is at rest and the deferred damage lands, and
	-- a line chosen from that arrives a second and a half too late.
	self:BarkRiderOnImpact(playerEnt, tierName,
			self:PredictImpactFatal(npc, tierName, armor, horseEnt), npc)
	self:PlayRiderVocal(playerEnt, tierName)
	self:PlayHorseVocal(horseEnt, tierName)

	-- Spawned where they are struck rather than where they land, because a
	-- gallop throws them several meters and dust that follows a body reads as
	-- smoke.
	self:ImpactDust(npc, tierName)

	-- How long the ragdoll this impact asked for actually took to take.
	-- Instrumentation only; it changes nothing.
	self:TraceFallLanding(npc, tierName)

	-- Marks, the native hit reaction, and the combat hit. `MarkVictim` gates
	-- itself on having dirt and blood figures for the tier, and a tier that
	-- does no damage is not a combat hit: telling the engine a shove was one
	-- starts a fight over a nudge.
	self:MarkVictim(npc, tierName, velocity, speed)
	self:SendHitReaction(npc, ctx.horseWuid, strength)

	-- Defer the crime trigger and retaliation until the victim stands up. The engine's
	-- `sb_switch_hitreactions.xml` spawns the assault crime volume the moment
	-- `SendCombatHit` arrives. By withholding it while they fall and only delivering
	-- it when they finish their get-up, the crime broadcast happens while they are
	-- standing. Their barks and reaction make physical sense, and it perfectly overrides
	-- the casual recovery dialogue.
	self:WhenVictimRises(npc, function(reason, elapsed)
		local isDead = false

		pcall(function()
			isDead = npc:IsDead()
		end)

		if not isDead then
			if wounds then
				self:SendCombatHit(npc, playerEnt, strength)
				npc.hcm_combat_injected = true
			end

			-- Retaliation is the answer to being shoved. It is deferred so a
			-- provoked victim enters combat from a standing posture rather
			-- than attempting to process fight initialization while ragdolled.
			if self:TierValue("RetaliationByTier", tierName) then
				if self:ProvokeIfAnnoyed(npc, playerEnt) then
					npc.hcm_combat_injected = true
				end
			end
		end
	end)

	-- Called after the native hit, but calling order is not resolution order.
	-- `ApplyImpactDamage` contains a wait that makes this mod's damage land
	-- last, and so own the killing blow and the crime attribution with it.
	self:ApplyImpactDamage(npc, tierName, armor, playerEnt, horseEnt)

	-- The loop resolves one victim per impact and charges the horse here. A
	-- rear and a charge are one deliberate move that can land on several
	-- people at once, and charging per victim would empty the horse for
	-- riding at a crowd, so their entry points charge once for the move.
	if self:TierValue("StaminaPerVictimByTier", tierName) then
		self:DrainImpactStamina(horseEnt, playerEnt, tierName, armor)
	end
end

-- test reload
