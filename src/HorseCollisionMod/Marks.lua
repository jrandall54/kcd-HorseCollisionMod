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
-- @release 4.11.0

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

	if tierName == "Gallop" then
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
