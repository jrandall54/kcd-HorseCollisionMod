# Technical Implementation Details

This document outlines the specific challenges and findings related to modifying Kingdom Come: Deliverance 1, specifically regarding AI overrides, C++ Native Sandboxing, and physics loops.

## 1. The Physics vs AI Override
Attempting to force a physics rigid body hook on a living NPC inherently fails in KCD. The AI Sub-Brain continuously overrides standard kinematics to lock their skeletal structure into the standard behavior tree, making the NPC stand back up instantly or entirely absorb AddImpulse blasts like brick walls.

While previous attempts tried parsing fake Hit Tables into ent.Server.OnHit() to trigger a ragdoll, KCD's C++ native engine strictly crashes if the hit.type or hit.pos arrays are incomplete (throwing a fatal Singeplayer.lua:0 error). 

Instead, this mod entirely bypasses the Damage framework and directly targets the AI Kinematic Core: it executes 
pc.actor:Fall({x=0,y=0,z=0}, true). This natively strips the rigid behavior tree, forcing them into a clean physical ragdoll state exactly 50ms before the 
pc:AddImpulse mathematically blasts them backwards based on the configurable vectors. Because no damage or hit table is ever parsed, no assault bounty is generated.

## 2. The Lua Configuration Sandbox
KCD's Developer Console (~) operates in a completely restricted environment from the physics thread. If users attempt to execute evaluated Lua code utilizing # while on a retail client without -devmode explicitly forced in the engine config, the commands silently fail. Subsequently, .cfg initialization scripts natively ignore dynamic memory access.

The community standard configuration for KCD scripts requires loose deployment: distributing .pak wrappers exactly as Mods/ModName/Data/ModName.pak. Users utilize 7-Zip to open the .pak archive without extracting it, altering the numerical arrays natively at the top of the Source Code script, and repacking it synchronously. 

## 3. Sandboxing Limits
KCD's proprietary engine severely restricts vanilla Lua functionality:
- You cannot write to files (the io library is restricted). 
- You cannot use os.clock() (it throws a nil exception). Use System.GetCurrTime().
- Iterating or checking properties on C++ UserData entities (like scenery variables) outside of pcall() wrappers will throw fatal runtime exceptions.

## 4. Timer Ghosting & Save Reloads
Whenever a player reloads a save, or transitions a core level context, KCD ruthlessly purges all active Local Timers allocated to the Lua state. Conversely, if a script hooks into sys_loadingimagescreen to re-initialize a timer after the reload, older timers may occasionally persist, causing duplicating timer loops that lag the game and destroy the Audio buffer.

This mod utilizes a Tick lifecycle identity manager. Every time the loading screen closes, it numerically increments self.TimerTick and passes that specific ID deeply into the UpdateTimer() closure hook. If any previous "ghost" instances of the timer survived the reload, they inherently realize their internally cached ID no longer matches the global master, and they cleanly kill themselves, resulting in absolutely flawless Save/Load resilience. 
