// Per-client macros (doc/rewrite/interactions.md §3). The skin ships one empty
// macro set, KEYBIND_MACRO_SET; each client's bindings are written into it with
// winset whenever its profile or preferences change.

/// How many macro elements we created in this client's macro set.
/client/var/tmp/keybind_macro_count = 0
/// The profile whose macros are applied, or null if none are.
/client/var/tmp/keybind_profile_applied
/// Is MouseEntered recorded for this client? Only for screentips or a binding that needs the hovered atom.
/client/var/tmp/hover_tracking = FALSE

/// The player's key overrides (profile -> id -> keys), or null for all defaults.
/client/proc/keybinding_overrides()
	return prefs?.key_bindings

/// What the player bound right-click to.
/client/proc/right_click_binding()
	var/binding = prefs?.right_click_binding
	return (binding in RIGHT_CLICK_BINDINGS) ? binding : INPUT_ACTION_MENU

/**
 * The winset() calls that put `macros` into the skin's macro set, replacing the
 * `old_count` elements made last time: a list of list(control id, params).
 *
 * A macro element is created by naming it as winset()'s control argument with a
 * `parent` param. The single null-control form ("dqkb1.parent=default") only sets
 * params of controls that already exist, so it never created the macros and every
 * key fell through to the client (keys did nothing and the client beeped).
 */
/proc/keybinding_winset_calls(list/macros, old_count)
	. = list()
	// Elements past the new count are detached; the rest are overwritten in place.
	for(var/i in length(macros) + 1 to old_count)
		. += list(list("[KEYBIND_MACRO_PREFIX][i]", "parent=none"))
	for(var/i in 1 to length(macros))
		var/list/macro = macros[i]
		. += list(list("[KEYBIND_MACRO_PREFIX][i]", list2params(list("parent" = KEYBIND_MACRO_SET, "name" = macro[1], "command" = macro[2]))))
	var/list/window = list(
		"mainwindow.macro" = KEYBIND_MACRO_SET,
		"mapwindow.map.right-click" = "true",
		"mapwindow.map.focus" = "true",
	)
	. += list(list(null, list2params(window)))

/**
 * Writes this client's bindings for its mob's profile into the skin.
 * Skips the work when the profile is already applied, unless forced (after a rebind).
 */
/client/proc/apply_keybindings(force = FALSE)
	var/profile = mob?.keybind_profile() || KEYBIND_PROFILE_DEFAULT
	if(!force && keybind_profile_applied == profile)
		return
	var/list/overrides = keybinding_overrides()
	var/list/macros = keybinding_macros(profile, overrides)

	// Right-click always reaches the router: Menu opens the interaction menu,
	// which replaces BYOND's native verb popup.
	for(var/list/call_args as anything in keybinding_winset_calls(macros, keybind_macro_count))
		winset(src, call_args[1], call_args[2])

	keybind_macro_count = length(macros)
	keybind_profile_applied = profile
	set_hover_tracking(keybinding_profile_uses_hover(profile, overrides) || screentips_enabled())
	log_input("Keybindings: applied [length(macros)] macros for [key] (profile [profile], right-click [right_click_binding()]).")

/client/proc/set_hover_tracking(enabled)
	hover_tracking = !!enabled
	tracked_changed(src, nameof(hover_tracking))
	if(!hover_tracking)
		if(mob)
			rel_clear(mob, nameof(/mob::hovered_atom_view))
		clear_screentip()

/// Lists the current bindings in chat. Replaces the old hand-written hotkey help.
/client/verb/hotkeys_help()
	set name = "hotkeys-help"
	set category = VERB_CAT_OOC_RESOURCES

	var/profile = mob?.keybind_profile() || KEYBIND_PROFILE_DEFAULT
	var/list/overrides = keybinding_overrides()
	var/list/lines = list("<b>Your keybindings</b> ([profile == KEYBIND_PROFILE_ROBOT ? "cyborg" : "default"]). Change them with the Keybindings verb.")
	var/last_category
	for(var/id in GLOB.keybindings)
		var/datum/keybinding/binding = GLOB.keybindings[id]
		if(binding.category == KEYBIND_CAT_ADMIN && !check_rights_for(src, R_HOLDER))
			continue
		var/list/keys = keybinding_keys(binding, profile, overrides)
		if(!length(keys))
			continue
		if(binding.category != last_category)
			last_category = binding.category
			lines += "<b>[last_category]</b>"
		lines += "\t[jointext(keys, ", ")] = [binding.name]"
	lines += "<b>Mouse</b>"
	lines += "\tClick = use; Shift+Click = examine; Alt+Click = alternate; Ctrl+Click = pull"
	lines += "\tRight-click = [right_click_binding() == INPUT_ACTION_MENU ? "menu" : "alternate"]"
	to_chat(src, span_purple(jointext(lines, "\n")))
