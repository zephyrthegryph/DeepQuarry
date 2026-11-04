/datum/gear/uniform/chief_medical_selector
	display_name = "Medical - " + JOB_CHIEF_MEDICAL_OFFICER + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_CHIEF_MEDICAL_OFFICER + "."
	allowed_roles = list(JOB_CHIEF_MEDICAL_OFFICER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_cmo
	sort_category = "Uniforms"
	cost = 2

/datum/gear/uniform/chief_medical_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/chief_medical_officer/skirt,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_cmo,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_cmo_skirt,
		"TG&C turtleneck"=/obj/item/clothing/under/rank/neo_cmo_turtle,
		"TG&C turtleneck w/ skirt"=/obj/item/clothing/under/rank/neo_cmo_turtle_skirt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/cmo
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
