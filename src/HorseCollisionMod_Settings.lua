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

	-- Knockdown force, trot and gallop only.
	Knockback                = 50.0,  -- horizontal, higher throws further
	Uplift                   = 30.0,  -- vertical, higher throws upward

	-- What the horse collides with, in kilograms. The engine gives every
	-- human 80, and this is written over it.
	--
	-- **It is deliberately the engine's own figure, and the armor scaling is
	-- off.** Armor is separated by the brake instead, which removes a
	-- commanded fraction of a thrown body's speed rather than lying about
	-- what a person weighs.
	--
	-- The scaling divided the base by the armor scale raised to the exponent,
	-- with nothing bounding the result. At base 100 and exponent 3.7 that ran
	-- from 43 kg for an unarmored villager to 1,208 kg for a mailed guard and
	-- 501,187 kg at an armor scale of 0.10, which real guards score. Between
	-- scale 0.35 and 0.10 the mass moved by a factor of a hundred. It was a
	-- cliff rather than a scale, and it made everything stacked on top of it
	-- meaningless: an impulse of 58 against 1,208 kg moves a guard five
	-- centimeters per second, so the knockback, the uplift and the whole
	-- barding force bonus did nothing to anyone in armor.
	--
	-- The write itself stays, and the value is not zero. It doubles as the
	-- signal that the body has physicalized as a ragdoll, which is what the
	-- impulse waits for, so writing the engine's own 80 keeps the handshake
	-- while changing nothing about what the horse hits.
	RagdollMass              = 80.0,
	RagdollMassArmorScaled   = false,
	RagdollMassArmorExponent = 3.7,
	-- How hard a traveling body is dragged, which is the figure that actually
	-- holds it, and the lever that decides how far an armored victim goes.
	-- The ceiling below only decides when the drag starts: past the ceiling
	-- plus the span it saturates, so without this every victim received the
	-- same drag on exactly the fast throws where armor should tell them apart.
	RagdollAirDampingArmorScaled = true,
	RagdollAirDampingArmored = 20.0,  -- drag on a victim in full mail
	RagdollAirDampingUnarmored = 4.0,   -- drag on an unarmored victim

	RagdollSpeedCapArmorScaled = true,
	RagdollSpeedCapArmored   = 2.5,   -- the ceiling for a victim in full mail
	RagdollSpeedCapUnarmored = 6.0,   -- the ceiling for an unarmored victim

	RagdollDamping           = 5.0,   -- higher stops a thrown body sooner
	RagdollMinEnergy         = 1.0,   -- higher puts it to rest sooner
	RagdollDampPollMs        = 100,   -- how often to look at a thrown body
	RagdollDampSettleSpeed   = 0.5,   -- speed it must fall under before damping
	RagdollDampFloorMs       = 200,   -- never damp before this, mid-launch
	RagdollDampCeilingMs     = 6000,  -- damp regardless by this point

	-- Stamina, against a full pool of roughly 210.
	--
	-- One figure per tier, and every tier is charged through the same path, so
	-- the rider's Horsemanship, the horse's barding and the combat penalty all
	-- apply to a rear and a charge exactly as they do to a gallop.
	StaminaDrainByTier       = {
		Walk   = 0.0,   -- a shove costs the horse nothing
		Trot   = 14.0,
		Gallop = 22.0,
		Rear   = 12.0,  -- hooves coming down, standing still
		Charge = 22.0,  -- charged once for the whole lunge, not per victim
	},

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
	-- Which key does what. Only these eight are offered, because the mod
	-- cannot rebind a key at runtime and its action map has to declare each
	-- one in advance: r, q, e, f, y, u, o, h.
	--
	-- The lean takes q and e, the usual keys for it. The rears take r and f,
	-- neither of which does anything in vanilla while mounted. Note that the
	-- key a vanilla action answers to is not always visible in the game's own
	-- files: surrender and draw resolve through the player profile rather
	-- than a pak, so g and the number keys are spoken for without ever
	-- appearing in a scan of the shipped action maps.
	RearChargeKey            = "r",   -- rear, then drive forward
	RearOnlyKey              = "f",   -- rear on the spot
	Rear                     = true,
	RearIdleOnly             = true,  -- also require the horse's idle state
	RearMaxSpeed             = 0.15,  -- horizontal m/s; above this it slides
	RearCooldownMs           = 2500,  -- before another rear is accepted
	RearFragTag              = "hcm_rear_charge", -- rear, then drive forward
	RearOnlyFragTag          = "hcm_rear",       -- the second key rears on the spot
	-- The charge rears in place and is then pushed forward physically, so the
	-- horse collides with the world like any moving horse.
	-- The rear on the spot is its own tier too. Hooves coming down on someone
	-- is not a horse riding into them, so it has its own sound, dust, shake,
	-- blur and reaction rather than borrowing the trot's.
	-- A rear is hooves coming down, so it leads with the horse's own landing
	-- rather than a hoofstep. `a_o_jump_landing` is the front feet hitting the
	-- ground after a jump, which is the same motion.
	--
	-- Its level is fixed: distance and obstruction do nothing to it. The fourth
	-- number is the only control there is, a chance of playing at all, so that
	-- it punctuates a rear rather than being welded to every one of them.
	-- The two armor layers sit further back than they did, and the hoofstep
	-- closer. `body` and `blunt` resolve by what the victim is wearing, and
	-- the chainmail variants are much brighter than the fabric ones: on an
	-- armored target they were masking the hoof entirely, while on an
	-- unarmored one the balance was right. Both were confirmed playing in the
	-- log, so this is a mix rather than a missing trigger.
	ImpactDustEffectRear     = "collisions.destructibles.arrow_soil",

	-- The charge is its own tier, not a gallop. It has its own damage, sound,
	-- dust, camera shake and view blur, so it can be tuned without touching
	-- what an ordinary collision does. It knocks down everyone in a corridor in
	-- front of the horse, with no cap: a crowd cannot shield each other by
	-- standing close.
	--
	-- Its sound drops the log layer an ordinary gallop uses and adds hoofsteps,
	-- so a charge sounds like a horse coming down on someone rather than like
	-- riding into them. `hs_hp_soil` ignores position and plays at a fixed
	-- level, so it is set back from the ear rather than sitting on top.
	RearChargeStrikes        = true,  -- whether the charge knocks people down
	RearChargeStrikeReach    = 1.8,   -- how far ahead it reaches
	RearChargeStrikeWidth    = 0.9,   -- how wide, either side
	RearChargeImpactSpeed    = 7.5,   -- the speed it is scored at
	RearChargeImpulse        = 6000,  -- how hard the charge is pushed
	RearChargeLift           = 0.2,   -- how much of that is upward
	RearChargeWindowMs       = 2600,  -- how long a charge counts as a gallop
	RearStrikes              = true,  -- the rear on the spot hits who is in front
	RearStrikeMs             = 700,   -- when in the animation they land
	-- Leaning out to see past the horse's head, in first person.
	--
	-- The camera slides to one side so you can look along the horse's neck
	-- rather than into it. Amplitude is not the distance traveled: the push
	-- is the opening part of one very slow swing, so at a period of 30 and a
	-- duration of 2 the camera reaches roughly 40 per cent of the amplitude.
	--
	-- Lower LeanPeriod to lean faster, raise LeanAmplitude to lean further.
	Lean                     = true,
	LeanLeftKey              = "q",   -- q and e, the usual lean keys
	LeanRightKey             = "e",
	LeanDistance             = 0.65,  -- how far out the camera holds, in meters
	LeanForwardShare         = 0.35,  -- how much it also carries forward, 0 for none
	LeanTravelAmplitude      = 110.0,   -- higher gets out there faster
	LeanHoldAmplitude        = 3.0,   -- lower holds steadier once out
	LeanPollMs               = 30,
	LeanDeadband             = 0.06,
	LeanMinFlipMs            = 200,
	LeanRunawayFactor        = 2.0,
	LeanMaxAngleDeg          = 45,    -- refuse a lean past this far off the horse's line
	LeanMaxPitchDeg          = 55,    -- and past this far up or down
	LeanSuppressShake        = true,  -- an impact does not shake the view mid lean
	LeanTurnLeadMs           = 200,   -- cancel this far ahead of a fast turn
	LeanHomeMs               = 220,    -- how often the hold is corrected
	LeanShakePeriod          = 40.0,
	LeanShakeSec             = 1.5,  -- long enough to outlast a held lean
	LeanReleaseSec           = 0.05,  -- a short shake, so it expires and comes home

	RearReach                = 2.5,   -- how far in front they reach
	RearArc                  = 70,    -- the arc in front that counts

	Retaliation              = true,
	RetaliationFreeBumps     = 1,     -- shoves tolerated before any chance
	RetaliationChanceStep    = 0.25,  -- added per shove beyond that
	RetaliationMaxChance     = 0.85,  -- the chance never exceeds this
	RetaliationMemorySec     = 45,    -- how long a victim stays annoyed
	-- The brawl is not timed. The mod watches the victim's own state, and
	-- when the fight is over it puts him back the way it found him.
	RetaliationCeilingSec    = 120,   -- failsafe, stop watching after this
	RetaliationPullsRiderDown = true, -- drag the rider down before fighting
	RetaliationSurrenderHint = true,  -- show the surrender prompt during the brawl
	ProvokeDuringCombat      = false, -- provoke new victims while already fighting
	SurrenderHintHoldMs      = 1000,  -- the HUD drops it, so put it back this often
	SurrenderHintYieldsToGame = true, -- guards get the game's own prompt, not
	                                  -- a second one from the mod
	SurrenderHintCalmPasses  = 3,     -- quiet passes before the prompt goes away
	PullDownPollMs           = 250,   -- how often to look for the chance
	PullDownForce            = false, -- ask even when the engine says it cannot
	PullDownRepeatMs         = 1500,  -- ask again this often until it happens
	PullDownCeilingMs        = 8000,  -- stop looking after this

	-- A woman answers the same shove differently, because the game's combat
	-- tree lets only men into the fight branch. She runs and fetches a guard
	-- instead, on the same count and the same roll.
	WomenRaiseAlarm          = true,  -- women raise the alarm rather than fight

	-- What being ridden down costs, over and above the engine's own charge for
	-- the collision. The engine's charge barely notices armor, so this is what
	-- makes a knight in plate different from a villager in a shirt.
	--
	-- Ordinary clothes are in the game's armor table and sum to about 0.4, so
	-- that much is ignored before anything counts as armor. Past it a victim
	-- takes half the tier's damage at ImpactDamageArmorScale, a third at twice
	-- it, and so on down. Worn totals run about 0.3 in clothes, 5 in mail and
	-- 12 or more in plate.
	ImpactDamage             = true,  -- charge the victim for the impact
	-- The damage model, in one place, meant to be read and tuned together.
	--
	-- ImpactDamageByTier says what a collision is worth before armor.
	-- ArmorScale and ArmorCurve say how much of that survives what the victim
	-- is wearing. ArmorFloor says how little armor is allowed to refuse.
	--
	-- Worked example at the defaults: a town guard reads smash_def about 6, so
	-- worn is 5.5, the falloff is 1/(1+5.5/0.6) = 0.10, and a charge's 110
	-- becomes 11. Raise ArmorFloor to 0.25 and the same charge lands 27.
	-- How hard the engine is told each impact hit, by name. The names come
	-- from the game's own hit reaction scale, ascending: Tickle, Unpleasant,
	-- Exhausting, MinorInjury, MajorInjury, Fatal.
	HitStrengthByTier        = {
		Walk   = "Tickle",
		Trot   = "MinorInjury",
		Gallop = "MajorInjury",
		Rear   = "MinorInjury",
		Charge = "MajorInjury",
	},

	-- Which set of spoken lines a victim answers each impact with. The rear
	-- and the charge have their own voice, separate from the collision sets
	-- and with their own switch.
	VictimBarkByTier         = {
		Walk   = "collision",
		Trot   = "collision",
		Gallop = "collision",
		Rear   = "rear",
		Charge = "collision",
	},

	-- Which impacts can make a victim lose patience and fight back. Only the
	-- shove: being reared on is not a patience problem.
	RetaliationByTier        = {
		Walk   = true,
		Trot   = false,
		Gallop = false,
		Rear   = false,
		Charge = false,
	},

	-- Which impacts charge the horse once for every person hit. A rear and a
	-- charge are one move that can land on several people at once, and are
	-- charged once for the move instead.
	StaminaPerVictimByTier   = {
		Walk   = true,
		Trot   = true,
		Gallop = true,
		Rear   = false,
		Charge = false,
	},

	-- How long a victim is closed to further impacts, in milliseconds, for an
	-- impact that is one deliberate move rather than a pass of the horse. Only
	-- the charge has one; every other tier is debounced by HitMinIntervalMs.
	VictimLockMsByTier       = { Charge = 2600 },

	-- How low a victim's head must be, as a fraction of how high they carry it
	-- standing, before the mod treats them as flat on the ground and refuses
	-- to start an animation on them.
	--
	-- Measured, not chosen. Every reading taken of a body lying flat is 0.04
	-- or 0.10 of its standing height; every reading of one that has begun to
	-- get up is 0.17 or more. This sits between them.
	--
	-- Raise it and a victim is refused further into their get-up; lower it and
	-- a reaction can start on a body still on the ground, which snaps them
	-- upright into it.
	VictimFlatFraction       = 0.15,

	-- What a tier does to the victim's body.
	--
	-- "stagger" and "knockdown" play an animation and nothing else. "fall"
	-- plays an animation whose own timing hands the body to physics partway
	-- through, and is the only one that restores a victim's facing and gives
	-- them their activity back afterwards. "ragdoll" drops them at the moment
	-- of contact and this mod drives the throw.
	-- Impact audio, one layer list per tier. Each layer is
	-- { event, delay in milliseconds, volume, optional pitch }.
	ImpactSoundByTier        = {
		-- Movement foley rather than an impact: a shove is a scuff and a
		-- stumble, spread out so it does not read as one hit.
		Walk   = { { "f_n_mat_foleyal_cl", 0 },
		           { "hs_hp_soil", 4 },
		           { "f_n_mat_foleyal_cl", 5 },
		           { "f_n_mat_foleyam_cl", 8 },
		           { "f_bodyfall1", 12 },
		           { "f_n_mat_foleyam_cl", 13 },
		           { "f_bodyfall1", 18 } },

		-- A trot puts someone on the ground, so the blunt impact leads,
		-- doubled with the second copy taken back a fraction to shade it
		-- down. Both copies sit back from the ear: at zero distance the lead
		-- impact is louder from the saddle than a trot deserves.
		Trot   = { { "body", 0, 1.3 },
		           { "body", 0, 1.65 },
		           { "f_bodyfall1", 0, 1.5 } },

		-- A gallop stacks four different blunt impacts rather than repeats of
		-- one, so it reads as a collision instead of a flam, with the body
		-- settling underneath. Every impact layer is a token, so a mailed
		-- guard and a peasant in cloth sound different on all four.
		--
		-- No hoofstep. `hs_hp_soil` is `hoofsteps_player`, the same family as
		-- `a_o_jump_landing`, and those events ignore position: it played at a
		-- fixed full level under every other layer and was the loudest thing
		-- in the mix with no way down. The horse is already making that noise
		-- at a gallop on its own.
		Gallop = { { "body", 0, 0.5 },
		           { "n_lu_log_ground", 0, 1.0 },
		           { "body_armed", 0, 0.85 },
		           { "blunt", 0, 1.0 },
		           { "face_armed", 0, 0.9 },
		           { "f_bodyfall1", 0, 0.7 } },

		-- The rear leads with the horse's own landing, because that is what
		-- the victim is hit by.
		Rear   = { { "a_o_jump_landing", 0, 0, 0.6 },
		           { "hs_hp_soil", 2, 0.6 },
		           { "body", 0, 1.6 },
		           { "blunt", 0, 2.0 },
		           { "f_bodyfall1", 0, 1.3 } },

		Charge = { { "body", 0, 0.6 },
		           { "hs_hp_soil", 3, 0.8 },
		           { "body_armed", 0, 0.9 },
		           { "blunt", 0, 1.0 },
		           { "hs_hp_soil", 6, 0.7 },
		           { "face_armed", 0, 0.9 },
		           { "f_bodyfall1", 0, 0.7 } },
	},

	HorseVocal               = true,
	HorseVocalCooldownMs     = 1500,

	-- Horse vocalization on impact. Triggered on the horse entity, not the
	-- victim. Rear and Charge are already covered by animation-driven sounds.
	HorseVocalByTier         = {
		Walk   = { "a_o_horse_excited1", 0, 0, 1 },
		Trot   = { "a_o_horse_excited1", 0, 0, 1 },
		Gallop = { "a_o_horse_whinny1",  0, 0, 1 },
		Rear   = { "", 0, 0, 1 },
		Charge = { "", 0, 0, 1 },
	},

	HorseVocalRankByTier     = {
		Walk = 1, Trot = 2, Gallop = 3, Rear = 2, Charge = 3,
	},

	-- Henry's own grunt as the collision goes through him, as
	-- { event, delay in milliseconds, pitch, volume }.
	RiderVocalByTier         = {
		Walk   = { "", 140, 0, 1 },
		Trot   = { "v_henry_hit_soft", 140, 0, 1 },
		Gallop = { "v_henry_hit_heavy", 90, 0, 1 },
		Rear   = { "v_henry_hit_soft", 140, 0, 1 },
		Charge = { "v_henry_hit_heavy", 90, 0, 1 },
	},

	-- Where each tier's grunt sits in the shared voice gate, so a heavier
	-- impact is never talked over by a lighter one.
	RiderVocalRankByTier     = {
		Walk = 1, Trot = 2, Gallop = 3, Rear = 2, Charge = 3,
	},

	-- How hard each tier kicks the camera. A tier with no entry does not
	-- shake it at all, which is why the walk is absent.
	CameraShakeByTier        = {
		Trot = 0.6, Gallop = 1.0, Rear = 0.8, Charge = 1.2,
	},

	-- How much each tier blurs the view, and how long that lasts. They are
	-- two tables rather than one pair per tier because they came apart in
	-- tuning: a trot wanted the strength kept and the length cut.
	RiderBlurByTier          = {
		Trot = 0.7, Gallop = 1.0, Rear = 0.6, Charge = 1.1,
	},

	RiderBlurLengthByTier    = {
		Trot = 0.3, Gallop = 1.0, Rear = 0.4, Charge = 1.1,
	},

	-- How much dust each tier raises where the victim is struck.
	ImpactDustScaleByTier    = {
		Trot = 0, Gallop = 0.09, Rear = 0.6, Charge = 0.10,
	},

	-- The marks left on the victim. Dirt is where they landed, blood is what
	-- the impact opened.
	VictimDirtByTier         = {
		Trot = 0.35, Gallop = 0.60, Rear = 0.35, Charge = 0.60,
	},

	VictimBloodByTier        = {
		Trot = 0.15, Gallop = 0.45, Rear = 0.15, Charge = 0.45,
	},

	ReactionByTier           = {
		Walk   = "stagger",
		Trot   = "fall",
		Gallop = "ragdoll",
		Rear   = "fall",   -- a rear is a trot-class blow, not a gallop's
		Charge = "ragdoll",
	},

	-- How hard each ragdoll tier throws. Only the tiers set to "ragdoll" above
	-- appear: the others hand the body to physics through the animation and
	-- this mod never pushes them, so a figure for them would do nothing.
	--
	-- The charge is below a gallop rather than above it. The horse is still
	-- driving forward when the victim goes down in front of it, so its own
	-- collider shoves the ragdoll on top of whatever this applies.
	ThrowByTier              = {
		Gallop = 1.0,
		Charge = 0.7,
	},

	ImpactDamageByTier       = {
		Walk   = 0,     -- a walk staggers, it does not wound
		Trot   = 18,
		Gallop = 95,
		Rear   = 60,    -- hooves coming down, standing still
		Charge = 110,   -- the heaviest thing the mod does
	},

	-- Hand back whatever the engine charged for the collision, so the figures
	-- above are the entire cost of an impact rather than an addition to one
	-- nobody can read. This is also what keeps a death the mod's to attribute,
	-- which is what CollisionIsCrime depends on.
	ImpactDamageOwnsTheHit   = true,

	ImpactDamageReclaimCeiling = 60,   -- never give back more than this at once

	ImpactDamageArmorScale   = 0.6,   -- smash_def past the ignored figure that halves damage
	ImpactDamageArmorCurve   = 1.0,   -- >1 armor bites sooner, <1 flattens
	ImpactDamageArmorFloor   = 0.0,   -- least armor can reduce an impact to
	ImpactDamageIgnoredArmor = 0.5,   -- smash_def that is clothing, not armor
	ImpactDamageVariance     = 0.15,  -- spread either side of the tier figure
	ImpactDamageDelayMs      = 600,   -- only for a test subject's health being
	                                  -- put back; a real impact waits for the
	                                  -- body to stop moving instead

	-- The rider's own half of a gallop impact. A collision costs stamina and
	-- costs the victim health, and in hardcore mode neither is visible from
	-- the saddle, so a kick to the camera is the only part of it the player
	-- feels. Gallop only: a trot knockdown should stay a shove.
	--
	-- Angle is degrees of rotation and shift is meters of displacement, both
	-- applied on all three axes. Frequency is the period vanilla's own shakes
	-- pass, which is a small number: `SinglePlayer:ViewShake` uses 1/20 and
	-- the CameraShake entity defaults to 0.5. Randomness varies each shake so
	-- repeated collisions do not feel canned.
	CameraShake              = true,
	CameraShakeAngle         = 4.0,
	CameraShakeShift         = 0.08,
	CameraShakeDurationSec   = 0.5,
	CameraShakeFrequency     = 0.05,
	CameraShakeRandomness    = 0.5,

	-- What a gallop impact does to the rider's own view in first person. The
	-- dust the collision throws up is on the ground below the field of view at
	-- speed, so a first person rider sees none of it; this is their share.
	--
	-- A blur pulse, because the engine has no dust or dirt lens overlay and
	-- this is the same cue the game uses for taking a hit. Amount is how heavy
	-- the blur starts, and it decays to nothing over RiderBlurMs.
	--
	-- Off in third person by default, where the real effect is already
	-- visible. The views are told apart by how far the camera sits from the
	-- player, which is under a meter in first person and several in third.
	RiderBlur                = true,
	RiderBlurAmount          = 1.0,
	RiderBlurHoldMs          = 260,
	RiderBlurChroma          = 0.2,
	RiderBlurMs              = 480,
	RiderBlurSteps           = 7,
	RiderBlurFirstPersonOnly = true,
	RiderBlurFirstPersonRange = 1.5,

	-- What the rider's own Horsemanship is worth. The game's `horse_riding`
	-- skill runs 0 to 20; a rider at 0 is unaffected and the figures below are
	-- what the skill is worth at the top of that scale.
	--
	-- The stamina cost is multiplied, not discounted, and the range is wide on
	-- purpose. At level 0 a single gallop impact very nearly empties the
	-- horse; at 20 it takes four or five armored guards, or about nine
	-- villagers. The ceiling is set against guards rather than villagers
	-- because guards are what the figure was judged on, and it stays low
	-- enough that a rider never becomes a cartoon. It runs linearly between
	-- the two, so every level is worth the same.
	--
	-- Seat is the chance of staying mounted when the horse is finally spent.
	-- The horse still stops either way; a rider who can ride does not always
	-- come off with it.
	Horsemanship             = true,
	HorsemanshipSkill        = "horse_riding",
	HorsemanshipMaxLevel     = 20,
	HorsemanshipStaminaWorst = 10.0,  -- the cost multiplier at level 0
	HorsemanshipStaminaBest  = 1.2,   -- and at HorsemanshipMaxLevel
	HorsemanshipSeatChance   = 0.6,   -- chance of keeping the saddle, at the top

	-- What the horse's own barding is worth. Barding is the horse's armor and
	-- is separate from its tack, so a saddle and shoes count for nothing here.
	-- Read from the total smash_def of what the horse is wearing, which is what
	-- separates a cloth caparison from a plated head and neck.
	--
	-- Three flat effects rather than one multiplier, each scaling from nothing
	-- on a bare horse to its figure below on a full set. Nothing about the
	-- rider enters this: barding does not scale with Horsemanship.
	Barding                  = true,
	BardingFullSmashDef      = 1.45,  -- smash_def counted as a full set, measured
	BardingStaminaRelief     = 0.25,  -- how much less stamina an impact costs
	BardingDamageBonus       = 0.15,  -- how much harder a barded horse hits
	-- What barding adds to the knockdown force, in five steps. No barding adds
	-- nothing, a fifth of a full set adds a fifth of the bonus, up to a full
	-- set adding all of it. Each row is
	--
	--     { coverage at or above, added to Knockback, added to Uplift }
	--
	-- and the highest row the horse qualifies for wins. At the top that is 5.0
	-- on a Knockback of 50 and 3.0 on an Uplift of 30, so ten per cent more of
	-- both.
	BardingForceSteps        = {
		{ 0.0, 0.0, 0.0 },
		{ 0.2, 1.0, 0.6 },
		{ 0.4, 2.0, 1.2 },
		{ 0.6, 3.0, 1.8 },
		{ 0.8, 4.0, 2.4 },
		{ 1.0, 5.0, 3.0 }
	},

	-- What happens to the horse after it dumps a rider who rode it into people
	-- until it was spent. Sometimes it wants nothing more to do with them and
	-- leaves, using its own AI: its combat subbrain flees wherever, so it only
	-- has to be given something to flee from.
	--
	-- A chance rather than a certainty. A horse that always bolts is a
	-- punishment; one that sometimes bolts is a horse.
	HorseBoltsWhenSpent      = true,
	HorseBoltChance          = 0.4,
	HorseBoltRestoreMs       = 3000,  -- health is given back this long after

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

	-- The master level control, in meters, added to every layer of every
	-- tier. Higher is quieter. The per-layer distances below set the balance
	-- between the layers; this sets how loud that balance is as a whole.
	--
	-- It exists because the listener follows the camera. In first person the
	-- ear is on top of the victim and hears the mix at close to full level; a
	-- third-person camera starts several meters further back and hears the
	-- same mix much quieter, which is why a mix tuned in one view is wrong in
	-- the other. The tuning here is done in first person, the loudest case.
	ImpactSoundDistance      = 2.0,

	-- A shove disturbs someone's clothing rather than striking them, so the
	-- walk tier carries no impact at all: two cloth foleys and a body
	-- settling, each doubled because those samples are very quiet, over a
	-- single hoofstep.

	-- A trot puts someone on the ground, so the blunt impact leads, doubled
	-- with the second copy taken back a fraction to shade it down. Both
	-- copies sit back from the ear: at zero distance the lead impact is
	-- louder from the saddle than a trot deserves.

	-- A gallop stacks four different blunt impacts rather than repeats of one,
	-- so it reads as a collision instead of a flam, with the body settling
	-- underneath. Every impact layer is a token, so a mailed guard and a
	-- peasant in cloth sound different on all four.
	--
	-- No hoofstep. `hs_hp_soil` is `hoofsteps_player`, the same family as
	-- `a_o_jump_landing`, and those events ignore position: it played at a
	-- fixed full level under every other layer and was the loudest thing in
	-- the mix with no way down. The horse is already making that noise at a
	-- gallop on its own.

	-- The occasional injury, gallop only. A foley event, so unlike
	-- `c_special_bone_crack1` it can be quietened; that one is 2D and came out
	-- at cartoon volume whatever was done to it.
	ImpactSoundCrack         = { "f_bodyfall_leg_break", 20, 6 },
	ImpactSoundCrackChance   = 0.12,

	-- Henry's own grunt as the collision goes through him. The game authors
	-- him three severities of taking a hit and each tier names one, so a shove
	-- at a walk and a body taken at a gallop do not sound alike.
	--
	-- These are sound events, not dialogue, which is why they are short: the
	-- mod names the exact event instead of asking the dialog system for a line
	-- and being given a speech.
	--
	-- Read as an impact layer: `{ trigger, delayMs, distance, chance }`.
	-- `distance` is the only volume control the game has, so raise it to push
	-- the grunt back. `chance` below 1 makes it occasional. A trigger of `""`
	-- silences that one tier and leaves the others alone.
	--
	-- The three triggers available are `v_henry_hit_soft`,
	-- `v_henry_hit_medium` and `v_henry_hit_heavy`.
	RiderVocal               = true,

	-- How long the rider stays quiet after grunting. Riding into a group lands
	-- several collisions inside a second and one grunt each reads as broken
	-- audio rather than as a man being jolted. A harder impact is still let
	-- through, so a gallop is never silenced by the walk shove before it.
	RiderVocalCooldownMs     = 1500,

	-- Henry saying something about the impact, rather than only grunting. The
	-- lines are vanilla's, addressed by `alias` so the mod names one topic
	-- instead of a whole bark set; `Bark.lua` carries the list and why these
	-- ones. Every impact draws from the same pool regardless of tier.
	--
	-- Words and breath share one gate, because both come out of Henry and two
	-- at once is a defect. So the chance below is how often an impact produces a
	-- line *instead of* a grunt, and a line holds the grunt off for its own
	-- cooldown, which is longer because a line takes longer to say.
	RiderBark                = false,
	RiderBarkChance          = 0.35,
	RiderBarkCooldownMs      = 5000,
	RiderBarkKill            = true,

	-- Henry's own line gets its own priority rather than sharing the victims'.
	-- Requests register in a shared array which the dialog system sorts
	-- descending, and a request below the top is discarded with no error, so at
	-- the default of zero a line loses every contest it enters. Both aliases
	-- that were confirmed audible in testing were sent at 50, so that is the
	-- shipped value: it makes the tested configuration the default one.
	RiderBarkPriority        = 50,

	-- How long a victim is left alone after being hit. The knockdown tiers
	-- read the victim's own state rather than counting. The victim is busy
	-- while an animation the mod started or a ragdoll owns their body, and
	-- hittable again once HitReadySettleMs has passed with neither. Any busy
	-- state restarts that window, because a trot victim is briefly idle
	-- between the fall clip ending and the ragdoll taking over.
	-- HitReadyCeilingMs releases a victim who is never seen busy at all.
	--
	-- The settle was 2000 and the ceiling 12000, which put roughly nine
	-- seconds between a gallop and being able to hit the same person again:
	-- their reaction, then two more seconds of standing there. The engine's
	-- own collision keeps firing through all of it, so a second impact gave a
	-- vanilla bark, no feedback from the mod, and the horse wedged inside the
	-- victim. That is what "muddy and unresponsive" was.
	--
	-- Zero is worse in the other direction. At a 1500 ceiling a victim was
	-- released while still flat, and trotting a downed guard rotated him along
	-- the ground, which looks wrong. The ceiling has to outlast a knockdown.
	--
	-- So the settle is short enough to be immediate once they are up, and the
	-- ceiling long enough that it never releases someone mid-knockdown.
	-- Only the tiers that play an animation wait. A gallop ragdolls, which is
	-- pure physics with no pose to start from, so it can land at any stage of a
	-- victim's recovery; gating it meant the mod declined the impact while the
	-- engine's own collision happened anyway, which is the vanilla result of
	-- getting wedged in someone with no reaction and a bark.
	-- One contact is one impact. Detection runs every 33 ms and a galloping
	-- horse clears a person in about 150 ms, so a single pass is four or five
	-- ticks and each is a collision by the loop's reckoning. Long enough to
	-- outlast a pass, far short of the time it takes to turn around and make a
	-- second deliberate run.
	HitMinIntervalMs         = 700,



	-- The dust a body throws up where it lands. Nothing at a walk, where
	-- nobody falls. Scale is the size of the effect, so a gallop kicks up
	-- more than a trot; 0 switches a tier off.
	--
	-- The dust waits for the victim to land rather than firing on contact,
	-- because at a gallop the two are several meters apart and the point of
	-- contact is behind the rider before it renders. The victim's height is
	-- position is sampled every ImpactDustSampleMs and the dust goes out on
	-- the first sample they have moved less than ImpactDustSettleDistance
	-- meters between, giving up after ImpactDustMaxSamples and spawning it
	-- anyway. Distance rather than height: a galloped victim is thrown almost
	-- flat, so watching height alone fires at the point of collision.
	--
	-- The effect name is a particle library node, from the game's own
	-- Libs/Particles. `collisions.destructibles.arrow_soil` is the soil an
	-- arrow kicks out of the ground and is the closest thing the game has to
	-- a body landing on dirt. `WH_Particels.other.gravel` and
	-- `WH_Particels.dust.sweep` are the alternatives worth trying.
	ImpactDust               = true,
	ImpactDustEffect         = "WH_Particels.other.explosion_dust",
	ImpactDustHeight         = 0.05,
	ImpactDustSampleMs       = 50,
	ImpactDustFallVz         = -0.5,
	ImpactDustLandVz         = -0.15,
	ImpactDustFallWaitSamples = 8,
	ImpactDustMaxSamples     = 30,

	-- What a victim looks like afterwards. Someone ridden down at a gallop
	-- otherwise stands back up immaculate. Dirt covers everything they are
	-- wearing; blood goes on the side of the body the horse struck. Both are
	-- amounts between 0 and 1 and both accumulate, so a man ridden down
	-- repeatedly gets steadily filthier. Setting either to 0 switches that
	-- half off. Nothing is applied at a walk, where nobody hits the ground.
	VictimMarks              = true,

	-- Switches.
	CollisionIsCrime         = true,  -- riding someone down is a crime at trot
	                                  -- and gallop; never at a walk
	ReleaseAnimationMovement = true,  -- keeps staggering victims out of walls
	ReleaseMovementAttempts  = 4,     -- repeated, since a blend can undo it
	ReleaseMovementGapMs     = 80,    -- how far apart the attempts are
	ReplanAfterReaction      = true,  -- sends them back to their stall or
	                                  -- whatever they were leaning on
	SuppressStaggerInCombat  = true,  -- skip the stagger during a fight

	-- Spoken reactions. Every line is vanilla, spoken by the character's own
	-- voice actor, chosen by naming a bark set. Nothing new ships.
	--
	-- Deliberately not the sets vanilla already fires on contact, the "Look
	-- where you're going!" lines, which the player hears anyway. These are
	-- moments the game has no line for: a horse shoving somebody, rearing in
	-- their face, or leaving them in the road.
	--
	-- A character whose voice never recorded a set simply stays silent, with
	-- no error, exactly as in vanilla, so this is safe on every NPC.
	--
	-- A knockdown speaks twice: a wordless cry at the moment of impact, graded
	-- by how hard the hit was, and then actual words once the victim is back
	-- on their feet. Each draws from a weighted pool holding both the mod's
	-- own finds and vanilla's collision lines, so the same impact does not
	-- produce the same sentence every time.
	Barks                    = true,  -- the feature as a whole
	CollisionBarks           = true,  -- victims and bystanders of an impact
	RearBarks                = true,  -- whoever a rear is aimed at
	RiderBarks               = true,  -- Henry's own remark over a body
	BarkCooldownMs           = 3000,  -- per speaker, so a crowd is not a choir.
	                                  -- Keep at or below HitCooldownMs: a
	                                  -- longer value silences whole impacts,
	                                  -- it does not just thin them out
	BarkSuppressMs           = 2500,  -- how long vanilla's own bark is held
	                                  -- off so the mod's line is not talked over
	BarkGapMs                = 2500,  -- least silence between two lines from
	                                  -- the same speaker, so a recovery line
	                                  -- cannot cut off the cry of pain
	BarkOnRecovery           = true,  -- victims say something once they are
	                                  -- back on their feet, rather than
	                                  -- walking off without a word

	-- Makes a victim the horse strikes immortal for the instant of contact, so
	-- the engine's own collision damage cannot kill them and this mod is the
	-- only thing that can. Lifted the moment the mod deals its damage. Without
	-- it, a victim the trample happens to kill is charged to you as murder even
	-- with CollisionIsCrime off.
	ShieldVictimFromEngineDamage = true,
	ShieldWindowMs           = 6000,  -- crash backstop only; the damage call lifts it

	WalkStagger              = true,  -- false gives vanilla behavior at a walk
	ProtectMutt              = true,  -- whether your dog is immune
	                                  -- around on his back

	-- Characters the game will not let you attack -- Captain Bernard, the Lord
	-- of Leipa and anyone else a quest is protecting -- take no damage from a
	-- collision. They are still knocked down, because that is the game's own
	-- physics and not something this mod applies, but the impact costs them no
	-- health. Turning this off lets a horse kill a quest-critical character.
	ProtectStoryCharacters   = true,
	LogTelemetry             = true,  -- diagnostics in kcd.log

	-- Names the reason a nearby NPC produced no reaction. Writes a line for
	-- every entity near the horse, including doors and audio areas, which is
	-- thousands per session. Only useful while investigating why a specific
	-- impact did nothing. `build.ps1` refuses a release build with this on.
	DiagnoseMisses           = false,

	-- ======================================================================
	-- Everything below is exposed for completeness. It was tuned by riding at
	-- people repeatedly and the shipped values are the ones that felt right,
	-- so treat each group's warning as the real guidance rather than an
	-- invitation. A key removed from this file falls back to its built-in
	-- default, so deleting a line is always a safe way back.
	-- ======================================================================

	-- Detection and scoring. The safest group to experiment with: these decide
	-- what counts as a hit and how fast the horse is judged to have been going,
	-- so a wrong value shows up as impacts that do not land or land when you
	-- rode past, which is obvious and harmless.
	HitRadius                = 2.5,   -- broad-phase sphere around the horse
	HorseMaxVerticalDiff     = 2.35,  -- height difference above which a hit is
	                                  -- ignored, so you do not strike someone
	                                  -- on a floor above or below you
	HorseAirborneVz          = 2.5,   -- upward speed counted as a jump
	MaxImpactSpeed           = 11.0,  -- ceiling on the speed a hit is scored at
	ImpactSpeedSamples       = 9,     -- ticks of speed history a hit is scored
	                                  -- from, which is what stops a single
	                                  -- stuttering frame deciding the tier
	SweepMultiplier          = 0.50,  -- how far ahead to sweep per m/s
	MaxSweepExtra            = 0.35,  -- cap on that forward sweep, in meters
	TickSeconds              = 0.033, -- detection interval

	-- Ragdoll motion after the throw. Raise the risk here: these shape how a
	-- thrown body travels and comes to rest, and the settled look at a gallop
	-- came out of tuning them together. Changing one alone usually reads as a
	-- body that slides, floats or stops dead.
	ImpulseDelayMs           = 50,    -- wait before the ragdoll impulse
	LateralImpulse           = 0.0,   -- sideways share of the impulse; the
	                                  -- throw direction is the engine's, and
	                                  -- adding to it fought that
	RagdollBrake             = true,  -- whether a thrown body is braked at all
	RagdollBrakeKeepArmored  = 0.45,  -- fraction of its speed a victim in full
	                                  -- armor keeps
	RagdollBrakeKeepUnarmored = 1.0,  -- and an unarmored one
	RagdollBrakeArmorScaleArmored = 0.35,
	RagdollBrakeArmorScaleUnarmored = 1.26,
	RagdollAirDamping        = 8.0,   -- damping at full strength in the air
	RagdollDampContactRun    = 3,     -- samples of contact in a row before the
	                                  -- body counts as down
	RagdollDampRampSamples   = 8,     -- samples over which damping ramps up
	RagdollSpeedSoftCap      = 4.0,   -- speed past which drag begins
	RagdollSpeedSoftCapSpan  = 3.0,   -- how far above it drag reaches full

	-- The rear and the charge. Timings measured against the animation, so a
	-- value out of step with the clip shows as a strike that misses or lands
	-- after the horse has come down.
	RearImpactSpeed          = 6.0,   -- the speed a rear is scored at, since
	                                  -- the horse is barely moving
	RearAnimSpeed            = 1.0,   -- how fast the rear plays
	RearChargeLungePeakMin   = 3.0,   -- top speed a lunge must reach to count
	RearChargeLungeSpentAt   = 0.5,   -- fraction of its peak at which the
	                                  -- lunge is treated as spent
	RearChargeStrikeBehind   = 0.2,   -- how far behind the horse still counts
	RearChargeStrikeMs       = 1600,  -- how long the strike sweeps for
	RearChargeStrikePollMs   = 50,    -- how often it sweeps
	                                  -- further hits
	RearChargeWaitMs         = 400,   -- when the mod starts watching for the
	                                  -- rear to end
	RearChargeWaitPollMs     = 30,    -- how often it looks
	RearChargeWaitCeilingMs  = 3000,  -- push anyway by this point

	-- How a spoken line is submitted to the dialog system. The system runs an
	-- auction and silently discards a losing request, so these decide whether
	-- a line is heard at all rather than how it sounds. Documented in full in
	-- docs/TECHNICAL_DETAILS.md.
	BarkPriority             = 0,     -- rank in the dialog system's auction
	BarkCanBeDelayed         = false, -- queue a line that loses, instead of
	                                  -- dropping it
	BarkOverrideSuppress     = false, -- ignore a suppressMonologs context
	BarkInCombat             = false, -- whether a victim already fighting still
	                                  -- remarks on being ridden into; vanilla's
	                                  -- judgment is that they do not

	-- Internals. These name files and animation tags the mod ships, or switch
	-- off machinery other features depend on. There is no useful value other
	-- than the one here; they are listed so nothing is hidden.
	RearActionMap            = "hcm_rear",
	RearActionMapFile        = "Libs/Config/hcm_actionmaps.xml",
	SettleFragTag            = "hcm_settle",
	SendHitReaction          = true,  -- posting this is what makes vanilla's
	                                  -- own barks fire on an impact
	TraceRecovery            = false  -- times every animation state during a
	                                  -- recovery; diagnostic only

}
