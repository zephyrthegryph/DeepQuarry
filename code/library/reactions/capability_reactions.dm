// Concrete capability table composition over the generic reaction declarations.
/// Capabilities carry their own reactions; an atom's table is its own plus each capability's.
/atom/reactions()
	. = ..()
	for(var/datum/capability/C as anything in caps_of(src))
		var/list/mine = C.reactions()
		if(length(mine))
			. += mine


/atom/reaction_holder_initialized()
	return !!(flags & ATOM_INITIALIZED)
