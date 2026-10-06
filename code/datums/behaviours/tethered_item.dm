// A handheld item on a tether to its host item (defib paddles, radio
// handsets, mediguns, proton packs). The tether itself is an edge of
// /datum/om/relation/tethered_to (handheld -> host): host.tethered_handheld()
// and handheld.tether_host() read it, and deleting the host deletes the
// handheld. The host carries /datum/om/behaviour/tether_host (was
// /datum/component/tethered_item) and the handheld /datum/om/behaviour/tether_handheld:
// together they keep the handheld in its host or its wearer's hands.
//
// Set up with host.make_tethered(handheld_path) before . = ..() in Initialize().

/datum/om/relation/tethered_to
	name = "tether"
	source_single = TRUE
	target_single = TRUE
	on_target_delete = OM_END_DELETE_OTHER

/// The handheld was deleted: a living host remakes it (out of the unlink).
/datum/om/relation/tethered_to/on_unlink(obj/item/handheld, obj/item/host, datum/om/edge/edge)
	if(QDELETED(host) || !host.tether_path)
		return
	after(host, 0, TYPE_PROC_REF(/obj/item, tether_remake_handheld))

/obj/item
	/// Path of the tethered handheld this host makes, or null (not a tether host).
	var/tether_path

/datum/om/behaviour/tether_host
	handles = list(/datum/om/event/before/attack_self, /datum/om/event/before/attackby, /datum/om/event/moved)

/datum/om/behaviour/tether_handheld
	handles = list(/datum/om/event/moved)

/// Makes this item the host of a tethered `handheld_path`. Call before . = ..() in Initialize().
/obj/item/proc/make_tethered(handheld_path)
	tether_path = handheld_path
	grant(src, granted_verb(/obj/item/proc/toggle_tethered_handheld), src)
	actions_types += list(/datum/action/item_action/swap_tethered_item)
	om_attach(src, /datum/om/behaviour/tether_host)
	tether_make_handheld()

/datum/om/behaviour/tether_host/on_stop(obj/item/host_item)
	revoke(host_item, granted_verb(/obj/item/proc/toggle_tethered_handheld), host_item)
	var/obj/item/hand_held = host_item.tethered_handheld()
	host_item.tether_path = null // no remake
	if(hand_held)
		spent(hand_held)

// !!!! IMPORTANT NOTE !!!!
// The attack_self event is used by ui action hud buttons, as they call attack_self() directly.
// Anything that uses this must intercept attack_hand() and call tether_swap().
// This stops you from removing the item from your backpack slot while trying to take the handheld item out.
// There's no way to block the item pickup code, so it has to be done this way. Unfortunately.
/datum/om/behaviour/tether_host/on_before_attack_self(obj/item/host_item, datum/om/event/before/attack_self/event)
	return host_item.tether_swap(event.user) ? EVENT_VETO : null

// Putting the handset back into our host
/datum/om/behaviour/tether_host/on_before_attackby(obj/item/host_item, datum/om/event/before/attackby/event)
	if(event.item && event.item == host_item.tethered_handheld())
		host_item.tether_reattach()
		return EVENT_VETO

/datum/om/behaviour/tether_host/on_moved(obj/item/host_item, datum/om/event/moved/event)
	host_item.tether_check()

/datum/om/behaviour/tether_handheld/on_moved(obj/item/hand_held, datum/om/event/moved/event)
	var/obj/item/host_item = hand_held.tether_host()
	host_item?.tether_check()

/// Takes the handheld out into `user`'s hands, or puts it back. TRUE if handled.
/obj/item/proc/tether_swap(mob/living/carbon/human/user)
	var/obj/item/hand_held = tethered_handheld()
	if(!hand_held)
		return FALSE
	if(hand_held.loc != src)
		tether_reattach()
		return TRUE
	//Detach the handset into the user's hands
	if(!tether_slot_check())
		if(ismob(loc))
			to_chat(user, span_warning("You need to equip \the [src] before taking out \the [hand_held]."))
		return FALSE
	if(!user.put_in_hands(hand_held))
		to_chat(user, span_warning("You need a free hand to hold the \the [hand_held]!"))
		return FALSE
	update_icon()
	hand_held.update_icon()
	to_chat(user,span_notice("You remove \the [hand_held] from \the [src]."))
	return TRUE

/// Makes the handheld if there is none.
/obj/item/proc/tether_make_handheld()
	if(!tether_path || tethered_handheld())
		return
	var/obj/item/hand_held = new tether_path(src)
	om_link(hand_held, src, /datum/om/relation/tethered_to)
	om_attach(hand_held, /datum/om/behaviour/tether_handheld)

/// after() target: remakes a deleted handheld.
/obj/item/proc/tether_remake_handheld()
	if(QDELETED(src) || !tether_path)
		return
	tether_make_handheld()
	update_icon()
	var/obj/item/remade = tethered_handheld()
	remade?.update_icon()

// Absolutely illegal to be anywhere else except in the slot you were allowed to remove it from
/obj/item/proc/tether_check()
	var/obj/item/hand_held = tethered_handheld()
	if(!hand_held || hand_held.loc == src) // handheld item is safely inside us
		return
	if(tether_slot_check() && hand_held.loc == loc) // We are safely worn by our mob, and handheld item is safely inside our mob
		return
	// PANIC
	tether_reattach()

/// Retracts the handheld back into this host.
/obj/item/proc/tether_reattach()
	var/obj/item/hand_held = tethered_handheld()
	if(!hand_held)
		return
	var/mob/handheld_mob = hand_held.loc
	if(istype(handheld_mob))
		to_chat(handheld_mob,span_notice("\The [hand_held] retracts back into \the [src]."))
		handheld_mob.drop_from_inventory(hand_held, src)
	else
		hand_held.forceMove(src)
	update_icon()
	hand_held.update_icon()

// By default this expects to be worn on your back
/obj/item/proc/tether_slot_check()
	var/mob/M = loc
	if(!istype(M))
		return FALSE
	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_BACK) == src)
		return TRUE
	if(HAS_TAG(src, TAG_WEAR_BELT) && M.get_equipped_item(SLOT_ID_BELT) == src)
		return TRUE
	if(M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src) // There is no flag for this, just a whitelist on the suits themselves
		return TRUE
	return FALSE

// Helper verbs
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/obj/item/proc/toggle_tethered_handheld()
	set name = "Remove/Replace Handset"
	set category = VERB_CAT_OBJECT

	// May only remove tethered while in the usr's direct inventory
	if(src.loc != usr)
		return
	tether_swap(usr)
