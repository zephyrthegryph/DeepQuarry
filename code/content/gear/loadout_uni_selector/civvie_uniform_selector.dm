/datum/gear/uniform/civvie_uniform_selector
	display_name = "Civilian - Basic Uniforms"
	description = "Select from a range of uniforms available to all personnel. Includes miscellaneous corporate contractor uniforms."
	path = /obj/item/clothing/under/utility/grey
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/civvie_uniform_selector/New()
	..()
	var/list/selector_uniforms = list(
		"TG&C plain turtleneck"=VARIANT(/obj/item/clothing/under/rank/neo_suspect_turtleneck),
		"TG&C plain turtleneck w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_suspect_turtleskirt),
		"TG&C blue turtleneck"=VARIANT(/obj/item/clothing/under/rank/neo_suspect_turtleneck_blue),
		"TG&C blue turtleneck w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_suspect_turtleskirt_blue),
		"TG&C red turtleneck"=VARIANT(/obj/item/clothing/under/rank/neo_suspicious_turtleneck),
		"TG&C red turtleneck w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_suspicious_turtleskirt),
		"TG&C comfy overalls"=VARIANT(/obj/item/clothing/under/rank/neo_suspect_overalls),
		"TG&C comfy overalls w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_suspect_overalls_skirt),
		"TG&C contractor's suit"=VARIANT(/obj/item/clothing/under/rank/neo_contract),
		"Corporate, Major Bill's uniform"=/obj/item/clothing/under/mbill,
		"Corporate, Aether Atmospherics uniform"=/obj/item/clothing/under/corp/aether,
		"Corporate, Focal Point Energistics uniform"=/obj/item/clothing/under/corp/focal,
		"Corporate, Grayson Manufactories uniform"=/obj/item/clothing/under/corp/grayson,
		"Corporate, Grayson Manufactories jumpsuit"=/obj/item/clothing/under/corp/grayson_jump,
		"Corporate, Kaleidoscope"=/obj/item/clothing/under/corp/kaleidoscope,
		"Corporate, Ward-Takahashi uniform"=/obj/item/clothing/under/corp/wardt,
		"Corporate, Hephaestus Arms uniform"=/obj/item/clothing/under/corp/hephaestus,
		"Corporate, Centauri Provisions uniform"=/obj/item/clothing/under/corp/centauri,
		"Corporate, Morpheus Cyberkinetics uniform"=/obj/item/clothing/under/corp/morpheus,
		"Corporate, Wulf Aeronautics uniform"=/obj/item/clothing/under/corp/wulf,
		"Corporate, Zeng-Hu uniform"=/obj/item/clothing/under/corp/zenghu,
		"Corporate, Xion Manufacturing uniform"=/obj/item/clothing/under/corp/xion,
		"Galactic Survey utility uniform"=/obj/item/clothing/under/gsa,
		"Galactic Survey reinforced uniform"=/obj/item/clothing/under/gsa_work,
		"Utility uniform, black"=/obj/item/clothing/under/utility,
		"Utility uniform, navy"=/obj/item/clothing/under/utility/blue,
		"Utility uniform, grey"=/obj/item/clothing/under/utility/grey,
		"Utility uniform, tan"=/obj/item/clothing/under/utility/tan,
		"Utility uniform, green"=/obj/item/clothing/under/utility/green,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka,
		"TG&C gorka suit (service)"=/obj/item/clothing/under/rank/neo_gorka/service,
		"TG&C gorka suit (civilian)"=/obj/item/clothing/under/rank/neo_gorka/civilian
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
