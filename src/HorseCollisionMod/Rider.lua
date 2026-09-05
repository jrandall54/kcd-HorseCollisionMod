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
-- @release 4.10.0
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
