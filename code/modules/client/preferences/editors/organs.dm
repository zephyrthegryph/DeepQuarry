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
	pref_keys = list("organ_data", "rlimb_data")

/datum/preference_editor/organs/proc/external_limb_labels()
	var/static/list/L = list(
		BP_TORSO   = "Torso",
		BP_HEAD    = "Head",
		BP_GROIN   = "Groin",
		BP_L_ARM   = "Left Arm",
		BP_R_ARM   = "Right Arm",
		BP_L_HAND  = "Left Hand",
		BP_R_HAND  = "Right Hand",
		BP_L_LEG   = "Left Leg",
		BP_R_LEG   = "Right Leg",
		BP_L_FOOT  = "Left Foot",
		BP_R_FOOT  = "Right Foot",
	)
	return L

/datum/preference_editor/organs/proc/internal_organ_labels()
	var/static/list/L = list(
		O_HEART     = "Heart",
		O_EYES      = "Eyes",
		O_LUNGS     = "Lungs",
		O_LIVER     = "Liver",
		O_KIDNEYS   = "Kidneys",
		O_SPLEEN    = "Spleen",
		O_STOMACH   = "Stomach",
		O_INTESTINE = "Intestine",
		O_VOICE     = "Voice Box",
		O_BRAIN     = "Brain",
	)
	return L

/datum/preference_editor/organs/build_ui_data(datum/preferences/preferences)
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
	var/list/rlimb_data = preferences.read_preference(/datum/preference/rlimb_data) || list()
	var/list/externals = list()
	for(var/name in external_limb_labels())
		externals[name] = list(
			"status" = organ_data[name] || "normal",
			"model"  = rlimb_data[name] || null,
		)
	var/list/internals = list()
	for(var/name in internal_organ_labels())
		internals[name] = organ_data[name] || "normal"
	return list(
		"externals" = externals,
		"internals" = internals,
	)

/datum/preference_editor/organs/build_ui_static_data(datum/preferences/preferences)
	var/list/limb_models = list()
	for(var/key in GLOB.all_robolimbs)
		limb_models += key
	return list(
		"external_labels" = external_limb_labels(),
		"internal_labels" = internal_organ_labels(),
		"limb_models"     = limb_models,
		"external_order"  = list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT),
		"internal_order"  = list(O_HEART, O_LUNGS, O_LIVER, O_KIDNEYS, O_SPLEEN, O_STOMACH, O_INTESTINE, O_VOICE, O_EYES, O_BRAIN),
	)

/datum/preference_editor/organs/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/limb = params["limb"]
	if(!limb)
		return PREF_UPDATE_REJECTED
	switch(action)
		if("set_external_status")
			var/status = params["status"]
			if(!(status in list("normal", "amputated", "cyborg")))
				return PREF_UPDATE_REJECTED
			if(!(limb in external_limb_labels()))
				return PREF_UPDATE_REJECTED
			var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
			var/list/rlimb_data = preferences.read_preference(/datum/preference/rlimb_data) || list()
			if(status == "normal")
				organ_data -= limb
				rlimb_data -= limb
			else
				organ_data[limb] = status
				if(status != "cyborg")
					rlimb_data -= limb
			preferences.begin_update_batch()
			preferences.update_preference_by_type(/datum/preference/organ_data, organ_data)
			preferences.update_preference_by_type(/datum/preference/rlimb_data, rlimb_data)
			preferences.end_update_batch()
			return PREF_UPDATE_ACCEPTED
		if("set_external_model")
			var/model = params["model"]
			if(!(model in GLOB.all_robolimbs))
				return PREF_UPDATE_REJECTED
			var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
			var/list/rlimb_data = preferences.read_preference(/datum/preference/rlimb_data) || list()
			organ_data[limb] = "cyborg"
			rlimb_data[limb] = model
			preferences.begin_update_batch()
			preferences.update_preference_by_type(/datum/preference/organ_data, organ_data)
			preferences.update_preference_by_type(/datum/preference/rlimb_data, rlimb_data)
			preferences.end_update_batch()
			return PREF_UPDATE_ACCEPTED
		if("set_internal_status")
			var/status = params["status"]
			if(!(status in list("normal", FBP_ASSISTED, FBP_MECHANICAL, FBP_DIGITAL)))
				return PREF_UPDATE_REJECTED
			if(!(limb in internal_organ_labels()))
				return PREF_UPDATE_REJECTED
			var/list/organ_data = preferences.read_preference(/datum/preference/organ_data) || list()
			if(status == "normal")
				organ_data -= limb
			else
				organ_data[limb] = status
			preferences.update_preference_by_type(/datum/preference/organ_data, organ_data)
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
