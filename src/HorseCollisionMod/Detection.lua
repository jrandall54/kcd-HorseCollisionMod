--- Detection: whether an impact happened, and which way it pushed.
--
-- The footprint test decides whether a nearby NPC is actually under the horse
-- rather than merely close to it, and the direction lookup turns the horse's
-- velocity into the side the victim is struck from, which is what selects the
-- reaction clip.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. The footprint limits are read
-- from `Config`, so they live in the entry point and exist before this file
-- runs.
--
-- @module HorseCollisionMod.Detection
-- @author jrandall54
-- @release 4.9.3
--- Tests whether a victim is actually under the horse.
--
-- The sphere search is a broad-phase cull and nothing more. A horse is about
-- two meters long and under a meter wide, so a sphere around its origin also
-- catches people walking alongside or trailing behind it, which is what makes
-- collisions feel like they reach too far.
--
-- This narrows the sphere to an oriented box: the victim must be within the
-- horse's width laterally, between its rear and front reach along its facing,
-- and at a comparable height. The front reach is extended by the distance the
-- horse travels in one tick so that fast victims are not missed between
-- frames.
--
-- The measurements are only formatted when somebody asks for them. This runs
-- for every entity near the horse on every tick, thirty times a second, and
-- building a diagnostic string that is then discarded is the most expensive
-- thing in the loop.
--
-- @tparam table npc victim entity
-- @tparam table horsePos world position of the horse
-- @tparam table horseForward horse facing, unit vector
-- @tparam number speed horse speed in meters per second
-- @tparam[opt] boolean wantDetail build the measurement string, which only
--   the diagnostics need
-- @treturn boolean true when the victim is inside the footprint
-- @treturn string the measurements, or nil when they were not asked for
function HorseCollisionMod:IsInHorseFootprint(npc, horsePos, horseForward, speed,
		wantDetail)
	local cfg = self.Config
	local npcPos = nil

	pcall(function()
		npcPos = npc:GetPos()
	end)

	if not npcPos or not horsePos or not horseForward then
		return false
	end

	local dx = npcPos.x - horsePos.x
	local dy = npcPos.y - horsePos.y
	local dz = npcPos.z - horsePos.z

	-- Rejects anyone on a bridge overhead or in a cellar below, who would
	-- otherwise pass the flat two-dimensional test.
	if math.abs(dz) > cfg.HorseMaxVerticalDiff then
		return false
	end

	-- Distance along the horse's facing, and perpendicular to it. The
	-- perpendicular is taken directly from the forward vector rather than
	-- asking the engine for a second axis, so the two cannot disagree.
	local forwardDistance = (horseForward.x * dx) + (horseForward.y * dy)
	local lateralDistance = math.abs((horseForward.y * dx) - (horseForward.x * dy))

	local sweepExtra = speed * cfg.TickSeconds * cfg.SweepMultiplier

	if sweepExtra > cfg.MaxSweepExtra then
		sweepExtra = cfg.MaxSweepExtra
	end

	local inside = forwardDistance >= -cfg.HorseRearReach
			and forwardDistance <= (cfg.HorseFrontReach + sweepExtra)
			and lateralDistance <= cfg.HorseHalfWidth

	-- Formatted only when it will be read. `DiagnoseMisses` is the switch that
	-- turns the loop's diagnostics on, and the footprint line is one of them:
	-- gating it on `LogTelemetry` instead wrote a line for every tick a victim
	-- stood in range, which is thirty a second in ordinary play.
	if not wantDetail and not cfg.DiagnoseMisses then
		return inside, nil
	end

	local detail = string.format(
			"fwd=%.2f lat=%.2f dz=%.2f sweep=%.2f limits=%.2f/%.2f/%.2f",
			forwardDistance, lateralDistance, dz, sweepExtra,
			cfg.HorseFrontReach + sweepExtra, cfg.HorseHalfWidth,
			cfg.HorseMaxVerticalDiff)

	if inside and cfg.DiagnoseMisses then
		self:Log("Footprint " .. detail)
	end

	return inside, detail
end


