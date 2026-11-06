// The second ear style's colours: one per channel the style draws, written by the Second ears row of the Body table.

/datum/preference_editor/ear_secondary
	key = "ear_secondary"
	category = "appearance"
	group = "ears"
	sort_order = 45
	display_name = "Second ear colours"
	pref_keys = list("ear_secondary_colors")

/datum/preference_editor/ear_secondary/build_ui_data(datum/preferences/preferences)
	return list(
		"colors" = preferences.read_preference(/datum/preference/ear_secondary_colors) || list(),
		"fallback" = first_ear_colors(preferences),
	)

/// What an unset channel draws: the first ear's colour for that channel (get_ears_overlay()).
/datum/preference_editor/ear_secondary/proc/first_ear_colors(datum/preferences/preferences)
	return list(
		lowertext(preferences.read_preference(/datum/preference/color/human/ears_color1)),
		lowertext(preferences.read_preference(/datum/preference/color/human/ears_color2)),
		lowertext(preferences.read_preference(/datum/preference/color/human/ears_color3)),
	)

/// Writes one channel. Channels below it that have no colour yet take the first ear's, which is what they drew.
/datum/preference_editor/ear_secondary/proc/write_channel(datum/preferences/preferences, index, color)
	var/list/colors = preferences.read_preference(/datum/preference/ear_secondary_colors) || list()
	if(!isnum(index) || index < 1 || index > length(GLOB.fancy_sprite_accessory_color_channel_names))
		return PREF_UPDATE_REJECTED
	if(!istext(color) || !findtext(color, GLOB.is_color))
		return PREF_UPDATE_REJECTED
	colors = colors.Copy()
	var/list/fallback = first_ear_colors(preferences)
	while(length(colors) < index)
		colors += fallback[length(colors) + 1]
	colors[index] = lowertext(sanitize_hexcolor(color))
	preferences.update_preference_by_type(/datum/preference/ear_secondary_colors, colors)
	return PREF_UPDATE_ACCEPTED

/datum/prompt/color/prefs/ear_channel
	var/channel

/datum/preference_editor/ear_secondary/proc/channel_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/ear_channel/ask = A.answer
	write_channel(ask.preferences, ask.channel, ask.value)
	SStgui.update_uis(ask.preferences)

/datum/preference_editor/ear_secondary/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_color")
			typed = payload_args(src, params, list("index" = null, "color" = schema_text(16)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return write_channel(preferences, typed["index"], typed["color"])
		if("pick_color")
			typed = payload_args(src, params, list("index" = null))
			if(!typed || !isnum(typed["index"]))
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			var/list/colors = preferences.read_preference(/datum/preference/ear_secondary_colors) || list()
			open_request(src, /datum/prompt/color/prefs/ear_channel, PROC_REF(channel_picked), answerer = user, title = "Color picker", question = "Second ear colour", default = LAZYACCESS(colors, typed["index"]) || "#FFFFFF", preferences = preferences, channel = typed["index"])
			return PREF_UPDATE_UNCHANGED
	return ..()
