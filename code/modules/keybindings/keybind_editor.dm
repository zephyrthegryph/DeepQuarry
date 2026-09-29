/// The tgui page where a player edits their keybindings. One per client, made on demand.
/datum/keybind_editor
	var/tmp/owner_handle
	/// The profile being edited in the UI.
	var/profile = KEYBIND_PROFILE_DEFAULT

/datum/keybind_editor/New(client/owner)
	src.owner_handle = om_handle(owner)
	profile = owner?.mob?.keybind_profile() || KEYBIND_PROFILE_DEFAULT

// clears the client's cached editor (clients aren't datums).
DECLARE_REF(/datum/keybind_editor, "owner_handle", BACK_HANDLE, "keybind_editor")

/client/var/tmp/datum/keybind_editor/keybind_editor

/client/verb/edit_keybindings()
	set name = "Keybindings"
	set category = "OOC.Settings"
	set desc = "Rebind keys and choose what right-click does."

	if(!prefs)
		return
	if(!keybind_editor)
		keybind_editor = new(src)
	keybind_editor.tgui_interact(mob)

DECLARE_UI_STATE(/datum/keybind_editor, GLOB.tgui_always_state)

DECLARE_UI(/datum/keybind_editor, "KeybindingEditor")

/datum/keybind_editor/tgui_static_data(mob/user)
	var/list/bindings = list()
	var/show_admin = check_rights_for(owner(), R_HOLDER)
	for(var/id in GLOB.keybindings)
		var/datum/keybinding/binding = GLOB.keybindings[id]
		if(binding.category == KEYBIND_CAT_ADMIN && !show_admin)
			continue
		bindings += list(list(
			"id" = binding.id,
			"name" = binding.name,
			"category" = binding.category,
			"command" = binding.command,
		))
	return list(
		"bindings" = bindings,
		"profiles" = list(
			list("id" = KEYBIND_PROFILE_DEFAULT, "name" = "Default"),
			list("id" = KEYBIND_PROFILE_ROBOT, "name" = "Cyborg"),
		),
		"right_click_options" = list(
			list("id" = INPUT_ACTION_MENU, "name" = "Menu (the interaction menu)"),
			list("id" = INPUT_ACTION_ALTERNATE, "name" = "Alternate (same as Alt-click)"),
		),
		"max_keys" = KEYBIND_MAX_KEYS,
	)

UI_DATA_REPLACE(/datum/keybind_editor, "merge:ui_data_datum_keybind_editor{}")

/// The computed part of /datum/keybind_editor's window data (declared on its UI_DATA row).
/datum/keybind_editor/proc/ui_data_datum_keybind_editor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/overrides = owner()?.prefs?.key_bindings
	var/list/keys = list()
	var/list/customised = list()
	var/list/profile_overrides = LAZYACCESS(overrides, profile)
	for(var/id in GLOB.keybindings)
		keys[id] = keybinding_keys(GLOB.keybindings[id], profile, overrides)
		if(profile_overrides && (id in profile_overrides))
			customised += id
	return list(
		"profile" = profile,
		"keys" = keys,
		"customised" = customised,
		"right_click" = owner()?.right_click_binding(),
	)

/datum/keybind_editor/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/datum/preferences/prefs = owner()?.prefs
	if(!prefs)
		return FALSE
	return TRUE

UI_ACT(/datum/keybind_editor, "set_profile", ui_act_set_profile, UI_ARG_TEXT("profile"))
UI_ACT_PROC(/datum/keybind_editor, ui_act_set_profile)
	if(params["profile"] in KEYBIND_PROFILES)
		profile = params["profile"]
	return TRUE

UI_ACT(/datum/keybind_editor, "set_right_click", ui_act_set_right_click, UI_ARG_TEXT("binding"))
UI_ACT_PROC(/datum/keybind_editor, ui_act_set_right_click)
	var/datum/preferences/prefs = owner()?.prefs
	var/binding = params["binding"]
	if(!(binding in RIGHT_CLICK_BINDINGS))
		return
	prefs.right_click_binding = binding
	save_and_apply()
	return TRUE

