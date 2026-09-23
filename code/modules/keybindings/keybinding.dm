/**
 * A keybinding maps physical keys to one command (doc/rewrite/interactions.md §3).
 *
 * Records are built once from keybinding_definitions() into GLOB.keybindings.
 * Each record carries default keys per profile (the robot profile reproduces
 * the old "borghotkeymode" macro set, the default profile "hotkeymode").
 * Players override keys per profile in their preferences; the client then
 * writes the resulting macros into the skin's one macro set with winset.
 */
/datum/keybinding
	/// Stable id, used as the preference key.
	var/id
	/// Shown in the editor.
	var/name
	/// KEYBIND_CAT_*, for grouping in the editor.
	var/category
	/// The verb command run when a key is pressed.
	var/command
	/// Optional command run when the key is released (a "KEY+UP" macro).
	var/release_command
	/// Default keys, keyed by KEYBIND_PROFILE_*. A profile missing here has no keys by default.
	var/list/default_keys

/datum/keybinding/New(id, name, category, command, release_command, list/default_keys)
	src.id = id
	src.name = name
	src.category = category
	src.command = command
	src.release_command = release_command
	src.default_keys = default_keys

/// The keys this binding has by default in a profile.
/datum/keybinding/proc/defaults_for(profile)
	var/list/keys = LAZYACCESS(default_keys, profile)
	return keys ? keys.Copy() : list()

GLOBAL_LIST_INIT(keybindings, init_keybindings())

/// Builds GLOB.keybindings: id -> /datum/keybinding, in definition order.
/proc/init_keybindings()
	var/list/bindings = list()
	for(var/list/row as anything in keybinding_definitions())
		var/datum/keybinding/binding = new(arglist(row))
		if(bindings[binding.id])
			stack_trace("Duplicate keybinding id [binding.id]")
			continue
		bindings[binding.id] = binding
	return bindings

/// Normalises a key name typed or captured by a player. Returns null if it is not a valid BYOND macro name.
/proc/sanitize_keybind_key(key)
	if(!istext(key))
		return null
	key = uppertext(trimtext(key))
	if(!length(key) || length(key) > KEYBIND_MAX_KEY_LENGTH)
		return null
	var/static/regex/valid_key = regex(@"^[A-Z0-9]+(\+[A-Z0-9]+)*$")
	if(!valid_key.Find(key))
		return null
	// The +UP suffix is generated from release_command; players bind the press.
	if(findtext(key, "+UP", -3))
		return null
	return key

/**
 * The keys a binding has for a profile, applying the player's overrides.
 *
 * overrides is the preference list: profile -> (binding id -> list of keys).
 * A binding present in overrides with an empty list is unbound.
 */
/proc/keybinding_keys(datum/keybinding/binding, profile, list/overrides)
	var/list/profile_overrides = LAZYACCESS(overrides, profile)
	if(profile_overrides && (binding.id in profile_overrides))
		var/list/keys = profile_overrides[binding.id]
		return islist(keys) ? keys.Copy() : list()
	return binding.defaults_for(profile)

/**
 * Every macro a profile produces: a list of list(key, command) pairs, including
 * the generated "KEY+UP" release macros. This is exactly what the client winsets.
 */
/proc/keybinding_macros(profile, list/overrides)
	var/list/macros = list()
	for(var/id in GLOB.keybindings)
		var/datum/keybinding/binding = GLOB.keybindings[id]
		for(var/key in keybinding_keys(binding, profile, overrides))
			macros += list(list(key, binding.command))
			if(binding.release_command)
				macros += list(list("[key]+UP", binding.release_command))
	return macros

/// Does any interaction-category binding have a key in this profile? Hover tracking is only needed then.
/proc/keybinding_profile_uses_hover(profile, list/overrides)
	for(var/id in GLOB.keybindings)
		var/datum/keybinding/binding = GLOB.keybindings[id]
		if(binding.category != KEYBIND_CAT_INTERACTION)
			continue
		if(length(keybinding_keys(binding, profile, overrides)))
			return TRUE
	return FALSE

/// Cleans a saved key_bindings preference. Drops unknown profiles, unknown ids and invalid keys.
/proc/sanitize_keybinding_overrides(list/overrides)
	if(!islist(overrides))
		return null
	var/list/clean = list()
	for(var/profile in overrides)
		if(!(profile in KEYBIND_PROFILES))
			continue
		var/list/profile_overrides = overrides[profile]
		if(!islist(profile_overrides))
			continue
		var/list/clean_profile = list()
		for(var/id in profile_overrides)
			if(!GLOB.keybindings[id])
				continue
			var/list/keys = profile_overrides[id]
			var/list/clean_keys = list()
			if(islist(keys))
				for(var/key in keys)
					var/clean_key = sanitize_keybind_key(key)
					if(clean_key && !(clean_key in clean_keys) && length(clean_keys) < KEYBIND_MAX_KEYS)
						clean_keys += clean_key
			clean_profile[id] = clean_keys
		if(length(clean_profile))
			clean[profile] = clean_profile
	return length(clean) ? clean : null

/// Which keybinding profile this mob's player gets by default.
/mob/proc/keybind_profile()
	return KEYBIND_PROFILE_DEFAULT

/mob/living/silicon/robot/keybind_profile()
	return KEYBIND_PROFILE_ROBOT

/// Input-layer debug logging: bindings applied, rebinds, category keys.
/proc/log_input(text, list/data)
	logger.Log(LOG_CATEGORY_DEBUG, text, data)
