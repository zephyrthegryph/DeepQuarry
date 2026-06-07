// DQAdd — Resolve all_underwear category->item names into the actual category_item datums
// on the character, and copy through the per-item metadata. Lives in a hook because the
// resolution depends on the global underwear catalog (GLOB.global_underwear.categories_by_name).

/datum/preference_apply_hook/equipment
	priority = APPLY_HOOK_PRIORITY_EQUIPMENT

/datum/preference_apply_hook/equipment/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return
	target.all_underwear.Cut()
	target.all_underwear_metadata.Cut()

	var/list/all_underwear = preferences.read_preference(/datum/preference/all_underwear)
	var/list/all_underwear_metadata = preferences.read_preference(/datum/preference/all_underwear_metadata)
	// Iterate a copy; the loop conditionally removes from the same list and DM doesn't
	// guarantee defined behavior for mutation-during-iteration. read_preference already
	// returns a Copy() for list values so the cache is safe either way; this is purely
	// for iteration correctness.
	for(var/underwear_category_name in all_underwear.Copy())
		var/datum/category_group/underwear/underwear_category = GLOB.global_underwear.categories_by_name[underwear_category_name]
		if(!underwear_category)
			all_underwear -= underwear_category_name
			continue
		var/underwear_item_name = all_underwear[underwear_category_name]
		target.all_underwear[underwear_category_name] = underwear_category.items_by_name[underwear_item_name]
		if(all_underwear_metadata[underwear_category_name])
			target.all_underwear_metadata[underwear_category_name] = all_underwear_metadata[underwear_category_name]
