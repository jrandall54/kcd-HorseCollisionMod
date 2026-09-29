--- Rider: what a collision does to the player and the horse.
--
-- The anti-bulldozing budget. Riding through a crowd has to end with Henry on
-- the ground rather than being a free way to scatter a dozen people, so every
-- impact but a walk draws horse stamina, and a spent horse throws its rider
-- and sometimes bolts. The file also holds the rider's camera shake and blur,
-- the Horsemanship scale, `GrantPerks`, and `PlayerHorse`.
--
-- `IsCombatCollision` lives here despite its name. It decides how hard an
-- impact counts, not whether it is an offense: charging into a fight costs
-- the horse more than riding through a market. Whether a collision is a crime
-- is `Crime.lua`.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. Every threshold and
-- multiplier is read from `Config` at call time.
--
-- @module HorseCollisionMod.Rider
-- @author jrandall54

--- The player's horse entity.
--
-- @treturn ?table the horse, or nil when the player has none or it cannot be
--   read
function HorseCollisionMod:PlayerHorse()
	local horse = nil

	pcall(function()
		horse = XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())
	end)

	return horse
end

--- Whether an impact happens in a fight, for the combat stamina surcharge.
--
-- @tparam ?table npc the victim, whose drawn weapon is logged only
-- @treturn boolean true when the player is in combat danger
-- @treturn string the readings, for the log
function HorseCollisionMod:IsCombatCollision(npc)
	local danger = false
	local dangerOk = false
	local armed = false
	local armedOk = false

	dangerOk = pcall(function()
		if player.soul and player.soul.IsInCombatDanger then
			danger = player.soul:IsInCombatDanger()
		end
	end)

	armedOk = pcall(function()
		if npc.human and npc.human.IsWeaponDrawn then
			armed = npc.human:IsWeaponDrawn()
		end
	end)

	local detail = "danger=" .. tostring(danger) .. "/" .. tostring(dangerOk)
			.. " armed=" .. tostring(armed) .. "/" .. tostring(armedOk)

	-- The player's own combat state decides this, and nothing else. The
	-- victim's drawn weapon is logged only, because guards patrol with weapons
	-- drawn and would take the surcharge out of combat.
	return danger == true, detail
end

--- Throws the rider from the horse.
--
-- Prefers the horse's own `RearAndThrowDown`, which plays the animation of
-- the animal rearing and unseating its rider. Falls back to ragdolling the
-- player, which reads as the player collapsing rather than being thrown.
--
-- `RearAndThrowDown` is undocumented. It sits on the horse entity's `horse`
-- extension, alongside `HasRider` and `IsMountable`.
--
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
function HorseCollisionMod:ThrowRider(horseEnt, playerEnt)
	local thrown = false

	-- The method lives on the horse's own `horse` extension, found by
	-- enumerating what the entity actually carries; the other two holders are
	-- fallbacks. The first holder that has it and accepts the call wins.
	local candidates = {
		{ name = "horse.horse", holder = horseEnt.horse },
		{ name = "horse", holder = horseEnt },
		{ name = "horse.actor", holder = horseEnt.actor }
	}

	for _, candidate in ipairs(candidates) do
		if not thrown and candidate.holder
				and type(candidate.holder.RearAndThrowDown) == "function" then
			local ok = pcall(function()
				candidate.holder:RearAndThrowDown()
			end)

			self:Log("ThrowRider via " .. candidate.name .. " ok=" .. tostring(ok))

			if ok then
				thrown = true
			end
		end
	end

	if not thrown then
		self:Log("ThrowRider falling back to player ragdoll")

		pcall(function()
			playerEnt.actor:Fall({x=0, y=0, z=0}, true)
		end)
	end
end

