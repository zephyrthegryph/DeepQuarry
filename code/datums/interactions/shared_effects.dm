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
	if(stat & (BROKEN|NOPOWER))
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

/// A rapid part exchange device swaps the machine's parts.
/obj/machinery/proc/interaction_part_replacement(mob/user, obj/item/held, datum/interaction/interaction)
	return default_part_replacement(user, held) ? TRUE : FALSE
