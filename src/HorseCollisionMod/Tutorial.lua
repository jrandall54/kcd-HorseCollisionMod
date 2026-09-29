--- In-game tutorial banners for the horseback maneuvers.
--
-- Shows each maneuver's banner once, when it is first available: the rear,
-- the charge and the lean. Attached to the `HorseCollisionMod` table created
-- by the entry point, which pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Tutorial
-- @author jrandall54

HorseCollisionMod.TutorialsShown = HorseCollisionMod.TutorialsShown or {}

-- How long a banner stays on screen, in seconds.
HorseCollisionMod.TutorialBannerSec = 10

-- The pause after one banner leaves the screen before the next is shown.
HorseCollisionMod.TutorialBannerGapMs = 500

--- Checks whether the player is currently using a game controller.
--
-- @treturn boolean true if a gamepad is active, false if keyboard/mouse
function HorseCollisionMod:IsController()
	local ctrl = Game.GetActionControl and Game.GetActionControl("player", "use")

	return type(ctrl) == "string" and string.sub(ctrl, 1, 3) == "xi_"
end

--- Formats the tutorial text for a given maneuver, resolving configured keys.
--
-- Dynamically adapts button prompts based on whether the player is currently
-- using a gamepad or keyboard.
--
-- @tparam string name "rear", "charge" or "lean"
-- @treturn string formatted tutorial message
function HorseCollisionMod:FormatTutorialText(name)
	local cfg = self.Config
	local pad = self:IsController()

	if name == "rear" then
		local btn = pad and "[L-Stick]"
				or ("[" .. string.upper(cfg.RearOnlyKey) .. "]")

		return "Horsemanship: Rear Maneuver\n\n"
				.. "Bring your horse to a stop and press " .. btn
				.. " to rear up and strike anyone ahead.\n\n"
				.. "- Consumes horse stamina (short cooldown).\n"
				.. "- Warning: Striking innocent bystanders is a crime!"
	elseif name == "charge" then
		local btn = pad and "[LT]"
				or ("[" .. string.upper(cfg.RearChargeKey) .. "]")

		return "Horsemanship: Rear Charge\n\n"
				.. "Bring your horse to a stop and press " .. btn
				.. " to lunge forward, trampling anyone in your path.\n\n"
				.. "- Consumes high horse stamina.\n"
				.. "- Warning: Trampling innocent bystanders is a crime!"
	elseif name == "lean" then
		local left = pad and "[LB]"
				or ("[" .. string.upper(cfg.LeanLeftKey) .. "]")
		local right = pad and "[RB]"
				or ("[" .. string.upper(cfg.LeanRightKey) .. "]")

		return "Horsemanship: Saddle Lean\n\n"
				.. "While mounted, hold " .. left .. " or " .. right
				.. " to lean out and look past your horse's head."
	end

	return ""
end

--- Displays an on-screen tutorial banner for a maneuver.
--
-- @tparam string name "rear", "charge" or "lean"
-- @treturn boolean true if the tutorial was displayed
function HorseCollisionMod:ShowTutorial(name)
	if not name or name == "" then
		return false
	end

	if not self.Config.ShowTutorials then
		return false
	end

	local uiEnabled = true

	pcall(function()
		if System.GetCVar("wh_ui_TutorialsEnabled") == 0 then
			uiEnabled = false
		end
	end)

	if not uiEnabled then
		return false
	end

	if self.TutorialsShown[name] then
		return false
	end

	self.TutorialsShown[name] = true

	local text = self:FormatTutorialText(name)

	if text == "" then
		return false
	end

	local ok = false

	pcall(function()
		if Game and Game.ShowTutorial then
			Game.ShowTutorial(text, self.TutorialBannerSec, false, true)
			ok = true
		end
	end)

	if self.Config.LogTelemetry then
		self:Log("Tutorial shown name=" .. tostring(name) .. " ok=" .. tostring(ok))
	end

	return ok
end

--- Shows the banners for newly available maneuvers, one after another.
--
-- When several perks are acquired at once, in the perk menu, this shows the
-- first banner at once and schedules the next for when the first banner has
-- left the screen, so every banner plays in full.
--
-- Without `RequirePerks` only the rear's banner is shown here; the charge's
-- and the lean's appear on their first use.
--
-- Called on mounting and on leaving the inventory.
function HorseCollisionMod:QueueNextTutorial()
	if not self.Config.ShowTutorials then
		return
	end

	if not player or not player.soul then
		return
	end

	if self.Config.RequirePerks then
		local pending = {}

		for _, maneuver in ipairs(self.Maneuvers) do
			local has = false

			pcall(function()
				has = player.soul:HasAbility(maneuver.ability)
			end)

			if has and not self.TutorialsShown[maneuver.banner] then
				table.insert(pending, maneuver.banner)
			end
		end

		if #pending > 0 then
			self:ShowTutorial(pending[1])

			if #pending > 1 and not self.TutorialTimerPending then
				self.TutorialTimerPending = true

				local tick = self.TimerTick
				local after = (self.TutorialBannerSec * 1000)
						+ self.TutorialBannerGapMs

				Script.SetTimer(after, function()
					self.TutorialTimerPending = false
					if self.TimerTick == tick and not self.InventoryOpen then
						self:QueueNextTutorial()
					end
				end)
			end
		end
	else
		if not self.TutorialsShown["rear"] then
			self:ShowTutorial("rear")
		end
	end
end

--- Matches the shown banners to the abilities in the loaded save.
--
-- Called from the load screen handler. An ability the loaded character
-- already has marks its banner as shown, so it is not repeated; one they lack
-- clears the mark, so unlocking it later in this save shows the banner.
function HorseCollisionMod:SyncTutorialsOnLoad()
	self.TutorialTimerPending = false

	if not player or not player.soul then
		return
	end

	if self.Config.RequirePerks then
		for _, maneuver in ipairs(self.Maneuvers) do
			local hasAbility = false

			pcall(function()
				hasAbility = player.soul:HasAbility(maneuver.ability)
			end)

			if hasAbility then
				self.TutorialsShown[maneuver.banner] = true
			else
				self.TutorialsShown[maneuver.banner] = nil
			end
		end
	end

	if self.Config.LogTelemetry then
		self:Log("SyncTutorialsOnLoad rear=" .. tostring(self.TutorialsShown["rear"])
				.. " charge=" .. tostring(self.TutorialsShown["charge"])
				.. " lean=" .. tostring(self.TutorialsShown["lean"]))
	end
end

--- Clears the history of displayed tutorials.
function HorseCollisionMod:ResetTutorials()
	self.TutorialsShown = {}
	self.TutorialTimerPending = false
	self:Log("Tutorials reset")
end