--- What one impact costs the horse, and charging it.
--
-- The single place the stamina figure is worked out. Every tier goes through
-- it, so the rider's Horsemanship, the horse's barding and the combat
-- surcharge reach a rear and a charge exactly as they reach a gallop.
--
-- The cost is a share of the horse's own maximum stamina, and the three
-- situational factors are surcharges on that share rather than multipliers on
-- it:
--
--     cost = maxStamina
--          * (tierShare + combatAdd + armorAdd - bardingRelief)
--          * horsemanship
--
-- Adding the surcharges makes every term readable on its own and the worst
-- case the sum of the named maxima rather than an emergent product: 0.20 +
-- 0.13 + 0.05 = 0.38 of the pool before Horsemanship, which the log prints
-- term by term.
--
-- Horsemanship stays a multiplier, because it is the one factor meant to
-- dominate. The progressive drain at low Horsemanship is settled design: at
-- level 0 a single gallop impact empties the horse, and that is the point.
--
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
-- @tparam string tierName an impact tier name
-- @tparam[opt] table armor the victim's armor from `ArmorOf`, where this
--   impact has a single victim to read it from
function HorseCollisionMod:DrainImpactStamina(horseEnt, playerEnt, tierName, armor)
	local share = self:TierValue("StaminaShareByTier", tierName)

	if type(share) ~= "number" or share <= 0 then
		return
	end

	local pool = self:MaxStaminaOf(horseEnt)

	if not pool or pool <= 0 then
		return
	end

	-- The victim's armor is the one surcharge that does not always apply.
	--
	-- A rear and a charge are charged once for the whole move and that move
	-- can land on several people at once, so there is no single victim whose
	-- armor to read and the cost is scored on the horse and rider alone. The
	-- loop tiers resolve one victim per impact and pass theirs.
	local armorAdd = 0.0

	if armor then
		armorAdd = self:ArmorStaminaAdd(armor)
	end

	local combatAdd = 0.0

	-- Decided by the player's own combat state and nothing about the victim,
	-- so this answers correctly for a rear and a charge with no
	-- victim to hand.
	if self:IsCombatCollision(nil) then
		combatAdd = self.Config.CombatStaminaAdd
	end

	local bardingRelief = self:BardingStaminaRelief(horseEnt)
	local horsemanship = self:HorsemanshipScale(playerEnt)
	local total = share + combatAdd + armorAdd - bardingRelief

	-- Floored rather than allowed to go negative, so that a fully barded horse
	-- on a tier with a small share is never paid stamina for an impact.
	if total < 0 then
		total = 0
	end

	local cost = pool * total * horsemanship

	-- Logged beside the figure it produces rather than on the impact line,
	-- because a cost that looks wrong is diagnosed by which term moved it.
	if self.Config.LogTelemetry then
		self:Log("Stamina tier=" .. tostring(tierName)
				.. " pool=" .. string.format("%.1f", pool)
				.. " share=" .. string.format("%.3f", share)
				.. " combat=" .. string.format("%.3f", combatAdd)
				.. " armor=" .. string.format("%.3f", armorAdd)
				.. " barding=" .. string.format("%.3f", bardingRelief)
				.. " horsemanship=" .. string.format("%.2f", horsemanship)
				.. " cost=" .. string.format("%.1f", cost))
	end

	self:DrainHorseStamina(horseEnt, playerEnt, cost)
end

--- The horse's maximum stamina, the pool every cost is a share of.
--
-- `mst` is the engine's own derived stat for maximum stamina, the figure
-- vanilla's own feature tests read to check a stamina potion worked. It is
-- read per impact rather than cached because a buff or a potion can move it
-- between one impact and the next.
--
-- @tparam table ent an entity with a soul
-- @treturn number|nil the maximum stamina, or nil when it cannot be read
function HorseCollisionMod:MaxStaminaOf(ent)
	if not ent or not ent.soul then
		return nil
	end

	local pool = nil

	pcall(function()
		pool = ent.soul:GetDerivedStat("mst")
	end)

	if type(pool) ~= "number" or pool <= 0 then
		return nil
	end

	return pool
end

