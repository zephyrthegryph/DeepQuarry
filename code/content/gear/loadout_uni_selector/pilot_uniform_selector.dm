/datum/gear/uniform/pilot_uniform_selector
	display_name = "Civilian - " + JOB_PILOT+ "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_PILOT + "s (including those on the Talon)."
	allowed_roles = list(JOB_PILOT,JOB_TALON_PILOT)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_pilot
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/pilot_uniform_selector/New()
	..()
	var/list/selector_uniforms = list(
		"standard pilot's uniform"=/obj/item/clothing/under/rank/pilot1/no_webbing,
		"navy pilot's uniform"=/obj/item/clothing/under/rank/pilot2,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_pilot,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_pilot_skirt,
		"Major Bill's flightsuit"=/obj/item/clothing/under/mbill_flight,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/pilot
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