UI_ACT(/datum/keybind_editor, "bind", ui_act_bind, UI_ARG_TEXT("id"), UI_ARG_TEXT("key"))
UI_ACT_PROC(/datum/keybind_editor, ui_act_bind)
	var/datum/preferences/prefs = owner()?.prefs
	var/datum/keybinding/binding = GLOB.keybindings[params["id"]]
	var/key = sanitize_keybind_key(params["key"])
	if(!binding || !key)
		return
	var/list/keys = keybinding_keys(binding, profile, prefs.key_bindings)
	if(key in keys)
		return TRUE
	if(length(keys) >= KEYBIND_MAX_KEYS)
		to_chat(owner(), span_warning("[binding.name] already has [KEYBIND_MAX_KEYS] keys. Remove one first."))
		return TRUE
	// A key does one thing per profile: take it off any other binding first.
	for(var/other_id in GLOB.keybindings)
		var/datum/keybinding/other = GLOB.keybindings[other_id]
		if(other == binding)
			continue
		var/list/other_keys = keybinding_keys(other, profile, prefs.key_bindings)
		if(key in other_keys)
			other_keys -= key
			set_keys(prefs, other, other_keys)
			to_chat(owner(), span_notice("[key] was moved from [other.name]."))
	keys += key
	set_keys(prefs, binding, keys)
	save_and_apply()
	return TRUE

UI_ACT(/datum/keybind_editor, "unbind", ui_act_unbind, UI_ARG_TEXT("id"), UI_ARG_TEXT("key"))
UI_ACT_PROC(/datum/keybind_editor, ui_act_unbind)
	var/datum/preferences/prefs = owner()?.prefs
	var/datum/keybinding/binding = GLOB.keybindings[params["id"]]
	if(!binding)
		return
	var/list/keys = keybinding_keys(binding, profile, prefs.key_bindings)
	keys -= params["key"]
	set_keys(prefs, binding, keys)
	save_and_apply()
	return TRUE

UI_ACT(/datum/keybind_editor, "reset", ui_act_reset, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/keybind_editor, ui_act_reset)
	var/datum/preferences/prefs = owner()?.prefs
	var/datum/keybinding/binding = GLOB.keybindings[params["id"]]
	if(!binding)
		return
	var/list/profile_overrides = LAZYACCESS(prefs.key_bindings, profile)
	if(profile_overrides)
		profile_overrides -= binding.id
		if(!length(profile_overrides))
			prefs.key_bindings -= profile
	if(!length(prefs.key_bindings))
		prefs.key_bindings = null
	save_and_apply()
	return TRUE

UI_ACT(/datum/keybind_editor, "reset_all", ui_act_reset_all)
UI_ACT_PROC(/datum/keybind_editor, ui_act_reset_all)
	var/datum/preferences/prefs = owner()?.prefs
	if(prefs.key_bindings)
		prefs.key_bindings -= profile
		if(!length(prefs.key_bindings))
			prefs.key_bindings = null
	save_and_apply()
	return TRUE

/// Stores a binding's keys for the edited profile. Keys equal to the defaults drop the override.
/datum/keybind_editor/proc/set_keys(datum/preferences/prefs, datum/keybinding/binding, list/keys)
	var/list/defaults = binding.defaults_for(profile)
	var/same_as_default = length(defaults) == length(keys)
	if(same_as_default)
		for(var/i in 1 to length(keys))
			if(defaults[i] != keys[i])
				same_as_default = FALSE
				break
	if(same_as_default)
		var/list/profile_overrides = LAZYACCESS(prefs.key_bindings, profile)
		if(profile_overrides)
			profile_overrides -= binding.id
			if(!length(profile_overrides))
				prefs.key_bindings -= profile
		if(!length(prefs.key_bindings))
			prefs.key_bindings = null
		return
	LAZYINITLIST(prefs.key_bindings)
	LAZYINITLIST(prefs.key_bindings[profile])
	var/list/profile_overrides = prefs.key_bindings[profile]
	profile_overrides[binding.id] = keys.Copy()

/datum/keybind_editor/proc/save_and_apply()
	var/datum/preferences/prefs = owner()?.prefs
	if(!prefs)
		return
	prefs.save_preferences()
	log_input("Keybindings: [owner().key] changed their [profile] bindings.")
	owner().apply_keybindings(force = TRUE)

DECLARE_REF(/client, "keybind_editor", OWNED, null)

/// LC-refs: the owner this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/keybind_editor/proc/owner() as /client
	return om_resolve(owner_handle)
