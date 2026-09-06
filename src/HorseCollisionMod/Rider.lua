--- Rider: what a collision costs the player and the horse.
--
-- The anti-bulldozing budget. Riding through a crowd has to end with Henry on
-- the ground rather than being a free way to scatter a dozen people, so every
-- impact at trot or gallop draws horse stamina, and a spent horse throws its
-- rider.
--
-- `IsCombatCollision` lives here despite its name. It decides how hard an
-- impact counts, not whether it is an offence, and the stamina multiplier is
-- its only consumer: charging into a fight costs the horse more than riding
-- through a market. Whether a collision is a crime is `Crime.lua`.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`. Every threshold and
-- multiplier is read from `Config` at call time.
--
-- @module HorseCollisionMod.Rider
-- @author jrandall54
-- @release 4.13.0
--- Whether this collision should count as a combat one.
--
-- Two independent signals, because neither alone is reliable:
--
-- * `player.soul:IsInCombatDanger()` is what vanilla scripts use, but it
--   reflects immediate danger rather than "a fight is happening", and reads
--   false for long stretches of an ongoing fight. Mounted and moving, the
--   player may not be in danger at the instant of each impact.
-- * The victim having a weapon drawn, which catches the case the first signal
--   misses: charging someone who is actively fighting.
--
-- **A drawn weapon does not mean a fight.** That signal was written believing
-- townsfolk never walk around armed, and a guard carrying a polearm does: he
-- holds it on patrol all day and so reads as armed permanently. That is why
-- polearm guards took no stagger at walking pace while every other NPC did.
-- The two signals are returned separately, and a caller meaning "a fight is
-- happening" must use the danger one alone.
--
-- Both raw values are logged so a disagreement between them is visible
-- rather than being hidden behind a single boolean.
--
-- @tparam table npc victim entity
-- @treturn boolean true when combat rules should apply
-- @treturn string diagnostic describing both signals
-- @treturn boolean whether the player is actually fighting, the only one of
--   the two signals that means combat rather than equipment
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

	return (danger == true or armed == true), detail, danger == true
end

--- Throws the rider from the horse.
--
-- Prefers the horse's own `RearAndThrowDown`, which plays the animation of
-- the animal rearing and unseating its rider. Falls back to ragdolling the
-- player, which is what earlier builds did and which reads as the player
-- collapsing rather than being thrown.
--
-- `RearAndThrowDown` is undocumented. It sits on the horse entity's `horse`
-- extension, alongside `HasRider` and `IsMountable`.
--
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
function HorseCollisionMod:ThrowRider(horseEnt, playerEnt)
	local thrown = false

	-- The method lives on the horse's own `horse` extension, found by
	-- enumerating what the entity actually carries. The other entries are
	-- kept as fallbacks in case a different mount type differs.
	local candidates = {
		{ name = "horse.horse", holder = horseEnt.horse },
		{ name = "horse", holder = horseEnt },
		{ name = "horse.actor", holder = horseEnt.actor }
	}

	for _, candidate in pairs(candidates) do
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

--- Charges the horse for an impact and dismounts Henry when it is spent.
--
-- Stamina is written with `soul:SetState`, never `soul:DealDamage`. That
-- call takes `(stamina, health, attacker, ...)`  -  stamina first  -  even though
-- vanilla's own debug helper names the parameters health-first, so using it
-- here silently injures the horse instead.
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
			self:Log("Horse spent - throwing rider.")
			self:ThrowRider(horseEnt, playerEnt)
		end
	end)
end

--- Shakes the rider's camera on a gallop impact.
--
-- A collision costs the rider stamina and costs the victim health, and neither
-- is visible from the saddle: hardcore mode hides the bars, and the horse's
-- own gait does not change. Half a ton of horse hitting a person should be
-- felt by the person riding it, and this is the only part of an impact that
-- reaches the player directly.
--
-- A trot gets a fraction of it through `CameraShakeTrotScale`, which scales
-- the angle, the shift and the duration together. A trot knockdown should
-- still read as a shove that happens to put someone down rather than as half a
-- ton of horse at speed, so the difference between the tiers is kept as a
-- difference of degree.
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
-- @tparam string tierName "Walk", "Trot" or "Gallop"; a walk never pulses
-- @treturn boolean true when a shake was requested
function HorseCollisionMod:ShakeRiderCamera(playerEnt, tierName)
	local cfg = self.Config

	if not cfg.CameraShake or not playerEnt or not playerEnt.actor then
		return false
	end

	-- A trot is the same kick at a fraction of it, on one number rather than a
	-- second set of values, for the same reason `BlurRiderView` scales: the
	-- shape is right and only the weight should differ between the tiers.
	local tier = 0

	if tierName == "Gallop" then
		tier = 1
	elseif tierName == "Trot" then
		tier = cfg.CameraShakeTrotScale or 0
	end

	if tier <= 0 then
		return false
	end

	local angle = (cfg.CameraShakeAngle or 0) * tier
			* (g_Deg2Rad or 0.0174532925)
	local shift = (cfg.CameraShakeShift or 0) * tier

	local ok = pcall(function()
		playerEnt.actor:SetViewShake(
				{ x = angle, y = angle, z = angle },
				{ x = shift, y = shift, z = shift },
				(cfg.CameraShakeDurationSec or 0.2) * tier,
				cfg.CameraShakeFrequency or 12,
				cfg.CameraShakeRandomness or 0.5)
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
-- and from the saddle in first person it is very nearly never seen: the impact
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
-- through are out of reach. What was confirmed working in game, by setting
-- each and looking:
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
-- Putting a particle effect in front of the camera instead was tried first and
-- abandoned. At a gallop the rider covers the meter in front of them in a
-- tenth of a second, so a puff placed there is behind their head before it
-- draws, and moving it far enough ahead to be ridden into read as a cloud
-- hanging in the road rather than as an impact.
--
-- ### Telling the views apart
--
-- `System.GetViewCameraPos` sits on the player in first person and meters away
-- in third: measured at 7.7 m behind and 4.6 m above with a third-person
-- camera mod running. Comparing it against the player's own position separates
-- them, which is what `RiderBlurFirstPersonOnly` uses, so a third-person
-- player does not get their screen blurred over an impact they can already
-- see.
--
-- **The blur amount is clamped.** Raising it from 0.9 to 1.3 to 2.0 produced
-- the same picture three times, so anything past about 1.0 is thrown away and
-- weight has to come from how long it is held and from what is layered under
-- it. `RiderBlurChroma` adds a chromatic shift on the same envelope, which is
-- a different distortion rather than more of the same one.
--
-- The blur is held at full for `RiderBlurHoldMs` before the decay starts. A
-- pulse that begins decaying on its first step never reaches the eye during a
-- gallop: it is competing with the camera shake and with the horse's own
-- motion, and raising the amount alone stopped helping well before it read.
--
-- The pulse always ends by writing zero. This parameter is global renderer
-- state rather than anything owned by the mod, so a decay that stopped partway
-- would leave the player's screen blurred for the rest of the session.
--
-- @tparam table playerEnt the player entity
-- @tparam string tierName "Walk", "Trot" or "Gallop"; a walk never pulses
-- @treturn boolean true when a pulse was started
function HorseCollisionMod:BlurRiderView(playerEnt, tierName)
	local cfg = self.Config

	if not cfg.RiderBlur or not playerEnt then
		return false
	end

	-- A trot is the same pulse at a fraction of it, on two numbers rather than
	-- a second set of five: one for how heavy it is and one for how long it
	-- lasts. They came apart in tuning, because a trot wanted the strength
	-- kept and the length cut, and a single scale could not do both.
	local tier, length = 0, 1

	if tierName == "Gallop" then
		tier = 1
	elseif tierName == "Trot" then
		tier = cfg.RiderBlurTrotScale or 0
		length = cfg.RiderBlurTrotLength or tier
	end

	if tier <= 0 then
		return false
	end

	local amount = (cfg.RiderBlurAmount or 0) * tier

	if amount <= 0 then
		return false
	end

	if cfg.RiderBlurFirstPersonOnly and not self:CameraIsFirstPerson(playerEnt) then
		return false
	end

	local steps = cfg.RiderBlurSteps or 5
	local hold = math.floor((cfg.RiderBlurHoldMs or 0) * length)
	local every = math.floor(((cfg.RiderBlurMs or 220) * length) / steps)

	local chroma = (cfg.RiderBlurChroma or 0) * tier

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

	return away <= (self.Config.RiderBlurFirstPersonRange or 1.5)
end
