/datum/holder/proc/fill(datum/thing, mob/user)
	// a statement and a value that is used
	rel_add(src, nameof(parts), thing)
	var/datum/got = rel_add(src, nameof(parts), thing)
	if(!rel_add(src, nameof(parts), thing))
		return null
	// another holder, a null value, an expression
	rel_add(thing, nameof(parts), null)
	rel_add(src, nameof(parts), new /datum())
	// over several lines, with a comment
	rel_add(src, // the holder
		nameof(parts), // the var
		thing) // the value
	// a text name stays as written; strings and comments that name it are untouched
	rel_add(src, "parts", thing)
	var/note = "own_add(src, nameof(parts), thing)"
	// own_add(src, nameof(parts), thing) is documented here
	return got
