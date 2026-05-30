// DQAdd — Body threshold perks. Linear Body points already give per-point HP/slowdown
// tweaks via the apply hook; these perks layer on top at fixed spent-Body thresholds.

/datum/perk/body/toughness
	name = "Toughness"
	desc = "Years of physical conditioning. Reduces incoming brute damage by 10%."
	cost = 1
	body_tier_threshold = BODY_TIER_LOW
	var_changes = list("brute_mod" = 0.9)

/datum/perk/body/vigor
	name = "Vigor"
	desc = "An unusually large frame and lung capacity. +25 max health."
	cost = 1
	body_tier_threshold = BODY_TIER_MID
	var_changes = list("total_health" = 125)

/datum/perk/body/endurance
	name = "Endurance"
	desc = "Hard-trained stamina. Reduces oxy and toxin damage taken by 15%."
	cost = 1
	body_tier_threshold = BODY_TIER_HIGH
	var_changes = list(
		"oxy_mod" = 0.85,
		"toxins_mod" = 0.85,
	)
