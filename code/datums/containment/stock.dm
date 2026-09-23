// Stock slots (roadmap C9, doc/rewrite/containment.md §4.6).
//
// Vending machines and smartfridges hold their stock as data: one
// /datum/stored_item record per product (type path, latent count, and the
// per-product deltas: price, category, variant, or a shared state blob). A
// real item exists only once it is vended, or while it has state of its own
// that no other copy shares (such items sit in the holder's stock slot and in
// the record's `instances`).
//
// The stock slot is a custom-units slot. Its cost is the thing's units (a
// stack's amount, else 1), and the latent counts count towards its usage. The
// holder's other contents (parts, circuit, coin) stay in an "internals" slot
// whose drop policy leaves them to the machine's own Destroy (C6 owns them).

/// Machine internals: legacy contents the machine's Destroy handles.
/datum/slot_def/machine_internals
	id = CONTAINER_SLOT_INTERNALS
	name = "internals"
	drop_policy = SLOT_DROP_HOLDER
	is_default = TRUE

/// Stock: latent records plus real items with unique state. Spilled on destroy.
/datum/slot_def/stock
	id = CONTAINER_SLOT_STOCK
	name = "stock"
	capacity_model = SLOT_CAPACITY_UNITS
	drop_policy = SLOT_DROP_SPILL

/// Vending stock is deleted with the machine, as it always was: a wrecked
/// vendor does not shower its whole inventory.
/datum/slot_def/stock/vending
	drop_policy = SLOT_DROP_DELETE

/datum/slot_def/stock/capacity_for(atom/holder)
	return INFINITY

/datum/slot_def/stock/cost(atom/holder, atom/movable/thing)
	return dq_stock_units(thing)

/datum/slot_def/stock/latent_used(atom/holder)
	. = 0
	for(var/datum/stored_item/I as anything in holder.stock_records())
		. += I.amount

/datum/slot_def/stock/drop_latent(atom/holder, atom/drop)
	for(var/datum/stored_item/I as anything in holder.stock_records())
		// The ledger applies the policy to the real ones; the record lets go.
		LAZYCLEARLIST(I.instances)
		if(drop_policy == SLOT_DROP_SPILL && drop && !QDELETED(drop))
			I.materialize_all(drop)
		I.amount = 0

/// Units a thing costs in a stock slot.
/proc/dq_stock_units(atom/movable/thing)
	if(istype(thing, /obj/item/stack))
		var/obj/item/stack/S = thing
		return S.get_amount()
	return 1

/// The stock records of a holder, or null.
/atom/proc/stock_records()
	return null

/**
 * The state blob `thing` would collapse into, or null if it must stay real:
 * its state must serialize (state_can_serialize), it has no contents, and it
 * runs nothing (timers, processing).
 */
/proc/dq_stock_blob(atom/movable/thing)
	if(!istype(thing) || QDELETED(thing) || length(thing.contents))
		return null
	if(length(state_running_blockers(thing)))
		return null
	return state_serialize(thing, STATE_FULL)

/// The canonical delta hash of a freshly made `path` with `variant`. Cached.
/proc/dq_stock_pristine_hash(path, variant)
	var/static/list/cache = list()
	var/key = "[path]|[variant]"
	if(key in cache)
		return cache[key]
	var/atom/movable/sample = spawn_with_variant(path, null, variant)
	var/list/blob = dq_stock_blob(sample)
	if(istype(sample) && !QDELETED(sample))
		qdel(sample)
	. = blob ? state_hash(blob) : null
	cache[key] = .
