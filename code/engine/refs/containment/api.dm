// The transaction API (doc/rewrite/containment.md Â§2, invariant 2).
//
//   move_into(holder, slot_id, thing, actor)          insert (slot_id null: the default slot)
//   holder.slot_remove(thing, destination, actor, flags)     take out, to a place that has no slots
//   holder.slot_transfer(thing, new_holder, slot_id, actor)   from one slot to another
//   holder.slot_empty(slot_id, destination, actor)    remove everything in a slot
//   holder.slot_item(slot_id)                         the one thing in a single-item slot, or null
//   holder.slot_lookup(slot_id, key)                  the thing keyed `key` in a keyed slot, or null
//   dq_ledger_refusal(thing, holder, slot_id, actor)  why a move would fail, or null
//
// Each move checks both sides first: the thing can leave its current slot
// (the slot's removal_refusal() and /datum/act/check_remove), and it can enter
// the new one (the slot's acceptance predicate, capacity, a keyed slot's
// duplicate-key check, and /datum/act/check_insert). Nothing that can sleep
// runs in between: the check procs and the check hooks' handlers are
// synchronous typed action handlers. Then the move commits with one forceMove, whose
// bookkeeping (ledger.dm) fires /datum/notice/slot_removed and /datum/notice/slot_inserted and
// the thing's on_unslotted()/on_slotted() hooks. A refused move changes
// nothing.
//
// slot_remove() takes a LEDGER_MOVE_FORCED flag that skips both refusals and
// both pre signals but still runs the same commit bookkeeping (J2): used to
// spill or transfer a holder's contents while it is being destroyed, where
// the move must not be refusable.
//
// Drop policies: the destroy transaction (L1, doc/rewrite/lifecycle.md Â§2)
// resolves every slot's declared policy in its contents phase, before any
// leftover Destroy() runs, so no holder type decides what happens to its
// contents by hand (code/datums/containment/lifecycle.dm).

/// Why `thing` can't go into `slot_id` (null: the default slot) on `holder`,
/// or null if it can. Checks both sides; changes nothing. `check_removal = FALSE`
/// skips the source side, for a caller that asked the thing's current place
/// itself (the one-call transfer's release_refusal(), ownership/transfer.dm).
/proc/dq_ledger_refusal(atom/movable/thing, atom/holder, slot_id, mob/actor, check_removal = TRUE)
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
	var/datum/relation_definition/slot/def = dest.def_by_id(id)
	if(!def)
		return "[holder] has no [id]"
	var/list/entry = dest.entries[thing]
	if(entry && entry[LEDGER_E_SLOT] == id)
		return "it is already there"
	if(check_removal)
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
	// A hook on the holder (observe(holder, /datum/act/check_insert, ...)) may refuse the move: the question, not the move, so it never commits.
	GLOB.act_next_actor = actor
	var/datum/act/check_insert/check = ACT_TRY(holder, check_insert, thing, id)
	GLOB.act_next_actor = null
	if(!check)
		return "it won't go in"
	act_cancel(check)
	return null

/// Why `thing` can't leave the slot it is in now, or null. Things not in a
/// slot can always leave.
/proc/dq_ledger_removal_refusal(atom/movable/thing, mob/actor)
	var/atom/source = thing.loc
	var/datum/ledger/from = dq_ledger(source)
	var/list/entry = from?.entries[thing]
	if(!entry)
		return null
	var/datum/relation_definition/slot/def = from.def_by_id(entry[LEDGER_E_SLOT])
	. = def.removal_refusal(source, thing, actor)
	if(.)
		return .
	GLOB.act_next_actor = actor
	var/datum/act/check_remove/check = ACT_TRY(source, check_remove, thing, entry[LEDGER_E_SLOT])
	GLOB.act_next_actor = null
	if(!check)
		return "it won't come out"
	act_cancel(check)
	return null

