/datum/gear/uniform/head_of_personnel_selector
	display_name = "Command - " + JOB_HEAD_OF_PERSONNEL + "'s Uniforms"
	description = "Select from a range of outfits available to all Heads of Personnel."
	allowed_roles = list(JOB_HEAD_OF_PERSONNEL)
	show_roles = FALSE
	path = VARIANT(/obj/item/clothing/under/rank/neo_hop)
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/head_of_personnel_selector/New()
	..()
	var/list/selector_uniforms = list(
		"uniform w/ dress"=/obj/item/clothing/under/dress/dress_hop,
		"HR director"=/obj/item/clothing/under/dress/dress_hr,
		"voidsuit underlayer"=/obj/item/clothing/under/undersuit/command,
		"TG&C command utility"=VARIANT(/obj/item/clothing/under/rank/neo_commandutil),
		"TG&C jumpsuit"=VARIANT(/obj/item/clothing/under/rank/neo_hop),
		"TG&C jumpskirt"=VARIANT(/obj/item/clothing/under/rank/neo_hop_skirt),
		"TG&C parade uniform"=VARIANT(/obj/item/clothing/under/rank/neo_hop_parade_masc),
		"TG&C parade dress"=VARIANT(/obj/item/clothing/under/rank/neo_hop_parade_fem),
		"TG&C turtleneck"=VARIANT(/obj/item/clothing/under/rank/neo_hop_turtle),
		"TG&C turtleneck w/ skirt"=VARIANT(/obj/item/clothing/under/rank/neo_hop_turtle_skirt),
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/command,
		"TG&C black command gorka"=/obj/item/clothing/under/rank/neo_gorka/black_command
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
