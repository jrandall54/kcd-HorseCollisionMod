local text = ""
local f = io.open("src/HorseCollisionMod/Reaction.lua", "r")
if f then
    text = f:read("*a")
    f:close()
end

text = string.gsub(text, "npc:SetPhysicParams%(PHYSICPARAM_SIMULATION, %{ damping = 0, min_energy = 0 %}%)\n\t\tend%)", "npc:SetPhysicParams(PHYSICPARAM_SIMULATION, { damping = 0, min_energy = 0 })\n\t\tend)\n\n\t\tpcall(function()\n\t\t\tnpc:AwakePhysics(0)\n\t\tend)")

local f2 = io.open("src/HorseCollisionMod/Reaction.lua", "w")
if f2 then
    f2:write(text)
    f2:close()
end
