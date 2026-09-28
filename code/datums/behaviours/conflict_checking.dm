/**
 * Simple conflict checking for getting number of conflicting things on someone with the same ID
 * (was /datum/element/conflict_checking). Atom state: `conflict_id`, read directly.
 */
/atom
	/// CONFLICT_ELEMENT_* id counted by ConflictElementCount(), or null.
	var/conflict_id

/**
 * Counts number of conflicts on something that have the conflict id `id`.
 */
/atom/proc/ConflictElementCount(id)
	. = 0
	for(var/i in GetAllContents())
		var/atom/movable/AM = i
		if(AM.conflict_id == id)
			++.
