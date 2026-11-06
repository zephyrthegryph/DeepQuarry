//template for quickly making more, if it's ever needed
/*

/datum/gear/uniform/BLANK_selector
	display_name = "DEPT - BLANK's Uniforms"
	description = "Select from a range of outfits available to all BLANK personnel."
	allowed_roles = list("")
	show_roles = FALSE
	path =
	slot = SLOT_ID_UNIFORM
	sort_category = "Uniforms"
	cost = 2

/datum/gear/uniform/BLANK_selector/New()
	..()
	var/list/selector_uniforms = list(
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
*/

//Command/Specific

/datum/gear/uniform/general_command_selector
	display_name = "Command - Department Head's Uniforms"
	description = "Select from a range of outfits available to all Department Heads, and Talon Captains."
	allowed_roles = list(JOB_SITE_MANAGER,JOB_TALON_CAPTAIN,JOB_HEAD_OF_PERSONNEL,JOB_HEAD_OF_SECURITY,JOB_QUARTERMASTER,JOB_RESEARCH_DIRECTOR,JOB_CHIEF_MEDICAL_OFFICER,JOB_CHIEF_ENGINEER)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_gorka/command
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/general_command_selector/New()
	..()
	var/list/selector_uniforms = list(
		"TG&C utility suit"=VARIANT(/obj/item/clothing/under/rank/neo_commandutil),
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/command,
		"TG&C black command gorka"=/obj/item/clothing/under/rank/neo_gorka/black_command
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
