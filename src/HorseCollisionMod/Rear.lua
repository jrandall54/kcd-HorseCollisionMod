--- Rearing the horse on command.
--
-- Everything else this mod does needs speed. A rear is what a rider has at a
-- standstill: the horse goes up on its hind legs and comes down on whoever is
-- in front.
--
-- Attached to the `HorseCollisionMod` table created by the entry point, which
-- pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Rear
-- @author jrandall54

--- The keys the mod's action map declares, and so the only ones selectable.
--
-- Kept beside the reader that uses it, because the two have to agree with
-- `Libs/Config/hcm_actionmaps.xml` and a key added there and not here is
-- unusable, while one here and not there names an action that does not exist.
HorseCollisionMod.RearKeys = {
	r = true, q = true, y = true, u = true, o = true, h = true
}

--- The action name a configured key maps to.
--
-- The mod cannot rebind a key at runtime, because Lua cannot write files and
-- `LoadFromXML` only reads one. So `hcm_actionmaps.xml` declares each feature
-- once per candidate key and the settings file picks which by naming the key.
-- An action nobody listens for costs nothing.
--
-- @tparam string key the key named in the settings, such as "r"
-- @tparam[opt] boolean onlyRear true for the rear on the spot
-- @treturn string the action name, or "" when the key is not one offered
function HorseCollisionMod:RearActionFor(key, onlyRear)
	if type(key) ~= "string" or key == "" then
		return ""
	end

	local lower = string.lower(key)

	if not self.RearKeys[lower] then
		return ""
	end

	local prefix = onlyRear and "hcm_rear_only_" or "hcm_rear_charge_"

	return prefix .. lower
end

--- Says so when the configured keys cannot work.
--
-- Both failures are silent otherwise, and a feature that does nothing with no
-- explanation is worse than one that is off: a key the action map does not
-- declare names an action nobody raises, and two features on one key leave the
-- second unreachable because the first match wins.
function HorseCollisionMod:CheckRearKeys()
	local cfg = self.Config

	for _, entry in ipairs({
		{ cfg.RearChargeKey, "RearChargeKey" },
		{ cfg.RearOnlyKey, "RearOnlyKey" }
	}) do
		local key = entry[1]

		if type(key) ~= "string" or not self.RearKeys[string.lower(key)] then
			self:Log("Rear " .. entry[2] .. " is " .. tostring(key)
					.. ", which the action map does not declare. Choose one of"
					.. " r, q, y, u, o, h.")
		end
	end

	if type(cfg.RearChargeKey) == "string"
			and type(cfg.RearOnlyKey) == "string"
			and string.lower(cfg.RearChargeKey)
				== string.lower(cfg.RearOnlyKey) then
		self:Log("Rear RearChargeKey and RearOnlyKey are both "
				.. tostring(cfg.RearChargeKey)
				.. ", so only the charge will fire.")
	end
end

