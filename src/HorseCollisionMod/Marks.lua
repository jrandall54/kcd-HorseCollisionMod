--- Marks: the dirt and blood a collision leaves on the victim.
--
-- Someone ridden down and put on the ground stands back up immaculate. The
-- animation plays, health is spent, the crime is charged, and nothing about
-- the victim afterwards says anything happened to them. This file leaves the
-- evidence on their body and their clothes.
--
-- Two engine calls do the work, both on the actor. `actor:AddDirt(n)` adds
-- dirt to everything the victim is wearing and takes no zone. `actor:AddBlood
-- (zone, n)` takes a named zone of the body and adds blood to the body and to
-- whatever covers it. Both arguments are deltas in the range -1 to 1, so
-- repeated collisions accumulate and a negative figure would wash it off.
-- Vanilla uses both this way: `deadBody.xml` bloods a corpse on spawn, and
-- `q_huntPtacek.xml` dirties a man dragged through a wood.
--
-- The zones are chosen from the impact direction `Detection.lua` already
-- computes for the reaction clips, so a rider who is run down from behind is
-- marked across the back rather than the face. Only zone names that vanilla
-- itself passes are used: the engine reads them from a database this mod
-- cannot see, and an unrecognized name fails silently, which would look
-- exactly like the feature not working.
--
-- The walk tier is deliberately unmarked. A shove that does not put anyone on
-- the ground should not leave them bloodied, and dirt on a victim who never
-- fell would read as a bug.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Marks
-- @author jrandall54
-- @release 5.1.0

--- Body zones bloodied for each impact direction.
--
-- Keyed by the strings `GetImpactDir` returns, which name the side of the
-- victim the blow arrives on: `so_forward` is a victim struck on the front,
-- `so_back` one run down from behind.
--
-- Every name here is attested in the vanilla quest scripts. The sets are not
-- mirror images of one another because the vanilla scripts do not use a
-- symmetrical set of names, and a name invented to balance a list would be
-- discarded by the engine without a word.
--
-- @table BloodZones
HorseCollisionMod.BloodZones = {
	so_forward = {
		"head_front",
		"body_front_down",
		"arm_left_upper_front",
		"arm_right_forearm_front",
		"leg_left_upper_front",
		"leg_right_upper_front"
	},
	so_back = {
		"head_back",
		"head_neck",
		"arm_left_upper_back",
		"arm_right_forearm_back",
		"leg_right_upper_back",
		"leg_right_lower_back"
	},
	so_left = {
		"head_left",
		"body_left",
		"arm_left_upper_front",
		"arm_left_forearm_front",
		"arm_left_forearm_back",
		"leg_left_lower_front"
	},
	so_right = {
		"head_right",
		"body_right",
		"arm_right_forearm_front",
		"arm_right_forearm_back",
		"leg_right_lower_front",
		"foot_right"
	}
}

