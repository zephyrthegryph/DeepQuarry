// Mind/Body refit constraint.
//
// Fires on age change and on any direct perk-list change. With a single shared
// pool per side, the refit is simple: drop any entry the entity rule no longer
// allows, then trim newest-first until the total spend fits the pool.

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
	prune_side(preferences, /datum/preference/typed_list/body_perks, PERK_KIND_BODY)
	prune_side(preferences, /datum/preference/typed_list/mind_perks, PERK_KIND_MIND)

/datum/preference_constraint/mind_body_refit/proc/prune_side(datum/preferences/preferences, list_type, kind)
	var/list/perks = preferences.read_preference(list_type)
	if(!islist(perks) || !length(perks))
		return
	var/changed = FALSE

	// Pass 1: drop unpickable entries (broken requires, missing perk, etc).
	for(var/path in perks.Copy())
		if(!dq_perk_is_pickable_by(path, preferences))
			perks -= path
			changed = TRUE

	// Pass 2: total cost vs pool. Trim newest-first if over budget.
	var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
	var/pool = (kind == PERK_KIND_BODY) \
		? dq_body_pool_for_age(age) \
		: dq_mind_pool_for_age(age)
	while(total_cost(perks) > pool && length(perks))
		perks.Cut(perks.len, perks.len + 1)
		changed = TRUE

	if(changed)
		preferences.update_preference_by_type(list_type, perks)

/datum/preference_constraint/mind_body_refit/proc/total_cost(list/perks)
	. = 0
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P)
			. += P.cost
