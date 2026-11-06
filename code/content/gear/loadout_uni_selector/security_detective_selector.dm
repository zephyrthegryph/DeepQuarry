/datum/gear/uniform/security_detective_selector
	display_name = "Security - " + JOB_DETECTIVE + "'s Uniforms"
	description = "Select from a range of outfits available to all Detectives."
	allowed_roles = list(JOB_HEAD_OF_SECURITY,JOB_DETECTIVE)
	show_roles = FALSE
	path = /obj/item/clothing/under/det/corporate
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/security_detective_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/det/skirt,
		"corporate"=/obj/item/clothing/under/det/corporate
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
