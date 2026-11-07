// germs: lazy state of /atom (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, germs, field), write with STATE_SET(A, germs, field, value), end it with germs_clear(A).
//
// A row of its own, not a field of atom_misc: a lazy state publishes its feature key on every write, and a human's draw reads atom_misc (its
// colours), so a germ tick on a walking person (one step in twelve) redrew the whole body.

/datum/germs_state
	parent_type = /datum/lazy_state
	/// Surface germs; null while the type's default (germs() / set_germs()).
	var/surface_germs
