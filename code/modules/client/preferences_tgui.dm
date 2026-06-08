/datum/preferences
	COOLDOWN_DECLARE(ui_refresh_cooldown)

/datum/preferences/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	// build the base64 preview assets before tgui opens so the
	// initial static_data includes them. update_preview_icon → update_character_previews
	// flattens the mannequin into 4 direction PNGs + BG PNG via icon2base64.
	if(!character_preview_b64)
		try
			update_preview_icon()
		catch(var/exception/e)
			stack_trace("preview_icon build at tgui_interact: [e.name] at [e.file]:[e.line]")

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PreferencesMenu", "Preferences")
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/preferences/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/preferences/tgui_status(mob/user, datum/tgui_state/state)
	return user.client == client ? STATUS_INTERACTIVE : STATUS_CLOSE

/datum/preferences/ui_assets(mob/user)
	var/list/assets = list(
		get_asset_datum(/datum/asset/simple/preferences),
		get_asset_datum(/datum/asset/spritesheet/preferences),
		get_asset_datum(/datum/asset/json/preferences),
	)

	if(GLOB.asset_datums[/datum/asset/spritesheet_batched/pai_icons])
		assets += get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)

	for (var/datum/preference_middleware/preference_middleware as anything in middleware)
		assets += preference_middleware.get_ui_assets()

	return assets

/datum/preferences/tgui_data(mob/user)
	var/list/data = list()

	if(tainted_character_profiles)
		data["character_profiles"] = create_character_profiles()
		tainted_character_profiles = FALSE

	data["character_preferences"] = compile_character_preferences(user)

	data["active_slot"] = default_slot
	data["saved_notification"] = saved_notification

	// preview assets ship in ui_data so they reach React via the
	// normal polling channel (send_update — ui_data only) instead of via
	// send_full_update (ui_data + static_data + heavy editor catalogs).
	// Posting preview rebuilds through send_full_update was reconciling the
	// entire React tree on every pref edit, which caused interactable
	// elements under the pointer to briefly unmount and the cursor to
	// flicker between pointer / default. Catalogs stay in static_data;
	// preview lives here. The bytes round-trip every poll tick (~50 KB
	// when populated) but only re-render PreviewPane in React.
	if(character_preview_b64)
		data["character_preview_assets"] = character_preview_b64

	for(var/datum/preference_middleware/preference_middleware as anything in middleware)
		data += preference_middleware.get_ui_data(user)

	return data

/datum/preferences/tgui_static_data(mob/user)
	var/list/data = list()

	data["character_profiles"] = create_character_profiles()

	// preview assets now ship in ui_data (see /datum/preferences/tgui_data).
	// data["overflow_role"] = SSjob.get_jobType(SSjob.overflow_role).title

	data["window"] = current_window

	for(var/datum/preference_middleware/preference_middleware as anything in middleware)
		data += preference_middleware.get_ui_static_data(user)

	return data

