// Trait picker composite editor.
// Owns the workflow for selecting positive/neutral/negative traits with point budget +
// max-traits enforcement + species/synth/meatbag filtering.
//
// Wire actions (sent via dq_editor_action):
//   "add_trait"   { category: "pos"|"neu"|"neg", trait_path: "/datum/trait/..." }
//   "remove_trait" { category: "pos"|"neu"|"neg", trait_path: "..." }
//   "toggle_cheating"
//   "set_blood_color" { color: "#XXXXXX" }

/datum/preference_editor/trait_picker
	key = "trait_picker"
	category = "traits"
	sort_order = 10
	display_name = "Traits"
	pref_keys = list("pos_traits", "neu_traits", "neg_traits", "blood_color", "traits_cheating", "starting_trait_points", "max_traits")

/datum/preference_editor/trait_picker/build_ui_data(datum/preferences/preferences)
	var/list/pos_traits = preferences.read_preference(/datum/preference/typed_list/traits/pos_traits) || list()
	var/list/neu_traits = preferences.read_preference(/datum/preference/typed_list/traits/neu_traits) || list()
	var/list/neg_traits = preferences.read_preference(/datum/preference/typed_list/traits/neg_traits) || list()

	var/points_used = 0
	for(var/T in (pos_traits + neu_traits + neg_traits))
		points_used += GLOB.traits_costs[T] || 0

	var/total_traits = pos_traits.len + neg_traits.len

	return list(
		"blood_color" = preferences.read_preference(/datum/preference/color/human/blood_color),
		"traits_cheating" = preferences.read_preference(/datum/preference/numeric/human/traits_cheating),
		"starting_trait_points" = preferences.read_preference(/datum/preference/numeric/human/starting_trait_points),
		"max_traits" = preferences.read_preference(/datum/preference/numeric/human/max_traits),
		"points_used" = points_used,
		"total_traits" = total_traits,
		"pos_traits" = simplify_trait_list(pos_traits),
		"neu_traits" = simplify_trait_list(neu_traits),
		"neg_traits" = simplify_trait_list(neg_traits),
	)

/datum/preference_editor/trait_picker/build_ui_static_data(datum/preferences/preferences)
	var/list/all_traits = list()
	for(var/path in GLOB.all_traits)
		var/datum/trait/T = GLOB.all_traits[path]
		all_traits["[path]"] = list(
			"name" = T.name,
			"desc" = T.desc,
			"cost" = T.cost,
			"category" = T.category,
		)
	return list(
		"all_traits" = all_traits,
		"positive_traits" = paths_to_text(GLOB.positive_traits),
		"neutral_traits" = paths_to_text(GLOB.neutral_traits),
		"negative_traits" = paths_to_text(GLOB.negative_traits),
	)

/datum/preference_editor/trait_picker/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("add_trait")
			var/trait_path = text2path(params["trait_path"])
			if(!trait_path)
				return PREF_UPDATE_REJECTED
			var/list_type = pref_for_category(params["category"])
			if(!list_type)
				return PREF_UPDATE_REJECTED
			preferences.update_many(CALLBACK(src, PROC_REF(add_trait_atomic), preferences, list_type, trait_path))
			return PREF_UPDATE_ACCEPTED
		if("remove_trait")
			var/trait_path = text2path(params["trait_path"])
			var/list_type = pref_for_category(params["category"])
			if(!trait_path || !list_type)
				return PREF_UPDATE_REJECTED
			var/list/current = preferences.read_preference(list_type)
			current -= trait_path
			preferences.update_preference_by_type(list_type, current)
			return PREF_UPDATE_ACCEPTED
		if("toggle_cheating")
			var/cur = preferences.read_preference(/datum/preference/numeric/human/traits_cheating)
			preferences.update_preference_by_type(/datum/preference/numeric/human/traits_cheating, !cur)
			return PREF_UPDATE_ACCEPTED
		if("set_blood_color")
			// open BYOND's color picker so the user can actually pick a color.
			var/current = preferences.read_preference(/datum/preference/color/human/blood_color) || "#A10808"
			var/picked = tgui_color_picker(user, "Blood color", "Color picker", current)
			if(!picked)
				return PREF_UPDATE_UNCHANGED
			// tgui_color_picker sleeps — re-verify prefs ownership before writing.
			if(!user?.client?.prefs || user.client.prefs != preferences)
				return PREF_UPDATE_UNCHANGED
			preferences.update_preference_by_type(/datum/preference/color/human/blood_color, sanitize_hexcolor(picked, default="#A10808"))
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/trait_picker/proc/add_trait_atomic(datum/preferences/preferences, list_type, trait_path)
	var/list/current = preferences.read_preference(list_type)
	if(trait_path in current)
		return
	current += trait_path
	preferences.update_preference_by_type(list_type, current)

/datum/preference_editor/trait_picker/proc/pref_for_category(category_key)
	switch(category_key)
		if("pos")
			return /datum/preference/typed_list/traits/pos_traits
		if("neu")
			return /datum/preference/typed_list/traits/neu_traits
		if("neg")
			return /datum/preference/typed_list/traits/neg_traits

/datum/preference_editor/trait_picker/proc/simplify_trait_list(list/traits)
	var/list/out = list()
	for(var/path in traits)
		out += "[path]"
	return out

/datum/preference_editor/trait_picker/proc/paths_to_text(list/path_list)
	var/list/out = list()
	for(var/path in path_list)
		out += "[path]"
	return out
