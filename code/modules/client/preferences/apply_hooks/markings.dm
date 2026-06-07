// DQAdd — Rebuild body marking overlays on the character's organs from the body_markings
// composite pref. Iterates organs and writes per-organ markings + sets character.markings_len.
// Lives in a hook because it touches the character's organ structure, and ordering matters
// (markings have priority = position in the list).

/datum/preference_apply_hook/markings
	priority = APPLY_HOOK_PRIORITY_ACCESSORIES

/datum/preference_apply_hook/markings/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return

	// Clear any stale markings from organs (apply_to_human on body_markings cleared character.markings_len's
	// concept of "owns the list," but the organ overlay list is rebuilt fresh here).
	// DQEdit — organs_by_name can include internal organs (e.g. posibrain in
	// FBP/protean torsos) that don't have a `markings` var. Filter to external
	// limbs only before touching .markings.
	for(var/N in target.organs_by_name)
		var/obj/item/organ/external/O = target.organs_by_name[N]
		if(!istype(O))
			continue
		O.markings.Cut()

	var/priority = 0
	var/list/body_markings = preferences.read_preference(/datum/preference/body_markings)
	for(var/M in body_markings)
		priority += 1
		var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[M]
		if(!mark_datum)
			continue
		for(var/BP in mark_datum.body_parts)
			var/obj/item/organ/external/O = target.organs_by_name[BP]
			if(!istype(O))
				continue
			if(islist(O.markings) && islist(body_markings[M]) && islist(body_markings[M][BP]))
				O.markings[M] = list(
					"color" = body_markings[M][BP]["color"],
					"datum" = mark_datum,
					"priority" = priority,
					"on" = body_markings[M][BP]["on"],
				)
	target.markings_len = priority
