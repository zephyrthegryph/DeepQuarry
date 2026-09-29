// One-call transfers (doc/rewrite/ownership.md §1.3a).
//
// own_set / own_add / own_put on an atom holder, given a movable that is somewhere else, take it
// out of wherever it is and put it in the holder before adopting it:
//
//   own_set(src, "beaker", W, user = user)
//
// replaces `user.drop_item(); W.forceMove(src); own_set(src, "beaker", W)`. In one call:
//   1. the checks: it can leave its current place (a mob's hand or equip slot: can_unequip and
//      NODROP; a storage item's or any other ledger slot's removal rules) and it can enter the
//      holder (the holder's ledger slot, when it has slots). A refusal changes nothing, returns
//      null and, with `user`, tells the user why;
//   2. the release: the current place lets it go through its own procs, so its bookkeeping runs (a
//      mob's HUD, slot redraw and dropped(); a storage's HUD and on_exit_storage()), and it lands in
//      the holder (in `slot` when given);
//   3. the adoption: another holder's owned var naming it lets it go, and the holder adopts it.
//   4. with `user`, the transfer is a dispatched call: changed(holder) and
//      dispatch_record(user, holder, "insert", log).
//
// When the accessor moves a value (own_wants_transfer()):
//   - an OWN_CONTAINED var: always (its values are the holder's own contents), off a turf too;
//   - `into = FALSE`: otherwise never (own_transfer / own_move re-own in place);
//   - the value is already in the holder, or anywhere inside it: no move (with `slot`, a thing
//     already in the holder moves into that slot: a mob's own held item into its body);
//   - `into = TRUE` or a `user`: it moves in, off a turf too;
//   - otherwise it moves in only when it is inside something else (a mob, a storage, a machine):
//     an owned effect or item left on a turf on purpose (a beam, a projector's field, a pAI cable)
//     stays where it is.
//
// Current places answer two procs, overridden where taking a thing out means more than a ledger
// move: /atom/proc/release_refusal() and /atom/proc/release_to() (mobs and storage below).

/// TRUE when adopting `value` into holder.var_name must first move it into the holder.
/proc/own_wants_transfer(datum/holder, var_name, datum/value, list/entry, mob/user, into, slot)
	if(!isatom(holder) || !ismovable(value))
		return FALSE
	var/atom/movable/thing = value
	var/atom/place = thing.loc
	if(place == holder) // already in: moves only between the holder's own slots (a mob's hand to its body)
		if(isnull(slot) || into == FALSE)
			return FALSE
		var/datum/ledger/L = dq_ledger_peek(holder)
		var/list/placed = L?.entries[thing]
		return placed && placed[LEDGER_E_SLOT] != slot
	// CONTAINED means the holder's own contents: the value always moves in, through own_transfer() /
	// own_move() too.
	if(entry && own_policy(holder, var_name, entry) == OWN_CONTAINED)
		return TRUE
	if(into == FALSE)
		return FALSE
	for(var/atom/A = place; A; A = A.loc) // anywhere inside the holder already
		if(A == holder)
			return FALSE
	if(into || user)
		return TRUE
	return !isnull(place) && !isturf(place)

/// Why `thing` can't be moved into `holder` (its slot `slot`, null: the default one), or null.
/// Checks both sides; changes nothing.
/proc/own_transfer_refusal(atom/holder, atom/movable/thing, slot, mob/user)
	if(!ismovable(thing) || QDELETED(thing))
		return "it is gone"
	if(!isatom(holder) || QDELETED(holder))
		return "there is nowhere to put it"
	for(var/atom/A = holder; A; A = A.loc)
		if(A == thing)
			return "it can't go inside itself"
	var/atom/place = thing.loc
	if(place)
		. = place.release_refusal(thing, user)
		if(.)
			return .
	if(dq_slot_defs_for(holder))
		return dq_ledger_refusal(thing, holder, slot, user, check_removal = FALSE)
	return null

