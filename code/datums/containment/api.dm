// The transaction API (doc/rewrite/containment.md §2, invariant 2).
//
//   thing.move_into(holder, slot_id, actor)          insert (slot_id null: the default slot)
//   holder.slot_remove(thing, destination, actor, flags)     take out, to a place that has no slots
//   holder.slot_transfer(thing, new_holder, slot_id, actor)   from one slot to another
//   holder.slot_empty(slot_id, destination, actor)    remove everything in a slot
//   holder.slot_item(slot_id)                         the one thing in a single-item slot, or null
//   holder.slot_lookup(slot_id, key)                  the thing keyed `key` in a keyed slot, or null
//   dq_ledger_refusal(thing, holder, slot_id, actor)  why a move would fail, or null
//
// Each move checks both sides first: the thing can leave its current slot
// (the slot's removal_refusal() and COMSIG_SLOT_PRE_REMOVE), and it can enter
// the new one (the slot's acceptance predicate, capacity, a keyed slot's
// duplicate-key check, and COMSIG_SLOT_PRE_INSERT). Nothing that can sleep
// runs in between: the check procs and the pre signals' handlers are
// SIGNAL_HANDLERs. Then the move commits with one forceMove, whose
// bookkeeping (ledger.dm) fires COMSIG_SLOT_REMOVED/COMSIG_SLOT_INSERTED and
// the thing's on_unslotted()/on_slotted() hooks. A refused move changes
// nothing.
//
// slot_remove() takes a LEDGER_MOVE_FORCED flag that skips both refusals and
// both pre signals but still runs the same commit bookkeeping (J2): used to
// spill or transfer a holder's contents while it is being destroyed, where
// the move must not be refusable.
//
// Drop policies: the destroy transaction (L1, doc/rewrite/lifecycle.md §2)
// resolves every slot's declared policy in its contents phase, before any
// leftover Destroy() runs, so no holder type decides what happens to its
// contents by hand (code/datums/containment/lifecycle.dm).

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
	var/datum/om/relation/slot/def = dest.def_by_id(id)
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
	if(def.keyed)
		var/key = thing.slot_key()
		if(!isnull(key))
			var/atom/movable/existing = dest.slot_lookup(id, key)
			if(existing && existing != thing)
				return "[existing] already has that"
	if(def.capacity_model != SLOT_CAPACITY_NONE)
		var/cost = def.cost(holder, thing)
		if(dest.used[id] + def.latent_used(holder) + cost > def.capacity_for(holder))
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
	var/datum/om/relation/slot/def = from.def_by_id(entry[LEDGER_E_SLOT])
	. = def.removal_refusal(source, thing, actor)
	if(.)
		return .
	if(SEND_SIGNAL(source, COMSIG_SLOT_PRE_REMOVE, thing, entry[LEDGER_E_SLOT], actor) & COMPONENT_SLOT_BLOCK)
		return "it won't come out"
	return null

/// Commits a checked move. Returns TRUE if the thing ended up in the slot.
/// `flags` (LEDGER_MOVE_*) reaches note_enter()/reslot() and, through them,
/// on_slotted()/on_unslotted() (J6).
/proc/dq_ledger_commit(atom/movable/thing, atom/holder, slot_id, flags = 0)
	var/datum/ledger/dest = holder.ledger
	var/id = slot_id || dest.default_id
	if(thing.loc == holder)
		dest.reslot(thing, id, flags)
		return TRUE
	dest.pending_thing = thing
	dest.pending_slot = id
	dest.pending_flags = flags
	var/datum/ledger/source = dq_ledger_peek(thing.loc)
	if(source)
		source.pending_exit_flags = flags
	thing.forceMove(holder)
	if(dest.pending_thing == thing)
		dest.pending_thing = null
		dest.pending_slot = null
		dest.pending_flags = null
	var/list/entry = dest.entries?[thing]
	return entry && entry[LEDGER_E_SLOT] == id

