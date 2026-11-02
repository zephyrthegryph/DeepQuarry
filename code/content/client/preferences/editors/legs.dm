// Legs: one style choice. Normal and digitigrade are the digitigrade pref; a taur body is the tail style it always was.
//
// Wire actions:
//   "set_leg_style" { style }   "plantigrade", "digitigrade", or a taur tail style's name

/datum/preference_editor/legs
	key = "legs"
	category = "appearance"
	hidden = TRUE
	display_name = "Legs"
	pref_keys = list("digitigrade", "tail_style")

/// The tail style named `name`, if it is a taur body.
/proc/dq_taur_style_named(name)
	for(var/key in GLOB.tail_styles_list)
		var/datum/sprite_accessory/S = GLOB.tail_styles_list[key]
		if(istype(S) && S.name == name && istaurtail(S))
			return S

/// Whether this character's saved tail is a taur body.
/datum/preferences/proc/has_taur_body()
	return !!dq_taur_style_named(read_preference(/datum/preference/text/human/tail_style))

/datum/preference_editor/legs/proc/ui_act_set_leg_style(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/style = params["style"]
	if(style == "plantigrade" || style == "digitigrade")
		if(preferences.has_taur_body())
			preferences.update_preference_by_type(/datum/preference/text/human/tail_style, "")
		preferences.update_preference_by_type(/datum/preference/toggle/human/digitigrade, style == "digitigrade")
		return PREF_UPDATE_ACCEPTED
	if(!dq_taur_style_named(style))
		return PREF_UPDATE_REJECTED
	preferences.update_preference_by_type(/datum/preference/text/human/tail_style, style)
	preferences.update_preference_by_type(/datum/preference/toggle/human/digitigrade, FALSE) // a taur body has no legs of its own
	return PREF_UPDATE_ACCEPTED

/// /datum/preference_editor/legs's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/legs/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_leg_style")
			typed = payload_args(src, params, list("style" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_leg_style(user, typed, preferences, null, action)
	return ..()

/// Saves from the three-button legs could be digitigrade with a taur body; the taur body wins, as it always drew.
/datum/preference/toggle/human/digitigrade/sanitize(value, datum/preferences/preferences)
	if(value && preferences?.has_taur_body())
		return FALSE
	return value
