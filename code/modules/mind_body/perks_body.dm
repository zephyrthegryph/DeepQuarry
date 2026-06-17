// Body perks — four trees (Strength, Vigor, Speed, Endurance) drawing on the shared
// age-scaled Body pool. Each tree is organised into sub-theme groups (comment headers)
// that define distinct build axes; the framework only knows trees, so the groupings are
// purely for the author/reader.
//
// Effects:
//  - `var_changes` perks bake stat mods into the synthesised species at spawn.
//  - every other perk's effect is read at its relevant hook via mob.has_perk(<type>).
//  - capstones gate on `category_spend_required` (deep investment by any combination).
//
// Player-facing `desc` is written plainly with no exact numbers; the real tuning lives
// in the hooks and var_changes.

// ═══════════════════════════════════════════════════════════════════════════════
// STRENGTH
// ═══════════════════════════════════════════════════════════════════════════════

// ── Bruiser (brute mitigation) ──────────────────────────────────────────────────

/datum/perk/body/str_toughness
	name = "Toughness"
	desc = "You take a little less damage from brute attacks."
	icon_name = "shield"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 10
	var_changes = list("brute_mod" = 0.9)

/datum/perk/body/str_iron_skin
	name = "Iron Skin"
	desc = "You take less damage from brute attacks."
	icon_name = "shield-halved"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_toughness)
	var_changes = list("brute_mod" = 0.8)

/datum/perk/body/str_crusher
	name = "Crusher"
	desc = "You take a lot less damage from brute attacks, and can shove harder."
	icon_name = "hand-fist"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_iron_skin)
	var_changes = list("brute_mod" = 0.7)

/datum/perk/body/str_bone_density
	name = "Bone Density"
	desc = "You take a lot less damage from heavy impacts."
	icon_name = "bone"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 100

/datum/perk/body/str_thick_skin
	name = "Thick Skin"
	desc = "You get open wounds from brute attacks less often."
	icon_name = "shield-blank"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 101

// ── Striker ─────────────────────────────────────────────────────────────────────

/datum/perk/body/str_powerful
	name = "Powerful Build"
	desc = "Your unarmed attacks hit harder."
	icon_name = "hand-back-fist"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 20
	fx_mult = list(DQ_PERK_FX_UNARMED_DMG = DQ_PERK_POWERFUL_UNARMED_MULT)

/datum/perk/body/str_sundering
	name = "Sundering Blows"
	desc = "Your melee strikes pierce through armor better."
	icon_name = "khanda"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_powerful)
	fx_add = list(DQ_PERK_FX_ARMOR_PEN = DQ_PERK_SUNDERING_PEN)

/datum/perk/body/str_heavy_hands
	name = "Heavy Hands"
	desc = "Your heavy swings are even stronger."
	icon_name = "weight-hanging"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_powerful)
	fx_mult = list(DQ_PERK_FX_HEAVY_DMG = DQ_PERK_HEAVY_HANDS_MULT)

/datum/perk/body/str_brawler
	name = "Brawler"
	desc = "Your bare-handed blows rattle an enemy's guard."
	icon_name = "hand-fist"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 30

/datum/perk/body/str_force_of_will
	name = "Force of Will"
	desc = "Your melee strikes can knock back enemies."
	icon_name = "explosion"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_brawler)

/datum/perk/body/str_concussive
	name = "Concussive Blows"
	desc = "Enemies you stagger are left slowed and reeling."
	icon_name = "burst"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_brawler)

/datum/perk/body/str_agile_strikes
	name = "Agile Strikes"
	desc = "You flow between enemies without breaking your attack rhythm."
	icon_name = "arrows-turn-to-dots"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_powerful)

// ── Grappler ────────────────────────────────────────────────────────────────────

/datum/perk/body/str_iron_grip
	name = "Iron Grip"
	desc = "You're hard to disarm or knock off balance."
	icon_name = "hand"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 40

/datum/perk/body/str_vise_hands
	name = "Vise Hands"
	desc = "Enemies struggle to break free of your grip."
	icon_name = "hand-rock"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_iron_grip)

