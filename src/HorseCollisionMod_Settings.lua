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
	SpeedGallop              = 8.5,   -- thrown

	-- Whether maneuvers (Lean, Rear, Charge) require Horsemanship perks.
	RequirePerks             = true,

	-- Automatically grant the maneuvers' Horsemanship perks to Henry on load.
	AutoGrantPerks           = false,

	-- Whether to display on-screen tutorials for maneuvers (Rear, Charge, Lean).
	ShowTutorials            = true,

	-- What counts as contact. Lower these if NPCs react when you ride past.
	HorseFrontReach          = 1.05,  -- meters ahead of the horse
	HorseHalfWidth           = 0.70,  -- meters to either side
	HorseRearReach           = 0.20,  -- meters behind

	-- The force a thrown victim is pushed with, at the gallop and the charge.
	Knockback                = 50.0,  -- horizontal, higher throws further
	Uplift                   = 30.0,  -- vertical, higher throws upward

	-- How a thrown body settles once it is down. The ceiling it is held under
	-- in the air, and the brake or launch it starts with, are per tier in
	-- `ThrowProfileByTier` below.
	RagdollDamping           = 5.0,   -- higher stops a thrown body sooner
	RagdollMinEnergy         = 1.0,   -- higher puts it to rest sooner
	RagdollDampPollMs        = 100,   -- how often to look at a thrown body
	RagdollDampSettleSpeed   = 0.5,   -- speed it must fall under before damping
	RagdollDampFloorMs       = 200,   -- never damp before this, mid-launch
	RagdollDampCeilingMs     = 6000,  -- damp regardless by this point

	-- Waiting for a victim to be back on their feet.
	RisePollMs                = 160,   -- how often to look
	RiseCeilingMs             = 15000, -- how long before the wait is given up

	-- When a ragdolled body gets up: it must lie still for RagdollStillDuration
	-- seconds, moving slower than RagdollStillSpeedThreshold. These are the
	-- engine's console variables `wh_rd_StillDuration` and
	-- `wh_rd_StillSpeedThreshold`, written on every load over any value set
	-- there.
	RagdollStillDuration        = 0.8,
	RagdollStillSpeedThreshold  = 0.4,

	-- Stamina. Every figure here is a share of the horse's own maximum
	-- stamina, not a point value, because that pool differs from horse to
	-- horse: 0.20 means a fifth of whatever this horse has.
	--
	-- One share per tier, and every tier is charged through the same path, so
	-- the rider's Horsemanship, the horse's barding and the combat surcharge
	-- all apply to a rear and a charge exactly as they do to a gallop:
	--
	--     cost = maxStamina
	--          * (tier share + combat + victim armor - barding)
	--          * Horsemanship
	--
	-- The three situational figures are added to the tier's share rather than
	-- multiplied with it, so the worst an impact can cost before Horsemanship
	-- is the sum of the figures below and can be read straight off them.
	StaminaShareByTier       = {
		Walk   = 0.00,  -- a shove costs the horse nothing
		Trot   = 0.13,  -- about eight back to back at full Horsemanship
		Gallop = 0.20,  -- five back to back, one at level 0 Horsemanship
		Rear   = 0.20,  -- matches the gallop; rationed by its cooldown
		Charge = 0.20,  -- matches the gallop; once per lunge, not per victim
	},

	CombatStaminaAdd         = 0.13,  -- 0 removes the combat surcharge
	ThrowRiderOnStaminaEmpty = true,  -- false still drains stamina

	-- How much what a target is wearing changes the impact. Weight is the
	-- sum of their armor, from the game's own item tables: a villager is
	-- around 5, a mail-wearing guard around 47.
	--
	-- The impulse multiplier is exactly 1.0 at ArmorReferenceWeight, and an
	-- exponent of 0 switches that half off. The stamina surcharge has its own
	-- anchor: it reaches MaxArmorStaminaAdd at ArmorStaminaFullWeight, the
	-- weight of a full set of armor, so a villager in clothes pays almost
	-- nothing.
	ArmorReferenceWeight     = 8.0,   -- the weight whose multiplier is 1.0
	ArmorImpulseExponent     = 0.5,   -- higher means armor plants them harder
	MinArmorImpulse          = 0.35,  -- a knight is never immovable
	MaxArmorImpulse          = 1.5,   -- nor is a naked peasant weightless
	ArmorStaminaFullWeight   = 50.0,  -- armor weight counted as a full set
	ArmorStaminaExponent     = 1.0,   -- higher means light armor costs less
	MaxArmorStaminaAdd       = 0.05,  -- the most an armored victim can add

	-- Keeps a victim out of vanilla's auto-cure daycycle after an impact,
	-- until their health is back over AutoCureHealthLimit.
	SuppressAutoCureSec      = 30,   -- how often it is rechecked; 0 turns it off
	AutoCureHealthLimit      = 40.0,  -- exemption held until health is back over this

	-- Which key does what. Any of r, q, e, f, y, u, o and h can be used; the
	-- mod's action map declares these eight and no others. The lean takes q
	-- and e and the rears take r and f, none of which does anything in vanilla
	-- while mounted.
	RearChargeKey            = "r",   -- rear, then drive forward
	RearOnlyKey              = "f",   -- rear on the spot
	Rear                     = true,
	RearIdleOnly             = true,  -- also require the horse's idle state
	RearMaxSpeed             = 0.15,  -- horizontal m/s; above this it slides
	RearCooldownMs           = 7500,  -- after a rear lands
	ChargeCooldownMs         = 12500, -- after a charge lands
	MoveCooldownIcons        = true,  -- show an icon while either runs
	RearFragTag              = "hcm_rear_charge", -- rear, then drive forward
	RearOnlyFragTag          = "hcm_rear",       -- the second key rears on the spot
	ImpactDustEffectRear     = "collisions.destructibles.arrow_soil", -- a rear's dust

	-- The charge rears in place and is then pushed forward physically. It is
	-- its own tier, with its own damage, sound, dust, camera shake and view
	-- blur. It knocks down everyone in a corridor in front of the horse, with
	-- no cap: a crowd cannot shield each other by standing close.
	RearChargeStrikes        = true,  -- whether the charge knocks people down
	RearChargeStrikeReach    = 1.8,   -- how far ahead it reaches
	RearChargeStrikeWidth    = 0.9,   -- how wide, either side
	-- The speed a charge is scored and thrown at. It is RearChargeImpulse over
	-- the horse's mass, 6000 on about 480 kg, less the share the lift takes;
	-- change it with RearChargeImpulse. How far a charge throws is
	-- RearChargeThrow below, not this figure.
	RearChargeImpactSpeed    = 12.3,  -- the speed a charge is resolved at

	-- How far a charge throws, and the only dial for it. The throw is the lunge
	-- speed above times the tier's transfer in `ThrowProfileByTier`, times this;
	-- at 1.0 a charge lands where a gallop lands.
	RearChargeThrow          = 0.6,   -- 1.0 throws like a gallop, 2.0 twice as far
	-- Bystanders a charge passes without striking are frightened and run.
	-- RearChargeFearReach is the 1.8 m strike reach plus one second of the
	-- slowest lunge, RearChargeLungePeakMin.
	RearChargeFear           = true,
	RearChargeFearReach      = 4.8,   -- the corridor plus a second of lunge
	RearChargeFearScreamPriority = 50, -- the rank the scream is sent at
	RearChargeImpulse        = 6000,  -- how hard the charge is pushed
	RearChargeLift           = 0.2,   -- how much of that is upward
	RearChargeWindowMs       = 2600,  -- how long a charge counts as a gallop
	RearStrikes              = true,  -- the rear on the spot hits who is in front
	RearStrikeMs             = 700,   -- when in the animation they land
	-- Leaning out to see past the horse's head, in first person. The camera
	-- travels out fast on LeanTravelAmplitude, then holds at LeanDistance on
	-- LeanHoldAmplitude, corrected every LeanPollMs when it drifts further than
	-- LeanDeadband. A lean ends on its own if the rider looks too far off the
	-- horse's line.
	Lean                     = true,
	LeanLeftKey              = "q",   -- q and e, the usual lean keys
	LeanRightKey             = "e",
	LeanDistance             = 0.65,  -- how far out the camera holds, in meters
	LeanForwardShare         = 0.35,  -- how much it also carries forward, 0 for none
	LeanTravelAmplitude      = 110.0,   -- higher gets out there faster
	LeanHoldAmplitude        = 3.0,   -- lower holds steadier once out
	LeanPollMs               = 30,    -- how often the hold is checked
	LeanDeadband             = 0.06,  -- meters off target before a correction
	LeanRunawayFactor        = 2.0,   -- end the lean this many times past target
	LeanMaxAngleDeg          = 45,    -- refuse a lean past this far off the horse's line
	LeanMaxPitchDeg          = 55,    -- and past this far up or down
	LeanSuppressShake        = true,  -- an impact does not shake the view mid lean
	LeanTurnLeadMs           = 200,   -- cancel this far ahead of a fast turn
	LeanHomeMs               = 220,    -- wait before another lean, while the camera returns
	LeanShakePeriod          = 40.0,  -- the camera shake period a lean is driven by
	LeanShakeSec             = 1.5,  -- long enough to outlast a held lean
	LeanReleaseSec           = 0.05,  -- a short shake, so it expires and comes home

	RearReach                = 2.5,   -- how far in front they reach
	RearArc                  = 70,    -- the arc in front that counts

	-- Bystanders near a rear who are not struck are frightened and run, in a
	-- band one stride past where the hooves reach, all round the horse.
	RearFear                 = true,
	RearFearReach            = 3.5,   -- a stride past the hooves, all round
	RearFearScreamPriority   = 50,    -- the rank the scream is sent at

	-- Losing patience. Barging the same person at a walk costs nobody
	-- anything, so this lets them run out of patience and swing back. The
	-- first shove is always free; each one after that rolls against a
	-- chance that grows with the count.
	--
	-- The fight it starts is deliberately not a crime: no fine, no guard
	-- summoned. Guards who actually witness the brawl still wade in. When the
	-- fight is over the victim's regard for Henry is put back the way it was.
	Retaliation              = true,
	RetaliationFreeBumps     = 1,     -- shoves tolerated before any chance
	RetaliationChanceStep    = 0.25,  -- added per shove beyond that
	RetaliationMaxChance     = 0.85,  -- the chance never exceeds this
	RetaliationMemorySec     = 45,    -- how long a victim stays annoyed
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

	-- The game lets only men into the fight branch. A woman runs and fetches a
	-- guard instead, on the same count and the same roll.
	WomenRaiseAlarm          = true,  -- women raise the alarm rather than fight

	-- What being ridden down costs, over and above the engine's own charge for
	-- the collision. The damage model is described above ImpactDamageByTier.
	ImpactDamage             = true,  -- charge the victim for the impact
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
	-- has its own set, with its own switch, RearBarks.
	VictimBarkByTier         = {
		Walk   = "collision",
		Trot   = "collision",
		Gallop = "collision",
		Rear   = "rear",
		Charge = "collision",
	},

	-- Which impacts can make a victim lose patience and fight back. Only the
	-- shove.
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
	-- to start an animation on them. Raise it and a victim is refused further
	-- into their get-up; lower it and a reaction can start on a body still on
	-- the ground.
	VictimFlatFraction       = 0.15,

	-- Impact audio, one layer list per tier. Each layer is
	-- { trigger, delay in milliseconds, distance in meters, chance }.
	--
	-- Distance is the volume control: a layer is played that much further
	-- away, from the same direction, so higher is quieter. It does nothing to
	-- `a_o_jump_landing` or `hs_hp_soil`, which ignore position; chance, from 0
	-- to 1, is how often a layer plays at all. `body`, `body_armed`,
	-- `face_armed` and `blunt` are replaced with the sample matching what the
	-- victim is wearing.
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

		-- The blunt impact leads, doubled with the second copy set a little
		-- further back.
		Trot   = { { "body", 0, 1.3 },
		           { "body", 0, 1.65 },
		           { "f_bodyfall1", 0, 1.5 } },

		-- Four different blunt impacts rather than repeats of one, with the body
		-- settling underneath.
		Gallop = { { "body", 0, 0.5 },
		           { "n_lu_log_ground", 0, 1.0 },
		           { "body_armed", 0, 0.85 },
		           { "blunt", 0, 1.0 },
		           { "face_armed", 0, 0.9 },
		           { "f_bodyfall1", 0, 0.7 } },

		-- Leads with the horse's own landing, on 60% of rears.
		Rear   = { { "a_o_jump_landing", 0, 0, 0.6 },
		           { "hs_hp_soil", 2, 0.6 },
		           { "body", 0, 1.6 },
		           { "blunt", 0, 2.0 },
		           { "f_bodyfall1", 0, 1.3 } },

		-- The gallop's impacts without the log layer, with hoofsteps.
		Charge = { { "body", 0, 0.6 },
		           { "hs_hp_soil", 3, 0.8 },
		           { "body_armed", 0, 0.9 },
		           { "blunt", 0, 1.0 },
		           { "hs_hp_soil", 6, 0.7 },
		           { "face_armed", 0, 0.9 },
		           { "f_bodyfall1", 0, 0.7 } },
	},

	HorseVocal               = true,  -- whether the horse makes a noise on impact
	HorseVocalCooldownMs     = 1500,  -- how long it stays quiet afterwards

	-- The horse's noise on impact, as an impact layer. Rear and Charge are
	-- empty because their animations carry their own.
	HorseVocalByTier         = {
		Walk   = { "a_o_horse_excited1", 0, 0, 1 },
		Trot   = { "a_o_horse_excited1", 0, 0, 1 },
		Gallop = { "a_o_horse_whinny1",  0, 0, 1 },
		Rear   = { "", 0, 0, 1 },
		Charge = { "", 0, 0, 1 },
	},

	-- Where each tier's horse noise sits in its cooldown, so a heavier impact
	-- is never silenced by a lighter one.
	HorseVocalRankByTier     = {
		Walk = 1, Trot = 2, Gallop = 3, Rear = 2, Charge = 3,
	},

	-- Henry's own grunt as the collision goes through him, as an impact layer.
	-- The triggers available are `v_henry_hit_soft`, `v_henry_hit_medium` and
	-- `v_henry_hit_heavy`; "" silences a tier.
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
	-- shake it at all; the walk has none.
	CameraShakeByTier        = {
		Trot = 0.6, Gallop = 1.0, Rear = 0.8, Charge = 1.2,
	},

	-- How much each tier blurs the view, and how long that lasts, as a share
	-- of RiderBlurAmount and RiderBlurMs.
	RiderBlurByTier          = {
		Trot = 0.7, Gallop = 1.0, Rear = 0.8, Charge = 1.1,
	},

	RiderBlurLengthByTier    = {
		Trot = 0.3, Gallop = 1.0, Rear = 0.4, Charge = 1.1,
	},

	-- How much dust each tier raises where the victim is struck.
	ImpactDustScaleByTier    = {
		Trot = 0, Gallop = 0.09, Rear = 0.6, Charge = 0.10,
	},

	-- The marks left on the victim. Dirt is where they landed, so a fall
	-- (trot, rear) leaves less than a throw (gallop, charge). Blood scales with
	-- each tier's damage against the gallop's.
	VictimDirtByTier         = {
		Trot = 0.35, Gallop = 0.60, Rear = 0.35, Charge = 0.60,
	},

	VictimBloodByTier        = {
		Trot = 0.07, Gallop = 0.45, Rear = 0.30, Charge = 0.48,
	},

	-- What a tier does to the victim's body. "stagger" plays an animation and
	-- nothing else. "fall" plays an animation that hands the body to physics
	-- partway through. "ragdoll" drops them at the moment of contact and this
	-- mod drives the throw.
	ReactionByTier           = {
		Walk   = "stagger",
		Trot   = "fall",
		Gallop = "ragdoll",
		Rear   = "fall",
		Charge = "ragdoll",
	},

	-- A scale on Knockback and Uplift for each ragdoll tier. Only the tiers
	-- set to "ragdoll" above appear. How far a charge throws is
	-- RearChargeThrow, not this.
	ThrowByTier              = {
		Gallop = 1.0,
		Charge = 1.0,
	},

	-- How each ragdoll tier throws a victim, and what holds the throw down.
	-- Every pair is blended across the victim's armor, so armor decides
	-- distance within a tier.
	--
	--   1. throw   -- the gallop brakes, keeping a fraction of the speed the
	--                 engine gave the body; the charge launches, at
	--                 RearChargeImpactSpeed * lungeTransfer * RearChargeThrow
	--   2. cap     -- the speed the body may not exceed in the air, held by
	--                 the drag. The charge's cap is its own launch speed
	--   3. settle  -- damping on the ground, the `RagdollDamp*` figures above,
	--                 which are the same for every tier
	ThrowProfileByTier       = {
		Gallop = {
			brakeKeepArmored   = 0.45,  -- fraction of its speed a victim in
			brakeKeepUnarmored = 1.0,   -- full mail keeps, and an unarmored one
			capArmored         = 2.5,   -- the cap for a victim in full mail
			capUnarmored       = 6.0,   -- and for an unarmored one
			dragArmored        = 20.0,  -- drag holding a victim in full mail
			dragUnarmored      = 4.0,   -- and an unarmored one
		},

		Charge = {
			-- The share of the lunge's speed the victim leaves with. These
			-- reproduce the gallop's caps off a 12.3 m/s lunge, so a charge at
			-- RearChargeThrow 1.0 throws like a gallop.
			lungeTransferArmored   = 0.20,  -- 2.5 / 12.3, a victim in mail
			lungeTransferUnarmored = 0.49,  -- 6.0 / 12.3, an unarmored one
			dragArmored            = 20.0,  -- the gallop's drag unchanged
			dragUnarmored          = 4.0,
		},
	},

	-- What a collision is worth, before armor, against an NPC's 100 health.
	--
	-- Clothing is ignored: ImpactDamageIgnoredArmor of smash_def does not count
	-- as armor. Past it a victim takes half the tier's damage at
	-- ImpactDamageArmorScale, a third at twice it, and so on down, never below
	-- ImpactDamageArmorFloor. Worn totals run about 0.3 in clothes, 5 in mail
	-- and 12 or more in plate.
	--
	-- At the defaults a town guard reads smash_def about 5, so worn is 4.5, the
	-- falloff is 1/(1+4.5/2.9) = 0.39, and a gallop's 111 becomes 44: two
	-- impacts to put them down on good rolls and three otherwise.
	ImpactDamageByTier       = {
		Walk   = 0,     -- a walk staggers, it does not wound
		Trot   = 18,
		Gallop = 111,   -- kills about four unarmored victims in five
		Rear   = 75,    -- badly wounds a healthy victim, kills one already hurt
		Charge = 118,   -- kills an unarmored victim on every roll
	},

	-- Hand back whatever the engine charged for the collision, so the figures
	-- above are the entire cost of an impact. This is also what keeps a death
	-- the mod's to attribute, which is what CollisionIsCrime depends on.
	ImpactDamageOwnsTheHit   = true,

	ImpactDamageReclaimCeiling = 60,   -- never give back more than this at once

	ImpactDamageArmorScale   = 2.9,   -- smash_def past the ignored figure that halves damage
	ImpactDamageArmorCurve   = 1.0,   -- >1 armor bites sooner, <1 flattens
	ImpactDamageArmorFloor   = 0.14,  -- least armor can reduce an impact to
	ImpactDamageIgnoredArmor = 0.5,   -- smash_def that is clothing, not armor
	ImpactDamageVariance     = 0.15,  -- spread either side of the tier figure
	ImpactDamageDelayMs      = 600,   -- used only when a development test
	                                  -- subject's health is put back; a real
	                                  -- impact waits for the body to stop

	-- The rider's own half of an impact: a kick to the camera, scaled per tier
	-- by CameraShakeByTier. Angle is degrees of rotation and shift is meters
	-- of displacement, both on all three axes. Frequency is the shake's
	-- period; vanilla's own shakes use 0.05. Randomness varies each shake so
	-- repeated collisions do not feel canned.
	CameraShake              = true,
	CameraShakeAngle         = 4.0,
	CameraShakeShift         = 0.08,
	CameraShakeDurationSec   = 0.5,
	CameraShakeFrequency     = 0.05,
	CameraShakeRandomness    = 0.5,

	-- A blur pulse on the rider's view in first person, scaled per tier by
	-- RiderBlurByTier. It starts at RiderBlurAmount, holds for RiderBlurHoldMs
	-- and decays to nothing over RiderBlurMs in RiderBlurSteps steps, with a
	-- chromatic shift of RiderBlurChroma on the same curve. Off in third
	-- person by default, where the dust is visible; the views are told apart
	-- by how far the camera sits from the player.
	RiderBlur                = true,
	RiderBlurAmount          = 1.0,
	RiderBlurHoldMs          = 260,
	RiderBlurChroma          = 0.2,
	RiderBlurMs              = 480,
	RiderBlurSteps           = 7,
	RiderBlurFirstPersonOnly = true,
	RiderBlurFirstPersonRange = 1.5,

	-- What the rider's own Horsemanship is worth. The game's `horse_riding`
	-- skill runs 0 to 20, and it multiplies an impact's stamina cost, running
	-- linearly from HorsemanshipStaminaWorst at level 0 to
	-- HorsemanshipStaminaBest at the top. At 5.0 a gallop's 0.20 share is one
	-- full pool, so a novice is thrown by a single impact; at 1.0 an expert
	-- rides down five in a row, or three in a fight.
	--
	-- Seat is the chance of staying mounted when the horse is finally spent,
	-- at the top of the skill. The horse stops either way.
	Horsemanship             = true,
	HorsemanshipSkill        = "horse_riding",
	HorsemanshipMaxLevel     = 20,
	HorsemanshipStaminaWorst = 5.0,   -- the cost multiplier at level 0
	HorsemanshipStaminaBest  = 1.0,   -- and at HorsemanshipMaxLevel
	HorsemanshipSeatChance   = 0.6,   -- chance of keeping the saddle, at the top

	-- What the horse's own barding is worth, read from the total smash_def of
	-- what the horse is wearing; tack counts for nothing. Three effects, each
	-- scaling from nothing on a bare horse to its figure below on a full set:
	-- a stamina relief, a damage multiplier and a flat added force. Barding
	-- does not scale with Horsemanship.
	Barding                  = true,
	BardingFullSmashDef      = 1.45,  -- smash_def counted as a full set, measured
	BardingStaminaRelief     = 0.03,  -- share of the pool a full set takes off
	BardingDamageBonus       = 0.15,  -- how much harder a barded horse hits
	-- What barding adds to the knockdown force, in five steps. Each row is
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

	-- Whether a horse ridden until spent sometimes bolts after throwing its
	-- rider, fleeing on its own AI.
	HorseBoltsWhenSpent      = true,
	HorseBoltChance          = 0.4,
	HorseBoltRestoreMs       = 3000,  -- health is given back this long after

	-- The noise a collision makes, played on the victim at the moment of
	-- impact. Any of the game's audio trigger names may be used, listed in
	-- Libs/GameAudio/*.xml inside GameData.pak. A name that does not exist
	-- plays nothing, and an empty list silences that tier alone.
	ImpactSound              = true,

	-- The master level, in meters, added to every layer of every tier. Higher
	-- is quieter. The listener follows the camera, so third person hears the
	-- mix from further back; these values are set in first person.
	ImpactSoundDistance      = 2.0,

	-- The occasional bone crack, at a gallop or a charge, as an impact layer.
	ImpactSoundCrack         = { "f_bodyfall_leg_break", 20, 6 },
	ImpactSoundCrackChance   = 0.12,

	-- Whether Henry grunts as the collision goes through him, from
	-- RiderVocalByTier.
	RiderVocal               = true,

	-- How long the rider stays quiet after grunting, so riding into a group is
	-- not a grunt per person. A harder impact is still let through.
	RiderVocalCooldownMs     = 1500,

	-- Henry's spoken lines. RiderBark gives an ordinary impact a chance of a
	-- line instead of a grunt; the pool of impact lines ships empty, so it has
	-- no effect. RiderBarkKill gives a collision that kills its own line.
	RiderBark                = false,
	RiderBarkChance          = 0.35,  -- how often an impact gets a line
	RiderBarkCooldownMs      = 5000,  -- how long Henry stays quiet after a line
	RiderBarkKill            = true,  -- a line when a collision kills

	-- The priority Henry's lines are sent at. The dialog system discards a
	-- request below the top without error, so at 0 a line loses to anything
	-- else the speaker is saying.
	RiderBarkPriority        = 50,

	-- The least time between two impacts on the same person, so one pass of
	-- the horse through them counts once.
	HitMinIntervalMs         = 700,

	-- The dust a body throws up where it lands, sized per tier by
	-- ImpactDustScaleByTier. The victim's vertical speed is sampled every
	-- ImpactDustSampleMs: once they fall faster than ImpactDustFallVz and then
	-- slow past ImpactDustLandVz, they have landed. A victim not seen falling
	-- within ImpactDustFallWaitSamples, or not landed by ImpactDustMaxSamples,
	-- gets the dust anyway. The effect is a particle library node from the
	-- game's own Libs/Particles.
	ImpactDust               = true,
	ImpactDustEffect         = "WH_Particels.other.explosion_dust",
	ImpactDustHeight         = 0.05,
	ImpactDustSampleMs       = 50,
	ImpactDustFallVz         = -0.5,
	ImpactDustLandVz         = -0.15,
	ImpactDustFallWaitSamples = 8,
	ImpactDustMaxSamples     = 30,

	-- The dirt and blood a collision leaves on the victim, from
	-- VictimDirtByTier and VictimBloodByTier. Dirt covers everything they are
	-- wearing; blood goes on the side of the body the horse struck. Both
	-- accumulate across impacts. Nothing is applied at a walk.
	VictimMarks              = true,

	-- Switches.
	CollisionIsCrime         = true,  -- riding someone down is a crime at every
	                                  -- tier that wounds; never at a walk
	ReleaseAnimationMovement = true,  -- keeps staggering victims out of walls
	ReleaseMovementAttempts  = 4,     -- repeated, since a blend can undo it
	ReleaseMovementGapMs     = 80,    -- how far apart the attempts are
	ReplanAfterReaction      = true,  -- sends them back to their stall or
	                                  -- whatever they were leaning on
	SuppressStaggerInCombat  = true,  -- skip the stagger during a fight

	-- Spoken reactions. Every line is vanilla, spoken by the character's own
	-- voice actor, chosen by naming a bark set. Nothing new ships. A character
	-- whose voice never recorded a set stays silent, as in vanilla.
	--
	-- A knockdown speaks twice: a wordless cry at the moment of impact, graded
	-- by how hard the hit was, and then words once the victim is back on their
	-- feet.
	Barks                    = true,  -- the feature as a whole
	CollisionBarks           = true,  -- victims and bystanders of an impact
	RearBarks                = true,  -- whoever a rear is aimed at
	BarkCooldownMs           = 3000,  -- per speaker, so a crowd is not a choir.
	                                  -- An impact inside it is silent for
	                                  -- that speaker
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

	-- Characters the game will not let you attack, such as Captain Bernard, the
	-- Lord of Leipa and anyone else a quest is protecting, take no damage from a
	-- collision. They are still knocked down, but the impact costs them no
	-- health. Turning this off lets a horse kill a quest-critical character.
	ProtectStoryCharacters   = true,
	LogTelemetry             = true,  -- diagnostics in kcd.log

	-- Names the reason a nearby NPC produced no reaction. Writes a line for
	-- every entity near the horse, including doors and audio areas, which is
	-- thousands per session. Only useful while investigating why a specific
	-- impact did nothing. `build.ps1` refuses a release build with this on.
	DiagnoseMisses           = false,

	-- ======================================================================
	-- Everything below is exposed for completeness; the values here are the
	-- tuned ones. A key removed from this file falls back to its built-in
	-- default, so deleting a line is always a safe way back.
	-- ======================================================================

	-- Detection and scoring. These decide what counts as a hit and how fast
	-- the horse is judged to have been going, so a wrong value shows up as
	-- impacts that do not land, or land when you rode past.
	HitRadius                = 2.5,   -- broad-phase sphere around the horse
	HorseMaxVerticalDiff     = 2.35,  -- height difference above which a hit is
	                                  -- ignored, so you do not strike someone
	                                  -- on a floor above or below you
	HorseAirborneVz          = 2.5,   -- upward speed counted as a jump
	MaxImpactSpeed           = 13.0,  -- ceiling on the speed a hit is scored
	                                  -- at, just above the fastest gallop in
	                                  -- the game
	ImpactSpeedSamples       = 9,     -- ticks of speed history a hit is scored
	                                  -- from, so a single stuttering frame
	                                  -- does not decide the tier
	SweepMultiplier          = 0.50,  -- how far ahead to sweep per m/s
	MaxSweepExtra            = 0.35,  -- cap on that forward sweep, in meters
	TickSeconds              = 0.033, -- detection interval

	-- Ragdoll motion after the throw. These shape how a thrown body travels
	-- and comes to rest; changing one alone usually reads as a body that
	-- slides, floats or stops dead.
	ImpulseDelayMs           = 50,    -- wait before the ragdoll impulse
	LateralImpulse           = 0.0,   -- sideways share of the impulse
	RagdollBrake             = true,  -- whether a braking tier brakes at all
	RagdollBrakeArmorScaleArmored = 0.35,   -- armor scale counted as full mail
	RagdollBrakeArmorScaleUnarmored = 1.26, -- armor scale counted as unarmored
	RagdollDampContactRun    = 3,     -- samples of contact in a row before the
	                                  -- body counts as down
	RagdollDampRampSamples   = 8,     -- samples over which damping ramps up
	RagdollSpeedSoftCapSpan  = 3.0,   -- how far above a tier's ceiling the drag
	                                  -- reaches full strength

	-- The rear and the charge. Timings measured against the animation, so a
	-- value out of step with the clip shows as a strike that misses or lands
	-- after the horse has come down.
	RearImpactSpeed          = 6.0,   -- the speed a rear is scored at, since
	                                  -- the horse is barely moving
	RearAnimSpeed            = 1.0,   -- how fast the charge's rear plays
	RearChargeLungePeakMin   = 3.0,   -- top speed a lunge must reach to count
	RearChargeLungeSpentAt   = 0.5,   -- fraction of its peak at which the
	                                  -- lunge is treated as spent
	RearChargeStrikeBehind   = 0.2,   -- how far behind the horse still counts
	RearChargeStrikeMs       = 1600,  -- how long the strike sweeps for
	RearChargeStrikePollMs   = 50,    -- how often it sweeps
	RearChargeWaitMs         = 400,   -- when the mod starts watching for the
	                                  -- rear to end
	RearChargeWaitPollMs     = 30,    -- how often it looks
	RearChargeWaitCeilingMs  = 3000,  -- push anyway by this point

	-- How a spoken line is submitted to the dialog system. The system discards
	-- a losing request silently, so these decide whether a line is heard at
	-- all. Documented in full in docs/TECHNICAL_DETAILS.md.
	BarkPriority             = 0,     -- rank in the dialog system's auction
	BarkCanBeDelayed         = false, -- queue a line that loses, instead of
	                                  -- dropping it
	BarkOverrideSuppress     = false, -- ignore a suppressMonologs context
	BarkInCombat             = false, -- whether a victim already fighting still
	                                  -- remarks on being ridden into, which
	                                  -- vanilla refuses

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
