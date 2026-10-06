/// UI helper for converting the associative list to a list of lists
/datum/lootpanel/proc/get_contents()
	var/list/items = list()

	for(var/datum/search_object/index as anything in searchables)
		UNTYPED_LIST_ADD(items, list(
			"icon_state" = index.icon_state,
			"icon" = index.icon,
			"name" = index.name,
			"path" = index.path,
			"ref" = REF(index),
		))

	return items


/// Clicks an object from the searchables. Validates the object and the user
/datum/lootpanel/proc/ui_act_grab(datum/act/op/A, ref, ctrl, middle, shift, alt, right)
	var/mob/user = A.actor
	if(!isnull(ref) && !(ref in src.searchables))
		return FALSE
	var/datum/search_object/index = ref
	if(isnull(index))
		return FALSE
	var/atom/thing = index?.item()
	if(QDELETED(index) || QDELETED(thing)) // Obj is gone
		return FALSE

	if(thing != source_turf() && !(locate_within(source_turf(), thing)))
		rel_remove(src, nameof(searchables), index) // Item has moved
		return TRUE

	var/modifiers = ""
	if(ctrl)
		modifiers += "ctrl=1;"
	if(middle)
		modifiers += "middle=1;"
	if(shift)
		modifiers += "shift=1;"
	if(alt)
		modifiers += "alt=1;"
	if(right)
		modifiers += "right=1;"


	user.ClickOn(thing, modifiers)

	return TRUE