/datum/perk/body/str_choke_hold
	name = "Choke Hold"
	desc = "You tighten your hold on a grabbed enemy faster."
	icon_name = "head-side-cough"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_vise_hands)

/datum/perk/body/str_crushing_embrace
	name = "Crushing Embrace"
	desc = "Holding an enemy tight slowly crushes them."
	icon_name = "hands-bound"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_vise_hands)

/datum/perk/body/str_pin
	name = "Pin"
	desc = "An enemy you've pinned can't crawl away."
	icon_name = "thumbtack"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_vise_hands)

/datum/perk/body/str_manhandle
	name = "Manhandle"
	desc = "Hauling a grabbed enemy around doesn't slow you."
	icon_name = "people-pulling"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_iron_grip)

/datum/perk/body/str_wrestler
	name = "Wrestler"
	desc = "Enemies you throw hit the ground harder."
	icon_name = "person-falling-burst"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 50

/datum/perk/body/str_toppler
	name = "Toppler"
	desc = "A thrown enemy bowls over anyone they crash into."
	icon_name = "people-arrows"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_wrestler)

// ── Thrower ─────────────────────────────────────────────────────────────────────

/datum/perk/body/str_throwing_arm
	name = "Throwing Arm"
	desc = "You throw items farther and more accurately."
	icon_name = "baseball"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 60
	fx_add = list(DQ_PERK_FX_THROW_RANGE = DQ_PERK_THROW_RANGE_BONUS)

/datum/perk/body/str_hammer_throw
	name = "Hammer Throw"
	desc = "Thrown items strike with greater force."
	icon_name = "hammer"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_throwing_arm)
	fx_mult = list(DQ_PERK_FX_THROW_FORCE = DQ_PERK_HAMMER_THROW_MULT)

/datum/perk/body/str_crippling_throw
	name = "Crippling Throw"
	desc = "Heavy thrown objects can stagger or knock down what they hit."
	icon_name = "meteor"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_hammer_throw)

/datum/perk/body/str_precise_aim
	name = "Precise Aim"
	desc = "You reliably hit the limb you aim for when throwing."
	icon_name = "bullseye"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 70

/datum/perk/body/str_practiced_throw
	name = "Practiced Throw"
	desc = "Sharp thrown items dig in and lodge in your target."
	icon_name = "location-pin"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_precise_aim)

// ── Powerhouse (heavy frame / structures) ───────────────────────────────────────

/datum/perk/body/str_heavy_lifter
	name = "Heavy Lifter"
	desc = "Bulky gear doesn't weigh you down."
	icon_name = "dumbbell"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 80

/datum/perk/body/str_strongman
	name = "Strongman"
	desc = "You can lug an extra bulky item without slowing."
	icon_name = "person"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_heavy_lifter)

/datum/perk/body/str_steel_frame
	name = "Steel Frame"
	desc = "Heavy armor barely slows you."
	icon_name = "shield-cat"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 110
	var_changes = list("item_slowdown_mod" = 0.5)

/datum/perk/body/str_wall_of_meat
	name = "Wall of Meat"
	desc = "Stand your ground and nothing can push you."
	icon_name = "anchor"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 120

// ── Capstone ────────────────────────────────────────────────────────────────────

/datum/perk/body/str_juggernaut
	name = "Juggernaut"
	desc = "Nothing knocks you back, your shoves always rock the enemy, and your fists hit even harder."
	icon_name = "mountain"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	category_spend_required = DQ_PERK_CAPSTONE_SPEND
	sort_priority = -10

// ═══════════════════════════════════════════════════════════════════════════════
// VIGOR
// ═══════════════════════════════════════════════════════════════════════════════

// ── Vitality (raw HP) ───────────────────────────────────────────────────────────

/datum/perk/body/vig_robust
	name = "Robust"
	desc = "You're hardier and carry more health than most."
	icon_name = "heart"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 10
	var_changes = list("total_health" = 125)