--- Routes the mod's own key to the rear.
--
-- `Player:OnAction(action, activation, value)` is an ordinary Lua method on the
-- `Player` entity class table, and the engine calls it for actions delivered to
-- the player. That is what makes input reachable at all: the UI action listener
-- this mod already uses for the load screen never sees a key, only interface
-- events.
--
-- Wrapped rather than replaced, and the original is always called, so every
-- other action behaves exactly as it did.
--
-- The action itself is the mod's own, loaded from `Libs/Config/
-- hcm_actionmaps.xml` through `ActionMapManager.LoadFromXML`, because a
-- vanilla key cannot be borrowed. Consuming a press here does not stop the
-- game acting on it: bound to `jump`, this reared the horse and then jumped
-- anyway. Nor is there a hold to distinguish one use from another, since a two
-- second hold and a tap both deliver a single `press` and no `release`.
--
-- So the mod brings its own action on its own key and disturbs no existing
-- control.
function HorseCollisionMod:HookRearKey()
	if type(rawget(_G, "Player")) ~= "table" then
		return
	end

	-- The original is kept on the mod table rather than only in the closure,
	-- so a reload can put it back before wrapping again. Refusing to reinstall
	-- once hooked leaves a wrapper from an older copy of this file in place,
	-- closed over an older `original`, and the keys stop working with the hook
	-- still reporting itself as installed.
	if self.RearOriginalOnAction then
		Player.OnAction = self.RearOriginalOnAction
	end

	local original = Player.OnAction

	if type(original) ~= "function" then
		return
	end

	self.RearOriginalOnAction = original

	Player.OnAction = function(playerSelf, action, activation, value)
		local consumed = false

		-- The hook is wrapped whole. An error in here would otherwise take
		-- the player's entire action handling with it, which is every key.
		-- Our own action is always consumed, whether or not it rears. It is
		-- not a vanilla action and the game's handler has no branch for it;
		-- passing it through hands an unknown name to `OnActorAction` on the
		-- game rules before anything else looks at it.
		pcall(function()
			local mod = HorseCollisionMod
			local cfg = mod.Config

			if action == mod:RearActionFor(cfg.RearChargeKey) then
				consumed = true

				if activation == "press" then
					mod:RearRequested(cfg.RearFragTag)
				end
			elseif action == mod:RearActionFor(cfg.RearOnlyKey, true) then
				consumed = true

				if activation == "press" then
					mod:RearRequested(cfg.RearOnlyFragTag)
				end
			end
		end)

		if consumed then
			return
		end

		return original(playerSelf, action, activation, value)
	end

	self:CheckRearKeys()

	self:Log("Rear hooked charge=" .. tostring(self.Config.RearChargeKey)
			.. " rear=" .. tostring(self.Config.RearOnlyKey))
end

--- Decides whether a press should rear.
--
-- @treturn boolean true when the press was taken
function HorseCollisionMod:RearRequested(fragTag)
	local cfg = self.Config

	-- Every way out of this function says which one it took. These gates all
	-- returned silently, and a press that arrives and is then dropped by one of
	-- them looks, from outside the game, exactly like a press that never
	-- arrived. Telling those two apart is what found the cooldown surviving a
	-- save load, after seven attempts at the action map had not.
	local function refuse(why)
		self:Log("Rear refused, " .. why)

		return false
	end

	if not cfg.Rear then
		return refuse("off")
	end

	local mounted = false

	pcall(function()
		mounted = player.human:IsMounted()
	end)

	if not mounted then
		return refuse("not mounted")
	end

	local horseEnt = nil

	pcall(function()
		horseEnt = XGenAIModule.GetEntityByWUID(player.player:GetPlayerHorse())
	end)

	if not horseEnt then
		return refuse("no horse")
	end

	-- The horse first and the player second, the same chain the detection loop
	-- uses. Asking only the horse is what made the gate useless: a nil velocity
	-- measures as zero, so every request read as standing still and the horse
	-- could be reared at a gallop, which throws the rider hard enough to hurt.
	local velocity = nil

	pcall(function()
		if horseEnt.GetVelocity then
			velocity = horseEnt:GetVelocity()
		end

		if not velocity and player.GetVelocity then
			velocity = player:GetVelocity()
		end
	end)

	if not velocity then
		return refuse("no velocity")
	end

	local speed = self:VectorLength(velocity)

	-- A rear is a standstill move, and the figure is low on purpose. The clip
	-- owns the horse's position while it plays, so momentum the horse already
	-- had fights it and drags the horse sideways over the closing frames:
	-- clearly visible at a walk, absent from a dead stop, where the horse holds
	-- position to 0.00 m for the whole animation.
	--
	-- Freeing that ownership instead is worse rather than better. With XyMove
	-- and Rotate at 0 the horse drifts under its own physics, measured at
	-- 0.80 m and described as a metre to the right.
	if speed > (cfg.RearMaxSpeed or 1.0) then
		return refuse("speed " .. string.format("%.2f", speed))
	end

	local now = self:TimeMs()

	if self.RearNextAt and now < self.RearNextAt then
		return refuse("cooldown")
	end

	self.RearNextAt = now + (cfg.RearCooldownMs or 2500)

	self:RearHorse(horseEnt, fragTag)

	return true
end

--- Rears the horse.
--
-- The horse plays its own `relaxed_rearing` clip and the rider stays in the
-- saddle, because nothing is dismounted: this is the animation, not a throw
-- caught in mid-air.
--
-- Reaching it took the whole chain. The horse has a `Rear` fragment in
-- `kcd_horse_database.adb`, but a fragment is not something Lua can ask for.
-- `StartInteractiveActionByName` resolves its argument against the FragTags of
-- one fragment, `AnimationControlled`, which the horse does not have, so the
-- mod ships four files: a parent database defining that fragment with an
-- `hcm_rear` option carrying vanilla's `Rear` contents, the horse fragment ids
-- with `AnimationControlled` declared, the tag itself, and the horse
-- controller definition giving the fragment a `FullBody` scope. A fragment
-- with no scope can never play whatever the database says, and humans needed
-- no equivalent only because vanilla already declares the fragment for them.
--
-- The last piece is the call itself. The bind takes
-- `ActionName, ObjectId, UpdateVisibility, AnimSpeed`, and with the name
-- alone it does nothing at all and still returns true: the horse must be given
-- as its own object. Every earlier attempt passed the name only, which is why
-- correct data looked like broken data.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:RearHorse(horseEnt, fragTag)
	local tag = fragTag or self.Config.RearFragTag or "hcm_rear_charge"

	-- Marked for as long as the charge could be touching anyone, so the
	-- detection loop scores whatever it finds as a gallop rather than by the
	-- horse's own speed. The lunge covers about five and a half meters in a
	-- second, which reads as a trot, and a deliberate charge producing the
	-- animated knockdown instead of a ragdoll is not what the rider asked for.
	if tag == (self.Config.RearFragTag or "") then
		self.RearCharging = true

		local generation = self.TimerTick

		Script.SetTimer(self.Config.RearChargeWindowMs or 2600, function()
			if generation == self.TimerTick then
				self.RearCharging = false
			end
		end)
	end

	local ok = pcall(function()
		horseEnt.actor:StartInteractiveActionByName(tag, horseEnt.id, false,
				self.Config.RearAnimSpeed or 1.0)
	end)

	-- Only the rear on the spot needs this. A charge physically drives the
	-- horse into people and the ordinary detection loop scores it; a rear that
	-- does not travel is invisible to that loop, because detection is driven by
	-- the horse's speed and the horse never moves.
	if tag == (self.Config.RearOnlyFragTag or "") then
		Script.SetTimer(self.Config.RearStrikeMs or 700, function()
			self:RearStrike(horseEnt)
		end)
	end

	if self.Config.LogTelemetry then
		-- The call returns true for any string at all, including names that do
		-- not exist, so this is only evidence that it was reached. The state a
		-- moment later is the evidence that it played.
		Script.SetTimer(600, function()
			local state = "?"

			pcall(function()
				state = tostring(horseEnt.actor:GetCurrentAnimationState())
			end)

			self:Log("Rear " .. tag .. " ok=" .. tostring(ok)
					.. " horse=" .. state)
		end)
	end
end

--- Whether a rear may land on this entity.
--
-- The same three tests the detection loop applies, for the same reasons. The
-- sphere returns crates, doors and dropped weapons as readily as people;
-- humans are named by class, because a faction test gave dogs a human
-- fragment on a dog skeleton and reached women only by a fallback. Corpses are
-- already ragdolls and reacting to them twitches bodies around. And Henry's
-- dog follows close enough to be caught constantly, so he is excluded by name,
-- dogs sharing the generic NPC class.
--
-- @tparam table npc the candidate
-- @treturn boolean true when the hooves may land on them
function HorseCollisionMod:RearCanHit(npc)
	local isHuman = false

	pcall(function()
		isHuman = (npc.class == "NPC"
				or npc.class == "NPC_Female")
	end)

	if not isHuman then
		return false
	end

	if self.Config.ProtectMutt then
		local isMutt = false

		pcall(function()
			local name = npc:GetName()

			if name and string.find(name, "dogCompanion") then
				isMutt = true
			end
		end)

		if isMutt then
			return false
		end
	end

	local isDead = false

	if npc.IsDead then
		pcall(function()
			isDead = npc:IsDead()
		end)
	end

	return not isDead
end

--- Brings the hooves down on whoever is in front.
--
-- The rear is the only thing this mod does that does not need speed. Every
-- other reaction is scored from how fast the horse was going, which is why a
-- stationary rider has never had anything to do but shove people at a walk.
--
-- Fired on a delay rather than with the request, because the strike is the
-- hooves landing and not the horse going up. `RearStrikeMs` is when that
-- happens in `relaxed_rearing`.
--
-- Only what is in front is hit, inside `RearArc` degrees of where the horse is
-- pointing and within `RearReach`. A rear that knocked down someone standing
-- behind the horse would be nonsense.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:RearStrike(horseEnt)
	local cfg = self.Config

	if not cfg.RearStrikes then
		return
	end

	local playerEnt = player
	local horsePos = nil
	local heading = nil

	pcall(function()
		horsePos = horseEnt:GetWorldPos()
		heading = horseEnt:GetDirectionVector(1)
	end)

	if not horsePos or not heading then
		return
	end

	local found = nil

	pcall(function()
		found = System.GetEntitiesInSphere(horsePos, cfg.RearReach or 3.0)
	end)

	if type(found) ~= "table" then
		return
	end

	local arc = math.cos(math.rad((cfg.RearArc or 70) / 2))
	local hit = 0

	for _, npc in pairs(found) do
		-- No cap. Everyone the hooves come down on takes it; a limit would
		-- mean a crowd absorbing the blow for each other by standing close.
		if npc ~= playerEnt and npc ~= horseEnt and npc.actor
				and self:RearCanHit(npc) then
			local ok, forward = pcall(function()
				local p = npc:GetWorldPos()
				local dx, dy = p.x - horsePos.x, p.y - horsePos.y
				local len = math.sqrt(dx * dx + dy * dy)

				if len <= 0 then
					return 1
				end

				return ((dx / len) * heading.x) + ((dy / len) * heading.y)
			end)

			if ok and forward and forward >= arc then
				hit = hit + 1
				self:RearHit(npc, horseEnt, playerEnt, heading)
			end
		end
	end

	if cfg.LogTelemetry then
		self:Log("RearStrike hit=" .. tostring(hit)
				.. " reach=" .. tostring(cfg.RearReach)
				.. " arc=" .. tostring(cfg.RearArc))
	end

	if hit > 0 then
		self:DrainHorseStamina(horseEnt, playerEnt, cfg.RearStaminaCost or 0)
	end
end

--- What a hoof landing on someone does.
--
-- The trot treatment, not the gallop one. A horse coming down on its front
-- hooves from a standstill is a real blow but it is not a charge, and the
-- charge is the move that earns the ragdoll.
--
-- Scored at a fixed speed rather than the horse's own, which is zero here:
-- what matters is the hooves, not ground the horse covered.
--
-- @tparam table npc the victim
-- @tparam table horseEnt the player's horse
-- @tparam table playerEnt the player
-- @tparam table heading the horse's facing, which the victim is thrown along
function HorseCollisionMod:RearHit(npc, horseEnt, playerEnt, heading)
	local cfg = self.Config
	local armor = self:ArmorOf(npc)
	local armorImpulse = self:ArmorImpulseScale(armor)
	local speed = cfg.RearImpactSpeed or 6.0
	local velocity = { x = heading.x * speed, y = heading.y * speed, z = 0 }
	local horsePos = nil

	pcall(function()
		horsePos = horseEnt:GetWorldPos()
	end)

	local horseWuid = nil

	pcall(function()
		horseWuid = player.player:GetPlayerHorse()
	end)

	local strength = self.HitReactionStrength

	self:SuppressAutoCure(npc)
	self:ProbeImpactCost(npc, "Trot", strength.MinorInjury, armor)

	-- Everything the ordinary path does at the moment of contact, in the same
	-- order. Reaching the reaction without these gave a hit with no sound, no
	-- dust and no kick to the camera, which reads as the animation glitching
	-- rather than as a blow landing.
	self:PlayImpactSound(npc, "Trot", armor)
	self:ShakeRiderCamera(playerEnt, "Trot")
	self:BlurRiderView(playerEnt, "Trot")
	self:ImpactDust(npc, "Trot")

	-- The same choice the trot tier makes, so the two agree: an animated
	-- knockdown by default, and the ragdoll only if the rider has asked for it
	-- there.
	if cfg.TrotReaction == "knockdown" then
		self:PlayReaction(npc, velocity, speed, "hcm_knockdown_")
	elseif cfg.TrotReaction == "fall" then
		self:PlayReaction(npc, velocity, speed, "hcm_fall_")
	else
		self:Ragdoll(npc, velocity, speed, 0.6, armorImpulse, horsePos, horseEnt)
	end

	self:MarkVictim(npc, "Trot", velocity, speed)
	self:SendHitReaction(npc, horseWuid, strength.MinorInjury)
	self:SendCombatHit(npc, playerEnt, strength.MinorInjury)
	self:ApplyImpactDamage(npc, "Trot", armor, playerEnt, horseEnt)
	self:ProvokeIfAnnoyed(npc, playerEnt)
end

--- Loads the mod's action map and points it at the player.
--
-- Repeated on every load screen because the action map manager is reset with
-- the world. Loading an already loaded map is harmless.
function HorseCollisionMod:LoadRearActionMap()
	if not self.Config.Rear then
		return
	end

	local file = self.Config.RearActionMapFile
	local map = self.Config.RearActionMap

	if type(file) ~= "string" or type(map) ~= "string" then
		return
	end

	-- The file is read once for the session and the listener re-pointed on
	-- every load screen. Those are two different needs.
	--
	-- Reading the file again once the map is registered registers the actions a
	-- second and third time, and one press then arrives three times over. That
	-- is what the guard below is for, and it is the only thing established about
	-- re-reading the file.
	--
	-- Re-pointing every load is because the listener is the player, whose entity
	-- the world reload replaces.
	--
	-- Nothing here was ever the cause of the rear keys being dead after a load,
	-- though several rides were spent on the assumption that it was. Logging the
	-- presses showed them reaching the hook at +112 ms with the map reporting
	-- itself listening and enabled, while the mod's own cooldown, stamped on a
	-- clock the load winds back, refused all of them. Do not read a dead key as
	-- evidence about this function without checking the gates in
	-- `RearRequested` first: they say which one refused.
	local loaded = self.RearActionMapLoaded

	if not loaded then
		loaded = pcall(function()
			ActionMapManager.LoadFromXML(file)
		end)

		self.RearActionMapLoaded = loaded
	end

	local listening = pcall(function()
		ActionMapManager.SetActionListener(map, player.id)
	end)

	local enabled = pcall(function()
		ActionMapManager.EnableActionMap(map, true)
	end)

	self:Log("Rear action map " .. map
			.. " loaded=" .. tostring(loaded)
			.. " listening=" .. tostring(listening)
			.. " enabled=" .. tostring(enabled))
end
