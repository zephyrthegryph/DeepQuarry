//Engineering

/datum/gear/uniform/engineering_chief_selector
	display_name = "Engineering - " + JOB_CHIEF_ENGINEER + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_CHIEF_ENGINEER + "s."
	allowed_roles = list(JOB_CHIEF_ENGINEER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_chiefengi
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/engineering_chief_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/chief_engineer/skirt,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_chiefengi,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_chiefengi_skirt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/ce
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
