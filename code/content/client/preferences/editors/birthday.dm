// Birthday picker: month-name and day-number dropdowns over bday_month + bday_day. Only real dates exist.

/datum/preference_editor/birthday
	key = "birthday"
	category = "identity"
	group = "demographics"
	sort_order = 50
	display_name = "Birthday"
	pref_keys = list("bday_month", "bday_day")

TYPE_TABLE_DECLARE(/datum/preference_editor/birthday, get_months, list( \
		"January", "February", "March", "April", "May", "June", \
		"July", "August", "September", "October", "November", "December", \
	))

/// The wire shape of /datum/preference_editor/birthday's build_ui_data() (an empty assoc list encodes as [] in JSON).
UI_SCHEMA(pref_editor_birthday, row(month = num(), day = num(), max_day_for_month = num()))
/// ...and of its build_ui_static_data().
UI_SCHEMA(pref_editor_birthday_static, row(months = list_of(schema_text())))

/datum/preference_editor/birthday/build_ui_data(datum/preferences/preferences)
	var/month = preferences.read_preference(/datum/preference/numeric/human/bday_month)
	return list(
		"month" = month,
		"day"   = preferences.read_preference(/datum/preference/numeric/human/bday_day),
		"max_day_for_month" = birth_month_days(month),
	)

/datum/preference_editor/birthday/build_ui_static_data(datum/preferences/preferences)
	return list(
		"months" = TYPE_TABLE_GET(src, get_months),
	)

/datum/preference_editor/birthday/proc/ui_act_set_month(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/value = params["value"]
	if(!birth_month_days(value))
		return PREF_UPDATE_REJECTED
	preferences.update_preference_by_type(/datum/preference/numeric/human/bday_month, value)
	// Clamp day to new month's max
	if(preferences.read_preference(/datum/preference/numeric/human/bday_day) > birth_month_days(value))
		preferences.update_preference_by_type(/datum/preference/numeric/human/bday_day, birth_month_days(value))
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/birthday/proc/ui_act_set_day(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/value = params["value"]
	if(!isnum(value) || value < 1 || value != round(value) || value > birth_month_days(preferences.read_preference(/datum/preference/numeric/human/bday_month)))
		return PREF_UPDATE_REJECTED
	preferences.update_preference_by_type(/datum/preference/numeric/human/bday_day, value)
	return PREF_UPDATE_ACCEPTED

/// /datum/preference_editor/birthday's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/birthday/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_month")
			typed = payload_args(src, params, list("value" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_month(user, typed, preferences, null, action)
		if("set_day")
			typed = payload_args(src, params, list("value" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_day(user, typed, preferences, null, action)
	return ..()
