/datum/holder
	var/list/datum/parts
	var/list/items

/datum/holder/proc/fill(datum/thing, mob/user, datum/holder/other)
	// a statement and a value that is used
	own_add(src, nameof(parts), thing)
	var/datum/got = own_add(src, nameof(parts), thing)
	if(!own_add(src, nameof(parts), thing))
		return null
	// another holder, a null value, an expression
	own_add(other, nameof(parts), null)
	own_add(src, nameof(parts), new /datum())
	// over several lines, with a comment
	own_add(src, // the holder
		nameof(parts), // the var
		thing) // the value
	// a text name stays as written; strings and comments that name it are untouched
	own_add(src, "parts", thing)
	var/note = "own_add(src, nameof(parts), thing)"
	// own_add(src, nameof(parts), thing) is documented here
	return got
