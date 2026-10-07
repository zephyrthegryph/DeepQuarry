// entity_clone (doc/rewrite/ownership.md §1.4): a deep, ownership-correct copy.
//
// The owned subtree is serialised with the declared codecs (state.md; the ownership codecs in
// code/datums/state/codecs.dm) and re-materialised: owned children become new owned children,
// shared and proto references are copied by id, relations inside the subtree are rewired to the
// clones and relations leaving it are dropped. Replaces DuplicateObject's shallow var copy,
// which aliased every owned child between the original and the copy.

/// A clone of `D`. An atom materialises at `loc` (default: D's loc); a datum is adopted into
/// new_owner.slot when given. Mobs stay real (the serializer refuses them): a mob clone is a
/// fresh instance of its type. Returns null when D refuses serialisation.
/proc/entity_clone(datum/D, datum/new_owner = null, slot = null, loc = null)
	if(!isdatum(D) || QDELETED(D))
		return null
	var/datum/clone
	if(ismob(D))
		var/mob/M = D
		clone = new M.type(loc || M.loc)
	else if(isatom(D))
		var/atom/A = D
		var/list/errors = list()
		var/list/blob = state_serialize(A, STATE_FULL, errors)
		if(!blob)
			log_world("entity_clone: [A.type] refused: [jointext(errors, "; ")]")
			return null
		clone = state_materialize(blob, loc || (ismovable(A) ? A.loc : null), STATE_FULL, errors)
	else
		var/datum/state_context/ctx = new(NONE)
		ctx.ids = list()
		var/list/nested = ctx.serialize_datum(D, NONE)
		if(nested)
			clone = ctx.materialize_datum(nested)
		if(ctx.errors)
			log_world("entity_clone: [D.type] refused: [jointext(ctx.errors, "; ")]")
		spent(ctx)
	if(clone && new_owner && slot)
		if(islist(new_owner.vars[slot]))
			_own_add(new_owner, slot, clone)
		else
			_own_set(new_owner, slot, clone)
	return clone
