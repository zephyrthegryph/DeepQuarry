// Mind/Body specialty editor.
//
// build_ui_data        — current spent-per-category + selected perk paths.
// build_ui_static_data — every category, every tree, every perk meta (name, icon,
//                        desc, cost, requires, category, tree). Read by React to
//                        render the tab strip + perk grid.
// handle_action        — add_perk / remove_perk (no more set_body_points — linear
//                        conditioning was retired in P7).

/datum/preference_editor/mind_body
	key = "mind_body"
	category = "mind_body"
	sort_order = 20
	display_name = "Mind & Body"
	pref_keys = list("body_perks", "mind_perks", "age")

/datum/preference_editor/mind_body/build_ui_data(datum/preferences/preferences)
	var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
	var/list/body_perks = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	var/list/mind_perks = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()

	return list(
		"age" = age,
		"body_pool" = dq_body_pool_for_age(age),
		"body_spent" = dq_body_total_spent(preferences),
		"mind_pool" = dq_mind_pool_for_age(age),
		"mind_spent" = dq_mind_total_spent(preferences),
		// Informational per-category spend for the chip badges.
		"spent_by_cat" = dq_spent_by_category(preferences),
		"body_perks" = paths_as_text(body_perks),
		"mind_perks" = paths_as_text(mind_perks),
	)

/datum/preference_editor/mind_body/build_ui_static_data(datum/preferences/preferences)
	var/list/categories = list()
	for(var/cat_id in GLOB.perk_categories)
		var/datum/perk_category/C = GLOB.perk_categories[cat_id]
		categories[cat_id] = list(
			"id" = C.id,
			"name" = C.display_name,
			"description" = C.description,
			"color" = C.color,
			"icon" = C.icon_name,
			"type" = C.category_type,
		)

	var/list/trees = list()
	for(var/tree_id in GLOB.perk_trees)
		var/datum/perk_tree/T = GLOB.perk_trees[tree_id]
		var/list/perk_paths = list()
		if(islist(T.perks))
			for(var/path in T.perks)
				perk_paths += "[path]"
		trees[tree_id] = list(
			"id" = T.id,
			"name" = T.display_name,
			"description" = T.description,
			"color" = T.color,
			"icon" = T.icon_name,
			"category" = T.category,
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
			"icon" = P.icon_name,
			"cost" = P.cost,
			"perk_kind" = P.perk_kind,
			"category" = P.category,
			"tree" = P.tree,
			"requires" = requires_text,
			"sort_priority" = P.sort_priority,
			"tree_x" = isnull(P.tree_x) ? null : P.tree_x,
			"tree_y" = isnull(P.tree_y) ? null : P.tree_y,
		)

	return list(
		"categories" = categories,
		"trees" = trees,
		"perks" = perks,
	)

/datum/preference_editor/mind_body/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
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
	switch(P.perk_kind)
		if(PERK_KIND_BODY)
			return /datum/preference/typed_list/body_perks
		if(PERK_KIND_MIND)
			return /datum/preference/typed_list/mind_perks

/datum/preference_editor/mind_body/proc/paths_as_text(list/paths)
	var/list/out = list()
	for(var/p in paths)
		out += "[p]"
	return out