/datum/perk/body/vig_iron_constitution
	name = "Iron Constitution"
	desc = "You have far more health and shrug off burns better."
	icon_name = "shield-heart"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_robust)
	var_changes = list(
		"total_health" = 160,
		"burn_mod" = 0.9,
	)

/datum/perk/body/vig_juice_box
	name = "Juice Box"
	desc = "Your body holds more blood before you run dry."
	icon_name = "wine-bottle"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 100
	fx_mult = list(DQ_PERK_FX_MAX_BLOOD = DQ_PERK_JUICE_BOX_MULT)

// ── Recovery ────────────────────────────────────────────────────────────────────

/datum/perk/body/vig_hearty
	name = "Hearty"
	desc = "You heal faster when out of a fight."
	icon_name = "house-medical"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 20
	fx_mult = list(DQ_PERK_FX_REGEN = DQ_PERK_HEARTY_MULT)

/datum/perk/body/vig_quick_healer
	name = "Quick Healer"
	desc = "All of your natural healing comes quicker."
	icon_name = "stethoscope"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_hearty)
	fx_mult = list(DQ_PERK_FX_HEAL = DQ_PERK_QUICK_HEALER_MULT)

/datum/perk/body/vig_convalescent
	name = "Convalescent"
	desc = "Resting or lying down speeds your recovery."
	icon_name = "bed-pulse"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_hearty)

/datum/perk/body/vig_stalwart
	name = "Stalwart"
	desc = "You shake off stuns quicker than most."
	icon_name = "person-rays"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 110

/datum/perk/body/vig_restoration
	name = "Restoration"
	desc = "Your damaged organs mend faster on their own."
	icon_name = "heart-pulse"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 120
	fx_mult = list(DQ_PERK_FX_ORGAN_HEAL = DQ_PERK_RESTORATION_MULT)

// ── Last Stand (crit survival) ──────────────────────────────────────────────────

/datum/perk/body/vig_pain_tolerance
	name = "Pain Tolerance"
	desc = "You stay on your feet at lower health before collapsing."
	icon_name = "user-injured"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 30

/datum/perk/body/vig_survivor
	name = "Survivor"
	desc = "You hold onto more health when you fall into critical condition."
	icon_name = "shield-virus"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 40

/datum/perk/body/vig_deaths_door
	name = "Death's Door"
	desc = "You cling to consciousness even past the brink."
	icon_name = "skull"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_survivor)

/datum/perk/body/vig_second_wind
	name = "Second Wind"
	desc = "When badly wounded you surge back to your feet — once in a while."
	icon_name = "rotate"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_pain_tolerance)

/datum/perk/body/vig_unkillable
	name = "Unkillable"
	desc = "While dying, you take half damage until you're stable."
	icon_name = "skull-crossbones"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_iron_constitution)

/datum/perk/body/vig_adrenal
	name = "Adrenal Reserve"
	desc = "Falling into critical condition floods you with a burst of speed and resilience — once in a while."
	icon_name = "bolt"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_survivor)

// ── Bloodwork ───────────────────────────────────────────────────────────────────

/datum/perk/body/vig_bloodflow
	name = "Strong Bloodflow"
	desc = "Your wounds stop bleeding faster."
	icon_name = "droplet"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 50
	fx_mult = list(DQ_PERK_FX_CLOT = DQ_PERK_CLOT_MULT)

/datum/perk/body/vig_coagulation
	name = "Coagulation"
	desc = "Your bleeding never gets truly severe."
	icon_name = "droplet-slash"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_bloodflow)
	fx_mult = list(DQ_PERK_FX_CLOT = DQ_PERK_CLOT_MULT)

/datum/perk/body/vig_blood_freak
	name = "Blood Freak"
	desc = "Drinking blood replenishes your own."
	icon_name = "wine-glass"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_coagulation)

/datum/perk/body/vig_marrow
	name = "Marrow Pack"
	desc = "You replace lost blood twice as fast."
	icon_name = "person-half-dress"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	sort_priority = 130
	fx_mult = list(DQ_PERK_FX_BLOOD_REGEN = DQ_PERK_MARROW_MULT)

