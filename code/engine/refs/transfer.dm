// The movement layer under move_into() (code/engine/declare/transfer.dm, doc/rewrite/final_api.html sections 6 and 17).
//
// move_into(holder, var, item, actor) takes a movable out of wherever it is and puts it in the holder before the holder
// adopts it. The checks and the move are these helpers:
//   1. own_transfer_refusal(): the item can leave its current place (a mob's hand or equip slot: can_unequip and
//      NODROP; a storage item's or any other ledger slot's removal rules) and it can enter the holder (the holder's
//      ledger slot, when it has slots). A refusal changes nothing;
//   2. own_transfer_land(): the release, the current place lets it go through its own procs, so its bookkeeping runs
//      (a mob's HUD, slot redraw and dropped(); a storage's HUD and on_exit_storage()), and it lands in the holder
//      (in `slot` when given);
//   3. own_release_previous(): another holder's owned var naming it lets it go;
//   4. own_transfer_record(): with an actor, state_changed(holder) and dispatch_record(actor, holder, "insert", log).
//
// The accessors rel_set / rel_add (_own_set / _own_add underneath) never move a thing for a caller, except where
// own_wants_transfer() says the var's own contents are meant: an OWN_CONTAINED var always takes its value into the
// holder (off a turf too), and a value inside something else (a mob, a storage, a machine) is moved in; a value on a
// turf or already inside the holder stays (a beam, a projector's field, a pAI cable). `into = FALSE` (own_transfer /
// own_move re-own in place) never moves.
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

/// The transfer half of _own_set / _own_add / _own_put: TRUE when `value` may be adopted (it is in the
/// holder now, or needs no move), FALSE when refused (and `user` was told why).
/proc/own_bring_in(datum/holder, var_name, datum/value, list/entry, mob/user, into, slot, force)
	if(!own_wants_transfer(holder, var_name, value, entry, user, into, slot))
		return TRUE
	var/atom/movable/thing = value
	if(!force)
		var/reason = own_transfer_refusal(holder, thing, slot, user)
		if(reason)
			transfer_outputs().refusal(user, "[capitalize(reason)].")
			return FALSE
	if(!own_transfer_land(holder, var_name, thing, slot, user, force))
		return FALSE
	own_release_previous(holder, var_name, thing)
	return TRUE

/// The move itself, already checked: the current place lets `thing` go through release_to() and it lands in
/// `dest` (its ledger slot `slot`). FALSE, with `user` told, when it did not land (a bug in a release_to() override).
/proc/own_transfer_land(atom/dest, var_name, atom/movable/thing, slot, mob/user, force)
	var/atom/place = thing.loc
	if(place)
		place.release_to(thing, dest, slot, user, force ? LEDGER_MOVE_FORCED : 0)
	else
		dq_ledger_force_move(thing, dest, force ? LEDGER_MOVE_FORCED : 0, slot)
	if(thing.loc != dest)
		// The checks passed, so a release that didn't land is a bug in a release_to() override.
		stack_trace("own transfer: [thing.type] from [place ? place.type : "nullspace"] didn't reach [dest.type].[var_name]")
		transfer_outputs().refusal(user, "\The [thing] won't go into \the [dest].")
		return FALSE
	if(slot)
		var/datum/ledger/L = dq_ledger(dest)
		var/list/placed = L?.entries[thing]
		if(placed && placed[LEDGER_E_SLOT] != slot)
			dq_ledger_commit(thing, dest, slot)
	return TRUE

/// Another holder's owned var naming `thing` lets it go: it is the new holder's now.
/proc/own_release_previous(datum/holder, var_name, datum/thing)
	var/datum/previous = owner_of(thing)
	if(previous && !(previous == holder && thing.own_slot == var_name))
		var/previous_var = thing.own_slot
		previous.on_owned_release(previous_var, thing)
		own_release_member(previous, previous_var, thing)
		own_unstamp(thing)

/// A user's transfer is a dispatched call: the holder refreshes, is fingerprinted, and the log
/// line is written at `log` (LOG_GAME / LOG_ADMIN / null).
/proc/own_transfer_record(datum/holder, datum/value, mob/user, log)
	state_changed(holder)
	transfer_outputs().record(user, holder, "insert", log, isdatum(value) ? list("item" = "[value.type]") : null)

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

GLOBAL_DATUM(transfer_outputs, /datum/transfer_outputs)
/datum/transfer_outputs
/datum/transfer_outputs/proc/refusal(mob/user, text)
	return UI_REFUSED
/datum/transfer_outputs/proc/record(mob/user, datum/target, action, log, list/details)
	return

/proc/transfer_outputs()
	RETURN_TYPE(/datum/transfer_outputs)
	if(!GLOB.transfer_outputs)
		GLOB.transfer_outputs = new /datum/transfer_outputs
	return GLOB.transfer_outputs
