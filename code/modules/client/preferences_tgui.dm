/datum/preferences
	COOLDOWN_DECLARE(ui_refresh_cooldown)

/datum/preferences/tgui_status(mob/user, datum/tgui_state/state)
	return user.client == client() ? STATUS_INTERACTIVE : STATUS_CLOSE

/datum/preferences/ui_assets(mob/user)
	var/list/assets = list()
	// The DeepQuarry character editor renders its active category from the compact
	// middleware payload and base64 preview. The legacy preference spritesheet and
	// JSON catalog are only consumed by the game-preferences renderer; sending them
	// on every character-editor cold open was the measured 760 ms asset stall.
	if(current_window != PREFERENCE_TAB_CHARACTER_PREFERENCES)
		assets += get_asset_datum(/datum/asset/simple/preferences)
		assets += get_asset_datum(/datum/asset/spritesheet/preferences)
		assets += get_asset_datum(/datum/asset/json/preferences)

	for (var/datum/preference_middleware/preference_middleware as anything in middleware)
		assets += preference_middleware.get_ui_assets()

	return assets

/datum/preferences/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["active_slot"] = default_slot
	var/list/merged_1 = ui_data_datum_preferences(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/preferences's window data.
/datum/preferences/proc/ui_data_datum_preferences(mob/user, datum/tgui/_ui, datum/tgui_state/_state)
	var/list/data = list()

	if(tainted_character_profiles)
		data["character_profiles"] = create_character_profiles()
		tainted_character_profiles = FALSE

	// DQCharacterSetup consumes dq_values/editor patches below. Building the legacy
	// all-preferences structure for that route duplicated the same work and accounted
	// for another ~650 ms in the first-open trace.
	if(current_window != PREFERENCE_TAB_CHARACTER_PREFERENCES)
		data["character_preferences"] = compile_character_preferences(user)

	data["saved_notification"] = !COOLDOWN_FINISHED(src, saved_notification)

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
		data += preference_middleware.get_ui_data(user, SStgui.get_open_ui(user, src)) // the window the data is for (a pooled window keeps its own versions)

	data["dq_server_profile"] = list(
		"pre_backend_ms" = dq_open_requested_at ? (REALTIMEOFDAY - dq_open_requested_at) * 100 : 0,
		"preview_render_ms" = dq_last_preview_render_ms,
	)
	dq_open_requested_at = null

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

/datum/preferences/proc/ui_act_load(datum/act/op/A)
	var/mob/user = A.actor
	if(!IsGuestKey(user.key))
		open_load_dialog(user)
	return TRUE

/datum/preferences/proc/ui_act_save(datum/act/op/A)
	save_character()
	save_preferences()
	COOLDOWN_START(src, saved_notification, 1 SECONDS)
	return OP_OK

/datum/preferences/proc/ui_act_reload(datum/act/op/A)
	load_preferences(TRUE)
	load_character()
	client().prefs_vr.load_vore()
	sanitize_preferences()
	return OP_OK

/datum/preferences/proc/ui_act_resetslot(datum/act/op/A)
	var/mob/user = A.actor
	if(!isnewplayer(user))
		to_chat(user, span_userdanger("You can't change your character slot while being in round."))
		return FALSE
	if(A.step_value("first") != "Yes" || A.step_value("second") != "Yes")
		return FALSE
	reset_slot()
	sanitize_preferences()
	return TRUE

/// The reset questions open only in the lobby (the handler tells a player in the round why not).
/datum/preferences/proc/slot_reset_open(datum/act/op/A)
	return isnewplayer(A.actor)

/// The second, are-you-sure question opens after a "Yes" to the first.
/datum/preferences/proc/slot_reset_confirmed_once(datum/act/op/A)
	return isnewplayer(A.actor) && A.step_value("first") == "Yes"

/datum/preferences/proc/ui_act_copy(datum/act/op/A)
	var/mob/user = A.actor
	if(!isnewplayer(user))
		to_chat(user, span_userdanger("You can't change your character slot while being in round."))
		return FALSE
	if(!IsGuestKey(user.key))
		open_copy_dialog(user)
	return TRUE

/datum/preferences/proc/ui_act_game_prefs(datum/act/op/A)
	A.actor.client.game_options()
	return OP_OK

/datum/preferences/proc/ui_act_refresh_character_preview(datum/act/op/A)
	var/mob/user = A.actor
	if(!COOLDOWN_FINISHED(src, ui_refresh_cooldown))
		return FALSE
	update_preview_icon()
	update_tgui_static_data(user)
	COOLDOWN_START(src, ui_refresh_cooldown, 5 SECONDS)
	return TRUE
// Cycle Background flips bgstate to the next choice and re-renders the
// preview assets so the new BG shows up immediately via the next static_data push.

/datum/preferences/proc/ui_act_cycle_background(datum/act/op/A)
	var/datum/preference/text/human/bgstate/bg = GLOB.preference_entries[/datum/preference/text/human/bgstate]
	if(bg && length(bg.bgstate_choices))
		var/current = read_preference(/datum/preference/text/human/bgstate) || bg.bgstate_choices[1]
		var/idx = bg.bgstate_choices.Find(current)
		idx = (idx % bg.bgstate_choices.len) + 1
		update_preference_by_type(/datum/preference/text/human/bgstate, bg.bgstate_choices[idx])
		update_preview_icon()
		update_tgui_static_data(A.actor)
	return OP_OK

// Pref-value actions

/datum/preferences/proc/ui_act_set_preference(datum/act/op/A, preference, value_arg)
	var/mob/user = A.actor
	var/requested_preference_key = preference
	var/value = value_arg

	for(var/datum/preference_middleware/preference_middleware as anything in middleware)
		if(preference_middleware.pre_set_preference(user, requested_preference_key, value))
			return TRUE

	var/datum/preference/requested_preference = GLOB.preference_entries_by_key[requested_preference_key]
	if(isnull(requested_preference))
		return FALSE

	// SAFETY: `update_preference` performs validation checks
	if(!update_preference(requested_preference, value))
		return FALSE

	return TRUE

/datum/preferences/proc/ui_act_set_color_preference(datum/act/op/A, preference)
	var/datum/preference/requested_preference = GLOB.preference_entries_by_key[preference]
	if(!istype(requested_preference, /datum/preference/color))
		return FALSE
	var/picked = A.step_value("color")
	if(isnull(picked))
		return FALSE
	return update_preference(requested_preference, picked)

/// The colour picker opens only for a colour preference.
/datum/preferences/proc/color_pref_valid(datum/act/op/A)
	return istype(GLOB.preference_entries_by_key[A.args["preference"]], /datum/preference/color)

/datum/preferences/proc/color_pref_key(datum/act/op/A)
	return A.args["preference"]

/datum/preferences/proc/prefs_self(datum/act/op/A)
	return src

/datum/preferences/proc/color_pref_default(datum/act/op/A)
	var/datum/preference/requested_preference = GLOB.preference_entries_by_key[A.args["preference"]]
	return (requested_preference && read_preference(requested_preference.type)) || COLOR_WHITE



/datum/preferences/tgui_close(mob/user)
	// Edits already persist as they happen: update_preference() ends every change with
	// end_update_batch() → save_character() + save_preferences(), flushing to the savefile
	// at edit time. The old load_character() + save_preferences() here therefore changed no
	// state — load_character() re-read the whole savefile (which already matched the in-memory
	// cache) and re-ran the priority-order read/sanitize loop, and save_preferences() re-wrote
	// already-written player prefs — costing ~2s of synchronous, blocking savefile I/O on the
	// close click. Keep the preview byte cache warm and queue one async straggler-flush.
	SScharacter_setup.queue_preferences_save(src)

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

/datum/prompt/choice/preference_slot_reset
	title = "Reset current slot?"
	choices = list("No", "Yes")
	buttons = TRUE
	timeout = 0

