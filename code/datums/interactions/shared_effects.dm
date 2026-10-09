// Shared effect procs of ops (doc/rewrite/interactions.md §5a): types point their then() at these instead of writing the same two-line effect each.

/// Leave a fingerprint, then open the target's tgui interface.
/atom/proc/interaction_open_ui_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

// ---- The shared effects as op handlers ----
// A converted type's op names one of these in its then() where its legacy interaction named the shared effect above
// (tools/dx/codemods/interact_declare.py, SHARED_OPS): op_<name> does what interaction_<name> did.

/atom/proc/op_open_ui(datum/act/op/A)
	tgui_interact(A.actor)

/atom/proc/op_open_ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	tgui_interact(A.actor)

/obj/machinery/proc/op_open_ui_powered(datum/act/op/A)
	if(!operable())
		return
	tgui_interact(A.actor)

/obj/machinery/proc/op_open_ui_powered_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	op_open_ui_powered(A)

/atom/proc/op_interact(datum/act/op/A)
	interact(A.actor)

/// Takes the input and does nothing with it.
/atom/proc/op_swallow(datum/act/op/A)
	return

/// The item (or the silicon's use) as an empty-hand touch.
/atom/proc/op_as_touch(datum/act/op/A)
	attack_hand(A.actor)

/// A fingerprint, and the next op takes the input.
/atom/proc/op_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_DECLINE

/// A rapid part exchange device swaps the machine's parts; one that swapped nothing lets the next op take the input.
/obj/machinery/proc/op_part_replacement(datum/act/op/A)
	return default_part_replacement(A.actor, A.held) ? OP_OK : OP_DECLINE
