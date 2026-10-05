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
UI_ACT(/datum/lootpanel, "grab", ui_act_grab, UI_ARG_REF("ref", "searchables", /datum/search_object), UI_ARG_BOOL("ctrl"), UI_ARG_BOOL("middle"), UI_ARG_BOOL("shift"), UI_ARG_BOOL("alt"), UI_ARG_BOOL("right"))
UI_ACT_PROC(/datum/lootpanel, ui_act_grab)
	var/datum/search_object/index = params["ref"]
	if(isnull(index))
		return FALSE
	var/atom/thing = index?.item()
	if(QDELETED(index) || QDELETED(thing)) // Obj is gone
		return FALSE

	if(thing != source_turf() && !(locate_within(source_turf(), thing)))
		rel_remove(src, nameof(searchables), index) // Item has moved
		return TRUE

	var/modifiers = ""
	if(params["ctrl"])
		modifiers += "ctrl=1;"
	if(params["middle"])
		modifiers += "middle=1;"
	if(params["shift"])
		modifiers += "shift=1;"
	if(params["alt"])
		modifiers += "alt=1;"
	if(params["right"])
		modifiers += "right=1;"


	user.ClickOn(thing, modifiers)

	return TRUE
