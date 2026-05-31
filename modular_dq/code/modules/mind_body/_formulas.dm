// DQAdd — Per-category pool formulas + the pickability gate.
//
// Each category has its own pool drawn from the player's age. Body categories shrink
// with age, Mind categories grow. All Body categories share the same shrink curve;
// all Mind categories share the same growth curve. Tune the constants in _defines.dm.

/// Pool size for the given category at the given age. Body and Mind categories diverge
/// on the linear coefficient — Body decays, Mind grows.
/proc/dq_pool_for_category_and_age(category_id, age)
	if(!isnum(age))
		age = 18
	var/datum/perk_category/C = GLOB.perk_categories?[category_id]
	if(!C)
		return 0
	var/delta = max(0, round((age - 18) / MIND_BODY_AGE_STEP))
	if(C.category_type == PERK_CATEGORY_TYPE_BODY)
		return clamp(
			MIND_BODY_BASE_BODY_PER_CAT - delta,
			MIND_BODY_MIN_PER_CAT,
			MIND_BODY_BASE_BODY_PER_CAT,
		)
	return clamp(
		MIND_BODY_MIN_PER_CAT + delta,
		MIND_BODY_MIN_PER_CAT,
		MIND_BODY_MAX_MIND_PER_CAT,
	)

/// Total points the player currently has spent in a given category. Sums the cost of
/// every selected perk whose category id matches.
/proc/dq_spent_in_category(datum/preferences/preferences, category_id)
	if(!preferences || !category_id)
		return 0
	var/datum/perk_category/C = GLOB.perk_categories?[category_id]
	if(!C)
		return 0
	var/list/selected = (C.category_type == PERK_CATEGORY_TYPE_BODY) \
		? (preferences.read_preference(/datum/preference/typed_list/body_perks) || list()) \
		: (preferences.read_preference(/datum/preference/typed_list/mind_perks) || list())
	var/total = 0
	for(var/path in selected)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P && P.category == category_id)
			total += P.cost
	return total

/// Single rule for "can this perk be picked right now?" Used by the typed_list
/// validators on write AND by the refit constraint on cascade.
/proc/dq_perk_is_pickable_by(path, datum/preferences/preferences)
	if(istext(path))
		path = text2path(path)
	var/datum/perk/P = GLOB.all_perks?[path]
	if(!P || !P.category)
		return FALSE
	var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
	var/pool = dq_pool_for_category_and_age(P.category, age)
	var/spent = dq_spent_in_category(preferences, P.category)
	// If the perk is already selected, its cost is already in `spent` — checking the
	// pool against `spent` alone is correct; for an unselected perk we add its cost.
	var/list/list_sel = (P.perk_kind == PERK_KIND_BODY) \
		? (preferences.read_preference(/datum/preference/typed_list/body_perks) || list()) \
		: (preferences.read_preference(/datum/preference/typed_list/mind_perks) || list())
	var/extra = (path in list_sel) ? 0 : P.cost
	if(spent + extra > pool)
		return FALSE
	if(LAZYLEN(P.requires))
		for(var/req in P.requires)
			if(!(req in list_sel))
				return FALSE
	return TRUE
