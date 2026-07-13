// Body perks. 22-ish per category, one tree per category. Pool sizes are set
// to give a player room to invest in ~3-4 perks per category at age 18, sculpting a
// build path rather than buying everything. var_changes effects are real where they
// touch /datum/species vars (brute_mod, total_health, slowdown, etc.); softer effects
// are descriptive roadmaps the gameplay hooks read off mob flags or perk lookups.

// ═══════════════════════════════════════════════════════════════════════════════
// STRENGTH
// ═══════════════════════════════════════════════════════════════════════════════

// Sort priorities: chain-head perks claim tens (10 / 20 / 30 …) so they land
// in a logical left-to-right reading order; standalone perks claim the 100s.
// Children inherit their parent's slot via the subtree algorithm.

/datum/perk/body/str_toughness
	name = "Toughness"
	desc = "Years of physical conditioning. Reduces incoming brute damage by 10%."
	icon_name = "shield"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 10
	var_changes = list("brute_mod" = 0.9)

/datum/perk/body/str_iron_skin
	name = "Iron Skin"
	desc = "Dense bone and scar tissue blunt heavy hits. Brute damage further reduced 10%."
	icon_name = "shield-halved"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_toughness)
	var_changes = list("brute_mod" = 0.8)

/datum/perk/body/str_crusher
	name = "Crusher"
	desc = "Capstone brute resistance. Brute reduced a further 10% and shoves stagger their target."
	icon_name = "fist-raised"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_iron_skin)
	var_changes = list("brute_mod" = 0.7)

/datum/perk/body/str_powerful
	name = "Powerful Build"
	desc = "A strong frame. Unarmed damage +20%."
	icon_name = "hand-fist"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 20

/datum/perk/body/str_bone_density
	name = "Bone Density"
	desc = "Heavy bone mass. Falls and impacts deal less damage."
	icon_name = "bone"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 100

/datum/perk/body/str_brawler
	name = "Brawler"
	desc = "Bar-fight veteran. Unarmed strikes have a 10% chance to stagger."
	icon_name = "hand-back-fist"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 30

/datum/perk/body/str_heavy_lifter
	name = "Heavy Lifter"
	desc = "Practiced load-bearing. You shrug off slowdown from carrying bulky items."
	icon_name = "weight-hanging"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 50

/datum/perk/body/str_strongman
	name = "Strongman"
	desc = "Carry one extra bulky item without slowdown."
	icon_name = "person"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_heavy_lifter)

/datum/perk/body/str_iron_grip
	name = "Iron Grip"
	desc = "It's hard to take what you don't want to let go of. Disarm attempts on you fail more often."
	icon_name = "hand"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 40

/datum/perk/body/str_vise_hands
	name = "Vise Hands"
	desc = "Practiced grip. Grabs you initiate are 50% harder to break."
	icon_name = "hand-rock"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_iron_grip)

/datum/perk/body/str_choke
	name = "Choke Hold"
	desc = "Aggressive-grab transitions take one fewer cycle to reach knockout."
	icon_name = "head-side-cough"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_vise_hands)

/datum/perk/body/str_throwing_arm
	name = "Throwing Arm"
	desc = "Better range and accuracy on thrown items."
	icon_name = "baseball"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 60

/datum/perk/body/str_hammer_throw
	name = "Hammer Throw"
	desc = "Thrown items deal +25% damage on impact."
	icon_name = "hammer"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_throwing_arm)

/datum/perk/body/str_sundering
	name = "Sundering Blows"
	desc = "Your melee strikes ignore 25% of target armor."
	icon_name = "khanda"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_powerful)

/datum/perk/body/str_demolisher
	name = "Demolisher"
	desc = "You deal double damage to walls, doors, and other structures."
	icon_name = "screwdriver-wrench"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 110

/datum/perk/body/str_force
	name = "Force of Will"
	desc = "Melee strikes have a 15% chance to knock the target a tile back."
	icon_name = "explosion"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_brawler)

/datum/perk/body/str_reckless
	name = "Reckless"
	desc = "Take 10% more damage but deal 20% more in melee."
	icon_name = "skull"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 120

/datum/perk/body/str_bulwark
	name = "Bulwark"
	desc = "Holding a shield grants an additional 10% block chance."
	icon_name = "shield-blank"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 130