--- Charges the horse for an impact and dismounts Henry when it is spent.
--
-- Stamina is written with `soul:SetState`, never `soul:DealDamage`.
-- `C_ScriptBindSoul` declares that call `DealDamage(float stamina, float
-- health)`, stamina first, while vanilla's own debug helper names the
-- parameters health-first, so it is easy to injure the horse by mistake.
--
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
-- @tparam number staminaDrain points of stamina to remove
function HorseCollisionMod:DrainHorseStamina(horseEnt, playerEnt, staminaDrain)
	if not staminaDrain or staminaDrain <= 0 or not horseEnt or not playerEnt then
		return
	end

	pcall(function()
		if not horseEnt.soul then
			return
		end

		local before = horseEnt.soul:GetState("stamina")

		if not before then
			return
		end

		-- Clamped at zero rather than allowed to go negative, so that a
		-- single heavy impact cannot bank a deficit the horse then has to
		-- recover from before it can move again.
		local target = before - staminaDrain

		if target < 0 then
			target = 0
		end

		horseEnt.soul:SetState("stamina", target)

		self:Log("Horse stamina " .. string.format("%.1f", before)
				.. " -> " .. string.format("%.1f", target))

		if not self.Config.ThrowRiderOnStaminaEmpty then
			return
		end

		if target <= 0 and playerEnt.actor then
			-- A rider who can ride keeps their seat some of the time. The
			-- horse is still spent and still stops; the skill decides whether
			-- they come off with it.
			local _, seat = self:HorsemanshipScale(playerEnt)

			-- Only on the impact that empties the horse. Rolled on every
			-- impact it would let a rider keep their seat on a horse already
			-- at zero and go on hitting people indefinitely.
			if before <= 0 then
				seat = 0
			end

			if seat > 0 and math.random() < seat then
				self:Log("Horse spent - rider kept their seat, chance="
						.. string.format("%.2f", seat))

				return
			end

			self:Log("Horse spent - throwing rider.")
			self:ThrowRider(horseEnt, playerEnt)

			-- After the throw, so the horse is rid of the rider before it is
			-- given a reason to leave.
			self:BoltHorse(horseEnt, playerEnt)
		end
	end)
end

--- Shakes the rider's camera on an impact.
--
-- A collision costs the rider stamina and costs the victim health, and neither
-- is visible from the saddle: hardcore mode hides the bars, and the horse's
-- own gait does not change. This is the part of an impact that reaches the
-- player directly.
--
-- `CameraShakeByTier` scales the angle, the shift and the duration together,
-- so the tiers differ by degree; a tier with no entry does not shake.
--
-- ### The call
--
-- `actor:SetViewShake` is what vanilla's own explosion shake uses, in
-- `SinglePlayer:ViewShake`:
--
--     player.actor:SetViewShake({ x = 2 * g_Deg2Rad * amt, ... },
--             { x = 0.02 * amt, ... }, duration, 1 / 20, rnd)
--
-- The first vector is an angular shake in radians and the second a positional
-- one in meters, so the degrees are converted rather than passed raw. The
-- frequency is oscillations per second and vanilla's 1/20 is a slow roll
-- suited to a distant blast; an impact wants a fast one that is over before
-- the victim has landed. Randomness breaks the regularity so repeated
-- collisions do not shake identically.
--
-- `actor:CameraShake` exists too and is what `BasicActor` calls when the
-- player is hit. It is not used here: it takes its own amount and frequency
-- with no positional component, so the shake it produces is a rotation only.
--
-- @tparam table playerEnt the player entity
-- @tparam string tierName an impact tier name
-- @treturn boolean true when a shake was requested
function HorseCollisionMod:ShakeRiderCamera(playerEnt, tierName)
	local cfg = self.Config

	if not cfg.CameraShake or not playerEnt or not playerEnt.actor then
		return false
	end

	-- Not while the rider is leaning out.
	--
	-- Both effects are `SetViewShake`, and a second call does not add to the
	-- first, it **reverses the camera's direction of travel**. An impact during
	-- a lean therefore does not jolt the view, it turns the lean around and
	-- sends the camera home, which is precisely the moment the rider leaned out
	-- to watch: the feature exists so they can see who they are about to hit.
	--
	-- Suppressed rather than scaled, because any amplitude at all flips the
	-- direction. The shake is feedback and the lean is aim, and the aim wins
	-- while it is deliberately held.
	if cfg.LeanSuppressShake and self.LeanHeld then
		if cfg.LogTelemetry then
			self:Log("CameraShake suppressed tier=" .. tostring(tierName)
					.. " reason=leaning")
		end

		return false
	end

	-- Each tier is the same kick at its own weight, on one number rather than
	-- a set of values per tier.
	local tier = self:TierValue("CameraShakeByTier", tierName) or 0

	if tier <= 0 then
		return false
	end

	local angle = math.rad(cfg.CameraShakeAngle * tier)
	local shift = cfg.CameraShakeShift * tier

	local ok = pcall(function()
		playerEnt.actor:SetViewShake(
				{ x = angle, y = angle, z = angle },
				{ x = shift, y = shift, z = shift },
				cfg.CameraShakeDurationSec * tier,
				cfg.CameraShakeFrequency,
				cfg.CameraShakeRandomness)
	end)

	if cfg.LogTelemetry then
		self:Log("CameraShake tier=" .. tostring(tierName)
				.. " angle=" .. string.format("%.3f", angle)
				.. " shift=" .. string.format("%.3f", shift)
				.. " ok=" .. tostring(ok))
	end

	return ok
