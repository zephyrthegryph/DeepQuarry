// Body markings composite editor.
//
// Wire actions:
//   "add"           { marking: "MarkingName" }
//   "remove"        { marking: "MarkingName" }
//   "move_up"       { marking: "..." }
//   "move_down"     { marking: "..." }
//   "set_color"     { marking, color }
//   "set_zone_color" { marking, zone, color }
//   "toggle_zone"   { marking, zone, on }
//   "toggle_all"    { marking, on }

/datum/preference_editor/body_markings
	key = "body_markings"
	category = "appearance"
	group = "markings"
	sort_order = 100
	display_name = "Body Markings"
	pref_keys = list("body_markings")

/datum/preference_editor/body_markings/build_ui_data(datum/preferences/preferences)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings) || list()
	var/list/payload = list()
	for(var/M in markings)
		payload[M] = markings[M]
	return list("markings" = payload)

/datum/preference_editor/body_markings/build_ui_static_data(datum/preferences/preferences)
	var/list/styles = list()
	for(var/path in GLOB.body_marking_styles_list)
		var/datum/sprite_accessory/marking/S = GLOB.body_marking_styles_list[path]
		// expose icon ref + the per-zone state so the React side can render a
		// colorized preview via ColorizedImage. icon_state is the BP_TORSO variant by
		// default; the front-end can swap zones if it wants.
		var/icon_state = S.icon_state
		if(LAZYLEN(S.body_parts))
			icon_state += "-[S.body_parts[1]]"
		styles[path] = list(
			"name" = S.name,
			"body_parts" = S.body_parts || list(),
			"icon" = "[REF(S.icon)]",
			"icon_state" = icon_state,
		)
	return list("available_styles" = styles)

/datum/preference_editor/body_markings/proc/ui_act_add(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	var/M = params["marking"]
	if(!M || (M in markings) || !(M in GLOB.body_marking_styles_list))
		return PREF_UPDATE_REJECTED
	markings[M] = preferences.mass_edit_marking_list(M)
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/body_markings/proc/ui_act_remove(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	markings -= params["marking"]
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/body_markings/proc/ui_act_move_up(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	var/start = markings.Find(params["marking"])
	if(!start)
		return PREF_UPDATE_REJECTED
	if(start != 1)
		moveElement(markings, start, start - 1)
	else
		moveElement(markings, start, markings.len + 1)
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/body_markings/proc/ui_act_move_down(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	var/start = markings.Find(params["marking"])
	if(!start)
		return PREF_UPDATE_REJECTED
	if(start != markings.len)
		moveElement(markings, start, start + 2)
	else
		moveElement(markings, start, 1)
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/body_markings/proc/ui_act_set_color(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	// open BYOND's color picker dialog. The client sends just the marking
	// key; we prompt the user, sanitize, then apply across all zones of the marking.
	var/M = params["marking"]
	if(!(M in markings))
		return PREF_UPDATE_REJECTED
	var/seed = "#FFFFFF"
	if(islist(markings[M]) && length(markings[M]))
		for(var/zone in markings[M])
			if(markings[M][zone]["color"])
				seed = markings[M][zone]["color"]
				break
	// The pick lands in marking_color_picked(), which writes and refreshes the UI.
	open_request(src, /datum/prompt/color/prefs/marking, PROC_REF(marking_color_picked), answerer = user, title = "Color picker", question = "Marking color", default = seed, preferences = preferences, marking = M)
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/body_markings/proc/ui_act_set_zone_color(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	var/M = params["marking"]
	var/zone = params["zone"]
	if(!(M in markings) || !islist(markings[M]) || !(zone in markings[M]))
		return PREF_UPDATE_REJECTED
	var/seed = markings[M][zone]["color"] || "#FFFFFF"
	open_request(src, /datum/prompt/color/prefs/marking, PROC_REF(zone_color_picked), answerer = user, title = "Color picker", question = "Zone color: [zone]", default = seed, preferences = preferences, marking = M, zone = zone)
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/body_markings/proc/ui_act_toggle_zone(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	var/M = params["marking"]
	var/zone = params["zone"]
	if(!(M in markings) || !islist(markings[M]) || !(zone in markings[M]))
		return PREF_UPDATE_REJECTED
	markings[M][zone]["on"] = !markings[M][zone]["on"]
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/body_markings/proc/ui_act_toggle_all(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	var/M = params["marking"]
	var/on = params["on"]
	if(!(M in markings))
		return PREF_UPDATE_REJECTED
	markings[M] = preferences.mass_edit_marking_list(M, TRUE, FALSE, markings[M], on = on)
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	return PREF_UPDATE_ACCEPTED

/// A colour for a preference, picked from the character setup UI. Re-checked on the answer:
/// the picker's prefs are still the ones being edited (a character swap mid-pick must not write
/// to the wrong /datum/preferences). The answer proc writes and refreshes the UI itself.
/datum/prompt/color/prefs
	timeout = 0
	var/datum/preferences/preferences

CAPABILITIES(/datum/prompt/color/prefs)
	ref_one(nameof(preferences), /datum/preferences)

/datum/prompt/color/prefs/prepare(datum/act/A)
	..()
	var/datum/preferences/captured_preferences = preferences
	rel_clear(src, nameof(preferences))
	rel_set(src, nameof(preferences), captured_preferences)

/datum/prompt/color/prefs/recheck_extra()
	return (!QDELETED(preferences) && answerer.client?.prefs && answerer.client.prefs == preferences) ? null : "prefs changed"

/// A body marking's colour (all zones, or one `zone`). Re-checked: the marking (and zone) still exists.
/datum/prompt/color/prefs/marking
	var/marking
	var/zone

/datum/prompt/color/prefs/marking/recheck_extra()
	. = ..()
	if(.)
		return
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!(marking in markings) || (zone && (!islist(markings[marking]) || !(zone in markings[marking]))))
		return "marking gone"

/datum/preference_editor/body_markings/proc/marking_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/marking/ask = A.answer
	var/datum/preferences/preferences = ask.preferences
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	var/M = ask.marking
	markings[M] = preferences.mass_edit_marking_list(M, FALSE, TRUE, markings[M], color = sanitize_hexcolor(ask.value))
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	SStgui.update_uis(preferences)

/datum/preference_editor/body_markings/proc/zone_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/marking/ask = A.answer
	var/datum/preferences/preferences = ask.preferences
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	markings[ask.marking][ask.zone]["color"] = sanitize_hexcolor(ask.value)
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
	SStgui.update_uis(preferences)

/// /datum/preference_editor/body_markings's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/body_markings/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("add")
			typed = payload_args(src, params, list("marking" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_add(user, typed, preferences, null, action)
		if("remove")
			typed = payload_args(src, params, list("marking" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_remove(user, typed, preferences, null, action)
		if("move_up")
			typed = payload_args(src, params, list("marking" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_move_up(user, typed, preferences, null, action)
		if("move_down")
			typed = payload_args(src, params, list("marking" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_move_down(user, typed, preferences, null, action)
		if("set_color")
			typed = payload_args(src, params, list("marking" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_color(user, typed, preferences, null, action)
		if("set_zone_color")
			typed = payload_args(src, params, list("marking" = null, "zone" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_zone_color(user, typed, preferences, null, action)
		if("toggle_zone")
			typed = payload_args(src, params, list("marking" = schema_text(4096), "zone" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_toggle_zone(user, typed, preferences, null, action)
		if("toggle_all")
			typed = payload_args(src, params, list("marking" = null, "on" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_toggle_all(user, typed, preferences, null, action)
	return ..()
