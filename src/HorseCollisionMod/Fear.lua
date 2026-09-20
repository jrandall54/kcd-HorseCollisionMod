--- The band around a rear or a charge where nobody is touched.
--
-- A rear either lands on somebody or does nothing at all, and a charge either
-- runs a man down or misses him, which makes a horse going up on its hind legs
-- in a crowded street, or driving through one, an event only the people it
-- touched notice. The hooves keep their own band, `RearReach` and `RearArc`,
-- and the charge keeps its corridor; this file owns the wider ground outside
-- both: the people close enough to be frightened and far enough not to be hit.
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

--- Frightens one bystander: the stimulus, and the scream that goes with it.
--
-- Both moves that can miss somebody want the same two things sent to the same
-- man in the same order, so the pair lives here rather than being written out
-- twice. Only the rank the scream is submitted at differs, and that comes
-- from the caller, because the rear and the charge carry their own settings.
--
-- Startled, not hurt. One line, at the fright, and it is the scream rather
-- than the startle.
--
-- The moment wanted two: a startled word as the horse comes at him, and a
-- scream once the man breaks and runs. The second one cannot be had. Measured
-- over several rides, a request sent to a man who is already fleeing is
-- accepted and never spoken, at priority 50 and with the context suppression
-- overridden, while the same set sent to the same speaker at the moment of the
-- fright is audible. The flee state itself is what eats it, and nothing
-- reachable from Lua reopens it.
--
-- So the one line that is heard is the one worth having, and `NASILI_UTEK` is
-- the frightened set: "Help!", "Christ almighty!", "Oh god, oh god." A
-- startled "Hey!" followed by silent running was the weaker half of the pair.
--
-- @tparam table npc whoever is in the band
-- @tparam userdata playerWuid the rider, already resolved by the caller
-- @tparam number priority the rank the scream is submitted at
-- @tparam ?boolean overrideSuppress whether the scream is spoken over a
--   suppressed speech context
-- @treturn boolean true when the man was frightened
function HorseCollisionMod:FrightenBystander(npc, playerWuid, priority,
		overrideSuppress)
	if not self:SendHostilePerception(npc, playerWuid) then
		return false
	end

	self:Bark(npc, "Panic", false, true, priority, overrideSuppress)

	return true
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
			if self:FrightenBystander(npc, playerWuid,
					cfg.RearFearScreamPriority,
					cfg.RearFearScreamOverrideSuppress) then
				sent = sent + 1
			end
		end
	end

	if cfg.LogTelemetry then
		self:Log("FearBand sent=" .. tostring(sent)
				.. " reach=" .. tostring(cfg.RearFearReach))
	end
end

--- Frightens the people a charge goes past rather than through.
--
-- The rear's band is a circle sampled once, because a rear happens in one
-- place. A charge does not: the horse covers ground, and the man it passed at
-- the start of the lunge is thirty feet behind by the end of it. So the band
-- is sampled along the sweep, from wherever the horse is at that moment, and
-- a set of who has already been frightened carries across the ticks so nobody
-- is startled twice by one charge.
--
-- Who is left out is the difference from the rear. Anyone the corridor
-- reached is excluded for the reason the rear excludes them, a hit reaction
-- being a whole reaction already. But the lane in front is excluded too, at
-- any distance, because a man standing in it is not being missed: the horse
-- is coming for him and he is about to be ridden down. Frightening him a
-- stride before the chest arrives would put a scream and a flee on a man the
-- next tick knocks flat.
--
-- The radius is wider than the rear's, because what is being missed is
-- different: a rear is a noise in one place and the fright is the hooves
-- landing a stride away, while a charge is a horse that will be where the man
-- is standing in a moment. `RearChargeFearReach` carries the derivation.
--
-- That leaves the charge falling short of him, which is the case `closing`
-- answers. Run once as the lunge dies, it drops the lane test and frightens
-- whoever is still standing in front untouched: the horse came at him and
-- stopped, which is its own fright and the one the lane test would otherwise
-- swallow.
--
-- @tparam table horseEnt the player's horse
-- @tparam table pos where the horse is this tick
-- @tparam number fx the horse's facing, x, already normalised
-- @tparam number fy the horse's facing, y, already normalised
-- @tparam userdata playerWuid the rider, resolved once by the caller
-- @tparam table struck a set of entity ids the charge has run down
-- @tparam table feared a set of entity ids already frightened by this charge
-- @tparam ?boolean closing true on the single pass run as the lunge ends
function HorseCollisionMod:ChargeFearBand(horseEnt, pos, fx, fy, playerWuid,
		struck, feared, closing)
	local cfg = self.Config

	if not cfg.RearChargeFear or not playerWuid or not pos then
		return 0
	end

	local playerEnt = player
	local found = nil

	pcall(function()
		found = System.GetEntitiesInSphere(pos,
				cfg.RearChargeFearReach or 4.8)
	end)

	if type(found) ~= "table" then
		return 0
	end

	local halfWidth = cfg.RearChargeStrikeWidth or 1.6
	local sent = 0

	for _, npc in pairs(found) do
		local id = npc and npc.id and tostring(npc.id)

		if id and npc ~= playerEnt and npc ~= horseEnt and npc.actor
				and not struck[id] and not feared[id]
				and self:RearCanHit(npc) then
			local inLane = false

			pcall(function()
				local p = npc:GetWorldPos()
				local dx, dy = p.x - pos.x, p.y - pos.y
				local ahead = (dx * fx) + (dy * fy)
				local across = math.abs((dx * -fy) + (dy * fx))

				inLane = (ahead >= 0 and across <= halfWidth)
			end)

			if closing or not inLane then
				feared[id] = true

				if self:FrightenBystander(npc, playerWuid,
						cfg.RearChargeFearScreamPriority,
						cfg.RearChargeFearScreamOverrideSuppress) then
					sent = sent + 1
				end
			end
		end
	end

	return sent
end

--- The single pass run as a charge dies.
--
-- Reads the horse's last position and facing itself, because the sweep that
-- calls it has already given up its own and is returning.
--
-- @tparam table horseEnt the player's horse
-- @tparam userdata playerWuid the rider, resolved by the sweep
-- @tparam table struck a set of entity ids the charge ran down
-- @tparam table feared a set of entity ids already frightened by this charge
function HorseCollisionMod:CloseChargeFear(horseEnt, playerWuid, struck, feared)
	local cfg = self.Config

	if not cfg.RearChargeFear then
		return
	end

	local pos = nil
	local fx, fy = nil, nil

	pcall(function()
		pos = horseEnt:GetWorldPos()

		local heading = horseEnt:GetDirectionVector(1)
		local flat = math.sqrt((heading.x * heading.x)
				+ (heading.y * heading.y))

		if flat > 0 then
			fx, fy = heading.x / flat, heading.y / flat
		end
	end)

	if not pos or not fx then
		return
	end

	local sent = self:ChargeFearBand(horseEnt, pos, fx, fy, playerWuid,
			struck, feared, true)

	if cfg.LogTelemetry then
		local total = 0

		for _ in pairs(feared) do
			total = total + 1
		end

		self:Log("ChargeFear closing=" .. tostring(sent)
				.. " total=" .. tostring(total)
				.. " reach=" .. tostring(cfg.RearChargeFearReach))
	end
end
