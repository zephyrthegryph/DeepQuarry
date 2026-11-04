/datum/gear/uniform/site_manager_selector
	display_name = "Command - " + JOB_SITE_MANAGER + "'s Uniforms"
	description = "Select from a range of outfits available to all " + JOB_SITE_MANAGER + "s, and Talon Captains."
	allowed_roles = list(JOB_SITE_MANAGER,JOB_TALON_CAPTAIN)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_captain
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/site_manager_selector/New()
	..()
	var/list/selector_uniforms = list(
		"uniform w/ dress"=/obj/item/clothing/under/dress/dress_cap,
		"voidsuit underlayer"=/obj/item/clothing/under/undersuit/command,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_captain,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_captain_skirt,
		"TG&C utility suit"=/obj/item/clothing/under/rank/neo_commandutil,
		"TG&C black suit"=/obj/item/clothing/under/rank/neo_captain_blacksuit,
		"TG&C parade uniform"=/obj/item/clothing/under/rank/neo_captain_parade,
		"TG&C jumpkilt"=/obj/item/clothing/under/rank/neo_captain_kilt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/command,
		"TG&C black command gorka"=/obj/item/clothing/under/rank/neo_gorka/black_command
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
