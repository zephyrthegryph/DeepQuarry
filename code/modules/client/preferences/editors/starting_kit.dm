// DQAdd — Starting Kit editor. Bundles the small "what you spawn with" prefs
// (headset, backpack, PDA, ringtone, no_jacket toggle, communicator visibility) into a
// single labelled panel instead of letting them auto-render as six unrelated widgets in
// a LabeledList. The underlying prefs are hidden from auto-render via _pref_metadata.dm.

// DQEdit — starting kit after no_jacket deletion: just ringtone + comm visibility.
// Neither is a gear item. Editor stays hidden; actions dispatch from the loadout panel's
// PDA-slot context where these two settings live.

/datum/preference_editor/starting_kit
	key = "starting_kit"
	category = "loadout"
	group = "starting_kit"
	sort_order = 5
	display_name = "Starting Kit"
	hidden = TRUE
	pref_keys = list("ringtone", "communicator_visibility")

/datum/preference_editor/starting_kit/build_ui_data(datum/preferences/preferences)
	return list(
		"ringtone"    = preferences.read_preference(/datum/preference/text/human/ringtone),
		"comm_visible" = preferences.read_preference(/datum/preference/toggle/human/communicator_visibility),
	)

/datum/preference_editor/starting_kit/build_ui_static_data(datum/preferences/preferences)
	var/list/ringtones = list()
	if(GLOB.device_ringtones)
		for(var/key in GLOB.device_ringtones)
			ringtones += key
	return list("ringtone_choices" = ringtones)

/datum/preference_editor/starting_kit/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("set_ringtone")
			var/value = params["value"]
			if(!(value in GLOB.device_ringtones))
				return PREF_UPDATE_REJECTED
			preferences.update_preference_by_type(/datum/preference/text/human/ringtone, value)
			return PREF_UPDATE_ACCEPTED
		if("toggle_comm_visible")
			var/cur = preferences.read_preference(/datum/preference/toggle/human/communicator_visibility)
			preferences.update_preference_by_type(/datum/preference/toggle/human/communicator_visibility, !cur)
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
