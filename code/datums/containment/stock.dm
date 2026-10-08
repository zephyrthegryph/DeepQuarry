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
//
// The latency policy's budgeted sweep (C10, containment.md §4.7) collapses
// through the general ledger's latent_entry API (latent_collapse()/
// latent_add()); stock instances live in /datum/stored_item.instances
// instead, a bespoke collapse of their own (dq_stock_blob(), stock_records())
// that already keeps a vending machine's stock from materializing until
// vended. /obj/machinery now sets latent_contents = TRUE for C6's machine
// internals (CONTAINER_SLOT_INTERNALS is a real latent_entry slot), and
// vending/smartfridge are machinery, so the sweep can't skip them by holder
// any more -- can_be_latent() (latency_policy.dm) excludes CONTAINER_SLOT_STOCK
// by slot id instead, leaving internals eligible. Folding stock onto the same
// latent_entry mechanism, so a vended item with unique state could go through
// one collapse path instead of two, is left for whoever revisits C9; the slot
// exclusion is correct either way, just not unified.

/// Machine internals: legacy contents the machine's Destroy handles.
/datum/om/relation/slot/machine_internals
	// Every concrete machine (or mech) that also declares its own extra slot
	// (an occupant, or stock) is named here too, since it registers its own
	// holder group -- which must still carry internals (containment.md §3).
	holder = list(
		/obj/machinery,
		/obj/machinery/vending,
		/obj/machinery/smartfridge,
		/obj/machinery/cryopod,
		/obj/machinery/recharge_station,
		/obj/machinery/suit_storage_unit,
		/obj/machinery/dna_scannernew,
		/obj/machinery/gibber,
		/obj/machinery/transhuman/resleever,
		/obj/machinery/implantchair,
		/obj/machinery/clonepod,
		/obj/machinery/vr_sleeper,
		/obj/machinery/suit_cycler,
		/obj/mecha,
	)
	slot_id = CONTAINER_SLOT_INTERNALS
	name = "internals"
	drop_policy = SLOT_DROP_HOLDER
	is_default = TRUE

/// Stock: latent records plus real items with unique state. Spilled on destroy.
/datum/om/relation/slot/stock
	holder = /obj/machinery/smartfridge
	slot_id = CONTAINER_SLOT_STOCK
	name = "stock"
	capacity_model = SLOT_CAPACITY_UNITS
	drop_policy = SLOT_DROP_SPILL

/// Vending stock is deleted with the machine, as it always was: a wrecked
/// vendor does not shower its whole inventory.
/datum/om/relation/slot/stock/vending
	holder = /obj/machinery/vending
	drop_policy = SLOT_DROP_DELETE

/datum/om/relation/slot/stock/capacity_for(atom/holder)
	return INFINITY

/datum/om/relation/slot/stock/cost(atom/holder, atom/movable/thing)
	return dq_stock_units(thing)

/datum/om/relation/slot/stock/latent_used(atom/holder)
	. = 0
	for(var/datum/stored_item/I as anything in holder.stock_records())
		. += I.amount

/datum/om/relation/slot/stock/drop_latent(atom/holder, atom/drop)
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
/// The canonical delta hash of a freshly made `path` with `variant`. Cached.
/proc/dq_stock_pristine_hash(path, variant)
	return CACHED2(stock_pristine_hash, path, variant)

DECLARE_SHARED_CACHE(stock_pristine_hash, GLOBAL_PROC_REF(build_stock_pristine_hash), SC_NEVER)

/proc/build_stock_pristine_hash(path, variant)
	var/atom/movable/sample = spawn_with_variant(path, null, variant)
	var/list/blob = dq_stock_blob(sample)
	if(istype(sample) && !QDELETED(sample))
		spent(sample)
	return blob ? state_hash(blob) : null
