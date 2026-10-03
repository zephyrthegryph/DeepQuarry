/datum/holder/proc/fill(datum/thing, mob/user)
	// a statement and a value that is used
	rel_set(src, nameof(cell), thing)
	var/datum/got = rel_set(src, nameof(cell), thing)
	if(!rel_set(src, nameof(cell), thing))
		return null
	// another holder, a null value, an expression
	rel_set(thing, nameof(cell), null)
	rel_set(src, nameof(cell), new /datum())
	// over several lines, with a comment
	rel_set(src, // the holder
		nameof(cell), // the var
		thing) // the value
	// a text name stays as written; strings and comments that name it are untouched
	rel_set(src, "cell", thing)
	var/note = "own_set(src, nameof(cell), thing)"
	// own_set(src, nameof(cell), thing) is documented here
	return got