/// Commits a checked move. Returns TRUE if the thing ended up in the slot.
/// `flags` (LEDGER_MOVE_*) reaches note_enter()/reslot() and, through them,
/// on_slotted()/on_unslotted() (J6).
/proc/dq_ledger_commit(atom/movable/thing, atom/holder, slot_id, flags = 0)
	var/datum/ledger/dest = holder.containment_ledger()
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
	thing.containment_move(holder)
	if(dest.pending_thing == thing)
		dest.pending_thing = null
		dest.pending_slot = null
		dest.pending_flags = null
	var/list/entry = dest.entries?[thing]
	return entry && entry[LEDGER_E_SLOT] == id

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
	if(dq_slot_defs_for(destination)) // the ledger's own checked commit: the place releases through here, so it can't go through move_into()
		if(dq_ledger_refusal(thing, destination, null, actor))
			return FALSE
		return dq_ledger_commit(thing, destination, null)
	for(var/atom/A = destination; A; A = A.loc)
		if(A == thing)
			return FALSE
	if(dq_ledger_removal_refusal(thing, actor))
		return FALSE
	thing.containment_move(destination)
	return thing.loc == destination

/**
 * The slot-link form: `thing` stops holding the slot it is in and is filed under this holder's default slot, without being moved. A machine whose
 * occupant came out as remains (a gibbed synthetic's wreck) keeps them physically inside, but they are no longer "the occupant": the occupant slot
 * empties, its occupancy is published and the slot hooks of both slots run, as for any other reslot. Returns TRUE when the thing was released; FALSE
 * when it is not in this holder, or already is in the default slot.
 */
/atom/proc/slot_release(atom/movable/thing)
	var/datum/ledger/L = dq_ledger_peek(src)
	var/list/entry = L?.entries[thing]
	if(!entry || thing.loc != src || entry[LEDGER_E_SLOT] == L.default_id)
		return FALSE
	L.reslot(thing, L.default_id, LEDGER_MOVE_FORCED)
	return TRUE

/// LEDGER_MOVE_FORCED's move: straight to the commit, no refusal checked and
/// no pre signal sent on either side. If `destination` has slots, `thing`
/// lands in `slot_id` (null: its default slot); otherwise this is a plain
/// forced forceMove. Either way doMove()'s bookkeeping (note_exit/note_enter,
/// the slot_* OM events, on_unslotted()/on_slotted()) runs as normal, carrying
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
	thing.containment_move(destination)
	return thing.loc == destination

/**
 * Move `thing` from one of this holder's slots into `new_holder`'s slot (`slot_id`, null: its default slot). A transfer is a remove and an
 * insert and always runs both as world actions, with their hooks (ACT_TRY of /datum/act/remove on this holder, then /datum/act/insert on
 * `new_holder`, each carrying `actor`): a belly's consent requirement or a bay's accepts is a needs() hook that refuses it like any other
 * move, an instead() takes it over, and the notices of both go out when it lands. Then both ledger checks run (dq_ledger_refusal()) and the move
 * commits. A refused or taken-over transfer changes nothing; the reason is GLOB.act_last_reason. Returns TRUE when it landed.
 *
 * `authority` is an AUTH_* mask; only AUTH_ADMIN forces the transfer: the needs() hooks and both ledger refusals are skipped, the actions, their
 * instead()/adjusts() hooks and notices and the commit bookkeeping still run. There is no other bypass.
 */
