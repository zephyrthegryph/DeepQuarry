//Cargo

/datum/gear/uniform/quartermaster_selector
	display_name = "Cargo - " + JOB_QUARTERMASTER + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_QUARTERMASTER + "s."
	allowed_roles = list(JOB_QUARTERMASTER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/cargo/jeans
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/quartermaster_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/cargo/skirt,
		"jeans"=/obj/item/clothing/under/rank/cargo/jeans,
		"jeans, feminine cut"=/obj/item/clothing/under/rank/cargo/jeans/female,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_qm,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_qm_skirt,
		"TG&C casualwear"=/obj/item/clothing/under/rank/neo_qm_jacket,
		"TG&C button-up"=/obj/item/clothing/under/rank/neo_qm_white,
		"TG&C button-up w/ skirt"=/obj/item/clothing/under/rank/neo_qm_white_skirt,
		"TG&C turtleneck"=/obj/item/clothing/under/rank/neo_qm_turtle,
		"TG&C turtleneck w/ skirt"=/obj/item/clothing/under/rank/neo_qm_turtle_skirt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/qm,
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
