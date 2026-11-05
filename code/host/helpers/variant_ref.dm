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

