// Shared effect procs for compact interactions (doc/rewrite/interactions.md §5a). Types point
// their specs at these instead of writing the same two-line effect each.

/// Open the target's tgui interface.
/atom/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/// Leave a fingerprint, then open the target's tgui interface.
/atom/proc/interaction_open_ui_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

/// Open the machine's tgui interface, unless it is broken or unpowered (the input is still used).
/obj/machinery/proc/interaction_open_ui_powered(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

/// Leave a fingerprint, then open the machine's tgui interface unless it is broken or unpowered.
/obj/machinery/proc/interaction_open_ui_powered_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return interaction_open_ui_powered(user, held, interaction)

/// Open the target's legacy interact() window.
/atom/proc/interaction_interact(mob/user, obj/item/held, datum/interaction/interaction)
	interact(user)
	return TRUE

/// Take the input and do nothing with it: nothing else handles it, and no afterattack follows.
/atom/proc/interaction_swallow(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/// Take the input and do nothing, but let the item's afterattack follow.
/atom/proc/interaction_pass(mob/user, obj/item/held, datum/interaction/interaction)
	return INTERACTION_HANDLED_PASS

/// Treat the item (or the silicon's Use) as an empty-hand touch.
/atom/proc/interaction_as_touch(mob/user, obj/item/held, datum/interaction/interaction)
	attack_hand(user)
	return TRUE

/// Leave a fingerprint and let the next interaction take the input.
/atom/proc/interaction_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return FALSE

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
