with open('src/HorseCollisionMod/Reaction.lua', 'r', encoding='utf-8') as f:
    text = f.read()

target = "npc:SetPhysicParams(PHYSICPARAM_SIMULATION, { damping = 0, min_energy = 0 })\n\t\tend)"
replacement = "npc:SetPhysicParams(PHYSICPARAM_SIMULATION, { damping = 0, min_energy = 0 })\n\t\tend)\n\n\t\tpcall(function()\n\t\t\tnpc:AwakePhysics(0)\n\t\tend)"

text = text.replace(target, replacement, 1)

with open('src/HorseCollisionMod/Reaction.lua', 'w', encoding='utf-8') as f:
    f.write(text)
