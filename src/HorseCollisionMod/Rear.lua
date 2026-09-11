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
-- `GetVelocity` cannot be trusted for this. At the moment a rear was requested
-- it read 0.24 m/s; the horse then covered 0.12 m in the next 128 ms, which is
-- 0.94 m/s. That is the same unreliability this project already documented on
-- the vertical axis, where a stationary horse reports 1 to 2 m/s because the
-- reading carries its settling fall.
--
-- It matters because the standstill gate is built on that number, and a gate
-- reading a quarter of the true speed lets through exactly the rears that
-- slide. The slide is the whole defect: the horse travels about 0.12 m in the
-- first 128 ms of a rear and is then frozen by the fragment for the rest of
-- the animation.
--
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

	-- Horizontal speed, not the length of the whole vector.
	--
	-- Whether this gate has anything to do with the sideways push is not
	-- established. What is established is that it was measuring the wrong
	-- quantity. `GetVelocity` on a horse standing perfectly
	-- still reports 1 to 2 m/s, because it carries the vertical settling fall,
	-- so a three dimensional length is mostly that noise: it refuses rears from
	-- a dead stop, which is a known fault, and passes a horse genuinely walking
	-- sideways because the horizontal part of the number was never isolated.
	--
	-- The ceiling itself is unchanged. Entry speed was briefly thought to
	-- predict how far the horse ends up displaced, and it does not: a rear
	-- entered at 0.09 m/s measured 1.76 m ahead and 0.97 m to the side a
	-- second later. That reading was the rider riding away after the rear, not
	-- the rear, which is why the sample window is now short enough that it
	-- cannot contain a decision to move off.
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

	if speed > (cfg.RearMaxSpeed or 1.0) then
		return refuse("speed " .. string.format("%.2f", speed))
	end

	-- The horse's own locomotion state, which is the only reliable answer to
	-- "is this horse moving".
	--
	-- Neither velocity source can be trusted here. A rear entered with
	-- `GetVelocity` reading 0.24 m/s, and a second with a position-derived
	-- 0.11 m/s, both slid 0.12 m in the opening 128 ms; 0.11 m/s over that
	-- window is 1.4 cm, so the horse accelerates once the rear begins and no
	-- reading taken beforehand predicts it. A rear entered from a genuine stop
	-- slides nothing at all, measured flat at 0.00 for the whole animation.
	--
	-- `MotionIdle` against `MotionMovement` is a state rather than an estimate,
	-- and it is the difference between those two cases.
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

	if self.RearNextAt and now < self.RearNextAt then
		return refuse("cooldown")
	end

	self.RearNextAt = now + (cfg.RearCooldownMs or 2500)

	self:RearHorse(horseEnt, fragTag)

	return true
end








--- Drives the charge forward with physics once the rear has finished.
--
-- The charge used to travel by root motion, blending the rear into
-- `relaxed_gallop_jump`. An interactive action moves the actor kinematically
-- with collision off, and every fault on this feature came from that: riding
-- through walls, wedging in fences, and a divergence the engine discharged at
-- over 20 m/s when the action ended.
--
-- All three movement control methods were measured and none gives travel and
-- collision together. `eMCM_Animation` travels without colliding.
-- `eMCM_AnimationHCollision` collides while the animation keeps demanding a
-- position collision refuses, which is the discharge. `eMCM_Entity` admits no
-- divergence but hands the horse to its movement controller, which zeroes an
-- impulse on the next frame.
--
-- That last one is only true *inside* the action. Once it has ended the horse
-- is an ordinary horse and an impulse moves it: measured at 4300 the horse
-- reached 8.33 m/s and traveled, and at 20000 it went a very long way.
--
-- So the rear plays in place and the travel is a real push afterwards. The
-- horse then collides with the world by default, reports a genuine velocity,
-- and the detection loop scores the collision exactly as it scores a gallop,
-- with no synthetic speed and no raycast brake.
--
-- Waited for rather than timed, because the action's length is not fixed and
-- an impulse applied while it still holds the horse is stored and discharged
-- later.
--
-- @tparam table horseEnt the player's horse
function HorseCollisionMod:ChargeForward(horseEnt)
	local cfg = self.Config

	if not cfg.RearChargeImpulse or cfg.RearChargeImpulse <= 0 then
		return
	end

	local generation = self.TimerTick
	local started = self:TimeMs()
	local deadline = started + (cfg.RearChargeWaitCeilingMs or 3000)

	-- The direction is taken at the moment of the push, not at the key press.
	--
	-- The rider can steer during the rear, and does. Sampling at the press meant
	-- the push used a heading up to a second and a half stale, so any correction
	-- sent the horse off diagonally.
	--
	-- Sampling late was wrong only for the old fragment, which blended into
	-- `relaxed_gallop_jump`: that clip traveled and turned the horse, so the
	-- heading at the end was whatever the animation had done rather than what
	-- the rider wanted. With the charge rearing in place, nothing turns the
	-- horse but the rider.

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
				z = cfg.RearChargeLift or 0.2
			}, cfg.RearChargeImpulse, 1)
		end)

		-- The elapsed time is the delay before the horse can move: the impulse
		-- cannot fire until the interactive action ends, so it is the rear up
		-- to its blend point plus whatever the landing clip runs. Measured at
		-- 1856 ms with the landing played whole, and 1408 ms once its front
		-- was skipped with `StartTime`.
		self:Log(string.format("ChargeForward pushed=%s impulse=%s after=%.0fms",
				tostring(ok), tostring(cfg.RearChargeImpulse),
				self:TimeMs() - started))

		-- The strike starts with the lunge, not with the key press. Started at
		-- the press it swept while the horse was still up on its hind legs and
		-- knocked people down before the charge had happened.
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

		Script.SetTimer(cfg.RearChargeWaitPollMs or 30, waitForEnd)
	end

	Script.SetTimer(cfg.RearChargeWaitMs or 400, waitForEnd)