/atom/proc/slot_transfer(atom/movable/thing, atom/new_holder, slot_id, mob/actor, authority = null)
	var/datum/ledger/L = dq_ledger(src)
	var/list/entry = L?.entries[thing]
	if(!entry || !new_holder || QDELETED(new_holder))
		return FALSE
	if(!isnull(authority) && !isnum(authority))
		stack_trace("slot_transfer(): authority is an AUTH_* mask, got [authority]")
		return FALSE
	var/forced = !!(authority & AUTH_ADMIN)
	var/from_slot = entry[LEDGER_E_SLOT]
	GLOB.act_next_actor = actor
	GLOB.act_next_authority = authority
	var/datum/act/remove/leaving = ACT_TRY(src, remove, thing, from_slot)
	GLOB.act_next_actor = null
	GLOB.act_next_authority = null
	if(isnull(leaving))
		log_world("SLOT_TRANSFER: [thing] out of [src] ([from_slot]) refused or taken over ([GLOB.act_last_reason])")
		return FALSE
	GLOB.act_next_actor = actor
	GLOB.act_next_authority = authority
	var/datum/act/insert/entering = ACT_TRY(new_holder, insert, thing, slot_id)
	GLOB.act_next_actor = null
	GLOB.act_next_authority = null
	if(isnull(entering))
		var/refused_for = GLOB.act_last_reason
		var/refused_how = GLOB.act_last_outcome
		act_cancel(leaving)
		GLOB.act_last_reason = refused_for // cancelling the removal must not hide why the insert was refused
		GLOB.act_last_outcome = refused_how
		log_world("SLOT_TRANSFER: [thing] into [new_holder] ([slot_id || "default"]) refused or taken over ([GLOB.act_last_reason])")
		return FALSE
	var/into_slot = ACT_FINAL(entering, slot_id, slot_id)
	var/landed = FALSE
	if(forced)
		log_world("SLOT_TRANSFER: FORCED [thing] from [src] ([from_slot]) to [new_holder] ([into_slot || "default"]) by [actor ? key_name(actor) : "the game"]")
		landed = dq_ledger_force_move(thing, new_holder, LEDGER_MOVE_FORCED, into_slot)
	else if(!dq_ledger_refusal(thing, new_holder, into_slot, actor))
		landed = dq_ledger_commit(thing, new_holder, into_slot)
	if(!landed)
		var/failed_for = GLOB.act_last_reason
		act_cancel(entering)
		act_cancel(leaving)
		GLOB.act_last_reason = failed_for
		return FALSE
	TEST_REC_TRANSFER(thing, src, new_holder, into_slot)
	act_done(leaving)
	act_done(entering)
	return TRUE

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
	var/datum/relation_definition/slot/def = L.def_by_id(id)
	return (L.used[id] || 0) + (def ? def.latent_used(src) : 0)

/// How many things are in `slot_id` (null: the default slot) right now. The occupancy count a requirement may read: the ledger writes it (move_into()
/// and every release land in note_enter/note_exit) and publishes SLOT_OCCUPANCY_KEY, which this accessor stands for (READS_AS below).
/atom/proc/slot_occupancy(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return 0
	var/list/things = L.slots[slot_id || L.default_id]
	return length(things)

READS_AS(/atom/proc/slot_occupancy, SLOT_OCCUPANCY_KEY)

/**
 * The types of what `slot_id` (null: the default slot) holds that are a `type`: a real thing by its own type, a latent one by its entry's type, once each.
 * Nothing is materialized and no generator is rolled: a holder that has not yet declared its generator answers from the declared lines (the types it
 * will hold), one with a ledger from the ledger. A look draw reads it through look.contents_of(), which stands for SLOT_OCCUPANCY_KEY.
 */
/atom/proc/slot_kinds(slot_id, type = /atom/movable)
	RETURN_TYPE(/list)
	. = list()
	var/datum/ledger/L = containment_ledger()
	if(!L && latent_contents_enabled() && !latent_is_declared())
		var/list/generator = latent_generator()
		if(length(generator))
			for(var/path in generator)
				if(ispath(path, type))
					for(var/n in 1 to dq_latent_spawn_count(generator[path]))
						. += path
			return
	if(!L)
		L = dq_ledger(src)
		if(!L)
			return
	var/id = slot_id || L.default_id
	for(var/atom/movable/thing as anything in L.slots[id])
		if(istype(thing, type))
			. += thing.type
	for(var/datum/latent_entry/entry as anything in L.latent_list(id))
		if(ispath(entry.path, type))
			for(var/n in 1 to entry.count)
				. += entry.path

READS_AS(/atom/proc/slot_kinds, SLOT_OCCUPANCY_KEY)

/// The limit of `slot_id` on this holder, or null when it has none.
/atom/proc/slot_capacity(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	var/datum/relation_definition/slot/def = L?.def_by_id(slot_id || L.default_id)
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

// The destroy transaction's contents phase (L1, doc/rewrite/lifecycle.md Â§2-3)
// replaces what used to live here (ledger_apply_drop_policies(),
// ledger_drop_latent()): see code/datums/containment/lifecycle.dm.
