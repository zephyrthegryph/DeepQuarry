/// The tgui page where a player edits their keybindings. One per client, made on demand.
/datum/keybind_editor
	var/client/owner
	/// The profile being edited in the UI.
	var/profile = KEYBIND_PROFILE_DEFAULT

/datum/keybind_editor/New(client/owner)
	src.owner = owner
	profile = owner?.mob?.keybind_profile() || KEYBIND_PROFILE_DEFAULT

/datum/keybind_editor/Destroy()
	if(owner?.keybind_editor == src)
		owner.keybind_editor = null
	owner = null
	return ..()

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

/datum/keybind_editor/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/keybind_editor/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "KeybindingEditor")
		ui.open()

/datum/keybind_editor/tgui_static_data(mob/user)
	var/list/bindings = list()
	var/show_admin = check_rights_for(owner, R_HOLDER)
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

/datum/keybind_editor/tgui_data(mob/user)
	var/list/overrides = owner?.prefs?.key_bindings
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
		"right_click" = owner?.right_click_binding(),
	)

/datum/keybind_editor/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/datum/preferences/prefs = owner?.prefs
	if(!prefs)
		return
	switch(action)
		if("set_profile")
			if(params["profile"] in KEYBIND_PROFILES)
				profile = params["profile"]
			return TRUE
		if("set_right_click")
			var/binding = params["binding"]
			if(!(binding in RIGHT_CLICK_BINDINGS))
				return
			prefs.right_click_binding = binding
			save_and_apply()
			return TRUE
		if("bind")
			var/datum/keybinding/binding = GLOB.keybindings[params["id"]]
			var/key = sanitize_keybind_key(params["key"])
			if(!binding || !key)
				return
			var/list/keys = keybinding_keys(binding, profile, prefs.key_bindings)
			if(key in keys)
				return TRUE
			if(length(keys) >= KEYBIND_MAX_KEYS)
				to_chat(owner, span_warning("[binding.name] already has [KEYBIND_MAX_KEYS] keys. Remove one first."))
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
					to_chat(owner, span_notice("[key] was moved from [other.name]."))
			keys += key
			set_keys(prefs, binding, keys)
			save_and_apply()
			return TRUE
		if("unbind")
			var/datum/keybinding/binding = GLOB.keybindings[params["id"]]
			if(!binding)
				return
			var/list/keys = keybinding_keys(binding, profile, prefs.key_bindings)
			keys -= params["key"]
			set_keys(prefs, binding, keys)
			save_and_apply()
			return TRUE
		if("reset")
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
		if("reset_all")
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
	var/datum/preferences/prefs = owner?.prefs
	if(!prefs)
		return
	prefs.save_preferences()
	log_input("Keybindings: [owner.key] changed their [profile] bindings.")
	owner.apply_keybindings(force = TRUE)
