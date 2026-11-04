/datum/gear/uniform/gestalt_selector
	display_name = "Sleek Uniform Selection"
	description = "Multiple variants of single-stripe pattern uniforms. Best worn under their accompanying jacket."
	path = /obj/item/clothing/under/gestalt
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/gestalt_selector/New()
	..()
	var/list/selector_uniforms = list(
		"Sleek, standard"=/obj/item/clothing/under/gestalt/sleek,
		"Sleek, skirt"=/obj/item/clothing/under/gestalt/sleek_skirt,
		"Sleek, feminine"=/obj/item/clothing/under/gestalt/sleek_fem,
		"Sleek, sleeveless"=/obj/item/clothing/under/gestalt/sleeveless
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