end

--- Blurs the rider's view for a moment on an impact.
--
-- The dust the collision throws up is on the ground behind the horse's neck,
-- and from the saddle in first person it is almost never seen: the impact
-- happens below the field of view at ten meters a second. Third person gets
-- the whole thing and first person gets none of it, so first person needs
-- something of its own, and it has to be on the camera rather than in the
-- world.
--
-- ### What the engine actually offers
--
-- `System.SetScreenFx(param, value)` is the only Lua surface onto the
-- renderer's post effects. No script bind exposes the material effect or HUD
-- systems at all, so the flowgraphs the game drives its own screen effects
-- through are out of reach. In game:
--
--     ScreenFrost_Amount          frosts the screen
--     WaterDroplets_Amount        droplets on the lens
--     FilterBlurring_Amount       blurs the screen
--     FilterRadialBlurring_*      nothing, at any amount
--
-- There is no dust or dirt lens overlay. Frost and water droplets are the only
-- two, and neither is a horse hitting somebody. A plain blur pulse is what is
-- left, and it is the same language the game itself uses for taking a hit:
-- `Libs/MaterialEffects/Flowgraphs/player_damage.xml` is a radial blur and
-- nothing else. Radial is the variant that does not work from here, so this
-- uses the one that does.
--
-- A particle effect in front of the camera does not work in its place. At a
-- gallop the rider covers the meter in front of them in a tenth of a second,
-- so a puff placed there is behind their head before it draws, and one far
-- enough ahead to be ridden into reads as a cloud hanging in the road rather
-- than as an impact.
--
-- ### Telling the views apart
--
-- `CameraIsFirstPerson` tells the views apart, which is what
-- `RiderBlurFirstPersonOnly` uses, so a third-person player does not get
-- their screen blurred over an impact they can already see.
--
-- **The blur amount has no effect past about 1.0**, so weight comes from how
-- long it is held and from what is layered under it. `RiderBlurChroma` adds a
-- chromatic shift on the same envelope, a different distortion rather than
-- more of the same one.
--
-- The blur is held at full for `RiderBlurHoldMs` before the decay starts. A
-- pulse that begins decaying on its first step never reaches the eye during a
-- gallop, competing with the camera shake and the horse's own motion.
--
-- The pulse always ends by writing zero. This parameter is global renderer
-- state rather than anything owned by the mod, so a decay that stopped partway
-- would leave the player's screen blurred for the rest of the session.
--
-- @tparam table playerEnt the player entity
-- @tparam string tierName an impact tier name; a tier with no entry never
--   pulses
-- @treturn boolean true when a pulse was started
function HorseCollisionMod:BlurRiderView(playerEnt, tierName)
	local cfg = self.Config

	if not cfg.RiderBlur or not playerEnt then
		return false
	end

	-- Each tier is the same pulse on two numbers: how heavy it is and how
	-- long it lasts. They are separate because a trot keeps the strength and
	-- cuts the length.
	local tier = self:TierValue("RiderBlurByTier", tierName) or 0
	local length = self:TierValue("RiderBlurLengthByTier", tierName) or tier

	if tier <= 0 then
		return false
	end

	local amount = cfg.RiderBlurAmount * tier

	if amount <= 0 then
		return false
	end

	if cfg.RiderBlurFirstPersonOnly and not self:CameraIsFirstPerson(playerEnt) then
		return false
	end

	local steps = math.max(1, cfg.RiderBlurSteps)
	local hold = math.floor(cfg.RiderBlurHoldMs * length)
	local every = math.floor((cfg.RiderBlurMs * length) / steps)

	local chroma = cfg.RiderBlurChroma * tier

	pcall(function()
		System.SetScreenFx("FilterBlurring_Type", 0)
		System.SetScreenFx("FilterBlurring_Amount", amount)

		if chroma > 0 then
			System.SetScreenFx("FilterChromaShift_User_Amount", chroma)
		end
	end)

	-- Every step is booked up front rather than each one booking the next, so
	-- the write that clears it cannot be lost by a step failing partway.
	for step = 1, steps do
		local left = amount * (1 - (step / steps))

		local leftChroma = chroma * (1 - (step / steps))

		Script.SetTimer(hold + (step * every), function()
			pcall(function()
				System.SetScreenFx("FilterBlurring_Amount", left)

				if chroma > 0 then
					System.SetScreenFx("FilterChromaShift_User_Amount", leftChroma)
				end
			end)
		end)
	end

	if cfg.LogTelemetry then
		self:Log("RiderBlur tier=" .. tostring(tierName)
				.. " amount=" .. string.format("%.2f", amount)
				.. " hold=" .. tostring(hold) .. "ms"
				.. " over=" .. tostring(steps * every) .. "ms")
	end

	return true
