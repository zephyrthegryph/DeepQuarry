// DQAdd — Body perks, one tree per category. Each category has its own pool, so
// "spending in Strength" doesn't reduce what's available for Vigor / Speed / Endurance.
// All perks declare `tree` (which sets `category` automatically via init_perks).

// ─── Strength ────────────────────────────────────────────────────────────────────

/datum/perk/body/strength_toughness
	name = "Toughness"
	desc = "Years of physical conditioning. Reduces incoming brute damage by 10%."
	icon_name = "hand-fist"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	var_changes = list("brute_mod" = 0.9)

/datum/perk/body/strength_iron_skin
	name = "Iron Skin"
	desc = "Dense bone and scar tissue blunt heavy hits. Brute damage reduced a further 10%."
	icon_name = "shield"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/strength_toughness)
	var_changes = list("brute_mod" = 0.8)

/datum/perk/body/strength_heavy_lifter
	name = "Heavy Lifter"
	desc = "Practiced load-bearing. You shrug off slowdown from carrying bulky items."
	icon_name = "weight-hanging"
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH

/datum/perk/body/strength_brawler
	name = "Brawler"
	desc = "Years of unarmed throwdowns. Your unarmed strikes deal 20% more damage."
	icon_name = "hand-back-fist"
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH

/datum/perk/body/strength_crusher
	name = "Crusher"
	desc = "Master physical leverage. Brute resistance another 10% AND your shoves stagger their target."
	icon_name = "fist-raised"
	cost = 3
	tree = PERK_TREE_BODY_STRENGTH
	requires = list(/datum/perk/body/strength_iron_skin)
	var_changes = list("brute_mod" = 0.7)

// ─── Vigor ──────────────────────────────────────────────────────────────────────

/datum/perk/body/vigor_robust
	name = "Robust"
	desc = "An unusually large frame and lung capacity. +25 max health."
	icon_name = "heart"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	var_changes = list("total_health" = 125)

/datum/perk/body/vigor_hearty
	name = "Hearty"
	desc = "Quick natural recovery. Out-of-combat regen speed is 25% faster."
	icon_name = "house-medical"
	cost = 1
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vigor_iron_constitution
	name = "Iron Constitution"
	desc = "A second wind. +35 additional max health and 10% burn resistance."
	icon_name = "shield-heart"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vigor_robust)
	var_changes = list(
		"total_health" = 160,
		"burn_mod" = 0.9,
	)

/datum/perk/body/vigor_pain_tolerance
	name = "Pain Tolerance"
	desc = "You're hard to put down. Threshold for crit halflowering by 15 HP."
	icon_name = "user-injured"
	cost = 2
	tree = PERK_TREE_BODY_VIGOR

/datum/perk/body/vigor_unkillable
	name = "Unkillable"
	desc = "Sheer bull-headed will to live. Halve all damage taken when in crit until you stabilise."
	icon_name = "skull-crossbones"
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	requires = list(/datum/perk/body/vigor_iron_constitution)

// ─── Speed ──────────────────────────────────────────────────────────────────────

/datum/perk/body/speed_quick_step
	name = "Quick Step"
	desc = "Light on your feet. Slowdown penalties hit you 25% less harshly."
	icon_name = "shoe-prints"
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	var_changes = list("slowdown" = -0.5)

/datum/perk/body/speed_sprinter
	name = "Sprinter"
	desc = "Trained for short bursts. Base movement speed permanently increased."
	icon_name = "person-running"
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/speed_quick_step)
	var_changes = list("slowdown" = -1)

/datum/perk/body/speed_sure_footed
	name = "Sure-Footed"
	desc = "Practiced balance. Slipping on wet floors or banana peels no longer knocks you down."
	icon_name = "shoe"
	cost = 1
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/speed_reflexes
	name = "Reflexes"
	desc = "Cat-fast reactions. 20% chance to evade thrown items and stray projectiles."
	icon_name = "bolt"
	cost = 2
	tree = PERK_TREE_BODY_SPEED

/datum/perk/body/speed_blinkstep
	name = "Blink Step"
	desc = "Trained for the killbox. Once a minute, dash one tile in any direction."
	icon_name = "wind"
	cost = 3
	tree = PERK_TREE_BODY_SPEED
	requires = list(/datum/perk/body/speed_sprinter)

// ─── Endurance ──────────────────────────────────────────────────────────────────

/datum/perk/body/endurance_steady
	name = "Steady"
	desc = "Hard-trained stamina. Reduces oxygen and toxin damage taken by 15%."
	icon_name = "lungs"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	var_changes = list(
		"oxy_mod" = 0.85,
		"toxins_mod" = 0.85,
	)

/datum/perk/body/endurance_iron_lungs
	name = "Iron Lungs"
	desc = "Hold your breath for noticeably longer. Asphyxiation damage halved."
	icon_name = "wind"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	requires = list(/datum/perk/body/endurance_steady)
	var_changes = list("oxy_mod" = 0.5)

/datum/perk/body/endurance_unflinching
	name = "Unflinching"
	desc = "Battle-tested nerves. Reduces stun and weaken effect duration by 20%."
	icon_name = "shield-alt"
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	var_changes = list(
		"stun_mod" = 0.8,
		"weaken_mod" = 0.8,
	)

/datum/perk/body/endurance_heat_acclimated
	name = "Heat Acclimated"
	desc = "Your body shrugs off high-pressure and high-temperature environments."
	icon_name = "fire"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE

/datum/perk/body/endurance_cold_acclimated
	name = "Cold Acclimated"
	desc = "Cryogenic environments and EVA work tire you out slower."
	icon_name = "snowflake"
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
