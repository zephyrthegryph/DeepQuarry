// DQAdd — Mind/Body refit constraint.
//
// Fires on age change and on any direct perk-list change. For each pool (one per
// category) compute current spend and trim newest-first if over-budget. Also drops
// any selection whose entity rule (dq_perk_is_pickable_by) no longer passes.

/datum/preference_constraint/mind_body_refit
	triggers = list(
		"age",
		"body_perks",
		"mind_perks",
	)
	affects = list(
		"body_perks",
		"mind_perks",
	)

/datum/preference_constraint/mind_body_refit/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	prune_side(preferences, /datum/preference/typed_list/body_perks)
	prune_side(preferences, /datum/preference/typed_list/mind_perks)

/datum/preference_constraint/mind_body_refit/proc/prune_side(datum/preferences/preferences, list_type)
	var/list/perks = preferences.read_preference(list_type)
	if(!islist(perks) || !length(perks))
		return
	var/changed = FALSE

	// Pass 1: drop unpickable entries (broken requires, missing perk, dead category…).
	for(var/path in perks.Copy())
		if(!dq_perk_is_pickable_by(path, preferences))
			perks -= path
			changed = TRUE

	// Pass 2: for each category present in the list, trim newest-first until the
	// per-category total fits. We use a fresh spend tally per category each loop
	// because removals affect future totals.
	var/list/by_cat = perks_by_category(perks)
	for(var/cat_id in by_cat)
		var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
		var/pool = dq_pool_for_category_and_age(cat_id, age)
		while(category_spend(perks, cat_id) > pool)
			var/list/in_cat = by_cat[cat_id]
			if(!length(in_cat))
				break
			// Remove the most recently added perk in this category.
			var/last = in_cat[length(in_cat)]
			perks -= last
			in_cat -= last
			changed = TRUE

	if(changed)
		preferences.update_preference_by_type(list_type, perks)

/datum/preference_constraint/mind_body_refit/proc/perks_by_category(list/perks)
	. = list()
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(!P || !P.category)
			continue
		var/list/L = .[P.category]
		if(!L)
			L = list()
			.[P.category] = L
		L += path

/datum/preference_constraint/mind_body_refit/proc/category_spend(list/perks, cat_id)
	. = 0
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P && P.category == cat_id)
			. += P.cost
