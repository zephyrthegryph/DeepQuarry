// DQAdd — Cyborg chargen prefs (module + chassis sprite).
//
// robot_module: the human-readable module name (e.g. "Engineering"), keyed
//   against GLOB.robot_modules. Determines what abilities the cyborg has at
//   spawn — no post-spawn popup required (see LateInitialize override in
//   code/modules/mob/living/silicon/robot/cyborg_spawn.dm).
// robot_chassis: the /datum/robot_sprite.name belonging to the chosen module
//   (e.g. "Engiebot"), keyed against SSrobot_sprites.cyborg_sprites_by_module.
//
// Both are PREF_WIDGET_HIDDEN from the auto-renderer — they're driven by the
// RobotChassisPicker editor instead, which gates chassis options on the
// currently-selected module.

/datum/preference/text/human/robot_module
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "robot_module"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/text/human/robot_module/create_default_value()
	return ""

/datum/preference/text/human/robot_module/apply_to_human(mob/living/carbon/human/target, value)
	// Cyborg-spawn-time prefs, not applied to humans.
	return

/datum/preference/text/human/robot_module/is_valid(value)
	if(!istext(value))
		return FALSE
	if(value == "")
		return TRUE
	return value in GLOB.robot_modules

/datum/preference/text/human/robot_chassis
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "robot_chassis"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/text/human/robot_chassis/create_default_value()
	return ""

/datum/preference/text/human/robot_chassis/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/text/human/robot_chassis/is_valid(value)
	return istext(value)
