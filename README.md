# Horse Collision Mod
No more hitting pedestrians like brick walls. This mod adds real physics to horse impacts in Kingdom Come: Deliverance. 

If you are galloping fast enough, running into an NPC will knock them over and toss their ragdoll out of your way. Because it hooks directly into the game's momentum physics rather than faking an attack, you won't get an assault bounty for running people over.

## Configurable Settings
You can easily customize the mod by opening the script (instructions below) and tweaking these values:
* **SpeedThreshold:** The minimum horse speed required to trigger a knockdown. 
* **HitRadius:** How close the horse needs to be to physically register the impact.
* **Knockback:** The raw push-back force applied to the NPC (Default: 50.0).
* **Uplift:** The vertical upward force applied during the impact (Default: 30.0).

## How to Configure
1. Locate the installed mod in your directory: Mods\HorseCollisionMod\Data\.
2. Right-click HorseCollisionMod.pak using **7-Zip** (or WinRAR) and select **Open Archive**. 
3. Right-click the HorseCollisionMod.lua file inside the window and select **Edit**.
4. Change the numbers in the config table at the top of the file and hit Save.
5. Close Notepad. When 7-Zip asks to update the archive, click **Yes**. 

## Installation
Extract the .zip directly into your C:\Games\Kingdom Come - Deliverance\Mods\ folder, or install normally via Vortex.
