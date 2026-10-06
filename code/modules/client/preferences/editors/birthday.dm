// Birthday picker. bday_month + bday_day are numeric 1-12 / 1-31 fields that need
// month-name and day-number dropdowns, not 0-12 / 0-31 sliders.

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

/datum/preference_editor/birthday/proc/days_in_month(month_idx)
	switch(month_idx)
		if(1, 3, 5, 7, 8, 10, 12) return 31
		if(4, 6, 9, 11)           return 30
		if(2)                     return 29  // leap-year-tolerant
	return 31

/datum/preference_editor/birthday/build_ui_data(datum/preferences/preferences)
	var/month = preferences.read_preference(/datum/preference/numeric/human/bday_month) || 0
	var/day   = preferences.read_preference(/datum/preference/numeric/human/bday_day)   || 0
	return list(
		"month" = month,
		"day"   = day,
		"max_day_for_month" = month > 0 ? days_in_month(month) : 31,
	)

/datum/preference_editor/birthday/build_ui_static_data(datum/preferences/preferences)
	return list(
		"months" = TYPE_TABLE_GET(src, get_months),
	)

/datum/preference_editor/birthday/proc/ui_act_set_month(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/value = params["value"]
	if(isnull(value) || value < 0 || value > 12)
		return PREF_UPDATE_REJECTED
	preferences.update_preference_by_type(/datum/preference/numeric/human/bday_month, value)
	// Clamp day to new month's max
	var/day = preferences.read_preference(/datum/preference/numeric/human/bday_day)
	if(value > 0 && day > days_in_month(value))
		preferences.update_preference_by_type(/datum/preference/numeric/human/bday_day, days_in_month(value))
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/birthday/proc/ui_act_set_day(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/value = params["value"]
	if(isnull(value) || value < 0 || value > 31)
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
