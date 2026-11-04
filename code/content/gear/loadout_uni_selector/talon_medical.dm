/datum/gear/uniform/talon_medical
	display_name = "Talon - Doctor's Uniforms"
	description = "Select from a range of outfits available to all Talon Doctor."
	allowed_roles = list(JOB_TALON_DOCTOR)
	path = /obj/item/clothing/under/rank/talon/proper/refreshed
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/talon_medical/New()
	..()
	var/list/selector_uniforms = list(
		"Refreshed Talon Doctor Uniform"=/obj/item/clothing/under/rank/talon/proper/refreshed,
		"Old Talon Doctor Uniform"=/obj/item/clothing/under/rank/talon/proper,
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
