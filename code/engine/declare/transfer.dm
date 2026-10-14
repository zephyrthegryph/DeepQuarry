// The one transfer verb (doc/rewrite/final_api.html sections 6, 9 and 17):
//
//   move_into(holder, slot_id, item, actor = null, ...)
//
// puts `item` into the holder's place `slot_id`, taking it out of wherever it is. One call does:
//   1. the checks, both sides: the item can leave its current place (a mob's hand or equip slot:
//      can_unequip and NODROP; a storage item's or any other ledger slot's removal rules) and it can
//      enter the holder (the holder's ledger slot, its capacity and accepts). The holder's
//      /datum/act/insert hooks run as well, so a requirement written as extend(/datum/act/insert,
//      needs(...)) refuses a transfer like any other insert. A refusal changes nothing, returns FALSE and
//      leaves its reason in GLOB.act_last_reason; with an `actor` the actor is told why;
//   2. the release: the current place lets the item go through its own procs, so its bookkeeping runs (a
//      mob's HUD, slot redraw and dropped(); a storage's HUD and on_exit_storage()), and it lands in
//      the holder (in `ledger_slot` when given);
//   3. the adoption, when `slot_id` names a declared owned var of the holder: another holder's owned var
//      naming the item lets it go, and the holder takes it through the tracked write of the var's declared
//      shape (owns_one: set; owns_many: add; with `key`, put under the key of an associative owns_many).
//      The var is the holder's one-item slot (op_var_slot()); any other `slot_id` is a ledger slot id and
//      the item is only placed there (null: the holder's default slot);
//   4. the record: state_changed(holder), the fingerprint and, with `log`, the log line (dispatch_record()),
//      when an `actor` did it; the insert action's notice goes out.
//
// `force` (an admin undress, a worn item swallowing the one under it) skips the checks and the hooks; the
// release and the bookkeeping still run. Refusals are written to the world log ("MOVE_INTO: ...") so a
// transfer that does nothing can be found.
//
// What a call moves, when `slot_id` is an owned var: the item always moves in, off a turf too, unless it is
// already inside the holder (then it only moves between the holder's own ledger slots when `ledger_slot` names another).
// A var that must adopt an item that stays where it is (a beam, a projector's field, a pAI cable) is written with
// rel_set()/rel_add(): those never move anything.

/// Why `item` can't be moved into `holder`'s place `slot_id` (its ledger slot `ledger_slot`) by `actor`, or null.
/// Checks both sides and changes nothing; the same reason move_into() gives.
/proc/move_into_refusal(datum/holder, slot_id, datum/item, mob/actor = null, ledger_slot = null)
	if(!ismovable(item) || QDELETED(item))
		return "it is gone"
	var/atom/movable/thing = item
	var/is_var = move_into_var_place(holder, slot_id)
	if(!is_var && isatom(holder) && !dq_slot_defs_for(holder))
		return "[holder] can't hold anything"
	if(!is_var && thing.loc == holder) // between the holder's own ledger slots (an equip slot to another): only the slot rules apply
		return dq_ledger_refusal(thing, holder, ledger_slot || slot_id, actor)
	return own_transfer_refusal(holder, thing, is_var ? ledger_slot : (ledger_slot || slot_id), actor)

