// play_mode pref.
//
// Drives whether the character setup UI is configuring a human (organic),
// cyborg, or pAI. Replaces the older /datum/preference/toggle/human/playing_as_robot.
// Storage values: "human" (default), "robot", "pai".
//
// Source of truth is the species picker — selecting "_robot" or "_pai" in the
// SpeciesPicker editor writes this pref via the editor's set_species handler.
// The underlying /datum/preference/choiced/species pref keeps its real organic
// species value (e.g. "Human") so switching back to human mode preserves the
// player's previous species pick.
//
// Filtering happens in /datum/preference_middleware/character_setup based on
// GLOB.dq_robot_mode_hidden_categories / dq_robot_mode_hidden_groups /
// dq_human_mode_hidden_groups, all declared next to the middleware.

/datum/preference/text/human/play_mode
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "play_mode"
	display_label = "Play Mode"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/text/human/play_mode/create_default_value()
	return "human"

/datum/preference/text/human/play_mode/is_valid(value)
	return value == "human" || value == "robot" || value == "pai"

/datum/preference/text/human/play_mode/apply_to_human(mob/living/carbon/human/target, value)
	// UI-only preference. The cyborg/pAI spawn flow is driven by job priority
	// + chargen robot_module/robot_chassis, not by this pref directly.
	return
