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
 * Caches read-only lists of any shape (nested lists, typepaths, numbers) by their
 * JSON form, so types whose instances all carry the same constant table share one
 * list. The result is shared: never edit it in place, assign a new list instead.
 */
/proc/intern_list(list/values)
	if(!islist(values))
		return values
	var/static/list/cache = list() // ALLOW(cache): interning store (values are caller-supplied, no builder)
	var/key = json_encode(values)
	. = cache[key]
	if(.)
		return
	cache[key] = values
	return values
