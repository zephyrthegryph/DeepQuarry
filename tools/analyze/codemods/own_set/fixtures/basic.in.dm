/datum/holder
	var/datum/cell
	var/list/items

/datum/holder/proc/fill(datum/thing, mob/user, datum/holder/other)
	// a statement and a value that is used
	own_set(src, nameof(cell), thing)
	var/datum/got = own_set(src, nameof(cell), thing)
	if(!own_set(src, nameof(cell), thing))
		return null
	// another holder, a null value, an expression
	own_set(other, nameof(cell), null)
	own_set(src, nameof(cell), new /datum())
	// over several lines, with a comment
	own_set(src, // the holder
		nameof(cell), // the var
		thing) // the value
	// a text name stays as written; strings and comments that name it are untouched
	own_set(src, "cell", thing)
	var/note = "own_set(src, nameof(cell), thing)"
	// own_set(src, nameof(cell), thing) is documented here
	return got
