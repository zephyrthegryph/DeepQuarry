/datum/gear/uniform/science_robotics_selector
	display_name = "Science - " + JOB_ROBOTICIST + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_ROBOTICIST + "s."
	allowed_roles = list(JOB_RESEARCH_DIRECTOR,JOB_ROBOTICIST)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_robo
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/science_robotics_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/roboticist/skirt,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_robo,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_robo_skirt
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
