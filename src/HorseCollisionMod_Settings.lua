--- Settings for HorseCollisionMod. This is the file to edit.
--
-- Change a value, save, and let the archive update when prompted. Nothing else
-- in the mod needs touching, and anything left out or misspelled falls back to
-- the default rather than breaking.
--
-- Speeds are meters per second. Distances are meters from the horse's center.
--
-- @script HorseCollisionMod_Settings

HorseCollisionModSettings = {

	-- Speed tiers. Below SpeedWalk nothing happens at all.
	SpeedWalk                = 1.8,   -- staggers, no damage, no stamina cost
	SpeedTrot                = 4.5,   -- knocked down
	SpeedGallop              = 8.5,   -- knocked down harder

	-- What counts as contact. Lower these if NPCs react when you ride past.
	HorseFrontReach          = 1.05,  -- meters ahead of the horse
	HorseHalfWidth           = 0.70,  -- meters to either side
	HorseRearReach           = 0.20,  -- meters behind
	HitCooldownMs            = 3000,  -- before a staggered NPC can react again
	KnockdownRecoveryMs      = 6000,  -- before a floored one can, they lie
	                                  -- there long after a stagger ends

	-- Knockdown force, trot and gallop only.
	Knockback                = 50.0,  -- horizontal, higher throws further
	Uplift                   = 30.0,  -- vertical, higher throws upward

	-- What the horse actually collides with, in kilograms. Every human is
	-- 80 to the physics engine, so a peasant and a knight are the same
	-- thing to hit, which is why armor has never been felt in a throw.
	-- This is divided by the armor scale, so mail is heavier to move.
	-- 0 leaves the engine's figure alone.
	--
	-- The exponent decides how far apart armored and unarmored victims land,
	-- and the base decides how far everyone travels. The base cancels out of
	-- the ratio between the two, so raising it shortens every throw without
	-- changing which victim resists; only the exponent widens the gap.
	--
	-- At these figures a villager is about 43 kg and a mailed guard about
	-- 4900, and the measured throws are 4.19 m against 1.92 m. Lowering the
	-- base to 40 roughly doubles the separation on the ground but launches
	-- light victims twelve meters and further, which does not read as a
	-- person being hit by a horse.
	RagdollMass              = 100.0,
	RagdollMassArmorScaled   = true,
	RagdollMassArmorExponent = 3.7,
	RagdollDamping           = 3.0,   -- higher stops a thrown body sooner
	RagdollMinEnergy         = 0.5,   -- higher puts it to rest sooner

	-- Stamina, against a full pool of roughly 210.
	StaminaDrainWalk         = 0.0,
	StaminaDrainTrot         = 18.0,
	StaminaDrainGallop       = 22.0,
	CombatStaminaMultiplier  = 2.2,   -- 1.0 removes the combat penalty
	ThrowRiderOnStaminaEmpty = true,  -- false still drains stamina

	-- How much what a target is wearing changes the impact. Weight is the
	-- sum of their armor, from the game's own item tables: a villager is
	-- around 5, a mail-wearing guard around 47.
	--
	-- Both multipliers are 1.0 at ArmorReferenceWeight and move from there.
	-- An exponent of 0 switches that half off and keeps the old behavior.
	ArmorReferenceWeight     = 8.0,   -- the weight that changes nothing
	ArmorImpulseExponent     = 0.5,   -- higher means armor plants them harder
	MinArmorImpulse          = 0.35,  -- a knight is never immovable
	MaxArmorImpulse          = 1.5,   -- nor is a naked peasant weightless
	ArmorStaminaExponent     = 0.4,   -- higher means armor tires the horse more
	MinArmorStamina          = 0.75,
	MaxArmorStamina          = 3.0,

	-- The floor a collision will not take a victim below. A collision puts
	-- its victim into a wounded state whose exit is gated on health, and an
	-- NPC never heals, so a victim left below that gate stays wounded for
	-- good: rooted in place, unable to fight, permanently.
	--
	-- Damage still lands, and still accumulates, down to this figure. The
	-- cost is that a collision can no longer kill: a victim cannot be
	-- trampled past the floor, however many times they are ridden into.
	-- Set it to 0 to restore the behavior 3.0.0 shipped with, lockup
	-- included.
	SuppressAutoCureSec      = 30,   -- exempt victims from the auto-cure daycycle
	TrotReaction             = "fall",
	         -- "fall" is an animated fall the game recovers from,
	         -- "knockdown" adds an animated get-up, "ragdoll" is physics
	AutoCureHealthLimit      = 40.0,  -- exemption held until health is back over this

	-- Losing patience. Barging the same person at a walk costs nobody
	-- anything, so this lets them run out of patience and swing back. The
	-- first shove is always free; each one after that rolls against a
	-- chance that grows with the count.
	--
	-- The fight it starts is deliberately not a crime: no fine, no guard
	-- summoned. Guards who actually witness the brawl still wade in.
	--
	-- Only men fight back. The game itself refuses the fight branch to
	-- women, and nothing this mod sets changes that.
	Retaliation              = true,
	RetaliationFreeBumps     = 1,     -- shoves tolerated before any chance
	RetaliationChanceStep    = 0.25,  -- added per shove beyond that
	RetaliationMaxChance     = 0.85,  -- the chance never exceeds this
	RetaliationMemorySec     = 45,    -- how long a victim stays annoyed
	-- The brawl is not timed. The mod watches the victim's own state, and
	-- when the fight is over it puts him back the way it found him.
	RetaliationCeilingSec    = 120,   -- failsafe, stop watching after this

	-- The noise a collision makes, played as the horse hits them.
	--
	-- No single sound in the game is a horse striking a person, because
	-- vanilla never makes that noise. These are layered instead: the horse's
	-- own landing carries the weight, and a blunt impact ten milliseconds
	-- later is the body it hit.
	--
	-- Any of the game's 1803 audio trigger names may be used, listed in
	-- Libs/GameAudio/*.xml inside GameData.pak. A name that does not exist
	-- plays nothing rather than breaking anything, and an empty list silences
	-- that tier alone.
	--
	ImpactSound              = true,

	-- Each tier is a list of { trigger, delay in milliseconds }. The trigger
	-- name "body" is replaced with the blunt impact matching what the victim
	-- is wearing: cloth, mail or plate.
	-- A third entry is a distance in meters, and it is the volume control:
	-- the layer is pushed that far back along the line from the listener, so
	-- it arrives from the same direction and quieter. Higher is quieter, and
	-- it does nothing to `a_o_jump_landing`, which is a 2D event whose level
	-- is fixed.
	--
	-- Walk names the cloth impact outright rather than using the `body` token.
	-- A shove at walking pace should not ring somebody's mail, which the token
	-- would do for an armored victim.
	-- A layer is { trigger, delay in ms, distance in meters, chance }.
	--
	-- Distance is the volume control. There is no gain anywhere in this
	-- engine's audio, so a layer is quietened by being played from further
	-- away: the offset is added along the line from the listener to the
	-- victim, so it arrives from the same direction and only its level drops.
	-- Because a victim is always a meter or two away at the moment of impact,
	-- the number behaves as a volume knob rather than as a position.
	--
	-- It does nothing to a 2D event. `a_o_jump_landing` and
	-- `c_special_bone_crack1` both ignore position entirely, so the only
	-- control over those is `chance`, which is how often the layer appears.
	--
	-- Two trigger names are tokens, replaced with the sample matching what the
	-- victim is wearing: `body` is the blunt impact against that material and
	-- `foley` is the movement rustle it makes.

	-- A shove disturbs someone's clothing rather than striking them, so the
	-- walk tier is cloth foley over a body settling, with a single hoofstep
	-- underneath for the horse. Quiet by being pushed back five meters.
	-- A layer is { trigger, delay in milliseconds, distance in meters, chance }.
	--
	-- Distance is the volume control, because the engine has no gain: a layer
	-- is quietened by being played from further away, offset along the line
	-- from the listener to the victim so it arrives from the same direction.
	-- A victim is always a meter or two away at impact, so the number behaves
	-- as a volume knob rather than as a position. The curve is steep and short:
	-- for the blunt impacts the usable range is about a meter, and past
	-- roughly 1.5 the sound is gone entirely, so the fine adjustments are
	-- fractional and are made to one copy of a layer rather than to all of it.
	--
	-- Distance does nothing to a 2D event. `a_o_jump_landing` and
	-- `c_special_bone_crack1` ignore position completely, which is why neither
	-- is used here.
	--
	-- Loudness otherwise comes from repetition. Naming a sample twice a few
	-- milliseconds apart thickens and lifts it, which is the only way up once
	-- a layer is already at zero distance.
	--
	-- Two trigger names are tokens, replaced with the sample matching what the
	-- victim is wearing: `body` is the blunt impact against that material and
	-- `foley` is the movement rustle it makes.

	-- A shove disturbs someone's clothing rather than striking them, so the
	-- walk tier carries no impact at all: two cloth foleys and a body
	-- settling, each doubled because those samples are very quiet, over a
	-- single hoofstep.
	ImpactSoundWalk          = { { "f_n_mat_foleyal_cl", 0 },
	                             { "hs_hp_soil", 4 },
	                             { "f_n_mat_foleyal_cl", 5 },
	                             { "f_n_mat_foleyam_cl", 8 },
	                             { "f_bodyfall1", 12 },
	                             { "f_n_mat_foleyam_cl", 13 },
	                             { "f_bodyfall1", 18 } },

	-- A trot puts someone on the ground, so the blunt impact leads, doubled
	-- with the second copy taken back a fraction to shade it down.
	ImpactSoundTrot          = { { "body", 0 },
	                             { "body", 8, 0.9 },
	                             { "f_bodyfall1", 14 } },

	-- A gallop stacks four different blunt impacts rather than repeats of one,
	-- so it reads as a collision instead of a flam, over a dull heavy thud
	-- held back to sit underneath, a hoofstep, and the body settling. Every
	-- impact layer is a token, so a mailed guard and a peasant in cloth sound
	-- different on all four.
	ImpactSoundGallop        = { { "body", 0 },
	                             { "n_lu_log_ground", 4, 5 },
	                             { "body_armed", 6 },
	                             { "blunt", 9, 1 },
	                             { "hs_hp_soil", 10 },
	                             { "face_armed", 18 },
	                             { "f_bodyfall1", 24 } },

	-- The occasional injury, gallop only. A foley event, so unlike
	-- `c_special_bone_crack1` it can be quietened; that one is 2D and came out
	-- at cartoon volume whatever was done to it.
	ImpactSoundCrack         = { "f_bodyfall_leg_break", 20, 6 },
	ImpactSoundCrackChance   = 0.12,

	-- What a victim looks like afterwards. Someone ridden down at a gallop
	-- otherwise stands back up immaculate. Dirt covers everything they are
	-- wearing; blood goes on the side of the body the horse struck. Both are
	-- amounts between 0 and 1 and both accumulate, so a man ridden down
	-- repeatedly gets steadily filthier. Setting either to 0 switches that
	-- half off. Nothing is applied at a walk, where nobody hits the ground.
	VictimMarks              = true,
	VictimDirtTrot           = 0.35,
	VictimDirtGallop         = 0.60,
	VictimBloodTrot          = 0.15,
	VictimBloodGallop        = 0.45,

	-- Switches.
	CollisionIsCrime         = true,  -- riding someone down is a crime at trot
	                                  -- and gallop; never at a walk
	ReleaseAnimationMovement = true,  -- keeps staggering victims out of walls
	ReplanAfterReaction      = true,  -- sends them back to their stall or
	                                  -- whatever they were leaning on
	SuppressStaggerInCombat  = true,  -- skip the stagger during a fight
	WalkStagger              = true,  -- false gives vanilla behavior at a walk
	ProtectMutt              = true,  -- whether your dog is immune
	LogTelemetry             = true,  -- diagnostics in kcd.log

	-- Names the reason a nearby NPC produced no reaction. Writes a line for
	-- every entity near the horse, including doors and audio areas, which is
	-- thousands per session. Only useful while investigating why a specific
	-- impact did nothing. `build.ps1` refuses a release build with this on.
	DiagnoseMisses           = false

}