end

--- Whether the camera is on the player rather than behind them.
--
-- The view camera is the eye and the listener both. In first person it sits on
-- the player; in third it is meters away, measured at 7.7 m behind and 4.6 m
-- above with a third-person camera mod running. Anything closer than
-- `RiderBlurFirstPersonRange` counts as first person.
--
-- @tparam table playerEnt the player entity
-- @treturn boolean true when the camera is on the player
function HorseCollisionMod:CameraIsFirstPerson(playerEnt)
	local cam, pos = nil, nil

	pcall(function()
		cam = System.GetViewCameraPos()
		pos = playerEnt:GetWorldPos()
	end)

	if not cam or not pos then
		return false
	end

	local dx = cam.x - pos.x
	local dy = cam.y - pos.y
	local dz = cam.z - pos.z
	local away = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

	return away <= self.Config.RiderBlurFirstPersonRange
end

--- Sends the horse off after it has thrown its rider.
--
-- A horse that has just dumped its rider because it was ridden into people
-- until it was spent sometimes wants nothing more to do with them, on
-- `HorseBoltChance`.
--
-- ### How, and why not by message
--
-- `combat:stimulus:hostilePerception` does not work here, despite the horse's
-- own combat subbrain declaring `t_fleeParams` as `wherever(true)`, which
-- would make it flee from anything it perceived. The known trap applies: a
-- `ProcessMessage` only receives while its subtree is running, and
-- `sb_combat_playerHorse.xml` is a bare `Wait` with no behavior in it, so the
-- player's horse has no combat brain to receive anything.
--
-- Emptying the horse's health throws the rider and sends the horse off, as it
-- does when a horse is attacked, so the roll takes the health rather than
-- asking the AI for anything. The health is restored after
-- `HorseBoltRestoreMs`, once the horse has left, so the cost is the bolt and
-- not a crippled horse.
--
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
-- @treturn boolean true when the horse was sent off
function HorseCollisionMod:BoltHorse(horseEnt, playerEnt)
	local cfg = self.Config

	if not cfg.HorseBoltsWhenSpent or not horseEnt or not playerEnt then
		return false
	end

	local chance = cfg.HorseBoltChance

	if chance <= 0 or math.random() >= chance then
		return false
	end

	local before = nil

	pcall(function()
		before = horseEnt.soul:GetState("health")
	end)

	if not before or before <= 0 then
		return false
	end

	local ok, err = pcall(function()
		horseEnt.soul:DealDamage(0, before)
	end)

	-- Given back once it has gone. The bolt is the whole point and a horse
	-- left on nothing would be a lasting penalty for an ordinary spree.
	if ok then
		Script.SetTimer(cfg.HorseBoltRestoreMs, function()
			pcall(function()
				horseEnt.soul:SetState("health", before)
			end)
		end)
	end

	if cfg.LogTelemetry then
		self:Log("HorseBolt chance=" .. string.format("%.2f", chance)
				.. " took=" .. string.format("%.1f", before)
				.. " ok=" .. tostring(ok)
				.. " err=" .. tostring(err))
	end

	return ok
