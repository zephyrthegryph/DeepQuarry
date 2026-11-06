// New Talon Uniforms

/datum/gear/uniform/talon
	display_name = "Talon's Uniforms"
	description = "Select from a range of outfits available to all Talon crew."
	allowed_roles = list(JOB_TALON_CAPTAIN, JOB_TALON_DOCTOR, JOB_TALON_ENGINEER, JOB_TALON_PILOT, JOB_TALON_GUARD, JOB_TALON_MINER)
	path = /obj/item/clothing/under/rank/talon/basic/refreshed
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/talon/New()
	..()
	var/list/selector_uniforms = list(
		"Refreshed Talon crew Uniform"=/obj/item/clothing/under/rank/talon/basic/refreshed,
		"Old Talon crew Uniform"=/obj/item/clothing/under/rank/talon/basic,
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
