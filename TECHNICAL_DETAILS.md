# Technical Implementation Details

This document outlines the specific challenges and findings related to modifying Kingdom Come: Deliverance 1, specifically regarding AI overrides, sandboxing, and physics.

## 1. The Physics vs AI Override
Attempting to force a rigid physics event on a living NPC (e.g. TurnRagdoll(1)) inherently fails in KCD. The AI Sub-Brain continuously overrides standard kinematics to maintain its current "patrol animations", making the NPC stand back up instantly or glitch. 

Instead of fighting the AI, this mod leans *into* it. It triggers KCD's organic HitDeathReactions.lua payload by calculating the horse velocity, formatting a hit-table (knocksDownLeg = true), setting TypeID = 0 (standard physics), and executing a native ent.Server.OnHit(ent, hit) command. This forces the AI to naturally drop the behavior tree and handle the "fall to the floor" reaction before getting back up.

## 2. Masking the Crime System
By actively falsifying the shooterId inside the payload natively (setting it to 
il), the NPC AI understands they were hit by a massive physical impact but are neurologically unaware that the player on the horse caused it. Their internal AI drops the behavior tree to naturally handle the "fall to the floor" reaction before dusting themselves off, completely bypassing the assault bounty.

## 3. CryEngine Lua Sandboxing
KCD's proprietary engine severely restricts Lua functionality. 
- You cannot write to files (the io library is restricted). 
- You cannot use os.clock() (it throws a nil value exception). The mod uses System.GetCurrTime() instead for cooldowns.
- Iterating or checking properties on C++ UserData entities (like scenery rocks or trees) outside of pcall() wrappers will throw fatal runtime exceptions. The mod safely wraps all entity class checks in pcall() blocks to prevent thread deaths when scanning a 2.5-meter radius around the moving horse coordinates.

## 4. Audio Thread Starvation
If the physics polling loop Script.SetTimer(100) is instantiated on a generic loading screen hook without a strict state-lock, the engine will duplicate the polling loops on every subsequent zone transition. Over time, the game scans the area 100 times a second instead of 10, starving the CPU thread and causing the game's audio buffer to stutter and sound "underwater". This mod ensures the timer spawns exactly once per session.

## 5. Vortex Compilation
To build a .zip archive exactly as Vortex and KCD expects, the internal .pak files must be compressed strictly as standard ZIP (Deflate), **not** LZMA2 (.7z). If built with LZMA2, the C++ engine fails to parse the headers, rendering the mod completely inert across the VFS.