/datum/perk/body/str_wall
	name = "Wall of Meat"
	desc = "While standing still, become Immovable — push attempts on you fail."
	icon_name = "anchor"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 140

/datum/perk/body/str_titan
	name = "Titan"
	desc = "Capstone build perk. +15% unarmed damage and +5% incoming brute resistance."
	icon_name = "mountain"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_powerful, /datum/perk/body/str_iron_skin)
	var_changes = list("brute_mod" = 0.75)

/datum/perk/body/str_slam
	name = "Body Slam"
	desc = "Sprint into a target — knock them prone and deal bonus brute."
	icon_name = "person-falling"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/str_force)

/datum/perk/body/str_steel
	name = "Steel Frame"
	desc = "Heavy armor's slowdown penalty is halved for you."
	icon_name = "shield-cat"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	sort_priority = 150

// ═══════════════════════════════════════════════════════════════════════════════
// VIGOR
// ═══════════════════════════════════════════════════════════════════════════════

/datum/perk/body/vig_robust
	name = "Robust"
	desc = "An unusually large frame and lung capacity. +25 max health."
	icon_name = "heart"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	var_changes = list("total_health" = 125)

/datum/perk/body/vig_iron_constitution
	name = "Iron Constitution"
	desc = "A second wind. +35 additional max health and 10% burn resistance."
	icon_name = "shield-heart"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_robust)
	var_changes = list(
		"total_health" = 160,
		"burn_mod" = 0.9,
	)

/datum/perk/body/vig_unkillable
	name = "Unkillable"
	desc = "Sheer bull-headed will to live. Halve damage taken while in crit until you stabilize."
	icon_name = "skull-crossbones"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_iron_constitution)

/datum/perk/body/vig_hearty
	name = "Hearty"
	desc = "Quick natural recovery. Out-of-combat regen speed is 25% faster."
	icon_name = "house-medical"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_pain_tolerance
	name = "Pain Tolerance"
	desc = "Hard to put down. Threshold for crit lowered by 15 HP."
	icon_name = "user-injured"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_quick_healer
	name = "Quick Healer"
	desc = "All forms of natural healing are 20% faster."
	icon_name = "stethoscope"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_hearty)

/datum/perk/body/vig_bloodflow
	name = "Strong Bloodflow"
	desc = "Bleed wounds clot 50% faster."
	icon_name = "droplet"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_coagulation
	name = "Coagulation"
	desc = "Severe blood loss is rare. Bleeds you suffer cap at moderate severity."
	icon_name = "droplet-slash"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_bloodflow)

/datum/perk/body/vig_marrow
	name = "Marrow Pack"
	desc = "Blood regeneration is doubled."
	icon_name = "person-half-dress"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_second_wind
	name = "Second Wind"
	desc = "Once per round, when you drop below 25% HP, restore 30 HP and clear stun."
	icon_name = "rotate"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_pain_tolerance)

/datum/perk/body/vig_stalwart
	name = "Stalwart"
	desc = "Stuns mid-combat do not interrupt your slow regen."
	icon_name = "tower-broadcast"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_battle_hardened
	name = "Battle Hardened"
	desc = "Reduced bleed and stun duration during combat."
	icon_name = "person-rays"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_long_lived
	name = "Long-Lived"
	desc = "Age penalties to stats begin 20 years later than usual."
	icon_name = "hourglass-half"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_robust_liver
	name = "Robust Liver"
	desc = "You metabolize alcohol and chems 50% faster."
	icon_name = "wine-bottle"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_hardy
	name = "Hardy"
	desc = "Disease resistance +20%."
	icon_name = "virus-slash"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_plague_veteran
	name = "Plague Veteran"
	desc = "Disease resistance +35% on top of Hardy. Infection length halved."
	icon_name = "virus-covid-slash"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_hardy)

/datum/perk/body/vig_furnace
	name = "Internal Furnace"
	desc = "Body heat self-regulates. Cold environments take longer to affect you."
	icon_name = "temperature-high"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_restoration
	name = "Restoration"
	desc = "Organ damage heals 25% faster naturally."
	icon_name = "heart-pulse"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_adrenal
	name = "Adrenal Reserve"
	desc = "When in crit, gain a brief burst of speed and damage resistance once per round."
	icon_name = "bolt"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_survivor
	name = "Survivor"
	desc = "Genuine lifeline. Dropping into crit costs you 10 fewer HP."
	icon_name = "shield-virus"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_iron_stomach
	name = "Iron Stomach"
	desc = "Food poisoning and contamination effects are halved."
	icon_name = "drumstick-bite"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vig_inexhaustible
	name = "Inexhaustible"
	desc = "Capstone vitality. +50 max HP and an extra Survivor activation per round."
	icon_name = "infinity"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vig_robust, /datum/perk/body/vig_survivor)
	var_changes = list("total_health" = 175)

