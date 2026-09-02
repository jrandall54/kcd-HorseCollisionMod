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
-- @release 4.5.0

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

--- Sends the victim a hit that starts a fight but is not a crime.
--
-- Same message and same attacker as `SendCombatHit`, with one field changed:
-- `real` is false. That flag is the engine's own, and
-- `sb_switch_hitreactions.xml` gates the whole reputation branch on it. A hit
-- carrying `real = true` reaches `SetReputationNPC` and is scored as
-- `hit_melee_weak` through `hit_melee_brutal` by strength; one carrying
-- `real = false` never gets there.
--
-- Vanilla uses the same flag for two things: an attack that missed but is
-- treated as a hit, and, in `sb_switching_horse.xml`, a hit relayed off a
-- horse. The second is this mod's own situation.
--
-- The victim's combat subbrain still receives it and still decides what to do
-- about it, which is the point: the fight happens, the fine does not. Guards
-- who see the resulting brawl react to what they saw, which is intended.
--
-- Not gated on `CollisionIsCrime`, because this is the path that deliberately
-- avoids the crime system rather than the one that feeds it.
--
-- @tparam table npc victim entity
-- @tparam table playerEnt the player entity
-- @tparam number strength a `HitReactionStrength` value
-- @treturn boolean true when the call was accepted
function HorseCollisionMod:SendProvocationHit(npc, playerEnt, strength)
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
		local message = Utils.makeTable("combat:hit", {
			attacker = playerWuid,
			strength = strength,
			hitType = self.HitReactionType.Melee,
			real = false
		})

		XGenAIModule.SendMessageToEntityData(target, "combat:hit", message)
	end)

	if self.Config.LogTelemetry then
		self:Log("ProvocationHit " .. tostring(npc:GetName())
				.. " ok=" .. tostring(ok)
				.. " strength=" .. tostring(strength)
				.. " err=" .. tostring(err))
	end

	return ok
end
