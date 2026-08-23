HorseCollisionMod = {}

HorseCollisionMod.Config = {
	SpeedThreshold = 2.0,
	HitRadius = 2.5,
	DamageMultiplier = 15.0,
	CooldownMs = 3000,
	EnableCrime = false,
	EnableDamage = true
}

HorseCollisionMod.RecentHits = {}
HorseCollisionMod.TimerId = nil

local function GetTimeMs()
	return System.GetCurrTime() * 1000
end

local function GetVectorLength(v)
	if not v then return 0 end
	return math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
end

function HorseCollisionMod:TriggerRagdoll(npc, velocity, speed, horseEnt, playerEnt)
	local npcId = tostring(npc.id)
	local now = GetTimeMs()
	
	if self.RecentHits[npcId] and (now - self.RecentHits[npcId]) < self.Config.CooldownMs then
		return
	end
	self.RecentHits[npcId] = now
	
	System.LogAlways("[HorseCollisionMod] EXECUTING COLLISION ON " .. tostring(npc:GetName()))
	
	local damage = self.Config.DamageMultiplier * speed
	if not self.Config.EnableDamage then damage = 0 end
	
	local theShooter = playerEnt
	if not self.Config.EnableCrime then theShooter = nil end

	local hit = {
		dir = velocity or {x=0,y=0,z=0},
		damage = damage,
		target = npc,
		shooter = theShooter,
		weapon = horseEnt, 
		typeId = 0,
		knocksDownLeg = true,
		knocksDown = true,
		partId = -1,
		materialId = 0
	}
	
	local success, err = pcall(function()
		if npc.Server and type(npc.Server.OnHit) == "function" then
			npc.Server.OnHit(npc, hit)
		end
	end)
	
	if not success then
		System.LogAlways("[HorseCollisionMod] ERROR IN ONHIT: " .. tostring(err))
	end
	
	pcall(function()
		if npc.actor then
			npc.actor:Fall(velocity or {x=0,y=0,z=0}, true)
		end
	end)
end

function HorseCollisionMod:SafeUpdate()
	if type(player) == "nil" or (not player) or type(player.human) == "nil" or type(player.player) == "nil" then return end
	
	local isMounted = false
	pcall(function() isMounted = player.human:IsMounted() end)
	if not isMounted then return end
	
	local horseWuid = nil
	pcall(function() horseWuid = player.player:GetPlayerHorse() end)
	if not horseWuid then return end
	
	local horseEnt = nil
	pcall(function() horseEnt = XGenAIModule.GetEntityByWUID(horseWuid) end)
	if not horseEnt then return end
	
	local velocity = nil
	pcall(function()
		if horseEnt.GetVelocity then velocity = horseEnt:GetVelocity() end
		if not velocity and player.GetVelocity then velocity = player:GetVelocity() end
	end)
	local speed = GetVectorLength(velocity)
	
	if speed >= self.Config.SpeedThreshold then
		local horsePos = nil
		pcall(function() horsePos = horseEnt:GetPos() end)
		if not horsePos then return end
		
		local hitEnts = nil
		pcall(function() hitEnts = System.GetEntitiesInSphere(horsePos, self.Config.HitRadius) end)
		
		if type(hitEnts) == "table" then
			for _, ent in pairs(hitEnts) do
				if ent and type(ent) == "table" and ent.id and ent.id ~= player.id and ent.id ~= horseEnt.id then
					local isHuman = false
					pcall(function() isHuman = (ent.class == 'NPC' or ent.class == 'Player' or (ent.Properties and ent.Properties.esFaction)) end)
					if isHuman and ent.actor then
						local isDead = false
						if ent.IsDead then pcall(function() isDead = ent:IsDead() end) end
						if not isDead then
							self:TriggerRagdoll(ent, velocity, speed, horseEnt, player)
						end
					end
				end
			end
		end
	end
end

function HorseCollisionMod:UpdateTimer()
	if not self.HasStartedTimer then return end
	Script.SetTimer(100, function() HorseCollisionMod:UpdateTimer() end)
	local success, err = pcall(function() self:SafeUpdate() end)
	if not success then
		System.LogAlways("[HorseCollisionMod] CRITICAL ERROR IN UPDATE TIMER: " .. tostring(err))
	end
end

function HorseCollisionMod:uiActionListener(actionName, eventName, argTable)
	if actionName == "sys_loadingimagescreen" and eventName == "OnEnd" then
		if not self.HasStartedTimer then
			self.HasStartedTimer = true
			System.LogAlways("[HorseCollisionMod] Load screen ended. Initializing physics timer.")
			Script.SetTimer(100, function() HorseCollisionMod:UpdateTimer() end)
		end
	end
end

System.LogAlways("[HorseCollisionMod] TOP OF FILE REACHED")

if type(UIAction) == "table" and type(UIAction.RegisterActionListener) == "function" then
    UIAction.RegisterActionListener(HorseCollisionMod, "", "", "uiActionListener")
    System.LogAlways("[HorseCollisionMod] Registered via UIAction!")
else
    System.LogAlways("[HorseCollisionMod] FATAL: UIAction IS NIL! Cannot register!")
end