// A VARIANT() reference is a text (code/defines/content/variants.dm): these read and build it. Neutral text helpers, so every layer can take one.

/// The reference text of a variant: the parent type's path and the row's key, as VARIANT() writes them.
/proc/variant_ref(parent, key)
	return "[parent]/[key]"

/// The row key of a variant reference, or null for a path.
/proc/variant_key(type)
	if(!istext(type))
		return null
	var/slash = findlasttext(type, "/")
	return slash ? copytext(type, slash + 1) : null

/// The path of a saved_type(): the type itself, or a reference's parent.
/proc/saved_type_path(type)
	if(!istext(type))
		return type
	var/slash = findlasttext(type, "/")
	return slash ? text2path(copytext(type, 1, slash)) : null

PROC_SUMMARY(/proc/variant_is) // reads the variant var by name: the family's parent type is only known from the reference text
/// Whether `thing` is what `type` names: a path (istype), or a VARIANT() reference (the parent type with that row's key).
/proc/variant_is(datum/thing, type)
	if(!istext(type))
		return istype(thing, type)
	var/path = saved_type_path(type)
	return ispath(path) && istype(thing, path) && thing.vars["variant"] == variant_key(type)
