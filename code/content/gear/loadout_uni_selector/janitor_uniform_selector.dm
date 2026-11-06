/datum/gear/uniform/janitor_uniform_selector
	display_name = "Civilian - " + JOB_JANITOR + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_JANITOR + "ial personnel."
	allowed_roles = list(JOB_JANITOR)
	show_roles = FALSE
	path = VARIANT(/obj/item/clothing/under/rank/neo_janitor)
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/janitor_uniform_selector/New()
	..()
	var/list/selector_uniforms = list(
		"TG&C janitor's uniform"=VARIANT(/obj/item/clothing/under/rank/neo_janitor),
		"TG&C janitor's uniform w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_janitor_skirt),
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/janitor
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
