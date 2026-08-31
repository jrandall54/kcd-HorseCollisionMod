--- Settings for HorseCollisionMod. This is the file to edit.
--
-- Change a value, save, and let the archive update when prompted. Nothing else
-- in the mod needs touching, and anything left out or misspelled falls back to
-- the default rather than breaking.
--
-- Speeds are meters per second. Distances are meters from the horse's centre.
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
	TrotReaction             = "knockdown", -- "knockdown" or "ragdoll"
	AutoCureHealthLimit      = 40.0,  -- exemption held until health is back over this

	-- Switches.
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