end

--- Closes the charge window when the lunge has spent itself.
--
-- The rider's definition, and it is a better one than any threshold: the charge
-- is over the moment the horse is no longer being carried by the impulse.
--
-- What came before was three numbers that had to agree with each other -- a
-- speed under which the horse counted as stopped, a floor before that test was
-- allowed to run, and a ceiling in case it never fired. All three were guesses,
-- and the rider could finish the whole animation and then walk into someone and
-- have it score as a charge.
--
-- The impulse is a single shove rather than sustained drive, so the horse
-- reaches its top speed within a frame or two of the push and everything after
-- that is friction taking it back. That makes the shape of the lunge readable
-- without any absolute figure in it: track the peak, and call the move finished
-- once the speed has decayed to a fraction of it. A horse walking away
-- afterwards is nowhere near its own peak, so it cannot hold the window open.
--
-- Started at the push and not at the key press, which is what removes the need
-- for a floor: the horse is stationary through the rear itself, and a watcher
-- begun there would have closed on the animation rather than on the lunge.
--
-- **A single sample cannot set the peak.** `HorseSpeed` is derived from two
-- positions rather than read from `GetVelocity`, for the reasons in
-- `TrackHorseSpeed`, and the first version of this closed every window inside
-- 200 ms because of it: measured peaks of 21.2, 25.5 and 25.8 m/s appeared for
-- one sample each, against 13.0 on the same move, and half of a spike is
-- reached by the very next ordinary reading. The lunge then ended before the
-- horse had traveled, the sweep died with it, and the charge landed as an
-- ordinary walk stagger.
--
-- So the peak is the larger of each neighbouring pair, which a lone spike can
-- never win. `RearChargeLungePeakMin` is the second guard, against a dip early
-- on being read as decay before the horse has gone anywhere.
--
-- Whether those spikes are measurement noise or the engine really discharging
-- the horse at 25 m/s is not settled, and it matters: the second would explain
-- bodies thrown thirty meters. `moved=` is here to tell them apart. A real
-- 25 m/s for even a tenth of a second puts the horse meters further along than
-- a 13 m/s lunge does.
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

		if peak >= (cfg.RearChargeLungePeakMin or 3.0)
				and speed <= peak * (cfg.RearChargeLungeSpentAt or 0.5) then
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

		Script.SetTimer(cfg.RearChargeWaitPollMs or 30, watch)
	end

	Script.SetTimer(cfg.RearChargeWaitPollMs or 30, watch)
end

