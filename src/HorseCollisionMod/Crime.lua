--- Crime: making the game charge the player for riding someone down.
--
-- Vanilla does not treat a mounted collision as an offence at all. What makes
-- it one is a real combat hit attributed to the player, which is delivered as
-- `combat:hit` rather than `hitReaction`: the latter is consumed by a passive
-- observer that cannot drive a body or raise a crime, while the former feeds
-- the combat subbrain that owns both.
--
-- `CollisionIsCrime` gates the whole thing, and the payload shape is vanilla's
-- own, taken from the branch that turns a player-ridden collision into a real
-- hit. The strength sent is the same `HitReactionStrength` the tier chose, so
-- a harder impact is charged as a worse offence without this file deciding
-- anything about severity.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Crime
-- @author jrandall54
-- @release 4.7.2
-- The engine's `combatAttackKind`, transcribed from
-- `Libs/AI/TypeDefinitions.xml`. Sequential, and the type definition's own
-- comment says the melee entries are ordered by increasing violence.
--
-- `Unarmed` is what a shove from horseback is charged as: the mildest melee
-- kind, so a provoked scuffle is a scuffle rather than an armed assault.
--
-- It lives here rather than in `Enums.lua` beside the other engine enums for
-- a blunt reason: a third annotated table in that module makes LDoc fail
-- outright with "'class' cannot have multiple values", whatever the tags on
-- it say. Here it sits beside its only consumer, which is the better place
-- for it anyway. Documented as an ordinary comment for the same reason the
-- entry point does that for the tables LDoc misreads.
--
-- The full set is kept rather than only the value used, so the contract
-- stays verifiable against the engine.
HorseCollisionMod.CombatAttackKind = {
	None = 0,
	Missile = 1,
	StealthAction = 2,
	Unarmed = 3,
	Melee = 4,
	DogBite = 5
}

--- Sends the victim a real combat hit, attributed to the player.
--
-- `hitReaction` is a physical event, consumed by `sb_switch_hitreactions.xml`,
-- which is a passive observer that cannot drive a body. `combat:hit` feeds the
-- combat subbrain, which owns it. That difference is why this is worth trying
-- at all, and why the mod's reaction animations have always had to be played
-- by seizing the actor instead.
--
-- The shape is vanilla's own, from the branch in that switch tree that turns a
-- player-ridden collision into a real hit:
--
--     attacker($__player), strength($hitReaction.hitStrength),
--     hitType($enum:HitReactionType.Melee), real(true)
--
-- A collision is rewritten as `Melee` there rather than kept as `Collision`,
-- the player is named rather than the horse, and `real` marks it as a genuine
-- strike rather than a near miss.
--
-- The payload has to be a typed table. As a `key(value)` string this message
-- is accepted and discarded, producing no reaction and no hostility, which is
-- the same fault that made `daycycle:restartRequest` look inert.
--
-- `CollisionIsCrime` governs it. A real hit attributed to the player is how the
-- game decides a crime happened, so this is what turns a village against the
-- rider.
--
-- @tparam table npc victim entity
-- @tparam table playerEnt the player entity
-- @tparam number strength a `HitReactionStrength` value
-- @treturn boolean true when the call was accepted
function HorseCollisionMod:SendCombatHit(npc, playerEnt, strength)
	if not self.Config.CollisionIsCrime or not playerEnt then
		return false
	end

	local target = npc.id

	if npc.this and npc.this.id then
		target = npc.this.id
	end

	local playerWuid = nil

	pcall(function()
		playerWuid = XGenAIModule.GetMyWUID(playerEnt)
	end)

	if not playerWuid then
		return false
	end

	-- Both overridable, so a single impact can be run at a chosen setting
	-- without a rebuild. The charge the game brings is the thing being
	-- measured, and it can only be read by surrendering to a guard, which
	-- means one impact per save load.
	-- Melee, not Collision, and that is not a mistake. Measured across nine
	-- runs, the crime system prosecutes `Melee`, `MeleeStealth` and `Bullet`
	-- and is blind to `Collision` and `Fall` at every strength. Vanilla makes
	-- the same substitution in `sb_switch_hitreactions.xml`, rewriting a
	-- player-ridden collision into `Melee` before re-sending it, because the
	-- crime system has no concept of being ridden down.
	--
	-- `strength` is passed through and changes nothing about the charge: a
	-- `Tickle`, which costs no health, is prosecuted exactly as a `Fatal` is.
	-- The fine scales with the victim's social class instead, and murder
	-- arrives on its own when a victim actually dies.
	local ok, err = pcall(function()
		local message = Utils.makeTable("combat:hit", {
			attacker = playerWuid,
			strength = strength,
			hitType = self.HitReactionType.Melee,
			real = true
		})

		XGenAIModule.SendMessageToEntityData(target, "combat:hit", message)
	end)

	if self.Config.LogTelemetry then
		self:Log("CombatHit ok=" .. tostring(ok)
				.. " strength=" .. tostring(strength)
				.. " err=" .. tostring(err))
	end

	return ok
