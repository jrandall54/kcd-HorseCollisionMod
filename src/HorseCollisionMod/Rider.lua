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
-- @release 4.17.0
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
			-- A rider who can ride keeps their seat some of the time. The
			-- horse is still spent and still stops; the skill decides whether
			-- they come off with it.
			local _, seat = self:HorsemanshipScale(playerEnt)

			-- Only on the impact that empties the horse. Rolled on every
			-- impact it lets a rider keep their seat on a horse already at
			-- zero and go on hitting people indefinitely, which was measured:
			-- two saves in a row at 0.0 stamina with the streak continuing.
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
-- A particle effect in front of the camera does not work in its place. At a
-- gallop the rider covers the meter in front of them in a tenth of a second,
-- so a puff placed there is behind their head before it draws, and one far
-- enough ahead to be ridden into reads as a cloud hanging in the road rather
-- than as an impact.
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

--- Sends the horse off after it has thrown its rider.
--
-- A horse that has just dumped its rider because it was ridden into people
-- until it was spent should sometimes want nothing more to do with them. Not
-- every time: a horse that always bolts is a punishment, and one that
-- sometimes bolts is a horse.
--
-- ### Why this is a chance and not a health system
--
-- The horse taking health damage from impacts was built and removed. It worked
-- and it was legible in the log, but from the saddle it was a second invisible
-- stat racing the first to the same outcome, and the rider could not tell what
-- it was contributing. What was actually wanted from it was this one moment,
-- so this is the moment on its own.
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
-- What is used instead is the behavior already observed in game. Emptying the
-- horse's health throws the rider and sends the horse off, which is how the
-- 2.0.0-dev1 bug behaved when it charged 25 health an impact by mistake, and
-- how this reads when a horse is attacked. So the roll takes the health rather
-- than asking the AI for anything.
--
-- The health is restored a moment later, once the horse has already left. The
-- point is the bolt, not a crippled horse the rider has to nurse: nothing here
-- is a fight they chose, and a permanent cost for running out of stamina is
-- not what was wanted.
--
-- @tparam table horseEnt the player's horse entity
-- @tparam table playerEnt the player entity
-- @treturn boolean true when the horse was sent off
function HorseCollisionMod:BoltHorse(horseEnt, playerEnt)
	local cfg = self.Config

	if not cfg.HorseBoltsWhenSpent or not horseEnt or not playerEnt then
		return false
	end

	local chance = cfg.HorseBoltChance or 0

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
		horseEnt.soul:DealDamage(0, before, nil, true)
	end)

	-- Given back once it has gone. The bolt is the whole point and a horse
	-- left on nothing would be a lasting penalty for an ordinary spree.
	if ok then
		Script.SetTimer(cfg.HorseBoltRestoreMs or 3000, function()
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

	local top = cfg.HorsemanshipMaxLevel or 20
	local fraction = level / top

	if fraction > 1 then
		fraction = 1
	end

	-- Linear across the whole scale. Two curved shapes do not work, both
	-- measured in game: one spends the benefit in the first few levels, which
	-- leaves 13 riding like 20, and one withholds it until the last quarter,
	-- which makes every level below 16 feel identical. A straight line spreads
	-- the difference evenly, so each level is worth the same and the ends are
	-- still far apart.
	local remaining = 1.0 - fraction
	local worst = cfg.HorsemanshipStaminaWorst or 1.0
	local best = cfg.HorsemanshipStaminaBest or 1.0

	local stamina = best + ((worst - best) * remaining)
	local seat = (cfg.HorsemanshipSeatChance or 0) * (1.0 - remaining)

	return stamina, seat
end
