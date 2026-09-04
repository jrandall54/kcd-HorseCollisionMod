--- Sound: the noise a collision makes.
--
-- A collision is silent. The victim's bark and the horse's own foley are all
-- there is, and nothing in the moment says that eighty kilograms of person was
-- struck by half a ton of horse.
--
-- Vanilla's audio triggers are reachable from Lua through a global helper in
-- `Scripts/Utils/SoundUtils.lua`:
--
--     function PlayAudioTrigger(entity, param)
--         entity:ExecuteAudioTrigger(AudioUtils.LookupTriggerID(param),
--                 entity:GetDefaultAuxAudioProxyID())
--     end
--
-- The trigger names come from the game's own `.animevents` files, which carry
-- 242 distinct `audio_trigger` parameters between them. That is the authored
-- vocabulary, and a name outside it does not resolve.
--
-- ### Why this is not in the animation data
--
-- The animation databases this mod generates can carry a `PlaySound`
-- procedural layer, and that route works: a trigger fired that way is audible,
-- and the stock male database ships twenty four of them. It was built, tested
-- in game, and abandoned, because a fragment cannot make a sound before it
-- starts. Even at `ExitTime="0.0"` the noise arrives after the horse has
-- already hit, since the reaction animation begins a detection tick and an
-- interactive-action call later than the contact that caused it. The rider's
-- verdict on that build was that the timing was "way off".
--
-- Firing from here instead puts the sound on the same line as the impact that
-- detected it, and leaves the animation data unchanged.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Sound
-- @author jrandall54
-- @release 4.9.0

--- Blunt body impacts, keyed by what the victim is wearing.
--
-- The combat audio in `Libs/GameAudio/combat.xml` carries one of these per
-- armor material. `Armor.lua` already reports the heaviest type a victim is
-- wearing, so the layer that lands on the body can match it: cloth thuds,
-- mail rings, plate bangs.
--
-- @table BodyImpactSounds
HorseCollisionMod.BodyImpactSounds = {
	fabric = "blunt_unarmed_body_fabric",
	chainmail = "blunt_unarmed_body_chainmail",
	plate = "blunt_unarmed_body_plate"
}

--- Movement foley, keyed by what the victim is wearing.
--
-- The third-person material foley the game plays when an NPC moves: cloth
-- swishes, leather creaks, mail rings, plate clanks. Right for a shove at
-- walking pace, which disturbs somebody's clothing rather than striking them.
--
-- @table BodyFoleySounds
HorseCollisionMod.BodyFoleySounds = {
	cloth = "f_n_mat_move_cl",
	leather = "f_n_mat_move_le",
	chainmail = "f_n_mat_move_ch",
	plate = "f_n_mat_move_pl"
}

--- Resolves the `foley` token to the movement foley for a victim's armor.
--
-- The same `heaviestType` indices `BodyImpactSound` reads, transcribed in
-- `ArmorTypeNames`: 2 and 3 are leather, 4 is chain, 5 is plate.
--
-- @tparam table armor the total from `ArmorOf`, or nil
-- @treturn string a trigger name
function HorseCollisionMod:BodyFoleySound(armor)
	local heaviest = armor and armor.heaviestType or 0

	if heaviest == 5 then
		return self.BodyFoleySounds.plate
	end

	if heaviest == 4 then
		return self.BodyFoleySounds.chainmail
	end

	if heaviest == 2 or heaviest == 3 then
		return self.BodyFoleySounds.leather
	end

	return self.BodyFoleySounds.cloth
end

--- Resolves the `body` token in a layer list to an armor-matched trigger.
--
-- `heaviestType` is the engine's armor type index, transcribed in
-- `ArmorTypeNames`: 4 is chain and 5 is plate. Everything else, including
-- leather and bare cloth, takes the fabric sample.
--
-- @tparam table armor the total from `ArmorOf`, or nil
-- @treturn string a trigger name
function HorseCollisionMod:BodyImpactSound(armor)
	local heaviest = armor and armor.heaviestType or 0

	if heaviest == 5 then
		return self.BodyImpactSounds.plate
	end

	if heaviest == 4 then
		return self.BodyImpactSounds.chainmail
	end

	return self.BodyImpactSounds.fabric
end

