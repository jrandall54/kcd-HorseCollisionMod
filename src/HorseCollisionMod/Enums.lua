--- Engine enums used by the collision reaction calls.
--
-- Both tables are transcribed from `Libs/AI/TypeDefinitions.xml` and are
-- attached to the `HorseCollisionMod` table created by the entry point. This
-- file defines data only: it is pulled in by `Script.ReloadScript` from
-- `Scripts/Startup/HorseCollisionMod.lua` and re-running it is harmless.
--
-- @module HorseCollisionMod.Enums
-- @author jrandall54
-- @release 4.5.0

--- Engine enum, transcribed from `Libs/AI/TypeDefinitions.xml`.
--
-- The values are deliberately non-sequential; they mirror a C++ enum. The
-- full set is kept rather than just the value used, so the contract stays
-- verifiable against the engine.
--
-- @table HitReactionType
HorseCollisionMod.HitReactionType = {
	Melee = 1,
	Collision = 2,
	Fall = 7,
	Bullet = 10,
	MeleeStealth = 16
}

--- Engine enum, transcribed from `Libs/AI/TypeDefinitions.xml`.
--
-- Ascending severity. `Tickle` and `Unpleasant` cost the victim no health.
--
-- @table HitReactionStrength
HorseCollisionMod.HitReactionStrength = {
	Zero = 0,
	Healing = 1,
	Tickle = 2,
	Unpleasant = 3,
	Exhausting = 4,
	MinorInjury = 5,
	MajorInjury = 6,
	Fatal = 7
}

--- Engine enum, transcribed from `Libs/AI/TypeDefinitions.xml`.
--
-- The kind of attack a combat stimulus describes. Sequential here, unlike
-- `HitReactionType`, and the comment in the type definition says the melee
-- entries are ordered by increasing violence.
--
-- `Unarmed` is what a shove from horseback is charged as by this mod: it is
-- the mildest melee kind, and a provoked scuffle is a scuffle rather than an
-- armed assault.
--
-- @table CombatAttackKind
HorseCollisionMod.CombatAttackKind = {
	None = 0,
	Missile = 1,
	StealthAction = 2,
	Unarmed = 3,
	Melee = 4,
	DogBite = 5
}
