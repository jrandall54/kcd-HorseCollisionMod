--- Sound: the noise a collision makes.
--
-- Vanilla plays nothing for a collision beyond the victim's bark and the
-- horse's own foley.
--
-- Vanilla's audio triggers are reachable from Lua through a global helper in
-- `Scripts/Utils/SoundUtils.lua`:
--
--     function PlayAudioTrigger(entity, param)
--         entity:ExecuteAudioTrigger(AudioUtils.LookupTriggerID(param),
--                 entity:GetDefaultAuxAudioProxyID())
--     end
--
-- The trigger names are the game's audio triggers, listed with their events in
-- `references/audio_triggers.tsv`. A name that does not exist plays nothing.
--
-- ### Why this is not in the animation data
--
-- A fragment's `PlaySound` procedural layer starts with the reaction, which
-- begins a detection tick and an interactive-action call after the contact,
-- so even at `ExitTime="0.0"` the sound lands late. Firing from here puts the
-- sound on the same line as the impact that detected it.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Sound
-- @author jrandall54

--- The material a victim's armor sounds like, by engine armor type.
--
-- `ArmorOf` reports the type of the heaviest piece a victim is wearing,
-- transcribed in `ArmorTypeNames`: 4 is chain and 5 is plate. Everything lighter, leather
-- included, sounds like cloth, because the blunt impact families are only
-- authored for three materials.
--
-- @tparam table armor the total from `ArmorOf`, or nil
-- @treturn string "fabric", "chainmail" or "plate"
function HorseCollisionMod:ArmorMaterial(armor)
	local heaviest = armor and armor.heaviestType or 0

	if heaviest == 5 then
		return "plate"
	end

	if heaviest == 4 then
		return "chainmail"
	end

	return "fabric"
end

--- Trigger name patterns for each token a layer may use.
--
-- A tier names a token rather than a trigger, and the material the victim is
-- wearing is substituted at the moment of impact. Every family here is
-- authored for all three materials, so a mailed guard and a peasant in cloth
-- are told apart by ear on every layer rather than only on one. Four tokens:
-- `body`, `body_armed`, `face_armed` and `blunt`.
--
-- @table ImpactTokens
HorseCollisionMod.ImpactTokens = {
	body = "blunt_unarmed_body_%s",
	body_armed = "blunt_armed_body_%s",
	face_armed = "blunt_armed_face_%s",
	blunt = "c_mfx_%s_sword_blunt_stopped"
}

--- Resolves a layer's trigger, substituting the victim's armor into a token.
--
-- A name that is not a token is returned untouched, so a tier may still name
-- a specific trigger where matching the armor would be wrong.
--
-- @tparam string trigger the name a layer carries
-- @tparam[opt] table armor the victim's armor total
-- @treturn string the trigger to play
function HorseCollisionMod:ResolveTrigger(trigger, armor)
	local pattern = self.ImpactTokens[trigger]

	if pattern then
		return string.format(pattern, self:ArmorMaterial(armor))
	end

	return trigger
end

