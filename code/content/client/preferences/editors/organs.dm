// Organs / cybernetics editor. organ_data is an assoc {limb_name -> status} for
// external limbs ("amputated"/"cyborg") and internal organs (FBP_ASSISTED/MECHANICAL/DIGITAL).
// rlimb_data is an assoc {limb_name -> robolimb model name} populated only when a limb is
// set to "cyborg".

/datum/preference_editor/organs
	key = "organs"
	category = "appearance"
	group = "organs"
	sort_order = 80
	display_name = "Organs & Cybernetics"
	pref_keys = list("organ_data", "rlimb_data", "limb_colors")

TYPE_TABLE_DECLARE(/datum/preference_editor/organs, external_limb_labels, list( \
		BP_TORSO   = "Torso", \
		BP_HEAD    = "Head", \
		BP_GROIN   = "Groin", \
		BP_L_ARM   = "Left Arm", \
		BP_R_ARM   = "Right Arm", \
		BP_L_HAND  = "Left Hand", \
		BP_R_HAND  = "Right Hand", \
		BP_L_LEG   = "Left Leg", \
		BP_R_LEG   = "Right Leg", \
		BP_L_FOOT  = "Left Foot", \
		BP_R_FOOT  = "Right Foot", \
	))

TYPE_TABLE_DECLARE(/datum/preference_editor/organs, internal_organ_labels, list( \
		O_HEART     = "Heart", \
		O_EYES      = "Eyes", \
		O_LUNGS     = "Lungs", \
		O_LIVER     = "Liver", \
		O_KIDNEYS   = "Kidneys", \
		O_SPLEEN    = "Spleen", \
		O_STOMACH   = "Stomach", \
		O_INTESTINE = "Intestine", \
		O_VOICE     = "Voice Box", \
		O_BRAIN     = "Brain", \
	))

/datum/preference_editor/organs/build_ui_data(datum/preferences/preferences)
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
	var/list/rlimb_data = preferences.read_preference(/datum/preference/rlimb_data) || list()
	var/list/colors = preferences.read_preference(/datum/preference/limb_colors) || list()
	var/list/stored_colors = preferences.read_preference_raw(/datum/preference/limb_colors) || list()
	var/list/externals = list()
	for(var/name in TYPE_TABLE_GET(src, external_limb_labels))
		externals[name] = list(
			"status" = organ_data[name] || "normal",
			"model"  = rlimb_data[name] || null,
			"color"  = colors[name] || null,
			"link"   = dq_color_slot_type(stored_colors[name]) ? stored_colors[name] : "",
		)
	var/list/internals = list()
	for(var/name in TYPE_TABLE_GET(src, internal_organ_labels))
		internals[name] = organ_data[name] || "normal"
	// Labels and order ride with the data (a few hundred bytes): as a catalog they arrived
	// one round-trip after the page, and until then the section showed bare headings.
	return list(
		"externals" = externals,
		"internals" = internals,
		"external_labels" = TYPE_TABLE_GET(src, external_limb_labels),
		"internal_labels" = TYPE_TABLE_GET(src, internal_organ_labels),
		"external_order"  = list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT),
		"internal_order"  = list(O_HEART, O_LUNGS, O_LIVER, O_KIDNEYS, O_SPLEEN, O_STOMACH, O_INTESTINE, O_VOICE, O_EYES, O_BRAIN),
	)

/datum/preference_editor/organs/build_ui_static_data(datum/preferences/preferences)
	var/list/limb_models = list()
	for(var/key in GLOB.all_robolimbs)
		limb_models += key
	// The doll of the Looks tab draws the HUD zone-select art and clicks through the HUD's own hit areas.
	return list("limb_models" = limb_models, "doll_regions" = GLOB.zone_sel_regions)

