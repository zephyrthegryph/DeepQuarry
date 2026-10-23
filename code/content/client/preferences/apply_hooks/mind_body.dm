// Mind/Body apply hook.
//
// Runs at SPECIES + 5 so it can write var_changes onto the species the traits hook
// just synthesised. Body perks write var_changes (like traits); Mind perks call
// perk.grant(target). No more linear-conditioning slider — every Body point now
// comes from a selected perk in some category.

/datum/preference_apply_hook/mind_body
	priority = APPLY_HOOK_PRIORITY_SPECIES + 5

/datum/preference_apply_hook/mind_body/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return
	var/datum/species/S = target.species
	if(!S)
		return

	var/list/body_perks = preferences.read_preference(/datum/preference/typed_list/body_perks) || list()
	for(var/path in body_perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(!P || P.perk_kind != PERK_KIND_BODY)
			continue
		P.apply_var_changes(S)
		P.grant(target, preferences)

	var/list/mind_perks = preferences.read_preference(/datum/preference/typed_list/mind_perks) || list()
	for(var/path in mind_perks)
		var/datum/perk/P = GLOB.all_perks?[path]
		if(!P || P.perk_kind != PERK_KIND_MIND)
			continue
		P.grant(target, preferences)
