// DQAdd — Mind/Body refit constraints.
//
// The write path's typed_list/{body,mind}_perks.validate gates direct user picks. This
// constraint handles state that becomes invalid *because of another pref change*:
//   - age moves, pool sizes shift, current selection may no longer fit.
//   - body_points_spent changes, threshold gates change, some Body perks may be unlocked
//     or invalidated.
//   - Mind perks change, their requires-chain may have been broken.
//
// Refit strategy:
//   1. Prune perks the entity rule no longer allows (broken requires, gone from registry).
//   2. If still over-budget, drop perks from the end of the saved list (newest-added first
//      assuming the editor always appends). The user can re-add what they want.
//   3. For Body specifically: if the new pool is smaller than current linear allocation,
//      clamp body_points_spent down to fit. Perks budget gets the leftover.

/datum/preference_constraint/mind_body_refit
	triggers = list(
		"age",
		"body_points_spent",
		"body_perks",
		"mind_perks",
	)
	affects = list(
		"body_points_spent",
		"body_perks",
		"mind_perks",
	)

/datum/preference_constraint/mind_body_refit/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
	var/body_pool = dq_body_pool_for_age(age)
	var/mind_pool = dq_mind_pool_for_age(age)

	// Body side. Linear allocation is the floor (it gates threshold perks); shrink it
	// first so the perks budget gets whatever is left.
	var/linear = preferences.read_preference(/datum/preference/numeric/body_points_spent) || 0
	if(linear > body_pool)
		linear = body_pool
		preferences.update_preference_by_type(/datum/preference/numeric/body_points_spent, linear)

	// Body perks: drop anything that no longer passes the entity rule, then trim from the
	// end if we're still over the body pool.
	prune_body_perks(preferences, body_pool, linear)

	// Mind perks: same shape, simpler (no threshold dependency).
	prune_mind_perks(preferences, mind_pool)

/datum/preference_constraint/mind_body_refit/proc/prune_body_perks(datum/preferences/preferences, body_pool, linear)
	var/list/perks = preferences.read_preference(/datum/preference/typed_list/body_perks)
	if(!islist(perks) || !length(perks))
		return
	var/changed = FALSE

	// Pass 1: drop unpickable (broken requires, missing from registry, etc.) Walking a
	// Copy lets us mutate `perks` safely; read_preference already returned a Copy so this
	// is paranoia, but cheap.
	for(var/path in perks.Copy())
		if(!dq_perk_is_pickable_by(path, preferences))
			perks -= path
			changed = TRUE

	// Pass 2: trim from the end until the running total fits the pool.
	var/spent
	while(TRUE)
		spent = linear + body_perks_cost(perks)
		if(spent <= body_pool || !length(perks))
			break
		perks.Cut(perks.len, perks.len + 1)
		changed = TRUE

	if(changed)
		preferences.update_preference_by_type(/datum/preference/typed_list/body_perks, perks)

/datum/preference_constraint/mind_body_refit/proc/prune_mind_perks(datum/preferences/preferences, mind_pool)
	var/list/perks = preferences.read_preference(/datum/preference/typed_list/mind_perks)
	if(!islist(perks) || !length(perks))
		return
	var/changed = FALSE

	for(var/path in perks.Copy())
		if(!dq_perk_is_pickable_by(path, preferences))
			perks -= path
			changed = TRUE

	var/spent
	while(TRUE)
		spent = mind_perks_cost(perks)
		if(spent <= mind_pool || !length(perks))
			break
		perks.Cut(perks.len, perks.len + 1)
		changed = TRUE

	if(changed)
		preferences.update_preference_by_type(/datum/preference/typed_list/mind_perks, perks)

/datum/preference_constraint/mind_body_refit/proc/body_perks_cost(list/perks)
	. = 0
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P)
			. += P.cost

/datum/preference_constraint/mind_body_refit/proc/mind_perks_cost(list/perks)
	. = 0
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P)
			. += P.cost