--- Marks a victim with the dirt and blood their impact earned.
--
-- Called at the moment of impact, from the trot and gallop branches of
-- `OnImpact`. Nothing is applied at a walk.
--
-- The amounts come from the settings, per tier, and each application is
-- jittered by a quarter either way so a victim ridden down twice does not
-- carry two identical marks. An amount of zero skips its call rather than
-- passing a delta the engine would ignore.
--
-- Every call is wrapped, because an actor can be unstreamed between the
-- impact and this line and a raw error would kill the collision tick.
--
-- @tparam table npc victim entity
-- @tparam string tierName "Trot" or "Gallop"; "Walk" leaves no mark
-- @tparam table velocity horse velocity vector
-- @tparam number speed horse speed in meters per second
-- @treturn boolean true when something was applied
function HorseCollisionMod:MarkVictim(npc, tierName, velocity, speed)
	local cfg = self.Config

	if not cfg.VictimMarks or tierName == "Walk" then
		return false
	end

	if not npc or not npc.actor then
		return false
	end

	local dirt = cfg.VictimDirtTrot
	local blood = cfg.VictimBloodTrot

	if tierName == "Gallop" or tierName == "Charge" then
		dirt = cfg.VictimDirtGallop
		blood = cfg.VictimBloodGallop
	end

	local direction = self:GetImpactDir(npc, velocity, speed)
	local zones = self.BloodZones[direction] or self.BloodZones.so_forward
	local applied = false

	-- A quarter either side of the figure asked for. Enough that two impacts
	-- do not stamp the same mark twice, not enough to change the tier.
	local function jitter(amount)
		return amount * (0.75 + (math.random() * 0.5))
	end

	if dirt and dirt > 0 and type(npc.actor.AddDirt) == "function" then
		local ok = pcall(function()
			npc.actor:AddDirt(jitter(dirt))
		end)

		applied = applied or ok
	end

	if blood and blood > 0 and type(npc.actor.AddBlood) == "function" then
		for _, zone in ipairs(zones) do
			local ok = pcall(function()
				npc.actor:AddBlood(zone, jitter(blood))
			end)

			applied = applied or ok
		end
	end

	if cfg.LogTelemetry then
		self:Log("VictimMarks tier=" .. tostring(tierName)
				.. " dir=" .. tostring(direction)
				.. " dirt=" .. string.format("%.2f", dirt or 0)
				.. " blood=" .. string.format("%.2f", blood or 0)
				.. " zones=" .. tostring(#zones)
				.. " applied=" .. tostring(applied))
	end

	return applied
end

--- Throws up dust where a body hits the ground.
--
-- A collision moves a person several meters and drops them, and the ground
-- they land on does not react at all. Dust is the cheapest thing that says
-- the impact happened somewhere rather than only to somebody.
--
-- ### Why this is not in the animation data
--
-- The animation databases can carry a `ParticleEffect` procedural layer, and
-- vanilla uses seven of them, all pouring something out of a hand. It is the
-- wrong route here for one reason: a gallop impact plays no fragment at all.
-- That tier is a physics ragdoll, so there is nothing to hang a layer on, and
-- authoring dust per fragment would give it to the trot tier only, which is
-- the tier that needs it least.
--
-- `Particle.SpawnEffect(name, pos, dir, scale)` is the same call vanilla uses
-- for a bullet hitting flesh in `BasicActor.lua` and for a fish breaking the
-- surface in `Fish.lua`. It takes a world position, so it is indifferent to
-- what the victim's body is doing, and one call covers all three tiers.
--
-- The effect is spawned at the victim's feet rather than at their center,
-- because the dust belongs to the ground and an emitter at chest height puts
-- it in the air. The direction is straight up, which is the way loose soil
-- leaves the ground when something lands on it.
--
-- It is spawned where and when the victim lands rather than where they were
-- struck. See `DustWhenLanded`: at a gallop those are several meters apart,
-- and the point of contact is underneath the horse and behind the rider
-- before the effect has finished rendering.
--
-- The walk tier gets none. Nobody falls at a walk, so there is nothing for
-- the ground to do.
--
-- @tparam table npc the victim entity
-- @tparam string tierName "Walk", "Trot" or "Gallop"
-- @treturn boolean true when an effect was spawned
function HorseCollisionMod:ImpactDust(npc, tierName)
	local cfg = self.Config

	if not cfg.ImpactDust or not npc or tierName == "Walk" then
		return false
	end

	local scale = cfg.ImpactDustScaleTrot or 0

	if tierName == "Charge" then
		scale = cfg.ImpactDustScaleCharge or cfg.ImpactDustScaleGallop or 0
	elseif tierName == "Rear" then
		scale = cfg.ImpactDustScaleRear or cfg.ImpactDustScaleTrot or 0
	end

	if tierName == "Gallop" or tierName == "Charge" then
		scale = cfg.ImpactDustScaleGallop or 0
	end

	if scale <= 0 then
		return false
	end

	-- The global is CryEngine's own, and is absent if the particle bindings
	-- have not loaded.
	if type(Particle) ~= "table" or type(Particle.SpawnEffect) ~= "function" then
		return false
	end

	self:DustWhenLanded(npc, tierName, scale, 0)

	return true
end

--- Waits until a thrown victim meets the ground, then throws up the dust.
--
-- Spawning at the moment of contact puts the dust where the victim was
-- standing, which at a gallop is underneath the horse and several meters
-- behind the rider before it has finished rendering. The dust belongs to the
-- landing, and how far a body travels first depends on the angle it was struck
-- at, so the landing has to be detected rather than predicted.
--
-- ### The signal is vertical velocity
--
-- The victim's velocity is polled on an interval. They are falling once it
-- passes `ImpactDustFallVz`, and they have met the ground on the first sample
-- after that which is back above `ImpactDustLandVz`. A victim who never starts
-- falling, because they went down where they stood, gets their dust when the
-- grace window runs out.
--
-- Measured on one gallop throw, sampled every 50 ms:
--
--     n=0   z 80.774   vz  0.000
--     n=2   z 80.779   vz -0.505     falling
--     n=6   z 80.550   vz -2.094
--     n=8   z 80.393   vz -0.291
--     n=9   z 80.396   vz +0.157     ground, 450 ms after contact
--     n=14  z 80.309   vz  0.027     at rest, 700 ms
--
-- ### Three signals that do not report it
--
-- All three look reasonable and all three were wrong in game:
--
-- * **Height falling.** A galloped victim is thrown almost flat, so their
--   height barely changes for the first tenth of a second and the test passed
--   immediately, putting the dust back at the collision. Frame-by-frame
--   footage caught it.
-- * **Total distance moved.** That is a body at rest, which the same trace
--   puts 250 ms after the ground contact, and it read as a visible delay.
-- * **`actor:IsFlying()`.** It reads false on the first sample and nil on
--   every one after, because a ragdolled victim has left actor movement
--   entirely. Actor state stops describing them the moment they are thrown.
--
-- What does survive the ragdoll is the entity itself: its transform follows
-- the body and `GetVelocity` reports real physics. Anything asking this
-- question again should start there rather than from the actor.
--
-- Terrain height is not usable either. `System.GetTerrainElevation` under the
-- same victim read 0.7 m above the body they were lying on, because the road
-- surface they landed on is geometry rather than terrain.
--
-- The sample count is capped so a victim who never lands, because they were
-- thrown into water or off a ledge, does not leave a poll running.
--
-- @tparam table npc the victim entity
-- @tparam string tierName the tier, for the telemetry line
-- @tparam number scale the size of the effect
-- @tparam number samples how many samples have already been taken
-- @tparam[opt] boolean falling whether they have been seen falling
function HorseCollisionMod:DustWhenLanded(npc, tierName, scale, samples, falling)
	local cfg = self.Config
	local pos, vel = nil, nil

	pcall(function()
		pos = npc:GetWorldPos()
		vel = npc:GetVelocity()
	end)

	if not pos then
		return
	end

	local vz = vel and vel.z or 0

	if vz <= (cfg.ImpactDustFallVz or -0.5) then
		falling = true
	end

	local landed = falling and vz > (cfg.ImpactDustLandVz or -0.15)
	local givenUp = samples >= (cfg.ImpactDustMaxSamples or 30)
	local expired = not falling
			and samples >= (cfg.ImpactDustFallWaitSamples or 8)

	if not landed and not givenUp and not expired then
		Script.SetTimer(cfg.ImpactDustSampleMs or 50, function()
			self:DustWhenLanded(npc, tierName, scale, samples + 1, falling)
		end)

		return
	end

	local ground = self:GroundUnder(pos)
	local at = ground or pos

	local ok = pcall(function()
		Particle.SpawnEffect(cfg.ImpactDustEffect,
				{ x = at.x, y = at.y, z = at.z + (cfg.ImpactDustHeight or 0) },
				{ x = 0, y = 0, z = 1 },
				scale)
	end)

	if cfg.LogTelemetry then
		self:Log("ImpactDust tier=" .. tostring(tierName)
				.. " scale=" .. string.format("%.2f", scale)
				.. " samples=" .. tostring(samples)
				.. " vz=" .. string.format("%.2f", vz)
				.. " fell=" .. tostring(falling and true or false)
				.. " bodyZ=" .. string.format("%.2f", pos.z)
				.. " groundZ=" .. string.format("%.2f",
						ground and ground.z or pos.z)
				.. " raycast=" .. tostring(ground ~= nil)
				.. " ok=" .. tostring(ok))
	end
end

--- The ground surface underneath a point, by raycast.
--
-- The dust has to come off the surface the body is lying on, and the body's
-- own origin is not that surface. A ragdoll's origin sits inside the mesh and
-- can end up well under the ground it is resting on: measured on one victim it
-- read 0.70 m below the terrain sample at the same spot. An emitter placed
-- there is buried and renders nothing, which is why the dust appeared on some
-- collisions and not others with the spawn reporting success every time.
--
-- Cast from a meter above the body straight down, against terrain and static
-- geometry, which is vanilla's own pattern for placing a blood splat on the
-- ground in `BasicActor.lua`. Terrain elevation alone is not enough: a victim
-- who lands on a road or a bridge is on geometry, and the terrain underneath
-- it read 0.7 m out on the same measurement.
--
-- @tparam table pos a world position
-- @treturn table the surface point below it, or nil when nothing was hit
function HorseCollisionMod:GroundUnder(pos)
	local hits, hit = 0, nil

	pcall(function()
		local from = { x = pos.x, y = pos.y, z = pos.z + 1.0 }
		local down = { x = 0, y = 0, z = -3.0 }
		local table_ = {}

		hits = Physics.RayWorldIntersection(from, down, 1,
				ent_terrain + ent_static, nil, nil, table_)
		hit = table_[1]
	end)

	if hits > 0 and hit and hit.pos then
		return hit.pos
	end

	return nil
end
