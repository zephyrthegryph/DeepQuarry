// DQAdd — Mind/Body specialty editor.
//
// Wires:
//   build_ui_data        — current pools (derived from age), spent counters, selected perks
//   build_ui_static_data — every tree + every perk, so the React side can render the grids
//   handle_action        — set_body_points / add_perk / remove_perk
//
// All writes route through update_preference_by_type so the typed_list validators and the
// mind_body_refit constraint fire. A forged Topic with an out-of-budget perk gets rejected
// at typed_list.validate before reaching the savefile.

/datum/preference_editor/mind_body
	key = "mind_body"
	category = "mind_body"
	sort_order = 20
	display_name = "Mind & Body"
	pref_keys = list("body_points_spent", "body_perks", "mind_perks", "age")

/datum/preference_editor/mind_body/build_ui_data(datum/preferences/preferences)
	var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
	var/list/body_perks = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	var/list/mind_perks = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	var/linear = preferences.read_preference(/datum/preference/numeric/body_points_spent) || 0

	return list(
		"age" = age,
		"body_pool" = dq_body_pool_for_age(age),
		"mind_pool" = dq_mind_pool_for_age(age),
		"body_linear" = linear,
		"body_spent" = dq_body_total_spent(preferences),
		"mind_spent" = dq_mind_total_spent(preferences),
		"body_perks" = paths_as_text(body_perks),
		"mind_perks" = paths_as_text(mind_perks),
	)

/datum/preference_editor/mind_body/build_ui_static_data(datum/preferences/preferences)
	var/list/trees = list()
	for(var/id in GLOB.perk_trees)
		var/datum/perk_tree/T = GLOB.perk_trees[id]
		var/list/perk_paths = list()
		if(islist(T.perks))
			for(var/path in T.perks)
				perk_paths += "[path]"
		trees[id] = list(
			"id" = T.id,
			"name" = T.display_name,
			"description" = T.description,
			"color" = T.color,
			"icon" = T.icon_name,
			"perks" = perk_paths,
		)

	var/list/perks = list()
	for(var/path in GLOB.all_perks)
		var/datum/perk/P = GLOB.all_perks[path]
		var/list/requires_text = list()
		if(LAZYLEN(P.requires))
			for(var/req in P.requires)
				requires_text += "[req]"
		perks["[path]"] = list(
			"name" = P.name,
			"desc" = P.desc,
			"cost" = P.cost,
			"category" = P.category,
			"tree" = P.tree,
			"threshold" = P.body_tier_threshold,
			"requires" = requires_text,
		)

	return list(
		"trees" = trees,
		"perks" = perks,
		// Body now spans multiple sub-trees (Strength / Vigor / Speed / Endurance), all
		// drawing from the same Body pool. React groups them under the Body pane and
		// uses the rest as Mind trees.
		"body_tree_ids" = list(
			PERK_TREE_BODY_STRENGTH,
			PERK_TREE_BODY_VIGOR,
			PERK_TREE_BODY_SPEED,
			PERK_TREE_BODY_ENDURANCE,
		),
		"body_max" = MIND_BODY_BASE_BODY_AT_18,
		"hp_per_point" = BODY_POINT_HP_PER,
		"slowdown_per_point" = BODY_POINT_SLOWDOWN_PER,
		"thresholds" = list(BODY_TIER_LOW, BODY_TIER_MID, BODY_TIER_HIGH),
	)

/datum/preference_editor/mind_body/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("set_body_points")
			var/raw = params["value"]
			var/value = isnum(raw) ? raw : text2num(raw)
			if(isnull(value))
				return PREF_UPDATE_REJECTED
			value = clamp(round(value), 0, MIND_BODY_BASE_BODY_AT_18)
			preferences.update_preference_by_type(/datum/preference/numeric/body_points_spent, value)
			return PREF_UPDATE_ACCEPTED

		if("add_perk")
			var/perk_path = text2path(params["perk_path"])
			if(!perk_path)
				return PREF_UPDATE_REJECTED
			var/datum/perk/P = GLOB.all_perks?[perk_path]
			if(!P)
				return PREF_UPDATE_REJECTED
			var/list_type = perk_list_type_for(P)
			if(!list_type)
				return PREF_UPDATE_REJECTED
			var/list/current = preferences.read_preference(list_type) || list()
			if(perk_path in current)
				return PREF_UPDATE_UNCHANGED
			current += perk_path
			// typed_list.validate runs dq_perk_is_pickable_by per entry; if the user is
			// busted on budget/threshold, the write is rejected and the cache stays clean.
			preferences.update_preference_by_type(list_type, current)
			return PREF_UPDATE_ACCEPTED

		if("remove_perk")
			var/perk_path = text2path(params["perk_path"])
			if(!perk_path)
				return PREF_UPDATE_REJECTED
			var/datum/perk/P = GLOB.all_perks?[perk_path]
			if(!P)
				return PREF_UPDATE_REJECTED
			var/list_type = perk_list_type_for(P)
			if(!list_type)
				return PREF_UPDATE_REJECTED
			var/list/current = preferences.read_preference(list_type) || list()
			if(!(perk_path in current))
				return PREF_UPDATE_UNCHANGED
			current -= perk_path
			preferences.update_preference_by_type(list_type, current)
			return PREF_UPDATE_ACCEPTED

	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/mind_body/proc/perk_list_type_for(datum/perk/P)
	switch(P.category)
		if(PERK_CATEGORY_BODY)
			return /datum/preference/typed_list/body_perks
		if(PERK_CATEGORY_MIND)
			return /datum/preference/typed_list/mind_perks

/datum/preference_editor/mind_body/proc/paths_as_text(list/paths)
	var/list/out = list()
	for(var/p in paths)
		out += "[p]"
	return out