/// Insert into `holder`'s slot `slot_id` (null: its default slot). Returns
/// TRUE on success; on failure nothing moved, and dq_ledger_refusal() says why.
/atom/movable/proc/move_into(atom/holder, slot_id, mob/actor)
	if(dq_ledger_refusal(src, holder, slot_id, actor))
		return FALSE
	return dq_ledger_commit(src, holder, slot_id)

/// Take `thing` out of this holder's slots to `destination`. A destination
/// with slots makes this a transfer into its default slot. `flags` may carry
/// LEDGER_MOVE_FORCED (J2): both refusals and pre signals are skipped, but
/// the commit bookkeeping still runs, same as any other move. LEDGER_MOVE_DESTROYING
/// (L1) always accompanies FORCED when the destroy transaction is the mover.
/atom/proc/slot_remove(atom/movable/thing, atom/destination, mob/actor, flags = 0)
	var/datum/ledger/L = dq_ledger(src)
	if(!L?.entries[thing] || !destination || QDELETED(destination))
		return FALSE
	if(flags & LEDGER_MOVE_FORCED)
		return dq_ledger_force_move(thing, destination, flags)
	if(dq_slot_defs_for(destination))
		return thing.move_into(destination, null, actor)
	for(var/atom/A = destination; A; A = A.loc)
		if(A == thing)
			return FALSE
	if(dq_ledger_removal_refusal(thing, actor))
		return FALSE
	thing.forceMove(destination)
	return thing.loc == destination

/// LEDGER_MOVE_FORCED's move: straight to the commit, no refusal checked and
/// no pre signal sent on either side. If `destination` has slots, `thing`
/// lands in `slot_id` (null: its default slot); otherwise this is a plain
/// forced forceMove. Either way doMove()'s bookkeeping (note_exit/note_enter,
/// COMSIG_SLOT_*, on_unslotted()/on_slotted()) runs as normal, carrying
/// `flags` to the hooks. L1's contents phase (lifecycle.dm) is the only
/// caller that ever names an explicit `slot_id` (KEEP_WITH).
/proc/dq_ledger_force_move(atom/movable/thing, atom/destination, flags = 0, slot_id = null)
	for(var/atom/A = destination; A; A = A.loc)
		if(A == thing)
			return FALSE
	if(dq_slot_defs_for(destination))
		dq_ledger(destination)
		return dq_ledger_commit(thing, destination, slot_id, flags)
	var/datum/ledger/source = dq_ledger_peek(thing.loc)
	if(source)
		source.pending_exit_flags = flags
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
	if(!L)
		return 0
	var/id = slot_id || L.default_id
	var/datum/om/relation/slot/def = L.def_by_id(id)
	return (L.used[id] || 0) + (def ? def.latent_used(src) : 0)

/// The limit of `slot_id` on this holder, or null when it has none.
/atom/proc/slot_capacity(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	var/datum/om/relation/slot/def = L?.def_by_id(slot_id || L.default_id)
	if(!def || def.capacity_model == SLOT_CAPACITY_NONE)
		return null
	return def.capacity_for(src)

/// The one thing in `slot_id` (null: the default slot), or null if it holds
/// none. For a single-item slot (organ, equipment): the whole point of
/// slot_item() over slot_contents() is not building a copied list to read
/// one entry (J8).
/atom/proc/slot_item(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return null
	var/id = slot_id || L.default_id
	var/list/things = L.slots[id]
	return length(things) ? things[1] : null

/// The thing keyed `key` in `slot_id` on this holder, or null (J4). O(1).
/atom/proc/slot_lookup(slot_id, key)
	var/datum/ledger/L = dq_ledger(src)
	return L?.slot_lookup(slot_id, key)

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

// The destroy transaction's contents phase (L1, doc/rewrite/lifecycle.md §2-3)
// replaces what used to live here (ledger_apply_drop_policies(),
// ledger_drop_latent()): see code/datums/containment/lifecycle.dm.