/datum/preference_editor/organs/proc/ui_act_set_external_status(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/limb = params["limb"]
	if(!limb)
		return FALSE
	var/status = params["status"]
	if(!(status in list("normal", "amputated", "cyborg")))
		return PREF_UPDATE_REJECTED
	if(!(limb in TYPE_TABLE_GET(src, external_limb_labels)))
		return PREF_UPDATE_REJECTED
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
	var/list/rlimb_data = preferences.read_preference(/datum/preference/rlimb_data) || list()
	var/list/colors = preferences.read_preference_raw(/datum/preference/limb_colors) || list()
	if(status == "normal")
		organ_data -= limb
		rlimb_data -= limb
		colors -= limb
	else
		organ_data[limb] = status
		if(status != "cyborg")
			rlimb_data -= limb
			colors -= limb
		else if(!colors[limb])
			colors[limb] = "tertiary"
	preferences.begin_update_batch()
	preferences.update_preference_by_type(/datum/preference/limb_colors, colors)
	preferences.update_preference_by_type(/datum/preference/organ_data, organ_data)
	preferences.update_preference_by_type(/datum/preference/rlimb_data, rlimb_data)
	preferences.end_update_batch()
	return PREF_UPDATE_ACCEPTED

/// A robotic limb's colour with no picker: a palette slot's name or a hex.
/datum/preference_editor/organs/proc/ui_act_set_limb_color(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/limb = params["limb"]
	var/color = params["color"]
	if(!(limb in TYPE_TABLE_GET(src, external_limb_labels)) || !istext(color))
		return PREF_UPDATE_REJECTED
	if(!dq_color_slot_type(color))
		if(!findtext(color, GLOB.is_color))
			return PREF_UPDATE_REJECTED
		color = lowertext(sanitize_hexcolor(color))
	var/list/colors = preferences.read_preference_raw(/datum/preference/limb_colors) || list()
	colors[limb] = color
	preferences.update_preference_by_type(/datum/preference/limb_colors, colors)
	return PREF_UPDATE_ACCEPTED

/// The same through BYOND's colour picker.
/datum/preference_editor/organs/proc/ui_act_pick_limb_color(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/limb = params["limb"]
	if(!(limb in TYPE_TABLE_GET(src, external_limb_labels)))
		return PREF_UPDATE_REJECTED
	var/list/colors = preferences.read_preference(/datum/preference/limb_colors) || list()
	open_request(src, /datum/prompt/color/prefs/limb, PROC_REF(limb_color_picked), answerer = user, title = "Color picker", question = "Limb color", default = colors[limb] || "#FFFFFF", preferences = preferences, limb = limb)
	return PREF_UPDATE_UNCHANGED

/datum/prompt/color/prefs/limb
	var/limb

/datum/preference_editor/organs/proc/limb_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/limb/ask = A.answer
	var/datum/preferences/preferences = ask.preferences
	var/list/colors = preferences.read_preference_raw(/datum/preference/limb_colors) || list()
	colors[ask.limb] = lowertext(sanitize_hexcolor(ask.value))
	preferences.update_preference_by_type(/datum/preference/limb_colors, colors)
	SStgui.update_uis(preferences)

/datum/preference_editor/organs/proc/ui_act_set_external_model(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/limb = params["limb"]
	if(!limb)
		return FALSE
	var/model = params["model"]
	if(!(model in GLOB.all_robolimbs))
		return PREF_UPDATE_REJECTED
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
	var/list/rlimb_data = preferences.read_preference(/datum/preference/rlimb_data) || list()
	organ_data[limb] = "cyborg"
	rlimb_data[limb] = model
	var/list/colors = preferences.read_preference_raw(/datum/preference/limb_colors) || list()
	if(!colors[limb])
		colors[limb] = "tertiary"
	preferences.begin_update_batch()
	preferences.update_preference_by_type(/datum/preference/limb_colors, colors)
	preferences.update_preference_by_type(/datum/preference/organ_data, organ_data)
	preferences.update_preference_by_type(/datum/preference/rlimb_data, rlimb_data)
	preferences.end_update_batch()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/organs/proc/ui_act_set_internal_status(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/limb = params["limb"]
	if(!limb)
		return FALSE
	var/status = params["status"]
	if(!(status in list("normal", FBP_ASSISTED, FBP_MECHANICAL, FBP_DIGITAL)))
		return PREF_UPDATE_REJECTED
	if(!(limb in TYPE_TABLE_GET(src, internal_organ_labels)))
		return PREF_UPDATE_REJECTED
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
	if(status == "normal")
		organ_data -= limb
	else
		organ_data[limb] = status
	preferences.update_preference_by_type(/datum/preference/organ_data, organ_data)
	return PREF_UPDATE_ACCEPTED

/// /datum/preference_editor/organs's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/organs/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_external_status")
			typed = payload_args(src, params, list("limb" = null, "status" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_external_status(user, typed, preferences, null, action)
		if("set_external_model")
			typed = payload_args(src, params, list("limb" = null, "model" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_external_model(user, typed, preferences, null, action)
		if("set_limb_color")
			typed = payload_args(src, params, list("limb" = schema_text(64), "color" = schema_text(16)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_limb_color(user, typed, preferences, null, action)
		if("pick_limb_color")
			typed = payload_args(src, params, list("limb" = schema_text(64)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_pick_limb_color(user, typed, preferences, null, action)
		if("set_internal_status")
			typed = payload_args(src, params, list("limb" = null, "status" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_internal_status(user, typed, preferences, null, action)
	return ..()
