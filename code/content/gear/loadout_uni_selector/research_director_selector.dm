//Science

/datum/gear/uniform/research_director_selector
	display_name = "Science - " + JOB_RESEARCH_DIRECTOR + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_RESEARCH_DIRECTOR + "s."
	allowed_roles = list(JOB_RESEARCH_DIRECTOR)
	show_roles = FALSE
	path = VARIANT(/obj/item/clothing/under/rank/neo_rd_suit)
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/research_director_selector/New()
	..()
	var/list/selector_uniforms = list(
		"TG&C jumpsuit"=VARIANT(/obj/item/clothing/under/rank/neo_rd_suit),
		"TG&C jumpskirt"=VARIANT(/obj/item/clothing/under/rank/neo_rd_suit_skirt),
		"TG&C turtleneck"=VARIANT(/obj/item/clothing/under/rank/neo_rd_turtle),
		"TG&C turtleneck w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_rd_turtle_skirt),
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/rd
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