end

--- Sends the victim a fight-starting stimulus that no bystander witnesses.
--
-- Deliberately **not** `combat:hit`. That message is handled by
-- `sb_switch_hitreactions.xml`, which runs two independent branches, and only
-- one of them is gated on the `real` flag:
--
-- * the reputation branch, which computes a `hit_melee_*` change and calls
--   `SetReputationNPC`. Gated on `real`, so `real = false` skips it.
-- * the assault broadcast, which is not gated on `real` at all. It spawns a
--   `SpawnExpiringPerceptibleVolume` one meter across at the victim, labeled
--   `assault`, for six seconds, at full conspicuousness and visibility, then
--   blinds the attacker and the victim to it and leaves everyone else able to
--   see it. That volume is how a bystander learns an assault happened, and it
--   is what charged the rider with brawling before a punch had been thrown.
--
-- `combat:stimulus:hit` is the message that switch ultimately sends onward to
-- the victim's own combat subbrain. Sending it directly reaches the same
-- handler in `sb_combat.xml`, where `alwaysFightWhenHit` is consulted, without
-- passing through the switch that broadcasts. The subbrain starter listens for
-- it by name on `combatStimulus_combatSubbrainStarter` and converts it into a
-- stimulus impulse of kind `hit`, exactly as it would have done anyway.
--
-- So the victim decides to fight and nobody else is told an assault occurred.
--
-- `kind` is `Unarmed`, the mildest melee kind the engine defines. `real` stays
-- false: nothing here should be scored as a real blow, and the flag is carried
-- through to the subbrain where the distinction still exists.
--
-- Not gated on `CollisionIsCrime`, because this is the path that deliberately
-- avoids the crime system rather than the one that feeds it.
--
-- @tparam table npc victim entity
-- @tparam table playerEnt the player entity
-- @treturn boolean true when the call was accepted
function HorseCollisionMod:SendProvocationHit(npc, playerEnt)
	if not playerEnt then
		return false
	end

	local target = npc.id

	if npc.this and npc.this.id then
		target = npc.this.id
	end

	local playerWuid = nil

	pcall(function()
		playerWuid = XGenAIModule.GetMyWUID(playerEnt)
	end)

	if not playerWuid then
		return false
	end

	local ok, err = pcall(function()
		local message = Utils.makeTable("combat:stimulus:hit", {
			attacker = playerWuid,
			kind = self.CombatAttackKind.Unarmed,
			real = false
		})

		XGenAIModule.SendMessageToEntityData(target,
				"combat:stimulus:hit", message)
	end)

	if self.Config.LogTelemetry then
		self:Log("ProvocationHit " .. tostring(npc:GetName())
				.. " ok=" .. tostring(ok)
				.. " err=" .. tostring(err))
	end

	return ok
end