// ── Capstone ────────────────────────────────────────────────────────────────────

/datum/perk/body/vig_undying
	name = "Undying"
	desc = "The closer you are to death, the less damage you take — down to half when critical — and your health pool grows."
	icon_name = "infinity"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	category_spend_required = DQ_PERK_CAPSTONE_SPEND
	sort_priority = -10
	var_changes = list("total_health" = 150)

// ═══════════════════════════════════════════════════════════════════════════════
// SPEED
// ═══════════════════════════════════════════════════════════════════════════════

// ── Swiftness (movement) ────────────────────────────────────────────────────────

/datum/perk/body/spd_quick_step
	name = "Quick Step"
	desc = "You shrug off slowdowns and move a little faster."
	icon_name = "shoe-prints"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 10
	var_changes = list("slowdown" = -0.5)

/datum/perk/body/spd_sprinter
	name = "Sprinter"
	desc = "Your base movement speed is permanently higher."
	icon_name = "person-running"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_quick_step)
	var_changes = list("slowdown" = -1)

/datum/perk/body/spd_burst
	name = "Burst Speed"
	desc = "You explode into a sprint, faster over the first few steps."
	icon_name = "rocket"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_sprinter)

/datum/perk/body/spd_light_footed
	name = "Light-Footed"
	desc = "You move more quietly."
	icon_name = "user-ninja"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 100

/datum/perk/body/spd_marathoner
	name = "Marathoner"
	desc = "You can run for ages without tiring."
	icon_name = "person-walking-arrow-loop-left"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 101

// ── Evasion ─────────────────────────────────────────────────────────────────────

/datum/perk/body/spd_reflexes
	name = "Reflexes"
	desc = "You can dodge thrown objects and stray gunfire."
	icon_name = "bolt"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 20
	fx_add = list(DQ_PERK_FX_EVADE_RANGED = DQ_PERK_REFLEXES_PROB)

/datum/perk/body/spd_dodge
	name = "Dodge"
	desc = "You sometimes slip aside from light melee blows."
	icon_name = "arrows-left-right"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_reflexes)
	fx_add = list(DQ_PERK_FX_EVADE_MELEE = DQ_PERK_DODGE_PROB)

/datum/perk/body/spd_evasive_step
	name = "Evasive Step"
	desc = "You can instinctively sidestep a telegraphed heavy attack."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_dodge)
	fx_add = list(DQ_PERK_FX_EVADE_MELEE = DQ_PERK_DODGE_PROB)

/datum/perk/body/spd_eyes_open
	name = "Eyes Open"
	desc = "Ambushes and backstabs lose their edge against you."
	icon_name = "eye"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 30

/datum/perk/body/spd_quick_reactions
	name = "Quick Reactions"
	desc = "You recover quickly after lowering your guard."
	icon_name = "bolt-lightning"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 40

/datum/perk/body/spd_always_ready
	name = "Always Ready"
	desc = "You can act almost the instant you stop moving."
	icon_name = "person-rays"
	cost = 3
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_quick_reactions, /datum/perk/body/spd_eyes_open)

// ── Footing ─────────────────────────────────────────────────────────────────────

/datum/perk/body/spd_sure_footed
	name = "Sure-Footed"
	desc = "You never slip on wet floors or peels."
	icon_name = "shoe"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 50

/datum/perk/body/spd_catlike
	name = "Catlike"
	desc = "You take less from falls and stay upright after drops."
	icon_name = "cat"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_sure_footed)

/datum/perk/body/spd_ice_walker
	name = "Ice Walker"
	desc = "Ice and frost can't make you slip."
	icon_name = "snowflake"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 102

/datum/perk/body/spd_web_walker
	name = "Web Walker"
	desc = "Sticky and webbed ground doesn't slow you."
	icon_name = "spider"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 103

// ── Escapist ────────────────────────────────────────────────────────────────────

