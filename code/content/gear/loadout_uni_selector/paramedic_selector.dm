/datum/gear/uniform/paramedic_selector
	display_name = "Medical - " + JOB_PARAMEDIC + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_PARAMEDIC + "s."
	allowed_roles = list(JOB_MEDICAL_DOCTOR,JOB_CHIEF_MEDICAL_OFFICER,JOB_PARAMEDIC,JOB_TALON_DOCTOR)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/paramedunidark
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/paramedic_selector/New()
	..()
	var/list/selector_uniforms = list(
		"dark"=/obj/item/clothing/under/rank/paramedunidark,
		"dark w/ skirt"=/obj/item/clothing/under/rank/parameduniskirtdark,
		"light"=/obj/item/clothing/under/rank/paramedunilight,
		"light w/ skirt"=/obj/item/clothing/under/rank/parameduniskirtlight,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_para,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_para_skirt,
		"TG&C light jumpsuit"=/obj/item/clothing/under/rank/neo_para_light,
		"TG&C light jumpskirt"=/obj/item/clothing/under/rank/neo_para_light_skirt
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
