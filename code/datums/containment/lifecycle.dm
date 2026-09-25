// Contents phases of the destroy transaction (L1, doc/rewrite/lifecycle.md
// §2-3): phase 0.5 (mind, pre-order, whole tree) and phase 3 (everything
// else, post-order per holder). Both are called from destroy_transaction()
// (code/datums/lifecycle/transaction.dm); nothing else calls them.
//
// "Children before parents" falls out of ordinary qdel() recursion: a
// SLOT_DROP_DELETE entry is qdel'd right here, and qdel() runs that child's
// *entire* transaction -- including its own phase 3 -- before returning
// control to this loop. There is nothing extra to do to get post-order.

/// Phase 0.5. Resolves every is_mind_slot across `root`'s whole holder tree,
/// pre-order (root before its children, so a body's mind slot resolves
/// before a head's, before a brain's): the mob is still fully registered and
/// has a loc when each TRANSFER(mind) resolver runs. A no-op today -- no
/// slot_def sets is_mind_slot yet (DQ Medical, O2) -- and cheap when so: one
/// ledger peek and a defs walk per holder in the tree, nothing per thing.
/proc/dq_lifecycle_resolve_minds(atom/movable/root)
	var/datum/ledger/L = dq_ledger_peek(root)
	if(L)
		for(var/datum/slot_def/def as anything in L.defs)
			if(!def.is_mind_slot)
				continue
			var/list/things = L.slots[def.id]
			if(!length(things))
				continue
			var/atom/drop = root.drop_location()
			for(var/atom/movable/thing as anything in things.Copy())
				if(!QDELETED(thing))
					dq_lifecycle_resolve_slot_entry(root, def, thing, drop, null)
	for(var/atom/movable/child as anything in root.contents)
		dq_lifecycle_resolve_minds(child)

/// Phase 3. Resolves every slot's declared policy for `src`'s own contents
/// (not recursing into children beyond what qdel() already does for
/// SLOT_DROP_DELETE -- see file header). Skips is_mind_slot entries: phase
/// 0.5 already resolved those, tree-wide, before this ever runs.
/atom/movable/proc/dq_lifecycle_resolve_contents()
	var/datum/ledger/L = dq_ledger(src) // builds it (and resolves a latent generator) if this is its first use
	if(!L)
		// A holder deleted before it ever became live (an unmaterialized probe, such as the
		// storage cost probe) never resolved its declared latent contents: they are only a
		// declaration, and nothing of them exists to release.
		if(!(flags & ATOM_MATERIALIZED))
			latent_contents = FALSE
		return
	var/atom/drop = drop_location()
	var/atom/movable/successor = lifecycle_successor
	for(var/datum/slot_def/def as anything in L.defs)
		if(def.drop_policy == SLOT_DROP_HOLDER || def.is_mind_slot)
			continue
		var/list/things = L.slots[def.id]
		for(var/atom/movable/thing as anything in things.Copy())
			if(!QDELETED(thing))
				dq_lifecycle_resolve_slot_entry(src, def, thing, drop, successor)
	dq_lifecycle_resolve_latent(L, drop, successor)

/// Applies `def`'s policy to the one `thing` already in its slot on `holder`.
/proc/dq_lifecycle_resolve_slot_entry(atom/movable/holder, datum/slot_def/def, atom/movable/thing, atom/drop, atom/movable/successor)
	var/flags = LEDGER_MOVE_FORCED | LEDGER_MOVE_DESTROYING
	switch(def.drop_policy)
		if(SLOT_DROP_DELETE)
			qdel(thing)
			return
		if(SLOT_DROP_TO_LATENT)
			var/atom/movable/target = def.latent_successor(holder)
			if(target && !QDELETED(target))
				var/list/blob = dq_stock_blob(thing)
				if(target.latent_add(thing.type, 1, blob))
					qdel(thing)
					return
			// No successor yet (debris/wreckage not built here): the data
			// would just be lost either way, so it goes with the holder.
			qdel(thing)
			return
		if(SLOT_DROP_KEEP_WITH)
			if(successor && !QDELETED(successor))
				if(dq_ledger_force_move(thing, successor, flags, def.keep_with_slot()))
					return
			// No successor (an ordinary delete, not a replace_with()), or
			// the successor refused it: spill below, same as SLOT_DROP_SPILL.
		if(SLOT_DROP_TRANSFER)
			var/atom/target = def.drop_resolver(holder, thing, drop)
			if(target && !QDELETED(target) && dq_ledger_force_move(thing, target, flags))
				return
			// The resolver named nothing, or was refused: spill below, same
			// as SLOT_DROP_SPILL. (DM's switch doesn't fall between cases --
			// this is its own branch reached only when drop_policy is
			// SLOT_DROP_TRANSFER, not a continuation of the KEEP_WITH case.)
	if(drop && !QDELETED(drop))
		dq_ledger_force_move(thing, drop, flags)
	if(thing.loc == holder)
		qdel(thing)

/// Drop policies for latent entries, as data (damage.md §6): deleted entries
/// are removed; SPILL/TRANSFER/TO_LATENT/KEEP_WITH entries stay latent if
/// they land in another latent holder, and are created only where they land
/// on a turf. Mirrors dq_lifecycle_resolve_slot_entry() for real things.
/proc/dq_lifecycle_resolve_latent(datum/ledger/L, atom/drop, atom/movable/successor)
	var/atom/movable/holder = L.holder
	for(var/datum/latent_entry/entry as anything in L.latent_list())
		var/datum/slot_def/def = L.def_by_id(entry.slot)
		var/path = entry.path
		var/list/blob = entry.blob
		var/n = entry.count
		L.latent_set_count(entry, 0)
		if(def.drop_policy == SLOT_DROP_DELETE)
			continue
		var/atom/target
		switch(def.drop_policy)
			if(SLOT_DROP_TO_LATENT)
				target = def.latent_successor(holder)
			if(SLOT_DROP_KEEP_WITH)
				target = successor
			if(SLOT_DROP_TRANSFER)
				target = def.drop_resolver(holder, null, drop)
		if(!target)
			target = drop
		if(!target || QDELETED(target))
			continue
		if(!isturf(target) && target.latent_add(path, n, blob))
			continue
		for(var/i in 1 to n)
			dq_latent_create(path, blob, target)

/// L3 (doc/rewrite/lifecycle.md §5): the successor replace_with() is
/// building, set just before it qdels the original. SLOT_DROP_KEEP_WITH
/// slots move their contents here instead of spilling; read (and cleared)
/// only by dq_lifecycle_resolve_contents()/dq_lifecycle_resolve_latent()
/// during this one transaction.
/atom/movable/var/tmp/atom/movable/lifecycle_successor
