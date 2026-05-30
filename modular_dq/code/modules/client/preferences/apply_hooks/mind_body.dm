// DQAdd — Mind/Body apply hook.
//
// Runs at SPECIES + 5 so it can write var_changes onto the already-synthesized species
// from the traits hook (priority SPECIES = 20). Body's linear allocation and threshold-perk
// var_changes both layer on the same way traits do; Mind perks call perk.grant(target).
//
// We split body and mind into one hook because the two pools share the prefs/preferences
// handle and there's no ordering need between them — body writes to species vars, mind
// attaches mob-level effects.

/datum/preference_apply_hook/mind_body
	priority = APPLY_HOOK_PRIORITY_SPECIES + 5

/datum/preference_apply_hook/mind_body/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return
	var/datum/species/S = target.species
	if(!S)
		return

	// ─── Body ───────────────────────────────────────────────────────────────────────
	// Linear allocation: per-point stat tweaks. Each point ticks total_health up by
	// BODY_POINT_HP_PER and slowdown down by BODY_POINT_SLOWDOWN_PER. These layer on the
	// species vars the traits hook just wrote.
	var/linear = preferences.read_preference(/datum/preference/numeric/body_points_spent) || 0
	if(linear > 0)
		S.total_health += linear * BODY_POINT_HP_PER
		S.slowdown -= linear * BODY_POINT_SLOWDOWN_PER

	// Body threshold perks: apply var_changes like traits do.
	var/list/body_perks = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	for(var/path in body_perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(!P || P.category != PERK_CATEGORY_BODY)
			continue
		P.apply_var_changes(S)
		// Body perks may also want to grant a component — call grant() so subtypes that
		// override it still fire. The default grant() is component-attach + no-op.
		P.grant(target, preferences)

	// ─── Mind ───────────────────────────────────────────────────────────────────────
	var/list/mind_perks = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	for(var/path in mind_perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(!P || P.category != PERK_CATEGORY_MIND)
			continue
		P.grant(target, preferences)