// ═══════════════════════════════════════════════════════════════════════════════
// SPEED
// ═══════════════════════════════════════════════════════════════════════════════

/datum/perk/body/spd_quick_step
	name = "Quick Step"
	desc = "Light on your feet. Slowdown penalties hit you 25% less harshly."
	icon_name = "shoe-prints"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	var_changes = list("slowdown" = -0.5)

/datum/perk/body/spd_sprinter
	name = "Sprinter"
	desc = "Trained for short bursts. Base movement speed permanently increased."
	icon_name = "person-running"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_quick_step)
	var_changes = list("slowdown" = -1)

/datum/perk/body/spd_blink_step
	name = "Blink Step"
	desc = "Trained for the killbox. Once a minute, dash one tile in any direction."
	icon_name = "wind"
	cost = 3
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_sprinter)

/datum/perk/body/spd_sure_footed
	name = "Sure-Footed"
	desc = "Practiced balance. Slipping on wet floors or banana peels no longer knocks you down."
	icon_name = "shoe"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_reflexes
	name = "Reflexes"
	desc = "Cat-fast reactions. 20% chance to evade thrown items and stray projectiles."
	icon_name = "bolt"
	cost = 2
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_light_footed
	name = "Light-Footed"
	desc = "You move quieter — footsteps are inaudible to others without sharp hearing."
	icon_name = "user-ninja"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_quick_reactions
	name = "Quick Reactions"
	desc = "Acting on first instinct. Reaction-time checks succeed 25% more often."
	icon_name = "bolt-lightning"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_dodge
	name = "Dodge"
	desc = "10% chance to evade an incoming melee hit."
	icon_name = "arrows-left-right"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_reflexes)

/datum/perk/body/spd_slippery
	name = "Slippery"
	desc = "Escape grabs in one fewer cycle."
	icon_name = "fish"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_eel
	name = "Eel Shape"
	desc = "Cuffs and restraints come off 50% faster on you."
	icon_name = "person-swimming"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_slippery)

/datum/perk/body/spd_burst
	name = "Burst Speed"
	desc = "Short-distance sprints are 25% faster for the first three tiles."
	icon_name = "rocket"
	cost = 2
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_acrobatic
	name = "Acrobatic"
	desc = "Tumble out of stuns. Knockdown duration -20%."
	icon_name = "person-skating"
	cost = 2
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_catlike
	name = "Catlike"
	desc = "You always land on your feet — fall damage halved and ledge drops don't stun."
	icon_name = "cat"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_sure_footed)

/datum/perk/body/spd_marathon
	name = "Marathoner"
	desc = "Running long distances doesn't tire you out at all."
	icon_name = "person-walking-arrow-loop-left"
	cost = 2
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_ice_walker
	name = "Ice Walker"
	desc = "Ice and frost tiles are not slippery to you."
	icon_name = "snowflake"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_web_walker
	name = "Web Walker"
	desc = "Sticky and webbed surfaces don't slow you."
	icon_name = "spider"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_quickened_hands
	name = "Quickened Hands"
	desc = "Equipping and unequipping items takes 25% less time."
	icon_name = "hand-sparkles"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_quick_draw
	name = "Quick Draw"
	desc = "Drawing a weapon from a holster is instant."
	icon_name = "gun"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_quickened_hands)

/datum/perk/body/spd_doordasher
	name = "Door Dasher"
	desc = "Doors open before you reach them — automatic doors stop slowing you."
	icon_name = "door-open"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_stair_climber
	name = "Stair Climber"
	desc = "Stairs and z-level transitions take no extra time for you."
	icon_name = "stairs"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_eyes_open
	name = "Eyes Open"
	desc = "Examining nearby tiles is instant. Surprise attacks on you fail more often."
	icon_name = "eye"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/spd_always_ready
	name = "Always Ready"
	desc = "Initiative is permanently improved — you act first when timing matters."
	icon_name = "person-rays"
	cost = 3
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/spd_quick_reactions, /datum/perk/body/spd_eyes_open)