--- Plays the impact sound for one collision.
--
-- Called from `OnImpact` before the reaction is chosen, so the request goes
-- out ahead of the animation rather than behind it.
--
-- Firing it earlier than the collision does not work. A footprint reaching
-- sixty milliseconds of travel further forward sounds near misses, and sounds
-- the same victim twice, which is worse than a sound that is slightly late.
--
-- ### Layers
--
-- A tier names a list of `{ trigger, delayMs }` pairs rather than one sound,
-- because no single sound in the game is a horse striking a person. Vanilla
-- never makes that noise, so its library does not contain it: of twenty three
-- candidates, every one reads as a weapon, a footstep or a dropped object.
--
-- What works is the horse's own weight underneath a body impact:
-- `a_o_jump_landing` is the sound of the horse landing from a jump, and it is
-- the only sample in the game carrying that mass. A blunt body impact ten
-- milliseconds later reads as the thing it struck.
--
-- The offsets are small on purpose. Far enough apart to thicken the hit,
-- close enough that the ear takes them as one event rather than as a stack.
--
-- A layer is `{ trigger, delay, distance, chance }`. Distance is the volume
-- control and chance is how often the layer appears at all, which is the only
-- lever on a sample whose level cannot be changed.
--
-- Two literal trigger names are tokens, both replaced with the sample matching
-- the victim's armor: `body` is the blunt impact against that material, and
-- `foley` is the movement rustle it makes.
--
-- ### Balancing layers without a volume control
--
-- There is no gain on a trigger. Distance is the substitute, and it only
-- reaches events authored in 3D; `PlayAtDistance` documents what was measured.
-- Loudness upward comes from repetition instead, which is why a tier names the
-- same sample two or four times a few milliseconds apart.
--
-- Levels can only be judged from the saddle. Every sample here is clearly
-- audible standing still and most of them disappear under the horse's own
-- hoofbeats at speed, so a mix that sounds correct while parked is not the
-- mix that will be heard.
--
-- @tparam table npc victim entity
-- @tparam string tierName "Walk", "Trot" or "Gallop"
-- @tparam[opt] table armor the victim's armor total, for the body layer
-- @treturn boolean true when at least one layer was played
function HorseCollisionMod:PlayImpactSound(npc, tierName, armor)
	local cfg = self.Config

	if not cfg.ImpactSound or not npc then
		return false
	end

	local layers = cfg.ImpactSoundWalk

	if tierName == "Trot" then
		layers = cfg.ImpactSoundTrot
	elseif tierName == "Gallop" then
		layers = cfg.ImpactSoundGallop
	end

	if type(layers) ~= "table" then
		return false
	end

	-- The global is vanilla's, declared in Scripts/Utils/SoundUtils.lua, and
	-- is absent if that file has not loaded yet.
	if type(PlayAudioTrigger) ~= "function" then
		return false
	end

	-- A copy, because the crack is appended per collision and the config list
	-- must not grow every time someone is ridden down.
	local plan = {}

	for _, layer in ipairs(layers) do
		plan[#plan + 1] = layer
	end

	-- The bone crack is occasional and gallop only. Every gallop cracking
	-- bones would stop reading as an injury and start reading as a sound
	-- effect attached to the tier.
	local cracked = false

	if tierName == "Gallop" and type(cfg.ImpactSoundCrack) == "table"
			and math.random() < (cfg.ImpactSoundCrackChance or 0) then
		plan[#plan + 1] = cfg.ImpactSoundCrack
		cracked = true
	end

	local played = 0
	local names = {}

	for _, layer in ipairs(plan) do
		local trigger = layer[1]
		local delay = layer[2] or 0
		local distance = layer[3] or 0
		local chance = layer[4] or 1

		-- A layer may fire only some of the time. It is the only control over
		-- a sample whose level is fixed: `a_o_jump_landing` cannot be made
		-- quieter by distance or by obstruction, so the way to stop it
		-- dominating every collision is for it not to be in every collision.
		if chance < 1 and math.random() >= chance then
			trigger = nil
		end

		if trigger == "body" then
			trigger = self:BodyImpactSound(armor)
		elseif trigger == "foley" then
			trigger = self:BodyFoleySound(armor)
		end

		if type(trigger) == "string" and trigger ~= "" then
			played = played + 1
			names[#names + 1] = trigger
					.. (distance > 0 and ("@" .. tostring(distance)) or "")

			-- Captured, because the loop variable is reused and a timer fires
			-- long after this iteration has ended.
			local queued = trigger
			local far = distance

			local function fire()
				pcall(function()
					if far > 0 then
						self:PlayAtDistance(npc, queued, far)
					else
						PlayAudioTrigger(npc, queued)
					end
				end)
			end

			if delay <= 0 then
				fire()
			else
				Script.SetTimer(delay, fire)
			end
		end
	end

	if cfg.LogTelemetry then
		self:Log("ImpactSound tier=" .. tostring(tierName)
				.. " layers=" .. tostring(played)
				.. " played=" .. table.concat(names, ",")
				.. " cracked=" .. tostring(cracked))
	end

	return played > 0
end

--- Plays a trigger as if it came from further away, which is the only volume
-- control the engine offers.
--
-- No gain exists anywhere: the audio translation layer parses no volume
-- attribute, none of the game's 66 parameters is one, and the only volume
-- controls are the player's own master sliders. Distance is the substitute.
--
-- The offset is pushed along the line from the listener to the source, so the
-- sound arrives from the same direction it would have anyway and only its
-- level changes. Offsetting along an arbitrary axis instead moves the sound
-- across the stereo field, which is audible as panning rather than as volume.
--
-- `SetAudioProxyOffset` takes an entity-local vector, which is why the world
-- direction is converted through the entity's own axes. `Lightning.lua` uses
-- the same call for distant thunder.
--
-- It only works on events authored in 3D. Measured through speakers placed at
-- verified distances of 2 and 25 meters, `blunt_unarmed_body_fabric` was
-- inaudible at the far one and `a_o_jump_landing` was identical at both: the
-- landing lives under `hoofsteps_player` and ignores position entirely, so its
-- level is fixed and no distance will lower it.
--
-- @tparam table entity the entity the sound belongs to
-- @tparam string trigger the audio trigger name
-- @tparam number distance meters to push it back by
-- @treturn boolean true when the trigger resolved and was executed
function HorseCollisionMod:PlayAtDistance(entity, trigger, distance)
	local id = Sound.GetAudioTriggerID(trigger)

	if not id then
		return false
	end

	local offset = self:AwayFromListener(entity, distance)
	local proxy = entity:CreateAuxAudioProxy()

	entity:SetAudioProxyOffset(offset, proxy)
	entity:ExecuteAudioTrigger(id, proxy)

	Script.SetTimer(self.AudioProxyLifetimeMs, function()
		pcall(function()
			entity:RemoveAuxAudioProxy(proxy)
		end)
	end)

	return true
end

--- An entity-local offset that pushes a sound directly away from the listener.
--
-- The world vector from the player to the entity, normalized and scaled, then
-- expressed in the entity's own frame, because that is the space
-- `SetAudioProxyOffset` reads. Falls back to straight up when the listener is
-- on top of the entity, which happens while mounted and would otherwise push
-- the sound into the ground.
--
-- @tparam table entity the entity the proxy belongs to
-- @tparam number distance meters to push back by
-- @treturn table an entity-local offset vector
function HorseCollisionMod:AwayFromListener(entity, distance)
	local up = { x = 0, y = 0, z = distance }
	local listener, source = nil, nil

	pcall(function()
		listener = player:GetWorldPos()
		source = entity:GetWorldPos()
	end)

	if not listener or not source then
		return up
	end

	local vx = source.x - listener.x
	local vy = source.y - listener.y
	local vz = source.z - listener.z
	local length = math.sqrt((vx * vx) + (vy * vy) + (vz * vz))

	-- Too close to have a direction, so there is no line to push along.
	if length < 0.5 then
		return up
	end

	vx, vy, vz = (vx / length) * distance, (vy / length) * distance,
			(vz / length) * distance

	local ax, ay, az = nil, nil, nil

	pcall(function()
		ax = entity:GetDirectionVector(0)
		ay = entity:GetDirectionVector(1)
		az = entity:GetDirectionVector(2)
	end)

	if not ax or not ay or not az then
		return up
	end

	return {
		x = (vx * ax.x) + (vy * ax.y) + (vz * ax.z),
		y = (vx * ay.x) + (vy * ay.y) + (vz * ay.z),
		z = (vx * az.x) + (vy * az.y) + (vz * az.z)
	}
end
