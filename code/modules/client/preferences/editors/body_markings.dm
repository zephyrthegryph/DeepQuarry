// DQAdd — Body markings composite editor.
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
		// DQAdd — expose icon ref + the per-zone state so the React side can render a
		// colorized preview via ColorizedImage. icon_state is the BP_TORSO variant by
		// default; the front-end can swap zones if it wants.
		var/icon_state = S.icon_state
		if(LAZYLEN(S.body_parts))
			icon_state += "-[S.body_parts[1]]"
		styles[path] = list(
			"name" = S.name,
			"body_parts" = S.body_parts,
			"icon" = "[REF(S.icon)]",
			"icon_state" = icon_state,
		)
	return list("available_styles" = styles)

/datum/preference_editor/body_markings/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		markings = list()
	switch(action)
		if("add")
			var/M = params["marking"]
			if(!M || (M in markings) || !(M in GLOB.body_marking_styles_list))
				return PREF_UPDATE_REJECTED
			markings[M] = preferences.mass_edit_marking_list(M)
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("remove")
			markings -= params["marking"]
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("move_up")
			var/start = markings.Find(params["marking"])
			if(!start)
				return PREF_UPDATE_REJECTED
			if(start != 1)
				moveElement(markings, start, start - 1)
			else
				moveElement(markings, start, markings.len + 1)
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("move_down")
			var/start = markings.Find(params["marking"])
			if(!start)
				return PREF_UPDATE_REJECTED
			if(start != markings.len)
				moveElement(markings, start, start + 2)
			else
				moveElement(markings, start, 1)
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("set_color")
			// DQEdit — open BYOND's color picker dialog. The client sends just the marking
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
			var/picked = tgui_color_picker(user, "Marking color", "Color picker", seed)
			if(!picked)
				return PREF_UPDATE_UNCHANGED
			// tgui_color_picker sleeps — re-verify the prefs are still owned
			// by the same player after it returns. Without this, a char swap
			// mid-pick writes to the wrong /datum/preferences.
			if(!user?.client?.prefs || user.client.prefs != preferences)
				return PREF_UPDATE_UNCHANGED
			var/color = sanitize_hexcolor(picked)
			markings[M] = preferences.mass_edit_marking_list(M, FALSE, TRUE, markings[M], color = color)
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("set_zone_color")
			var/M = params["marking"]
			var/zone = params["zone"]
			if(!(M in markings) || !islist(markings[M]) || !(zone in markings[M]))
				return PREF_UPDATE_REJECTED
			var/seed = markings[M][zone]["color"] || "#FFFFFF"
			var/picked = tgui_color_picker(user, "Zone color: [zone]", "Color picker", seed)
			if(!picked)
				return PREF_UPDATE_UNCHANGED
			// Same post-sleep re-validation as above.
			if(!user?.client?.prefs || user.client.prefs != preferences)
				return PREF_UPDATE_UNCHANGED
			var/color = sanitize_hexcolor(picked)
			markings[M][zone]["color"] = color
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("toggle_zone")
			var/M = params["marking"]
			var/zone = params["zone"]
			if(!(M in markings) || !islist(markings[M]) || !(zone in markings[M]))
				return PREF_UPDATE_REJECTED
			markings[M][zone]["on"] = !markings[M][zone]["on"]
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
		if("toggle_all")
			var/M = params["marking"]
			var/on = text2num(params["on"])
			if(!(M in markings))
				return PREF_UPDATE_REJECTED
			markings[M] = preferences.mass_edit_marking_list(M, TRUE, FALSE, markings[M], on = on)
			preferences.update_preference_by_type(/datum/preference/body_markings, markings)
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