--- Plays the impact sound for one collision.
--
-- Called from `OnImpact` before the reaction is chosen, so the request goes
-- out ahead of the animation rather than behind it.
--
-- Firing it earlier than the collision does not work: sounding ahead of
-- contact plays near misses, and sounds the same victim twice.
--
-- ### Layers
--
-- A tier names a list of layers rather than one sound, because no single
-- sound in the game is a horse striking a person. A layer is
-- `{ trigger, delay, distance, chance }`. The offsets are small, so the ear
-- takes the layers as one event. Distance is the volume control and chance is
-- how often the layer appears at all, which is the only lever on a sample
-- whose level cannot be changed. A trigger name that is a key of
-- `ImpactTokens` is replaced with the sample matching the victim's armor.
--
-- ### Balancing layers without a volume control
--
-- There is no gain on a trigger. Distance is the substitute, and it only
-- reaches events authored in 3D; see `PlayAtDistance`. Loudness upward comes
-- from repetition instead: a tier names the same sample more
-- than once a few milliseconds apart.
--
-- Levels can only be judged from the saddle. Every sample here is clearly
-- audible standing still and most of them disappear under the horse's own
-- hoofbeats at speed, so a mix that sounds correct while parked is not the
-- mix that will be heard.
--
-- And they can only be judged from the camera the player uses: the listener
-- follows the camera, so a third-person view starts several meters further
-- from the victim than a first-person one and hears the whole mix quieter.
--
-- @tparam table npc victim entity
-- @tparam string tierName an impact tier name
-- @tparam[opt] table armor the victim's armor total, for the body layer
-- @treturn boolean true when at least one layer was played
function HorseCollisionMod:PlayImpactSound(npc, tierName, armor)
	local cfg = self.Config

	if not cfg.ImpactSound or not npc then
		return false
	end

	local layers = self:TierValue("ImpactSoundByTier", tierName)

	-- The master level control, `ImpactSoundDistance`, added to every layer
	-- of the tier so the mix comes down as a whole and the balance between
	-- the layers is left alone.
	--
	-- Only the two loop tiers that ride into someone, trot and gallop, take it. Walk is movement
	-- foley rather than an impact, its samples are the quietest in use and are
	-- already doubled to be audible at all, so there is no headroom in them to
	-- give away. The rear and the charge are tuned as their own moves.
	local master = 0

	if tierName == "Trot" or tierName == "Gallop" then
		master = cfg.ImpactSoundDistance
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

	-- The bone crack is occasional, on a gallop or a charge. Every gallop cracking
	-- bones would stop reading as an injury and start reading as a sound
	-- effect attached to the tier.
	local cracked = false

	if (tierName == "Gallop" or tierName == "Charge")
			and type(cfg.ImpactSoundCrack) == "table"
			and math.random() < (cfg.ImpactSoundCrackChance) then
		plan[#plan + 1] = cfg.ImpactSoundCrack
		cracked = true
	end

	local played = 0
	local names = {}

	for _, layer in ipairs(plan) do
		local trigger = layer[1]
		local delay = layer[2] or 0
		local distance = (layer[3] or 0) + master
		local chance = layer[4] or 1

		-- A layer may fire only some of the time. It is the only control over
		-- a sample whose level is fixed: `a_o_jump_landing` cannot be made
		-- quieter by distance or by obstruction, so the way to stop it
		-- dominating every collision is for it not to be in every collision.
		if chance < 1 and math.random() >= chance then
			trigger = nil
		end

		if type(trigger) == "string" then
			trigger = self:ResolveTrigger(trigger, armor)
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

--- Henry's own grunt as the collision goes through him.
--
-- The game authors him three severities of taking a hit:
--
--     v_henry_hit_soft     event:/voice/henry_hit_soft
--     v_henry_hit_medium   event:/voice/henry_hit_medium
--     v_henry_hit_heavy    event:/voice/henry_hit_heavy
--
-- and `RiderVocalByTier` names one per tier; the shipped tiers use `soft` and
-- `heavy`.
--
-- ### Why this is not a bark
--
-- A bark names a set and the dialog system chooses the line, and the sets
-- available to Henry answer with full monologs. These are FMOD events fired
-- straight at the entity's audio proxy, the same call the impact foley above
-- uses, so the mod names the exact event and the dialog system is not
-- consulted: no monolog, no priority auction, and nothing a crime reaction can
-- take.
--
-- What it does not give is a choice of sample. An FMOD event may hold several
-- takes and randomize inside them, and that is internal to FMOD. The severity
-- is chosen; the variation within a severity is not.
--
-- ### The layer format is the impact layers'
--
-- `{ trigger, delayMs, distance, chance }`, read exactly as `PlayImpactSound`
-- reads a layer, so the knobs learned there transfer. `distance` is the only
-- volume control the engine offers and `PlayAtDistance` documents why. A tier
-- whose trigger is `""` is silent, which is how a tier is switched off without
-- switching off the others.
--
-- The delays are short and fall as the tier rises. The grunt belongs just
-- behind the thud rather than under it, and a heavier blow knocks the air out
-- sooner.
--
-- ### Why there is a cooldown
--
-- Riding into a group lands several collisions inside a second, and one grunt
-- per collision reads as broken audio rather than a rider being jolted. So
-- `RiderVocalCooldownMs` holds the next one off. One exception: a **harder**
-- impact, by `RiderVocalRankByTier`, is still allowed through, because a
-- gallop silenced by the walk shove just before it is the worse fault.
--
-- With the shipped ranks the worst case is two grunts in one window, rank 2
-- then rank 3. Riding through a crowd is all one tier and gets one grunt.
--
-- The stamp is taken when the grunt is *scheduled* rather than when it plays,
-- so collisions arriving inside the tier's own delay are still caught.
--
-- @tparam table playerEnt the player entity, as `ShakeRiderCamera` takes it
-- @tparam string tierName an impact tier name
-- @treturn boolean true when a trigger resolved and was played
function HorseCollisionMod:PlayRiderVocal(playerEnt, tierName)
	local cfg = self.Config

	if not cfg.RiderVocal or not playerEnt then
		return false
	end

	local layer = self:TierValue("RiderVocalByTier", tierName)
	local rank = self:TierValue("RiderVocalRankByTier", tierName) or 1

	if type(layer) ~= "table" then
		return false
	end

	local trigger = layer[1]
	local delay = layer[2] or 0
	local distance = layer[3] or 0
	local chance = layer[4] or 1

	if type(trigger) ~= "string" or trigger == "" then
		return false
	end

	-- The global is vanilla's, declared in Scripts/Utils/SoundUtils.lua, and is
	-- absent if that file has not loaded yet. Checked for the same reason
	-- `PlayImpactSound` checks it, and before the telemetry below so a line
	-- cannot claim a play that had nothing to play it.
	if type(PlayAudioTrigger) ~= "function" then
		return false
	end

	local now = self:TimeMs()
	local cooldown = cfg.RiderVocalCooldownMs

	-- One gate for everything that comes out of Henry's mouth, shared with
	-- `BarkRiderImpact`. A spoken line and a grunt on the same impact is two
	-- voices at once, so whichever goes out first holds the other off.
	local until_ = self.RiderVoiceUntil or 0
	local longest = math.max(cooldown, cfg.RiderBarkCooldownMs)

	-- A hold further out than the longest cooldown means the save clock was
	-- wound back by a load; it is ignored, as in `RiderVoiceReady`.
	if (until_ - now) > longest then
		until_ = 0
	end

	-- A harder impact still speaks. A spoken line stamps a rank above every
	-- grunt, so no grunt interrupts it.
	if now < until_ and rank <= (self.RiderVoiceRank or 0) then
		if cfg.LogTelemetry then
			self:Log("RiderVocal tier=" .. tostring(tierName)
					.. " trigger=" .. trigger .. " skipped=cooldown"
					.. " for=" .. string.format("%.0f", until_ - now) .. "ms more"
					.. " rank=" .. tostring(rank)
					.. " held=" .. tostring(self.RiderVoiceRank))
		end

		return false
	end

	-- Rolled before the timer is set, so the telemetry line says what the
	-- collision actually did rather than what it intended.
	--
	-- After the cooldown, not before it: a roll that loses should not also
	-- start a cooldown, or a lost roll would silence the next impact too.
	if chance < 1 and math.random() >= chance then
		if cfg.LogTelemetry then
			self:Log("RiderVocal tier=" .. tostring(tierName)
					.. " trigger=" .. trigger .. " skipped=chance")
		end

		return false
	end

	self.RiderVoiceUntil = now + cooldown
	self.RiderVoiceRank = rank

	local function fire()
		pcall(function()
			if distance > 0 then
				self:PlayAtDistance(playerEnt, trigger, distance)
			else
				PlayAudioTrigger(playerEnt, trigger)
			end
		end)
	end

	if delay <= 0 then
		fire()
	else
		Script.SetTimer(delay, fire)
	end

	if cfg.LogTelemetry then
		self:Log("RiderVocal tier=" .. tostring(tierName)
				.. " trigger=" .. trigger
				.. " delay=" .. tostring(delay) .. "ms"
				.. " distance=" .. tostring(distance))
	end

	return true
end

--- Plays a horse vocalization on the horse entity at each impact tier.
--
-- Mirrors `PlayRiderVocal`, played on the horse. The horse has its own voice
-- gate (`HorseVoiceUntil` and `HorseVoiceRank`), so a rapid series of
-- collisions does not produce a chorus: a harder impact is still let through,
-- and equal or lighter ones are held off.
--
-- @tparam table horseEnt the horse entity
-- @tparam string tierName an impact tier name
-- @treturn boolean true when a trigger resolved and was played
function HorseCollisionMod:PlayHorseVocal(horseEnt, tierName)
	local cfg = self.Config

	if not cfg.HorseVocal or not horseEnt then
		return false
	end

	local layer = self:TierValue("HorseVocalByTier", tierName)
	local rank  = self:TierValue("HorseVocalRankByTier", tierName) or 1

	if type(layer) ~= "table" then
		return false
	end

	local trigger  = layer[1]
	local delay    = layer[2] or 0
	local distance = layer[3] or 0
	local chance   = layer[4] or 1

	if type(trigger) ~= "string" or trigger == "" then
		return false
	end

	-- Same guard as PlayRiderVocal: the global may not exist yet.
	if type(PlayAudioTrigger) ~= "function" then
		return false
	end

	local now      = self:TimeMs()
	local cooldown = cfg.HorseVocalCooldownMs

	local until_ = self.HorseVoiceUntil or 0
	local longest = cooldown

	if (until_ - now) > longest then
		until_ = 0
	end

	if now < until_ and rank <= (self.HorseVoiceRank or 0) then
		if cfg.LogTelemetry then
			self:Log("HorseVocal tier=" .. tostring(tierName)
					.. " trigger=" .. trigger .. " skipped=cooldown"
					.. " for=" .. string.format("%.0f", until_ - now) .. "ms more"
					.. " rank=" .. tostring(rank)
					.. " held=" .. tostring(self.HorseVoiceRank))
		end
		return false
	end

	if chance < 1 and math.random() >= chance then
		if cfg.LogTelemetry then
			self:Log("HorseVocal tier=" .. tostring(tierName)
					.. " trigger=" .. trigger .. " skipped=chance")
		end
		return false
	end

	self.HorseVoiceUntil = now + cooldown
	self.HorseVoiceRank  = rank

	local function fire()
		pcall(function()
			if distance > 0 then
				self:PlayAtDistance(horseEnt, trigger, distance)
			else
				PlayAudioTrigger(horseEnt, trigger)
			end
		end)
	end

	if delay <= 0 then
		fire()
	else
		Script.SetTimer(delay, fire)
	end

	if cfg.LogTelemetry then
		self:Log("HorseVocal tier=" .. tostring(tierName)
				.. " trigger=" .. trigger
				.. " delay=" .. tostring(delay) .. "ms"
				.. " distance=" .. tostring(distance))
	end

	return true
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
-- `SetAudioProxyOffset` takes an entity-local vector, so the world
-- direction is converted through the entity's own axes. `Lightning.lua` uses
-- the same call for distant thunder.
--
-- It only works on events authored in 3D. `a_o_jump_landing` lives under
-- `hoofsteps_player`, which ignores position, so its level is fixed and no
-- distance lowers it.
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
-- The player's position stands in for the listener, which follows the camera.
-- The world vector from the player to the entity, normalized and scaled, is
-- expressed in the entity's own frame, because that is the space
-- `SetAudioProxyOffset` reads. Falls back to straight up when the listener is
-- within half a meter of the entity, as it is while mounted, where there is
-- no direction to push along and a guess could push the sound into the
-- ground.
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
