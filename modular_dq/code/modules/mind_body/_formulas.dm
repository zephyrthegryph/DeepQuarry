// DQAdd — Age → point-pool formulas + the prereq/budget gate.
//
// Centralized so the apply hooks, the constraint, the validator, and the React UI all
// read the same numbers. Tweak the defines in _defines.dm to retune the curves.

/// Body pool for a given age. Younger = more.
/proc/dq_body_pool_for_age(age)
	if(!isnum(age))
		age = 18
	var/decay = max(0, round((age - 18) / MIND_BODY_AGE_STEP))
	return clamp(MIND_BODY_BASE_BODY_AT_18 - decay, MIND_BODY_MIN_POINTS, MIND_BODY_BASE_BODY_AT_18)

/// Mind pool for a given age. Older = more.
/proc/dq_mind_pool_for_age(age)
	if(!isnum(age))
		age = 18
	var/growth = max(0, round((age - 18) / MIND_BODY_AGE_STEP))
	return clamp(MIND_BODY_MIN_POINTS + growth, MIND_BODY_MIN_POINTS, MIND_BODY_BASE_BODY_AT_18)

/// Total Body points spent = linear allocation + cost of selected Body perks.
/proc/dq_body_total_spent(datum/preferences/preferences)
	if(!preferences)
		return 0
	var/linear = preferences.read_preference(/datum/preference/numeric/body_points_spent) || 0
	var/list/perks = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	var/perk_total = 0
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P)
			perk_total += P.cost
	return linear + perk_total

/// Total Mind points spent = sum of selected Mind perk costs.
/proc/dq_mind_total_spent(datum/preferences/preferences)
	if(!preferences)
		return 0
	var/list/perks = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	var/total = 0
	for(var/path in perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P)
			total += P.cost
	return total

/// Single rule for "can this perk be picked right now?" Used by typed_list.validate AND
/// by the constraint when refitting. Centralizing here keeps the write-gate and the
/// refit-trim in lockstep.
///
/// Checks, in order:
///   1. The path is a known perk in GLOB.all_perks.
///   2. The pool can still afford its cost.
///   3. Body threshold perks: linear-Body spend meets the perk's threshold gate.
///   4. requires-chain: all prerequisite perks already selected.
/proc/dq_perk_is_pickable_by(path, datum/preferences/preferences)
	if(istext(path))
		path = text2path(path)
	var/datum/perk/P = GLOB.all_perks?[path]
	if(!P)
		return FALSE
	if(P.category == PERK_CATEGORY_BODY)
		var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
		var/pool = dq_body_pool_for_age(age)
		var/spent = dq_body_total_spent(preferences)
		var/list/body_perks = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
		// If already selected, the cost is already counted in `spent` — no extra check.
		var/extra = (path in body_perks) ? 0 : P.cost
		if(spent + extra > pool)
			return FALSE
		// Threshold gate: linear Body points must meet the perk's tier.
		if(P.body_tier_threshold)
			var/linear = preferences.read_preference(/datum/preference/numeric/body_points_spent) || 0
			if(linear < P.body_tier_threshold)
				return FALSE
		if(LAZYLEN(P.requires))
			for(var/req in P.requires)
				if(!(req in body_perks))
					return FALSE
	else if(P.category == PERK_CATEGORY_MIND)
		var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
		var/pool = dq_mind_pool_for_age(age)
		var/spent = dq_mind_total_spent(preferences)
		var/list/mind_perks = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
		var/extra = (path in mind_perks) ? 0 : P.cost
		if(spent + extra > pool)
			return FALSE
		if(LAZYLEN(P.requires))
			for(var/req in P.requires)
				if(!(req in mind_perks))
					return FALSE
	return TRUE
