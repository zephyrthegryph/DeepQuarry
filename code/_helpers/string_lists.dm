GLOBAL_LIST_EMPTY(string_lists)

/**
 * Caches lists with non-numeric stringify-able values (text or typepath).
 */
/proc/string_list(list/values)
	var/string_id = values.Join("-")

	. = GLOB.string_lists[string_id]

	if(.)
		return

	return GLOB.string_lists[string_id] = values

/**
 * Caches assoc lists whose keys and values are text or numbers, so identical
 * tables (item armor, for instance) share one list. The result is shared:
 * copy it before writing to it.
 */
/proc/string_assoc_list(list/values)
	var/list/parts = list()
	for(var/key in values)
		parts += "[key]=[values[key]]"
	var/string_id = "assoc:[parts.Join(";")]"

	. = GLOB.string_lists[string_id]

	if(.)
		return

	return GLOB.string_lists[string_id] = values

/**
 * One list per (type, name): the first instance's list becomes the shared copy
 * for every later instance of that type. For per-subtype constant tables that
 * DM can't express as a static var. The result is shared: never write to it.
 */
/proc/shared_type_list(type, name, list/values)
	var/static/list/cache = list()
	var/key = "[type]:[name]"
	. = cache[key]
	if(.)
		return
	cache[key] = values
	return values
