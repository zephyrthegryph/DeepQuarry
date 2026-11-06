/datum/gear/uniform/engineer_selector
	display_name = "Engineering - Basic Uniforms"
	description = "Select from a range of outfits available to all Engineering personnel."
	allowed_roles = list(JOB_CHIEF_ENGINEER,JOB_ENGINEER,JOB_ATMOSPHERIC_TECHNICIAN,JOB_TALON_ENGINEER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_engi
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/engineer_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/engineer/skirt,
		"turtleneck"=/obj/item/clothing/under/rank/engineer/turtleneck,
		"voidsuit underlayer"=/obj/item/clothing/under/undersuit/hazard,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_engi,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_engi_skirt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/engi,
		"hazard jumpsuit"=/obj/item/clothing/under/hazard
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