--- Measurements for a candidate the footprint test rejected.
--
-- Same geometry as the test itself rather than a second copy of it, so the
-- numbers reported are the numbers the decision was made on.
--
-- @treturn string the distances and the limits they were checked against
function HorseCollisionMod:FootprintDetail(npc, horsePos, horseForward, speed)
	local _, detail = self:IsInHorseFootprint(npc, horsePos, horseForward,
			speed, true)

	return detail or "unmeasurable"
end

--- The entities near the horse, from a cached broad phase where possible.
--
-- `System.GetEntitiesInSphere` is the most expensive call the mod makes and
-- the only one with a real budget at thirty ticks a second. The result is
-- reused until the horse has travelled `SphereCacheTravel`, or the result is
-- older than `SphereCacheMaxAgeMs`, whichever comes first.
--
-- That is safe rather than merely cheap. The sphere reaches `HitRadius` and
-- the footprint can never reach beyond `HorseFrontReach` plus `MaxSweepExtra`,
-- so anyone the query did not return is at least the difference away from
-- being hit. Both thresholds are set inside that difference, and keying the
-- refresh on distance travelled rather than on elapsed ticks means the
-- guarantee does not depend on how fast the horse is going.
--
-- A cached entity may have been unstreamed since. Every use of one is already
-- wrapped, and its position is read fresh each tick, so a stale list costs a
-- rejected candidate rather than an error.
--
-- @tparam table horsePos world position of the horse
-- @tparam number now engine clock in milliseconds
-- @treturn table the entities near the horse, possibly from the last tick
-- @treturn boolean true when the query actually ran
function HorseCollisionMod:EntitiesNearHorse(horsePos, now)
	local cache = self.SphereCache

	if cache.ents and cache.pos then
		local dx = horsePos.x - cache.pos.x
		local dy = horsePos.y - cache.pos.y
		local dz = horsePos.z - cache.pos.z
		local moved = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

		if moved < self.SphereCacheTravel
				and (now - cache.at) < self.SphereCacheMaxAgeMs then
			return cache.ents, false
		end
	end

	local found = nil

	pcall(function()
		found = System.GetEntitiesInSphere(horsePos, self.Config.HitRadius)
	end)

	if type(found) ~= "table" then
		return nil, true
	end

	cache.ents = found
	cache.pos = { x = horsePos.x, y = horsePos.y, z = horsePos.z }
	cache.at = now

	return found, true
end

--- Works out which side of the victim the impact lands on.
--
-- The stagger clips are authored relative to the NPC's facing, so the impact
-- has to be expressed in the victim's own frame. Using the horse's frame
-- instead makes NPCs stagger into the horse rather than away from it.
--
-- The impact is derived from the horse's **direction of travel**, not its
-- position. Position is ambiguous at the moment of contact, when the horse
-- is effectively on top of the victim and a centimeter either way flips the
-- answer. Travel direction is stable, and it is what actually decides which
-- side of the body is struck: a horse moving north hits the south face of
-- whoever is in front of it.
--
-- @tparam table npc victim entity
-- @tparam table velocity horse velocity vector
-- @tparam number speed horse speed in meters per second
-- @treturn string one of "so_forward", "so_back", "so_left", "so_right"
function HorseCollisionMod:GetImpactDir(npc, velocity, speed)
	local forward = nil

	pcall(function()
		if npc.GetDirectionVector then
			forward = npc:GetDirectionVector(1)
		end
	end)

	if not forward or not velocity or speed <= 0 then
		return "so_forward"
	end

	-- The blow arrives from the direction the horse came from, which is the
	-- opposite of its travel. Flattened to the ground plane, since a rider
	-- is always above a pedestrian and the height would bias every result.
	local fromX = -velocity.x / speed
	local fromY = -velocity.y / speed

	-- Projected onto the victim's axes: dot is how much the blow comes from
	-- ahead of them (negative means from behind), cross is how much it comes
	-- from their left (negative means their right).
	local dot = (forward.x * fromX) + (forward.y * fromY)
	local cross = (forward.x * fromY) - (forward.y * fromX)

	-- The larger magnitude wins, which snaps the blow to the nearest of the
	-- four authored clips. Comparing magnitudes rather than testing a fixed
	-- angle means a glancing hit still resolves sensibly.
	if math.abs(dot) >= math.abs(cross) then
		if dot >= 0 then
			return "so_forward"
		end

		return "so_back"
	end

	if cross >= 0 then
		return "so_left"
	end

	return "so_right"
end