--- Reports how long an interactive action held the horse.
--
-- The charge gets this figure for free, because it has to wait for the action
-- to end before it can push and logs the wait as `after=`. The rear waits for
-- nothing, so without this its length can only be judged by eye, and choosing
-- where to cut it then costs a ride per guess.
--
-- Same instrument as the charge's wait: the action owns the horse for exactly
-- as long as `GetCurrentAnimationState` reads `AnimationControlled`.
--
-- @tparam table horseEnt the player's horse
-- @tparam string tag the fragment tag that was started, for the log line
function HorseCollisionMod:LogActionEnd(horseEnt, tag)
	if not self.Config.LogTelemetry then
		return
	end

	local generation = self.TimerTick
	local started = self:TimeMs()
	local deadline = started + (self.Config.RearChargeWaitCeilingMs or 3000)

	local function poll()
		if generation ~= self.TimerTick then
			return
		end

		local state = "?"

		pcall(function()
			state = tostring(horseEnt.actor:GetCurrentAnimationState())
		end)

		if state ~= "AnimationControlled" or self:TimeMs() > deadline then
			self:Log(string.format("ActionEnd %s held=%.0fms state=%s",
					tostring(tag), self:TimeMs() - started, state))

			return
		end

		Script.SetTimer(self.Config.RearChargeWaitPollMs or 30, poll)
	end

	-- Started after the same delay the charge uses, because the state does not
	-- read back as `AnimationControlled` the instant the call returns and a poll
	-- that begins too early ends immediately with a length of nothing.
	Script.SetTimer(self.Config.RearChargeWaitMs or 400, poll)
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

		-- The window ends when the lunge is spent, which `ChargeForward`
		-- decides because it is the only thing that knows when the push
		-- happened. This timer is the ceiling for a lunge never seen to decay.
		--
		-- While the window is open, any impact the detection loop finds is
		-- scored as a gallop whatever the horse's real speed. A fixed 2600 ms
		-- outlives the move by a long way: the action ends around 1050 ms and
		-- the lunge covers one to two meters, so more than a second remains in
		-- which walking into someone plays a full charge reaction.
		Script.SetTimer(self.Config.RearChargeWindowMs or 2600, function()
			if generation == self.TimerTick then
				self.RearCharging = false
			end
		end)

		self:ChargeForward(horseEnt)
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

		self:LogActionEnd(horseEnt, tag)
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