end

--- What the rider's horsemanship is worth against a collision.
--
-- `player.soul:GetSkillLevel("horse_riding")` is the skill, on the game's own
-- 0 to 20 scale, and it is the stat the game itself calls Horsemanship. A
-- rider who can actually ride keeps their seat through a collision that would
-- put a novice on the ground, and spends less of the horse under them doing
-- it.
--
-- Returns two numbers rather than one, because the skill should not be a
-- single blunt discount: a stamina multiplier, which is what makes a long ride
-- possible at all, and the chance of keeping the saddle when the horse is
-- spent, which is what makes the skill felt at the moment it matters.
--
-- Both run linearly from level 0 to `HorsemanshipMaxLevel`. The range is what
-- carries the difference rather than any curve: a novice is thrown by a single
-- gallop impact and a rider at 20 rides through four or five armored guards.
--
-- @tparam table playerEnt the player entity
-- @treturn number a multiplier on the horse's stamina cost
-- @treturn number the chance of keeping the saddle, 0 to 1
function HorseCollisionMod:HorsemanshipScale(playerEnt)
	local cfg = self.Config

	if not cfg.Horsemanship or not playerEnt or not playerEnt.soul then
		return 1.0, 0.0
	end

	local level = nil

	pcall(function()
		level = playerEnt.soul:GetSkillLevel(cfg.HorsemanshipSkill)
	end)

	if type(level) ~= "number" or level <= 0 then
		return 1.0, 0.0
	end

	local top = cfg.HorsemanshipMaxLevel
	local fraction = level / top

	if fraction > 1 then
		fraction = 1
	end

	-- Linear across the whole scale, so each level is worth the same and the
	-- ends are still far apart.
	local remaining = 1.0 - fraction
	local worst = cfg.HorsemanshipStaminaWorst
	local best = cfg.HorsemanshipStaminaBest

	local stamina = best + ((worst - best) * remaining)
	local seat = cfg.HorsemanshipSeatChance * (1.0 - remaining)

	return stamina, seat
end

--- The mod's Horsemanship maneuvers, in the order their banners are shown.
--
-- `perk` is the perk in `perk__horsecollisionmod.xml` that grants the
-- maneuver, `ability` the ability that perk unlocks, and `banner` the name
-- `ShowTutorial` knows it by.
--
-- @table Maneuvers
HorseCollisionMod.Maneuvers = {
	{ banner = "lean", ability = "hcm_lean",
		perk = "13ed04b3-297d-43ca-9fb8-d3a3a1192f9c" },
	{ banner = "rear", ability = "hcm_rear",
		perk = "da38020a-eecf-45b5-8203-34b0b678600a" },
	{ banner = "charge", ability = "hcm_charge",
		perk = "6a0ca946-cce5-4c2b-831a-585db059027d" },
}

--- Grants the mod's Horsemanship perks directly to the player soul.
--
-- Called from `ApplySettings` on every load screen when `AutoGrantPerks` is
-- on.
function HorseCollisionMod:GrantPerks()
	if not player or not player.soul then
		return
	end

	for _, maneuver in ipairs(self.Maneuvers) do
		pcall(function()
			player.soul:AddPerk(maneuver.perk)
		end)
	end
end
