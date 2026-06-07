// DQAdd — Pool formulas + the pickability gate.
//
// Single shared pool per side: one Body pool covering Strength + Vigor + Speed
// + Endurance, one Mind pool covering all 7 departments. Categories on the UI
// side are organisational only; the actual budget is global.

/// Total Body pool for the given age. Younger → bigger.
/proc/dq_body_pool_for_age(age)
	if(!isnum(age))
		age = 18
	var/decay = max(0, round((age - 18) / MIND_BODY_AGE_STEP))
	return clamp(
		MIND_BODY_BODY_POOL_AT_18 - decay,
		MIND_BODY_BODY_POOL_MIN,
		MIND_BODY_BODY_POOL_AT_18,
	)

/// Total Mind pool for the given age. Older → bigger.
/proc/dq_mind_pool_for_age(age)
	if(!isnum(age))
		age = 18
	var/growth = max(0, round((age - 18) / MIND_BODY_AGE_STEP))
	return clamp(
		MIND_BODY_MIND_POOL_AT_18 + growth,
		MIND_BODY_MIND_POOL_AT_18,
		MIND_BODY_MIND_POOL_MAX,
	)

/// Sum of costs across all selected Body perks.
/proc/dq_body_total_spent(datum/preferences/preferences)
	if(!preferences)
		return 0
	var/list/selected = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	. = 0
	for(var/path in selected)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P && P.perk_kind == PERK_KIND_BODY)
			. += P.cost

/// Sum of costs across all selected Mind perks.
/proc/dq_mind_total_spent(datum/preferences/preferences)
	if(!preferences)
		return 0
	var/list/selected = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	. = 0
	for(var/path in selected)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P && P.perk_kind == PERK_KIND_MIND)
			. += P.cost

/// Helper: which category contains how many cost-units. Used by the React UI
/// for the informational "X spent in Strength" chip badges.
/proc/dq_spent_by_category(datum/preferences/preferences)
	. = list()
	var/list/body_sel = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	for(var/path in body_sel)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P && P.category)
			.[P.category] = (.[P.category] || 0) + P.cost
	var/list/mind_sel = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	for(var/path in mind_sel)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(P && P.category)
			.[P.category] = (.[P.category] || 0) + P.cost

/// Single rule for "can this perk be picked right now?" Used by the typed_list
/// validators on write AND by the refit constraint on cascade. Checks against
/// the *side-wide* pool (Body or Mind), not per-category.
/proc/dq_perk_is_pickable_by(path, datum/preferences/preferences)
	if(istext(path))
		path = text2path(path)
	var/datum/perk/P = GLOB.all_perks?[path]
	if(!P || !P.perk_kind)
		return FALSE
	var/age = preferences.read_preference(/datum/preference/numeric/human/age) || 18
	var/pool
	var/spent
	var/list/list_sel
	if(P.perk_kind == PERK_KIND_BODY)
		pool = dq_body_pool_for_age(age)
		spent = dq_body_total_spent(preferences)
		list_sel = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	else
		pool = dq_mind_pool_for_age(age)
		spent = dq_mind_total_spent(preferences)
		list_sel = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	var/extra = (path in list_sel) ? 0 : P.cost
	if(spent + extra > pool)
		return FALSE
	if(LAZYLEN(P.requires))
		for(var/req in P.requires)
			if(!(req in list_sel))
				return FALSE
	return TRUE
