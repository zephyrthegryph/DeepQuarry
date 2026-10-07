// Contents phases of the destroy transaction (L1, doc/rewrite/lifecycle.md
// Â§2-3): phase 0.5 (mind, pre-order, whole tree) and phase 3 (everything
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
		for(var/datum/relation_definition/slot/def as anything in L.defs)
			if(!def.is_mind_slot)
				continue
			var/list/things = L.slots[def.slot_id]
			if(!length(things))
				continue
			var/atom/drop = root.containment_drop_location()
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
	var/datum/ledger/L = dq_ledger(src, destroying = TRUE) // builds it (and resolves a latent generator) if this is its first use
	if(!L)
		return
	var/atom/drop = containment_drop_location()
	var/atom/movable/successor = containment_successor()
	// Slot types that keep latent contents of their own (stock records) apply their policy to
	// them first; the ledger then handles the real things. The L1 move lost this call.
	for(var/datum/relation_definition/slot/def as anything in L.defs)
		if(!def.is_mind_slot)
			def.drop_latent(src, drop)
	for(var/datum/relation_definition/slot/def as anything in L.defs)
		if(def.drop_policy == SLOT_DROP_HOLDER || def.is_mind_slot)
			continue
		var/list/things = L.slots[def.slot_id]
		for(var/atom/movable/thing as anything in things.Copy())
			if(!QDELETED(thing))
				dq_lifecycle_resolve_slot_entry(src, def, thing, drop, successor)
	dq_lifecycle_resolve_latent(L, drop, successor)

/// End of phase 3: the contents phase must have carried out every slot's policy. Checked here,
/// while the ledger still exists: phase 4 disposes of its runtime-owned ledger through
/// clear_containment_ledger(), so a later destroy check would read a missing ledger and
/// reported holder-kept contents (a machine's radio, a sleeper's beaker) as unreleased.
/atom/movable/proc/dq_lifecycle_check_released()
	if((containment_ledger() || dq_slot_defs_for(src)) && dq_holds_unreleased())
		stack_trace("[type] still holds contents/latent entries after the destroy transaction's contents phase -- it should have released them: [dq_unreleased_report()]")

/// The contents phase's check that it did its job: TRUE when something still sits in a
/// slot whose policy the transaction must carry out. SLOT_DROP_HOLDER slots (a mob's worn and
/// held items) and mind slots keep their contents on purpose: the base Destroy() deletes them.
/atom/movable/proc/dq_holds_unreleased()
	if(!length(contents) && !has_latent())
		return FALSE
	var/datum/ledger/L = containment_ledger()
	if(!L)
		// No ledger: phase 3 had nothing to go on, so only holder-kept slot sets are fine.
		for(var/datum/relation_definition/slot/def as anything in dq_slot_defs_for(src))
			if(def.drop_policy != SLOT_DROP_HOLDER && !def.is_mind_slot)
				return TRUE
		return FALSE
	for(var/datum/relation_definition/slot/def as anything in L.defs)
		if(def.drop_policy == SLOT_DROP_HOLDER || def.is_mind_slot)
			continue
		if(length(L.slots[def.slot_id]) || length(L.latent_list(def.slot_id)))
			return TRUE
	return FALSE

/// What dq_holds_unreleased() objected to, for Destroy()'s stack trace: each offending slot with
/// its real things and latent entry count, plus contents no slot accounts for.
/atom/movable/proc/dq_unreleased_report()
	var/list/parts = list()
	var/datum/ledger/L = containment_ledger()
	if(!L)
		parts += "no ledger (latent_contents=[latent_contents_enabled()], latent_declared=[latent_is_declared()], generator lines=[length(latent_generator())])"
		for(var/atom/movable/thing as anything in contents)
			parts += "[thing] ([thing.type])"
		return jointext(parts, "; ")
	for(var/datum/relation_definition/slot/def as anything in L.defs)
		if(def.drop_policy == SLOT_DROP_HOLDER || def.is_mind_slot)
			continue
		var/list/things = L.slots[def.slot_id]
		var/list/names = list()
		for(var/atom/movable/thing as anything in things)
			names += "[thing] ([thing.type], loc=[thing.loc == src ? "holder" : thing.loc])"
		var/latent_n = length(L.latent_list(def.slot_id))
		if(length(names) || latent_n)
			parts += "slot [def.slot_id] (policy [def.drop_policy]): [jointext(names, ", ")] latent entries=[latent_n]"
	return jointext(parts, "; ")

/// Applies `def`'s policy to the one `thing` already in its slot on `holder`.
/proc/dq_lifecycle_resolve_slot_entry(atom/movable/holder, datum/relation_definition/slot/def, atom/movable/thing, atom/drop, atom/movable/successor)
	var/flags = LEDGER_MOVE_FORCED | LEDGER_MOVE_DESTROYING
	switch(def.drop_policy)
		if(SLOT_DROP_DELETE)
			spent(thing)
			return
		if(SLOT_DROP_TO_LATENT)
			var/atom/movable/target = def.latent_successor(holder)
			if(target && !QDELETED(target))
				var/list/blob = dq_stock_blob(thing)
				if(target.latent_add(thing.type, 1, blob))
					spent(thing)
					return
			// No successor yet (debris/wreckage not built here): the data
			// would just be lost either way, so it goes with the holder.
			spent(thing)
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
		spent(thing)

/// Drop policies for latent entries, as data (damage.md Â§6): deleted (and
/// holder-kept) entries are removed; SPILL/TRANSFER/TO_LATENT/KEEP_WITH entries stay latent if
/// they land in another latent holder, and are created only where they land
/// on a turf. Mirrors dq_lifecycle_resolve_slot_entry() for real things.
/proc/dq_lifecycle_resolve_latent(datum/ledger/L, atom/drop, atom/movable/successor)
	var/atom/movable/holder = L.holder
	for(var/datum/latent_entry/entry as anything in L.latent_list())
		var/datum/relation_definition/slot/def = L.def_by_id(entry.slot)
		var/path = entry.path
		var/list/blob = entry.blob
		var/n = entry.count
		L.latent_set_count(entry, 0)
		// SLOT_DROP_HOLDER: the base Destroy() deletes a holder-kept slot's real contents
		// (a machine's board and parts, a body's worn items), so its latent entries go with
		// the holder too. Spilling them made every deleted machine drop its unbuilt parts.
		if(def.drop_policy == SLOT_DROP_DELETE || def.drop_policy == SLOT_DROP_HOLDER)
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

/// L3 (doc/rewrite/lifecycle.md Â§5): the successor replace_with() is
/// building, set just before it qdels the original. SLOT_DROP_KEEP_WITH
/// slots move their contents here instead of spilling; read (and cleared)
/// only by dq_lifecycle_resolve_contents()/dq_lifecycle_resolve_latent()
/// during this one transaction.
// Scoped to one destroy transaction; set and cleared by dq_lifecycle_resolve_contents()/_latent()