/datum/perk/body/spd_slippery
	name = "Slippery"
	desc = "You wriggle free of grabs faster."
	icon_name = "fish"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 60
	fx_add = list(DQ_PERK_FX_GRAB_ESCAPE = DQ_PERK_SLIPPERY_ESCAPE)

/datum/perk/body/spd_eel_shape
	name = "Eel Shape"
	desc = "Cuffs and restraints come off you quickly."
	icon_name = "person-swimming"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_slippery)

/datum/perk/body/spd_wriggler
	name = "Wriggler"
	desc = "It's very hard to keep you pinned down."
	icon_name = "worm"
	cost = 3
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_slippery)
	fx_add = list(DQ_PERK_FX_GRAB_ESCAPE = DQ_PERK_WRIGGLER_ESCAPE)

// ── Deft Hands ──────────────────────────────────────────────────────────────────

/datum/perk/body/spd_quickened_hands
	name = "Quickened Hands"
	desc = "You swap gear in and out of your hands faster."
	icon_name = "hand-sparkles"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 70

/datum/perk/body/spd_quick_draw
	name = "Quick Draw"
	desc = "You draw a holstered weapon instantly."
	icon_name = "gun"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_quickened_hands)

/datum/perk/body/spd_acrobatic
	name = "Acrobatic"
	desc = "You get back up from knockdowns faster."
	icon_name = "person-skating"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	sort_priority = 140
	fx_mult = list(DQ_PERK_FX_KNOCKDOWN_DUR = DQ_PERK_ACROBATIC_MULT)

// ── Capstone ────────────────────────────────────────────────────────────────────

/datum/perk/body/spd_blur
	name = "Blur"
	desc = "You're always likely to slip aside from melee, and a clean dodge sends you darting away."
	icon_name = "ghost"
	cost = 3
	tree = PERK_TREE_BODY_SPEED
	category_spend_required = DQ_PERK_CAPSTONE_SPEND
	sort_priority = -10
	fx_add = list(DQ_PERK_FX_EVADE_MELEE = DQ_PERK_BLUR_PROB)

// ═══════════════════════════════════════════════════════════════════════════════
// ENDURANCE
// ═══════════════════════════════════════════════════════════════════════════════

// ── Unyielding (status resistance) ──────────────────────────────────────────────

/datum/perk/body/end_unflinching
	name = "Unflinching"
	desc = "Stuns and knockdowns don't hold you as long."
	icon_name = "shield-blank"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 10
	var_changes = list(
		"stun_mod" = 0.8,
		"weaken_mod" = 0.8,
	)

/datum/perk/body/end_steadfast
	name = "Steadfast"
	desc = "You're knocked back a shorter distance."
	icon_name = "anchor"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 20
	fx_mult = list(DQ_PERK_FX_KNOCKBACK_DIST = DQ_PERK_STEADFAST_MULT)

/datum/perk/body/end_stone_wall
	name = "Stone Wall"
	desc = "You shake off stuns, knockdowns, and weakening even faster."
	icon_name = "wall-brick"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_unflinching, /datum/perk/body/end_steadfast)
	var_changes = list(
		"stun_mod" = 0.6,
		"weaken_mod" = 0.6,
	)

/datum/perk/body/end_rooted
	name = "Rooted"
	desc = "Hold your ground and shoves can't budge you."
	icon_name = "tree"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_steadfast)

/datum/perk/body/end_tenacious
	name = "Tenacious"
	desc = "The first time you're stunned in a fight, you recover fast."
	icon_name = "person-falling-burst"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 100

// ── Conditioning (stamina economy) ──────────────────────────────────────────────

/datum/perk/body/end_steady
	name = "Steady"
	desc = "You resist suffocation and toxins better."
	icon_name = "lungs"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 30
	var_changes = list(
		"oxy_mod" = 0.85,
		"toxins_mod" = 0.85,
	)

/datum/perk/body/end_iron_lungs
	name = "Iron Lungs"
	desc = "You hold your breath far longer and barely suffer suffocation."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_steady)
	var_changes = list("oxy_mod" = 0.5)

