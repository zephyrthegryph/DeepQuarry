/datum/gear/uniform/cargo_miner_selector
	display_name = "Cargo - Miner's Uniforms"
	description = "Select from a range of outfits available to all Mining personnel."
	allowed_roles = list(JOB_SHAFT_MINER,JOB_QUARTERMASTER,JOB_TALON_MINER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_miner
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/cargo_miner_selector/New()
	..()
	var/list/selector_uniforms = list(
		"TG&C miner's uniform"=/obj/item/clothing/under/rank/neo_miner,
		"TG&C hunter's uniform"=/obj/item/clothing/under/rank/neo_miner_fauna
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
