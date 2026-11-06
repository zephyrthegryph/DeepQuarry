/datum/gear/uniform/cargo_general_selector
	display_name = "Cargo - Basic Uniforms"
	description = "Select from a range of outfits available to all Cargo personnel."
	allowed_roles = list(JOB_CARGO_TECHNICIAN,JOB_SHAFT_MINER,JOB_QUARTERMASTER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/cargotech/jeans
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/cargo_general_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/cargotech/skirt,
		"jeans"=/obj/item/clothing/under/rank/cargotech/jeans,
		"jeans, feminine cut"=/obj/item/clothing/under/rank/cargotech/jeans/female,
		"TG&C shorts"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_shorts),
		"TG&C skirt"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_skirt),
		"TG&C jumpsuit"=VARIANT(/obj/item/clothing/under/rank/neo_cargo),
		"TG&C utility uniform"=VARIANT(/obj/item/clothing/under/rank/neo_util_cargo),
		"TG&C dark"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_dark),
		"TG&C casual"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_casual),
		"TG&C turtleneck"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_turtle),
		"TG&C turtleneck w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_turtle_skirt),
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/cargo,
		"customs officer"=VARIANT(/obj/item/clothing/under/rank/neo_cargo_customs)
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
