// DQAdd — NIF status panel (read-only display in the Character Setup UI).
// In-round purchase/install of NIFsoft happens through the NIF item's own UI; this editor
// just shows whether the character has a NIF saved and what type/durability.

/datum/preference_editor/nif_status
	key = "nif_status"
	category = "game"
	group = "nif"
	sort_order = 10
	display_name = "NIF Status"
	pref_keys = list("nif_path", "nif_durability", "nif_savedata")

/datum/preference_editor/nif_status/build_ui_data(datum/preferences/preferences)
	var/obj/item/nif/nif_path = preferences.read_preference(/datum/preference/nif_path)
	return list(
		"installed" = ispath(nif_path),
		"nif_type" = nif_path ? "[nif_path]" : null,
		"display_name" = nif_path ? initial(nif_path.name) : null,
		"durability" = preferences.read_preference(/datum/preference/numeric/nif_durability),
	)

/datum/preference_editor/nif_status/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	return PREF_UPDATE_UNCHANGED
