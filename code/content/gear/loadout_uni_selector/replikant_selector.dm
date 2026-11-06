//Replikant & Signalis-themed human-wear

/datum/gear/uniform/replikant_selector
	display_name = "Replikant Uniform Selection"
	description = "Several variants of bodysuit designed for Second Generation Biosynthetics."
	path = /obj/item/clothing/under/replika/arar
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/replikant_selector/New()
	..()
	var/list/selector_uniforms = list(
		"Macaw"=/obj/item/clothing/under/replika/arar,
		"Magpie"=/obj/item/clothing/under/replika/lstr,
		"Falcon"=/obj/item/clothing/under/replika/fklr,
		"Owl"=/obj/item/clothing/under/replika/eulr,
		"Hummingbird"=/obj/item/clothing/under/replika/klbr,
		"Stork/Starling"=/obj/item/clothing/under/replika/stcr,
		"Eagle"=/obj/item/clothing/under/replika/adlr,
		"Magpie, Alternate"=/obj/item/clothing/under/replika/lstr_alt
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
