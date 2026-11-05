// Lazy owned state (the storage contract; owns_one(lazy = TRUE)).
//
// State that only a few instances ever hold is not a var on the base type and not a slot in a text-keyed table: it is the vars of a small state
// datum the holder owns, made when the first instance needs it.
//
//	/datum/burn_state
//		var/fuel = 0
//
//	CAPABILITIES(/obj/item)
//		owns_one(nameof(burn), /datum/burn_state, lazy = TRUE)
//
//	A.burn?.fuel                  read: null while no one ever wrote it, so a read costs a null check and allocates nothing
//	burn_of(A).set_fuel(5)        write: burn_of() is generated (code/engine/_generated/declare.dm); it makes the datum on its first call
//
// The datum is owned (rel_set), so it dies with its holder and needs no collection. Its vars are tracked like any other var: a write publishes the
// var's key on the state datum and a draw, stat or on_change that reads `A.burn?.fuel` follows it through the relation.

GLOBAL_VAR_INIT(lazy_states_made, 0)

/// Makes the lazy state datum `var_name` of `holder` (a `state_type`), owned by it. Called by the generated `x_of()` when the var is still null.
/proc/lazy_state_make(datum/holder, var_name, state_type)
	if(!holder)
		stack_trace("lazy_state_make(): no holder for [var_name]")
		return null
	var/datum/state = new state_type
	if(QDELETED(holder))
		// A write during the holder's teardown: the caller still needs something to write to, and nothing should keep it. The state is not owned by
		// anything, so it is freed when the caller lets go of it.
		log_world("LAZY STATE: [holder.type].[var_name] written while its holder is being deleted; the state is discarded")
		return state
	rel_set(holder, var_name, state)
	GLOB.lazy_states_made++
	BOOT_PHASE_COUNT("lazy state: made on first write")
	return state

/// A tracked var of lazy state S changed (TRACKED_STATE): published on S, and on the holder as a change of the owned var that holds S, so whatever reads
/// through that var (`A.burn?.fuel` in a draw, a stat, an on_change) follows the write. Before this a write to sparse state published nothing at all.
/proc/lazy_state_changed(datum/S, field)
	tracked_changed(S, field)
	var/datum/holder = owner_of(S)
	if(holder)
		tracked_changed(holder, S.own_slot)
		GLOB.lazy_state_published++

GLOBAL_VAR_INIT(lazy_state_published, 0)
