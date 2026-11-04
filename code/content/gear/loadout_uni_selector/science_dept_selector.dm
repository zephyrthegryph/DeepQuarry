/datum/gear/uniform/science_dept_selector
	display_name = "Science - Basic Uniforms"
	description = "Select from a range of outfits available to all Science personnel."
	allowed_roles = list(JOB_SCIENTIST,JOB_RESEARCH_DIRECTOR,JOB_ROBOTICIST,JOB_XENOBIOLOGIST,JOB_XENOBOTANIST)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_science
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/science_dept_selector/New()
	..()
	var/list/selector_uniforms = list(
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_science,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_science_skirt,
		"TG&C utility"=/obj/item/clothing/under/rank/neo_util_sci,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/sci
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
