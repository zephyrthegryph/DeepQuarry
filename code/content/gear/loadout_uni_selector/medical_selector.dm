//Medical

/datum/gear/uniform/medical_selector
	display_name = "Medical - Basic Uniforms"
	description = "Select from a range of outfits available to all Medical personnel."
	allowed_roles = list(JOB_CHIEF_MEDICAL_OFFICER,JOB_MEDICAL_DOCTOR,JOB_CHEMIST,JOB_PSYCHIATRIST,JOB_PARAMEDIC,JOB_TALON_DOCTOR)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_med
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/medical_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/medical/skirt,
		"virologist skirt"=/obj/item/clothing/under/rank/virologist/skirt,
		"turtleneck"=/obj/item/clothing/under/rank/medical/turtleneck,
		"vey-medical jumpsuit"=/obj/item/clothing/under/corp/veymed,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_med,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_med_skirt,
		"TG&C virology jumpsuit"=/obj/item/clothing/under/rank/neo_viro,
		"TG&C virology jumpskirt"=/obj/item/clothing/under/rank/neo_viro_skirt,
		"TG&C dark jumpsuit"=/obj/item/clothing/under/rank/neo_med_dark,
		"TG&C dark jumpskirt"=/obj/item/clothing/under/rank/neo_med_dark_skirt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/med,
		"sterile jumpsuit"=/obj/item/clothing/under/sterile
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
