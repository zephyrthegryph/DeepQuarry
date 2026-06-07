// DQAdd — Antagonist opt-in editor. be_special is a bitfield of BE_* flags, one bit per
// antag role the player is willing to be considered for. Auto-render can't render this,
// so we expose each flag as its own toggle.

/datum/preference_editor/antag_optin
	key = "antag_optin"
	category = "antag"
	sort_order = 5
	display_name = "Antagonist Opt-Ins"
	pref_keys = list("be_special")

/// Display-friendly labels for every BE_* flag. Order here is the order shown in the UI.
/datum/preference_editor/antag_optin/proc/get_flag_table()
	var/static/list/L = list(
		list("key" = "traitor",      "bit" = BE_TRAITOR,      "label" = "Traitor"),
		list("key" = "operative",    "bit" = BE_OPERATIVE,    "label" = "Nuclear Operative"),
		list("key" = "changeling",   "bit" = BE_CHANGELING,   "label" = "Changeling"),
		list("key" = "wizard",       "bit" = BE_WIZARD,       "label" = "Wizard"),
		list("key" = "malf",         "bit" = BE_MALF,         "label" = "Malfunctioning AI"),
		list("key" = "rev",          "bit" = BE_REV,          "label" = "Revolutionary"),
		list("key" = "alien",        "bit" = BE_ALIEN,        "label" = "Xenomorph"),
		list("key" = "cultist",      "bit" = BE_CULTIST,      "label" = "Cultist"),
		list("key" = "renegade",     "bit" = BE_RENEGADE,     "label" = "Renegade"),
		list("key" = "ninja",        "bit" = BE_NINJA,        "label" = "Space Ninja"),
		list("key" = "raider",       "bit" = BE_RAIDER,       "label" = "Raider"),
		list("key" = "plant",        "bit" = BE_PLANT,        "label" = "Diona Plant"),
		list("key" = "loyalist",     "bit" = BE_LOYALIST,     "label" = "Loyalist"),
		list("key" = "pai",          "bit" = BE_PAI,          "label" = "Personal AI"),
		list("key" = "lostdrone",    "bit" = BE_LOSTDRONE,    "label" = "Lost Drone"),
		list("key" = "maintcritter", "bit" = BE_MAINTCRITTER, "label" = "Maintenance Critter"),
		list("key" = "corgi",        "bit" = BE_CORGI,        "label" = "Corgi"),
		list("key" = "cursedsword",  "bit" = BE_CURSEDSWORD,  "label" = "Cursed Sword"),
		list("key" = "survivor",     "bit" = BE_SURVIVOR,     "label" = "Survivor"),
		list("key" = "event",        "bit" = BE_EVENT,        "label" = "Event Roles"),
	)
	return L

/datum/preference_editor/antag_optin/build_ui_data(datum/preferences/preferences)
	var/value = preferences.read_preference(/datum/preference/numeric/human/be_special)
	var/list/state = list()
	for(var/list/row in get_flag_table())
		state[row["key"]] = (value & row["bit"]) ? TRUE : FALSE
	return list("flags" = state)

/datum/preference_editor/antag_optin/build_ui_static_data(datum/preferences/preferences)
	var/list/labels = list()
	for(var/list/row in get_flag_table())
		labels[row["key"]] = row["label"]
	return list("labels" = labels)

/datum/preference_editor/antag_optin/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	if(action != "toggle_flag")
		return PREF_UPDATE_UNCHANGED
	var/key = params["flag"]
	var/bit
	for(var/list/row in get_flag_table())
		if(row["key"] == key)
			bit = row["bit"]
			break
	if(!bit)
		return PREF_UPDATE_REJECTED
	var/current = preferences.read_preference(/datum/preference/numeric/human/be_special)
	current ^= bit
	preferences.update_preference_by_type(/datum/preference/numeric/human/be_special, current)
	return PREF_UPDATE_ACCEPTED
