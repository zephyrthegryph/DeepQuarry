// DQAdd — Body perks, split across four thematic trees. Linear Conditioning still
// applies per-point HP/slowdown via the apply hook; these perks layer on top once
// the player has invested enough Conditioning to unlock each tier.

// ─── Strength ────────────────────────────────────────────────────────────────────
// Force, brute mitigation, carry capacity.

/datum/perk/body/toughness
	name = "Toughness"
	desc = "Years of physical conditioning. Reduces incoming brute damage by 10%."
	cost = 1
	tree = PERK_TREE_BODY_STRENGTH
	body_tier_threshold = BODY_TIER_LOW
	var_changes = list("brute_mod" = 0.9)

/datum/perk/body/iron_skin
	name = "Iron Skin"
	desc = "Dense bone and scar tissue blunt heavy hits. Brute damage reduced a further 10%."
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	body_tier_threshold = BODY_TIER_MID
	requires = list(/datum/perk/body/toughness)
	var_changes = list("brute_mod" = 0.8)

/datum/perk/body/heavy_lifter
	name = "Heavy Lifter"
	desc = "Practiced load-bearing. You shrug off the slowdown from carrying bulky items."
	cost = 2
	tree = PERK_TREE_BODY_STRENGTH
	body_tier_threshold = BODY_TIER_MID

// ─── Vigor ──────────────────────────────────────────────────────────────────────
// Health pool, recovery, raw vitality.

/datum/perk/body/vigor
	name = "Vigor"
	desc = "An unusually large frame and lung capacity. +25 max health."
	cost = 1
	tree = PERK_TREE_BODY_VIGOR
	body_tier_threshold = BODY_TIER_LOW
	var_changes = list("total_health" = 125)

/datum/perk/body/hearty
	name = "Hearty"
	desc = "Quick natural recovery. Out-of-combat regeneration speed is 25% faster."
	cost = 2
	tree = PERK_TREE_BODY_VIGOR
	body_tier_threshold = BODY_TIER_MID
	requires = list(/datum/perk/body/vigor)

/datum/perk/body/iron_constitution
	name = "Iron Constitution"
	desc = "A second wind. +35 additional max health and burn resistance up 10%."
	cost = 3
	tree = PERK_TREE_BODY_VIGOR
	body_tier_threshold = BODY_TIER_HIGH
	requires = list(/datum/perk/body/vigor)
	var_changes = list(
		"total_health" = 160,
		"burn_mod" = 0.9,
	)

// ─── Speed ──────────────────────────────────────────────────────────────────────
// Movement speed, reflexes, agility.

/datum/perk/body/quick_step
	name = "Quick Step"
	desc = "Light on your feet. Slowdown penalties take effect 25% less harshly."
	cost = 1
	tree = PERK_TREE_BODY_SPEED
	body_tier_threshold = BODY_TIER_LOW
	var_changes = list("slowdown" = -0.5)

/datum/perk/body/sprinter
	name = "Sprinter"
	desc = "Trained for short bursts. Your base movement speed is permanently increased."
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	body_tier_threshold = BODY_TIER_MID
	requires = list(/datum/perk/body/quick_step)
	var_changes = list("slowdown" = -1)

/datum/perk/body/sure_footed
	name = "Sure-Footed"
	desc = "Practiced balance. Slipping on wet floors and similar terrain hazards no longer knocks you down."
	cost = 2
	tree = PERK_TREE_BODY_SPEED
	body_tier_threshold = BODY_TIER_MID

// ─── Endurance ──────────────────────────────────────────────────────────────────
// Stamina, resistance, hazard tolerance.

/datum/perk/body/endurance
	name = "Endurance"
	desc = "Hard-trained stamina. Reduces oxy and toxin damage taken by 15%."
	cost = 1
	tree = PERK_TREE_BODY_ENDURANCE
	body_tier_threshold = BODY_TIER_LOW
	var_changes = list(
		"oxy_mod" = 0.85,
		"toxins_mod" = 0.85,
	)

/datum/perk/body/iron_lungs
	name = "Iron Lungs"
	desc = "You hold your breath for noticeably longer. Asphyxiation damage from low-pressure environments is halved."
	cost = 2
	tree = PERK_TREE_BODY_ENDURANCE
	body_tier_threshold = BODY_TIER_MID
	requires = list(/datum/perk/body/endurance)
	var_changes = list("oxy_mod" = 0.5)

/datum/perk/body/unflinching
	name = "Unflinching"
	desc = "Battle-tested nerves. Reduces stun and weaken effect duration by 20%."
	cost = 3
	tree = PERK_TREE_BODY_ENDURANCE
	body_tier_threshold = BODY_TIER_HIGH
	var_changes = list(
		"stun_mod" = 0.8,
		"weaken_mod" = 0.8,
	)
