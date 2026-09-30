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
	r = true, q = true, e = true, f = true,
	y = true, u = true, o = true, h = true
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
	local offered = {}

	for key in pairs(self.RearKeys) do
		offered[#offered + 1] = key
	end

	table.sort(offered)

	for _, entry in ipairs({
		{ cfg.RearChargeKey, "RearChargeKey" },
		{ cfg.RearOnlyKey, "RearOnlyKey" }
	}) do
		local key = entry[1]

		if type(key) ~= "string" or not self.RearKeys[string.lower(key)] then
			self:Log("Rear " .. entry[2] .. " is " .. tostring(key)
					.. ", which the action map does not declare. Choose one of "
					.. table.concat(offered, ", ") .. ".")
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
-- vanilla action cannot be borrowed: consuming a press here does not stop the
-- game acting on it, and a hold and a tap both deliver a single `press` and no
-- `release`, so there is no second use to separate out. The mod's own action
-- on its own key disturbs no existing control.
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
		-- The mod's own action is always consumed, whether or not it rears.
		-- It is not a vanilla action and the game's handler has no branch for
		-- it; passing it through hands an unknown name to `OnActorAction` on
		-- the game rules before anything else looks at it.
		pcall(function()
			local mod = HorseCollisionMod
			local cfg = mod.Config

			-- The lean shares this hook rather than wrapping OnAction a
			-- second time. Two wrappers cannot both survive a reload: this
			-- one restores `RearOriginalOnAction` before rewrapping, which
			-- would discard the other.
			if mod:HandleLeanAction(action, activation) then
				consumed = true
			elseif action == mod:RearActionFor(cfg.RearChargeKey) then
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

--- Keeps a real speed for the player's horse, derived from where it has been.
--
-- `GetVelocity` under-reports a slow horse, and the standstill gate is built
-- on this number, so a low reading lets through exactly the rears that slide.
-- Two positions and the time between them cannot be wrong in that way.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:TrackHorseSpeed(horseEnt)
	if not horseEnt then
		return
	end

	local now = self:TimeMs()

	pcall(function()
		local p = horseEnt:GetWorldPos()
		local last = self.HorseTrack

		if last and last.id == tostring(horseEnt.id) and now > last.t then
			local dx = p.x - last.x
			local dy = p.y - last.y
			local dt = (now - last.t) / 1000

			if dt > 0 then
				self.HorseSpeed = math.sqrt((dx * dx) + (dy * dy)) / dt
			end
		end

		self.HorseTrack = {
			id = tostring(horseEnt.id), x = p.x, y = p.y, t = now
		}
	end)
end

--- Decides whether a press should rear.
--
-- @treturn boolean true when the press was taken
function HorseCollisionMod:RearRequested(fragTag)
	local cfg = self.Config

	-- Every way out of this function logs its reason, so a press dropped by a
	-- gate can be told from a press that never arrived.
	local function refuse(why)
		self:Log("Rear refused, " .. why)

		return false
	end

	if not cfg.Rear then
		return refuse("off")
	end

	if cfg.RequirePerks then
		local isCharge = (fragTag == cfg.RearFragTag)
		local abilityName = isCharge and "hcm_charge" or "hcm_rear"
		local hasAbility = false

		pcall(function()
			hasAbility = player.soul:HasAbility(abilityName)
		end)

		if not hasAbility then
			return refuse("missing perk: " .. abilityName)
		end
	end

	local mounted = false

	pcall(function()
		mounted = player.human:IsMounted()
	end)

	if not mounted then
		return refuse("not mounted")
	end

	if fragTag == cfg.RearFragTag then
		self:ShowTutorial("charge")
	else
		self:ShowTutorial("rear")
	end

	local horseEnt = self:PlayerHorse()

	if not horseEnt then
		return refuse("no horse")
	end

	-- The horse first and the player second, the same chain the detection loop
	-- uses. A missing velocity refuses the press, because read as zero it
	-- would pass every press and let the horse rear at a gallop.
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

	-- Horizontal speed, not the length of the whole vector. `GetVelocity` on a
	-- horse standing still reports 1 to 2 m/s because it carries the vertical
	-- settling fall, so the full length would refuse rears from a dead stop.
	local speed = 0

	if velocity then
		speed = math.sqrt((velocity.x * velocity.x)
				+ (velocity.y * velocity.y))
	end

	-- The derived figure wins where it exists, because the engine's is wrong
	-- in the direction that matters: it under-reports, so it passes rears the
	-- gate exists to refuse.
	local tracked = self.HorseSpeed

	if tracked and tracked > speed then
		speed = tracked
	end

	if speed > (cfg.RearMaxSpeed) then
		return refuse("speed " .. string.format("%.2f", speed))
	end

	-- The horse's own locomotion state, which is the only reliable answer to
	-- "is this horse moving". A horse still in `MotionMovement` accelerates once
	-- the rear begins and slides, however slow it read beforehand; one in
	-- `MotionIdle` does not slide at all.
	if cfg.RearIdleOnly then
		local state = "?"

		pcall(function()
			state = tostring(horseEnt.actor:GetCurrentAnimationState())
		end)

		if state ~= "MotionIdle" then
			return refuse("state " .. state)
		end
	end

	if cfg.LogTelemetry then
		self:Log(string.format("Rear entry speed=%.2f (horizontal)", speed))
	end

	local now = self:TimeMs()

	-- One move at a time. The idle and speed gates above do not cover this:
	-- between the charge's rear ending and its push the horse reads
	-- `MotionIdle` at 0 m/s, and the standing rear reads `MotionIdle`
	-- throughout. So the press is refused on the move's own state, the
	-- charge's `RearCharging` and the rear's animation length.
	if self.RearCharging then
		return refuse("charge in progress")
	end

	if self.RearBusyUntil and now < self.RearBusyUntil
			and (self.RearBusyUntil - now) <= self:RearAnimMs() then
		return refuse("rear in progress")
	end

	-- The rear and the charge each keep their own cooldown clock, started on
	-- the move's first contact in `RearStrike` and `ChargeStrike`, so a move
	-- that reaches nobody costs no cooldown. A save load clears both clocks.
	local isCharge = (fragTag == cfg.RearFragTag)
	local nextAt = self[isCharge and "ChargeNextAt" or "RearNextAt"]

	if nextAt and now < nextAt then
		return refuse("cooldown " .. string.format("%.1fs", (nextAt - now) / 1000))
	end

	if not isCharge then
		self.RearBusyUntil = now + self:RearAnimMs()
	end

	self:RearHorse(horseEnt, fragTag)

	return true
end

--- How long the standing rear holds the horse, in milliseconds.
--
-- Read from the animation itself rather than declared. The standing rear
-- plays at normal speed; `RearAnimSpeed` applies to the charge only.
--
-- @treturn number the length, or 0 when it cannot be read
function HorseCollisionMod:RearAnimMs()
	local length = 0

	pcall(function()
		length = self:PlayerHorse():GetAnimationLength(0, "relaxed_rearing") or 0
	end)

	return length * 1000
end

--- The cooldown icons, one per commanded move.
--
-- Each is the mod's own buff, a copy of vanilla's `barking_cooldown`: a timed
-- buff with no effect whose only job is to sit among the game's buff icons.
-- They are declared with no duration, so the table never carries a second
-- copy of the cooldown; `UpdateMoveCooldowns` takes each off when its clock
-- runs out.
local COOLDOWN_ICONS = {
	{ clock = "RearNextAt", buff = "RearCooldownBuff" },
	{ clock = "ChargeNextAt", buff = "ChargeCooldownBuff" },
}

--- Starts a move's cooldown and puts its icon on the player.
--
-- Called at the move's first contact, which is when its cooldown starts.
--
-- @tparam string clock "RearNextAt" or "ChargeNextAt"
-- @tparam number cooldown the cooldown, in milliseconds
function HorseCollisionMod:StartMoveCooldown(clock, cooldown)
	local cfg = self.Config

	self[clock] = self:TimeMs() + cooldown

	if not cfg.MoveCooldownIcons then
		return
	end

	for _, icon in ipairs(COOLDOWN_ICONS) do
		if icon.clock == clock then
			pcall(function()
				player.soul:RemoveAllBuffsByGuid(cfg[icon.buff])
				player.soul:AddBuff(cfg[icon.buff])
			end)

			self.CooldownIconShown = self.CooldownIconShown or {}
			self.CooldownIconShown[clock] = true
		end
	end
end

--- Takes a cooldown icon off once its move is available again.
--
-- Read from the move's clock every tick, so an icon clears at the moment a
-- press would be taken, and after a save load, whose handler clears the
-- deadline.
--
-- @tparam number now the mod's clock, in milliseconds
function HorseCollisionMod:UpdateMoveCooldowns(now)
	local shown = self.CooldownIconShown

	if not shown then
		return
	end

	for _, icon in ipairs(COOLDOWN_ICONS) do
		local nextAt = self[icon.clock]

		if shown[icon.clock] and not (nextAt and now < nextAt) then
			pcall(function()
				player.soul:RemoveAllBuffsByGuid(self.Config[icon.buff])
			end)

			shown[icon.clock] = false
		end
	end
end

--- Drives the charge forward with physics once the rear has finished.
--
-- An interactive action moves the actor kinematically with collision off,
-- and none of the three movement control methods gives travel and collision
-- together inside one: `eMCM_Animation` travels without colliding,
-- `eMCM_AnimationHCollision` builds a divergence the engine discharges when
-- the action ends, and `eMCM_Entity` zeroes an impulse on the next frame. Once
-- the action has ended the horse is an ordinary horse and an impulse moves it.
--
-- So the rear plays in place and the travel is a real push afterwards, and
-- the horse collides with the world like any moving horse. Waited for rather
-- than timed, because the action's length is not fixed and an impulse applied
-- while it still holds the horse is stored and discharged later.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:ChargeForward(horseEnt)
	local cfg = self.Config

	if not cfg.RearChargeImpulse or cfg.RearChargeImpulse <= 0 then
		return
	end

	local generation = self.TimerTick
	local started = self:TimeMs()
	local deadline = started + (cfg.RearChargeWaitCeilingMs)

	-- The direction is taken at the moment of the push, not at the key press,
	-- because the player can steer during the rear.
	local function push()
		local ok = pcall(function()
			local d = horseEnt:GetDirectionVector(1)
			local flat = math.sqrt((d.x * d.x) + (d.y * d.y))

			if flat <= 0 then
				return
			end

			horseEnt:AddImpulse(-1, horseEnt:GetWorldPos(), {
				x = d.x / flat,
				y = d.y / flat,
				z = cfg.RearChargeLift
			}, cfg.RearChargeImpulse, 1)
		end)

		-- `after=` is the delay before the horse can move: the impulse cannot
		-- fire until the interactive action ends.
		self:Log(string.format("ChargeForward pushed=%s impulse=%s after=%.0fms",
				tostring(ok), tostring(cfg.RearChargeImpulse),
				self:TimeMs() - started))

		-- The strike starts with the lunge, not with the key press, so nobody
		-- is struck while the horse is still up on its hind legs.
		self:ChargeStrike(horseEnt)
		self:WatchLunge(horseEnt)
	end

	local function waitForEnd()
		if generation ~= self.TimerTick then
			return
		end

		local state = "?"

		pcall(function()
			state = tostring(horseEnt.actor:GetCurrentAnimationState())
		end)

		if state ~= "AnimationControlled" or self:TimeMs() > deadline then
			push()

			return
		end

		Script.SetTimer(cfg.RearChargeWaitPollMs, waitForEnd)
	end

	Script.SetTimer(cfg.RearChargeWaitMs, waitForEnd)
end

--- Closes the charge window when the lunge has spent itself.
--
-- The charge is over the moment the horse stops being carried by the
-- impulse. The impulse is a single shove rather than sustained drive, so the
-- horse reaches its top speed within a frame or two of the push and everything
-- after that is friction taking it back. The move is finished once the speed
-- has decayed to `RearChargeLungeSpentAt` of its peak; a horse walking away
-- afterwards is nowhere near its own peak, so it cannot hold the window open.
--
-- Started at the push and not at the key press, because the horse is
-- stationary through the rear itself.
--
-- **A single sample cannot set the peak.** `HorseSpeed` is derived from two
-- positions, which spike for one sample at a time, and half of a spike is
-- reached by the next ordinary reading. So the peak is the smaller of
-- each neighboring pair, which a lone spike can never set.
-- `RearChargeLungePeakMin` is the second guard, against a dip early on being
-- read as decay before the horse has gone anywhere. The log's `spike=` and
-- `moved=` record the raw peak and the distance covered.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:WatchLunge(horseEnt)
	local cfg = self.Config
	local generation = self.TimerTick
	local started = self:TimeMs()
	local peak = 0
	local spike = 0
	local previous = nil
	local origin = nil

	pcall(function()
		origin = horseEnt:GetWorldPos()
	end)

	local function watch()
		if generation ~= self.TimerTick or not self.RearCharging then
			return
		end

		local speed = self.HorseSpeed or 0

		if speed > spike then
			spike = speed
		end

		-- Two consecutive samples both above a figure is evidence the horse
		-- was actually traveling at it, where one alone is not.
		if previous then
			local held = math.min(previous, speed)

			if held > peak then
				peak = held
			end
		end

		previous = speed

		if peak >= (cfg.RearChargeLungePeakMin)
				and speed <= peak * (cfg.RearChargeLungeSpentAt) then
			self.RearCharging = false

			if cfg.LogTelemetry then
				local moved = -1

				pcall(function()
					local p = horseEnt:GetWorldPos()

					if origin then
						moved = math.sqrt(((p.x - origin.x) ^ 2)
								+ ((p.y - origin.y) ^ 2))
					end
				end)

				self:Log(string.format(
						"ChargeWindow spent peak=%.2f spike=%.2f now=%.2f"
								.. " moved=%.2f after=%.0fms",
						peak, spike, speed, moved, self:TimeMs() - started))
			end

			return
		end

		Script.SetTimer(cfg.RearChargeWaitPollMs, watch)
	end

	Script.SetTimer(cfg.RearChargeWaitPollMs, watch)
end

--- Rears the horse, on the spot or into a charge.
--
-- The horse plays a rear and the rider stays in the saddle, because nothing
-- is dismounted: this is the animation, not a throw caught in mid-air.
--
-- The standing rear plays `relaxed_rearing` directly with `StartAnimation`,
-- outside Mannequin. The charge's rear is the `hcm_rear_charge` option,
-- reached through `StartInteractiveActionByName`, which resolves its argument
-- against the FragTags of one fragment, `AnimationControlled`, which the horse
-- does not have in vanilla. So the mod ships four files: a parent database
-- defining that fragment with the rear options, the horse fragment ids with
-- `AnimationControlled` declared, the tags, and the horse controller
-- definition giving the fragment a `FullBody` scope; a fragment with no scope
-- never plays. The bind takes `ActionName, ObjectId, UpdateVisibility,
-- AnimSpeed`, and with the name alone it does nothing and still returns true:
-- the horse must be given as its own object.
--
-- @tparam table horseEnt the player's horse
-- @tparam[opt] string fragTag `RearFragTag` for the charge or `RearOnlyFragTag`
--   for the standing rear; the charge when omitted
function HorseCollisionMod:RearHorse(horseEnt, fragTag)
	local tag = fragTag or self.Config.RearFragTag

	if player and self.Config.RiderVocal and type(PlayAudioTrigger) == "function" then
		pcall(function() PlayAudioTrigger(player, "v_henry_hyje") end)
	end

	-- `RearCharging` marks the charge as in progress, from the press until
	-- `WatchLunge` sees the lunge spent. It keeps the sweep alive and refuses
	-- a second press.
	if tag == (self.Config.RearFragTag) then
		self.RearCharging = true

		-- Cleared here so the charge's stamina drain and Henry's voice happen
		-- once per lunge rather than once per session.
		self.ChargeDrained = false
		self.ChargeVoiced = false

		-- A new lunge clears every lockout the last one wrote.
		-- `VictimLockMsByTier.Charge` stops one lunge striking the same person
		-- twice; a new press is a new attack, so the previous lunge's lockouts
		-- have no say in it.
		self.LockedUntil = {}

		-- How long the detection loop stands aside so the charge's own sweep
		-- scores its contacts. Stamped at the press, so it covers the rear and
		-- the start of the lunge; `ImpactIsNewContact` guards the overlap after
		-- it closes.
		self.ChargeScoringUntil = self:TimeMs()
				+ (self.Config.RearChargeStrikeMs)

		local generation = self.TimerTick

		-- The ceiling on `RearCharging`, for a lunge `WatchLunge` never sees
		-- decay.
		Script.SetTimer(self.Config.RearChargeWindowMs, function()
			if generation == self.TimerTick then
				self.RearCharging = false
			end
		end)

		self:ChargeForward(horseEnt)
	end

	local animSpeed = self.Config.RearAnimSpeed

	local ok = true

	if tag == (self.Config.RearOnlyFragTag) then
		ok = pcall(function()
			-- Clear any stuck manual animations from a previous rear so this can
			-- be re-triggered without requiring the horse to move.
			horseEnt:StopAnimation(0, 0)

			-- Mannequin is bypassed for the standing rear, and
			-- `SetAnimationDrivenMotion` is left to the engine, so the horse
			-- does not rubberband and a move by the player interrupts the rear
			-- with ordinary locomotion.
			horseEnt:StartAnimation(0, "relaxed_rearing")
		end)
	else
		ok = pcall(function()
			horseEnt.actor:StartInteractiveActionByName(tag, horseEnt.id, false, animSpeed)
		end)
	end

	-- The rear on the spot strikes with `RearStrike`; the charge has its own
	-- sweep, started with the lunge. A rear that does not travel is invisible
	-- to the detection loop, which is driven by the horse's speed.
	if tag == (self.Config.RearOnlyFragTag) then
		Script.SetTimer(self.Config.RearStrikeMs, function()
			self:RearStrike(horseEnt)
		end)
	end

	if self.Config.LogTelemetry then
		-- For the charge, `StartInteractiveActionByName` returns true for any
		-- string, including names that do not exist, so `ok` is only evidence
		-- that it was reached. The horse's state 600 ms later, well inside the
		-- rear, is the evidence that it played.
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

--- The charge's own strike, swept along the lunge.
--
-- The charge does not use the mod's ordinary detection loop, which is driven
-- by the horse's speed and would make whether the move connects depend on how
-- the physics behaved. The sweep is the only thing that scores a charge. It
-- knocks several people down at once: there is no cap and no cooldown between
-- victims, and each is hit once per charge.
--
-- Swept rather than sampled once, because the horse is moving and a single
-- test at one instant would miss anyone it passes. The corridor is measured
-- from the horse each tick, so it follows the lunge wherever it actually goes.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:ChargeStrike(horseEnt)
	local cfg = self.Config

	if not cfg.RearChargeStrikes then
		return
	end

	local generation = self.TimerTick
	local deadline = self:TimeMs() + (cfg.RearChargeStrikeMs)
	local hit = {}
	local playerEnt = player

	-- Who the near miss has already reached. It belongs to the charge and not
	-- to a tick, because the band is sampled every tick from a horse that has
	-- moved, and the same bystander would otherwise be frightened once a tick
	-- for as long as the lunge kept them inside the radius.
	local feared = {}
	local playerWuid = nil

	pcall(function()
		playerWuid = XGenAIModule.GetMyWUID(playerEnt)
	end)

	local function sweep()
		-- The sweep lives exactly as long as the charge does, read from
		-- `RearCharging`, so it does not strike anyone after the horse has
		-- stopped. `RearChargeStrikeMs` is only its ceiling.
		if generation ~= self.TimerTick or not self.RearCharging
				or self:TimeMs() > deadline then
			-- The lunge is over. Whoever is still standing in front of the
			-- horse untouched was charged at and not reached, which the lane
			-- test inside the band suppresses while the charge is still
			-- coming, so the closing pass is the only thing that speaks for
			-- them. Not run on a script reload, where `generation` has moved
			-- on and there is no charge to close.
			if generation == self.TimerTick then
				self:CloseChargeFear(horseEnt, playerWuid, hit, feared)
			end

			return
		end

		pcall(function()
			local pos = horseEnt:GetWorldPos()
			local heading = horseEnt:GetDirectionVector(1)
			local flat = math.sqrt((heading.x * heading.x)
					+ (heading.y * heading.y))

			if flat <= 0 then
				return
			end

			local fx, fy = heading.x / flat, heading.y / flat
			local reach = cfg.RearChargeStrikeReach
			local halfWidth = cfg.RearChargeStrikeWidth
			local found = System.GetEntitiesInSphere(pos, reach + 1.0)
			local now = self:TimeMs()

			if type(found) ~= "table" then
				return
			end

			for _, npc in pairs(found) do
				local id = npc and npc.id

				-- `hit` only knows about this sweep. Once `ChargeScoringUntil`
				-- closes, the detection loop can reach the same victim while
				-- the sweep still runs, so the sweep also honors a contact the
				-- loop wrote, through `ImpactIsNewContact`.
				if id and not hit[tostring(id)] and npc ~= playerEnt
						and npc ~= horseEnt and npc.actor
						and self:ImpactIsNewContact(tostring(id), now)
						and self:RearCanHit(npc) then
					local p = npc:GetWorldPos()
					local dx, dy = p.x - pos.x, p.y - pos.y
					local ahead = (dx * fx) + (dy * fy)
					local across = math.abs((dx * -fy) + (dy * fx))
					local dz = math.abs(p.z - pos.z)

					-- A corridor in front of the horse: far enough back to catch
					-- anyone the chest reaches, and never behind it.
					if ahead >= -(cfg.RearChargeStrikeBehind)
							and ahead <= reach and across <= halfWidth
							and dz <= (cfg.HorseMaxVerticalDiff) then
						hit[tostring(id)] = true

						-- Struck at the charge's own speed, which is declared
						-- rather than measured: the rear holds the horse
						-- `AnimationControlled`, so it cannot be measured
						-- through a lunge. `RearChargeImpactSpeed` carries the
						-- derivation, and it is the speed the whole impact is
						-- resolved at, the launch in `ImpulseVictim` included.
						self:RearHit(npc, horseEnt, playerEnt,
								{ x = fx, y = fy, z = 0 }, "Charge",
								cfg.RearChargeImpactSpeed)

						-- Once per charge, not once per victim. Riding down a
						-- group is the move; a crowd should not empty the
						-- horse for standing close together.
						-- The cooldown starts here for the same reason: it is
						-- the price of a charge that landed, and a lunge into
						-- empty air has not spent one.
						if not self.ChargeDrained then
							self.ChargeDrained = true

							self:DrainImpactStamina(horseEnt, playerEnt,
									"Charge")

							self:StartMoveCooldown("ChargeNextAt",
									cfg.ChargeCooldownMs)
						end
					end
				end
			end

			self:ChargeFearBand(horseEnt, pos, fx, fy, playerWuid, hit,
					feared, false)
		end)

		Script.SetTimer(cfg.RearChargeStrikePollMs, sweep)
	end

	sweep()
end

--- Whether a rear may land on this entity.
--
-- The same three tests the detection loop applies, for the same reasons. The
-- sphere returns crates, doors and dropped weapons as readily as people;
-- humans are matched by class, which admits men and women and no animal. Corpses are
-- already ragdolls and reacting to them twitches bodies around. Dogs, Henry's
-- included, are class `Dog` and fail the class test.
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
		found = System.GetEntitiesInSphere(horsePos, cfg.RearReach)
	end)

	if type(found) ~= "table" then
		return
	end

	local arc = math.cos(math.rad((cfg.RearArc) / 2))
	local hit = 0

	-- Who the hooves reached, so the fear band can leave them out: a victim
	-- with a hit reaction to get through does not also need a reason to run.
	local struck = {}

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
				struck[tostring(npc.id)] = true
				self:RearHit(npc, horseEnt, playerEnt, heading, "Rear")
			end
		end
	end

	if cfg.LogTelemetry then
		self:Log("RearStrike hit=" .. tostring(hit)
				.. " reach=" .. tostring(cfg.RearReach)
				.. " arc=" .. tostring(cfg.RearArc))
	end

	if hit > 0 then
		self:DrainImpactStamina(horseEnt, playerEnt, "Rear")

		-- The rear's cooldown starts on contact, as the charge's does.
		self:StartMoveCooldown("RearNextAt", cfg.RearCooldownMs)
	end

	-- After the strike, because the band excludes whoever it landed on and
	-- cannot know that until the sweep has run.
	self:FearBand(horseEnt, struck)
end

--- What a rear or a charge landing on someone does.
--
-- Shared by the standing rear's strike and the charge's sweep; the tier's own
-- tables decide the reaction. Scored at a fixed speed rather than the horse's
-- own, which is zero for a rear and unmeasurable through a lunge.
--
-- @tparam table npc the victim
-- @tparam table horseEnt the player's horse
-- @tparam table playerEnt the player
-- @tparam table heading the horse's facing, which the victim is thrown along
-- @tparam[opt] string tier "Rear" or "Charge"; "Rear" when omitted
-- @tparam[opt] number hitSpeed the speed to score at; `RearImpactSpeed` when
--   omitted
function HorseCollisionMod:RearHit(npc, horseEnt, playerEnt, heading, tier,
		hitSpeed)
	local cfg = self.Config

	tier = tier or "Rear"

	local speed = hitSpeed or cfg.RearImpactSpeed
	local velocity = { x = heading.x * speed, y = heading.y * speed, z = 0 }
	local horsePos, horseWuid = nil, nil

	pcall(function()
		horsePos = horseEnt:GetWorldPos()
	end)

	pcall(function()
		horseWuid = player.player:GetPlayerHorse()
	end)

	local victimId = tostring(npc.id)
	local now = self:TimeMs()

	-- Both strikes record their contact, because neither goes through the
	-- detection loop and the loop cannot honor a gap it was never told about;
	-- `HitMinIntervalMs` measures from this stamp.
	self.LastScoredHit[victimId] = now

	-- A lockout longer than the gap between two passes, for a move that is one
	-- deliberate act rather than a series of collisions. Only tiers listed in
	-- `VictimLockMsByTier` carry one.
	local lock = self:TierValue("VictimLockMsByTier", tier)

	if lock and lock > 0 then
		self.LockedUntil[victimId] = now + lock
	end

	-- Everything an impact does is shared with the detection loop and lives in
	-- `Impact.lua`. What stays here is the rear's alone: a fixed scoring
	-- speed, a heading to be thrown along, the contact stamp the sweep owes
	-- the loop, and the charge's lockout.
	self:ResolveImpact(npc, tier, {
		velocity = velocity,
		speed = speed,
		horsePos = horsePos,
		horseEnt = horseEnt,
		playerEnt = playerEnt,
		horseWuid = horseWuid
	})
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
	-- second and third time, and one press then arrives three times over, so
	-- the guard below reads it once.
	--
	-- Re-pointing every load is because the listener is the player, whose entity
	-- the world reload replaces. For a key that does nothing, the refusal lines
	-- from `RearRequested` say which gate refused it.
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