/datum/preferences/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		// Slot / persistence actions
		if("load")
			if(!IsGuestKey(ui.user.key))
				open_load_dialog(ui.user)
			return TRUE
		if("save")
			save_character()
			save_preferences()
			saved_notification = TRUE
			VARSET_IN(src, saved_notification, FALSE, 1 SECONDS)
			return TRUE
		if("reload")
			load_preferences(TRUE)
			load_character()
			client.prefs_vr.load_vore()
			sanitize_preferences()
			return TRUE
		if("resetslot")
			if(!isnewplayer(ui.user))
				to_chat(ui.user, span_userdanger("You can't change your character slot while being in round."))
			if("Yes" != tgui_alert(ui.user, "This will reset the current slot. Continue?", "Reset current slot?", list("No", "Yes")))
				return FALSE
			if("Yes" != tgui_alert(ui.user, "Are you completely sure that you want to reset this character slot?", "Reset current slot?", list("No", "Yes")))
				return FALSE
			reset_slot()
			sanitize_preferences()
			return TRUE
		if("copy")
			if(!isnewplayer(ui.user))
				to_chat(ui.user, span_userdanger("You can't change your character slot while being in round."))
			if(!IsGuestKey(ui.user.key))
				open_copy_dialog(ui.user)
			return TRUE
		if("game_prefs")
			ui.user.client.game_options()
			return TRUE
		if("refresh_character_preview")
			if(!COOLDOWN_FINISHED(src, ui_refresh_cooldown))
				return FALSE
			update_preview_icon()
			update_tgui_static_data(ui.user)
			COOLDOWN_START(src, ui_refresh_cooldown, 5 SECONDS)
			return TRUE
		// Cycle Background flips bgstate to the next choice and re-renders the
		// preview assets so the new BG shows up immediately via the next static_data push.
		if("cycle_background")
			var/datum/preference/text/human/bgstate/bg = GLOB.preference_entries[/datum/preference/text/human/bgstate]
			if(bg && length(bg.bgstate_choices))
				var/current = read_preference(/datum/preference/text/human/bgstate) || bg.bgstate_choices[1]
				var/idx = bg.bgstate_choices.Find(current)
				idx = (idx % bg.bgstate_choices.len) + 1
				update_preference_by_type(/datum/preference/text/human/bgstate, bg.bgstate_choices[idx])
				update_preview_icon()
				update_tgui_static_data(ui.user)
			return TRUE

		// Pref-value actions
		if("set_preference")
			var/requested_preference_key = params["preference"]
			var/value = params["value"]

			for(var/datum/preference_middleware/preference_middleware as anything in middleware)
				if(preference_middleware.pre_set_preference(ui.user, requested_preference_key, value))
					return TRUE

			var/datum/preference/requested_preference = GLOB.preference_entries_by_key[requested_preference_key]
			if(isnull(requested_preference))
				return FALSE

			// SAFETY: `update_preference` performs validation checks
			if(!update_preference(requested_preference, value))
				return FALSE

			return TRUE

		if("set_color_preference")
			var/requested_preference_key = params["preference"]

			var/datum/preference/requested_preference = GLOB.preference_entries_by_key[requested_preference_key]
			if(isnull(requested_preference))
				return FALSE

			if(!istype(requested_preference, /datum/preference/color))
				return FALSE

			var/default_value = read_preference(requested_preference.type)

			// Yielding
			var/new_color = tgui_color_picker(
				ui.user,
				"Select new color",
				null,
				default_value || COLOR_WHITE,
			)

			if(!new_color)
				return FALSE

			if(!update_preference(requested_preference, new_color))
				return FALSE

			return TRUE

	for(var/datum/preference_middleware/preference_middleware as anything in middleware)
		. = preference_middleware.tgui_act(action, params, ui, state)
		if(.)
			return

	return FALSE


/datum/preferences/tgui_close(mob/user)
	load_character()
	save_preferences()

/datum/preferences/proc/create_character_profiles()
	var/list/profiles = list()

	for(var/index in 1 to CONFIG_GET(number/character_slots))
		// TODO: It won't be updated in the savefile yet, so just read the name directly
		// if(index == default_slot)
		// 	profiles += read_preference(/datum/preference/name/real_name)
		// 	continue

		var/tree_key = "character[index]"
		var/save_data = savefile.get_entry(tree_key)
		var/name = save_data?["real_name"]

		if(isnull(name))
			profiles += null
			continue

		profiles += name

	return profiles

/datum/preferences/proc/compile_character_preferences(mob/user)
	var/list/preferences = list()

	for(var/datum/preference/preference as anything in get_preferences_in_priority_order())
		if(!preference.is_accessible(src))
			continue

		var/value = read_preference(preference.type)
		var/data = preference.compile_ui_data(user, value)

		LAZYINITLIST(preferences[preference.category])
		preferences[preference.category][preference.savefile_key] = data

	for(var/datum/preference_middleware/preference_middleware as anything in middleware)
		var/list/append_character_preferences = preference_middleware.get_character_preferences(user)
		if(isnull(append_character_preferences))
			continue

		for(var/category in append_character_preferences)
			if(category in preferences)
				preferences[category] += append_character_preferences[category]
			else
				preferences[category] = append_character_preferences[category]

	return preferences
