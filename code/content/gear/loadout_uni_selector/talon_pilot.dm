/datum/gear/uniform/talon_pilot
	display_name = "Talon - Pilot's Uniforms"
	description = "Select from a range of outfits available to all Talon Pilot."
	allowed_roles = list(JOB_TALON_PILOT)
	path = /obj/item/clothing/under/rank/talon/pilot/refreshed
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/talon_pilot/New()
	..()
	var/list/selector_uniforms = list(
		"Refreshed Talon Pilot Uniform"=/obj/item/clothing/under/rank/talon/pilot/refreshed,
		"Old Talon Pilot Uniform"=/obj/item/clothing/under/rank/talon/pilot,
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