// ═══════════════════════════════════════════════════════════════════════════════
// ENDURANCE
// ═══════════════════════════════════════════════════════════════════════════════

/datum/perk/body/end_steady
	name = "Steady"
	desc = "Hard-trained stamina. Reduces oxygen and toxin damage taken by 15%."
	icon_name = "lungs"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	var_changes = list(
		"oxy_mod" = 0.85,
		"toxins_mod" = 0.85,
	)

/datum/perk/body/end_iron_lungs
	name = "Iron Lungs"
	desc = "Hold your breath for noticeably longer. Asphyxiation damage halved."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_steady)
	var_changes = list("oxy_mod" = 0.5)

/datum/perk/body/end_unflinching
	name = "Unflinching"
	desc = "Battle-tested nerves. Reduces stun and weaken effect duration by 20%."
	icon_name = "shield-blank"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	var_changes = list(
		"stun_mod" = 0.8,
		"weaken_mod" = 0.8,
	)

/datum/perk/body/end_heat_acclimated
	name = "Heat Acclimated"
	desc = "Your body shrugs off high-pressure and high-temperature environments."
	icon_name = "fire"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_cold_acclimated
	name = "Cold Acclimated"
	desc = "Cryogenic environments and EVA work tire you out slower."
	icon_name = "snowflake"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_vacuum
	name = "Vacuum Native"
	desc = "Low-pressure environments deal 50% less damage to you."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_acid
	name = "Acid Resistant"
	desc = "Reduces acid burn damage by 25%."
	icon_name = "flask"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_rad
	name = "Radiation Hardened"
	desc = "Reduces radiation exposure damage by 40%."
	icon_name = "radiation"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_emp
	name = "EMP Hardened"
	desc = "EMP effects on cybernetics you carry are reduced 50%."
	icon_name = "tower-broadcast"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_iron_will
	name = "Iron Will"
	desc = "Mental stun (flash, panic) resisted 30% more often."
	icon_name = "brain"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_steadfast
	name = "Steadfast"
	desc = "Knockback distance from explosions and shoves halved for you."
	icon_name = "anchor"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_composed
	name = "Composed"
	desc = "Panic and terror effects last 50% less time."
	icon_name = "user-shield"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_indomitable
	name = "Indomitable"
	desc = "Flash effects reduced to a brief blink. Recovery instant."
	icon_name = "eye-slash"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_iron_will)

/datum/perk/body/end_tireless
	name = "Tireless"
	desc = "Sleep deprivation no longer slows you down."
	icon_name = "moon"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_hard_worker
	name = "Hard Worker"
	desc = "Sustained labor never fatigues you. Construction and tool work effects no longer wind you."
	icon_name = "person-digging"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_caffeine
	name = "Caffeine Tolerant"
	desc = "Stimulants and caffeine effects last twice as long."
	icon_name = "mug-hot"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_camel
	name = "Camel"
	desc = "Hunger and thirst grow 50% slower."
	icon_name = "drumstick-bite"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_iron_belly
	name = "Iron Belly"
	desc = "Food poisoning and contamination effects are negated."
	icon_name = "utensils"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_burn_tolerant
	name = "Burn Tolerant"
	desc = "Reduces burn damage by 10% on top of any other resistances."
	icon_name = "fire"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	var_changes = list("burn_mod" = 0.9)

/datum/perk/body/end_bleed_tolerant
	name = "Bleed Tolerant"
	desc = "Total bleed cap reduced 25%."
	icon_name = "droplet-slash"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/end_stone_wall
	name = "Stone Wall"
	desc = "Capstone endurance. Combined stun, weaken, knockdown duration reduced an additional 20%."
	icon_name = "wall-brick"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_unflinching, /datum/perk/body/end_steadfast)
	var_changes = list(
		"stun_mod" = 0.6,
		"weaken_mod" = 0.6,
	)

/datum/perk/body/end_unbreakable
	name = "Unbreakable"
	desc = "Capstone resilience. Hazard damage from heat, cold, radiation, and pressure all reduced an additional 25%."
	icon_name = "shield-virus"
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/end_heat_acclimated, /datum/perk/body/end_cold_acclimated, /datum/perk/body/end_vacuum)
