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

/// The taur body takes the tail style's place; the tail it replaced is kept (tail_style_under_taur) and comes back when the taur goes.
/datum/preference_editor/legs/proc/ui_act_set_leg_style(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/style = params["style"]
	if(style == "plantigrade" || style == "digitigrade")
		if(preferences.has_taur_body())
			preferences.update_preference_by_type(/datum/preference/text/human/tail_style, preferences.read_preference(/datum/preference/text/human/tail_style_under_taur) || "")
			preferences.update_preference_by_type(/datum/preference/text/human/tail_style_under_taur, "")
			dq_tail_shown_changed(preferences)
		preferences.update_preference_by_type(/datum/preference/toggle/human/digitigrade, style == "digitigrade")
		return PREF_UPDATE_ACCEPTED
	if(!dq_taur_style_named(style))
		return PREF_UPDATE_REJECTED
	if(!preferences.has_taur_body())
		preferences.update_preference_by_type(/datum/preference/text/human/tail_style_under_taur, preferences.read_preference(/datum/preference/text/human/tail_style) || "")
		dq_tail_shown_changed(preferences)
	preferences.update_preference_by_type(/datum/preference/text/human/tail_style, style)
	preferences.update_preference_by_type(/datum/preference/toggle/human/digitigrade, FALSE) // a taur body has no legs of its own
	return PREF_UPDATE_ACCEPTED

/// The greyed Tail row reads the kept tail from the tail style's widget props: send the window a fresh structure.
/datum/preference_editor/legs/proc/dq_tail_shown_changed(datum/preferences/preferences)
	preferences.dq_invalidate_category_cache()
	preferences.dq_schedule_static_push()

/// The tail a taur body replaced, worn again when the taur goes. Set only by the Legs picker; never drawn while the taur is.
/datum/preference/text/human/tail_style_under_taur
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "tail_style_under_taur"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/tail_style_under_taur/create_default_value()
	return ""

/datum/preference/text/human/tail_style_under_taur/validate(datum/preferences/preferences, value)
	return !value || (is_valid(value) && (value in sprite_accessory_names(GLOB.tail_styles_list)) && !dq_taur_style_named(value))

/datum/preference/text/human/tail_style_under_taur/apply_to_human(mob/living/carbon/human/target, value)
	return

/// The Tail row greys out under a taur body and shows the tail it keeps.
/datum/preference/text/human/tail_style/get_widget_props(datum/preferences/preferences)
	. = ..()
	.["under_taur"] = preferences?.read_preference(/datum/preference/text/human/tail_style_under_taur) || ""


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
