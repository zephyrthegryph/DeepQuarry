// The transaction API (doc/rewrite/containment.md §2, invariant 2).
//
//   thing.move_into(holder, slot_id, actor)          insert (slot_id null: the default slot)
//   holder.slot_remove(thing, destination, actor)     take out, to a place that has no slots
//   holder.slot_transfer(thing, new_holder, slot_id, actor)   from one slot to another
//   holder.slot_empty(slot_id, destination, actor)    remove everything in a slot
//   dq_ledger_refusal(thing, holder, slot_id, actor)  why a move would fail, or null
//
// Each move checks both sides first: the thing can leave its current slot
// (the slot's removal_refusal() and COMSIG_SLOT_PRE_REMOVE), and it can enter
// the new one (the slot's acceptance predicate, capacity and
// COMSIG_SLOT_PRE_INSERT). Nothing that can sleep runs in between: the check
// procs and the pre signals' handlers are SIGNAL_HANDLERs. Then the move
// commits with one forceMove, whose bookkeeping (ledger.dm) fires
// COMSIG_SLOT_REMOVED and COMSIG_SLOT_INSERTED. A refused move changes nothing.
//
// Drop policies: the base /atom/movable/Destroy() calls
// ledger_apply_drop_policies() before anything else, so no holder type
// decides what happens to its contents in its own Destroy().

/// Why `thing` can't go into `slot_id` (null: the default slot) on `holder`,
/// or null if it can. Checks both sides; changes nothing.
/proc/dq_ledger_refusal(atom/movable/thing, atom/holder, slot_id, mob/actor)
	if(!istype(thing) || QDELETED(thing))
		return "it is gone"
	if(!holder || QDELETED(holder))
		return "there is nowhere to put it"
	for(var/atom/A = holder; A; A = A.loc)
		if(A == thing)
			return "it can't go inside itself"
	var/datum/ledger/dest = dq_ledger(holder)
	if(!dest)
		return "[holder] can't hold anything"
	var/id = slot_id || dest.default_id
	var/datum/slot_def/def = dest.def_by_id(id)
	if(!def)
		return "[holder] has no [id]"
	var/list/entry = dest.entries[thing]
	if(entry && entry[LEDGER_E_SLOT] == id)
		return "it is already there"
	. = dq_ledger_removal_refusal(thing, actor)
	if(.)
		return .
	. = def.refusal(holder, thing, actor)
	if(.)
		return .
	if(def.capacity_model != SLOT_CAPACITY_NONE)
		var/cost = def.cost(holder, thing)
		if(dest.used[id] + cost > def.capacity_for(holder))
			return "there's no room for it"
	if(SEND_SIGNAL(holder, COMSIG_SLOT_PRE_INSERT, thing, id, actor) & COMPONENT_SLOT_BLOCK)
		return "it won't go in"
	return null

/// Why `thing` can't leave the slot it is in now, or null. Things not in a
/// slot can always leave.
/proc/dq_ledger_removal_refusal(atom/movable/thing, mob/actor)
	var/atom/source = thing.loc
	var/datum/ledger/from = dq_ledger(source)
	var/list/entry = from?.entries[thing]
	if(!entry)
		return null
	var/datum/slot_def/def = from.def_by_id(entry[LEDGER_E_SLOT])
	. = def.removal_refusal(source, thing, actor)
	if(.)
		return .
	if(SEND_SIGNAL(source, COMSIG_SLOT_PRE_REMOVE, thing, entry[LEDGER_E_SLOT], actor) & COMPONENT_SLOT_BLOCK)
		return "it won't come out"
	return null

/// Commits a checked move. Returns TRUE if the thing ended up in the slot.
/proc/dq_ledger_commit(atom/movable/thing, atom/holder, slot_id)
	var/datum/ledger/dest = holder.ledger
	var/id = slot_id || dest.default_id
	if(thing.loc == holder)
		dest.reslot(thing, id)
		return TRUE
	dest.pending_thing = thing
	dest.pending_slot = id
	thing.forceMove(holder)
	if(dest.pending_thing == thing)
		dest.pending_thing = null
		dest.pending_slot = null
	var/list/entry = dest.entries?[thing]
	return entry && entry[LEDGER_E_SLOT] == id

/// Insert into `holder`'s slot `slot_id` (null: its default slot). Returns
/// TRUE on success; on failure nothing moved, and dq_ledger_refusal() says why.
/atom/movable/proc/move_into(atom/holder, slot_id, mob/actor)
	if(dq_ledger_refusal(src, holder, slot_id, actor))
		return FALSE
	return dq_ledger_commit(src, holder, slot_id)

