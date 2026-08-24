HorseCollisionMod = {}

HorseCollisionMod.Config = {
	SpeedThreshold = 2.0,
	HitRadius = 2.5,
	Knockback = 50.0,
	Uplift = 30.0,
	ProtectMutt = true
}

HorseCollisionMod.RecentHits = {}

local function GetTimeMs()
	return System.GetCurrTime() * 1000
end

local function GetVectorLength(v)
	if not v then 
		return 0 
	end
	
	return math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
end

function HorseCollisionMod:TriggerRagdoll(npc, velocity, speed, horseEnt, playerEnt)
	local npcId = tostring(npc.id)
	local now = GetTimeMs()
	
	if self.RecentHits[npcId] and (now - self.RecentHits[npcId]) < 3000 then 
		return 
	end
	
	self.RecentHits[npcId] = now
	System.LogAlways("[HorseCollisionMod] EXECUTING COLLISION ON " .. tostring(npc:GetName()))
	
	pcall(function()
		if npc.actor then
			npc.actor:Fall({x=0,y=0,z=0}, true)
		end
	end)
	
	local k_back = self.Config.Knockback
	local k_up = self.Config.Uplift
	
	if k_back > 0 or k_up > 0 then
		pcall(function()
			local hitPos = {x=0,y=0,z=0}
			
			if npc.GetPos then 
				hitPos = npc:GetPos() 
			end

			hitPos.z = hitPos.z + 1.0
			local dir = {x=1, y=0, z=0}
			
			if speed > 0 and velocity then
				dir.x = velocity.x / speed
				dir.y = velocity.y / speed
				dir.z = 0
			end
			
			local combined = { x = dir.x * k_back, y = dir.y * k_back, z = k_up }
			local impulseMag = math.sqrt((combined.x * combined.x) + (combined.y * combined.y) + (combined.z * combined.z))
			
			if npc.AddImpulse and impulseMag > 0 then
				local normDir = { x = combined.x / impulseMag, y = combined.y / impulseMag, z = combined.z / impulseMag }

				System.LogAlways("[HorseCollisionMod] Applying Knockback Impulse Mag: "
						.. tostring(impulseMag) .. " to "
						.. tostring(npc:GetName()))
				
				Script.SetTimer(50, function()
					pcall(function() 
						npc:AddImpulse(-1, hitPos, normDir, impulseMag, 1) 
					end)
				end)
			end
		end)
	end
end

function HorseCollisionMod:SafeUpdate()
	if type(player) == "nil"
			or (not player)
			or type(player.human) == "nil"
			or type(player.player) == "nil" then return
	end
	
	local isMounted = false
	pcall(function() 
		isMounted = player.human:IsMounted() 
	end)
	
	if not isMounted then 
		return 
	end
	
	local horseWuid = nil
	pcall(function() 
		horseWuid = player.player:GetPlayerHorse() 
	end)
	
	if not horseWuid then 
		return 
	end
	
	local horseEnt = nil
	pcall(function() 
		horseEnt = XGenAIModule.GetEntityByWUID(horseWuid) 
	end)
	
	if not horseEnt then 
		return 
	end
	
	local velocity = nil
	pcall(function()
		if horseEnt.GetVelocity then 
			velocity = horseEnt:GetVelocity() 
		end
		if not velocity and player.GetVelocity then
			velocity = player:GetVelocity() 
		end
	end)
	
	local speed = GetVectorLength(velocity)
	
	if speed >= self.Config.SpeedThreshold then
		local horsePos = nil

		pcall(function()
			horsePos = horseEnt:GetPos() 
		end)
		
		if not horsePos then 
			return 
		end
		
		local hitEnts = nil

		pcall(function()
			hitEnts = System.GetEntitiesInSphere(horsePos, self.Config.HitRadius) 
		end)
		
		if type(hitEnts) == "table" then
			for _, ent in pairs(hitEnts) do
				if ent and type(ent) == "table" and ent.id and ent.id ~= player.id and ent.id ~= horseEnt.id then
					local isMutt = false
					
					pcall(function()
						local entName = ent:GetName()
						if entName and string.find(entName, "dogCompanion") then
							isMutt = true
						end
					end)

					local isProtected = (self.Config.ProtectMutt and isMutt)

					if not isProtected then
						local isHuman = false

						pcall(function()
							isHuman = (ent.class == 'NPC'
									or ent.class == 'Player'
									or (ent.Properties and ent.Properties.esFaction))
						end)
						
						if isHuman and ent.actor then
							local isDead = false

							if ent.IsDead then
								pcall(function() 
									isDead = ent:IsDead() 
								end)
							end

							if not isDead then
								self:TriggerRagdoll(ent, velocity, speed, horseEnt, player)
							end
						end
					end
				end
			end
		end
	end
end

function HorseCollisionMod:UpdateTimer(assignedTick)
	if self.TimerTick ~= assignedTick then 
		return 
	end
	
	Script.SetTimer(100, function() 
		HorseCollisionMod:UpdateTimer(assignedTick) 
	end)
	
	local success, err = pcall(function() 
		self:SafeUpdate() 
	end)
	
	if not success then
		System.LogAlways("[HorseCollisionMod] CRITICAL ERROR IN UPDATE TIMER: " .. tostring(err))
	end
end

function HorseCollisionMod:uiActionListener(actionName, eventName, argTable)
	if actionName == "sys_loadingimagescreen" and eventName == "OnEnd" then
		self.TimerTick = (self.TimerTick or 0) + 1
		local currentTick = self.TimerTick
		
		System.LogAlways("[HorseCollisionMod] Load screen ended. Initializing physics timer loop "
				.. tostring(currentTick))

		Script.SetTimer(100, function()
			HorseCollisionMod:UpdateTimer(currentTick) 
		end)
	end
end

System.LogAlways("[HorseCollisionMod] TOP OF FILE REACHED (Release 1.2.0)")

if type(UIAction) == "table" and type(UIAction.RegisterActionListener) == "function" then
    UIAction.RegisterActionListener(HorseCollisionMod, "", "", "uiActionListener")
    System.LogAlways("[HorseCollisionMod] Registered via UIAction!")
else
    System.LogAlways("[HorseCollisionMod] FATAL: UIAction IS NIL! Cannot register!")
end
