/datum/gear/uniform/talon_security
	display_name = "Talon - Guard's Uniforms"
	description = "Select from a range of outfits available to all Talon Guard."
	allowed_roles = list(JOB_TALON_GUARD)
	path = /obj/item/clothing/under/rank/talon/security/refreshed
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/talon_security/New()
	..()
	var/list/selector_uniforms = list(
		"Refreshed Talon Guard Uniform"=/obj/item/clothing/under/rank/talon/security/refreshed,
		"Old Talon Security Uniform"=/obj/item/clothing/under/rank/talon/security,
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