--- The charge's own strike, swept along the lunge.
--
-- The charge does not use the mod's ordinary detection loop. That loop is
-- driven by the horse's speed, which is a poor fit here: it exits below
-- walking pace, so a charge detected nobody at all until the horse was given a
-- physical push, and it then depended on the impulse landing cleanly for
-- anyone to be hit. Whether a special move connects should not rest on how
-- well the physics behaved.
--
-- So the charge carries its own detection, the way the rear on the spot
-- already does. The rider asked for a move that knocks several people down at
-- once, so there is no cap and no cooldown between victims: everyone in the
-- corridor goes down, and each is hit once per charge.
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
	local deadline = self:TimeMs() + (cfg.RearChargeStrikeMs or 1600)
	local hit = {}
	local drained = false
	local playerEnt = player

	local function sweep()
		-- The sweep lives exactly as long as the charge does.
		--
		-- `RearChargeStrikeMs` is a ceiling and not the definition. The lunge
		-- ends around 1050 ms and the sweep ran for 1600, so it kept striking
		-- anyone within 1.8 m after the horse had stopped, scoring them as a
		-- charge. `RearCharging` is the one fact that says whether the move is
		-- still happening, and it is already closed when the horse slows below
		-- walking pace, so the sweep reads it rather than keeping a second
		-- clock that has to agree with the first.
		if generation ~= self.TimerTick or not self.RearCharging
				or self:TimeMs() > deadline then
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
			local reach = cfg.RearChargeStrikeReach or 3.0
			local halfWidth = cfg.RearChargeStrikeWidth or 1.6
			local found = System.GetEntitiesInSphere(pos, reach + 1.0)
			local now = self:TimeMs()

			if type(found) ~= "table" then
				return
			end

			for _, npc in pairs(found) do
				local id = npc and npc.id

				-- `hit` only knows about this sweep. The detection loop is
				-- scoring the same lunge at the same time, and it writes its
				-- contacts where `ImpactIsNewContact` can see them, so without
				-- asking that question here the two paths honor different
				-- rules: the loop respects a contact the sweep wrote, and the
				-- sweep ignores one the loop wrote. Loop first, then sweep,
				-- was the half of the double hit that survived the lockout.
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
					if ahead >= -(cfg.RearChargeStrikeBehind or 0.5)
							and ahead <= reach and across <= halfWidth
							and dz <= (cfg.HorseMaxVerticalDiff or 2.0) then
						hit[tostring(id)] = true

						self:RearHit(npc, horseEnt, playerEnt,
								{ x = fx, y = fy, z = 0 }, "Charge",
								cfg.RearChargeImpactSpeed or 9.0)

						-- The charge pays for itself now that the detection
						-- loop stays out of a lunge. It received the gallop's
						-- drain as a side effect of being scored as a gallop,
						-- and taking that relabel away took the cost with it.
						--
						-- Once per charge, not once per victim. Riding down a
						-- group is the move; a crowd should not empty the horse
						-- for standing close together.
						if not drained then
							drained = true

							self:DrainHorseStamina(horseEnt, playerEnt,
									cfg.RearChargeStaminaCost or 0)
						end
					end
				end
			end
		end)

		Script.SetTimer(cfg.RearChargeStrikePollMs or 50, sweep)
	end

	sweep()
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
function HorseCollisionMod:RearHit(npc, horseEnt, playerEnt, heading, tier,
		hitSpeed)
	local cfg = self.Config
	local armor = self:ArmorOf(npc)
	local armorImpulse = self:ArmorImpulseScale(armor)
	tier = tier or "Rear"
	local speed = hitSpeed or cfg.RearImpactSpeed or 6.0
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
	self:ProbeImpactCost(npc, tier, strength.MinorInjury, armor)

	-- Everything the ordinary path does at the moment of contact, in the same
	-- order. Reaching the reaction without these gave a hit with no sound, no
	-- dust and no kick to the camera, which reads as the animation glitching
	-- rather than as a blow landing.
	self:PlayImpactSound(npc, tier, armor)
	self:ShakeRiderCamera(playerEnt, tier)
	self:BlurRiderView(playerEnt, tier)
	self:ImpactDust(npc, tier)

	-- A victim already inside a reaction is not given another one.
	--
	-- Rearing on someone still down from the last rear started a second
	-- interactive action on top of the first. The new one interrupts the
	-- running one mid-blend and the body ends up in a broken pose, face down
	-- and slowly rotating.
	--
	-- The hit itself still lands. A previous session built a cooldown that
	-- refused the whole impact on the premise that a second blow on a downed
	-- victim does nothing, and testing disproved it: a second impact on a
	-- victim in `BlendRagdoll` registers and costs full health. So the damage,
	-- the sound, the dust and the rest all happen. Only the animation is
	-- skipped, and the victim stays down under the reaction already playing,
	-- which is what should happen to someone being trampled where they lie.
	local busy = false

	pcall(function()
		local state = tostring(npc.actor:GetCurrentAnimationState())

		busy = state == self.ReactionAnimationState
				or state == self.RagdollAnimationState
	end)

	if busy then
		self:Log("RearHit " .. self:NameOf(npc)
				.. " already reacting, damage only")
	elseif tier == "Charge" then
		-- The throw is its own figure rather than a full gallop's. A charge
		-- was launching people cartoonishly far at 1.0: the horse is also
		-- moving under physics by then, so its collider shoves the ragdoll on
		-- top of whatever this applies.
		self:Ragdoll(npc, velocity, speed, cfg.RearChargeThrow or 0.7,
				armorImpulse, horsePos, horseEnt)
	elseif (cfg.RearReaction or cfg.TrotReaction) == "knockdown" then
		self:PlayReaction(npc, velocity, speed, "hcm_knockdown_")
	elseif (cfg.RearReaction or cfg.TrotReaction) == "fall" then
		self:PlayReaction(npc, velocity, speed, "hcm_fall_")
	else
		self:Ragdoll(npc, velocity, speed, 0.6, armorImpulse, horsePos, horseEnt)
	end

	self:MarkVictim(npc, tier, velocity, speed)
	local force = (tier == "Charge") and strength.MajorInjury
			or strength.MinorInjury

	self:SendHitReaction(npc, horseWuid, force)

	-- Both strikes record their contact, because neither goes through the
	-- detection loop and the loop cannot honor a gap it was never told about.
	-- Without this the sweep reaches 1.8 m ahead and hits, the loop comes round
	-- and hits the same person again, and `HitMinIntervalMs` is powerless
	-- because no contact was ever written for it to measure from. That is the
	-- double hit on one lunge.
	local victimId = tostring(npc.id)
	local now = self:TimeMs()

	self.LastScoredHit[victimId] = now

	-- The lockout is the charge's alone.
	--
	-- It is the length of the whole move rather than the gap between two
	-- passes, because a charge is one deliberate act and a victim struck by it
	-- should be finished with it. That reasoning is about the charge and
	-- nothing else, and applying it here unconditionally closed a victim out of
	-- every impact for 2.6 seconds after an ordinary rear as well -- one
	-- feature's rule silently governing another because the two share this
	-- function.
	if tier == "Charge" then
		self.LockedUntil[victimId] = now
				+ (self.Config.RearChargeVictimLockMs or 0)
	end

	self:SendCombatHit(npc, playerEnt, force)
	self:ApplyImpactDamage(npc, tier, armor, playerEnt, horseEnt)

	-- No retaliation from a rear or a charge, deliberately.
	--
	-- Retaliation is the answer to being shoved: a man barged repeatedly at
	-- walking pace loses patience and fights back, and the escalating roll in
	-- `ProvokeIfAnnoyed` is built around a nuisance that does no real harm.
	-- A rear brings hooves down on someone and a charge rides them down, and
	-- neither is a shove. Being reared on four times is not a patience
	-- problem.
	--
	-- It was wired here when the rear was first built, before the rear was a
	-- tier of its own, and it meant a guard reared on repeatedly would start a
	-- fight through `SendProvocationHit`, which deliberately bypasses the
	-- crime system and so could not be turned off with `CollisionIsCrime`
	-- either. `Update.lua` keeps the only remaining call, inside the walk
	-- stagger branch.
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
