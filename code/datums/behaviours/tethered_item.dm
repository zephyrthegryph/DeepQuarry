// A handheld item on a tether to its host item (defib paddles, radio
// handsets, mediguns, proton packs). The tether itself is an edge of
// /datum/om/relation/tethered_to (handheld -> host): host.tethered_handheld()
// and handheld.tether_host() read it, and deleting the host deletes the
// handheld. The host carries /datum/om/behaviour/tether_host (was
// /datum/component/tethered_item) and the handheld /datum/om/behaviour/tether_handheld:
// together they keep the handheld in its host or its wearer's hands.
//
// Set up with make_tethered(host, handheld_path) before . = ..() in Initialize(). The
// helpers are global procs (base-type procs cost a proc-table entry per subtype).

/datum/om/relation/tethered_to
	name = "tether"
	source_single = TRUE
	target_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER

/// The handheld was deleted: a living host remakes it (out of the unlink).
/datum/om/relation/tethered_to/on_unlink(obj/item/handheld, obj/item/host, datum/om/edge/edge)
	if(QDELETED(host) || !host.tether_path)
		return
	om_after(host, 0, GLOBAL_PROC_REF(tether_remake_handheld), host)

/obj/item
	/// Path of the tethered handheld this host makes, or null (not a tether host).
	var/tether_path

/datum/om/behaviour/tether_host
	handles = list(/datum/om/event/before/attack_self, /datum/om/event/before/attackby, /datum/om/event/moved)

/datum/om/behaviour/tether_handheld
	handles = list(/datum/om/event/moved)

/// Makes `host` the host of a tethered `handheld_path`. Call before . = ..() in Initialize().
/proc/make_tethered(obj/item/host, handheld_path)
	host.tether_path = handheld_path
	host.verbs += /obj/item/proc/toggle_tethered_handheld
	host.actions_types += list(/datum/action/item_action/swap_tethered_item)
	om_attach(host, /datum/om/behaviour/tether_host)
	tether_make_handheld(host)

/datum/om/behaviour/tether_host/on_stop(obj/item/host_item)
	host_item.verbs -= /obj/item/proc/toggle_tethered_handheld
	var/obj/item/hand_held = host_item.tethered_handheld()
	host_item.tether_path = null // no remake
	if(hand_held)
		qdel(hand_held)

// !!!! IMPORTANT NOTE !!!!
// The attack_self event is used by ui action hud buttons, as they call attack_self() directly.
// Anything that uses this must intercept attack_hand() and call tether_swap().
// This stops you from removing the item from your backpack slot while trying to take the handheld item out.
// There's no way to block the item pickup code, so it has to be done this way. Unfortunately.
/datum/om/behaviour/tether_host/on_before_attack_self(obj/item/host_item, datum/om/event/before/attack_self/event)
	return tether_swap(host_item, event.user) ? EVENT_VETO : null

// Putting the handset back into our host
/datum/om/behaviour/tether_host/on_before_attackby(obj/item/host_item, datum/om/event/before/attackby/event)
	if(event.item && event.item == host_item.tethered_handheld())
		tether_reattach(host_item)
		return EVENT_VETO

/datum/om/behaviour/tether_host/on_moved(obj/item/host_item, datum/om/event/moved/event)
	tether_check(host_item)

/datum/om/behaviour/tether_handheld/on_moved(obj/item/hand_held, datum/om/event/moved/event)
	var/obj/item/host_item = hand_held.tether_host()
	if(host_item)
		tether_check(host_item)

/// Takes the handheld out into `user`'s hands, or puts it back. TRUE if handled.
/proc/tether_swap(obj/item/host, mob/living/carbon/human/user)
	var/obj/item/hand_held = host.tethered_handheld()
	if(!hand_held)
		return FALSE
	if(hand_held.loc != host)
		tether_reattach(host)
		return TRUE
	//Detach the handset into the user's hands
	if(!tether_slot_check(host))
		if(ismob(host.loc))
			to_chat(user, span_warning("You need to equip \the [host] before taking out \the [hand_held]."))
		return FALSE
	if(!user.put_in_hands(hand_held))
		to_chat(user, span_warning("You need a free hand to hold the \the [hand_held]!"))
		return FALSE
	host.update_icon()
	hand_held.update_icon()
	to_chat(user,span_notice("You remove \the [hand_held] from \the [host]."))
	return TRUE

/// Makes the handheld if there is none.
/proc/tether_make_handheld(obj/item/host)
	if(!host.tether_path || host.tethered_handheld())
		return
	var/obj/item/hand_held = new host.tether_path(host)
	om_link(hand_held, host, /datum/om/relation/tethered_to)
	om_attach(hand_held, /datum/om/behaviour/tether_handheld)

/// om_after() target: remakes a deleted handheld.
/proc/tether_remake_handheld(obj/item/host)
	if(QDELETED(host) || !host.tether_path)
		return
	tether_make_handheld(host)
	host.update_icon()
	var/obj/item/remade = host.tethered_handheld()
	remade?.update_icon()

// Absolutely illegal to be anywhere else except in the slot you were allowed to remove it from
/proc/tether_check(obj/item/host)
	var/obj/item/hand_held = host.tethered_handheld()
	if(!hand_held || hand_held.loc == host) // handheld item is safely inside us
		return
	if(tether_slot_check(host) && hand_held.loc == host.loc) // We are safely worn by our mob, and handheld item is safely inside our mob
		return
	// PANIC
	tether_reattach(host)

/// Retracts the handheld back into its host.
/proc/tether_reattach(obj/item/host)
	var/obj/item/hand_held = host.tethered_handheld()
	if(!hand_held)
		return
	var/mob/handheld_mob = hand_held.loc
	if(istype(handheld_mob))
		to_chat(handheld_mob,span_notice("\The [hand_held] retracts back into \the [host]."))
		handheld_mob.drop_from_inventory(hand_held, host)
	else
		hand_held.forceMove(host)
	host.update_icon()
	hand_held.update_icon()

// By default this expects to be worn on your back
/proc/tether_slot_check(obj/item/host)
	var/mob/M = host.loc
	if(!istype(M))
		return FALSE
	if(HAS_TAG(host, TAG_WEAR_BACK) && M.get_equipped_item(slot_back) == host)
		return TRUE
	if(HAS_TAG(host, TAG_WEAR_BELT) && M.get_equipped_item(slot_belt) == host)
		return TRUE
	if(M.get_equipped_item(slot_s_store) == host) // There is no flag for this, just a whitelist on the suits themselves
		return TRUE
	return FALSE

// Helper verbs
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/obj/item/proc/toggle_tethered_handheld()
	set name = "Remove/Replace Handset"
	set category = "Object"

	// May only remove tethered while in the usr's direct inventory
	if(src.loc != usr)
		return
	tether_swap(src, usr)