/// The transfer half of own_set / own_add / own_put: TRUE when `value` may be adopted (it is in the
/// holder now, or needs no move), FALSE when refused (and `user` was told why).
/proc/own_bring_in(datum/holder, var_name, datum/value, list/entry, mob/user, into, slot, force)
	if(!own_wants_transfer(holder, var_name, value, entry, user, into, slot))
		return TRUE
	var/atom/movable/thing = value
	var/atom/dest = holder
	if(!force)
		var/reason = own_transfer_refusal(dest, thing, slot, user)
		if(reason)
			refuse(user, "[capitalize(reason)].")
			return FALSE
	var/atom/place = thing.loc
	if(place)
		place.release_to(thing, dest, slot, user, force ? LEDGER_MOVE_FORCED : 0)
	else
		dq_ledger_force_move(thing, dest, force ? LEDGER_MOVE_FORCED : 0, slot)
	if(thing.loc != dest)
		// The checks passed, so a release that didn't land is a bug in a release_to() override.
		stack_trace("own transfer: [thing.type] from [place ? place.type : "nullspace"] didn't reach [dest.type].[var_name]")
		refuse(user, "\The [thing] won't go into \the [dest].")
		return FALSE
	if(slot)
		var/datum/ledger/L = dq_ledger(dest)
		var/list/placed = L?.entries[thing]
		if(placed && placed[LEDGER_E_SLOT] != slot)
			dq_ledger_commit(thing, dest, slot)
	// Another holder's owned var naming it lets it go: it is the new holder's now.
	var/datum/previous = owner_of(thing)
	if(previous && !(previous == holder && thing.own_slot == var_name))
		var/previous_var = thing.own_slot
		previous.on_owned_release(previous_var, thing)
		own_release_member(previous, previous_var, thing)
		own_unstamp(thing)
	return TRUE

/// A user's transfer is a dispatched call: the holder refreshes, is fingerprinted, and the log
/// line is written at `log` (LOG_GAME / LOG_ADMIN / null).
/proc/own_transfer_record(datum/holder, datum/value, mob/user, log)
	changed(holder)
	dispatch_record(user, holder, "insert", log, isdatum(value) ? list("item" = "[value.type]") : null)

// ---- current places ----

/// Why `thing` can't leave this atom now (for `user`), or null. Default: the ledger slot's removal
/// rules (a thing in no slot can always leave). Must not sleep or change anything.
/atom/proc/release_refusal(atom/movable/thing, mob/user)
	return dq_ledger_removal_refusal(thing, user)

/// Lets `thing` go into `destination` (its slot `slot`), already checked. Default: the ledger
/// commit (slot bookkeeping, slot events, on_unslotted()); a plain move for a place without slots.
/// Must not sleep: nothing may change between the checks and the commit.
/atom/proc/release_to(atom/movable/thing, atom/destination, slot, mob/user, flags = 0)
	return dq_ledger_force_move(thing, destination, flags, slot)

/// A mob's hands and equipment: the item must be one it can let go of (NODROP, can_unequip).
/mob/release_refusal(atom/movable/thing, mob/user)
	if(isitem(thing))
		var/obj/item/I = thing
		var/id = inventory_slot_id(I)
		if(id)
			if(has_trait(I, TRAIT_NODROP))
				return user == src || !user ? "\the [I] is stuck to you" : "\the [I] is stuck to [src]"
			if(!I.mob_can_unequip(src, id, TRUE))
				return user == src || !user ? "you can't take off \the [I]" : "you can't take \the [I] from [src]"
	return ..()

/// Out of a mob's inventory through remove_from_mob(): the slot clears, the HUD drops the item,
/// the slot redraws and the item's dropped() runs.
/mob/release_to(atom/movable/thing, atom/destination, slot, mob/user, flags = 0)
	if(!isitem(thing))
		return ..()
	remove_from_mob(thing, destination)
	return thing.loc == destination

/// Out of a storage item through storage_exit(), remove_from_storage()'s commit (no stall: nothing
/// sleeps between the checks and the commit): its HUD and on_exit_storage() run.
/obj/item/storage/release_to(atom/movable/thing, atom/destination, slot, mob/user, flags = 0)
	if(!isitem(thing))
		return ..()
	var/obj/item/W = thing
	if(ismob(loc))
		W.dropped(loc)
	return storage_exit(W, destination, user, slot, flags, checked = TRUE)
