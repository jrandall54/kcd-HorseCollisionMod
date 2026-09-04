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
-- @release 4.8.0

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
-- Firing it earlier than the collision was tried and abandoned. A footprint
-- reaching sixty milliseconds of travel further forward sounded near misses
-- and sounded the same victim twice, which is worse than a sound that is
-- slightly late.
--
-- ### Layers
--
-- A tier names a list of `{ trigger, delayMs }` pairs rather than one sound,
-- because no single sound in the game is a horse striking a person. Vanilla
-- never makes that noise, so its library does not contain it, and twenty three
-- candidates were auditioned and rejected before layering was tried.
--
-- What works is the horse's own weight underneath a body impact:
-- `a_o_jump_landing` is the sound of the horse landing from a jump, and it is
-- the only sample in the game carrying that mass. A blunt body impact ten
-- milliseconds later reads as the thing it struck.
--
-- The offsets are small on purpose. Far enough apart to thicken the hit,
-- close enough that the ear takes them as one event rather than as a stack.
--
-- The literal trigger name `body` is a token, replaced with the sample
-- matching the victim's armor.
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

	-- Which entity the sound is hung on. The victim is the honest choice,
	-- because that is where the impact is and the helper positions the sound
	-- at the entity it is given. The rider is the alternative, and is louder
	-- and less positional.
	local on = npc

	if cfg.ImpactSoundOnRider and player then
		on = player
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

	for _, layer in ipairs(plan) do
		local trigger = layer[1]
		local delay = layer[2] or 0

		if trigger == "body" then
			trigger = self:BodyImpactSound(armor)
		end

		if type(trigger) == "string" and trigger ~= "" then
			played = played + 1

			if delay <= 0 then
				pcall(function()
					PlayAudioTrigger(on, trigger)
				end)
			else
				-- Captured, because the loop variable is reused and the timer
				-- fires long after this iteration has ended.
				local queued = trigger

				Script.SetTimer(delay, function()
					pcall(function()
						PlayAudioTrigger(on, queued)
					end)
				end)
			end
		end
	end

	if cfg.LogTelemetry then
		self:Log("ImpactSound tier=" .. tostring(tierName)
				.. " layers=" .. tostring(played)
				.. " body=" .. tostring(self:BodyImpactSound(armor))
				.. " cracked=" .. tostring(cracked)
				.. " onRider=" .. tostring(cfg.ImpactSoundOnRider and true or false))
	end

	return played > 0
end
