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
	HorseHalfWidth           = 0.35,  -- meters to either side
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
	-- The exponent is what separates armored victims from unarmored ones.
	-- The base cancels out of the ratio between them, which is why 80 and 40
	-- both measured at parity: both hand the horse the same 3.4x spread.
	--
	-- TEST RIDE: base 40, exponent 2. That squares the spread to 11.6x,
	-- putting villagers at 25-30 kg and guards at 227-327.
	RagdollMass              = 40.0,
	RagdollMassArmorScaled   = true,
	RagdollMassArmorExponent = 2.0,
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
	-- The brawl is not timed. The mod watches the victim's own state and
	-- steps in only if they leave the fight and keep running, which the
	-- game sometimes does not resolve on its own.
	RetaliationFleeSpeed     = 3.5,   -- m/s that counts as running away
	RetaliationFleeIgnoreRange = 25.0,-- how far off you must be first; running
	                                  -- from someone stood over you is fair
	RetaliationFleeSamples   = 8,     -- seconds of that before stepping in
	RetaliationCeilingSec    = 120,   -- failsafe, stop watching after this

	-- Switches.
	CollisionIsCrime         = false,  -- riding someone down is a crime at trot
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
	DiagnoseMisses           = true

}
