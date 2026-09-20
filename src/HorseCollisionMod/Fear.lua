--- The band around a rear where nobody is touched.
--
-- A rear either lands on somebody or does nothing at all, which makes a horse
-- going up on its hind legs in a crowded street an event only one man in the
-- street notices. The hooves keep their own band, `RearReach` and `RearArc`,
-- and this file owns the wider one outside it: the people close enough to be
-- frightened and far enough not to be hit.
--
-- Nothing here decides who runs. The stimulus the band sends is vanilla's own
-- `combat:stimulus:hostilePerception`, the message an NPC's brain receives
-- when it perceives somebody it reads as a threat, and the brain then makes
-- the choice it always makes: most people break and get away from the rider,
-- and the ones who back themselves turn round and come for him. That fork is
-- the game's, scored against the relationship, the social class and the
-- combat evaluation each NPC already carries, and a man who chooses to fight
-- arrives at the retaliation pillar through vanilla's own path rather than
-- through anything this mod forces on him.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Fear
-- @author jrandall54

--- Tells one NPC that the rider is a threat.
--
-- `hostilePerception` carries a single member, `perceptible`, a WUID, and the
-- payload has to be a typed table: as a `key(value)` string a stimulus is
-- accepted and discarded, which is what `Crime.lua` records for
-- `combat:hit`.
--
-- The player is named rather than the horse. The horse is what the victim
-- feels in an impact and what the hit reaction blames, but the thing an
-- onlooker is frightened of, and the thing they would run from or turn on, is
-- the man riding it.
--
-- @tparam table npc whoever is in the band
-- @tparam userdata playerWuid the rider, already resolved by the caller
-- @treturn boolean true when the call was accepted
function HorseCollisionMod:SendHostilePerception(npc, playerWuid)
	local target = npc.id

	if npc.this and npc.this.id then
		target = npc.this.id
	end

	local ok, err = pcall(function()
		local message = Utils.makeTable("combat:stimulus:hostilePerception", {
			perceptible = playerWuid
		})

		XGenAIModule.SendMessageToEntityData(target,
				"combat:stimulus:hostilePerception", message)
	end)

	if self.Config.LogTelemetry then
		self:Log("Fear hostilePerception ok=" .. tostring(ok)
				.. " npc=" .. tostring(npc:GetName())
				.. " err=" .. tostring(err))
	end

	return ok
end

--- Frightens everyone standing round a rear who was not hit by it.
--
-- The band is a circle and not an arc. The strike has an arc because hooves
-- come down in one direction, but being missed by them does not: a man the
-- horse reared beside, or reared in front of while walking past him, watched
-- the same thing happen a stride away and has the same reason to run. Where
-- he happened to be standing relative to the horse's nose is not what makes
-- it frightening.
--
-- What keeps it a near miss rather than a sweep of the street is the radius
-- alone. A horse going up on its hind legs is neither a crime nor a fright in
-- itself; the hooves coming down close to you is. Anybody the hooves actually
-- reached is excluded: they have a hit reaction, a bark and a fall to get
-- through, and a fear stimulus on top of that is a second reaction competing
-- with the first.
--
-- The same three tests the strike applies decide who counts, through
-- `RearCanHit`, because the band is asking the same question about the same
-- kind of body: a living human who is not Henry's dog.
--
-- @tparam table horseEnt the player's horse
-- @tparam ?table struck a set of entity ids the hooves landed on
function HorseCollisionMod:FearBand(horseEnt, struck)
	local cfg = self.Config

	if not cfg.RearFear then
		return
	end

	local playerEnt = player
	local horsePos = nil

	pcall(function()
		horsePos = horseEnt:GetWorldPos()
	end)

	if not horsePos then
		return
	end

	local playerWuid = nil

	pcall(function()
		playerWuid = XGenAIModule.GetMyWUID(playerEnt)
	end)

	if not playerWuid then
		return
	end

	local found = nil

	pcall(function()
		found = System.GetEntitiesInSphere(horsePos, cfg.RearFearReach or 3.5)
	end)

	if type(found) ~= "table" then
		return
	end

	local sent = 0

	for _, npc in pairs(found) do
		if npc ~= playerEnt and npc ~= horseEnt and npc.actor
				and not (struck and struck[tostring(npc.id)])
				and self:RearCanHit(npc) then
			if self:SendHostilePerception(npc, playerWuid) then
				sent = sent + 1

				-- Startled, not hurt. `BarkRear` already carries the two
				-- sets and picks between them on whether contact was
				-- made, and a near miss is exactly the case it was
				-- written for and never reached, because until now
				-- nothing but the strike itself spoke for a rear.
				-- One line, at the fright, and it is the scream rather than
				-- the startle.
				--
				-- The moment wanted two: a startled word as the hooves come
				-- down, and a scream once the man breaks and runs. The second
				-- one cannot be had. Measured over several rides, a request
				-- sent to a man who is already fleeing is accepted and never
				-- spoken, at priority 50 and with the context suppression
				-- overridden, while the same set sent to the same speaker at
				-- the moment of the fright is audible. The flee state itself
				-- is what eats it, and nothing reachable from Lua reopens it.
				--
				-- So the one line that is heard is the one worth having, and
				-- `NASILI_UTEK` is the frightened set: "Help!", "Christ
				-- almighty!", "Oh god, oh god." A startled "Hey!" followed by
				-- silent running was the weaker half of the pair.
				self:Bark(npc, "Panic", false, true,
						cfg.RearFearScreamPriority,
						cfg.RearFearScreamOverrideSuppress)
			end
		end
	end

	if cfg.LogTelemetry then
		self:Log("FearBand sent=" .. tostring(sent)
				.. " reach=" .. tostring(cfg.RearFearReach))
	end
end
