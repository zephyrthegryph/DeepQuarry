// DQAdd — Persistence settings editor. persistence_settings is a bitfield of PERSIST_*
// flags (SPAWN/WEIGHT/ORGANS/MARKINGS/SIZE). The auto-renderer can't show a bitfield as
// anything useful, so we expose each flag as its own checkbox.

/datum/preference_editor/persistence
	key = "persistence"
	category = "game"
	group = "persistence"
	sort_order = 5
	display_name = "Persistence"
	pref_keys = list("persistence_settings")

/datum/preference_editor/persistence/build_ui_data(datum/preferences/preferences)
	var/value = preferences.read_preference(/datum/preference/numeric/human/persistence_settings)
	return list(
		"flags" = list(
			"spawn"    = (value & PERSIST_SPAWN)    ? TRUE : FALSE,
			"weight"   = (value & PERSIST_WEIGHT)   ? TRUE : FALSE,
			"organs"   = (value & PERSIST_ORGANS)   ? TRUE : FALSE,
			"markings" = (value & PERSIST_MARKINGS) ? TRUE : FALSE,
			"size"     = (value & PERSIST_SIZE)     ? TRUE : FALSE,
		),
	)

/datum/preference_editor/persistence/build_ui_static_data(datum/preferences/preferences)
	return list(
		"labels" = list(
			"spawn"    = "Carry spawn point between rounds",
			"weight"   = "Carry weight between rounds",
			"organs"   = "Carry organ status (amputations, augments) between rounds",
			"markings" = "Carry markings between rounds",
			"size"     = "Carry size between rounds",
		),
	)

/datum/preference_editor/persistence/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	if(action != "toggle_flag")
		return PREF_UPDATE_UNCHANGED
	var/flag_name = params["flag"]
	var/bit
	switch(flag_name)
		if("spawn")    bit = PERSIST_SPAWN
		if("weight")   bit = PERSIST_WEIGHT
		if("organs")   bit = PERSIST_ORGANS
		if("markings") bit = PERSIST_MARKINGS
		if("size")     bit = PERSIST_SIZE
		else           return PREF_UPDATE_REJECTED
	var/current = preferences.read_preference(/datum/preference/numeric/human/persistence_settings)
	current ^= bit
	preferences.update_preference_by_type(/datum/preference/numeric/human/persistence_settings, current)
	return PREF_UPDATE_ACCEPTED
