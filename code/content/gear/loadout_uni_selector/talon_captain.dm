/datum/gear/uniform/talon_captain
	display_name = "Talon - Captain's Uniforms"
	description = "Select from a range of outfits available to all Talon Captain."
	allowed_roles = list(JOB_TALON_CAPTAIN)
	path = /obj/item/clothing/under/rank/talon/command/refreshed
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/talon_captain/New()
	..()
	var/list/selector_uniforms = list(
		"Refreshed Talon Command Uniform"=/obj/item/clothing/under/rank/talon/command/refreshed,
		"Old Talon Command Uniform"=/obj/item/clothing/under/rank/talon/command,
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
