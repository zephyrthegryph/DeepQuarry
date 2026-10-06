// Flavor text editor. Manages the 9 body-part flavor slots (general/head/face/eyes/
// torso/arms/hands/legs/feet) plus the robot module flavor map.

/// Single source of truth for the body-part flavor slots — shared between the static-data
/// payload and the Topic-validation whitelist so the two can't drift apart.
GLOBAL_LIST_INIT(dq_flavor_zones, list("general", "head", "face", "eyes", "torso", "arms", "hands", "legs", "feet"))

/datum/preference_editor/flavor
	key = "flavor"
	category = "identity"
	group = "flavor"
	sort_order = 50
	display_name = "Flavor Text"
	pref_keys = list("flavor_texts", "flavour_texts_robot")

/datum/preference_editor/flavor/build_ui_data(datum/preferences/preferences)
	// play_mode-derived is_robot flag is passed through so React
	// shows only the body flavor block for humans and only the robot flavor
	// block for cyborgs (avoid having both visible at once when only one
	// applies). pAI mode renders neither (configured via the dedicated
	// pAI fields in the Game tab).
	var/play_mode = preferences.read_preference(/datum/preference/text/human/play_mode) || "human"
	return list(
		"flavor_texts" = preferences.read_preference(/datum/preference/flavor_texts) || list(),
		"flavour_texts_robot" = preferences.read_preference(/datum/preference/flavour_texts_robot) || list(),
		"play_mode" = play_mode,
	)

/datum/preference_editor/flavor/build_ui_static_data(datum/preferences/preferences)
	return list(
		"flavor_zones" = GLOB.dq_flavor_zones,
		"robot_modules" = GLOB.robot_module_types,
	)

/datum/preference_editor/flavor/proc/ui_act_set_flavor(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// Whitelist zone against the static list — a forged Topic could otherwise write
	// arbitrary assoc-list keys into the savefile.
	var/zone = params["zone"]
	if(!(zone in GLOB.dq_flavor_zones))
		return PREF_UPDATE_REJECTED
	var/text = strip_html_simple(params["text"])
	if(istext(text) && length_char(text) > MAX_MESSAGE_LEN)
		text = copytext_char(text, 1, MAX_MESSAGE_LEN + 1)
	var/list/flavor = preferences.read_preference(/datum/preference/flavor_texts) || list()
	flavor[zone] = text
	preferences.update_preference_by_type(/datum/preference/flavor_texts, flavor)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/flavor/proc/ui_act_set_robot_flavor(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/module = params["module"]
	// "Default" is the explicit fallback slot that the React side ships for the
	// generic case; everything else must be a known module type.
	if(module != "Default" && !(module in GLOB.robot_module_types))
		return PREF_UPDATE_REJECTED
	var/text = strip_html_simple(params["text"])
	if(istext(text) && length_char(text) > MAX_MESSAGE_LEN)
		text = copytext_char(text, 1, MAX_MESSAGE_LEN + 1)
	var/list/robot_flavor = preferences.read_preference(/datum/preference/flavour_texts_robot) || list()
	robot_flavor[module] = text
	preferences.update_preference_by_type(/datum/preference/flavour_texts_robot, robot_flavor)
	return PREF_UPDATE_ACCEPTED

/// /datum/preference_editor/flavor's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/flavor/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_flavor")
			typed = payload_args(src, params, list("text" = schema_text(4096), "zone" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_flavor(user, typed, preferences, null, action)
		if("set_robot_flavor")
			typed = payload_args(src, params, list("module" = schema_text(4096), "text" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_robot_flavor(user, typed, preferences, null, action)
	return ..()