/// Puts `item` into `holder`'s place `slot_id`: the one transfer. TRUE when it is there now (or already was), FALSE when refused
/// (nothing changed; the reason is in GLOB.act_last_reason and `actor` was told). See the header for the full contract.
/proc/move_into(datum/holder, slot_id, datum/item, mob/actor = null, ledger_slot = null, force = FALSE, log = null, key = null)
	if(!isdatum(holder) || QDELETED(holder) || !isdatum(item))
		GLOB.act_last_reason = "there is nowhere to put it"
		return FALSE
	var/atom/movable/thing = ismovable(item) ? item : null
	var/is_var = move_into_var_place(holder, slot_id)
	var/list/entry = null
	var/shape = MOVE_SHAPE_LEDGER
	if(is_var)
		// No first-write learning: the type declares the var owns_one / owns_many (its shape comes from the declaration).
		var/datum/own_table/own_decls = own_table_of(holder)
		entry = own_decls.entries[slot_id]
		if(!entry || entry[OWNE_KIND] != OWNK_OWN)
			OWN_REPORT("move_into: [holder.type].[slot_id] is not declared owns_one/owns_many")
			GLOB.act_last_reason = "[slot_id] isn't an owned var of [holder.type]"
			return FALSE
		if(!own_guard(holder, item, "move_into([slot_id])") || !own_type_ok(holder, slot_id, entry, item))
			GLOB.act_last_reason = "it doesn't go there"
			return FALSE
		shape = !isnull(key) ? MOVE_SHAPE_KEYED : (entry[OWNE_LIST] ? MOVE_SHAPE_MANY : MOVE_SHAPE_ONE)
		if(shape == MOVE_SHAPE_ONE && holder.vars[slot_id] == item)
			return TRUE // already the var's value: nothing to move or write
	else if(!thing)
		GLOB.act_last_reason = "it can't be moved"
		return FALSE
	var/into_slot = is_var ? ledger_slot : (ledger_slot || slot_id)
	var/moves = is_var ? (!!thing && own_wants_transfer(holder, slot_id, thing, entry, actor, TRUE, ledger_slot)) : TRUE
	// The checks, both sides, and then the insert action's hooks.
	var/reason = null
	var/datum/act/insert/F = null
	var/hook_outcome = ACT_REFUSED
	if(!force)
		if(moves)
			reason = move_into_refusal(holder, slot_id, item, actor, ledger_slot)
		if(!reason && thing && moves)
			GLOB.act_next_actor = actor
			F = ACT_TRY(holder, insert, thing, is_var ? slot_id : into_slot)
			GLOB.act_next_actor = null
			if(isnull(F))
				hook_outcome = GLOB.act_last_outcome // refused or taken over by a hook: put_in() reports the two differently
				reason = GLOB.act_last_reason || "it can't go there"
	if(reason)
		act_cancel(F)
		return move_into_failed(holder, slot_id, item, actor, reason, hook_outcome)
	var/atom/from = thing?.loc
	if(moves)
		var/landed = FALSE
		if(!is_var && from == holder) // already in the holder: the ledger slot changes, nothing is released
			landed = dq_ledger_commit(thing, holder, into_slot)
			if(!landed)
				transfer_feedback_provider().send(actor, holder, thing, "\The [thing] won't go into \the [holder].", raw = TRUE)
		else
			landed = own_transfer_land(holder, slot_id, thing, into_slot, actor, force)
		if(!landed)
			log_world("MOVE_INTO: [item] from [from || "nullspace"] didn't land in [holder] ([slot_id || "default"])")
			act_cancel(F)
			return move_into_failed(holder, slot_id, item, null, "it won't go into [holder]")
		if(is_var)
			own_release_previous(holder, slot_id, thing)
	if(is_var)
		var/adopted = null
		switch(shape)
			if(MOVE_SHAPE_ONE)
				adopted = _own_set(holder, slot_id, item)
			if(MOVE_SHAPE_MANY)
				adopted = _own_add(holder, slot_id, item)
			if(MOVE_SHAPE_KEYED)
				adopted = _own_put(holder, slot_id, key, item)
		if(isnull(adopted))
			log_world("MOVE_INTO: [holder] ([holder.type]) refused to adopt [item] into [slot_id] after the move")
			act_cancel(F)
			return move_into_failed(holder, slot_id, item, null, "[holder] won't take it")
	if(force)
		log_world("MOVE_INTO: FORCED [item] into [holder] ([slot_id || "default"]) by [actor ? key_name(actor) : "the game"]")
	TEST_REC_TRANSFER(item, from, holder, slot_id)
	if(actor)
		own_transfer_record(holder, item, actor, log)
	act_done(F)
	return TRUE

/// Is `slot_id` a var of the holder (an owned one-item or list place), rather than a ledger slot id?
/proc/move_into_var_place(datum/holder, slot_id)
	if(!istext(slot_id) || !(slot_id in holder.vars))
		return FALSE
	return !isatom(holder) || op_var_slot(holder, slot_id)

/// A transfer that did not happen (the caller already cancelled its insert action, whose own reason ours replaces): the reason and outcome
/// are left where put_in() reads them, the world log has the line and `actor` is told why (null: already told). Returns FALSE.
/proc/move_into_failed(datum/holder, slot_id, datum/item, mob/actor, reason, outcome = ACT_REFUSED)
	GLOB.act_last_reason = reason
	GLOB.act_last_outcome = outcome
	var/refusal = "MOVE_INTO: [item] into [holder] ([slot_id || "default"]) refused: [reason]"
	boot_noise_note(refusal)
	log_world(refusal)
	transfer_feedback_provider().send(actor, holder, item, reason)
	return FALSE
