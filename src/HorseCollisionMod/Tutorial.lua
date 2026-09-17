--- In-game tutorial guidance for horseback maneuvers.
--
-- Explains how to execute the Rear, Rear Charge, and Saddle Lean maneuvers,
-- detailing key controls, standstill requirements, stamina drain, and crime
-- consequences. Attached to the `HorseCollisionMod` table created by the
-- entry point, which pulls this file in with `Script.ReloadScript`.
--
-- @module HorseCollisionMod.Tutorial
-- @author jrandall54
-- @release 5.22.1

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
	elseif name == "rear_locked" then
		local btn = pad and "[L-Stick]"
				or ("[" .. string.upper(cfg.RearOnlyKey or "f") .. "]")
		return "Rear Maneuver Locked\n\n"
				.. "Requires the Horsemanship perk 'Rear in Headlights' (Level 7).\n"
				.. "Bring your horse to a stop and press " .. btn .. " to perform."
	elseif name == "charge_locked" then
		local btn = pad and "[LT]"
				or ("[" .. string.upper(cfg.RearChargeKey or "r") .. "]")
		return "Rear Charge Locked\n\n"
				.. "Requires the perk 'Move Roach, Get Out the Way' (Level 10).\n"
				.. "Bring your horse to a stop and press " .. btn .. " to perform."
	elseif name == "lean" then
		local left = pad and "[LB]"
				or ("[" .. string.upper(cfg.LeanLeftKey or "q") .. "]")
		local right = pad and "[RB]"
				or ("[" .. string.upper(cfg.LeanRightKey or "e") .. "]")
		return "Horsemanship: Saddle Lean\n\n"
				.. "While mounted, hold " .. left .. " or " .. right
				.. " to lean out and look past your horse's head."
	elseif name == "lean_locked" then
		local left = pad and "[LB]"
				or ("[" .. string.upper(cfg.LeanLeftKey or "q") .. "]")
		local right = pad and "[RB]"
				or ("[" .. string.upper(cfg.LeanRightKey or "e") .. "]")
		return "Saddle Lean Locked\n\n"
				.. "Requires the Horsemanship perk 'Hello There' (Level 4).\n"
				.. "Hold " .. left .. " or " .. right .. " while mounted to lean."
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

--- Checks whether newly unlocked maneuver tutorials should be shown on mount.
--
-- @tparam table playerEnt the player entity table
function HorseCollisionMod:CheckMountTutorials(playerEnt)
	if not self.Config.ShowTutorials then
		return
	end

	if not playerEnt or not playerEnt.soul then
		return
	end

	self.TutorialsShown = self.TutorialsShown or {}

	if self.Config.RequirePerks then
		local hasRear = false
		local hasCharge = false
		local hasLean = false

		pcall(function()
			hasRear = playerEnt.soul:HasAbility("hcm_rear")
			hasCharge = playerEnt.soul:HasAbility("hcm_charge")
			hasLean = playerEnt.soul:HasAbility("hcm_lean")
		end)

		if hasRear and not self.TutorialsShown["rear"] then
			self:ShowTutorial("rear")
			return
		end

		if hasCharge and not self.TutorialsShown["charge"] then
			self:ShowTutorial("charge")
			return
		end

		if hasLean and not self.TutorialsShown["lean"] then
			self:ShowTutorial("lean")
			return
		end
	else
		if not self.TutorialsShown["rear"] then
			self:ShowTutorial("rear")
		end
	end
end

--- Checks whether newly unlocked maneuver tutorials should be shown when leaving menus.
function HorseCollisionMod:CheckMenuTutorials()
	if not self.Config.ShowTutorials then
		return
	end

	local playerEnt = rawget(_G, "player")
	if not playerEnt or not playerEnt.soul then
		return
	end

	self.TutorialsShown = self.TutorialsShown or {}

	if self.Config.RequirePerks then
		local hasRear = false
		local hasCharge = false
		local hasLean = false

		pcall(function()
			hasRear = playerEnt.soul:HasAbility("hcm_rear")
			hasCharge = playerEnt.soul:HasAbility("hcm_charge")
			hasLean = playerEnt.soul:HasAbility("hcm_lean")
		end)

		if hasRear and not self.TutorialsShown["rear"] then
			self:ShowTutorial("rear")
		elseif hasCharge and not self.TutorialsShown["charge"] then
			self:ShowTutorial("charge")
		elseif hasLean and not self.TutorialsShown["lean"] then
			self:ShowTutorial("lean")
		end
	end
end

--- Clears the history of displayed tutorials.
function HorseCollisionMod:ResetTutorials()
	self.TutorialsShown = {}
	self:Log("Tutorials reset")
end
