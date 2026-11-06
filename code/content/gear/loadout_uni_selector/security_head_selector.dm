/datum/gear/uniform/security_head_selector
	display_name = "Security - Head's Uniforms"
	description = "Select from a range of outfits available to all Heads of Security."
	allowed_roles = list(JOB_HEAD_OF_SECURITY)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/head_of_security/corp
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/security_head_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/head_of_security/skirt,
		"corporate"=/obj/item/clothing/under/rank/head_of_security/corp,
		"formal, navy"=/obj/item/clothing/under/rank/head_of_security/navyblue,
		"formal, tan"=/obj/item/clothing/under/rank/head_of_security/tan,
		"voidsuit underlayer"=/obj/item/clothing/under/undersuit/sec/hos,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_hos_red,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_hos_red_skirt,
		"TG&C turtleneck"=/obj/item/clothing/under/rank/neo_hos_blackred,
		"TG&C turtleneck & skirt"=/obj/item/clothing/under/rank/neo_hos_blackred_skirt,
		"TG&C parade uniform"=/obj/item/clothing/under/rank/neo_hos_parade,
		"TG&C parade uniform, feminine"=/obj/item/clothing/under/rank/neo_hos_parade_fem,
		"TG&C blue"=/obj/item/clothing/under/rank/neo_hos_blue,
		"TG&C blue turtleneck"=/obj/item/clothing/under/rank/neo_hos_blackblue,
		"TG&C blue turtleneck & skirt"=/obj/item/clothing/under/rank/neo_hos_blackblue_skirt,
		"TG&C blue parade uniform"=/obj/item/clothing/under/rank/neo_hos_parade_blue,
		"TG&C blue parade uniform, feminine"=/obj/item/clothing/under/rank/neo_hos_parade_blue_fem,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/hos
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