/// Take `thing` out of this holder's slots to `destination`. A destination
/// with slots makes this a transfer into its default slot.
/atom/proc/slot_remove(atom/movable/thing, atom/destination, mob/actor)
	var/datum/ledger/L = dq_ledger(src)
	if(!L?.entries[thing] || !destination || QDELETED(destination))
		return FALSE
	if(dq_slot_defs_for(destination))
		return thing.move_into(destination, null, actor)
	for(var/atom/A = destination; A; A = A.loc)
		if(A == thing)
			return FALSE
	if(dq_ledger_removal_refusal(thing, actor))
		return FALSE
	thing.forceMove(destination)
	return thing.loc == destination

/// Move `thing` from one of this holder's slots into `new_holder`'s slot.
/atom/proc/slot_transfer(atom/movable/thing, atom/new_holder, slot_id, mob/actor)
	var/datum/ledger/L = dq_ledger(src)
	if(!L?.entries[thing])
		return FALSE
	return thing.move_into(new_holder, slot_id, actor)

/// Remove everything in `slot_id` (null: every slot) to `destination`.
/// Returns how many things left.
/atom/proc/slot_empty(slot_id, atom/destination, mob/actor)
	. = 0
	// Pulling things out materializes them (C5).
	latent_materialize_all(slot_id)
	for(var/atom/movable/thing as anything in slot_contents(slot_id))
		if(slot_remove(thing, destination, actor))
			.++

/// A copy of what is in `slot_id` (null: every slot, in slot order).
/atom/proc/slot_contents(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return list()
	if(isnull(slot_id))
		return L.ordered()
	var/list/things = L.slots[slot_id]
	return things ? things.Copy() : list()

/// Capacity used in `slot_id`, in its capacity model's units.
/atom/proc/slot_used(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	return L?.used[slot_id || L.default_id] || 0

/// The limit of `slot_id` on this holder, or null when it has none.
/atom/proc/slot_capacity(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	var/datum/slot_def/def = L?.def_by_id(slot_id || L.default_id)
	if(!def || def.capacity_model == SLOT_CAPACITY_NONE)
		return null
	return def.capacity_for(src)

/// Aggregate of measure `id` over everything in this holder, nested holders
/// included. Null when empty or when this holds no slots.
/atom/proc/contents_property(id)
	var/datum/ledger/L = dq_ledger(src)
	return L?.aggregate(id)

/// Whether anything in this holder, nested holders included, has `tag`.
/atom/proc/contents_has_tag(tag)
	var/datum/ledger/L = dq_ledger(src)
	return L ? L.has_tag(tag) : FALSE

/// The entry id of `thing` in this holder ("interior#12"), or null.
/atom/proc/slot_entry_id(atom/movable/thing)
	var/datum/ledger/L = dq_ledger(src)
	return L?.entry_id(thing)

/// The thing an entry id names, or null if the id is stale.
/atom/proc/slot_find_entry(entry_id)
	var/datum/ledger/L = dq_ledger(src)
	return L?.find_entry(entry_id)

/// The base Destroy() calls this first. Each slot's drop policy decides what
/// happens to what it holds; things with nowhere to go are deleted.
/atom/movable/proc/ledger_apply_drop_policies()
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return
	var/atom/drop = drop_location()
	for(var/datum/slot_def/def as anything in L.defs)
		var/list/things = L.slots[def.id]
		for(var/atom/movable/thing as anything in things.Copy())
			if(QDELETED(thing))
				continue
			switch(def.drop_policy)
				if(SLOT_DROP_DELETE)
					qdel(thing)
					continue
				if(SLOT_DROP_TRANSFER)
					if(loc && dq_slot_defs_for(loc) && thing.move_into(loc))
						continue
			if(drop && !QDELETED(drop))
				thing.forceMove(drop)
			if(thing.loc == src)
				qdel(thing)
	ledger_drop_latent(L, drop)

/// Drop policies for latent entries, as data (damage.md §6): deleted entries
/// are removed; spilled or transferred ones stay latent if they land in
/// another latent holder, and are created only where they land on a turf.
/atom/movable/proc/ledger_drop_latent(datum/ledger/L, atom/drop)
	for(var/datum/latent_entry/entry as anything in L.latent_list())
		var/datum/slot_def/def = L.def_by_id(entry.slot)
		var/path = entry.path
		var/list/blob = entry.blob
		var/n = entry.count
		L.latent_set_count(entry, 0)
		if(def.drop_policy == SLOT_DROP_DELETE)
			continue
		var/atom/target = drop
		if(def.drop_policy == SLOT_DROP_TRANSFER && loc && dq_slot_defs_for(loc))
			target = loc
		if(!target || QDELETED(target))
			continue
		if(!isturf(target) && target.latent_add(path, n, blob))
			continue
		for(var/i in 1 to n)
			dq_latent_create(path, blob, target)