/datum/perk/body/end_breathless
	name = "Breathless"
	desc = "You no longer need to breathe at all."
	icon_name = "ban"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_iron_lungs)
	var_changes = list("oxy_mod" = 0)

/datum/perk/body/end_conditioned
	name = "Conditioned"
	desc = "You tire more slowly during exertion."
	icon_name = "person-running"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 40
	fx_mult = list(DQ_PERK_FX_STAMINA_DRAIN = DQ_PERK_CONDITIONED_MULT)

/datum/perk/body/end_second_breath
	name = "Second Breath"
	desc = "Your stamina returns faster when you're clear of the fight."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_conditioned)
	fx_mult = list(DQ_PERK_FX_STAMINA_REGEN = DQ_PERK_SECOND_BREATH_MULT)

/datum/perk/body/end_tireless
	name = "Tireless"
	desc = "Running out of stamina slows you instead of dropping you."
	icon_name = "battery-three-quarters"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 110

/datum/perk/body/end_hard_worker
	name = "Hard Worker"
	desc = "Hard labor never wears you out."
	icon_name = "person-digging"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 120

// ── Acclimated (hazard tolerance) ───────────────────────────────────────────────

/datum/perk/body/end_heat
	name = "Heat Acclimated"
	desc = "You endure extreme heat and pressure with ease."
	icon_name = "fire"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 50
	fx_mult = list(DQ_PERK_FX_HAZARD_HEAT = 0.5, DQ_PERK_FX_HAZARD_PRESSURE_HIGH = 0.7)

/datum/perk/body/end_cold
	name = "Cold Acclimated"
	desc = "Cold and vacuum work tire you more slowly."
	icon_name = "snowflake"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 51
	fx_mult = list(DQ_PERK_FX_HAZARD_COLD = 0.5)

/datum/perk/body/end_vacuum
	name = "Vacuum Native"
	desc = "Low pressure barely harms you."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 60
	fx_mult = list(DQ_PERK_FX_HAZARD_PRESSURE_LOW = 0.5)

/datum/perk/body/end_acid
	name = "Acid Resistant"
	desc = "Acid burns you less."
	icon_name = "flask"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 130
	fx_mult = list(DQ_PERK_FX_HAZARD_ACID = 0.75)

/datum/perk/body/end_radiation
	name = "Radiation Hardened"
	desc = "You take much less harm from radiation."
	icon_name = "radiation"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	sort_priority = 140
	var_changes = list("radiation_mod" = 0.5)

/datum/perk/body/end_pressure_immune
	name = "Pressure Immune"
	desc = "Pressure extremes can't harm you at all."
	icon_name = "gauge-high"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_vacuum)
	fx_mult = list(DQ_PERK_FX_HAZARD_PRESSURE_HIGH = 0, DQ_PERK_FX_HAZARD_PRESSURE_LOW = 0)

/datum/perk/body/end_unbreakable
	name = "Unbreakable"
	desc = "Heat, cold, radiation, and pressure harm you even less."
	icon_name = "shield-virus"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_heat, /datum/perk/body/end_cold, /datum/perk/body/end_vacuum)
	fx_mult = list(DQ_PERK_FX_HAZARD_HEAT = 0.75, DQ_PERK_FX_HAZARD_COLD = 0.75, DQ_PERK_FX_HAZARD_PRESSURE_HIGH = 0.75, DQ_PERK_FX_HAZARD_PRESSURE_LOW = 0.75)

// ── Capstone ────────────────────────────────────────────────────────────────────

/datum/perk/body/end_immovable
	name = "Immovable"
	desc = "After you're stunned or knocked down, you're briefly immune to being stunned again, and your guard is harder to break."
	icon_name = "wall-brick"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	category_spend_required = DQ_PERK_CAPSTONE_SPEND
	sort_priority = -10
	fx_mult = list(DQ_PERK_FX_STAGGER_RESIST = DQ_PERK_IMMOVABLE_STAGGER)
