--- In-game tutorial guidance for horseback maneuvers.
--
-- Explains how to execute the Rear, Rear Charge, and Saddle Lean maneuvers,
-- detailing key controls, standstill requirements, stamina drain, and crime
-- consequences. Attached to the `HorseCollisionMod` table created by the
-- entry point, which pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Tutorial
-- @author jrandall54
-- @release 5.25.0

HorseCollisionMod.TutorialsShown = HorseCollisionMod.TutorialsShown or {}

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
-- @tparam string name tutorial identifier ("rear", "charge", "lean", etc.)
-- @treturn string formatted tutorial message
function HorseCollisionMod:FormatTutorialText(name)
	local cfg = self.Config
	local pad = self:IsController()

	if name == "rear" then
		local btn = pad and "[L-Stick]"
				or ("[" .. string.upper(cfg.RearOnlyKey or "f") .. "]")
		return "Horsemanship: Rear Maneuver\n\n"
				.. "Bring your horse to a stop and press " .. btn
				.. " to rear up and strike anyone ahead.\n\n"
				.. "- Consumes horse stamina (short cooldown).\n"
				.. "- Warning: Striking innocent bystanders is a crime!"
	elseif name == "charge" then
		local btn = pad and "[LT]"
				or ("[" .. string.upper(cfg.RearChargeKey or "r") .. "]")
		return "Horsemanship: Rear Charge\n\n"
				.. "Bring your horse to a stop and press " .. btn
				.. " to lunge forward, trampling anyone in your path.\n\n"
				.. "- Consumes high horse stamina.\n"
				.. "- Warning: Trampling innocent bystanders is a crime!"
	elseif name == "lean" then
		local left = pad and "[LB]"
				or ("[" .. string.upper(cfg.LeanLeftKey or "q") .. "]")
		local right = pad and "[RB]"
				or ("[" .. string.upper(cfg.LeanRightKey or "e") .. "]")
		return "Horsemanship: Saddle Lean\n\n"
				.. "While mounted, hold " .. left .. " or " .. right
				.. " to lean out and look past your horse's head."
	end

	return ""
end

--- Displays an on-screen tutorial banner for a maneuver.
--
-- @tparam string name tutorial identifier ("rear", "charge", "lean", etc.)
-- @tparam[opt] boolean force true to bypass settings and CVar checks
-- @treturn boolean true if the tutorial was displayed
function HorseCollisionMod:ShowTutorial(name, force)
	if not name or name == "" then
		return false
	end

	if not self.Config.ShowTutorials and not force then
		return false
	end

	local uiEnabled = true
	pcall(function()
		if System.GetCVar("wh_ui_TutorialsEnabled") == 0 then
			uiEnabled = false
		end
	end)

	if not uiEnabled and not force then
		return false
	end

	self.TutorialsShown = self.TutorialsShown or {}

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
			Game.ShowTutorial(text, 10, false, true)
			ok = true
		end
	end)

	if self.Config.LogTelemetry then
		self:Log("Tutorial shown name=" .. tostring(name) .. " ok=" .. tostring(ok))
	end

	return ok
end

--- Displays newly acquired maneuver tutorials in order, scheduling subsequent banners.
--
-- When multiple perks are acquired at once (e.g. in the perk menu), this shows
-- the first banner immediately and schedules subsequent banners to appear after
-- the preceding banner's 10-second display duration expires, ensuring every
-- tutorial plays in full in sequence.
function HorseCollisionMod:QueueNextTutorial()
	if not self.Config.ShowTutorials then
		return
	end

	local playerEnt = rawget(_G, "player")
	if not playerEnt or not playerEnt.soul then
		return
	end

	self.TutorialsShown = self.TutorialsShown or {}

	if self.Config.RequirePerks then
		local perks = {
			{ id = "lean", ability = "hcm_lean" },
			{ id = "rear", ability = "hcm_rear" },
			{ id = "charge", ability = "hcm_charge" },
		}

		local pending = {}
		for _, p in ipairs(perks) do
			local has = false
			pcall(function()
				has = playerEnt.soul:HasAbility(p.ability)
			end)
			if has and not self.TutorialsShown[p.id] then
				table.insert(pending, p.id)
			end
		end

		if #pending > 0 then
			local nextId = pending[1]
			self:ShowTutorial(nextId)

			if #pending > 1 and not self.TutorialTimerPending then
				self.TutorialTimerPending = true
				local tick = self.TimerTick
				Script.SetTimer(10500, function()
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

--- Checks whether newly acquired maneuver tutorials should be shown on mount.
--
-- @tparam table playerEnt the player entity table
function HorseCollisionMod:CheckMountTutorials(playerEnt)
	self:QueueNextTutorial()
end

--- Checks whether newly acquired maneuver tutorials should be shown when leaving menus.
function HorseCollisionMod:CheckMenuTutorials()
	self:QueueNextTutorial()
end

--- Synchronizes tutorial state against the player's actual abilities in the loaded save.
--
-- Called on save load (sys_loadingimagescreen OnEnd). If a loaded character
-- already has an ability, mark its tutorial as already shown so the player is
-- not spammed. If the loaded character does NOT have the ability in this save,
-- clear the flag so unlocking it later in this save cleanly displays the banner.
function HorseCollisionMod:SyncTutorialsOnLoad()
	self.TutorialsShown = self.TutorialsShown or {}
	self.TutorialTimerPending = false

	local playerEnt = rawget(_G, "player")
	if not playerEnt or not playerEnt.soul then
		return
	end

	if self.Config.RequirePerks then
		local abilities = {
			rear = "hcm_rear",
			charge = "hcm_charge",
			lean = "hcm_lean",
		}

		for bannerName, abilityName in pairs(abilities) do
			local hasAbility = false
			pcall(function()
				hasAbility = playerEnt.soul:HasAbility(abilityName)
			end)

			if hasAbility then
				self.TutorialsShown[bannerName] = true
			else
				self.TutorialsShown[bannerName] = nil
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
